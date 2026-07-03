#!/usr/bin/env python3
# =============================================================================
# Internal DNS sync — one-shot reconciler
# -----------------------------------------------------------------------------
# Publishes ${DOMAIN} -> ${LOCAL_IP} to the LAN's own resolver (an OPNsense box
# running Unbound, or any future router via a new adapter).
#
# Idempotent and safe to re-run on every `docker compose up`. Exits 0 without
# touching anything when INTERNAL_DNS_ADAPTER is unset, so it is inert until
# configured.
#
# Adding a router type = add an Adapter subclass + one ADAPTERS entry. Each
# adapter reads its own env vars (API creds, SSH details, ...). Selected by
# INTERNAL_DNS_ADAPTER. No abstraction beyond that until a third adapter exists.
# =============================================================================
import json
import os
import ssl
import sys
import urllib.error
import urllib.request

# --- Configuration from environment ------------------------------------------

ADAPTER = os.environ.get("INTERNAL_DNS_ADAPTER", "").strip().lower()
DOMAIN = os.environ.get("DOMAIN", "").strip()
LOCAL_IP = os.environ.get("LOCAL_IP", "").strip()
# A record that is no longer desired is removed unless DNS_CLEANUP=false.
CLEANUP = os.environ.get("DNS_CLEANUP", "true").strip().lower() == "true"
# When set, compute and print the full diff but make no write calls. list_managed()
# still runs (it's read-only), so a dry run also confirms the router's API actually
# works — endpoint casing, auth, reachability — without changing anything. Handy
# for the first run against a real router. Set DRY_RUN=1 to enable.
DRY_RUN = os.environ.get("DRY_RUN", "").strip().lower() in ("1", "true", "yes")
# Only records carrying this exact description are ever read, updated, or deleted,
# so hand-made overrides on the router are never touched. An empty/unset value
# falls back to the default rather than matching every blank-description record.
MARKER = os.environ.get("INTERNAL_DNS_MARKER", "").strip() or "managed-by-mediaserver"


def desired_records():
    """fqdn -> ip that should exist on the router.

    Today that is the single ${DOMAIN} -> ${LOCAL_IP} record: nginx serves every
    service by path under one domain, and Plex shares the domain on its own
    port. A dict rather than a bare pair so future names can point at other
    hosts — e.g. the auth.${DOMAIN} -> ${AUTH_IP} record planned in
    SSOAuthSpec.md. Reconcile authoritatively removes any MARKER-tagged record
    not in this dict.
    """
    return {DOMAIN: LOCAL_IP}


# --- Adapter interface -------------------------------------------------------

class Adapter:
    """A router backend. Reconcile only touches records tagged with MARKER.

    Implementations return managed records from list_managed() as dicts with at
    least 'fqdn' and 'ip' keys, plus whatever they need for update()/delete().
    apply() commits the change set to the running resolver and is called at most
    once, only when something actually changed.
    """

    def list_managed(self):
        raise NotImplementedError

    def create(self, fqdn, ip):
        raise NotImplementedError

    def update(self, record, ip):
        raise NotImplementedError

    def delete(self, record):
        raise NotImplementedError

    def apply(self):
        raise NotImplementedError


# --- OPNsense / Unbound adapter ----------------------------------------------

class OPNsenseAdapter(Adapter):
    # OPNsense Unbound host-override endpoints. NOTE: real-world OPNsense uses
    # camelCase action names (matching the opnsense-go client libs), even though
    # the auto-generated API docs render them snake_case. VERIFY these against
    # YOUR firmware version before first run by inspecting the JSON the web UI
    # POSTs in browser devtools — this is the "assume third-party version drift"
    # rule; getting the casing or field names wrong fails opaquely.
    SEARCH = "/api/unbound/settings/searchHostOverride"
    ADD = "/api/unbound/settings/addHostOverride"
    SET = "/api/unbound/settings/setHostOverride/"   # + uuid
    DEL = "/api/unbound/settings/delHostOverride/"   # + uuid
    RECONFIGURE = "/api/unbound/service/reconfigure"

    def __init__(self):
        base = require_env("OPNSENSE_URL").rstrip("/")
        # A bare host ("router.internal") is a valid answer to the setup prompt,
        # but urllib rejects scheme-less URLs; default to https, the OPNsense
        # web UI's own default.
        if "://" not in base:
            base = "https://" + base
        self.base = base
        key = require_env("OPNSENSE_API_KEY")
        secret = require_env("OPNSENSE_API_SECRET")
        import base64
        self.auth = "Basic " + base64.b64encode(
            f"{key}:{secret}".encode()).decode()
        verify = os.environ.get("OPNSENSE_TLS_VERIFY", "false").lower() == "true"
        # Router web UIs commonly serve a self-signed cert, so verification is
        # off by default; set OPNSENSE_TLS_VERIFY=true once a trusted cert is in
        # place. The connection stays on the LAN to the gateway either way.
        self.ctx = None if verify else ssl._create_unverified_context()

    def _api(self, path, body=None):
        data = json.dumps(body).encode() if body is not None else b""
        # OPNsense write endpoints are POST; an empty body still needs POST.
        method = "POST" if body is not None or path.endswith(("/", self.RECONFIGURE)) else "GET"
        req = urllib.request.Request(
            self.base + path, data=data if method == "POST" else None,
            method=method,
            headers={"Authorization": self.auth,
                     "Content-Type": "application/json",
                     "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=15, context=self.ctx) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            raw = e.read().decode(errors="replace")
            die(f"OPNsense API {method} {path} -> HTTP {e.code}: {raw}")
        except urllib.error.URLError as e:
            die(f"OPNsense API {method} {path} unreachable: {e.reason} "
                f"(is OPNSENSE_URL correct and the firewall reachable from this server?)")

    def list_managed(self):
        # searchHostOverride returns {"rows": [...], "rowCount": N, "total": N}.
        resp = self._api(self.SEARCH, {})
        records = []
        for row in resp.get("rows", []):
            if (row.get("description") or "") != MARKER:
                continue   # never touch records we didn't create
            host = row.get("hostname", "")
            dom = row.get("domain", "")
            records.append({
                "uuid": row["uuid"],
                "fqdn": f"{host}.{dom}",
                "ip": row.get("server", ""),
            })
        return records

    def _host_body(self, fqdn, ip):
        # Unbound host overrides store the host label and domain separately.
        # Unlike the office stack (single-label subdomains under a base DOMAIN),
        # this stack's DOMAIN is itself the full FQDN (e.g. myserver.ddns.net),
        # so split on the FIRST dot: hostname=myserver, domain=ddns.net.
        if "." not in fqdn:
            die(f"cannot split {fqdn!r} into host + domain for a host override "
                f"(DOMAIN must be a full FQDN like myserver.ddns.net)")
        host, dom = fqdn.split(".", 1)
        return {"host": {
            "enabled": "1",
            "hostname": host,
            "domain": dom,
            "rr": "A",
            "server": ip,
            "description": MARKER,
        }}

    def create(self, fqdn, ip):
        self._api(self.ADD, self._host_body(fqdn, ip))

    def update(self, record, ip):
        self._api(self.SET + record["uuid"], self._host_body(record["fqdn"], ip))

    def delete(self, record):
        self._api(self.DEL + record["uuid"], {})

    def apply(self):
        self._api(self.RECONFIGURE, {})


ADAPTERS = {
    "opnsense": OPNsenseAdapter,
}


# --- Helpers -----------------------------------------------------------------

def die(msg):
    print(f"ERROR: {msg}", flush=True)
    sys.exit(1)


def require_env(name):
    val = os.environ.get(name, "").strip()
    if not val:
        die(f"{name} must be set for the {ADAPTER!r} adapter")
    return val


# --- Reconcile ---------------------------------------------------------------

def main():
    if not ADAPTER or ADAPTER == "none":
        print("INTERNAL_DNS_ADAPTER not set; skipping internal DNS sync", flush=True)
        return
    if ADAPTER not in ADAPTERS:
        die(f"unknown INTERNAL_DNS_ADAPTER {ADAPTER!r}; "
            f"known adapters: {', '.join(sorted(ADAPTERS))}")
    if not DOMAIN:
        die("DOMAIN must be set")
    if not LOCAL_IP:
        die("LOCAL_IP must be set (the server's LAN IP that the domain should "
            "resolve to on the local network)")

    desired = desired_records()

    print("", flush=True)
    print(f"Syncing internal DNS  adapter={ADAPTER}  domain={DOMAIN}  ip={LOCAL_IP}",
          flush=True)
    if DRY_RUN:
        print("*** DRY RUN - reading state only; nothing will be written ***", flush=True)
    print("-------------------------------------------", flush=True)

    adapter = ADAPTERS[ADAPTER]()
    managed = {r["fqdn"]: r for r in adapter.list_managed()}
    changed = False

    for fqdn, ip in sorted(desired.items()):
        rec = managed.get(fqdn)
        if rec is None:
            print(f"  + Creating  A {fqdn} -> {ip}", flush=True)
            if not DRY_RUN:
                adapter.create(fqdn, ip)
            changed = True
        elif rec["ip"] != ip:
            print(f"  ~ Updating  A {fqdn}  ({rec['ip']} -> {ip})", flush=True)
            if not DRY_RUN:
                adapter.update(rec, ip)
            changed = True
        else:
            print(f"  = Unchanged A {fqdn} -> {ip}", flush=True)

    # Anything WE manage (carries MARKER) that is no longer desired gets removed,
    # unless cleanup is disabled. Records without the marker were never in
    # `managed`, so they are invisible here and can't be touched.
    for fqdn in sorted(managed):
        if fqdn in desired:
            continue
        rec = managed[fqdn]
        if CLEANUP:
            print(f"  - Deleting  A {fqdn} (no longer active)", flush=True)
            if not DRY_RUN:
                adapter.delete(rec)
            changed = True
        else:
            print(f"  . Skipping  A {fqdn} (no longer active, DNS_CLEANUP=false)", flush=True)

    if not changed:
        print("No changes; resolver not reloaded.", flush=True)
    elif DRY_RUN:
        print("[dry-run] would apply the above changes and reload the resolver.", flush=True)
    else:
        print("Applying changes to the resolver...", flush=True)
        adapter.apply()

    print("", flush=True)
    print("Done.", flush=True)


if __name__ == "__main__":
    main()

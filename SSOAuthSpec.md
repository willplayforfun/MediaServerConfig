# Spec: SSO via the LAN Keycloak server

Add the ability to put each web service in this stack behind the **Keycloak** identity provider
running on the office server (`keycloak.mlev.net`, `192.168.10.42`), switchable per-service via
`.env` vars. Each app can keep its own native login (current behaviour, the default), or be
pointed at Keycloak, by changing a few variables and re-running the render step.

`none` everywhere reproduces today's behaviour exactly, so this change is non-breaking when the
new vars are unset.

## Goal

One knob per service controlling how it authenticates:

```
JELLYFIN_AUTH=none|oidc
AUDIOBOOKSHELF_AUTH=none|oidc
NAVIDROME_AUTH=none|header
FILEBROWSER_AUTH=none|header
STASH_AUTH=none|forward
```

…plus broker-level vars (`AUTH_ENABLED`, `AUTH_ISSUER`, OIDC client creds) saying where Keycloak
is and how to reach it.

## The IdP: what we're targeting

The office server (`OfficeServerConfig`) runs Keycloak. Confirmed details:

- **Issuer:** `https://keycloak.mlev.net/realms/officeserver`
- **Discovery:** `…/.well-known/openid-configuration`
- **Signing:** RS256 realm-wide
- **Credentials live in lldap**, federated `READ_ONLY` into Keycloak. A user's password is their
  lldap password; self-service reset at `https://ldap.mlev.net`. **Do not create a second
  credential store.**
- **Certs are real publicly-trusted ACME certs** (Cloudflare DNS-01). No custom CA trust needed —
  plain TLS verification works from this box.

> ⚠️ **Do not target `auth.mlev.net`.** Authentik is not running on the office server; its config
> still lives in that repo but the profile is disabled. Any doc or memory suggesting Authentik is
> stale.

### Things about Keycloak's setup that will bite

- **Access control happens at login, not in the app.** Each gated client gets a per-client copy of
  the `browser` flow with a group check. A user not in `grp-<svc>` gets a 401 "Access denied" and
  the downstream app never sees them. **If login 401s, the user isn't in the group — it is not an
  app misconfiguration.**
- **Brute-force protection is on**: 5 failures → escalating lockout up to 15 min, per account.
  Jellyfin TV clients and Audiobookshelf's background sync retry aggressively on a stale token.
  Expect a "SSO works, then mysteriously stops for 15 minutes" failure during testing.
- **A new lldap user/group is invisible to Keycloak until a sync runs.** No periodic timer; it
  happens on the office server's next `docker compose up`.
- **Redirect URIs are matched strictly** — exact scheme, host, and path.
- **Keycloak's admin API 503s for 60–90s after a cold start.** Do not add a `depends_on` or startup
  health gate against Keycloak from this stack; it's on a box we don't control, and these services
  must start and serve regardless.
- **No `groups` claim by default** — see the oauth2-proxy client below, which needs it.

### DNS — verify this first

`*.mlev.net` LAN records resolve to `192.168.10.42` via the **router's** resolver. This stack runs
its own `dnsmasq` ([docker-compose.yml:412](docker-compose.yml:412)) forwarding to `${DNS1}`/`${DNS2}`,
with an empty [local.conf.tmpl](dnsmasq/local.conf.tmpl).

**If `DNS1` is the router, this works. If it's a public resolver, `keycloak.mlev.net` will resolve
to the public record instead of the LAN IP.** Confirm with a `dig` before building anything — it's
a 30-second check that otherwise costs an hour of confusion.

No dnsmasq changes are otherwise needed. (An earlier draft of this spec called for an
`auth.${DOMAIN}` record and an `AUTH_IP` var; both are unnecessary — Keycloak is already resolvable
and already has valid certs.)

## Background: why there is no single switch

The services fall into three auth categories, and **they cannot all be gated the same way**. This
is the central constraint the implementer must respect:

1. **"Dumb" browser-only web apps** (Stash) — no useful native auth, no native clients. Gate these
   at nginx with **forward-auth** (`auth_request`). Cleanest option.
2. **Apps with native-app/API clients that also support a proxy/header mode** (Navidrome,
   Filebrowser) — these have non-browser clients (Subsonic apps) that authenticate with API
   tokens. A blanket nginx `auth_request` gate **will lock those clients out**. Use the app's own
   reverse-proxy header auth and leave the API paths ungated.
3. **Apps with their own identity model + native TV/mobile apps** (Jellyfin, Audiobookshelf) — must
   use **app-native OIDC**, NOT nginx forward-auth, or the apps break. Jellyfin clients use API
   tokens; a cookie-based proxy gate cannot see them.

> ⚠️ Forward-auth (`auth_request`) only works for browser cookie sessions. Never put it in front of
> a service whose mobile/TV/Subsonic apps you care about. That's why the three categories use three
> different mechanisms.

### Out of scope

- **Plex** — insists on plex.tv accounts, no OIDC.
- **Universal Media Server** — DLNA/UPnP, no meaningful web auth.
- **Kodi** — not a web service.
- **FileFlows** — see the published-ports section below; it is not proxied through nginx at all, so
  there is no nginx layer to gate. Would require either proxying it first (it doesn't support
  subpaths — that's why it's on a direct port today) or a separate vhost. Deliberately excluded.
- **LDAP as a transport** — lldap publishes no host ports, so nothing off the office server can
  bind to it today. Making it reachable needs a change on the office server *and* puts plaintext
  credentials on the LAN wire. Use OIDC.
- **Hosting Keycloak here** — it lives on the office server.
- **Per-user RBAC beyond "authenticated or not"** in this stack. Keycloak's group gate handles
  access; app-level roles stay in each app.

## ⚠️ Published host ports bypass every nginx gate

**This is the most important security caveat in this spec, and it applies to all three categories.**

Most services publish host ports directly:

| Service | Published port | Also proxied at |
|---|---|---|
| Jellyfin | `8096` | `/jellyfin/` |
| Audiobookshelf | `13378` | `/audiobookshelf` |
| Navidrome | `4533` | `/music/` |
| Filebrowser | `8085` | `/files/` |
| FileFlows | `19200` | *(not proxied)* |

Anything gated at nginx — forward-auth *and* header-auth — is **trivially bypassed** by hitting
`http://<host>:<port>` directly from the LAN. The gate is decorative until this is addressed.

For any service switched to `forward` or `header`, the implementer must **either**:

- bind the published port to loopback (`127.0.0.1:8096:8096`), **or**
- drop the `ports:` entry entirely and rely on the nginx route.

Note this breaks any existing bookmark or client configured against the direct port — call it out
in the setup guide. Native-OIDC services (Jellyfin, Audiobookshelf) are *not* affected, because
their auth is enforced inside the app rather than at the proxy; their direct ports can stay.

## Architecture: local oauth2-proxy

Keycloak is a pure OIDC/SAML IdP — **it has no forward-auth endpoint**. (Authentik's embedded
outpost provided one; Keycloak does not.) So forward-auth and header-auth both require an
`oauth2-proxy` sitting between nginx and Keycloak.

The office server runs its own `oauth2-proxy` at `https://oauth.mlev.net`, but using it would
require routing this stack's traffic through the office server's Caddy. **Don't** — that puts media
streaming through a second box's reverse proxy (latency, a bandwidth chokepoint on their NIC, and
this stack goes down when theirs does), and it doesn't compose with the existing nginx subpath
routing.

**Run `oauth2-proxy` locally in this compose stack**, as its own Keycloak client. It talks to
Keycloak over the LAN for the auth handshake only; media bytes never leave this box. This mirrors
the shape the office stack already runs successfully, so it's well-trodden rather than novel.

## The toggle mechanism

The repo renders nginx config through `envsubst`
([nginx-render](docker-compose.yml:28) → [locations.conf.tmpl](nginx-configs/locations.conf.tmpl)).

**Confirmed implementation risk (previously flagged as open):** the renderer
([render-templates.sh](template_rendering/render-templates.sh)) is plain `envsubst` over an
allowlist — **pure substitution, no conditionals**. It cannot conditionally emit per-service auth
blocks as-is.

Two options:

- **(A)** Build the nginx snippet *into an env var* (e.g. `STASH_AUTH_BLOCK` holding the whole
  block or an empty string), assembled in `env-setup.sh`. Zero new tooling; multi-line envsubst
  values do work. But it puts nginx config text inside `.env`, which will age badly.
- **(B) Swap the renderer for `gomplate`.** Both
  [render-templates.sh](template_rendering/render-templates.sh) and
  [the Dockerfile](template_rendering/Dockerfile) already carry comments anticipating exactly this
  ("To swap envsubst for a more capable engine (gomplate, jinja, ...)"). ~1 hour, and it pays off
  for every future conditional.

**Recommend (B).** It was designed for.

Whichever is chosen: new vars must be added to the `VARS` allowlist
([docker-compose.yml:40](docker-compose.yml:40)), and nginx runtime `$variables` must stay out of
that allowlist as they do today.

---

## 📌 NOTE: Keycloak client registration is a change in the *other* repo

**This is a blocking external dependency. Do it first — the wait overlaps with Phase 0/1.**

There is **no dynamic client registration**. Clients are reconciled idempotently on every `up` from
`services/keycloak/realm_config.py` in `OfficeServerConfig`. Someone with access to that repo must:

1. Add a client spec function + a `SERVICES` entry in `services/keycloak/realm_config.py`. The
   `SERVICES` key defaults to a Compose profile name — these services are **externally hosted** and
   have no profile in that stack, so each entry needs an explicit `enabled_check` callable
   (always-true, or keyed on an env var).
2. Add `<SVC>_OIDC_CLIENT_ID` / `<SVC>_OIDC_CLIENT_SECRET` to `example.env` and `prod.env`, a
   generator line in `scripts/generate-local-secrets.sh`, and the vars in
   `services/keycloak/keycloak_vars.jsonc`'s `keycloak-admin-init` contract.
3. Create each `grp-<svc>` in **all** declaring places (no single source of truth):
   `services/lldap/init-groups.py`'s `GROUP_NAMES`, the `realm_config.py` entry, and
   `services/authentik/blueprints/00-groups.yaml` for parity.
4. `docker compose up` on the office server to reconcile.

**Batch the whole request at once** — discovering a missing client mid-phase costs another
round-trip through that repo.

### Clients to request

| Client | Type | Shape | Group(s) | Redirect URIs |
|---|---|---|---|---|
| `jellyfin` | confidential | `gated` | `grp-jellyfin` | `https://${DOMAIN}/jellyfin/sso/OID/redirect/keycloak` + `org.jellyfin.mobile://login-callback` |
| `audiobookshelf` | confidential | `gated` | `grp-audiobookshelf` | `https://${DOMAIN}/audiobookshelf/auth/openid/callback` + mobile app scheme |
| `mediaserver-proxy` | confidential | `open`, **`groups_scope: "groups"`** | `grp-stash`, `grp-navidrome`, `grp-filebrowser` | `https://${DOMAIN}/oauth2/callback` |

Notes on the table:

- **`mediaserver-proxy` is the local oauth2-proxy.** It must be `open` rather than `gated`: a single
  oauth2-proxy instance covers several services, and a per-client login gate can only enforce one
  group. Instead it gets the `groups` claim and gates per-route in nginx via
  `?allowed_groups=grp-<svc>`. This is exactly what the office stack does for its own oauth2-proxy.
  **This is the one place the `groups` scope must be explicitly wired.**
- **Jellyfin's redirect path is subpath-sensitive.** Jellyfin is proxied at `/jellyfin/`
  ([locations.conf.tmpl:29](nginx-configs/locations.conf.tmpl:29)) and `JELLYFIN_PublishedServerUrl`
  is already `https://${DOMAIN}/jellyfin`. The plugin's callback is
  `/sso/OID/redirect/<PROVIDER_NAME>`; `PROVIDER_NAME` must match the name configured in the plugin
  exactly. Confirm the rendered URL against a live login attempt before finalising — a wrong path
  means another round-trip.
- **Audiobookshelf's exact callback and mobile scheme should be verified against the deployed
  version** before sending the request; ABS subpath hosting is not officially supported and this
  stack proxies it at `/audiobookshelf` without a rewrite.

### Escape hatch

A client created by hand in the Keycloak admin UI is **not** clobbered by the next `up` (reconcile
only deletes clients it knows about). Fine for a spike, but it gets no group-gate flow, is invisible
to that repo, and is lost on any realm rebuild. Migrate to the proper path.

---

## Per-service implementation detail

### Forward-auth group — Stash

Stash ([locations.conf.tmpl:109](nginx-configs/locations.conf.tmpl:109)) is the ideal case: single
shared password, browser-only, no API clients.

Add conditionally to the `location` block:

```nginx
# Rendered in only when STASH_AUTH=forward
auth_request /oauth2/auth?allowed_groups=grp-stash;
error_page 401 = @oauth2_signin;
auth_request_set $auth_user $upstream_http_x_auth_request_user;
proxy_set_header X-Forwarded-User $auth_user;
```

Plus shared blocks (always present when `AUTH_ENABLED=true`): a `location /oauth2/` proxying to the
local oauth2-proxy, and the `@oauth2_signin` named location redirecting 401s to `/oauth2/start`.

Remember the published-port caveat above.

### Header-auth group — Navidrome, Filebrowser

**Navidrome has no native OIDC** — verified. Its
[Externalized Authentication](https://www.navidrome.org/docs/usage/integration/authentication/)
docs describe exactly this reverse-proxy-header shape, so it is the intended fit rather than a
workaround. A long-standing feature request
([#858](https://github.com/navidrome/navidrome/issues/858)) exists but is unreleased.

- **Navidrome** ([docker-compose.yml:180](docker-compose.yml:180)):
  ```yaml
  ND_REVERSEPROXYUSERHEADER: X-Forwarded-User
  ND_REVERSEPROXYWHITELIST: 172.16.0.0/12   # docker bridge / nginx source
  ```
  **Whitelisting is mandatory** — without it the header is spoofable from the open LAN. Note that
  Navidrome auto-creates a user with a random password on first proxied login.
  Subsonic apps (DSub, play:Sub, …) keep working via Navidrome's own tokens — gate only the web UI
  and leave the Subsonic API paths ungated. Verify which paths the apps actually hit; `ND_BASEURL`
  is `/music`.
- **Filebrowser** ([docker-compose.yml:254](docker-compose.yml:254)): built-in `proxy` auth method,
  set in [settings.json](filebrowser/settings.json) rather than env (the file is mounted read-only
  and seeded by `init.sh`). Switching auth method changes how accounts are provisioned — document
  that existing local accounts behave differently.

### Native-OIDC group — Jellyfin, Audiobookshelf

No nginx auth changes; keep the current proxy blocks. Configure OIDC inside the app.

- **Audiobookshelf** ([docker-compose.yml:166](docker-compose.yml:166)): native OIDC, configured
  in-app (Settings → Authentication). Cleanest case. No compose change beyond possibly an env var.
- **Jellyfin** ([docker-compose.yml:126](docker-compose.yml:126)): requires the
  [9p4 SSO plugin](https://github.com/9p4/jellyfin-plugin-sso) — add its plugin repo, install,
  configure the provider. This is manual first-run config that compose cannot declare; the setup
  guide must walk through it. **The main testing cost is confirming TV/mobile clients still
  authenticate**, not the browser. The LDAP-plugin alternative is unavailable (lldap is not
  reachable off the office server).

## docker-compose.yml changes

- New `oauth2-proxy` service behind a compose profile, matching the existing optional-service
  pattern. Needs `OAUTH2_PROXY_COOKIE_SECRET`, the client id/secret, and
  `--oidc-issuer-url=https://keycloak.mlev.net/realms/officeserver`. **No `depends_on` against
  Keycloak** (cold-start 503s; different box).
- Conditional env vars in the `navidrome` block (`ND_REVERSEPROXY*`), defaulted so `_AUTH=none`
  injects nothing functional.
- Loopback-bind or remove published ports for any gated service (see the caveat section).
- New vars threaded into [nginx-render](docker-compose.yml:28)'s `VARS` allowlist.

## env-setup.sh / env-lib.sh changes

Add an auth block to [env-setup.sh](env-setup.sh) after service selection:

- Prompt "Enable single sign-on (SSO)?" → if no, all `*_AUTH=none`, skip the rest (preserves the
  current flow exactly).
- If yes: `AUTH_ISSUER` (default `https://keycloak.mlev.net/realms/officeserver`), the oauth2-proxy
  client id/secret, and a generated cookie secret.
- Per enabled service that can do SSO, prompt for its mode, default `none`. **Only offer modes the
  service supports** — don't offer `forward` for Jellyfin.
- Warn when a gated service still publishes a host port.
- Seed all new vars with defaults at the top (matching the existing seed block at
  [env-setup.sh:20](env-setup.sh:20)) so `write_env` always has them.

All new vars go through the existing `write_env` in [env-lib.sh](env-lib.sh) — extend its var list.

## New file: SSOSetupGuide.md

Follow the `*SetupGuide.md` pattern. Cover:

- The three auth categories and which services fall where (set expectations: Plex, UMS, Kodi,
  FileFlows excluded).
- Prerequisite: the client-registration request to the office repo (link to the note above), and
  the fact that users must be added to `grp-<svc>` in lldap **and** a Keycloak sync run.
- The DNS check.
- The published-port bypass and what changed about direct-port access.
- Per-service walkthrough: the Jellyfin plugin, Audiobookshelf's in-app settings, Filebrowser's
  `settings.json`.
- **Testing checklist**, emphasising native-app login for Jellyfin/Audiobookshelf and Subsonic
  clients for Navidrome — the failure mode this whole design exists to avoid. Include the
  brute-force-lockout gotcha.
- Troubleshooting: 401 "Access denied" = missing group, not app misconfig.
- Rollback: set the service's `_AUTH=none`, re-render, restart.

## README.md / SoftwareGuide.md changes

- README: short paragraph noting optional SSO against the LAN Keycloak.
- SoftwareGuide.md: link `SSOSetupGuide.md` in the "Service Setup" list.

## Phasing

| # | Phase | Est. |
|---|---|---|
| 0 | Verify DNS; swap renderer to gomplate | 0.5 d |
| 1 | **Request Keycloak clients from the office repo** (do first; wait overlaps) | 0.25 d |
| 2 | Local `oauth2-proxy` + nginx `/oauth2/` blocks | 0.5 d |
| 3 | Forward-auth: Stash. Proves the toggle end to end. *Highest value / least risk.* | 0.5 d |
| 4 | Header-auth: Navidrome, Filebrowser (API-client whitelisting; fiddly) | 0.5 d |
| 5 | Native OIDC: Audiobookshelf, then Jellyfin (plugin). Testing-heavy. | 1 d |
| 6 | `env-setup.sh` prompts + docs | 0.25 d |

**~3 days of work**, gated on Phase 1 landing in the other repo.

## Open questions

1. **Published ports:** loopback-bind or remove outright for gated services? Loopback-binding keeps
   host-local access for debugging; removing is cleaner. Either way it breaks existing direct-port
   bookmarks — is that acceptable?
2. **Group granularity:** one `grp-mediaserver` for everything, or per-service groups as specced?
   Per-service is more work in the office repo but allows e.g. Stash access to be narrower than
   Jellyfin's. The table above assumes per-service.
3. **FileFlows:** leave ungated (current assumption), or is it worth putting behind its own nginx
   vhost to bring it into the forward-auth group?

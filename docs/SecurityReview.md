# Security review

Static review of this repo's compose files, nginx config, scripts and docs. The server itself was **not** probed: anything marked *verify* needs the output of `sudo bash host/security-audit.sh` (and the scans in "Scanning from outside"). Only finding 1 was reproduced (in a scratch nginx container). No current CVE feeds were consulted; use the `trivy` command at the end for version-specific CVEs.

Threat model: an attacker either (a) comes in from the internet through the forwarded ports, or (b) is already on the LAN (a compromised laptop, phone, IoT device or guest on the same segment), or (c) has code execution inside one container. The goal is to stop each from reaching the host, and to stop a compromised host or container from reaching the router, the office server and the rest of the homelab.

## 1. Attack surface: WAN vs LAN

**WAN** (router forwards 80, 443, 8443, optionally 222; the Operations Guide also lists 22 as public, so verify): nginx on 80/443 and 8443 (Plex), SFTP, maybe SSH. Through nginx, 443 serves **every enabled service**: Jellyfin, Audiobookshelf, Navidrome, Filebrowser, Stash, help site. Plex is on 8443.

**LAN adds** (everything below is published on `0.0.0.0` and bypasses nginx, TLS and any future nginx auth):

| Port | Service | Notes |
|---|---|---|
| 8096, 13378, 4533 | Jellyfin, Audiobookshelf, Navidrome | Same apps as WAN, but plaintext and direct. |
| 8085 | Filebrowser | Admin account seeded with a documented default password (`hellofilebrowser`), root in container, read/write on the share. Also on WAN via `/files/`. |
| 9999 | Stash | Also on WAN via `/stash/`. Auth is optional in Stash; *verify* it is set. |
| 19200 | FileFlows | Not proxied. Runs flows and scripts, mounts the **whole media pool read/write**. Auth is off unless enabled in its settings (*verify*). |
| 8080, 9090, 9777/udp | Kodi | Web UI, JSON-RPC, EventServer. The raw TCP JSON-RPC on 9090 has no password option at all. |
| 9001, 5001, 1044, 1900/udp | Universal Media Server | Host network. DLNA is unauthenticated by design. Admin UI auth is optional. |
| 8090 | Gatus | No auth. Lists every service, its health and the domain. |
| 3000 | WUD | No auth by default. Backed by the Docker socket. |
| 53 | dnsmasq | Open recursive resolver for the whole LAN. |
| 8888, 445, 22, 222 | OMV workbench, SMB, SSH, SFTP | Host services. Docs suggest reusing the same `admin` password everywhere and start from `admin`/`openmediavault`. |

Not published, but reachable by any container: `tv-hub:8099` (unauthenticated launcher API: launch/sleep only).

Other LAN-only exposures:

- Port 80 serves LAN clients over **plain HTTP** (the `geo $needs_https` exception), so logins to every service can be sniffed or ARP-spoofed on the LAN. The Let's Encrypt cert is valid for the domain, and split DNS already points the domain at the server, so LAN clients can use HTTPS.
- Fail2ban ignores `192.168.0.0/16`, so a LAN attacker can brute-force SSH and the web logins without being banned.
- Docker publishes ports through iptables NAT, which **bypasses ufw/INPUT rules**. A host firewall alone does not close any of the ports above; use the `DOCKER-USER` chain or bind to `127.0.0.1`.

## 2. Findings

### High

**1. Plain-HTTP bypass of the HTTPS redirect (reproduced).** `default.conf` puts `if ($needs_https) { return 301 ...; }` inside `location /`, then includes the service `location` blocks *inside* it. A nested location that matches never runs the outer `if`, so an internet client gets `/jellyfin/`, `/audiobookshelf`, `/files/`, `/stash/` and `/help/` over plain HTTP on port 80; only `/` and unmatched paths redirect. Logins and session tokens cross the internet in cleartext. Reproduced on `nginx:alpine` 1.31.2 with a client outside the "LAN" geo range: the service paths returned 200, with the fix below they return 301 and the ACME path is still served. *Fix* (tested):

```nginx
map "$needs_https:$uri" $force_https {
    default                              0;
    "~^1:/\.well-known/acme-challenge/"  0;
    "~^1:"                               1;
}
server {
    listen 80;
    if ($force_https) { return 301 https://$host$request_uri; }   # server level: runs for every location
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { include /etc/nginx/conf.d/locations/*.conf; }    # no `if` here any more
}
```

**2. Three containers hold the Docker socket, which is root on the host.** `certbot-renew` (read-write), `tv-hub` (read-write plus `SYS_ADMIN`) and `wud`. The `:ro` on WUD's mount does **not** make the API read-only; the socket still accepts "create a privileged container mounting `/`". Any code execution in one of these = host root, then everything on the box. See section 3 for the replacement for each.

**3. Admin surfaces with default or no authentication.** Filebrowser's default password is documented and in `env.sh`; FileFlows, Kodi (esp. TCP 9090), WUD, Gatus and possibly Stash and UMS are open to anyone on the LAN. Several of these are code execution by design: FileFlows scripts/flows, Stash scrapers and plugins, Kodi add-ons (via JSON-RPC), Filebrowser write access to the share. Unauthenticated = RCE in the container as root, with media read/write. Stash and Filebrowser are additionally on the WAN.

**4. Flat network, no egress control.** Every container is on one default bridge (Stash/Chrome has its own). Containers can reach each other (e.g. Stash → `filebrowser:80`, `fileflows:5000`, `tv-hub:8099`), the Docker host on the bridge gateway (workbench 8888, SSH, SMB), and the whole LAN through NAT: OPNsense's admin UI, the office server (192.168.10.42) and everything else. A compromised container is a foothold on the LAN.

### Medium

**5. Host-network containers.** `dnsmasq` (host net + `NET_ADMIN`, plus Docker's default `NET_RAW`) can rewrite host routes/iptables and sniff or spoof ARP/DNS for the LAN. `universalmediaserver` (host net, Java, DLNA parser on an unauthenticated port) can reach host-loopback services and scan the LAN as the host. `noip-duc` and `cloudflare-ddns` (host net) hold DNS credentials but listen on nothing, so they are only at risk from image compromise.

**6. TV kiosk browsers run with the sandbox off and raw input.** `tv-youtube`/`tv-home` set `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1`, `tv-jellyfin` sets `QTWEBENGINE_DISABLE_SANDBOX=1`; all run as root with `/dev/input`, `/dev/dri`, `/dev/snd`. They render remote web content (YouTube TV) — the stack's most likely real-world entry point, since a WebKit/Chromium renderer bug becomes full code execution in the container. With `/dev/input` readable, that includes **every keystroke on the host console** (the root login at tty1 included). `tv/data/youtube` holds the Google session cookie.

**7. Credentials with more reach than they need.** The OPNsense API key is only safe if its user has just the Unbound privileges listed in the guide (an API key inherits its user's rights; a key from an admin user is full router control). `OPNSENSE_TLS_VERIFY` defaults to **false**, so anyone who can MITM the LAN can capture the key and secret. The Cloudflare token should be scoped to one zone, DNS edit only. `.env` is mode 600 (good), but any `docker` group member or a compromised socket holder can read every container's environment via `docker inspect`.

**8. No container hardening.** Everything runs as root unless the image drops privileges; no `cap_drop`, `no-new-privileges`, `read_only`, `pids_limit` or memory limits. A container escape needs a kernel bug, but nothing else slows a compromised container down. `/dev/dri` is passed to Jellyfin, Plex, FileFlows, UMS, Kodi and the TV apps: the i915 driver is kernel attack surface for any of them.

**9. Login surfaces on the WAN have no rate limiting or proxy-awareness.** No `limit_req` on any login, no `fail2ban`/CrowdSec on nginx logs. nginx forwards the real client IP in `X-Forwarded-For`, but apps only use it if told which proxy to trust. *Verify*: Jellyfin "Known proxies" and "LAN networks"; Plex "LAN networks" and "Require authentication on local networks" (Plex sees nginx's private address for every client, so it may treat the internet as local); ABS and Navidrome trust-proxy settings. Wrong settings mean WAN clients count as LAN (remote-access and bandwidth rules bypassed) and brute-force lockouts apply to nginx rather than the attacker.

**10. Host and SSH.** Docs use `root` SSH with a key and reuse one `admin` password across OMV, Jellyfin, ABS, etc. (one phished password = all). *Verify* with the audit script: `PermitRootLogin`, `PasswordAuthentication` for both sshd instances (22 and 222), fail2ban jail status, and that IPv6 GUA does not expose 22/445/8888 directly (Docker's NAT does not cover the host's own services).

### Low / hygiene

- **Supply chain.** Tags, not digests; `chromedp/headless-shell:stable` floats; `archlinux:base`, `debian:*` and `python:3.13-alpine` rebuild from whatever is current; `certbot-renew` runs `apk add docker-cli` at every start; `install-omv-extras.sh` pipes `wget` into `bash`; the Jellyfin Desktop `.deb` is downloaded without a checksum.
- **Stash Chrome** browses attacker-influenced pages for scrapers, on a bridge that still NATs to the LAN, with an unauthenticated CDP port (reachable only from Stash). A Chrome bug is a plausible foothold; the network can be made `internal: true` except for the scraper traffic you accept.
- `server_name _` means every service answers on the bare IP and for any `Host`. Harmless alone, but it makes scanners' job easy; add a default server returning 444.
- No security headers (HSTS etc.) on 443.
- SnapRAID parity is not a backup: after a sync, a deleted or encrypted file is gone. There is no offline copy.

## 3. Per-container threat model

"Plausible path" lists the realistic ways in (a bug class, not a specific CVE; none was looked up). "Blast radius" is what the attacker gets **after** compromise, using: **C** container only, **D** media/data (read, write or ransom), **H** host root, **L** LAN pivot.

| Container | Exposure | Plausible path | Blast radius | Hardening |
|---|---|---|---|---|
| **nginx** | WAN 80/443/8443 | Parser/proxy bug; misrouting; a bad location block (finding 1) | Holds TLS key + LE account key (read-only mount). Sees all traffic. Reaches every backend. **D L**, MITM of the domain with a valid cert. Not H. | Pin digest, `cap_drop: ALL` + `NET_BIND_SERVICE`, `no-new-privileges`, `read_only` + tmpfs, fix finding 1, `limit_req`, 444 default server. Reload via an in-container timer so no one needs the socket. |
| **certbot-renew** | None (outbound only) | Compromised image or `apk` package at start; certbot/ACME client bug | **H** (read-write socket), also the TLS key. | Remove the socket: nginx reloads itself every 12 h from an `/docker-entrypoint.d` loop; pin a prebuilt image with docker-cli, or drop the deploy hook. |
| **cert-init** | Port 80 for minutes at first start | Standalone ACME listener | Low; one-shot. | Fine. |
| **wud** | LAN 3000, no auth | Open UI/API on the LAN; WUD or Node bug | **H** via socket; leaks container env. | Put the socket behind `docker-socket-proxy` (containers/images read-only, no POST); bind UI to localhost; enable WUD auth. |
| **gatus** | LAN 8090, no auth | Info disclosure; Go bug | **C**; learns the full service map. | Bind to `127.0.0.1` or put behind nginx LAN-only. |
| **dnsmasq** | LAN 53 (host net, `NET_ADMIN`) | dnsmasq memory-safety bugs (the DNSpooq class); cache poisoning | **L**: root-in-container with host network namespace and `NET_ADMIN`/`NET_RAW`; reroute, sniff, ARP-spoof and DNS-spoof the whole LAN. | `cap_drop: ALL` + `NET_BIND_SERVICE` (test it; DHCP is unused), `read_only`. Better: drop it and let OPNsense Unbound serve the override (already automated by `internal-dns-init`). |
| **noip-duc / cloudflare-ddns** | None (host net, outbound) | Image/supply-chain compromise only | Token theft: **DNS hijack** of the domain. | Cloudflare token scoped to one zone; No-IP DDNS key, not account password; digest-pin; they do not need host net if you set the IP provider explicitly. |
| **internal-dns-init** | None, one-shot | Compromised image; MITM of the unverified TLS call | Steals the OPNsense key (**L**, potentially the router). | Least-privilege OPNsense user; `OPNSENSE_TLS_VERIFY=true`. |
| **jellyfin** | WAN via nginx, LAN 8096 | Unauthenticated/low-privilege bugs in a .NET media server (past classes: arbitrary file read, SSRF, ffmpeg argument injection); malicious media through ffmpeg/image libraries; a malicious plugin if an admin is phished | **C**; users, API tokens, `/config`; media read-only. **L** by pivot. Not H without a kernel/GPU bug. | Non-root `user:`, `cap_drop: ALL`, `read_only` + tmpfs for `/tmp`, bind 8096 to localhost, forbid plugin installs for non-admins, set Known proxies. |
| **plex** | WAN 8443 | Plex PMS bugs; crafted media; the proxy-looks-local issue (finding 9) | **C**; `Preferences.xml` holds the account token (acts as your plex.tv account). Media read-only. | Set LAN networks to your actual subnet and require auth on local networks; non-root via `PLEX_UID/GID`; leave 32400 unpublished (already). |
| **universalmediaserver** | LAN host net 9001/5001/1044/1900 | DLNA/UPnP/HTTP parsing and renderer-config bugs in a Java app; open web UI | Container root with **host network**: reach loopback services on the host, scan and attack the LAN as the host. Media is read-only. **L** | Enable UMS auth; bind to one interface (`UMS_NETWORK_INTERFACE`); consider dropping it or moving to a bridge with `macvlan`/mDNS reflector; `cap_drop: ALL`, no `/dev/dri` if you don't need transcoding. |
| **navidrome** | WAN via nginx, LAN 4533 | Subsonic API/auth bugs; tag/image parsing | **C**, music read-only, user DB. | Non-root, `cap_drop`, `read_only`, bind localhost, trust-proxy setting. |
| **audiobookshelf** | WAN via nginx, LAN 13378 | Auth/IDOR/SSRF/path-traversal bugs (podcast feed fetching is an SSRF source); malicious uploads if upload is enabled | **C**; `/config`, `/metadata`; **audiobooks and podcasts mounted read-write**. SSRF into the LAN. | Egress filter RFC1918; disable uploads for non-admins; non-root. |
| **stash** | WAN via nginx, LAN 9999 | Open or weak auth; plugin/scraper = code execution by design for anyone logged in; Go bugs | **C** as root; `extra/media` read-write; scraper calls reach the LAN; stored API keys. | **LAN-only in nginx**; set a long password; remove the published port; internal network except needed scrapers; `cap_drop`. |
| **stash-chrome** | Only from Stash (CDP, no auth) | Chrome renderer n-day while scraping hostile pages (it floats on `stable`); CDP is a full browser control channel | **C**, then LAN through NAT; can also drive Stash's session data if it lands there. | Pin by digest, `internal: true` network plus an egress proxy, `cap_drop`, `security_opt: no-new-privileges`, fresh container per run if possible. |
| **filebrowser** | WAN via nginx `/files`, LAN 8085, runs as **root** | Default/weak password, then upload/rename/delete; app bugs (past: path/command-execution classes) | **D**: read/write/delete the whole share, **plant files that Jellyfin, Plex, Stash and FileFlows will parse** (the classic chain into a media-parser bug); root in container. | Make the initial password required (no default), change it now, **LAN-only or VPN-only**, drop `user: root`, scope `FILEBROWSER_ROOT` to the smallest folder. |
| **fileflows** | LAN 19200 only, no auth by default | Unauthenticated flow/script editor = RCE as designed; anything on the LAN can reach it | **D**: whole media pool read/write → delete or encrypt everything; `/dev/dri`; LAN pivot. | Enable its auth, bind to `127.0.0.1` and tunnel, mount only the folders it needs, take it down when not processing. |
| **kodi** | LAN 8080/9090/9777 | Open JSON-RPC/EventServer; hostile add-ons (Python, Widevine); Arch rolling image | Root in container; `/dev/input` (keylogging), `/dev/dri`, `/dev/snd`; media read-only; config with add-on tokens; **L**. | Set a web password; do not publish 9090/9777 (or bind to the remote's IP); non-root with `video`/`input` groups. |
| **tv-hub** | Internal 8099 only | Another container POSTing to it; bug in the 130-line HTTP handler | **H**: read-write socket + `SYS_ADMIN` + `/dev/tty1`. | Replace the socket with `docker-socket-proxy` allowing only `containers` + `ALLOW_START/STOP`; a dedicated internal network with only the hub, proxy and `tv-home`. |
| **tv-home / tv-youtube / tv-jellyfin** | Remote web content | WebKit (Cog) / Chromium (Qt) renderer bug via ads, embeds or a hijacked page; sandbox is off | Root in container; **keystrokes from every input device**; Google session cookie (`tv/data/youtube`); LAN pivot; DRM master on the display. | Non-root user in `video`/`audio`/`input`; replace `*_DISABLE_SANDBOX` with a seccomp profile that allows user namespaces for bwrap; egress limited to the internet; `read_only`; keep the images rebuilt often. |
| **render one-shots** | None | Compromised image only | Low; they write only rendered config dirs. | Digest-pin. |

## 4. Remediation order

**Do first (small changes, large effect)**

1. Apply the nginx fix in finding 1.
2. Change the Filebrowser admin password now; remove the default from `filebrowser/env.sh` and `docs/FilebrowserGuide.md` (generate one).
3. Run `host/security-audit.sh`; enable auth on whatever it reports as open (Stash, FileFlows, Kodi web, UMS, WUD).
4. Router: confirm only 80, 443, 8443 (and 222 if used) are forwarded, UPnP is off, and IPv6 inbound is not open to the server.
5. Take Filebrowser, Stash and FileFlows off the WAN. In their nginx locations: `if ($needs_https) { return 403; }` (that variable is the "not on a private range" flag), or better, reach them over a WireGuard tunnel on OPNsense.
6. Bind published ports that nginx already proxies (8096, 13378, 4533, 8085, 9999) to `127.0.0.1`, and publish admin-only ports (8090, 3000, 19200, 8080, 9090) to `127.0.0.1` or remove them. Drop the plain-HTTP LAN exception so LAN clients use HTTPS via the domain.

**Then**

7. Remove or proxy the Docker socket (certbot-renew, tv-hub, wud).
8. Add a compose anchor applied to every service: `cap_drop: [ALL]` (add back only what is needed), `security_opt: [no-new-privileges:true]`, `read_only: true` where it works, `pids_limit`, memory limits, and a non-root `user:` where the image supports it.
9. Segment inside Docker: one network per app plus `nginx` attached to each; `internal: true` for apps that do not need the internet (Filebrowser, FileFlows, Kodi, tv-hub); `DOCKER-USER` rules dropping container → RFC1918 except DNS and the office server's 443.
10. Drop or de-privilege `dnsmasq`; set `OPNSENSE_TLS_VERIFY=true`; give the OPNsense API user only the Unbound privileges; scope the Cloudflare token to one zone.
11. Fix the TV kiosk sandbox (seccomp profile instead of disabling the sandbox), run them non-root.

**Network (the biggest single control for the "attack other homelab surfaces" goal)**

12. Put the server on its own VLAN or DMZ in OPNsense. Allow LAN → server on only the ports clients need (443, 80, 8443, 445 if used, DNS), server → LAN denied except DNS/NTP and (for SSO) the office server's 443. Then even a full host compromise cannot touch the router UI, the office server or other devices. Do not let that VLAN reach OPNsense's management ports.
13. Make fail2ban see LAN failures too (remove `192.168.0.0/16` from `ignoreip` or narrow it to your own admin machine), add CrowdSec or fail2ban for nginx 401/403, and send Gatus alerts.
14. Keep an offline or immutable backup of `docker/` config and irreplaceable media.

## Scanning from outside

LAN (from any other LAN machine; nmap is installed on the dev PC):

```
nmap -sS -sV -p- -T4 <server-ip>
nmap -sU --top-ports 100 <server-ip>
```

WAN (from a network that is **not** yours, e.g. a phone hotspot):

```
nmap -Pn -p 22,53,80,222,443,445,3000,4533,5001,8080,8085,8090,8096,8443,8888,9001,9090,9999,13378,19200 <your-domain>
nmap -6 -Pn -p- <server-ipv6>
curl -i http://<your-domain>/jellyfin/
```

The last line should be a 301 to HTTPS; before the fix in finding 1 it is a 200 or 30x from Jellyfin itself.

Known-CVE scan of every image the stack runs (on the server):

```
for i in $(docker ps --format '{{.Image}}' | sort -u); do docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL --ignore-unfixed "$i"; done
```

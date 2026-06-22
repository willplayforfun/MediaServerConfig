# Spec: Pluggable Identity Provider (SSO) for the stack

Add the ability to put each web service behind an Identity Provider — either a **self-hosted IdP** (Authentik, running on a different box on the home LAN) or an **external IdP** (Google, Okta, Authelia, etc.) — switchable per-service via `.env` vars. Each app can run with its own native login (current behaviour, the default), or be pointed at a shared IdP, by changing a few variables and re-running the render step.

## Goal

One knob per service controlling how it authenticates:

```
JELLYFIN_AUTH=none|oidc
AUDIOBOOKSHELF_AUTH=none|oidc
NAVIDROME_AUTH=none|header
CALIBREWEB_AUTH=none|header
STASH_AUTH=none|forward
FILEBROWSER_AUTH=none|header
```

…plus a small set of broker-level vars (`AUTH_BROKER`, `AUTH_HOST`, OIDC client creds) that say *where* the IdP is and *what kind* it is. `none` everywhere reproduces today's behaviour exactly, so this change is non-breaking when the new vars are unset.

## Background: why there is no single switch

The services in this stack fall into three auth categories, and **they cannot all be gated the same way**. This is the central constraint the implementer must respect:

1. **"Dumb" browser-only web apps** (Stash) — no useful native auth, no native client apps. Gate these at nginx with **forward-auth** (`auth_request`). Cleanest option.
2. **Apps with native-app/API clients that also support a proxy/header or OIDC mode** (Navidrome, Calibre-Web, Filebrowser) — these have non-browser clients (Subsonic apps, OPDS readers) that authenticate with API tokens/basic-auth. A blanket nginx `auth_request` gate **will lock those clients out**. Use the app's own **reverse-proxy header** auth and whitelist the API paths/clients.
3. **Apps with their own identity model + native TV/mobile apps** (Jellyfin, Audiobookshelf) — must use **app-native OIDC**, NOT nginx forward-auth, or the apps break. Jellyfin clients use API tokens; a cookie-based proxy gate cannot see them.

**Plex and Universal Media Server are out of scope.** Plex insists on plex.tv accounts and has no OIDC; UMS is DLNA/UPnP with no meaningful web auth. Neither can participate; the spec must not try.

> ⚠️ Forward-auth (`auth_request`) only works for browser cookie sessions. Never put it in front of a service whose mobile/TV/OPDS/Subsonic apps you care about. That's why the three categories use three different mechanisms.

## Architecture: broker indirection (how external vs self-hosted is switched)

Apps never point at the external IdP directly. They always point at a **local broker**, and the broker's upstream is the switchable part. Two broker options:

- **`AUTH_BROKER=authentik`** — Authentik's embedded outpost (running on the other LAN box) provides the `/outpost.goauthentik.io/auth/nginx` endpoint for forward-auth and acts as the OIDC provider for the native-OIDC apps. To use an **external** IdP, add it to Authentik as a *federation source* — the apps' config never changes. This keeps "switch a few env vars" literally true.
- **`AUTH_BROKER=oauth2-proxy`** — a local `oauth2-proxy` container pointed straight at an external OIDC endpoint, for users who don't want to run Authentik at all. Provides forward-auth only; the native-OIDC apps point at the external IdP directly.

Recommended default and primary target: **`authentik`**. The `oauth2-proxy` path is a documented alternative, implemented only if it doesn't balloon scope (see Phasing — it's Phase 5, optional).

Because the IdP lives on a **different host on the LAN**, two things must resolve to that host:
- nginx's `auth_request` upstream (server-to-server, inside the LAN).
- the OIDC `redirect_uri` / browser-facing IdP URL (client-to-IdP, from the user's browser).

Add an `auth.${DOMAIN}` (or `${AUTH_HOST}`) record to **dnsmasq** — the stack already runs local DNS via the `dnsmasq` service and [dnsmasq-render](docker-compose.yml:44). This is the natural place. The IdP box's LAN IP becomes a new env var (`AUTH_IP`).

## The toggle mechanism (leverages existing render step)

The repo already renders nginx config through `envsubst` ([nginx-render in docker-compose.yml:28](docker-compose.yml:28) → [locations.conf.tmpl](nginx-configs/locations.conf.tmpl)). **This render step is the toggle.** nginx cannot do conditional `include` from an env var directly, but the render container controls exactly what text lands in the rendered config.

Two viable implementation approaches — implementer picks one:

- **(A) Pre-include map / `map` + per-location include of a shared snippet.** Render a small `auth_forward.conf` once; in each gated `location`, emit either the `auth_request /outpost.goauthentik.io/auth/nginx;` line + headers, or nothing, depending on the per-service var. Requires the render step to do conditional emission per service.
- **(B) Switch the renderer from plain `envsubst` to a tiny templating pass** that supports conditionals (e.g. a few `sed`/`awk` guards, or swap the render image's tool). Heavier but cleaner if more conditional blocks are expected later.

Approach **(A)** is preferred — smallest change, stays within the spirit of the current envsubst pipeline. The implementer must check whether the current [template_rendering](template_rendering) image can do conditional emission or whether a minimal helper is needed; flag this as the main implementation-risk item.

Whichever is chosen: the new vars must be added to the `VARS` allowlist passed to the renderer ([docker-compose.yml:40](docker-compose.yml:40)), and nginx runtime `$variables` must stay out of that allowlist as they do today.

## Per-service implementation detail

### Forward-auth group — Stash

Add to each `location` block in [locations.conf.tmpl](nginx-configs/locations.conf.tmpl), conditionally:

```nginx
# Rendered in only when <SERVICE>_AUTH=forward
auth_request /outpost.goauthentik.io/auth/nginx;
error_page 401 = @goauthentik_proxy_signin;
auth_request_set $authentik_username $upstream_http_x_authentik_username;
proxy_set_header X-authentik-username $authentik_username;
```

Plus one shared, always-present (when broker=authentik) location block proxying `/outpost.goauthentik.io/` to the Authentik outpost at `${AUTH_HOST}`, and the `@goauthentik_proxy_signin` named location for the 401 redirect. Follow Authentik's official nginx forward-auth snippet.

- **Stash** ([locations.conf.tmpl:131](nginx-configs/locations.conf.tmpl)): trivial, single-password app, no API clients to worry about.

### Header-auth group — Navidrome, Calibre-Web, Filebrowser

These keep their native auth for API clients and trust a proxy-injected user header for browser traffic. **Whitelisting the proxy source is mandatory** so the header can't be spoofed from the open LAN.

- **Navidrome** ([docker-compose.yml:180](docker-compose.yml:180)): native support via
  ```yaml
  ND_REVERSEPROXYUSERHEADER: X-authentik-username
  ND_REVERSEPROXYWHITELIST: 172.16.0.0/12   # docker bridge / nginx source
  ```
  Subsonic apps (DSub, play:Sub, etc.) keep working via Navidrome's own tokens — do **not** forward-auth `/music/`; gate only the web UI, and leave the Subsonic API paths ungated. Verify which paths the apps hit.
- **Calibre-Web** ([docker-compose.yml:246](docker-compose.yml:246)): has a "Use Reverse Proxy Authentication" setting (configured in-app, plus the trusted header). OPDS feed (`/books/opds`) is consumed by e-reader apps with basic-auth — must stay reachable without the browser gate. This interacts with the existing `X-Script-Name` subpath setup ([locations.conf.tmpl:96](nginx-configs/locations.conf.tmpl)); test both together.
- **Filebrowser** ([docker-compose.yml:266](docker-compose.yml:266)): has a built-in `proxy` auth method (`--auth.method=proxy`, header configurable). Set via its `settings.json` ([filebrowser/settings.json](docker-compose.yml:280)) rather than env. Switching auth method changes how accounts are provisioned — document that existing local accounts behave differently.

### Native-OIDC group — Jellyfin, Audiobookshelf

No nginx changes for auth (keep current proxy blocks). Configure OIDC inside the app and register a client in the IdP.

- **Audiobookshelf** ([docker-compose.yml:166](docker-compose.yml:166)): native OIDC support, configured in-app (Settings → Authentication). Register an OIDC client in Authentik; set redirect URI to `https://${DOMAIN}/audiobookshelf/auth/openid/callback`. App's mobile apps support the SSO flow. No compose change beyond possibly an env var or two if headless config is wanted.
- **Jellyfin** ([docker-compose.yml:126](docker-compose.yml:126)): requires the **9p4 SSO plugin** (`Jellyfin.Plugin.SSO`) — add its plugin repo, install, configure provider. This is manual first-run config, not something compose can fully declare; the setup guide must walk through it. Jellyfin/TV apps log in via Quick Connect or the plugin's flow — **the main testing cost is confirming TV/mobile clients still authenticate**, not the browser.

## docker-compose.yml changes

- New optional broker service(s) behind a compose profile, matching the existing optional-service pattern:
  ```yaml
  # ── Authentik outpost / broker ─────────────────────────────────────────────
  # Only the embedded-outpost endpoint is consumed by nginx; the full Authentik
  # server/db runs on a SEPARATE LAN box (out of scope for this compose file).
  # If running Authentik's server here too is desired, that's a much larger add
  # (postgres + redis + server + worker) — see Open questions.
  ```
  Decision needed: is Authentik **only ever** on the other box (this compose just talks to it over the LAN — no new container here, only nginx + dnsmasq config), or should this stack be able to *host* Authentik too? The spec assumes **the former** (Authentik lives elsewhere; this repo only points at it). The `oauth2-proxy` broker, if implemented, *is* a local container here.
- Conditional env vars added to the `jellyfin`, `audiobookshelf`, `navidrome`, `calibreweb`, `filebrowser` service blocks (the `ND_REVERSEPROXY*` etc. above), defaulted so that `_AUTH=none` injects nothing functional.
- New vars threaded into [nginx-render](docker-compose.yml:28)'s `VARS` allowlist.

## dnsmasq changes

Add an `auth.${DOMAIN}` → `${AUTH_IP}` record to the dnsmasq template ([dnsmasq/templates/local.conf.tmpl](docker-compose.yml:326), rendered by [dnsmasq-render](docker-compose.yml:44)), and add `AUTH_IP` to that render step's `VARS`. Gate it so it's only emitted when an IdP is configured.

## env-setup.sh / env-lib.sh changes

Add an auth-configuration block to [env-setup.sh](env-setup.sh), after service selection ([env-setup.sh:184](env-setup.sh:184)):

- Prompt: "Enable single sign-on (SSO)?" → if no, all `*_AUTH=none`, skip the rest (preserves current flow).
- If yes: pick broker (`authentik` / `oauth2-proxy`), enter `AUTH_HOST` (e.g. `auth.${DOMAIN}`), `AUTH_IP` (IdP box LAN IP), and OIDC client id/secret(s).
- Per enabled service that *can* do SSO, prompt for its mode with the safe default = `none`. Only offer modes the service supports (don't offer `forward` for Jellyfin, etc.).
- Seed all new vars with defaults at the top of the script (matching the existing seed block at [env-setup.sh:20](env-setup.sh:20)) so `write_env` always has them.

All new vars go through the existing `write_env` in [env-lib.sh](env-lib.sh) — extend its var list.

## New file: SSOSetupGuide.md

Follow the `*SetupGuide.md` pattern. Cover:
- The three auth categories and which services fall where (set expectations: Plex/UMS excluded).
- Prerequisite: standing up Authentik on the other box (link to Authentik docs; out of scope to install here), creating the embedded-outpost provider/application, and the OIDC clients.
- The dnsmasq `auth.` record / `AUTH_IP`.
- Per-service walkthrough: registering each app in Authentik (provider type, redirect URIs), the in-app settings for Calibre-Web / Filebrowser / Jellyfin plugin, and the env-var mode for each.
- **Testing checklist**, emphasizing native-app login for Jellyfin/Audiobookshelf and Subsonic/OPDS clients for Navidrome/Calibre-Web — the failure mode this whole design exists to avoid.
- Rollback: set the service's `_AUTH=none`, re-render, restart.

## README.md / SoftwareGuide.md changes

- README: short paragraph noting optional SSO via a pluggable IdP, with the self-hosted-or-external framing.
- SoftwareGuide.md: link `SSOSetupGuide.md` in the "Service Setup" list, and note the `auth.` DNS record alongside the dnsmasq section.

## Phasing (suggested implementation order, ~3 focused days)

1. **Forward-auth for Stash**. Proves the render-toggle mechanism end to end. ~0.5 day. *Highest value / least risk.*
2. **Header-auth: Navidrome, Calibre-Web, Filebrowser** — fiddly because of API-client whitelisting. ~0.5 day.
3. **Native OIDC: Audiobookshelf**, then **Jellyfin** (plugin). ~0.5 day each; testing-heavy.
4. **env-setup.sh prompts + dnsmasq record + docs.** ~0.5 day.
5. **(Optional) `oauth2-proxy` broker path** for external-IdP-without-Authentik. Only if it doesn't expand scope. ~0.5 day.

## Out of scope

- **Plex and Universal Media Server** — no OIDC / not browser-auth; cannot participate.
- **Hosting the Authentik server itself** in this compose stack (postgres + redis + server + worker). Assumed to live on the separate LAN box. Could be a future spec.
- **LDAP** as a transport — OIDC/forward-auth only. (Calibre-Web and Jellyfin both support LDAP, but it's redundant with the OIDC path and doubles the test matrix.)
- **Per-user authorization / RBAC** beyond "authenticated or not" at the nginx layer. App-level roles stay in each app.

## Open questions for you

1. **Authentik location:** confirmed that Authentik (server + DB) runs entirely on the *other* box, and this stack only points nginx/dnsmasq at it — i.e. no Authentik container added here? (Spec assumes yes.)
2. **Default broker:** standardize on `authentik` and treat `oauth2-proxy` as the optional Phase-5 alternative, as written? Or is external-IdP-direct (no Authentik) the primary use case?
3. **Render approach:** OK to extend the existing envsubst render with conditional per-service emission (Approach A), or do you want the renderer swapped for a real templating tool (Approach B) to make future conditionals easier?

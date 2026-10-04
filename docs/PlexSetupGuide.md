# Plex Setup

Enable Plex by selecting it when running `env-setup.sh`, or add `plex` to `COMPOSE_PROFILES` in `.env`.

Access Plex at `https://<server-ip>/plex` - note that initial setup has to come from a computer on the same LAN network, 
unless you specify a claim code via re-running the `env-setup.sh` script on the server (see [SoftwareGuide.md]).

If you do need a claim token, get it from [https://www.plex.tv/claim].

## Initial Setup 

Once the server is running:
- Sign in with your Plex account.
- Add libraries:
    - Movies → /media/movies
    - TV → /media/tv

While adding libraries, it can be good to enable "Prefer local metadata" to ensure consistent experience (assuming you manage your .nfo metadata files).

## Remote Access
- Forward external port 8443 → internal port 8443 (TCP).
- Settings → Network → confirm "Custom server access URLs" includes `https://<your-domain>:8443`.

# Adding Users
Plex users are managed through your Plex account (Plex Home / sharing), not locally. See the [Operations Guide](OperationsGuide.md).

# Connecting with a Client
Sign in to your Plex account in the app and the server appears automatically. To connect manually, use `https://<your-domain>:8443`.

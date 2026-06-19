# Plex Setup

Enable Plex by selecting it when running `env-setup.sh`, or add `plex` to `COMPOSE_PROFILES` in `.env`.

Access Plex at `https://<your-domain>/plex`

## Initial Setup 

Make sure to enter a claim token during initial env setup (see [SoftwareGuide.md]). Once the server is running:
- Sign in with your Plex account.
- Add libraries:
    - Movies → /media/movies
    - TV → /media/tv

## Enable Hardware Transcoding
Settings → Transcoder:
- Enable "Use hardware acceleration when available" (requires Plex Pass)

## Remote Access
- Forward external port 8443 → internal port 8443 (TCP).
- Settings → Network → confirm "Custom server access URLs" includes `https://<your-domain>:8443`.

# Adding Users
Plex users are managed through your Plex account (Plex Home / sharing), not locally. See the [Operations Guide](OperationsGuide.md).

# Connecting with a Client
Sign in to your Plex account in the app and the server appears automatically. To connect manually, use `https://<your-domain>:8443`.

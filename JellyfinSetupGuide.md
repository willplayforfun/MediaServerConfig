# Jellyfin Setup
Access Jellyfin at `https://<your-domain>/jellyfin` once done following the [Software Guide](SoftwareGuide.md).

## Initial Setup Wizard
- Create your admin account
- Add media libraries:
    - Movies: /media/movies (type: Movies)
    - TV: /media/tv (type: Shows)
- Allow remote connections: Yes

## Enable Hardware Transcoding
Dashboard → Playback → Transcoding:
- Hardware acceleration: Video Acceleration API (VA-API)
- VA-API Device: /dev/dri/renderD128
- Enable hardware decoding for: H264, HEVC, MPEG2, VC1
- Enable hardware encoding

## Set the Base URL
Dashboard → Networking:
- Set "Base URL" to `/jellyfin`
- Restart the server (via the OMV admin dashboard)

## Custom CSS (Optional)
Dashboard → General → Custom CSS. Community themes: https://jellyfin.org/docs/general/clients/css-customization/#community-themes

# Adding Users
Each user gets their own watch history, favorites, and continue-watching. See the [Operations Guide](OperationsGuide.md) for how to manage Jellyfin users.

# Connecting with a Client
In the app, set the server URL to `https://<your-domain>/jellyfin`.

# Helpful Software
**Jelly Party** to help synchronize and watch together: https://www.jelly-party.com/
**tinyMediaManager** to help with renaming, metadata, thumbnails: https://www.tinymediamanager.org/
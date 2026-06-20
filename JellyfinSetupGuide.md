# Jellyfin Setup
Access Jellyfin directly at `https://<server-ip>:8096` once done following the [Software Guide](SoftwareGuide.md). Note this requires being on the same LAN network.

## Initial Setup Wizard
- Set server name
- Create your admin account
- Add media libraries:
    - Movies: /media/movies (type: Movies)
    - TV: /media/tv (type: Shows)
- Allow remote connections: Yes

Worth setting these options when creating your libaries:
- Enabled
- Trickplay: Enable trickplay image extraction
- Chapter Images: Enable chapter image extraction

## Set the Base URL
Administration → Dashboard → Networking:
- Set "Base URL" to `/jellyfin`
- Restart the server (via the OMV admin dashboard)
- Jellyfin can now be accessed at `https://<your-domain>/jellyfin`

## Enable Hardware Transcoding
Dashboard → Playback → Transcoding:
- Hardware acceleration: Video Acceleration API (VA-API)
- VA-API Device: /dev/dri/renderD128
- Enable hardware decoding for: H264, HEVC, MPEG2, VC1
- Enable hardware encoding

## Custom CSS (Optional)
Community themes: https://jellyfin.org/docs/general/clients/css-customization/#community-themes

# Adding Users
Each user gets their own watch history, favorites, and continue-watching. See the [Operations Guide](OperationsGuide.md) for how to manage Jellyfin users.

# Connecting with a Client
In the app, set the server URL to `https://<your-domain>/jellyfin`.

# Subtitles
If you have issues with subtitles causing videoplayer crashes, go to User Settings → Subtitles and set "Preferred subtitle mode" to **Only forced** or **None** — this prevents it from using embedded subtitle streams.

# Helpful Software
**Jelly Party** to help synchronize and watch together: https://www.jelly-party.com/
**tinyMediaManager** to help with renaming, metadata, thumbnails: https://www.tinymediamanager.org/
**Bazarr** to automatically download and sync subtitles: see [BazarrSetupGuide.md](BazarrSetupGuide.md)

To permanently strip problem subtitle tracks from a file, `mkvmerge` (from the `mkvtoolnix` package) can remove specific tracks without re-encoding:
```bash
mkvmerge -o output.mkv --subtitle-tracks "" input.mkv
```

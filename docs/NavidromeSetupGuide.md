# Navidrome Setup
Access Navidrome at `https://<your-domain>/music`

## First Login
Create your admin account on first access.

## Adding Music
/srv/mergerfs/media/music/
├── Artist Name/
│   ├── Album Name (Year)/
│   │   ├── 01 - Track Title.flac
│   │   ├── 02 - Track Title.flac
│   │   └── cover.jpg

Navidrome auto-scans every hour (ND_SCANSCHEDULE). You can also trigger a manual scan from the web UI.

# Adding Users
Each user gets their own playlists, favorites, play history. See the [Operations Guide](OperationsGuide.md) for how to manage Navidrome users.

# Connecting with a Client
When setting up Subsonic-compatible clients (Symfonium, DSub, etc.), the server URL is: `https://<your-domain>/music`.

Symfonium is the best Android Subsonic client. It handles sub-path base URLs correctly and supports offline caching.
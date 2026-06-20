# Bazarr Setup
Access Bazarr at `https://<your-domain>/bazarr` once enabled via the [Software Guide](SoftwareGuide.md).

Bazarr automatically downloads subtitles and can fix subtitle timing mismatches. Having clean external subtitle files also sidesteps Jellyfin crashes caused by malformed or unsupported embedded subtitle tracks.

## First-Time Configuration

### 1. Set the Base URL
Settings → General → Base URL: set to `/bazarr`

Restart Bazarr (Settings → General → scroll to bottom → Restart).

### 2. Connect to Jellyfin
This lets Bazarr notify Jellyfin to refresh metadata when a subtitle is added.

First, in the Jellyfin dashboard: Go to API Keys and create a new one.

Settings → Subtitles → Media Servers → Add Jellyfin:

| Field          | Value                                           |
|----------------|-------------------------------------------------|
| Hostname       | `jellyfin`                                      |
| Port           | `8096`                                          |
| API Key        |  Copy from Jellyfin dashboard.                  |
| Base URL       | *(leave blank)*                                 |


### 3. Configure Languages
Settings → Languages:
- Add the language(s) you want.
- Enable "Single Language" if you only want one.

### 4. Add Subtitle Providers
Settings → Providers. The most useful free option:

**OpenSubtitles.com** — register a free account at https://www.opensubtitles.com
- Username / Password: your account credentials
- API Key: get one from your account settings at opensubtitles.com

Other providers (Subscene, Addic7ed, etc.) can also be added.

### 5. Enable Embedded Subtitle Options
Bazarr can detect and extract embedded subtitles - this is a good idea. Settings → Subtitles → Embedded Subtitles:
- Enable "Use Embedded Subtitles"
- Enable "Extract Embedded Subtitles"

### 6. Enable Subtitle Sync (SubSync)
This corrects timing drift so subtitles match the audio without manual adjustment.

Settings → Subtitles → Subtitle Sync:
- Enable: **On**
- Provider: **FFsubsync**
- Trigger sync automatically: Yes


### 7. Scan for Media
Bazarr will import your library and begin checking for missing subtitles:
- Bazarr → Movies → "Scan Disk"
- Bazarr → Series → "Scan Disk"

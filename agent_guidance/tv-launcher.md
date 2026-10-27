# TV launcher

## Goal

The projector shows a smart-TV style launcher, built on the server rather than using a streaming box.

Kodi stays as an alternative "HDMI display app": the `kodi` profile in `kodi/compose.yml`, with `kodi/Dockerfile` and `kodi/reset-config.sh`.
- `env-setup.sh` enables at most one of `tv` or `kodi`, because both drive DRM/KMS directly, and offers to remove the other one's containers.
- Kodi is standalone: it isn't integrated with the hub, and it has no sleep/wake handling.

## Layout (`tv/`, included from the root `docker-compose.yml`)

- **`tv/hub/`** (`tv-hub`, profile `tv`, always running). Stdlib Python, `app.py`. It:
  - serves the launcher page (`launcher.html`, with the tiles injected from `APPS`);
  - switches apps through the Docker socket;
  - reads the remote straight from evdev;
  - handles sleep/wake.
- **`tv/browser/`**: one Cog/WPE image shared by every browser-based app. Each container only sets `APP=<name>`; the entrypoint reads the URL and user agent from `/config/<name>.conf` on every launch.
  - `tv-home` shows the launcher page.
  - `tv-youtube` shows `youtube.com/tv` with a Cobalt user agent; its data is in `tv/data/youtube`.
- **`tv/jellyfin/`** (`tv-jellyfin`): Jellyfin Desktop from upstream's bookworm `.deb` (`JF_VERSION` build arg), on Qt's eglfs/KMS platform rather than Cog. Same `/config/<name>.conf` pattern (`JF_ARGS`); the server address and sign-in persist in `tv/data/jellyfin`. Needs `shm_size` (Chromium) and `QTWEBENGINE_DISABLE_SANDBOX` (runs as root).
- **`tv/apps/`**: the apps' settings (`<name>.conf`, plus `asound.conf.tmpl` for `TV_AUDIO_DEVICE`). `tv-render` (profile `tv`, before the hub starts) renders it into `tv/apps-rendered/` on every `up`, and each app mounts that at `/config`.
  - Rule: app settings go in these mounted files, never in the app's compose `environment:` or its image. The hub only starts existing containers, so anything set at container creation would need the containers recreated to change.
- App containers are in profile `tv-apps`. That profile is never in `COMPOSE_PROFILES`, so a plain `compose up` never starts two at once, but it also never creates or updates them. `env-setup.sh` does that (`tv_post_setup` in `tv/env.sh`), which is why the Operations Guide says to re-run it after every `git pull`. That's only needed for image or compose structure changes (devices, mounts); settings changes don't need it.
  - The create command names the app services, taken from `APPS`. `--profile` replaces `COMPOSE_PROFILES` rather than adding to it, so an unnamed `create` would also recreate any changed core container (nginx, ...) and leave it stopped.
  - Gotcha: `compose down` removes the network but not these containers, so they keep the old network ID and fail to start with `network … not found` (Docker reports it as a 404). The documented update flow (down, pull, env-setup, up) hits this every time, so `tv_post_setup` uses `--force-recreate`. Symptom: blank HDMI, hub logging "start … got 404" in a loop.
- Build speed: each app's `entrypoint.sh` is bind-mounted, not `COPY`'d, so editing one needs only `docker restart <container>`. Images rebuild only for package changes. The Dockerfiles use BuildKit apt cache mounts (and a separate `.deb` download stage for Jellyfin), so even a package change reuses downloaded packages. This needs BuildKit (the default in current Docker).
- Adding an app: add `tv/apps/<name>.conf`, a `tv-apps` service with `APP=<name>` whose `container_name` matches its service name, `name=container` in the hub's `APPS`, and optionally an entry in `APP_META`.

## Behaviour

- **Home key:** a short press returns to the launcher; holding it (≥1.5 s) or pressing `SLEEP_KEY` sleeps the display.
- **Sleep:** stops all app containers, then blanks the console (TIOCLINUX, hence `cap_add: SYS_ADMIN` and `/dev/tty1`). HDMI goes off.
- **Wake:** any key while asleep starts the launcher. Air-mouse motion counts as activity but doesn't wake.
- **Idle sleep:** after `TV_HOME_IDLE_MINUTES` (10) on the launcher, or after `TV_APP_IDLE_MINUTES` (240) in an app if no HDMI audio is playing (checked via the host's `/proc/asound`, bind-mounted).
- **App exits on its own:** the hub returns to the launcher.
- **Boot:** `TV_BOOT_STATE` is `home` (default) or `sleep`. If an app is already running when the hub starts, the hub adopts it.
- **Settings in `.env`:**
  - `REMOTE_DEVICES`: blank means watch every input device.
  - `HOME_KEY`: a name from `KEY_CODES` in `app.py`, or a numeric code.
  - `SLEEP_KEY`
  - `TV_AUDIO_DEVICE`: the ALSA device in the apps' rendered `asound.conf`.

## Unverified on hardware

- Whether Cog/WPE plays YouTube TV smoothly, whether the Cobalt user agent is accepted, and whether the sign-in persists (`--cookie-jar=sqlite`).
- Whether VA-API hardware decode works through the va plugin in `gstreamer1.0-plugins-bad`.
- Whether trixie's Cog 0.18 uses the GLES renderer. Bookworm's 0.16.1 fell back to the software `modeset` renderer (log: "Renderer 'modeset' does not support rotation"), which garbled the YouTube layout.
- Jellyfin Desktop (all of it): that Qt eglfs_kms gets DRM master in the container, that `--tv` is the right flag, whether mpv gets VA-API decode and picks the HDMI ALSA default, and where its `mpv.conf` lives (not yet wired up).
- The hub's console blank ioctl from inside a container, and the `/proc/asound` bind mount.

## Still to build

1. Steam: Moonlight on the server, streaming from Apollo (a Sunshine fork) on the user's Windows PC. It should launch straight into Big Picture, with Wake-on-LAN.

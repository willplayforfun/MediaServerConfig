# Universal Media Server Setup

Enable it by selecting Universal Media Server in `env-setup.sh`, or add `universalmediaserver` to `COMPOSE_PROFILES` in `.env`.

Access the admin UI at `http://<server-ip>:9001`

## First Login
On first access, create a login (or disable authentication). 

## Settings
If you have to tweak anything, first go under Server Settings and enable "Show advanced settings".

# Connecting a Client
- Put the device on the same network as the server.
- Open its DLNA/media browser and select the server from the list of sources.
- If the server doesn't show up despite being on the same LAN/Wi-Fi, see the `network_interface` note above — that's the most common silent cause of DLNA discovery failing under Docker.

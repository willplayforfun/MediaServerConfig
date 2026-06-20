# Universal Media Server Setup

Enable it by selecting Universal Media Server in `env-setup.sh`, or add `universalmediaserver` to `COMPOSE_PROFILES` in `.env`.

Access the admin UI at `http://<server-ip>:9001`

## First Login
On first access, create a login (or disable authentication). 

## Settings
If there are duplicate sources to `root/`, delete all but one of them.

# Connecting a Client
- Put the device on the same network as the server.
- Open its DLNA/media browser and select the server from the list of sources.

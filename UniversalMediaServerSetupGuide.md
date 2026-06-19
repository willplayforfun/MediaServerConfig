# Universal Media Server Setup

Enable it by selecting Universal Media Server in `env-setup.sh`, or add `universalmediaserver` to `COMPOSE_PROFILES` in `.env`.

Access the admin UI at `http://<server-ip>:9001`

## First Login
On first access, create a login (or disable authentication). 

## Network Discovery
DLNA clients find the server over the LAN — there is no URL to enter. If it doesn't appear:
- Settings → General Settings → set the network interface to your LAN interface, then restart the server.
- Confirm the client is on the same subnet (multicast often doesn't cross Wi-Fi/VLAN boundaries).

# Connecting a Client
- Put the device on the same network as the server.
- Open its DLNA/media browser and select the server from the list of sources.

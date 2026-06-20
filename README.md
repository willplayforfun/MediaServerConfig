# This Repository

I am endeavoring to make it dead simple to self-host a media server in my home, and to allow others to do the same.

Services that can be provided on this server include:
- [Jellyfin](https://jellyfin.org/) - video streaming. Replaces Netflix, Hulu, etc. Similar to Plex, but truly free.
- [Plex](https://www.plex.tv/) - video streaming, as an alternative to Jellyfin. Can serve the same movie/TV libraries.
- [Universal Media Server](https://www.universalmediaserver.com/) - a DLNA/UPnP server for devices that discover media over the LAN, such as streaming 360 video to a VR headset.
- [Audiobookshelf](https://www.audiobookshelf.org/) - audiobook and podcast streaming and downloads. Replaces Audible.
- [Navidrome](https://www.navidrome.org/) - music streaming and downloads. Replaces Spotify.
- Help Pages - static HTML guides for your friends and family.

Each service can be turned on or off independently.

Since it uses Nginx to proxy traffic to each service, it can also host static websites with a little additional effort. It can also provide networked storage to other computers on your home network.

The setup uses Docker to contain each service. It is built on [OpenMediaVault](https://www.openmediavault.org/), a Debian Linux distribution designed to host a networked storage server. It uses `mergerfs` to pool together multiple hard drives into a single volume, and then `SnapRAID` to provide security against data loss due to disk failure. [No-IP](https://www.noip.com/) provides DDNS services, while `dnsmasq` allows you to use that domain within your home network.

The server can be made accessible to the wider internet by forwarding two ports from your public IP to your server, and by signing up for a free Dynamic DNS address.

# Getting Started

If you have a machine ready to turn into a home server, follow [this setup guide](SoftwareGuide.md).

If you need to build or refit a machine, follow [this build guide](HardwareGuide.md). 

For details on operating a server after setup, see [this ops guide](OperationsGuide.md).

# Conceptual Overview

[OpenMediaVault](https://www.openmediavault.org/) (OMV) is a Linux distribution which, by default, serves an admin UI (called the "workbench") to allow you to configure it from another computer without needed to navigate a terminal. It also supports plugins which help it to be a flexible media server, such as being a Network Attached Storage (NAS). 

By default, OMV serves the workbench UI on port 80, but doesn't do much else.

There are three separate issues here:
1. How to configure OMV to be an effective media *storage* device, including optionally exposing it to SFTP, SMB, and NFS protocols (network file share).
2. How to allow convenient access to media, such as streaming movies and music.
3. How to access the server outside your home.

## OMV as Network Media Storage

### File Storage
Managing different hard drives and worrying about drive failure is a thing of the past. Using a Redundant Array of Independent Disks (RAID) you can survive one or more drive failures without data loss. Creating a merged file system out of those disks allows you to shove files in without worrying about filling up individual drives. Run out of space? Shove in more disks!

#### SnapRAID
This implements a RAID architecture by taking regular snapshots and updating a "parity disk". There are other options for a RAID; this was chosen for its simplicity and flexibility. However, a disk failure may lose changes that have happened since the last snapshot. Snapshot interval can be configured, though nightly is typical.

#### MergerFS
This takes multiple filesystems across the disks and merges them into a single filesystem.

### Network Access
How do you access the file system on the server? There are two primary methods:

#### SFTP
This is the fastest way to do file transfer over a network if you are just uploading or downloading files. Requires a client like [WinSCP](https://winscp.net/eng/download.php). Great for uploading videos and audio to the server.

#### NFS/SMB
This allows the folders on the server to appear as regular folders in your computer's file browser. Great if you want other programs to be able to read/write files to your network storage, or have a shared folder across all your computers at home.

Note: SMB has wider compatibility, and works with Windows. NFS is for Linux/Mac.

## Streaming Services

If you just want a place to upload and share files, or a simple NAS solution, you can skip this section. However, if you want to be able to stream your music, audiobooks, movies, and TV shows, we need to run additional software on the server.

Jellyfin, Navidrome, and Audiobookshelf combine to provide most of the features we expect out of video streaming, music streaming, and audiobook/podcast streaming nowadays.

These are run using [Docker](https://www.docker.com/), which allows each service to be operated independently of the others.

### Nginx
Each service is accessed on a different port. That means the Jellyfin UI is accessed with `http://my_server_ip:8096`, while Audiobookshelf is accessed with `http://my_server_ip:13378`. This is hard to remember and confusing; it would be great to use regular URLs like `http://my_server_ip/jellyfin` and `http://my_server_ip/audiobookshelf`. [Nginx](https://nginx.org/) is the software that allows that.

Nginx routes different URL paths to different locations - in our case, to the different Docker containers running our services.

## Accessing from Anywhere
At this point, the server is completely usable, as long as you are connected to your own network (Wifi or Ethernet). However, there are two problems to overcome if you want to use it from anywhere on the internet:
1. Your home router doesn't know to send HTTP/HTTPS packets to the server.
2. You would have to know and remember your public IP address to connect.  

### Forwarding Ports
Your internet-facing router needs to send incoming HTTP requests to the server. This is requires "forwarding" ports 80 (HTTP) and 443 (HTTPS) to your server's local IP address (which is assigned to the server by the router). It helps to disable DHCP for the server, which can reassign the internal IP and screw up your configuration.

### Dynamic DNS
While you could connect by typing in the IP address assigned by your internet service provider, it is more convenient to use a Dynamic DNS service like [No-IP](https://www.noip.com/), which allows your server to ping the DDNS service and update the target of a reserved domain name. Then you just need to remember/share that domain name.

### Security
For security purposes, I recommend not exposing the admin UIs (OMV's workbench and Nginx Proxy Manager) to the internet. Although they are secured by a username and password, the risk is very high if that ever gets compromised.

### Local DNS
Once you are used to accessing your server by typing in a domain, it is convenient to have that work on your home network. However, some routers don't support "hairpin NATs", which just means that it can't send outgoing packets to itself. The solution is to take the router out of the equation - host a local DNS server (using [dnsmasq](https://thekelleys.org.uk/dnsmasq/doc.html)) that can reroute your domain name to the server's internal network IP, rather than your public IP.

# Repository Notes

## What Goes in the Repo
- docker-compose.yml
- Nginx config files (e.g., helpsite default.conf)
- Help page HTML/CSS
- Any custom scripts (backup scripts, cron jobs, etc.)
- Documentation

## What Does NOT Go in the Repo
- Media files
- Docker persistent data (databases, caches, generated thumbnails)
- Secrets (passwords, API keys) – use a .env file excluded via .gitignore


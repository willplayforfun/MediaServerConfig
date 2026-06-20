# Managing Users

You only need to add a new system user if you want to grant SFTP/SMB access. Otherwise, each service (Jellyfin, Audiobookshelf, etc.) manage their own user list.

## Creating a new system user
- Have them do ssh-keygen locally
    - (they may need to convert the private key to `.ppk` with PuttyGen if using WinSCP)
    - Have them send you their public key
- Create new user in OMV workbench
- Set "Shell" to `/usr/sbin/nologin`
- Add them to the groups `users` and `sftp-access`
- Add public key in user config

You can also do the keygen for them - since it is just for shared SFTP access, there are no real security concerns. 

If they lose their key file, you can simply generate a new keypair and replace the public key in the user config with a new one.

## Creating a new Jellyfin user
While logged in as Jellyfin admin:
- Dashboard → Users → Add User
- Optionally restrict library access per user
- Optionally set per-user transcoding limits, download permissions, parental controls

### Resetting Passwords
TODO: script to fetch PIN for jellyfin password reset

## Creating a new Audiobookshelf user
While logged in as Audiobookshelf admin:
- Settings → Users → Add User
- Optionally restrict library access per user
- Optionally can enable upload permissions per user

### Resetting Passwords
TODO: script to reset audiobookshelf password

## Creating a new Navidrome user
While logged in with an admin account:
- Settings → Users → Add User
- Users can be admin or regular

## Creating a new Plex user
Plex accounts are managed through your Plex account rather than locally:
- Plex Web → Settings → Users & Sharing → invite by email (Plex Home / Managed Users)
- Shared users get access to the libraries you grant them


# Uploading Media

The best way is to connect via SFTP on port 222. This allows mass transfer of files to the proper directories at high speed. Use an SFTP client like WinSCP. Make sure to add your private key under the authentication settings.

## Managing Metadata

I highly recommend using [tinyMediaManager](https://www.tinymediamanager.org/) (or a similar program) to create `.nfo` files, download thumbnails, and rename your video files to use a consistent naming scheme. This ensures that the information displayed in Jellyfin is correct, even for obscure movies and TV. Without this step, Jellyfin will try to infer the metadata based on the filename, but this can be messy.

# Ports

If you are curious which ports are relevant:

## Public

### OpenMediaVault (OMV)
- 22 - SSH (key only auth)
- 222 - SFTP (key only auth)

### Nginx
- 80 - HTTP, Let's Encrypt ACME challenges + redirect to HTTPS
- 443 - HTTPS, all web traffic (proxy + help site)

### Plex
- 8443 - HTTPS. Configurable via `PLEX_HTTPS_PORT`.

## Internal Network Only

### OpenMediaVault (OMV)
- 445 - SMB
- 8888 - Workbench (admin web ui)

### Jellyfin
- 8096 - webui (routed to by Nginx)

### Universal Media Server
- 9001 - admin web UI
- 1044, 5001 - DLNA/UPnP services (plus SSDP multicast discovery; LAN only)

### Audiobookshelf
- 13378 - webui (routed to by Nginx)
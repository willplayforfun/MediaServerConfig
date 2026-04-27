# Managing Users

You only need to add a new system user if you want to grant SFTP/SMB access. Otherwise, each service (Jellyfin, Audiobookshelf, etc.) manage their own user list.

## Creating a new system user
- Have them do ssh-keygen locally
    - (they may need to convert the private key to `.ppk` with PuttyGen if using WinSCP)
    - Have them send you their public key
- Create new user in OMV workbench
- Add them to the groups `users` and `sftp-access`
- Add public key in user config

You can also do the keygen for them - since it is just for shared SFTP access, there are no real security concerns. 

If they lose their key file, you can simply generate a new keypair and replace the public key in the user config with a new one.

# Uploading Media

The best way is to connect via SFTP on port 222. This allows mass transfer of files to the proper directories at high speed. Use an SFTP client like WinSCP. Make sure to add your private key under the authentication settings.

## Managing Metadata

I highly recommend using [tinyMediaManager](URL TODO) (or a similar program) to create `.nfo` files, download thumbnails, and rename your video files to use a consistent naming scheme. This ensures that the information displayed in Jellyfin is correct, even for obscure movies and TV. Without this step, Jellyfin will try to infer the metadata based on the filename, but this can be messy.

# Ports

If you are curious which ports are relevant:

## OpenMediaVault (OMV)
- 22 - SSH (key only auth)
- 222 - SFTP (key only auth)

### Internal Network Only
- 445 - SMB
- 8888 - Workbench (admin web ui)

## Nginx
- 80 - HTTP, Let's Encrypt ACME challenges + redirect to HTTPS
- 443 - HTTPS, all web traffic (proxy + help site)

## Jellyfin
- 8096 - webui (routed to by Nginx)

## Audiobookshelf
- 13378 - webui (routed to by Nginx)
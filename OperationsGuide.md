
# New Users

## Creating a new user
1. Have them do ssh-keygen
2. Create new user in OMV workbench
3. Add to `users` and `sftp-access`
4. Add public key in user config

## How they connect:
- port 222
- use private key file (need to convert to ppk with PuttyGen if using WinSCP)


# Ports:

## OMV
- 22 - SSH (key only auth)
- 222 - SFTP (key only auth)
### Internal Network Only
- 445 - SMB
- 8888 - Workbench (admin web ui)
- 3670 - File browser plugin

## Nginx
- 80 - HTTP, Internal network connections, Let's Encrypt
- 443 - HTTPS, External internet connections
### Internal Network Only
- 81 - Nginx Proxy Manager web ui

## Help Pages
- 8080 - server (nginx)

## Jellyfin
- 8096 - webui

## Audiobookshelf
- 13378 - webui
Read through these instructions line by line. Each is important.

# Prerequisites
- No-IP DDNS
    - Create an account, claim a domain.
    - Generate a DDNS Key. Write down the username and password for later.
        - TODO: how?
- Router admin access for port forwarding
- Flash drive (2 GB should be enough)
- [Server hardware](HardwareGuide.md) with an SSD for the OS and at least 1 drive for your data.
    - I recommend starting with just the SSD connected to the motherboard, to avoid confusion.
- Keyboard and monitor hooked up to server


# OpenMediaVault Installation
- Download the latest OMV ISO from https://www.openmediavault.org/download.html
- Flash the ISO to a USB drive using [Rufus](https://rufus.ie/en/).
- Plug your server into your Ethernet LAN network.
- Boot your server from the USB drive.
- Follow the Debian installer. Key screens:
	- Hostname: e.g., `myserver` - NOTE: this name will show up e.g. on your network shared folder and your "connected devices" list on your router config page
    - Domain name (unimportant, use default: `lan`)
	- Root password: choose something strong and save it - I wrote mine on a sticky note and stuck it to the server
    - You can ignore any warnings about BIOS and UEFI mode while partitioning.
	- Install destination: select your OS SSD – NOT your data HDDs.
- Once installation completes, remove the USB drive and reboot.
- If you left your data drives disconnected, now is the time to reconnect them (while the server is off!).
- After reboot, log in at the console using the login name `root` and the root password you set (remember that the password will not display as you type it in). 
- Run `ip addr` to find your server's IP on your local network. It will be something like `192.168.1.XXX`, under an entry that looks like `eth0` or `enp1s0`. Write it down for later use, anywhere you see `<server-ip>` in these guides.

# Initial OMV Setup
Access the OMV web UI at `http://<server-ip>` in your browser. Default login:
- Username: `admin` 
- Password: `openmediavault`

## First Steps
- Change the admin password: "User Settings" (person icon in top bar) → "Change Password"
	- I recommend saving this password in a password manager, like LastPass.
	- I recommend re-using this `admin` username and password across all the admin accounts we set up, to make it easier to log in. 
- Update the system: "System" → "Update Management" → "Check for updates" → "Install all".
- Enable SSH: "Services" → "SSH" → "Enable"
	- I recommend generating a keypair and using that to authenticate for SSH and SFTP, rather than using a password. It is more secure and more convenient. See ["Generating SSH Keypair" section below](#Generating-SSH-Keypair).
	- It is generally recommended to disable password-based login before exposing your server to the internet. See ["Disabling Password Login" section below](#Disabling-Password-Login).
- Set the Port in "System" → "Workbench" → "Settings" to `8888`. Going forwards, the OMV web UI is accessed at `http://<server-ip>:8888`
    - Setting the automatic logout to 1 day or Disabled is helpful
- Set "System" → "Power Management" → "Settings" → "CPU frequency scaling" to `powersave` or `Disabled`.

### Generating SSH Keypair
On Windows, you can use the command prompt:
```
ssh-keygen -t ed25519 -C "MediaServer Root Key"
```
It will ask you for a filename, you can enter something like `.ssh/mediaserver-root-key` to avoid having it use the default name of `id_ed25519`, which is helpful for keeping track of it in the future.

The private key is saved as a file with no extension, while the public key has `.pub`. Windows SSH will look for keys in the `.ssh` folder under your User folder, so having `.ssh/` in the above name is helpful.

To add the key to the server for SSH, run the following. Replacing with `<key-name>` with the full string you entered, e.g. `.ssh/mediaserver-root-key`. Replace <server-ip> with your server's IP:
```
type %USERPROFILE%\<key-name>.pub | ssh root@<server-ip> "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" 
```
Finally, make sure this checkbox is checked in the OMV web UI: "Services" → "SSH" → "Public key authentication".

I like to save my keys in cloud storage so I can SSH from anywhere and never lose it.

### Using SSH Keypair
On Windows, if doing SSH in the terminal, use the key via:
```
ssh -i "~/<key-name>" root@<server-ip>
```

If using PuTTY:
- First user PuTTYgen to convert the private key file to a `.ppk` via "Conversions" → "Import key".
- Set username to `root` under "Connections" → "Data" → "Auto-login username".
- Link to *private* key file under  "Connections" → "SSH" → "Auth" → "Credentials" → "Private key file for authentication"

### Disabling Password Login
Only do this after setting a keypair for SSH. In the OMV web UI, disable this checkbox: Services → SSH → Password authentication.

# OMV Extras Setup

The next steps can either be accomplished via SSH or direct keyboard-and-monitor terminal, if you are comfortable using SSH, it can be easier for the terminal steps (i.e. via `ssh root@<server-ip>`). If using an SSH key, see the ["Using SSH Keypair" section above](#Using-SSH-Keypair).

### Clone the Repository

Either with a keyboard connected to the server or via SSH:
- Install git: `apt install git`
- Clone repo: `git clone https://github.com/willplayforfun/MediaServerConfig.git /opt/docker`
- Run env-setup script: `bash /opt/docker/env-setup.sh`
    - If setting up DDNS (NoIP.com):
        - enter your DDNS hostname; not including the `.ddns.net` part
        - enter your DDNS Key username and password. Get this from "DDNS & Remote Access" → "DDNS Keys" → "Add Group" on the [NoIP.com] website.
    - choose which services to enable. You can re-run the script later to change the mix.
    - if you enable Plex, you'll be asked for a claim token. Get it from [https://www.plex.tv/claim]. You can leave the port at the default `8443`.

### Fan Speed Control (optional)

To set up quiet, temperature-responsive fan curves:
- Run `bash /opt/docker/install-fan-control.sh`

This installs `lm-sensors` and `fancontrol`, probes for fan controllers, then runs the interactive `pwmconfig` wizard to let you set a thermal curve for your motherboard. Verify with `sensors` and adjust `/etc/fancontrol` if needed.

### Install OMV-Extras

Still with a keyboard connected or via SSH:
- Run `bash /opt/docker/install-omv-extras.sh`

Now refresh the OMV web UI. New options will appear under System → Plugins. 

# OMV Plugins and Docker Setup

## Install Plugins
mergerfs combines your data drives into a single pool. SnapRAID provides parity so you can recover from a drive failure.

> [!NOTE]
> **Understanding the Layout**
> Example with 4 x 2TB drives:
> - 3 drives = data (pooled by mergerfs into ~6TB usable)
> - 1 drive = SnapRAID parity (enables single-drive failure recovery)
> **Note:** The parity drive must be at least as large as your largest data drive.

- System → Plugins – install `openmediavault-snapraid`, `openmediavault-mergerfs`.
- Apply changes when prompted.

## Prepare Drives in OMV
- Storage → Disks – verify all HDDs appear. Make note of the name of your OS SSD (e.g. `/dev/sdb`).
- Storage → File Systems – create EXT4 on each HDD, then mount the new filesystems.
    - Make sure the HDDs are empty. Getting data off the HDDs is beyond the scope of this guide.

## Confgure SnapRAID
- Services → SnapRAID → Arrays
    - create new array `media_raid`
- Services → SnapRAID → Drives
    - Add one "Parity" drive and the rest of your non-OS disk as "Data" drives. All drives can be marked "Content".
    - I like to include the name of the disk (e.g. `sda1`) in the name of the RAID drive (e.g. `data_sda1`, `parity_sdc1`).
- Services → SnapRAID → Settings → Scheduled diff
    - Enable and set Time of Execution to "Daily".
- Save and apply.

## Configure mergerfs
- Storage → mergerfs → Create.
    - Name: `media`
    - Filesystems: select data disks only (NOT parity)
- Save and apply

# Folder Setup
Now that we have a merged file system which is loss-tolerant, let's set up our media storage on top of it.

## Create Media Folders
Storage → Shared Folders. For each folder we create, set the filesystem to `media`.
| Name               | Relative Path |
|--------------------|---------------|
| media-movies       | movies/       |
| media-tv           | tv/           |
| media-music        | music/        |
| media-audiobooks   | audiobooks/   |
| media-podcasts     | podcasts/     |
| media-vr          | vr/           |

You can also create additional folders for network file sharing using the same scheme. By default, a filebrowser UI exists that points at `share/`

## Install Docker Plugin
In OMV web UI: 
- Under System → Plugins → search for `openmediavault-compose` and install it.
- Under Storage → Shared Folders → Create a new one
    - Call it `docker`
    - Assign it the OS SSD filesystem.
    - Set the relative path to `opt/docker/` 
- Under Services → Compose → Settings – set the Shared Folder to `docker`.

## Configure SMB

Services → SMB/CIFS → Settings. Enable it. Standard options are fine.
Services → SMB/CIFS → Shares. Add the folders to share. Standard options are fine.

## Configure SFTP

Create a User Group `sftp-access`. Give Read/Write permission to all relevant media folders. 

System → Plugins → install `openmediavault-sftp`

Services → Sftp → Settings:
- Enable: true
- Port: 222 (22 is used for SSH)
- Password authentication: false
- Public key authentication: true
- AllowGroups: true
- Extra Options:
```
Match Group sftp-access
    ChrootDirectory /srv/mergerfs/media
    ForceCommand internal-sftp
```

All SFTP users will be able to see all folders in the merged media filesystem. However, they can only access folders which have been explicitly granted Read/Write permission. 

NOTE: You can grant additional permissions to specific users or other user groups, and those permission will apply to SFTP actions.


# First User Setup

With the permissions set up on SFTP above, you will need a non-root user to start transferring media.

Follow the user creation steps in the [Operations Guide](OperationsGuide.md).

# Network Setup

## Install Fail2ban
System → Plugins → install `openmediavault-fail2ban`. This will block bots that try to brute-force attack your server.

Services → Fail2ban → Settings 
- Enable: true
- Ignore IP: `127.0.0.1 192.168.0.0/16`
- I set my times to `604800`, added my email, and set `action_mwl`, but these are not essential.

## Forward Ports
On your router, forward these ports to your server:
- External port 80 → Internal port 80 (TCP) – required for Let's Encrypt
- External port 443 → Internal port 443 (TCP) – HTTPS traffic
- (Plex only) External port 8443 → Internal port 8443 (TCP). Use whatever port you set `PLEX_HTTPS_PORT` to (default is 8443).

## Configure dnsmasq
Dnsmasq runs as part of the Docker stack, but you must set the "Primary DNS Server" in your router's config to the internal IP of your server. 

NOTE: It is important that your router never re-assign the IP of the server when using dnsmasq. Make sure to assign the server a static IP.

# Service Setup

See the individual guides for [Jellyfin](JellyfinSetupGuide.md), [Plex](PlexSetupGuide.md), [Universal Media Server](UniversalMediaServerSetupGuide.md), [Navidrome](NavidromeSetupGuide.md), and [Audiobookshelf](AudiobookshelfSetupGuide.md).

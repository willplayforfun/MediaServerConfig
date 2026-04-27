Read through these instructions line by line. Each is important.

# Prerequisites
- No-IP DDNS
    - Generate a DDNS Key. Write down the username and password for later.
- Router admin access for port forwarding
- Flash drive (2 GB should be enough)
- Server hardware with an SSD for the OS and at least 1 drive for your data.
    - I recommend starting with just the SSD connected to the motherboard, to avoid confusion.
- Keyboard and monitor hooked up to server


# OpenMediaVault Installation
- Download the latest OMV ISO from https://www.openmediavault.org/download.html
- Flash the ISO to a USB drive using [Rufus](https://rufus.ie/en/).
- Boot your server from the USB drive.
- Follow the Debian installer. Key choices:
	- Hostname: e.g., myserver - NOTE: this name will show up e.g. on your network shared folder and your "connected devices" list on your router config page
	- Root password: choose something strong and save it - I wrote mine on a sticky note and stuck it to the server
	- Install destination: select your OS SSD – NOT your data HDDs.
- Once installation completes, remove the USB drive and reboot.
- If you left your data drives disconnected, now is the time to reconnect them (while the server is off!).
- After reboot, log in at the console using the root password. Run `ip addr` to find your server's IP on your local network. It will be something like `192.168.1.XXX`, under an entry that looks like `eth0` or `enp1s0`. Write it down for later use.

# Initial OMV Setup
Access the OMV web UI at `http://<server-ip>` in your browser. Default login:
- Username: `admin` 
- Password: `openmediavault`

## First Steps
- Change the admin password: User Settings (person icon in top bar) → Change Password
	- I recommend saving this password in a password manager, like LastPass.
	- I recommend re-using this `admin` username and password across all the admin accounts we set up, to make it easier to log in. 
- Update the system: System → Update Management → Check for updates → Install all.
- Enable SSH: Services → SSH → Enable
	- I recommend generating a keypair and using that to authenticate for SSH and SFTP, rather than using a password. It is more secure and more convenient.
        - TODO: How?
	- It is generally recommended to disable password-based login before exposing your server to the internet.
        - TODO: How?
- Set the Port in System → Workbench → Settings to `8888`. Going forwards, the OMV web UI is accessed at `http://<server-ip>:8888`
    - Setting the automatic logout to 1 day or Disabled is helpful

# OMV Plugins and Docker Setup
If you are comfortable using SSH, it can be easier for the next terminal steps here. (i.e. `ssh root@<server-ip>`).

## Clone the Repository

Either with a keyboard connected to the server or via SSH:
- Install git: `apt install git`
- Clone repo: `git clone https://github.com/willplayforfun/HomeServer1Config.git /opt/docker`
- Run env-setup script: `bash /opt/docker/env-setup.sh`
    - enter your DDNS hostname; not including the `.ddns.net` part
    - enter your DDNS Key username and password

## Install OMV-Extras

Still with a keyboard connected or via SSH:
- Run `bash /opt/docker/install-omv-extras.sh`

Now refresh the OMV web UI. New options will appear under System → Plugins. 

## Install Plugins
mergerfs combines your data drives into a single pool. SnapRAID provides parity so you can recover from a drive failure.

> [!NOTE]
> **Understanding the Layout**
> Example with 4 x 2TB drives:
> - 3 drives = data (pooled by mergerfs into ~6TB usable)
> - 1 drive = SnapRAID parity (enables single-drive failure recovery)
> **Note:** The parity drive must be at least as large as your largest data drive.

- System → Plugins – install `openmediavault-snapraid`, `openmediavault-mergerfs`, and `openmediavault-sharerootfs`.
- Apply changes when prompted.

## Prepare Drives in OMV
- Storage → Disks – verify all HDDs appear. Make note of the name of your OS SSD (e.g. `/dev/sdb`).
- Storage → File Systems – create EXT4 on each HDD.
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

You can also create additional folders for network file sharing using the same scheme.

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

## Configure Nginx

Navigate to `http://<server-ip>:81` in your browser
Default credentials: 
- Username: `admin@example.com` 
- Password: `changeme`
Change these immediately. I recommend using the same password as you used for the OMV web UI. Use a real email (it's used for generating TLS certificates) 

Go to Hosts → Proxy Hosts → **Add Proxy Host**

Route internet traffic from DDNS, Force SSL:
```
Domain Names: <your-domain>
Scheme: http
Forward Hostname: localhost
Forward Port: 80
Block Common Exploits: true
Websockets Support: true
Force SSL: true
HTTP/2 Support: true 
```
For the SSL Certificate, just select "Request a new certificate".

If you don't plan on using dnsmasq to make your server accessible within your network via the domain names, then add this block (Non-SSL, local traffic via server IP):
```
Domain Names: <server-ip>
Scheme: http
Forward Hostname: localhost
Forward Port: 80
Block Common Exploits: true
Websockets Support: true
```

## Configure dnsmasq
Dnsmasq runs as part of the Docker stack, but you must set the "Primary DNS Server" in your router's config to the internal IP of your server. 

NOTE: It is important that your router never re-assign the IP of the server when using dnsmasq. Make sure to assign the server a static IP.

# Service Setup

See the individual guides for [Jellyfin](JellyfinSetupGuide.md), [Navidrome](NavidromeSetupGuide.md), and [Audiobookshelf](AudiobookshelfSetupGuide.md).

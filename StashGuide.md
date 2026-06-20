# Stash Setup

Access Stash at `https://<your-domain>/stash`

## OMV Setup 

Add a new Shared Folder in the OMV workbench UI:
`extra/`

Create a new User Group: `sftp-access-extra`

Grant access to the `extra/` folder for `sftp-access-extra` but NOT `sftp-access`. (You can extend this pattern to other folders, if you like.)

## Stash Setup

Go through the first-time setup wizard. Set the data directory to `/data/media`. All other options can be left default.

### Additional Settings

In the settings menu, it can be nice to enable:
- Tasks -> Library
    - Generate previews
    - Generate scrubber sprites
    - Generate video perceptual hashes
- Interface -> Scene Player
    - Disable "Show scrubber"
- Metadata Providers -> Installed Scrapers
    - Add sources to pull metadata relevant to your videos


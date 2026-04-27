# Audiobookshelf Setup
Access Audiobookshelf at `https://<your-domain>/audiobookshelf`

## First Login
Create your admin account on first access.

## Add Libraries
Settings → Libraries → Add Library:
- Audiobooks library → folder: /audiobooks
- Podcasts library → folder: /podcasts

## Getting Your Audible Books
OpenAudible (https://openaudible.org/) – desktop app to download and convert Audible books to M4B/MP3.
audible-cli (https://github.com/mkb79/audible-cli) – command-line bulk download tool.
Place converted files on the server.

### Audiobook Folder Structure
/srv/mergerfs/media/audiobooks/
├── Author Name/
│   ├── Book Title/
│   │   ├── BookTitle.m4b
│   │   └── cover.jpg

## Podcasts
In the Podcasts library, use the "Add Podcast" button and paste RSS feed URLs. Episodes download automatically.

# Adding Users
Each user gets their own  listening progress, bookmarks, collections. See the [Operations Guide](OperationsGuide.md) for how to manage Audiobookshelf users.

# Connecting the Client App
In the app, set the server URL to `https://<your-domain>` (the app appends /audiobookshelf automatically)
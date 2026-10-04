# Audiobookshelf Setup
Access Audiobookshelf at `https://<your-domain>/audiobookshelf`

## First Login
Create your admin account on first access.

## Add Libraries
Settings → Libraries → Add Library:
- Audiobooks library → folder: /audiobooks
- Podcasts library → folder: /podcasts

## Getting Your Audible Books
Just use Libation (https://getlibation.com/) – desktop app to download and convert Audible books to M4B/MP3.
Place converted files on the server.

### Audiobook Folder Structure
/srv/mergerfs/media/audiobooks/
│   ├── Book Title/
│   │   ├── BookTitle.m4b
│   │   └── cover.jpg

## Podcasts
In the Podcasts library, use the "Add Podcast" button and paste RSS feed URLs. Episodes download automatically.

# Adding Users
Each user gets their own  listening progress, bookmarks, collections. See the [Operations Guide](OperationsGuide.md) for how to manage Audiobookshelf users.

# Connecting the Client App
In the app, set the server URL to `https://<your-domain>` (the app appends /audiobookshelf automatically)
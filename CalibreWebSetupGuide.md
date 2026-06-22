# Calibre-Web Setup
Access Calibre-Web at `https://<your-domain>/books`, once enabled via the [Software Guide](SoftwareGuide.md).

Note that we use Calibre-Web-Automated, which is a better maintained and fully-featured service. It serves as both a library manager and a web reader interface.

## First Login
Default admin login: `admin` / `admin123`.

Log in immediately and change the password: 
- click on the profile icon (top right) -> admin
- set new password in "Password" field
- scroll to bottom and hit save

Go to Settings (top right):
- Edit Basic Configuration:
    - Feature Configuration
        - "Enable Uploads"
- Edit UI Configuration:
    - Default Settings for New Users, enable:
        - "Allow eBook Viewer"
        - "Allow Downloads"
        - "Allow Edit"
        - "Allow Changing Password"

### Book Folder Structure
Calibre-Web (and Calibre itself) organizes books as:
```
/srv/mergerfs/media/books/
│   ├── Author Name/
│   │   ├── Book Title (id)/
│   │   │   ├── book.epub
│   │   │   ├── cover.jpg
│   │   │   └── metadata.opf
```
You can drop existing epub/mobi/pdf files into the library through the web UI's upload button, or copy them directly into the folder via SFTP/Filebrowser and use Admin → "Reconnect/Reload" to pick them up.

## OPDS Feed (e-reader apps)
Calibre-Web exposes an OPDS catalog for apps like KOReader, Moon+ Reader, etc.:
- Feed URL: `https://<your-domain>/books/opds`
- Use your Calibre-Web username/password when the app prompts for auth.

## Adding Users
As admin:
- Settings (top right) → Add new user
- Set username, email, password
- Hit "Save"

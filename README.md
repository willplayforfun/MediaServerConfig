What Goes in the Repo
- docker-compose.yml
- Nginx config files (e.g., helpsite default.conf)
- Help page HTML/CSS
 -Any custom scripts (backup scripts, cron jobs, etc.)
- A README documenting your setup

What Does NOT Go in the Repo
- Media files (too large)
- Docker persistent data (databases, caches, generated thumbnails)
- Secrets (passwords, API keys) – use a .env file excluded via .gitignore

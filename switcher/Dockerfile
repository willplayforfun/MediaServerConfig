# Stdlib only (see app.py) - no pip install step needed, matches the
# internal-dns-init service's convention in the main docker-compose.yml.
FROM python:3.13-alpine

COPY app.py /app.py

CMD ["python3", "/app.py"]

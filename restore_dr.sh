#!/bin/sh
set -eu
cd "$(dirname "$0")"
CID="$(docker compose ps -q app)"
[ -n "$CID" ] || { echo "Container app non avviato" >&2; exit 1; }

echo "Backup Disaster Recovery disponibili:"
docker exec "$CID" sh -c 'ls -1t /backups/DR-*.tgz 2>/dev/null || true'
printf "Nome archivio DR da ripristinare: "; read -r archive
case "$archive" in DR-*.tgz) ;; *) echo "Archivio DR non valido" >&2; exit 2;; esac
docker exec "$CID" test -f "/backups/$archive" || { echo "Backup non trovato" >&2; exit 1; }
printf "ATTENZIONE: verranno sostituiti applicazione, configurazione e database. Scrivi RIPRISTINA-DR: "
read -r confirm
[ "$confirm" = "RIPRISTINA-DR" ] || { echo "Annullato"; exit 0; }

echo "Creo un DR di sicurezza dello stato corrente..."
./backup.sh dr >/dev/null
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
docker cp "$CID:/backups/$archive" "$tmp/$archive"
mkdir "$tmp/unpack"
tar -xzf "$tmp/$archive" -C "$tmp/unpack"
[ -f "$tmp/unpack/app.py" ] && [ -f "$tmp/unpack/compose.yaml" ] || { echo "Archivio DR incompleto" >&2; exit 1; }
db="$(find "$tmp/unpack" -maxdepth 1 -name 'DR-*.sqlite3' | head -n1)"
[ -n "$db" ] || { echo "Database DR mancante" >&2; exit 1; }

echo "Arresto stack e ripristino file..."
docker compose down
for f in app.py Dockerfile compose.yaml setup.sh update.sh backup.sh manage_user.sh static; do
 [ -e "$tmp/unpack/$f" ] && { rm -rf "$f"; cp -a "$tmp/unpack/$f" "$f"; }
done
[ -f "$tmp/unpack/compose.override.yaml" ] && cp "$tmp/unpack/compose.override.yaml" compose.override.yaml
[ -f "$tmp/unpack/.env" ] && cp "$tmp/unpack/.env" .env

docker compose up -d --build
CID="$(docker compose ps -q app)"
i=0
while [ -z "$CID" ] && [ "$i" -lt 15 ]; do sleep 2; CID="$(docker compose ps -q app)"; i=$((i+1)); done
[ -n "$CID" ] || { echo "Container non avviato dopo il ripristino" >&2; exit 1; }
docker cp "$db" "$CID:/tmp/restore.sqlite3"
docker exec "$CID" python - <<'PY'
import sqlite3,app
src=sqlite3.connect('/tmp/restore.sqlite3'); dst=app.connect()
try:
 assert src.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
 src.backup(dst); dst.commit()
finally:
 src.close(); dst.close()
PY
docker compose restart app
echo "Disaster Recovery completato da $archive"

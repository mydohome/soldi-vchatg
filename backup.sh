#!/bin/sh
set -eu
PROJECT_DIR="${PROJECT_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
cd "$PROJECT_DIR"
CID="$(docker compose ps -q app)"
[ -n "$CID" ] || { echo "Container app non avviato" >&2; exit 1; }
case "${1:-users}" in
  users)
    docker exec "$CID" python -c "import app; print('\n'.join(app.scheduled_user_backups()))"
    ;;
  dr)
    DBFILE="$(docker exec "$CID" python -c "import app; print(app.server_backup('DR'))")"
    STAMP="$(date +%Y%m%d-%H%M%S)"
    TMP="/tmp/spese-DR-$STAMP"
    mkdir -p "$TMP"
    cp -a Dockerfile compose.yaml setup.sh update.sh backup.sh static app.py "$TMP/" 2>/dev/null || true
    [ -f compose.override.yaml ] && cp compose.override.yaml "$TMP/"
    [ -f .env ] && cp .env "$TMP/"
    docker cp "$CID:/data/backups/$DBFILE" "$TMP/$DBFILE"
    tar -czf "/tmp/DR-$STAMP.tgz" -C "$TMP" .
    docker cp "/tmp/DR-$STAMP.tgz" "$CID:/data/backups/DR-$STAMP.tgz"
    rm -rf "$TMP" "/tmp/DR-$STAMP.tgz"
    docker exec "$CID" sh -c "ls -1t /data/backups/DR-*.tgz 2>/dev/null | tail -n +5 | xargs -r rm -f; ls -1t /data/backups/DR-*.sqlite3 2>/dev/null | tail -n +5 | xargs -r rm -f"
    echo "DR-$STAMP.tgz"
    ;;
  *) echo "Uso: $0 [users|dr]" >&2; exit 2 ;;
esac

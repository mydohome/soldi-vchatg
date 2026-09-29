#!/bin/sh
set -eu
PROJECT_DIR="${PROJECT_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
cd "$PROJECT_DIR"
CID="$(docker compose ps -q app)"
[ -n "$CID" ] || { echo "Container app non avviato" >&2; exit 1; }
docker exec "$CID" python -c "import app; print(app.server_backup('scheduled'))"

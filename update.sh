#!/bin/sh
# Aggiorna il branch main da origin, verifica lo stack e torna al commit precedente se necessario.
set -eu
cd "$(dirname "$0")"

error() { printf 'ERRORE: %s\n' "$*" >&2; }
command -v git >/dev/null 2>&1 || { error 'Git non trovato'; exit 1; }
command -v docker >/dev/null 2>&1 || { error 'Docker non trovato'; exit 1; }
docker compose version >/dev/null 2>&1 || { error 'Docker Compose v2 non disponibile'; exit 1; }
[ -f .env ] || { error 'File .env mancante: esegui prima setup.sh'; exit 1; }
[ "$(git branch --show-current 2>/dev/null)" = main ] || { error 'Lo script richiede il branch main'; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { error 'Modifiche locali presenti: salvale prima di aggiornare'; exit 1; }
git remote get-url origin >/dev/null 2>&1 || { error 'Remote origin assente'; exit 1; }
docker compose config --quiet || { error 'Configurazione Compose non valida'; exit 1; }

printf 'Controllo aggiornamenti su origin/main...\n'
if ! git fetch --quiet origin main; then error 'Impossibile controllare il repository remoto'; exit 1; fi
old_rev=$(git rev-parse HEAD)
new_rev=$(git rev-parse FETCH_HEAD)
if [ "$old_rev" = "$new_rev" ]; then
  printf 'Nessun aggiornamento disponibile (%s).\n' "$(git rev-parse --short HEAD)"
  exit 0
fi
if ! git merge-base --is-ancestor "$old_rev" "$new_rev"; then
  error 'La cronologia remota è divergente; aggiornamento automatico interrotto'
  exit 1
fi
printf 'Aggiornamento %s → %s\n' "$(git rev-parse --short "$old_rev")" "$(git rev-parse --short "$new_rev")"

healthy() {
  attempt=0
  while [ "$attempt" -lt 30 ]; do
    if docker compose exec -T app python -c "import json,urllib.request; assert json.load(urllib.request.urlopen('http://127.0.0.1:8080/api/health',timeout=3))['status']=='ok'" >/dev/null 2>&1; then return 0; fi
    attempt=$((attempt+1))
    sleep 2
  done
  return 1
}

rollback() {
  error 'Aggiornamento non riuscito. Ripristino della versione precedente...'
  docker compose logs --tail=40 app >&2 || true
  if ! git reset --hard "$old_rev" >/dev/null; then
    error 'Ripristino del codice fallito: intervento manuale necessario'
    exit 1
  fi
  if docker compose up -d --build && healthy; then
    error "Versione precedente ripristinata e funzionante ($(git rev-parse --short HEAD))"
  else
    error 'Anche il ripristino dello stack non è riuscito: controlla docker compose logs app'
  fi
  exit 1
}

if ! git merge --ff-only --quiet "$new_rev"; then error 'Impossibile applicare l’aggiornamento'; exit 1; fi
mkdir -p backups
# Migra una sola volta eventuali backup creati nel vecchio volume /data/backups.
old_cid=$(docker compose ps -q app 2>/dev/null || true)
if [ -n "$old_cid" ]; then
  docker cp "$old_cid:/data/backups/." backups/ >/dev/null 2>&1 || true
fi
chmod 777 backups 2>/dev/null || true
if ! docker compose config --quiet || ! docker compose up -d --build; then rollback; fi
if ! healthy; then rollback; fi
if [ -w /etc/cron.d ] || [ "$(id -u)" -eq 0 ]; then
  project_dir=$(pwd)
  {
    echo 'SHELL=/bin/sh'
    printf '15 2 * * * root cd "%s" && ./backup.sh users >> /var/log/soldi-vchatg-backup.log 2>&1\n' "$project_dir"
    printf '15 3 * * 0 root cd "%s" && ./backup.sh dr >> /var/log/soldi-vchatg-backup.log 2>&1\n' "$project_dir"
  } > /etc/cron.d/soldi-vchatg
  chmod 644 /etc/cron.d/soldi-vchatg
  printf 'Cron backup configurato: utenti giornalieri, DR settimanale.\n'
else
  printf 'ATTENZIONE: cron non configurato (permessi insufficienti su /etc/cron.d).\n' >&2
fi
printf 'Aggiornamento completato: stack funzionante (%s).\n' "$(git rev-parse --short HEAD)"

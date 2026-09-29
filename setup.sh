#!/bin/sh
set -eu
cd "$(dirname "$0")"
command -v docker >/dev/null 2>&1 || { echo 'Docker non trovato'; exit 1; }
docker compose version >/dev/null 2>&1 || { echo 'Docker Compose non trovato'; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo 'Python 3 non trovato (necessario per verificare le porte)'; exit 1; }

port_available() {
  python3 - "$1" <<'PY'
import socket
import sys

port = int(sys.argv[1])
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    try:
        sock.bind(("0.0.0.0", port))
    except OSError:
        sys.exit(1)
PY
}

choose_port() {
  label=$1
  suggested=''
  candidate=8088
  while [ "$candidate" -le 8999 ]; do
    if port_available "$candidate"; then suggested=$candidate; break; fi
    candidate=$((candidate + 1))
  done
  [ -n "$suggested" ] || { echo 'Nessuna porta libera tra 8088 e 8999.' >&2; return 1; }
  while :; do
    printf '%s [%s]: ' "$label" "$suggested" >&2
    IFS= read -r selected || return 1
    selected=${selected:-$suggested}
    case "$selected" in
      *[!0-9]*|'') echo 'Inserisci una porta numerica tra 1 e 65535.' >&2; continue ;;
    esac
    if [ "$selected" -lt 1 ] || [ "$selected" -gt 65535 ]; then
      echo 'Inserisci una porta tra 1 e 65535.' >&2
    elif ! port_available "$selected"; then
      echo "La porta $selected è già occupata o non disponibile." >&2
    else
      printf '%s\n' "$selected"
      return 0
    fi
  done
}

existing=0; old_key=''; old_mode=''
if [ -f .env ]; then
  existing=1
  old_key=$(sed -n 's/^INSTALL_KEY=//p' .env | head -n1)
  old_mode=$(sed -n 's/^DEPLOY_MODE=//p' .env | head -n1)
  echo "Installazione esistente rilevata (modalità: ${old_mode:-non registrata})."
  echo 'Utenti e dati nel volume Docker saranno mantenuti.'
fi
[ -n "$old_key" ] || old_key="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"

printf '\nModalità di accesso:\n  1) Test in LAN via HTTP\n  2) NPM sulla stessa macchina/rete Docker\n  3) NPM su altro host\nScelta [1/2/3]: '
read -r mode
case "$mode" in
  1)
    deploy_mode=lan-http
    port=$(choose_port 'Porta HTTP LAN')
    network=spese_internal
    docker network inspect "$network" >/dev/null 2>&1 || docker network create "$network" >/dev/null
    printf 'services:\n  app:\n    ports:\n      - "%s:8080"\n' "$port" > compose.override.yaml
    message="Accesso LAN: http://IP_DEL_SERVER:$port"
    ;;
  2)
    deploy_mode=npm-docker
    printf 'Nome rete Docker condivisa con NPM [npm_proxy]: '; read -r network; network=${network:-npm_proxy}
    docker network inspect "$network" >/dev/null 2>&1 || { echo "Rete Docker '$network' non trovata."; exit 1; }
    printf 'services: {}\n' > compose.override.yaml
    message='In NPM usa come upstream app:8080 sulla rete Docker condivisa.'
    ;;
  3)
    deploy_mode=npm-remote
    port=$(choose_port 'Porta sull host Docker')
    network=spese_internal
    docker network inspect "$network" >/dev/null 2>&1 || docker network create "$network" >/dev/null
    printf 'services:\n  app:\n    ports:\n      - "%s:8080"\n' "$port" > compose.override.yaml
    message="In NPM usa IP del server Docker e porta $port; limita la porta via firewall al solo host NPM."
    ;;
  *) echo 'Scelta non valida'; exit 1;;
esac

printf 'PROXY_NETWORK=%s\nINSTALL_KEY=%s\nDEPLOY_MODE=%s\n' "$network" "$old_key" "$deploy_mode" > .env
chmod 600 .env

docker compose build
if [ "$existing" -eq 0 ]; then
  printf 'Nome del primo utente: '; read -r username
  printf 'Email facoltativa: '; read -r email
  printf 'Password del primo utente (minimo 12 caratteri, input nascosto): '
  stty -echo; read -r password; stty echo; printf '\n'
  [ "${#username}" -ge 3 ] && [ "${#password}" -ge 12 ] || { echo 'Credenziali non valide; correggi e rilancia setup.sh.'; exit 1; }
  docker compose run --rm -T -e FIRST_USERNAME="$username" -e FIRST_EMAIL="$email" -e FIRST_PASSWORD="$password" app sh -c 'python /app/app.py create-user "$FIRST_USERNAME" "$FIRST_PASSWORD" "$FIRST_EMAIL" 1'
else
  echo 'Riconfigurazione: creazione utente iniziale saltata.'
fi

docker compose up -d --remove-orphans

# Backup automatici: utenti ogni giorno alle 02:15, DR ogni domenica alle 03:15.
CRON_FILE="/etc/cron.d/soldi-vchatg"
if [ -w /etc/cron.d ] || [ "$(id -u)" -eq 0 ]; then
  project_dir=$(pwd)
  {
    echo 'SHELL=/bin/sh'
    printf '15 2 * * * root cd "%s" && ./backup.sh users >> /var/log/soldi-vchatg-backup.log 2>&1\n' "$project_dir"
    printf '15 3 * * 0 root cd "%s" && ./backup.sh dr >> /var/log/soldi-vchatg-backup.log 2>&1\n' "$project_dir"
  } > "$CRON_FILE"
  chmod 644 "$CRON_FILE"
  echo 'Backup automatici configurati: utenti giornalieri (7 copie), DR settimanale (4 copie).'
else
  echo 'ATTENZIONE: impossibile scrivere /etc/cron.d. Configura manualmente backup.sh users e backup.sh dr.'
fi
echo 'Attendo il controllo di integrità...'
i=0
while [ "$i" -lt 12 ]; do
  if docker compose exec -T app python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/api/health', timeout=3).read()" >/dev/null 2>&1; then
    echo 'Configurazione completata e applicazione operativa.'
    echo "$message"
    [ "$deploy_mode" = "lan-http" ] && echo 'ATTENZIONE: HTTP è previsto per test in LAN; per uso normale preferisci HTTPS dietro NPM.'
    exit 0
  fi
  i=$((i + 1)); sleep 5
done
echo 'ERRORE: stack avviato ma health check HTTP interno non riuscito.'
docker compose ps
exit 1

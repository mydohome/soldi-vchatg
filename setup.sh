#!/bin/sh
set -eu
cd "$(dirname "$0")"
command -v docker >/dev/null 2>&1 || { echo 'Docker non trovato'; exit 1; }
docker compose version >/dev/null 2>&1 || { echo 'Docker Compose non trovato'; exit 1; }
[ ! -e .env ] || { echo '.env esiste già: installazione già inizializzata'; exit 1; }
printf 'Tipo installazione: 1) NPM su rete Docker  2) NPM su altro host\nScelta [1/2]: '
read -r mode
case "$mode" in 1) printf 'Nome rete Docker condivisa con NPM [npm_proxy]: '; read -r network; network=${network:-npm_proxy}; docker network inspect "$network" >/dev/null 2>&1 || { echo 'Rete non trovata';exit 1; }; printf 'PROXY_NETWORK=%s\nINSTALL_KEY=%s\n' "$network" "$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')" > .env; cat > compose.override.yaml <<'EOF'
services: {}
EOF
 echo 'In NPM usa il nome host app e la porta 8080 sulla rete condivisa.';;
 2) printf 'Porta sull’host Docker [8088]: '; read -r port; port=${port:-8088}; case "$port" in *[!0-9]*|'') echo 'Porta non valida';exit 1;; esac; [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { echo 'Porta non valida';exit 1; }; network=spese_internal; docker network inspect "$network" >/dev/null 2>&1 || docker network create "$network" >/dev/null; printf 'PROXY_NETWORK=%s\nINSTALL_KEY=%s\n' "$network" "$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')" > .env; cat > compose.override.yaml <<EOF
services:
  app:
    ports:
      - "${port}:8080"
EOF
 echo "In NPM sull'altro host usa l'IP del server Docker e la porta $port. Limita l'accesso alla porta con il firewall.";;
 *) echo 'Scelta non valida';exit 1;;esac
chmod 600 .env
printf 'Nome del primo utente: '; read -r username
printf 'Email facoltativa: '; read -r email
printf 'Password del primo utente (minimo 12 caratteri, input nascosto): '
stty -echo; read -r password; stty echo; printf '\n'
[ "${#username}" -ge 3 ] && [ "${#password}" -ge 12 ] || { echo 'Credenziali non valide; ripeti setup dopo aver rimosso .env e compose.override.yaml';exit 1; }
docker compose build
docker compose run --rm -T -e FIRST_USERNAME="$username" -e FIRST_EMAIL="$email" -e FIRST_PASSWORD="$password" app sh -c 'python /app/app.py create-user "$FIRST_USERNAME" "$FIRST_PASSWORD" "$FIRST_EMAIL" 1'
docker compose up -d
echo 'Installazione completata. Configura NPM con HTTPS e Websockets disattivato.'

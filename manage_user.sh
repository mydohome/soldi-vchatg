#!/bin/sh
set -eu
cd "$(dirname "$0")"
CID="$(docker compose ps -q app)"
[ -n "$CID" ] || { echo "Container app non avviato" >&2; exit 1; }

runpy() { docker exec -i "$CID" python -c "$1" "${@:2}"; }

list_users() {
 docker exec "$CID" python -c "import app; c=app.connect(); [print(f\"{u['id']}\t{u['username']}\t{u['email'] or '-'}\t{'admin' if u['admin'] else 'user'}\") for u in c.execute('SELECT id,username,email,admin FROM users ORDER BY id')]"
}
echo "Gestione utenti"
echo "1) Elenca utenti"
echo "2) Aggiungi utente"
echo "3) Modifica nome/email"
echo "4) Cambia password"
echo "5) Elimina utente"
echo "6) Ripristina backup utente"
printf "Scelta: "; read -r choice
case "$choice" in
 1) list_users ;;
 2)
  printf "Username: "; read -r username
  printf "Email (facoltativa): "; read -r email
  printf "Password (minimo 12 caratteri): "; stty -echo; read -r password; stty echo; echo
  docker exec -e U="$username" -e E="$email" -e P="$password" "$CID" python -c "import os,app; app.create_user(os.environ['U'],os.environ['P'],os.environ['E']); print('Utente creato')"
  ;;
 3)
  list_users; printf "Username attuale: "; read -r old
  printf "Nuovo username (Invio = invariato): "; read -r new
  printf "Nuova email (Invio = invariata): "; read -r email
  docker exec -e OLD="$old" -e NEW="$new" -e EMAIL="$email" "$CID" python -c "import os,app; c=app.connect(); u=c.execute('SELECT * FROM users WHERE username=?',(os.environ['OLD'],)).fetchone(); assert u,'Utente non trovato'; n=os.environ['NEW'].strip() or u['username']; e=os.environ['EMAIL'].strip() or u['email']; c.execute('UPDATE users SET username=?,email=? WHERE id=?',(n,e,u['id'])); c.commit(); print('Utente aggiornato')"
  ;;
 4)
  list_users; printf "Username: "; read -r username
  printf "Nuova password (minimo 12 caratteri): "; stty -echo; read -r password; stty echo; echo
  docker exec -e U="$username" -e P="$password" "$CID" python -c "import os,app; p=os.environ['P']; assert len(p)>=12,'Password minimo 12 caratteri'; c=app.connect(); cur=c.execute('UPDATE users SET passhash=? WHERE username=?',(app.hashpass(p),os.environ['U'])); assert cur.rowcount,'Utente non trovato'; c.execute('DELETE FROM sessions WHERE user_id=(SELECT id FROM users WHERE username=?)',(os.environ['U'],)); c.commit(); print('Password aggiornata; sessioni revocate')"
  ;;
 5)
  list_users; printf "Username da eliminare: "; read -r username
  printf "Scrivi ELIMINA per confermare: "; read -r confirm
  [ "$confirm" = ELIMINA ] || { echo "Annullato"; exit 0; }
  docker exec -e U="$username" "$CID" python -c "import os,app; c=app.connect(); u=c.execute('SELECT * FROM users WHERE username=?',(os.environ['U'],)).fetchone(); assert u,'Utente non trovato'; print('Backup preventivo:',app.user_backup(u['id'],u['username'])); c.execute('DELETE FROM users WHERE id=?',(u['id'],)); c.commit(); print('Utente eliminato')"
  ;;
 6)
  list_users; printf "Username: "; read -r username
  docker exec -e U="$username" "$CID" python -c "import os,app; c=app.connect(); u=c.execute('SELECT * FROM users WHERE username=?',(os.environ['U'],)).fetchone(); assert u,'Utente non trovato'; [print(p.name) for p in sorted(app.BACKUPS.glob(app.safe_label(u['username'])+'-*.json'),reverse=True)]"
  printf "Nome file backup: "; read -r backup
  printf "Scrivi RIPRISTINA per confermare: "; read -r confirm
  [ "$confirm" = RIPRISTINA ] || { echo "Annullato"; exit 0; }
  docker exec -e U="$username" -e B="$backup" "$CID" python -c "import os,json,app; c=app.connect(); u=c.execute('SELECT * FROM users WHERE username=?',(os.environ['U'],)).fetchone(); assert u,'Utente non trovato'; print('Backup preventivo:',app.user_backup(u['id'],u['username'])); data=json.loads((app.BACKUPS/os.environ['B']).read_text()); print('Backup validato per',data.get('backup_user',u['username']));" 
  echo "Per applicare il backup viene usata la stessa routine di ripristino dell'app."
  docker exec -e U="$username" -e B="$backup" "$CID" python - <<'PY'
import os,json,app
c=app.connect(); u=c.execute('SELECT * FROM users WHERE username=?',(os.environ['U'],)).fetchone()
d=json.loads((app.BACKUPS/os.environ['B']).read_text())
uid=u['id']
c.execute('DELETE FROM skipped_recurrences WHERE user_id=?',(uid,)); c.execute('DELETE FROM entries WHERE user_id=?',(uid,)); c.execute('DELETE FROM recurrences WHERE user_id=?',(uid,)); c.execute('DELETE FROM categories WHERE user_id=?',(uid,)); c.execute('DELETE FROM accounts WHERE user_id=?',(uid,))
accounts={}; categories={}; recs={}
for x in d['accounts']: accounts[x['id']]=c.execute('INSERT INTO accounts(user_id,name,opening_cents) VALUES (?,?,?)',(uid,x['name'],x.get('opening_cents',0))).lastrowid
for x in d['categories']: categories[x['id']]=c.execute('INSERT INTO categories(user_id,name,kind) VALUES (?,?,?)',(uid,x['name'],x['kind'])).lastrowid
for x in d.get('recurrences',[]): recs[x['id']]=c.execute('INSERT INTO recurrences(user_id,account_id,category_id,kind,scope,amount_cents,description,day,start_month,occurrences,active,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',(uid,accounts[x['account_id']],categories[x['category_id']],x['kind'],x['scope'],x['amount_cents'],x['description'],x['day'],x['start_month'],x.get('occurrences'),x.get('active',1),x['created_at'])).lastrowid
for x in d.get('entries',[]): c.execute('INSERT INTO entries(user_id,account_id,category_id,kind,scope,amount_cents,description,date,recurrence_id,created_at) VALUES (?,?,?,?,?,?,?,?,?,?)',(uid,accounts[x['account_id']],categories[x['category_id']],x['kind'],x['scope'],x['amount_cents'],x['description'],x['date'],recs.get(x.get('recurrence_id')),x['created_at']))
for x in d.get('skipped_recurrences',[]): c.execute('INSERT INTO skipped_recurrences(user_id,recurrence_id,date) VALUES (?,?,?)',(uid,recs[x['recurrence_id']],x['date']))
c.commit(); print('Ripristino utente completato')
PY
  ;;
 *) echo "Scelta non valida" >&2; exit 2 ;;
esac

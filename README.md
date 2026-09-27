# Spese

Webapp mobile per spese personali e domestiche. Ogni utente possiede conti, categorie, movimenti, ricorrenze e backup separati. L'amministratore crea gli altri utenti. Interfaccia in italiano con tasto rapido fisso per spese ed entrate.

## Installazione

Requisiti: Docker Compose v2, Nginx Proxy Manager (NPM), un dominio e HTTPS.

```sh
chmod +x setup.sh
./setup.sh
```

Scegli NPM sulla stessa rete Docker o su altro host. Nel primo caso indica una rete Docker esterna esistente, condivisa con NPM, e configura l'upstream `app:8080`. Nel secondo caso configura come upstream l'IP del server Docker e la porta scelta; limita tale porta con firewall al solo host NPM. Attiva un certificato SSL e Force SSL in NPM. Lo script crea `.env` con un segreto casuale e `compose.override.yaml`, poi chiede le credenziali del primo amministratore. SQLite usa un volume Docker e non richiede una password database. Conserva la password amministratore e il backup in luogo sicuro.

Per aggiornare: `docker compose up -d --build`. Per vedere i log: `docker compose logs -f app`. Per un backup completo dalla UI: Impostazioni → Scarica backup. Il ripristino sostituisce i soli dati dell'utente corrente; l'account e la password restano invariati.

## Funzioni

- Spese ed entrate con ambito personale o casa, categoria, conto e data.
- Ricorrenze mensili con giorno 1–31 e numero opzionale di occorrenze. Nei mesi più corti viene usato l'ultimo giorno; gli addebiti maturati sono creati all'apertura dell'app, senza duplicati.
- Suggerimenti locali per descrizioni e categorie basati sulla frequenza dei movimenti passati del solo utente.
- Dashboard con spese giornaliere, settimanali e mensili, confronto percentuale col mese precedente, andamento a sei mesi e categorie. I saldi includono il saldo iniziale e i movimenti caricati.
- Backup JSON e ripristino per utente. Dati persistenti nel volume `spese_data`.

Aggiungi la pagina alla schermata Home da Safari su iPhone per usarla come webapp. L'app richiede connessione al server; non contiene una modalità offline.

## Sicurezza e limiti

Password archiviate con PBKDF2-HMAC-SHA256 e sale casuale; sessioni in cookie HttpOnly/Secure/SameSite. Servi l'app solo via HTTPS dietro NPM. La lista movimenti mostra i 200 più recenti; grafici e saldi usano tutti i movimenti. Il modello di suggerimento è un conteggio delle descrizioni già usate, senza servizi esterni. Prima di aggiornamenti importanti, conserva anche un backup del volume Docker.

## Test automatici

Il workflow GitHub Actions `.github/workflows/test.yml` controlla la sintassi, costruisce l'immagine e avvia Compose con un test HTTP di accesso, movimento e backup. Usa un runner Linux standard e non pubblica l'app.

## Aggiornamenti

Dalla cartella del repository sul server:

```sh
./update.sh
```

Lo script richiede il branch `main`, una copia Git senza modifiche ai file tracciati, `.env` e Docker Compose v2. Controlla `origin/main`, applica solo un avanzamento lineare, ricostruisce lo stack e verifica HTTP e database tramite `/api/health`. Se la nuova versione non si avvia o non risponde entro circa un minuto, riporta codice e container al commit precedente e restituisce un errore. Un ripristino del codice non annulla eventuali migrazioni del database: conserva sempre un backup prima di aggiornamenti importanti. Se non ci sono novità, non riavvia i container.

# Spese

Webapp mobile per spese personali e domestiche. Ogni utente possiede conti, categorie, movimenti, ricorrenze e backup separati. L'amministratore crea gli altri utenti. Interfaccia in italiano con tasto rapido fisso per spese ed entrate.

## Installazione

Requisiti: Docker Compose v2. Per il deploy normale sono consigliati Nginx Proxy Manager (NPM), un dominio e HTTPS; per i test è disponibile anche l'accesso HTTP diretto in LAN.

```sh
chmod +x setup.sh
./setup.sh
```

Il setup offre tre modalità: HTTP diretto in LAN per test, NPM sulla stessa rete Docker, oppure NPM su un altro host. In LAN viene pubblicata una porta HTTP del server. Per LAN e NPM remoto il setup cerca una porta libera tra 8088 e 8999, la propone come default e consente di sostituirla; anche la porta inserita manualmente viene controllata prima di applicare la configurazione. Con NPM locale indica una rete Docker esterna esistente e configura l'upstream `app:8080`; con NPM remoto usa l'IP del server Docker e la porta scelta, limitandola via firewall al solo host NPM. Per NPM attiva certificato SSL e Force SSL.\n\n`setup.sh` è rilanciabile: se l'installazione esiste, mantiene `INSTALL_KEY`, utenti e volume `spese_data`, consente di scegliere nuovamente una delle tre modalità, rigenera `.env` e `compose.override.yaml`, ricrea lo stack e verifica `/api/health`. Il primo amministratore viene richiesto solo alla prima installazione. SQLite usa un volume Docker e non richiede una password database.

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

# Spese

Webapp mobile per il tracciamento delle **spese personali e domestiche**, pensata anche per l'uso da iPhone.

Ogni utente dispone di conti, categorie, movimenti, ricorrenze e backup separati. L'amministratore può creare gli altri utenti.

## Funzioni principali

- Spese ed entrate con ambito **Personale** o **Casa**.
- Più conti e categorie di spesa.
- Ricorrenze mensili programmabili.
- Dashboard con riepiloghi giornalieri, settimanali e mensili.
- Confronto con il mese precedente e andamento degli ultimi sei mesi.
- Suggerimenti locali basati sui movimenti precedenti dell'utente.
- Backup e ripristino JSON per singolo utente.
- Dati persistenti in un volume Docker.
- Interfaccia mobile utilizzabile da Safari su iPhone.

---

## Requisiti

Sul server devono essere disponibili:

- Git
- Docker
- Docker Compose v2

Per l'utilizzo normale è consigliato pubblicare l'app tramite **Nginx Proxy Manager (NPM)** con dominio e HTTPS.

Per i test è disponibile anche una modalità **HTTP diretta in LAN**.

---

## Prima installazione

Sul server esegui:

```sh
git clone https://github.com/mydohome/soldi-vchatg.git
cd soldi-vchatg
chmod +x setup.sh update.sh
./setup.sh
```

Alla prima esecuzione `setup.sh`:

1. chiede la modalità di deploy;
2. prepara la configurazione Docker;
3. costruisce l'immagine;
4. chiede le credenziali del primo amministratore;
5. avvia lo stack;
6. verifica il funzionamento tramite `/api/health`.

SQLite utilizza il volume Docker `spese_data`; non è necessaria una password per il database.

---

## Modalità di deploy

Durante il setup puoi scegliere una delle tre modalità.

### 1. Test in LAN via HTTP

Pubblica direttamente l'app su una porta del server.

Il setup cerca automaticamente una porta TCP libera nell'intervallo **8088–8999** e la propone come default. Puoi accettarla premendo Invio oppure indicarne un'altra.

Anche una porta inserita manualmente viene controllata prima di procedere.

Al termine verrà mostrato un indirizzo simile a:

```text
http://IP_DEL_SERVER:8088
```

Questa modalità è pensata per **test nella rete locale**.

### 2. NPM sulla stessa macchina / rete Docker

Usa questa modalità quando Nginx Proxy Manager può raggiungere direttamente il container tramite una rete Docker condivisa.

Il setup chiede il nome della rete Docker, ad esempio:

```text
npm_proxy
```

La rete deve esistere già.

Nel Proxy Host di NPM configura:

```text
Forward Hostname / IP: app
Forward Port:          8080
```

Abilita HTTPS e **Force SSL** in NPM.

### 3. NPM su un altro host

Usa questa modalità quando Nginx Proxy Manager gira su un server differente.

Il setup cerca una porta libera nell'intervallo **8088–8999**, la propone e permette di cambiarla.

In NPM configura come destinazione:

```text
Forward Hostname / IP: IP_DEL_SERVER_DOCKER
Forward Port:          PORTA_SCELTA_DAL_SETUP
```

È consigliato limitare tramite firewall l'accesso a questa porta al solo host che esegue NPM.

---

## Riconfigurare il deploy

`setup.sh` può essere eseguito nuovamente anche dopo l'installazione:

```sh
cd soldi-vchatg
./setup.sh
```

Lo script rileva l'installazione esistente e permette di passare, ad esempio:

```text
LAN HTTP → NPM locale
LAN HTTP → NPM remoto
NPM locale → NPM remoto
NPM remoto → NPM locale
```

Durante la riconfigurazione vengono aggiornati `.env` e `compose.override.yaml` e lo stack viene ricreato.

Vengono mantenuti:

- utenti;
- database;
- volume `spese_data`;
- `INSTALL_KEY`.

La creazione del primo amministratore viene quindi richiesta **solo alla prima installazione**.

---

## Aggiornamenti

Per i normali aggiornamenti non è necessario eseguire manualmente `git pull`.

Dalla directory del progetto:

```sh
./update.sh
```

Lo script:

- controlla la presenza di aggiornamenti su `origin/main`;
- applica solo un avanzamento lineare del repository;
- ricostruisce lo stack Docker;
- riavvia i container;
- verifica HTTP e database tramite `/api/health`.

Se la nuova versione non si avvia correttamente, lo script tenta di riportare codice e container al commit precedente e restituisce un errore.

> **Nota:** il rollback del codice non annulla eventuali migrazioni del database. Prima di aggiornamenti importanti conserva sempre un backup.

Se non sono disponibili aggiornamenti, i container non vengono riavviati.

---

## Comandi utili

Visualizzare lo stato dei container:

```sh
docker compose ps
```

Seguire i log dell'app:

```sh
docker compose logs -f app
```

Riavviare lo stack:

```sh
docker compose restart
```

Verificare la configurazione Compose risultante:

```sh
docker compose config
```

---

## Backup e ripristino

Dall'interfaccia dell'app:

**Impostazioni → Scarica backup**

Il backup è relativo all'utente corrente.

Il ripristino sostituisce i dati dell'utente corrente, mentre account e password rimangono invariati.

Prima di aggiornamenti importanti è consigliato conservare anche un backup del volume Docker.

---

## Utilizzo da iPhone

Apri l'app in Safari e usa **Aggiungi alla schermata Home** per avviarla come una webapp.

L'app richiede una connessione al server e non dispone di una modalità offline.

---

## Sicurezza e limiti

Le password sono archiviate con **PBKDF2-HMAC-SHA256** e sale casuale.

Le sessioni utilizzano cookie HttpOnly e SameSite. Dietro Nginx Proxy Manager il cookie è anche Secure e richiede HTTPS. Nella modalità HTTP LAN, destinata ai test, il cookie non ha l'attributo Secure per permettere il login; usa questa modalità solo su una rete fidata.

La lista dei movimenti mostra i 200 elementi più recenti, mentre grafici e saldi utilizzano tutti i movimenti.

I suggerimenti sono calcolati localmente sui dati dell'utente e non utilizzano servizi esterni.

---

## Test automatici

Il workflow GitHub Actions:

```text
.github/workflows/test.yml
```

controlla la sintassi, costruisce l'immagine Docker e avvia Compose eseguendo test HTTP su accesso, movimenti e backup.

Il workflow utilizza un runner Linux standard e non pubblica l'app.

import calendar, datetime as dt, hashlib, hmac, json, os, secrets, sqlite3, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from zoneinfo import ZoneInfo
from urllib.parse import urlparse, parse_qs

ROOT=Path(__file__).parent; DATA=Path(os.getenv('DATA_DIR','/data')); DATA.mkdir(parents=True,exist_ok=True)
DB=DATA/'spese.sqlite3'; COOKIE='spese_session'; TZ=ZoneInfo(os.getenv('TZ','Europe/Rome'))
COOKIE_FLAGS='; HttpOnly; SameSite=Lax; Path=/' + ('' if os.getenv('DEPLOY_MODE')=='lan-http' else '; Secure')
def now(): return dt.datetime.now(TZ)
def today(): return now().date()
def connect():
 c=sqlite3.connect(DB); c.row_factory=sqlite3.Row; c.execute('PRAGMA foreign_keys=ON'); c.execute('PRAGMA journal_mode=WAL'); return c
def init():
 with connect() as c:
  c.executescript('''CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY,username TEXT UNIQUE NOT NULL,email TEXT,passhash TEXT NOT NULL,admin INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,expires TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS accounts(id INTEGER PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,name TEXT NOT NULL,opening_cents INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS categories(id INTEGER PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,name TEXT NOT NULL,kind TEXT NOT NULL CHECK(kind IN ('expense','income')));
CREATE TABLE IF NOT EXISTS entries(id INTEGER PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,account_id INTEGER NOT NULL REFERENCES accounts(id),category_id INTEGER NOT NULL REFERENCES categories(id),kind TEXT NOT NULL CHECK(kind IN ('expense','income')),scope TEXT NOT NULL CHECK(scope IN ('personal','household')),amount_cents INTEGER NOT NULL CHECK(amount_cents>0),description TEXT NOT NULL,date TEXT NOT NULL,recurrence_id INTEGER,created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS recurrences(id INTEGER PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,account_id INTEGER NOT NULL REFERENCES accounts(id),category_id INTEGER NOT NULL REFERENCES categories(id),kind TEXT NOT NULL,scope TEXT NOT NULL,amount_cents INTEGER NOT NULL,description TEXT NOT NULL,day INTEGER NOT NULL CHECK(day BETWEEN 1 AND 31),start_month TEXT NOT NULL,occurrences INTEGER,active INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL);
CREATE UNIQUE INDEX IF NOT EXISTS entry_recurrence_date ON entries(recurrence_id,date) WHERE recurrence_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS entries_user_date ON entries(user_id,date);''')
def hashpass(password,salt=None):
 salt=salt or secrets.token_bytes(16); return salt.hex()+':'+hashlib.pbkdf2_hmac('sha256',password.encode(),salt,310000).hex()
def verify(password,stored):
 try: salt,digest=stored.split(':'); return hmac.compare_digest(hashpass(password,bytes.fromhex(salt)),stored)
 except (ValueError,TypeError): return False
def seed(c,uid):
 c.execute('INSERT INTO accounts(user_id,name) VALUES (?,?)',(uid,'Conto principale'))
 for name,kind in [('Alimentari','expense'),('Casa','expense'),('Trasporti','expense'),('Salute','expense'),('Svago','expense'),('Altro','expense'),('Stipendio','income'),('Altre entrate','income')]: c.execute('INSERT INTO categories(user_id,name,kind) VALUES (?,?,?)',(uid,name,kind))
def create_user(username,password,email='',admin=0):
 if len(username.strip())<3 or len(password)<12: raise ValueError('Nome utente minimo 3 caratteri e password minimo 12 caratteri')
 with connect() as c:
  cur=c.execute('INSERT INTO users(username,email,passhash,admin) VALUES (?,?,?,?)',(username.strip(),email.strip(),hashpass(password),admin)); seed(c,cur.lastrowid)
def monthadd(month,n):
 y,m=map(int,month.split('-')); k=y*12+m-1+n; return f'{k//12:04d}-{k%12+1:02d}'
def materialize(c,uid):
 limit=today().strftime('%Y-%m')
 for r in c.execute('SELECT * FROM recurrences WHERE user_id=? AND active=1',(uid,)).fetchall():
  diff=(int(limit[:4])-int(r['start_month'][:4]))*12+int(limit[5:])-int(r['start_month'][5:])
  for i in range(max(0,min(diff+1,r['occurrences'] or 1200))):
   m=monthadd(r['start_month'],i); y,mo=map(int,m.split('-')); day=min(r['day'],calendar.monthrange(y,mo)[1]); date=f'{m}-{day:02d}'
   if date>today().isoformat(): continue
   c.execute('''INSERT OR IGNORE INTO entries(user_id,account_id,category_id,kind,scope,amount_cents,description,date,recurrence_id,created_at) VALUES (?,?,?,?,?,?,?,?,?,?)''',(uid,r['account_id'],r['category_id'],r['kind'],r['scope'],r['amount_cents'],r['description'],date,r['id'],now().isoformat()))
def integer(value):
 if isinstance(value,bool) or not isinstance(value,int): raise ValueError('Importo non valido')
 return value
def validated_entry(c,uid,d):
 amount=integer(d.get('amount_cents')); account=integer(d.get('account_id')); category=integer(d.get('category_id'))
 if not 0<amount<=100000000000: raise ValueError('Importo non valido')
 kind=d.get('kind'); scope=d.get('scope'); desc=str(d.get('description','')).strip()
 if kind not in ('expense','income') or scope not in ('personal','household') or not 1<=len(desc)<=160: raise ValueError('Dati non validi')
 if not c.execute('SELECT 1 FROM accounts WHERE id=? AND user_id=?',(account,uid)).fetchone(): raise ValueError('Conto non valido')
 if not c.execute('SELECT 1 FROM categories WHERE id=? AND user_id=? AND kind=?',(category,uid,kind)).fetchone(): raise ValueError('Categoria non valida')
 return account,category,kind,scope,amount,desc
def datecheck(s):
 if not isinstance(s,str) or dt.date.fromisoformat(s).isoformat()!=s: raise ValueError('Data non valida')
 return s
def export_data(c,uid):
 return {'version':1,'accounts':[dict(x) for x in c.execute('SELECT id,name,opening_cents FROM accounts WHERE user_id=?',(uid,))], 'categories':[dict(x) for x in c.execute('SELECT id,name,kind FROM categories WHERE user_id=?',(uid,))], 'recurrences':[dict(x) for x in c.execute('SELECT * FROM recurrences WHERE user_id=?',(uid,))], 'entries':[dict(x) for x in c.execute('SELECT * FROM entries WHERE user_id=?',(uid,))]}
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def respond(self,obj,status=200,cookie=None):
  data=json.dumps(obj,ensure_ascii=False).encode(); self.send_response(status); self.send_header('Content-Type','application/json; charset=utf-8'); self.send_header('Cache-Control','no-store'); self.send_header('Content-Length',str(len(data)))
  if cookie:self.send_header('Set-Cookie',cookie)
  self.end_headers(); self.wfile.write(data)
 def body(self):
  size=int(self.headers.get('Content-Length','0'))
  if size>8_000_000: raise ValueError('File troppo grande')
  return json.loads(self.rfile.read(size))
 def user(self,c):
  token=next((x.strip()[len(COOKIE)+1:] for x in self.headers.get('Cookie','').split(';') if x.strip().startswith(COOKIE+'=')),None)
  if not token:return None
  return c.execute('SELECT users.* FROM users JOIN sessions ON sessions.user_id=users.id WHERE sessions.token_hash=? AND sessions.expires>?',(hashlib.sha256(token.encode()).hexdigest(),now().isoformat())).fetchone()
 def do_GET(self):
  path=urlparse(self.path).path
  if path=='/' or path.startswith('/static/'):
   name='index.html' if path=='/' else path[8:]
   if name not in ('index.html','app.js','style.css','manifest.json'):self.send_error(404);return
   data=(ROOT/'static'/name).read_bytes(); self.send_response(200); self.send_header('Content-Type',{'html':'text/html; charset=utf-8','js':'text/javascript; charset=utf-8','css':'text/css; charset=utf-8','json':'application/manifest+json'}[name.split('.')[-1]]);self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data);return
  if path=='/api/health':
   try:
    with connect() as c: c.execute('SELECT 1').fetchone()
    return self.respond({'status':'ok'})
   except sqlite3.Error: return self.respond({'status':'error'},503)
  with connect() as c:
   u=self.user(c)
   if not u:return self.respond({'error':'Accesso richiesto'},401)
   uid=u['id']; materialize(c,uid); c.commit()
   if path=='/api/state':
    entries=[dict(x) for x in c.execute('SELECT e.*,a.name account_name,k.name category_name FROM entries e JOIN accounts a ON a.id=e.account_id JOIN categories k ON k.id=e.category_id WHERE e.user_id=? ORDER BY e.date DESC,e.id DESC',(uid,))]
    return self.respond({'user':{'id':uid,'username':u['username'],'admin':bool(u['admin'])},'accounts':[dict(x) for x in c.execute('SELECT * FROM accounts WHERE user_id=? ORDER BY name',(uid,))],'categories':[dict(x) for x in c.execute('SELECT * FROM categories WHERE user_id=? ORDER BY name',(uid,))],'entries':entries,'recurrences':[dict(x) for x in c.execute('SELECT * FROM recurrences WHERE user_id=? ORDER BY id DESC',(uid,))],'users':[dict(x) for x in c.execute('SELECT id,username,email,admin FROM users ORDER BY id')] if u['admin'] else [],'today':today().isoformat()})
   if path=='/api/export':return self.respond(export_data(c,uid))
   if path=='/api/suggest':
    q=parse_qs(urlparse(self.path).query).get('q',[''])[0].strip().lower()[:100]
    if len(q)<2:return self.respond([])
    rows=c.execute('''SELECT lower(description) normalized,description,category_id,kind,COUNT(*) n FROM entries WHERE user_id=? AND lower(description) LIKE ? GROUP BY normalized,category_id,kind ORDER BY CASE WHEN normalized=? THEN 0 ELSE 1 END,n DESC LIMIT 8''',(uid,q+'%',q)).fetchall()
    return self.respond([dict(x) for x in rows])
  self.respond({'error':'Non trovato'},404)
 def do_POST(self):
  try:
   d=self.body(); path=urlparse(self.path).path
   with connect() as c:
    if path=='/api/login':
     u=c.execute('SELECT * FROM users WHERE username=?',(str(d.get('username','')).strip(),)).fetchone()
     if not u or not verify(str(d.get('password','')),u['passhash']):return self.respond({'error':'Credenziali non valide'},401)
     token=secrets.token_urlsafe(32); c.execute('INSERT INTO sessions VALUES (?,?,?)',(hashlib.sha256(token.encode()).hexdigest(),u['id'],(now()+dt.timedelta(days=30)).isoformat()));return self.respond({'ok':True},cookie=f'{COOKIE}={token}{COOKIE_FLAGS}; Max-Age=2592000')
    u=self.user(c)
    if not u:return self.respond({'error':'Accesso richiesto'},401)
    uid=u['id']
    if path=='/api/logout':
     token=next((x.strip()[len(COOKIE)+1:] for x in self.headers.get('Cookie','').split(';') if x.strip().startswith(COOKIE+'=')),None)
     if token:c.execute('DELETE FROM sessions WHERE token_hash=?',(hashlib.sha256(token.encode()).hexdigest(),))
     return self.respond({'ok':True},cookie=f'{COOKIE}={COOKIE_FLAGS}; Max-Age=0')
    if path=='/api/entry':
     a,k,kind,scope,amount,desc=validated_entry(c,uid,d); date=datecheck(d.get('date'))
     c.execute('INSERT INTO entries(user_id,account_id,category_id,kind,scope,amount_cents,description,date,created_at) VALUES (?,?,?,?,?,?,?,?,?)',(uid,a,k,kind,scope,amount,desc,date,now().isoformat()))
    elif path=='/api/account':
     name=str(d.get('name','')).strip(); opening=integer(d.get('opening_cents',0))
     if not 1<=len(name)<=80:raise ValueError('Nome conto non valido')
     c.execute('INSERT INTO accounts(user_id,name,opening_cents) VALUES (?,?,?)',(uid,name,opening))
    elif path=='/api/category':
     name=str(d.get('name','')).strip(); kind=d.get('kind')
     if not 1<=len(name)<=80 or kind not in ('expense','income'):raise ValueError('Categoria non valida')
     c.execute('INSERT INTO categories(user_id,name,kind) VALUES (?,?,?)',(uid,name,kind))
    elif path=='/api/recurrence':
     a,k,kind,scope,amount,desc=validated_entry(c,uid,d); day=integer(d.get('day')); count=d.get('occurrences')
     if not 1<=day<=31 or (count is not None and not 1<=integer(count)<=1200):raise ValueError('Ricorrenza non valida')
     month=str(d.get('start_month',''))
     if len(month)!=7 or dt.date.fromisoformat(month+'-01').strftime('%Y-%m')!=month:raise ValueError('Mese non valido')
     c.execute('INSERT INTO recurrences(user_id,account_id,category_id,kind,scope,amount_cents,description,day,start_month,occurrences,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',(uid,a,k,kind,scope,amount,desc,day,month,count,now().isoformat())); materialize(c,uid)
    elif path=='/api/user':
     if not u['admin']:return self.respond({'error':'Permesso negato'},403)
     username=str(d.get('username','')).strip(); password=str(d.get('password',''));email=str(d.get('email','')).strip()
     if len(username)<3 or len(password)<12:raise ValueError('Nome minimo 3 caratteri e password minimo 12 caratteri')
     cur=c.execute('INSERT INTO users(username,email,passhash) VALUES (?,?,?)',(username,email,hashpass(password)));seed(c,cur.lastrowid)
    elif path=='/api/restore':
     if d.get('version')!=1 or not all(isinstance(d.get(t),list) for t in ('accounts','categories','entries','recurrences')):raise ValueError('Backup non valido')
     if len(d['entries'])>100000 or len(d['recurrences'])>10000:raise ValueError('Backup troppo grande')
     # Validate in one transaction; existing user data remains intact on failure.
     c.execute('DELETE FROM entries WHERE user_id=?',(uid,));c.execute('DELETE FROM recurrences WHERE user_id=?',(uid,));c.execute('DELETE FROM categories WHERE user_id=?',(uid,));c.execute('DELETE FROM accounts WHERE user_id=?',(uid,))
     accounts={};categories={};recs={}
     for row in d['accounts']:
      old=integer(row['id']);name=str(row['name']);opening=integer(row['opening_cents']);
      if old in accounts or not 1<=len(name)<=80:raise ValueError('Conto nel backup non valido')
      accounts[old]=c.execute('INSERT INTO accounts(user_id,name,opening_cents) VALUES (?,?,?)',(uid,name,opening)).lastrowid
     for row in d['categories']:
      old=integer(row['id']);name=str(row['name']);kind=row['kind']
      if old in categories or not 1<=len(name)<=80 or kind not in ('expense','income'):raise ValueError('Categoria nel backup non valida')
      categories[old]=c.execute('INSERT INTO categories(user_id,name,kind) VALUES (?,?,?)',(uid,name,kind)).lastrowid
     for row in d['recurrences']:
      old=integer(row['id']);count=row['occurrences']; day=integer(row['day']);month=row['start_month'];amount=integer(row['amount_cents']);kind=row['kind'];scope=row['scope']
      if old in recs or not 1<=day<=31 or len(month)!=7 or dt.date.fromisoformat(month+'-01').strftime('%Y-%m')!=month or count is not None and not 1<=integer(count)<=1200 or amount<=0 or kind not in ('expense','income') or scope not in ('personal','household') or row['category_id'] not in categories or row['account_id'] not in accounts: raise ValueError('Ricorrenza nel backup non valida')
      if not any(x['id']==row['category_id'] and x['kind']==kind for x in d['categories']):raise ValueError('Categoria ricorrenza non valida')
      recs[old]=c.execute('INSERT INTO recurrences(user_id,account_id,category_id,kind,scope,amount_cents,description,day,start_month,occurrences,active,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',(uid,accounts[row['account_id']],categories[row['category_id']],kind,scope,amount,str(row['description'])[:160],day,month,count,1 if row['active'] else 0,row['created_at'])).lastrowid
     for row in d['entries']:
      datecheck(row['date']);kind=row['kind'];scope=row['scope'];amount=integer(row['amount_cents'])
      if amount<=0 or row['account_id'] not in accounts or row['category_id'] not in categories or row['recurrence_id'] is not None and row['recurrence_id'] not in recs or kind not in ('expense','income') or scope not in ('personal','household') or not any(x['id']==row['category_id'] and x['kind']==kind for x in d['categories']):raise ValueError('Movimento nel backup non valido')
      c.execute('INSERT INTO entries(user_id,account_id,category_id,kind,scope,amount_cents,description,date,recurrence_id,created_at) VALUES (?,?,?,?,?,?,?,?,?,?)',(uid,accounts[row['account_id']],categories[row['category_id']],kind,scope,amount,str(row['description'])[:160],row['date'],recs.get(row['recurrence_id']) if row['recurrence_id'] is not None else None,row['created_at']))
    else:return self.respond({'error':'Non trovato'},404)
    return self.respond({'ok':True})
  except (ValueError,KeyError,TypeError,sqlite3.IntegrityError) as e:return self.respond({'error':str(e)},400)
 def do_DELETE(self):
  path=urlparse(self.path).path.split('/')
  if len(path)!=4 or path[1]!='api' or path[2] not in ('entry','recurrence'):return self.respond({'error':'Non trovato'},404)
  try: obj=int(path[3])
  except ValueError:return self.respond({'error':'ID non valido'},400)
  with connect() as c:
   u=self.user(c)
   if not u:return self.respond({'error':'Accesso richiesto'},401)
   if path[2]=='entry':
    row=c.execute('SELECT recurrence_id FROM entries WHERE id=? AND user_id=?',(obj,u['id'])).fetchone()
    if row and row['recurrence_id']:return self.respond({'error':'Disattiva la ricorrenza per interrompere i futuri addebiti'},400)
    c.execute('DELETE FROM entries WHERE id=? AND user_id=?',(obj,u['id']))
   else:c.execute('UPDATE recurrences SET active=0 WHERE id=? AND user_id=?',(obj,u['id']))
   return self.respond({'ok':True})
if __name__=='__main__':
 init()
 if len(sys.argv)>1 and sys.argv[1]=='create-user':
  create_user(sys.argv[2],sys.argv[3],sys.argv[4] if len(sys.argv)>4 else '',int(sys.argv[5]) if len(sys.argv)>5 else 0);print('Utente creato')
 else:ThreadingHTTPServer(('0.0.0.0',8080),Handler).serve_forever()

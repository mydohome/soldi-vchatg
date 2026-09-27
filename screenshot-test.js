const { chromium, devices } = require('playwright');
async function login(context) {
  const response=await context.request.post('http://localhost:18080/api/login',{data:{username:'admin',password:'password-di-test-lunga'}});
  if (!response.ok()) throw Error('Login failed');
  const token=response.headers()['set-cookie'].match(/spese_session=([^;]+)/)[1];
  await context.addCookies([{name:'spese_session',value:token,url:'http://localhost:18080',httpOnly:true,sameSite:'Lax'}]);
}
(async () => {
  const browser = await chromium.launch({headless:true});
  const context = await browser.newContext({...devices['iPhone 13'], baseURL:'http://localhost:18080', ignoreHTTPSErrors:true});
  const page = await context.newPage();
  const errors=[]; page.on('pageerror',e=>errors.push(e.message));
  await login(context);
  await page.goto('/');
  await page.locator('#quick').waitFor({state:'visible'});
  const state=await (await page.request.get('/api/state')).json();
  const account=state.accounts[0].id, category=state.categories.find(c=>c.kind==='expense').id;
  for (const [i,amount,scope] of [[1,3250,'personal'],[2,7990,'household'],[3,1450,'personal']]) {
    const response=await page.request.post('/api/entry',{data:{account_id:account,category_id:category,kind:'expense',scope,amount_cents:amount,description:['','Pranzo','Spesa supermercato','Trasporto'][i],date:state.today}});
    if (!response.ok()) throw Error('Fixture failed: '+await response.text());
  }
  await page.reload(); await page.locator('#quick').waitFor({state:'visible'});
  await page.screenshot({path:'screenshots/iphone-dashboard.png',fullPage:true});
  await page.locator('[data-page=movements]').click();
  await page.waitForTimeout(300);
  await page.screenshot({path:'screenshots/iphone-movimenti.png',fullPage:true});
  await page.locator('#quick').click();
  await page.locator('#editor').waitFor({state:'visible'});
  await page.screenshot({path:'screenshots/iphone-nuova-spesa.png',fullPage:true});
  const personalColor=await page.locator('.scope-personal span').evaluate(el=>getComputedStyle(el).backgroundColor);
  await page.locator('.scope-household span').click();
  await page.waitForTimeout(300);
  const houseColor=await page.locator('.scope-household span').evaluate(el=>getComputedStyle(el).backgroundColor);
  if (personalColor===houseColor || !await page.locator('[name=scope][value=household]').isChecked()) throw Error('Switch ambito non funziona');
  await page.screenshot({path:'screenshots/iphone-casa.png',fullPage:true});
  const save=await page.locator('#entryForm > button:last-child').boundingBox();
  if (!save || save.y+save.height>devices['iPhone 13'].viewport.height) throw Error('Pulsante Salva non visibile su iPhone');
  await page.locator('#close').click();
  await page.locator('[data-page=settings]').click();
  await page.waitForTimeout(300);
  await page.screenshot({path:'screenshots/iphone-impostazioni.png',fullPage:true});
  if (errors.length) throw Error(errors.join('\n'));
  await browser.close();
  const desktop=await chromium.launch({headless:true});
  const dc=await desktop.newContext({viewport:{width:1440,height:900},baseURL:'http://localhost:18080'});
  await login(dc); const p=await dc.newPage(); await p.goto('/');await p.locator('#quick').waitFor({state:'visible'});
  await p.screenshot({path:'screenshots/desktop-dashboard.png',fullPage:true}); await desktop.close();
})().catch(e=>{console.error(e);process.exit(1)});

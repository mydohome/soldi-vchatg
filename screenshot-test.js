const { chromium, devices } = require('playwright');
(async () => {
  const browser = await chromium.launch({headless:true});
  const context = await browser.newContext({...devices['iPhone 13'], baseURL:'http://localhost:18080', ignoreHTTPSErrors:true});
  const page = await context.newPage();
  const errors=[]; page.on('pageerror',e=>errors.push(e.message));
  await page.goto('/');
  await page.locator('#loginForm [name=username]').fill('admin');
  await page.locator('#loginForm [name=password]').fill('password-di-test-lunga');
  await page.locator('#loginForm button').click();
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
  await page.screenshot({path:'screenshots/iphone-movimenti.png',fullPage:true});
  await page.locator('#quick').click();
  await page.locator('#editor').waitFor({state:'visible'});
  await page.screenshot({path:'screenshots/iphone-nuova-spesa.png',fullPage:true});
  if (errors.length) throw Error(errors.join('\n'));
  await browser.close();
  const desktop=await chromium.launch({headless:true});
  const dc=await desktop.newContext({viewport:{width:1440,height:900},baseURL:'http://localhost:18080'});
  const p=await dc.newPage(); await p.goto('/');
  await p.locator('#loginForm [name=username]').fill('admin'); await p.locator('#loginForm [name=password]').fill('password-di-test-lunga');await p.locator('#loginForm button').click();await p.locator('#quick').waitFor({state:'visible'});
  await p.screenshot({path:'screenshots/desktop-dashboard.png',fullPage:true}); await desktop.close();
})().catch(e=>{console.error(e);process.exit(1)});

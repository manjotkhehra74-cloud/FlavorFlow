const {chromium:pw}=require('playwright-core');
// Run against a local static preview. Requires playwright-core and a Chromium binary.
const baseURL=process.env.LANDING_URL||'http://127.0.0.1:3000';
const assert=require('node:assert/strict');
(async()=>{
const browser=await pw.launch({executablePath:process.env.CHROMIUM_EXECUTABLE,args:['--no-sandbox','--disable-dev-shm-usage'],headless:true});
const page=await browser.newPage({viewport:{width:1440,height:1000}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
await page.route('**/api/saas/plans',r=>r.fulfill({json:{trialDays:10,tiers:{basic:{monthly:999,yearly:9990,features:['HRMate integration']},pro:{monthly:1999,yearly:19990},enterprise:{monthly:3999,yearly:39990}}}}));
await page.route('**/api/saas/lead',r=>r.fulfill({json:{ok:true}}));
await page.goto(baseURL);
await page.waitForFunction(()=>document.getElementById('reg-title').textContent.includes('10-day'));
assert(!/hrmate|integrations?/i.test(await page.locator('body').innerText()));
assert.equal(await page.locator('[data-play-store]').first().getAttribute('aria-disabled'),'true');
assert.equal(await page.locator('[data-play-store]').first().getAttribute('href'),null);
assert.equal(await page.locator('[data-play-qr] svg').count(),0);
assert.equal(await page.locator('[data-windows-store]').getAttribute('aria-disabled'),'true');
assert((await page.locator('[data-windows-store]').innerText()).includes('Download for Windows'));
assert.equal(await page.locator('[data-windows-store]').getAttribute('href'),null);
assert.equal(await page.locator('a[href$=".apk"]').count(),0);
const playURL='https://play.google.com/store/apps/details?id=in.flavorflow.flavorflow_erp';
// Simulate an approved listing locally; production config remains blank/pending.
await page.evaluate(url=>FlavorFlowDistribution.configure({androidPackageId:'in.flavorflow.flavorflow_erp',playStoreUrl:url}),playURL);
assert.equal(await page.locator('[data-play-store]').first().getAttribute('href'),playURL);
assert.equal(await page.locator('[data-play-qr]').getAttribute('data-qr-url'),playURL);
assert.equal(await page.locator('[data-play-qr] svg').count(),1);
await page.evaluate(()=>FlavorFlowDistribution.configure({androidPackageId:'in.flavorflow.flavorflow_erp',playStoreUrl:'https://play.google.com/store/apps/details?id=wrong.app'}));
assert.equal(await page.locator('[data-play-store]').first().getAttribute('href'),null);
assert.equal(await page.locator('[data-play-qr] svg').count(),0);

assert.equal(await page.locator('header img.brand-mark').getAttribute('src'),'/assets/flavorflow-logo-v2.png');
assert.equal(await page.locator('footer img.brand-mark').getAttribute('src'),'/assets/flavorflow-logo-v2.png');
await page.waitForFunction(()=>Array.from(document.querySelectorAll('img.brand-mark')).every(img=>img.complete&&img.naturalWidth>0));
for(const asset of ['flavorflow-logo-v2.png','favicon-32-v2.png','favicon-48-v2.png','apple-touch-icon-v2.png']){
  const response=await page.request.get(baseURL+'/assets/'+asset);assert(response.ok(),asset);
}
assert.equal(await page.locator('link[rel="icon"][sizes="32x32"]').getAttribute('href'),'/assets/favicon-32-v2.png');
// Main navigation and footer expose support, and preview links open the local design.
assert.equal(await page.locator('[data-support-link]').count(),2);
for (const link of await page.locator('[data-support-link]').all()) assert.equal(await link.getAttribute('href'),'/support/');
// Enterprise homepage: local assets, accessible capabilities and mobile navigation.
for (const asset of ['landing.css','site.js','fonts/inter-regular.woff2','fonts/inter-semibold.woff2','fonts/inter-bold.woff2']) {
  assert((await page.request.get(baseURL+'/assets/'+asset)).ok(),asset);
}
assert.equal(await page.locator('.module-tab').count(),6);
for (const tab of await page.locator('.module-tab').all()) {
  await tab.click();
  assert.equal(await tab.getAttribute('aria-selected'),'true');
  assert.equal(await page.locator('.module-panel:visible').count(),1);
  assert(await page.locator('#'+await tab.getAttribute('aria-controls')).isVisible());
}
await page.locator('#tab-production').click();
await page.locator('#tab-production').focus();
await page.keyboard.press('ArrowDown');
assert.equal(await page.locator('#tab-inventory').getAttribute('aria-selected'),'true');
assert(await page.locator('#tab-inventory').evaluate(el=>el===document.activeElement));
await page.keyboard.press('End');
assert.equal(await page.locator('#tab-controls').getAttribute('aria-selected'),'true');
await page.keyboard.press('ArrowDown');
assert.equal(await page.locator('#tab-production').getAttribute('aria-selected'),'true');
await page.setViewportSize({width:375,height:850});
await page.locator('#menu-toggle').click();
assert.equal(await page.locator('#menu-toggle').getAttribute('aria-expanded'),'true');
assert(await page.locator('#main-navigation').isVisible());
await page.keyboard.press('Escape');
assert.equal(await page.locator('#menu-toggle').getAttribute('aria-expanded'),'false');
assert(!await page.locator('#main-navigation').isVisible());
await page.locator('#menu-toggle').click();
await page.locator('#main-navigation a[href="#features"]').click();
assert.equal(await page.locator('#menu-toggle').getAttribute('aria-expanded'),'false');
assert.equal(await page.locator('.module-tabs').getAttribute('aria-orientation'),'horizontal');
await page.locator('#tab-production').focus();
await page.keyboard.press('ArrowRight');
assert.equal(await page.locator('#tab-inventory').getAttribute('aria-selected'),'true');
await page.setViewportSize({width:1440,height:1000});
await page.locator('#tab-production').click();
assert.equal(await page.locator('.module-tabs').getAttribute('aria-orientation'),'vertical');

const paymentCopy=await page.locator('#payment-options').innerText();
for(const method of ['NEFT','IMPS','RTGS','cheque','UPI','net banking','UPI AutoPay','eNACH'])assert(paymentCopy.includes(method),method);
assert(paymentCopy.includes('setup pending'));
assert(paymentCopy.includes('Credit/debit card payments are not offered'));
assert(paymentCopy.includes('explicit customer authorisation'));
assert(!paymentCopy.includes('activated the same day'));
const dataFAQ=page.locator('#faq details').filter({has:page.locator('summary', {hasText:'Where is my company’s data stored?'})});
await dataFAQ.locator('summary').click();
assert((await dataFAQ.innerText()).includes('hosted server'));
const paymentFAQ=page.locator('#faq details').filter({has:page.locator('summary', {hasText:'How do I pay after the trial?'})});
await paymentFAQ.locator('summary').click();
assert((await paymentFAQ.innerText()).includes('Credit/debit cards are not offered'));

await page.locator('#cyc-y').click();assert.equal(await page.locator('[data-tier="basic"] .amt').innerText(),'833');
await page.locator('[data-tier="pro"] .btn').click();assert.equal(await page.locator('#r-plan').inputValue(),'pro-yearly');
assert(await page.locator('#m-reg').isVisible());await page.keyboard.press('Escape');assert(!await page.locator('#m-reg').isVisible());
await page.locator('.hero button').first().click();
await page.locator('#r-co').fill('Sample Factory');await page.locator('#r-name').fill('Demo Owner');await page.locator('#r-ph').fill('9876543210');await page.locator('#r-em').fill('demo@example.com');await page.locator('#r-pw').fill('Example123!');
await page.route('**/api/saas/register',r=>r.fulfill({status:400,json:{error:'Company already exists'}}));
await page.locator('#r-go').click();await page.locator('#r-msg').filter({hasText:'Company already exists'}).waitFor();assert.equal(new URL(page.url()).pathname,'/');assert(await page.locator('#r-go').isEnabled());
await page.unroute('**/api/saas/register');await page.route('**/api/saas/register',r=>r.fulfill({json:{companyCode:'sample-factory',serverUrl:'https://example.com/erp',trialEnds:'2026-10-23'}}));await page.locator('#r-go').click();await page.locator('#r-res.show').waitFor();assert.equal(await page.locator('#r-code').innerText(),'sample-factory');await page.keyboard.press('Escape');
for(const width of [320,375,390,580,768,1024,1280,1440]){await page.setViewportSize({width,height:900});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),`overflow at ${width}`)}
await page.setViewportSize({width:375,height:850});await page.goto(baseURL);
await page.locator('.hero button').nth(1).click();await page.locator('#d-name').fill('Demo Owner');await page.locator('#d-co').fill('Demo Factory');await page.locator('#d-ph').fill('9876543210');await page.locator('#d-go').click();await page.waitForURL('**/demo.html');assert.equal(await page.locator('a[href$=".apk"]').count(),0);assert.equal(await page.locator('[data-play-store]').getAttribute('aria-disabled'),'true');
await page.goto(baseURL);await page.locator('#menu-toggle').click();await page.locator('#main-navigation [data-support-link]').click();await page.waitForURL('**/support/');assert.equal(await page.title(),'Support Centre | FlavorFlow ERP');
assert.equal(errors.length,0,errors.join('\n'));console.log('PASS: enterprise tabs (click/keyboard), mobile menu, local styles/fonts, ERP-only copy, live prices/trial, plan selection, dialogs, registration errors/success, demo navigation, logo/favicon assets, Play Store pending/live validation and QR, mobile widths, no JS errors.');
await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});

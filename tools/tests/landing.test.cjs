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

await page.locator('#cyc-y').click();assert.equal(await page.locator('[data-tier="basic"] .amt').innerText(),'833');
await page.locator('[data-tier="pro"] .btn').click();assert.equal(await page.locator('#r-plan').inputValue(),'pro-yearly');
assert(await page.locator('#m-reg').isVisible());await page.keyboard.press('Escape');assert(!await page.locator('#m-reg').isVisible());
await page.locator('.hero button').first().click();
await page.locator('#r-co').fill('Sample Factory');await page.locator('#r-name').fill('Demo Owner');await page.locator('#r-ph').fill('9876543210');await page.locator('#r-em').fill('demo@example.com');await page.locator('#r-pw').fill('Example123!');
await page.route('**/api/saas/register',r=>r.fulfill({status:400,json:{error:'Company already exists'}}));
await page.locator('#r-go').click();await page.locator('#r-msg').filter({hasText:'Company already exists'}).waitFor();assert.equal(page.url(),baseURL+'/');assert(await page.locator('#r-go').isEnabled());
await page.unroute('**/api/saas/register');await page.route('**/api/saas/register',r=>r.fulfill({json:{companyCode:'sample-factory',serverUrl:'https://example.com/erp',trialEnds:'2026-10-23'}}));await page.locator('#r-go').click();await page.locator('#r-res.show').waitFor();assert.equal(await page.locator('#r-code').innerText(),'sample-factory');await page.keyboard.press('Escape');
for(const width of [320,375,768,1440]){await page.setViewportSize({width,height:900});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),`overflow at ${width}`)}
await page.setViewportSize({width:375,height:850});await page.goto(baseURL);
await page.locator('.hero button').nth(1).click();await page.locator('#d-name').fill('Demo Owner');await page.locator('#d-co').fill('Demo Factory');await page.locator('#d-ph').fill('9876543210');await page.locator('#d-go').click();await page.waitForURL('**/demo.html');
assert.equal(errors.length,0,errors.join('\n'));console.log('PASS: ERP-only copy, live prices/trial, plan selection, dialogs, registration errors/success, demo navigation, mobile widths, no JS errors.');
await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});

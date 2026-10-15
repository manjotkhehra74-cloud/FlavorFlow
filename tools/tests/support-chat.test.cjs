// Browser integration tests use a stub vendor script; never send actual chats.
const { chromium } = require('playwright-core');
const assert = require('node:assert/strict');
const base = process.env.LANDING_URL || 'http://127.0.0.1:3000';
const embed = 'https://embed.tawk.to/6ad0c458b841da34cc9dcaef/1k4vntur2';
(async () => {
  const browser = await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE, args:['--no-sandbox'],headless:true});
  try {
    const page = await browser.newPage();
    const errors = [], provider = [];
    page.on('pageerror', e => errors.push(e.message));
    page.on('request', r => { if (r.url().includes('tawk.to')) provider.push(r.url()); });
    await page.route('https://embed.tawk.to/**', route => route.fulfill({contentType:'application/javascript',body:'window.openCount=0; Tawk_API.showWidget=()=>{}; Tawk_API.maximize=()=>{window.openCount++}; setTimeout(()=>Tawk_API.onLoad(),50);'}));
    await page.goto(base+'/support/');
    assert.equal(provider.length,0,'No third-party requests before customer action');
    assert.equal(await page.locator('#live-chat-link').getAttribute('role'),'button');
    await page.locator('#live-chat-link').click();
    await page.locator('#live-chat-link').click();
    await page.waitForFunction(()=>window.openCount >= 1);
    assert.deepEqual(provider,[embed]);
    await page.locator('#live-chat-link').focus();
    await page.keyboard.press('Space');
    await page.waitForFunction(()=>window.openCount >= 2);
    assert.equal(provider.length,1,'Repeated clicks reuse widget');
    assert((await page.locator('#chat-feedback').innerText()).includes('Chat opened'));
    assert.equal(await page.locator('#support-call-link').getAttribute('href'),'tel:+919501606877');
    assert((await page.locator('#support-email-link').getAttribute('href')).startsWith('mailto:support%40'));
    assert.equal(await page.locator('.help-article').count(),18);
    // Unapproved script URLs cannot be injected through settings.
    await page.evaluate(()=>FlavorFlowSupportContacts.configure({tawkEmbedUrl:'https://evil.example/widget.js'}));
    assert.equal(await page.locator('#live-chat-link').getAttribute('aria-disabled'),'true');
    // Provider blocked: friendly fallback and retry, preserving email/call.
    const blocked = await browser.newPage();
    await blocked.route('https://embed.tawk.to/**',r=>r.abort());
    await blocked.goto(base+'/support/');
    await blocked.locator('#live-chat-link').click();
    await blocked.waitForFunction(()=>document.querySelector('#chat-feedback').textContent.includes('could not load'));
    await blocked.unroute('https://embed.tawk.to/**');
    await blocked.route('https://embed.tawk.to/**',r=>r.fulfill({contentType:'application/javascript',body:'Tawk_API.showWidget=()=>{};Tawk_API.maximize=()=>{};Tawk_API.onLoad();'}));
    await blocked.locator('#live-chat-link').click();
    await blocked.waitForFunction(()=>document.querySelector('#chat-feedback').textContent.includes('Chat opened'));
    // Provider script loads but never calls ready: timeout, not a fake open.
    const stalled = await browser.newPage();
    await stalled.clock.install();
    await stalled.route('https://embed.tawk.to/**',r=>r.fulfill({contentType:'application/javascript',body:'/* stalled provider */'}));
    await stalled.goto(base+'/support/');
    await stalled.locator('#live-chat-link').click();
    await stalled.clock.fastForward(16000);
    assert((await stalled.locator('#chat-feedback').innerText()).includes('could not load'));
    assert.equal(errors.length,0,errors.join('\n'));
    console.log('PASS: exact supplied embed, lazy loading, open/reopen, keyboard, no duplicate script, URL allowlist, blocked/timeout fallback, retry, email/phone preserved. Vendor stub only; real message/reply test still required.');
  } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exit(1)});

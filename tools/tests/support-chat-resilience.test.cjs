// Failure/recovery regression tests: vendor stub only, never real chats.
const { chromium } = require('playwright-core');
const assert = require('node:assert/strict');
const base = process.env.LANDING_URL || 'http://127.0.0.1:3000';
const embed = 'https://embed.tawk.to/6ad0c458b841da34cc9dcaef/1k4vntur2';
const readyStub = 'window.opens=0; window.starts=0; Tawk_API.start=()=>{starts++}; Tawk_API.showWidget=()=>{}; Tawk_API.maximize=()=>{opens++};';
(async () => {
  const browser = await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE,args:['--no-sandbox'],headless:true});
  try {
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror',e=>errors.push(e.message));
    await page.clock.install();
    let loads = 0;
    await page.route(embed, r=>{loads++;return r.fulfill({contentType:'application/javascript',body:readyStub+'setTimeout(()=>Tawk_API.onLoad(),25000);'});});
    await page.goto(base+'/support/');
    await page.waitForFunction(()=>typeof window.opens==='number');
    await page.clock.fastForward(16000);
    assert((await page.locator('#chat-feedback').innerText()).includes('could not load'));
    await page.locator('#support-reconnect > summary').click();
    await page.locator('#support-chat-retry').click();
    assert.equal(loads,1,'Timeout retry must not inject a duplicate widget');
    await page.clock.fastForward(10000);
    assert.equal(await page.evaluate(()=>window.opens),1,'Late onLoad still opens widget after timeout');
    // A loaded chat can go offline; launcher, email and phone do not disappear.
    await page.evaluate(()=>{
      Object.defineProperty(navigator,'onLine',{value:false,configurable:true});
      window.dispatchEvent(new Event('offline'));
    });
    await page.locator('#support-chat-retry').click();
    assert((await page.locator('#support-reconnect-status').innerText()).includes('offline'));
    assert.equal(await page.evaluate(()=>window.opens),1);
    await page.evaluate(()=>{
      Object.defineProperty(navigator,'onLine',{value:true,configurable:true});
      window.dispatchEvent(new Event('online'));
    });
    assert.equal(await page.evaluate(()=>window.opens),1,'Network recovery must not force ready widget open');
    await page.locator('#support-chat-retry').click();
    assert.equal(await page.evaluate(()=>window.opens),2);
    assert.equal(await page.evaluate(()=>window.starts),2,'One initialization retry and one manual reconnect');
    assert.equal(loads,1);
    // Missing/throwing provider APIs are surfaced, not treated as successful delivery.
    await page.evaluate(()=>{Tawk_API.maximize=()=>{throw new Error('disconnected')};});
    await page.locator('#support-chat-retry').click();
    assert((await page.locator('#support-reconnect-status').innerText()).includes('unavailable'));
    assert(await page.locator('#support-reconnect a[href^="mailto:"]').isVisible());
    assert(await page.locator('#support-reconnect a[href^="tel:"]').isVisible());
    for (const width of [320,375,768,1440]) {
      await page.setViewportSize({width,height:850});
      assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
      const rect = await page.locator('#support-reconnect > summary').boundingBox();
      assert(rect && rect.x>=0 && rect.x+rect.width<=width && rect.y>=0);
    }
    // Start offline: no request until network returns, then auto-open only once.
    const offline = await browser.newPage();
    await offline.addInitScript(()=>Object.defineProperty(navigator,'onLine',{get:()=>window.testOnline===true,configurable:true}));
    let offlineLoads=0;
    await offline.route(embed,r=>{offlineLoads++;return r.fulfill({contentType:'application/javascript',body:readyStub+'Tawk_API.onLoad();'});});
    await offline.goto(base+'/support/');
    assert.equal(offlineLoads,0);
    await offline.evaluate(()=>{window.testOnline=true;window.dispatchEvent(new Event('online'));});
    await offline.waitForFunction(()=>window.opens===1);
    assert.equal(offlineLoads,1);
    // Provider scripts blocked entirely: native launcher and fallback remain available.
    const blocked = await browser.newPage();
    await blocked.route('**/assets/support-chat.js*',r=>r.abort());
    await blocked.route(embed,r=>r.abort());
    await blocked.goto(base+'/support/');
    await blocked.locator('#support-reconnect > summary').click();
    assert(await blocked.locator('#support-reconnect a[href^="mailto:"]').isVisible());
    assert(await blocked.locator('#support-reconnect a[href^="tel:"]').isVisible());
    assert.equal(await blocked.locator('#support-chat-retry').isVisible(),false);
    assert.equal(errors.length,0,errors.join('\n'));
    console.log('PASS: persistent native support launcher, late readiness after timeout, deduplicated retry, network offline/online, manual socket restart, throwing APIs, responsive launcher, blocked-loader fallback. Vendor stub only.');
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});

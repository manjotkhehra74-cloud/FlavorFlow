// Chatwoot integration tests. Stub SDK only: never create provider contacts or send messages.
const { chromium } = require('playwright-core');
const assert = require('node:assert/strict');
const base = process.env.LANDING_URL || 'http://127.0.0.1:3000';
const SDK = 'https://app.chatwoot.com/packs/js/sdk.js';
const token = 'gSkACYN5CHoy4WnpSdPjgfvT';
const stub = (delay=0) => `
window.runs=0; window.resets=0; window.opens=0; window.order=[];
window.chatwootSDK={run:function(options){
  runs++; window.runOptions=options;
  window.historyMessages=JSON.parse(localStorage.getItem('test-chat-messages')||'[]');
  window.$chatwoot={
    reset:function(){resets++;order.push('reset');historyMessages=[];localStorage.removeItem('test-chat-messages');window.dispatchEvent(new Event('chatwoot:ready'));},
    toggleBubbleVisibility:function(state){order.push('bubble:'+state);},
    toggle:function(state){if(state==='open'){opens++;order.push('open');window.visibleMessages=historyMessages.slice();}}
  };
  setTimeout(()=>window.dispatchEvent(new Event('chatwoot:ready')),${delay});
}};`;
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE,args:['--no-sandbox'],headless:true});
 try {
  const page=await browser.newPage(); const errors=[],requests=[];
  page.on('pageerror',e=>errors.push(e.message));
  page.on('request',r=>requests.push(r.url()));
  await page.route(SDK,r=>r.fulfill({contentType:'application/javascript',body:stub()}));
  await page.goto(base+'/support/');
  await page.waitForFunction(()=>window.opens===1);
  assert.equal(await page.evaluate(()=>runs),1);
  assert.equal(await page.evaluate(()=>resets),1,'Reset ready-event recursion must not loop');
  assert.deepEqual(await page.evaluate(()=>runOptions),{websiteToken:token,baseUrl:'https://app.chatwoot.com'});
  assert.deepEqual(await page.evaluate(()=>order),['reset','bubble:show','open']);
  assert.equal(await page.evaluate(()=>chatwootSettings.position),'right');
  assert.equal(await page.evaluate(()=>chatwootSettings.hideMessageBubble),true);
  assert.equal(requests.filter(x=>x===SDK).length,1);
  assert(!requests.some(x=>/tawk\./i.test(x)),'No tawk.to request');
  await page.locator('#live-chat-link').click();
  await page.locator('#live-chat-link').focus();await page.keyboard.press('Space');
  assert.equal(await page.evaluate(()=>resets),1,'Manual reopen must preserve current conversation');
  assert.equal(requests.filter(x=>x===SDK).length,1);
  // Same-tab refresh must reset restored messages before the widget is opened.
  await page.evaluate(()=>localStorage.setItem('test-chat-messages',JSON.stringify(['old private message'])));
  await page.reload();await page.waitForFunction(()=>window.opens===1);
  assert.deepEqual(await page.evaluate(()=>visibleMessages),[]);
  assert.equal(await page.evaluate(()=>resets),1);
  await page.clock.install();const before=await page.evaluate(()=>opens);
  await page.clock.fastForward(20000);
  assert.equal(await page.evaluate(()=>opens),before,'No forced reopening timer');
  await page.locator('#support-reconnect > summary').click();
  for(const width of [320,375,768,1440]){
    await page.setViewportSize({width,height:850});
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
    assert(await page.locator('#support-chat-retry').isVisible());
  }
  await page.evaluate(()=>{Object.defineProperty(navigator,'onLine',{value:false,configurable:true});window.dispatchEvent(new Event('offline'));});
  await page.locator('#support-chat-retry').click();
  assert((await page.locator('#support-reconnect-status').innerText()).includes('offline'));
  await page.evaluate(()=>{Object.defineProperty(navigator,'onLine',{value:true,configurable:true});window.dispatchEvent(new Event('online'));});
  assert.equal(await page.evaluate(()=>opens),before);
  await page.locator('#support-chat-retry').click();
  assert.equal(await page.evaluate(()=>resets),1,'Reconnect/retry must not reset the chat');
  await page.evaluate(()=>window.dispatchEvent(new Event('chatwoot:error')));
  assert((await page.locator('#chat-feedback').innerText()).includes('connection or setup error'));
  assert.equal(await page.locator('#support-call-link').getAttribute('href'),'tel:+919501606877');
  assert((await page.locator('#support-email-link').getAttribute('href')).startsWith('mailto:support%40'));
  await page.evaluate(()=>FlavorFlowSupportContacts.configure({chatwootBaseUrl:'https://evil.example',chatwootWebsiteToken:'gSkACYN5CHoy4WnpSdPjgfvT'}));
  assert.equal(await page.locator('#live-chat-link').getAttribute('aria-disabled'),'true');
  // A real SDK error permits a fresh download, not a duplicate successful run.
  const blocked=await browser.newPage();
  await blocked.route(SDK,r=>r.abort());await blocked.goto(base+'/support/');
  await blocked.waitForFunction(()=>document.querySelector('#chat-feedback').textContent.includes('could not load'));
  await blocked.locator('#support-reconnect > summary').click();
  assert(await blocked.locator('#support-reconnect a[href^="mailto:"]').isVisible());
  assert(await blocked.locator('#support-reconnect a[href^="tel:"]').isVisible());
  await blocked.unroute(SDK);await blocked.route(SDK,r=>r.fulfill({contentType:'application/javascript',body:stub()}));
  await blocked.locator('#support-chat-retry').click();await blocked.waitForFunction(()=>window.opens===1);
  // Slow readiness after timeout still succeeds; retries don't duplicate run/reset.
  const slow=await browser.newPage();await slow.clock.install();let loads=0;
  await slow.route(SDK,r=>{loads++;return r.fulfill({contentType:'application/javascript',body:stub(25000)});});
  await slow.goto(base+'/support/');await slow.waitForFunction(()=>window.runs===1);
  await slow.clock.fastForward(16000);
  assert((await slow.locator('#chat-feedback').innerText()).includes('could not load'));
  await slow.locator('#live-chat-link').click();
  await slow.clock.fastForward(10000);assert.equal(await slow.evaluate(()=>opens),1);
  assert.equal(loads,1);assert.equal(await slow.evaluate(()=>runs),1);assert.equal(await slow.evaluate(()=>resets),1);
  // Do not expose restored history when the reset API fails.
  const bad=await browser.newPage();await bad.route(SDK,r=>r.fulfill({contentType:'application/javascript',body:stub().replace("resets++;order.push('reset');", "throw new Error('reset failed');resets++;order.push('reset');")}));
  await bad.goto(base+'/support/');await bad.waitForFunction(()=>document.querySelector('#chat-feedback').textContent.includes('could not be reset'));
  assert.equal(await bad.evaluate(()=>opens),0);
  // Start offline: only initialize after connectivity returns.
  const offline=await browser.newPage();await offline.addInitScript(()=>Object.defineProperty(navigator,'onLine',{get:()=>window.testOnline===true,configurable:true}));
  let offlineLoads=0;await offline.route(SDK,r=>{offlineLoads++;return r.fulfill({contentType:'application/javascript',body:stub()});});
  await offline.goto(base+'/support/');assert.equal(offlineLoads,0);
  await offline.evaluate(()=>{window.testOnline=true;window.dispatchEvent(new Event('online'));});
  await offline.waitForFunction(()=>opens===1);assert.equal(offlineLoads,1);
  const home=await browser.newPage();const homeRequests=[];home.on('request',r=>homeRequests.push(r.url()));await home.goto(base+'/');
  assert(!homeRequests.some(x=>/chatwoot|tawk\./i.test(x)));
  assert.equal(errors.length,0,errors.join('\n'));
  console.log('PASS: owner Chatwoot token, exact SDK/base URL, no tawk requests, automatic open, fresh-session reset before open once per reload, guarded recursive ready, reopen/reconnect preserves session, blocked/late/error/offline handling, keyboard/mobile/native fallback, no provider on homepage. SDK stub only; live delivery and account plan remain owner checks.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});

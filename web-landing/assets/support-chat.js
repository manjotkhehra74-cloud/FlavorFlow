/* Chatwoot human support. Public website token only; no ERP or account data is sent. */
(function () {
  'use strict';
  const BASE = 'https://app.chatwoot.com';
  const SDK = BASE + '/packs/js/sdk.js';
  let loading = false, ready = false, started = false, resetDone = false;
  let timer, script;
  function message(text) {
    ['chat-feedback', 'support-reconnect-status'].forEach(id => {
      const node = document.getElementById(id);
      if (node) node.textContent = text;
    });
  }
  function configured(settings) {
    return Boolean(settings && settings.chatwootBaseUrl === BASE &&
      typeof settings.chatwootWebsiteToken === 'string' && /^[A-Za-z0-9]{16,64}$/.test(settings.chatwootWebsiteToken));
  }
  function unavailable() {
    message('Chat could not load yet. Retry chat, or use email or call support.');
  }
  function watch() {
    clearTimeout(timer);
    timer = setTimeout(function () {
      loading = false;
      // Keep a slow SDK and its readiness listener; never inject duplicate widgets.
      unavailable();
    }, 15000);
  }
  function show() {
    try {
      window.$chatwoot.toggleBubbleVisibility('show');
      window.$chatwoot.toggle('open');
      message('Chat window opened. Replies depend on team availability. If disconnected, use email or call support.');
    } catch (_) {
      message('Chat is unavailable. Retry chat, or use email or call support.');
    }
  }
  function initialize(settings) {
    if (started) return;
    if (!window.chatwootSDK || typeof window.chatwootSDK.run !== 'function') {
      clearTimeout(timer);
      loading = false;
      unavailable();
      return;
    }
    started = true;
    try {
      window.chatwootSDK.run({ websiteToken: settings.chatwootWebsiteToken, baseUrl: BASE });
    } catch (_) {
      // Do not run again: a partially-created frame may already exist.
      clearTimeout(timer);
      loading = false;
      unavailable();
    }
  }
  function open(settings) {
    if (!configured(settings)) return;
    if (navigator.onLine === false) {
      message('You appear to be offline. Reconnect to the internet, then retry chat. You can also call support.');
      return;
    }
    if (ready) { show(); return; }
    if (loading) return;
    loading = true;
    message('Loading chat… Email and call support remain available.');
    watch();
    if (script) {
      // If the SDK finished but was not usable earlier, allow its initialization now.
      if (!started) initialize(settings);
      return;
    }
    window.chatwootSettings = {
      position: 'right', type: 'standard', launcherTitle: '',
      // Do not expose the restored conversation before the fresh-session reset.
      hideMessageBubble: true, showUnreadMessagesDialog: false
    };
    const element = document.createElement('script');
    script = element;
    element.src = SDK;
    element.async = true;
    element.onload = function () { initialize(settings); };
    element.onerror = function () {
      if (script !== element || started) return;
      clearTimeout(timer);
      loading = false;
      element.remove();
      script = null;
      unavailable();
    };
    document.head.appendChild(element);
  }
  // Register before loading the SDK: ready may fire immediately or again after reset.
  window.addEventListener('chatwoot:ready', function () {
    if (!started || ready || resetDone) return;
    resetDone = true; // Set before reset to prevent recursive/repeated ready-event resets.
    try {
      // Once per page visit/reload, not on manual reopen or network reconnection.
      // This creates a fresh visitor session; it does not delete agent inbox history.
      window.$chatwoot.reset();
      ready = true;
      loading = false;
      clearTimeout(timer);
      show();
    } catch (_) {
      resetDone = false;
      loading = false;
      clearTimeout(timer);
      message('Chat session could not be reset. Please refresh this page, or use email or call support.');
    }
  });
  window.addEventListener('chatwoot:error', function () {
    message('Chat reported a connection or setup error. Retry chat, or use email or call support.');
  });
  window.FlavorFlowSupportChat = Object.freeze({ configured: configured, open: open });
  const settings = window.FF_SUPPORT_CONTACTS;
  const retry = document.getElementById('support-chat-retry');
  if (retry && configured(settings)) {
    retry.hidden = false;
    retry.addEventListener('click', function () { open(settings); });
  }
  window.addEventListener('offline', function () {
    message('Internet connection lost. Reconnect and retry chat, or call support.');
  });
  window.addEventListener('online', function () {
    // Recover initial loading, without reopening a ready/closed widget or resetting a chat.
    if (!ready && configured(settings)) open(settings);
    else if (ready) message('Internet connection restored. Retry chat if needed; email and call support remain available.');
  });
  open(settings);
}());

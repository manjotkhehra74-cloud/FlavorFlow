/* Free tawk.to human chat. The local support launcher never depends on the vendor. */
(function () {
  'use strict';
  const EMBED = 'https://embed.tawk.to/6ad0c458b841da34cc9dcaef/1k4vntur2';
  let loading = false, ready = false, timer, script, generation = 0;
  let reconnect = false;
  function message(text) {
    ['chat-feedback', 'support-reconnect-status'].forEach(id => {
      const node = document.getElementById(id);
      if (node) node.textContent = text;
    });
  }
  function configured(settings) { return Boolean(settings && settings.tawkEmbedUrl === EMBED); }
  function unavailable() {
    message('Chat could not load yet. Retry chat, or use email or call support.');
  }
  function watch() {
    clearTimeout(timer);
    timer = setTimeout(function () {
      loading = false;
      // A slow vendor may still finish. Keep its script/callback; never inject a second widget.
      unavailable();
    }, 15000);
  }
  function show() {
    try {
      const api = window.Tawk_API;
      if (reconnect && typeof api.start === 'function') api.start({ showWidget: true });
      api.showWidget();
      api.maximize();
      reconnect = false;
      message('Chat window opened. Replies depend on team availability. If disconnected, use email or call support.');
    } catch (_) {
      reconnect = true;
      message('Chat is unavailable. Retry chat, or use email or call support.');
    }
  }
  function open(settings) {
    if (!configured(settings)) return;
    if (navigator.onLine === false) {
      reconnect = true;
      message('You appear to be offline. Reconnect to the internet, then retry chat. You can also call support.');
      return;
    }
    if (ready) { show(); return; }
    if (loading) return;
    loading = true;
    message('Loading chat… Email and call support remain available.');
    watch();
    if (script) {
      // The original script is still initializing. Restart its socket if supported, not its embed.
      try {
        if (typeof window.Tawk_API.start === 'function') window.Tawk_API.start({ showWidget: true });
      } catch (_) { unavailable(); }
      return;
    }
    const api = window.Tawk_API = window.Tawk_API || {};
    const attempt = ++generation;
    window.Tawk_LoadStart = new Date();
    api.onLoad = function () {
      if (attempt !== generation || ready) return;
      clearTimeout(timer);
      loading = false;
      ready = true;
      show();
    };
    const element = document.createElement('script');
    script = element;
    element.async = true;
    element.src = EMBED;
    element.charset = 'UTF-8';
    element.setAttribute('crossorigin', '*');
    element.onerror = function () {
      if (attempt !== generation || ready) return;
      ++generation;
      clearTimeout(timer);
      loading = false;
      element.remove();
      script = null;
      unavailable();
    };
    document.head.appendChild(element);
  }
  window.FlavorFlowSupportChat = Object.freeze({ configured: configured, open: open });
  const settings = window.FF_SUPPORT_CONTACTS;
  const retry = document.getElementById('support-chat-retry');
  if (retry && configured(settings)) {
    retry.hidden = false;
    retry.addEventListener('click', function () { open(settings); });
  }
  window.addEventListener('offline', function () {
    reconnect = true;
    message('Internet connection lost. Reconnect and retry chat, or call support.');
  });
  window.addEventListener('online', function () {
    // Recover initial loading, but never force a closed/minimized ready widget back open.
    if (!ready && configured(settings)) open(settings);
    else if (ready) message('Internet connection restored. Retry chat if needed; email and call support remain available.');
  });
  // Auto-open once on support-page visits. Manual reopen remains available after closing.
  open(settings);
}());

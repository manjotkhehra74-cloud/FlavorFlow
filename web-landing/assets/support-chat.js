/* tawk.to free human chat. Open the supplied widget automatically on the support page. */
(function () {
  'use strict';
  const EMBED = 'https://embed.tawk.to/6ad0c458b841da34cc9dcaef/1k4vntur2';
  let loading = false, loaded = false, timer, script;
  const feedback = () => document.getElementById('chat-feedback');
  function message(text) { const node = feedback(); if (node) node.textContent = text; }
  function configured(settings) { return Boolean(settings && settings.tawkEmbedUrl === EMBED); }
  function failed() {
    loading = false;
    clearTimeout(timer);
    if (script) script.remove();
    message('Chat could not load. Please try again, or use email or call support.');
  }
  function show() {
    try {
      window.Tawk_API.showWidget();
      window.Tawk_API.maximize();
      message('Chat opened. Replies depend on team availability.');
    } catch (_) { message('Chat is unavailable. Please use email or call support.'); }
  }
  function open(settings) {
    if (!configured(settings)) return;
    if (loaded) { show(); return; }
    if (loading) return;
    loading = true;
    message('Loading chat… If it does not open, use email or call support.');
    const api = window.Tawk_API = window.Tawk_API || {};
    window.Tawk_LoadStart = new Date();
    api.onLoad = function () {
      if (!loading) return;
      clearTimeout(timer);
      loading = false;
      loaded = true;
      show();
    };
    script = document.createElement('script');
    script.async = true;
    script.src = EMBED;
    script.charset = 'UTF-8';
    script.setAttribute('crossorigin', '*');
    script.onerror = failed;
    timer = setTimeout(failed, 15000);
    document.head.appendChild(script);
  }
  window.FlavorFlowSupportChat = Object.freeze({ configured: configured, open: open });
  // This script is included only on the support centre, after its contact config.
  // Run once per page load; closing the widget must not automatically reopen it.
  open(window.FF_SUPPORT_CONTACTS);
}());

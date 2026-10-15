/* Contact links only. No chat simulation, ticket storage or automatic widget loading. */
(function () {
  'use strict';
  const config = window.FF_SUPPORT_CONTACTS || {};
  const chat = document.getElementById('live-chat-link');
  const email = document.getElementById('support-email-link');
  const phone = document.getElementById('support-call-link');
  function pending(link) {
    link.removeAttribute('href');
    link.setAttribute('aria-disabled', 'true');
    link.classList.add('channel-pending');
  }
  function enable(link, href) {
    link.href = href;
    link.removeAttribute('aria-disabled');
    link.classList.remove('channel-pending');
  }
  function apply(settings) {
    settings = settings && typeof settings === 'object' ? settings : {};
    pending(chat);
    pending(email);
    pending(phone);
    let chatURL = null;
    try {
      const url = new URL(settings.liveChatUrl);
      if (url.protocol === 'https:' && !url.username && !url.password && url.hostname !== 'localhost' && !/^(127\.|0\.|\[::1\])/.test(url.hostname)) chatURL = url.href;
    } catch (_) { /* Unconfigured/malformed chat stays unavailable. */ }
    document.getElementById('chat-status').textContent = chatURL ? 'EXTERNAL CHAT' : 'SETUP PENDING';
    document.getElementById('chat-description').textContent = chatURL ? 'Open our customer chat channel in a new tab. Agent availability depends on the support team.' : 'A dedicated customer chat channel is being prepared. Chat is not available yet.';
    document.getElementById('chat-label').textContent = chatURL ? 'Open live chat' : 'Live chat — coming soon';
    document.getElementById('chat-status').classList.toggle('pending-status', !chatURL);
    if (chatURL) enable(chat, chatURL);
    const emailAddress = typeof settings.emailAddress === 'string' && /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/.test(settings.emailAddress) ? settings.emailAddress : '';
    const ready = settings.emailEnabled === true && Boolean(emailAddress);
    document.getElementById('email-status').textContent = ready ? 'EMAIL SUPPORT' : 'SETUP PENDING';
    document.getElementById('email-address').textContent = emailAddress || 'Email address to be confirmed';
    document.getElementById('email-description').textContent = ready ? 'Send your company code, issue summary and relevant references. Avoid confidential credentials.' : 'Planned address only — not yet enabled for support. Email sending will open after activation.';
    document.getElementById('email-label').textContent = ready ? 'Email our team' : 'Email support — pending';
    document.getElementById('email-status').classList.toggle('pending-status', !ready);
    if (ready) enable(email, 'mailto:' + encodeURIComponent(emailAddress) + '?subject=' + encodeURIComponent('FlavorFlow ERP support request'));
    const number = typeof settings.phoneNumber === 'string' && /^\+[1-9][0-9]{7,14}$/.test(settings.phoneNumber) ? settings.phoneNumber : '';
    document.getElementById('call-status').textContent = number ? 'PHONE SUPPORT' : 'SETUP PENDING';
    document.getElementById('call-label').textContent = number ? 'Call support' : 'Phone support — pending';
    document.getElementById('call-number').textContent = number === '+919501606877' ? '+91 95016 06877' : (number || 'Number to be confirmed');
    document.getElementById('call-status').classList.toggle('pending-status', !number);
    if (number) enable(phone, 'tel:' + number);
    const statuses = [number ? 'Call support' : 'Phone setup pending', ready ? 'Email support' : 'Email setup pending', chatURL ? 'External chat' : 'Chat setup pending'];
    document.getElementById('contact-availability-note').textContent = statuses.join(' · ') + '. Call/email open your device’s apps; configured chat opens a third-party service. Never share passwords, OTPs or banking credentials.';
    document.getElementById('support-footer-status').textContent = statuses.join(' · ');

  }
  window.FlavorFlowSupportContacts = Object.freeze({ configure: apply });
  apply(config);
  document.querySelectorAll('.support-channel a[aria-disabled]').forEach(link => {
    link.addEventListener('click', event => { if (link.getAttribute('aria-disabled') === 'true') event.preventDefault(); });
  });
}());

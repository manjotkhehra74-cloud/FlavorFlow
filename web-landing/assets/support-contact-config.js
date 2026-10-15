// Owner-managed contact settings. Publish email/chat only after activation/testing.
// Never put passwords, API secrets, OTPs or private account keys in this public file.
window.FF_SUPPORT_CONTACTS = Object.freeze({
  phoneNumber: '+919501606877', // Existing published FlavorFlow business number.
  emailAddress: 'support@flavorflow.co.in',
  emailEnabled: true,
  chatwootBaseUrl: 'https://app.chatwoot.com',
  chatwootWebsiteToken: 'gSkACYN5CHoy4WnpSdPjgfvT', // Public widget token from owner snippet, not an account API key.
  liveChatUrl: '' // Approved HTTPS customer chat URL from your chosen provider.
});

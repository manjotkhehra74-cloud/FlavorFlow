# FlavorFlow — Cashfree shortlist and onboarding

Decision recorded: 13 October 2026.

**Owner decision: defer Cashfree onboarding/integration. Keep it pending while Android store distribution and Windows development are prioritised.**

## Status

Cashfree is shortlisted for FlavorFlow's business-to-business ERP subscription collections, subject to written commercial confirmation and merchant approval. No Cashfree account has been created by the agent, no sales request has been submitted, and no quote has been received. Online checkout is not implemented or enabled. Existing bank-transfer and cheque verification remains unchanged.

Credit/debit card payments are excluded by the owner. Start with one-time UPI and net banking; consider virtual-account bank reconciliation and customer-authorised UPI AutoPay/eNACH separately. Do not accidentally enable credit-card-funded UPI when excluding card payments: confirm whether Cashfree can enforce bank-account-funded UPI only.

## Official links

- Sales request: https://www.cashfree.com/contact-sales/
- Merchant signup: https://merchant.cashfree.com/merchants/signup
- Pricing FAQ: https://www.cashfree.com/docs/help/account/pricing
- Current rate card: https://www.cashfree.com/payment-gateway-charges/

Cashfree's sales form currently requests contact/business details, GSTIN, revenue, business type and mobile OTP verification. The owner must supply real legal/business details directly to Cashfree. Never put bank credentials, OTPs, API secrets or KYC documents in chat or Git.

## Request to submit to Cashfree

We operate FlavorFlow ERP (https://www.flavorflow.co.in/), a manufacturing ERP sold to Indian businesses on monthly and yearly subscription plans. We want to collect our own ERP subscription invoices from our business customers, not process payments on behalf of those customers.

Please provide a written quote and confirm:

1. Approval of our B2B SaaS/ERP use case and the assigned merchant category.
2. Eligibility for the current 0% platform-fee offer, its cumulative volume cap, expiry date and exclusions. Confirm whether GST is charged on a waived platform fee, and illustrate the total fee, GST and net settlement on a INR 10,000 bank-account-funded UPI and net-banking payment, both during and after the offer.
3. Any KYC, setup, maintenance, minimum-commitment, payment-link or other fixed fees.
4. Support for corporate/business net-banking accounts and any bank-specific restrictions.
5. Ability to disable all credit/debit card checkout methods and exclude RuPay credit-card-funded UPI while permitting bank-account-funded UPI. Please confirm supported configuration and enforcement.
6. Separate pricing and activation prerequisites for virtual-account NEFT/IMPS/RTGS collections and automatic invoice/customer reconciliation.
7. Separate mandate creation, recurring debit, failed debit and cancellation charges for UPI AutoPay/eNACH; support and authorisation requirements for business/current accounts.
8. Settlement schedule, refund treatment (including fee/GST reversal or retention), dispute/chargeback charges and any reserves or holds.
9. Requirements for our GST invoices, payment receipts and online policy pages before go-live.

Please distinguish standard payment-gateway fees from subscriptions and virtual-account product charges. We do not wish to advertise payment facilities before our account and selected payment methods are enabled.

## Integration gates

1. Owner receives and accepts the written quote, completes merchant KYC and receives account approval.
2. Configure test credentials securely on the hosting VM, not in frontend code, repository files or chat.
3. Implement backend-created payments linked to an authenticated company and invoice. Calculate amount/currency on the server. Disable card methods according to the provider's approved configuration.
4. Verify provider signatures and payment status on the server. Browser redirects, screenshots and unverified UTR claims must never automatically activate subscriptions. Handle duplicate/delayed webhooks idempotently.
5. Test successes, failures, retries, duplicate callbacks, refunds and reconciliation in sandbox before live credentials and production transactions.
6. Update public payment availability only after testing and explicit go-live approval. Add recurring debit only after separate customer authorisation and supported-bank checks.

# Fält owner operations

This document describes what the Fält owner needs outside the Android app.

## Services and ownership

| Area | Recommended owner account | Purpose |
|---|---|---|
| Domain | Registrar account owned by Fält owner | `falt.se`, DNS and email addresses |
| Billing | Stripe account owned by Fält owner | Subscriptions, invoices, payouts and tax reports |
| Bank | Separate business or dedicated project account | Receives Stripe payouts and pays suppliers |
| App distribution | Google Play Console owned by Fält owner | Android releases and testers |
| Backend | Cloud account owned by Fält owner | Production API, database, storage and backups |
| Source code | GitHub organisation/repository owned by Fält owner | Code, CI and release history |

The customer uses one shared Fält Android app. A company is a tenant in the backend. The owner does not need a second mobile app to receive payments or operate the service.

## URLs

The intended production layout is:

- `falt.se` — marketing, registration, pricing and help
- `app.falt.se` — customer web account and billing checkout
- `admin.falt.se` — owner portal
- `api.falt.se` — authenticated backend API

Development and staging use separate hostnames and separate databases. Test Stripe keys and test accounts must never be used in production.

## Owner portal

The owner portal should show subscription and operational metadata: companies, plan, status, seats, payment state, MRR, failed payments, app version, storage use and support access logs. It must not give ordinary staff unrestricted access to customer documents, personnummer, payroll or private notes. Support access is time-limited, explicit and logged.

## Payment lifecycle

1. A company registers on `app.falt.se`.
2. Stripe Checkout creates the subscription.
3. Stripe webhooks are verified by the backend.
4. The backend grants or revokes entitlements for that company.
5. The Fält app reads entitlements from the backend; it never trusts local storage to decide payment status.
6. Stripe sends payouts to the owner’s configured bank account.

Keep Stripe test mode, webhook secrets and production secrets separate. Do not commit keys to GitHub or the mobile binary.

## Before registering a company

The technical work can start before a company exists. Use:

- a personal GitHub account with a private development repository if needed
- Stripe test mode for all development and fake subscriptions
- a development domain or local hostnames
- fake companies and synthetic customer data
- a separate email address for project administration

Do not collect real personnummer, customer documents or real payment details during the hobby/prototype phase. Do not promise production support or issue commercial invoices until the legal and accounting setup is ready.

When the service is ready for real customers, register the appropriate business form, open the correct bank and payment accounts, move production ownership to those accounts, and update the privacy notice, terms, DPA and support process.

## Swedish tax and business caution

Moms and income tax are separate. For a business established in Sweden, the small-business VAT exemption can apply when annual taxable turnover is at most 120,000 SEK under the current rules. If turnover passes the applicable limit, VAT registration is required. The limit concerns VAT turnover and does not make income tax-free. You can also choose voluntary VAT registration, and cross-border digital sales can trigger separate EU VAT/OSS rules.

Whether the activity is hobby or näringsverksamhet is assessed from the actual circumstances, including purpose, continuity, independence and profit intention. Surplus from hobby activity can be taxable and must be documented. Accounting, consumer rules, payment-provider requirements and VAT are separate questions.

Before accepting real subscriptions, confirm the current rules with Skatteverket or an accountant. Keep a ledger from day one: Stripe fees, hosting, software, domain, advertising, refunds, taxable turnover and every payout. If operating under the small-business VAT exemption, use the legally required wording on invoices and do not charge VAT until registered.

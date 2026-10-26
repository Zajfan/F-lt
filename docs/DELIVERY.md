# Delivery status and gates

## Current delivery

Source foundation committed. No successful Flutter build or device run has been verified. The GitHub workflow is the next executable check, not a claim that checks already passed.

### Implemented in source

Flutter evaluation screens; local SQLite records/outbox; quote calculations; customer edits; local scheduling; job progression; invoice snapshots; manual payment recording; domain tests; Android debug build workflow; initial tenant SQL migration.

### Required before a company pilot

- Run CI and fix all failures; commit resolved dependency lockfile and reviewed Android host.
- Physical Android checks: small screen, 200% text, TalkBack, keyboard, process death, permission denial and airplane mode.
- Integration tests using SQLite for atomic rollback, duplicate invoice requests and restart persistence.
- Auth, company onboarding and invitations; RLS and cross-company regression tests.
- Authenticated sync API, idempotency receipts, conflict resolution, outbox retry and clear sync UI.
- Secure cache partitioning, logout policy, backup controls and recovery test.
- Editable price book, quote revision editing, company settings and customer history in the mobile app.
- Real quote PDF/delivery and auditable customer acceptance. Manual approval in this build is not external signing.
- Reviewed invoice numbering, VAT and versioned tax rules; export and credit-note paths.

### Required before commercial release

- Time/material capture and photos with access-controlled uploads and retention rules.
- Accountant-approved integration and reconciliation tests.
- Billing entitlement checks on server; cancellation and data export.
- Support tooling, privacy notice, DPA/subprocessor list, restore rehearsal and incident ownership.
- App signing, store listing, Play testing track and release monitoring.
- Independent performance, accessibility and security review on production-like data.

## iOS deferred

Shared Flutter code can be developed now. Generating the iOS host, device testing, platform-specific permissions, signing and distribution remain future tasks; cross-platform source does not itself verify iOS compatibility.

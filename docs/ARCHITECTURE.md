# Architecture

## Implemented boundary

`mobile/lib/domain/` contains pure Dart pricing and lifecycle rules. `data/local_store.dart` owns SQLite transactions and snapshots. `main.dart` currently contains the evaluation UI; split it into feature modules as the flows are hardened. No HTML webview is involved.

Each local write and its outbox event are committed in one transaction. This prevents a local business change being saved without its pending operation. The outbox currently has no transport, retry worker, acknowledgement or pruning. It is not proof of cloud durability.

Money uses integer öre and quantity thousandths. VAT is rounded per line. This is an explicit current convention that must match the future accounting integration. Current quote deductions are illustrative, not a verified tax policy.

## Target server boundary

Use Supabase Auth and Postgres with a European region subject to a reviewed data processing agreement. Every business table carries company_id and RLS enforces membership. Mobile contains no service-role credentials. Company creation and invitations use privileged, narrowly scoped server commands.

The included migration implements initial company/membership/customer/job tables and restrictive policies. Worker writes, onboarding, quotes, invoice issuance, audit storage and outbox receipt are not implemented. Test cross-company SELECT/INSERT/UPDATE and revoked membership before deploying an API.

## Sync protocol to implement

Each command includes operation UUID, company ID, entity ID, expected server version, device ID and typed payload. Server validates role, membership and state in a transaction. A unique company/operation key makes retries idempotent. Acknowledge only committed commands.

Pull by server cursor with tombstones; avoid client clock ordering. On conflicting quote or invoice revisions, return a conflict for explicit review. Never use blind last-write-wins on financial documents. Persist retry metadata and use bounded exponential backoff. Keep pending changes scoped to the authenticated account and company; sign-out must not expose another user's cached data.

SQLite is currently ordinary app-private storage, without application-level encryption, per-account partitioning or backup exclusions. No real customer data until device storage, credential handling, logout and backup policies are reviewed.

## Customer acceptance

Generate expiring, high-entropy, single-purpose links on the server. Store token hashes, bind to quote revision and present the exact immutable document. Record server timestamp, method, revision digest and customer attestation. Add an identity/signing provider when the evidence requirements call for it. A finger-drawn signature alone does not establish identity.

## Invoice issuance

Server allocates numbers transactionally per company and accounting series. Unique source/revision and idempotency constraints prevent duplicates. Issued invoices become immutable; corrections use credit notes. Payment records are independent events. Validate with a Swedish accountant and the chosen Fortnox/Spiris integration.

## Operations

Separate development, staging and production. Version migrations; rehearse rollback and restore. Scrub customer data from crash reports. Collect sync failure counts, startup performance and command latency without logging document content. Require signed Android release builds and staged distribution. Add iOS CI on macOS when signing and distribution are authorized.

# Architecture

## Implemented boundary

Authentication, company onboarding, scoped live workspaces, foreground retry, and the Android WorkManager background entrypoint are implemented in source. Production Supabase configuration and device verification remain required.

`mobile/lib/domain/` contains pure Dart pricing and lifecycle rules. `mobile/lib/data/local_store.dart` owns SQLite transactions, scoped records, snapshots, outbox rows, conflicts, and cursors. `mobile/lib/sync/` contains typed protocol models, the transport-independent sync engine, the Supabase RPC adapter, and the Android WorkManager entrypoint. `main.dart` wires authentication, company onboarding, scoped workspaces, foreground retry, and background scheduling. No HTML webview is involved.

Money uses integer öre and quantity thousandths. VAT is rounded per line. This is an explicit current convention that must match future accounting work; current quote deductions are illustrative, not a verified tax policy.

## Product and authority

Fält is trade-neutral. Trade profiles are configuration and content layered on shared customer, job, quote, and invoice models. Roofing, painting, electrical, and other profiles must not create separate domain or sync implementations.

Supabase Auth plus PostgreSQL is authoritative for synchronized customer and job state. The server tenant is `company_id`; the mobile store additionally partitions cached records, outbox rows, conflicts, and cursors by authenticated `account_id` and `company_id`, and tags operations with `device_id`. A local SQLite row or outbox entry is not proof of cloud durability until its operation is accepted or replayed as a receipt.

## Customer/job sync vertical slice

The implemented server contract is:

```text
sync_push(
  p_operation_id uuid,
  p_company_id uuid,
  p_entity_kind text,       -- customer | job
  p_entity_id uuid,
  p_device_id uuid,
  p_expected_version bigint,
  p_operation_kind text,    -- upsert | delete
  p_payload jsonb
) -> jsonb

sync_pull(
  p_company_id uuid,
  p_after_cursor bigint,
  p_limit integer
) -> (cursor bigint, entity_kind text, entity_id uuid,
      version bigint, deleted_at timestamptz, payload jsonb,
      operation_id uuid)
```

`sync_push` requires an authenticated Supabase session and membership in the requested company. Customer writes require owner/admin membership. Managers can manage company jobs. Workers may update existing jobs assigned to themselves and may create a new job only when the submitted `assignee_id` is themselves. The RPC validates entity/operation kinds, non-negative expected versions, and object payloads for upserts.

Push behavior is transactionally serialized by a company sync-state row. Expected version `0` creates a record; a positive expected version must match the current server version for an update or delete. An accepted write advances the record version, allocates one company cursor, appends one change-log row, and stores one operation receipt. The `(company_id, operation_id)` receipt makes replay idempotent and returns a duplicate outcome without applying another write or cursor change. A stale/versioned conflict returns the current server state, including `current.version` and payload, stores the receipt, and appends no change. SQL can also return `current: null` for cases such as a zero-version delete or a hidden cross-company ID collision; that response has no server version, so it cannot be recorded in `sync_conflicts` and is intentionally retained as a protocol-error/manual-action outbox row. The engine does not invent a version. Malformed operations are rejected before mutation.

Pull is company-authorized, strictly ordered by server cursor, and returns rows with `cursor > p_after_cursor`; the server clamps the requested page to 1–200 rows. A deleted record is a tombstone: `deleted_at` is set and `payload` is null. The migration snapshots pre-existing customer/job rows so a cursor-zero client can bootstrap them before later changes.

On the mobile side, each customer/job write and its outbox operation commit in one SQLite transaction. The outbox stores account, company, device, entity, expected server version, operation kind, attempt count, retry eligibility, and the last transport error. The Supabase adapter exposes only sanitized typed transport errors. The engine reads due pending/retry operations in creation order, makes at most 50 push attempts per run, rereads after every result so same-entity acknowledgements can rebase later expected versions, and then pulls at most 100 changes only when push handling has not been blocked.

Transient failures use bounded delays of 5 seconds, 30 seconds, 5 minutes, 30 minutes, and 2 hours. After five recorded transient retry attempts, the next transient failure is retained as ineligible and marked for user action. Validation, authorization, and rejected outcomes are not scheduled for transient retry; they are retained as ineligible and user-actionable through the shared path, which may increment the stored `attempt_count`. Protocol failures retain the outbox operation and block pull for that run.

Conflicts are retained, never silently last-write-wins. A versioned push conflict keeps the local operation and records the returned server version/payload in `sync_conflicts`. A `current: null` push conflict has no version to store, so the engine retains the operation as a protocol-error/manual-action outbox row instead. During pull, a newer remote change for an entity with an unresolved local operation leaves the local record or tombstone in place, records the remote state as a conflict, and still advances the cursor. A tombstone remains stored with its server version while ordinary record reads hide it; older changes cannot resurrect it.

`applyPullPage` validates strictly increasing cursors, matching entity IDs, and page advancement, then applies records/conflicts and the cursor in one SQLite transaction. Invalid pages roll back all changes. An empty page at the current cursor is a no-op and does not invent progress.

## Security boundaries and known gaps

The SQL RPCs are `security definer` functions with an empty `search_path`, explicit object qualification, authenticated-session checks, membership checks, and role checks. Direct client access to sync tables is revoked, and direct customer/job writes are removed so synchronized writes go through `sync_push`. The mobile adapter requires an active session and maps transport failures to generic typed errors without copying response bodies, tokens, or raw exception text into the sync error surface.

Only a publishable/anon Supabase key may be present in mobile configuration. A service-role key belongs only in narrowly scoped server-side operations and must never be embedded in the APK. Production validation is still required for the real Supabase project, Auth setup, memberships, RLS behavior, migrations, and onboarding flow. SQLCipher key recovery/upgrade behavior for pre-release plaintext caches, backup exclusions/recovery, logout cache handling, and release/device testing are also open security/product gates.

## Customer acceptance

Generate expiring, high-entropy, single-purpose links on the server. Store token hashes, bind them to a quote revision, and present the exact immutable document. Record server timestamp, method, revision digest, and customer attestation. Add an identity/signing provider when evidence requirements call for it; a finger-drawn signature alone does not establish identity.

## Invoice issuance

Fält's server should allocate invoice numbers transactionally per company and accounting series. Unique source/revision and idempotency constraints prevent duplicates. Issued invoices become immutable; corrections use credit notes. Payment records are independent events. Validate VAT, invoice examples, deductions, exports, and reconciliation with a Swedish accountant. Fortnox, Spiris, and other accounting-provider integrations are optional future boundaries, not dependencies of this customer/job sync slice.

## Operations

Separate development, staging, and production. Version migrations; rehearse rollback and restore. Scrub customer data from crash reports. Collect sync failure counts, startup performance, and command latency without logging document content. Require signed Android release builds and staged distribution. Add iOS CI on macOS when signing and distribution are authorized.

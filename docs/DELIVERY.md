# Delivery status and gates

## Current delivery

The first customer/job sync vertical slice is implemented in source, but it is not production-verified. Supabase/Postgres is the authority; the mobile SQLite database is a scoped cache, outbox, conflict store, and cursor store.

Implemented across Tasks 1–9 plus the background scheduler:

- Supabase/Postgres tenancy and sync migrations with authenticated `sync_push` and cursor-based `sync_pull` RPCs.
- Idempotent company/operation receipts, optimistic server versions, change cursors, and tombstones.
- Versioned push conflicts retained with server version/payload in `sync_conflicts`; `current: null` SQL conflicts retained as protocol-error/manual-action outbox rows without an invented version.
- Immutable Dart sync models and account/company-scoped SQLite records, conflicts, and cursors, with device-tagged outbox operations.
- Atomic local writes plus outbox insertion, atomic pull record/conflict/cursor application, and tombstone retention.
- Transport-independent push/pull orchestration with conflict retention, bounded retries, retry exhaustion handling, and pull-after-push cursor safety.
- An authenticated Supabase adapter with exact RPC parameter mapping, empty-page cursor preservation, response validation, and sanitized transport errors.
- Authenticated sign-in/sign-up, company onboarding, device identity, scoped live workspace startup, request-race protection, and sanitized auth-stream error handling.
- Android WorkManager scheduling with a top-level background isolate that reuses the same outbox/sync engine, requires network connectivity, and retries through platform backoff.
- Job detail fields (`address`, `instructions`, and provider-neutral `quote_id`) carried through the SQL and mobile wire contract, including normalization of legacy local outbox payloads.
- SQLCipher-backed local storage with a per-installation key held in platform secure storage; FFI test factories remain injectable without a platform key.
- Recipient-facing invoice preview with immutable customer/company snapshots for new invoice drafts and fallback support for older local invoice records.

The source slice is not the same as a connected production feature: a real Supabase project/configuration, production RLS validation, and device installation testing remain open.

The GitHub Actions workflow `.github/workflows/android.yml` is the toolchain-enabled evaluation path. It runs on `ubuntu-latest`, resolves dependencies, runs analyzer/tests, builds a demo debug APK, and uploads it as `falt-android-demo-debug`. A local Flutter/Android installation is not required to obtain that artifact.

## Exact verification commands

Bootstrap a local toolchain first:

```bash
./tooling/bootstrap.sh
source tooling/env.sh
flutter doctor --android-licenses
./tooling/install-postgres-client.sh
./tooling/doctor.sh
cp mobile/config/env.example.json mobile/config/env.json
```

Fill `mobile/config/env.json` with the Supabase project URL and publishable/anon key. Apply `backend/migrations/001_tenancy.sql`, `002_sync_foundation.sql`, `003_onboarding.sql`, and `004_job_details_sync.sql` through the Supabase migration workflow before testing live login or sync. Keep `mobile/config/env.json` out of version control.

Run the SQL command against a disposable Supabase-compatible database prepared with the full sequence (`001_tenancy.sql`, the pre-existing-row fixture, `002_sync_foundation.sql`, `003_onboarding.sql`, and `004_job_details_sync.sql`). Then run the mobile commands from the repository root as shown:

```bash
psql "$FALT_TEST_DATABASE_URL" --set ON_ERROR_STOP=1 --file backend/tests/sync_contract.sql
cd mobile
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug --dart-define-from-file=config/env.json
```

The current CLI environment lacks `psql`, `flutter`, `dart`, `adb`, and `sdkmanager`. The committed `mobile/pubspec.lock` and the GitHub workflow provide the reproducible CI path, but SQL execution, local Flutter runtime tests, analyzer execution and local APK compilation have not passed in this environment. The latest supplied CI run reported 104 tests passing before the final invoice-preview test assertion was corrected in commit `5e6a5fa`; the workflow must be rerun before claiming a fully passing build.

## Required gates before a company pilot

- Provision a real Supabase project with Auth, memberships, migrations, reviewed RLS/RPC privileges, and a European data-processing posture appropriate to the deployment.
- Run the SQL contract against a disposable database and resolve any PostgreSQL/Supabase compatibility findings; include cross-company, role, replay, conflict, cursor, and tombstone coverage.
- Review the committed `mobile/pubspec.lock` and keep dependency resolution pinned to the Flutter 3.35.7 CI environment.
- Run Flutter tests and `flutter analyze --no-fatal-infos`; install the debug APK on a physical Android device and check small screens, 200% text, TalkBack, keyboard, process death, permission denial, airplane mode, logout, and retry recovery.
- Verify authenticated app wiring and WorkManager scheduling on a physical Android device after account/company cache partitioning, device-tagged outbox handling, backup policy, and recovery behavior are reviewed.
- Create and securely back up the company-owned Android keystore with `tooling/create-release-keystore.sh` (or configure the example manually), and verify a signed release APK before store submission.
- Finish the product flows around editable price books, quote revisions, customer history, real quote PDF delivery, auditable customer acceptance, reviewed invoice numbering, VAT/versioned tax rules, exports, and credit notes.

## Required gates before commercial release

- Time/material capture and photos with access-controlled uploads and retention rules.
- Accountant-approved Fält invoicing, export, and reconciliation tests. Fortnox and Spiris are not prerequisites for this slice; any later provider adapter is an optional integration boundary.
- Billing entitlement checks on the server, cancellation, data export, support tooling, privacy notice, DPA/subprocessor list, restore rehearsal, and incident ownership.
- App signing, store listing, Play testing track, release monitoring, and an independent performance, accessibility, and security review on production-like data.

## iOS deferred

Shared Flutter code can be developed now. Generating the iOS host, device testing, platform-specific permissions, signing, and distribution remain future tasks; cross-platform source does not itself verify iOS compatibility.

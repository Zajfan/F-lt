# Fält — Android-first mobile product

Fält is being rebuilt as a Flutter application for Swedish trade businesses. Android is the first delivery platform; iOS signing, builds and store distribution are deferred. This repository is **an early engineering foundation, not a production-ready commercial product**.

Fält is trade-neutral. The shared workflow supports configurable profiles for roofers, painters, electricians, and other trades; profiles provide templates, price-book content, terminology, checklists, and demo data. The current source is an evaluation foundation and does not claim complete support for every profession.

## Current mobile implementation

- Native Flutter screens for today's jobs, quotes, schedules, invoice drafts and customers.
- SQLite persistence with transactional business writes and a durable, scoped sync outbox.
- A first customer/job sync vertical slice: Supabase/Postgres RPCs, typed Dart protocol models, account/company-scoped SQLite records, conflicts and cursors, device-tagged outbox operations, a transport-independent sync engine, and a Supabase RPC adapter.
- Quote calculations, job scheduling and progression, invoice snapshots, manual payment recording, and domain models for the existing evaluation flows.
- Fält-owned invoicing remains the product direction. This customer/job sync slice has no Fortnox or Spiris dependency.

Supabase/Postgres is authoritative for synchronized customer and job state. SQLCipher-backed SQLite is a local cache plus pending-operation store, with its key kept in platform secure storage; it is not cloud durability. Authenticated app wiring, foreground retry, and an Android WorkManager scheduler are implemented in source; production deployment and device verification are not complete. Do not use real customer data in this evaluation version.

Versioned push conflicts retain the server version and payload in local `sync_conflicts`. SQL conflicts that return `current: null` have no server version; they remain retained as protocol-error/manual-action outbox rows, and the engine never invents a version.

## Scope and security boundary

The server uses Supabase Auth identity and company membership. Client records, conflicts, and cursors are scoped by authenticated `account_id` and `company_id`; outbox operations additionally carry `device_id`. RPCs accept only the authenticated session and an authorized company. Customer writes require owner/admin authority. Managers can manage company jobs; workers may update existing jobs assigned to themselves and may create a new job only when the submitted assignee is themselves. Mobile configuration may contain only the publishable/anon Supabase key; service-role secrets must never be shipped in an APK.

The current gaps are encrypted-store upgrade/recovery validation for pre-release plaintext caches, backup policy, production Supabase/RLS validation, a provisioned production project, and release/device verification. Customer identity verification, external signing, email delivery, legal invoice numbering, real payments, accounting export, and production sync deployment are also future work.

## Run Android

The repository includes a reproducible local toolchain bootstrap. It needs a working network connection and enough disk space for Flutter and Android SDK packages:

```sh
./tooling/bootstrap.sh
source tooling/env.sh
flutter doctor --android-licenses
./tooling/install-postgres-client.sh
./tooling/doctor.sh
```

Licenses are intentionally not auto-accepted by the script. Install Flutter **3.35.7**, Java 17+ and the Android SDK before accepting them. Then configure Supabase from the publishable client key:

```sh
cp mobile/config/env.example.json mobile/config/env.json
# Edit mobile/config/env.json with the Supabase URL and publishable/anon key.
```

Run demo mode without credentials by setting `FALT_DEMO_MODE` to `true` in that file. Live login, company onboarding and cloud sync require migrations `003_onboarding.sql` and `004_job_details_sync.sql` in the configured Supabase project.

Then:

```sh
cd mobile
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter run --dart-define-from-file=config/env.json
```

The Android host is generated from the pinned Flutter template for now. Before distribution, commit a reviewed host with final application ID, backup policy, permissions, icons and signing configuration. The placeholder `se.falt` namespace is not a verified registered identity.

## Android APK

The Android workflow analyzes, tests and builds a debug APK when its environment is available. A successful run produces a sideloadable evaluation artifact; this is not a Play Store release. For a signed release build, create a user-owned keystore with the helper below, or copy `mobile/config/release-key.properties.example` and configure it manually:

```sh
read -r -s FALT_STORE_PASSWORD
export FALT_STORE_PASSWORD
read -r -s FALT_KEY_PASSWORD
export FALT_KEY_PASSWORD
./tooling/create-release-keystore.sh
unset FALT_STORE_PASSWORD FALT_KEY_PASSWORD

cd mobile
flutter build apk --release --dart-define-from-file=config/env.json
```

The helper refuses to overwrite an existing keystore or `key.properties`. Back up both files securely; losing the signing key prevents updates to a published Android app. No paid Apple membership is needed for Android development.

## Build through GitHub Actions

The repository workflow at `.github/workflows/android.yml` runs on GitHub's Ubuntu runner, resolves dependencies, runs analyzer/tests, builds the demo APK, and uploads `falt-android-demo-debug`. Start it from the Actions tab with **Run workflow**, or push a change to `main` affecting `mobile/**`. Download the APK from the completed workflow's Artifacts section; the local machine does not need Flutter or the Android SDK for this path.

## Architecture and product plan

See [product brief](docs/PRODUCT.md), [architecture](docs/ARCHITECTURE.md), and [delivery status](docs/DELIVERY.md). The original HTML prototype is under `archive/web-demo/` for historical reference and is not the mobile application.

## Verification status

The current CLI environment lacks `psql`, `flutter`, `dart`, `adb`, and `sdkmanager`. `mobile/pubspec.lock` has not been regenerated after adding `supabase_flutter`, `workmanager`, `sqflite_sqlcipher`, and `flutter_secure_storage`. Therefore SQL execution, dependency resolution, Dart/Flutter runtime tests, analyzer results, and local APK compilation are pending; no local SQL/runtime/analyzer/dependency/APK result is passing in this environment. GitHub Actions is the intended toolchain-enabled APK path and must pass before an artifact is treated as usable. No test count is claimed. `./tooling/doctor.sh` reports the exact missing tools.

The exact verification commands for this slice are:

```bash
psql "$FALT_TEST_DATABASE_URL" --set ON_ERROR_STOP=1 --file backend/tests/sync_contract.sql
cd mobile
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug --dart-define-from-file=config/env.json
```

Run the SQL command against a disposable Supabase-compatible database prepared with migrations `001_tenancy.sql`, the pre-existing-row fixture, `002_sync_foundation.sql`, `003_onboarding.sql`, and `004_job_details_sync.sql`. The delivery gates describe the required order and follow-up checks.

# Fält — Android-first mobile product

Fält is being rebuilt as a Flutter application for Swedish trade businesses. Android is the first delivery platform; iOS signing, builds and store distribution are deferred. This repository is **an early engineering foundation, not a production-ready commercial product**.

## Current mobile implementation

- Native Flutter screens: today's jobs, quotes, chronological schedule, invoice drafts and customers.
- SQLite persistence with transactional writes and a durable outbox. **No server sync worker is connected.**
- Quote creation with a spotlight template and custom labour/material lines.
- Integer öre pricing, fractional quantities, VAT and explicitly provisional ROT/RUT calculations.
- Quote state transitions, manual approval recording, invoice snapshots and idempotent invoice draft creation.
- Job scheduling with local overlap checks; start and complete jobs.
- Customer editing and explicit local payment recording.
- Domain tests for money, tax scope, lifecycle transitions and scheduling boundaries.
- Initial Supabase tenancy migration, separate from the mobile app. Not deployed or integrated.

No customer identity verification, electronic signature provider, email delivery, legal invoice numbering, real payments, accounting export, authentication or production sync is implemented. Do not use real customer data in this evaluation version.

## Run Android

Install Flutter **3.35.7**, Java 17 and the Android SDK. Then:

```sh
cd mobile
flutter create --platforms=android --org se.falt --project-name falt --no-pub .
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter run
```

The Android host is generated from the pinned Flutter template for now. Before distribution, commit a reviewed host with final application ID, backup policy, permissions, icons and signing configuration. The placeholder `se.falt` namespace is not a verified registered identity.

## Android APK

The **Android evaluation build** GitHub Actions workflow generates the host, analyzes, tests and builds a debug APK. When successful, open the workflow run and download `falt-android-evaluation` from Artifacts. This is a sideloadable debug evaluation build, not a Play Store release. No paid Apple membership is needed for Android development.

## Architecture and product plan

See [product brief](docs/PRODUCT.md), [architecture](docs/ARCHITECTURE.md), and [delivery status](docs/DELIVERY.md). The original HTML prototype is under `archive/web-demo/` for historical reference and is not the mobile application.

## Verification

Flutter analysis completed locally. The automated suite passes 22 tests, including SQLite persistence, timers, invoice integrity, phone navigation and 200% text scaling. The visual golden references are generated locally but are kept out of the first source commit to keep the repository lean. A local debug APK build reached Gradle dependency resolution; the environment's Java trust store rejected Maven/Google HTTPS artifacts, so APK compilation must be verified in GitHub Actions. No backend migration has been applied.

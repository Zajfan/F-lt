# Fält mobile

Android-first Flutter client for Fält's Swedish trade-business workspace.

The app contains the field workflow for customers, quotes, scheduling, jobs,
time, materials, documentation, invoice drafts and recipient-facing invoice
preview. Demo mode is local-first; live authentication and customer/job sync
use the Supabase configuration described in the repository [README](../README.md).

Run from the repository root after the pinned Flutter toolchain is installed:

```sh
cd mobile
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter run --dart-define=FALT_DEMO_MODE=true
```

The GitHub Actions workflow builds the Android evaluation APK. A debug APK is
not a production release and must not be used with real customer data.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

# Arch Terminal

A local-first terminal application built with Flutter for Android, Linux, and Windows. Arch Terminal provides a local Arch Linux environment, RootFS management, terminal sessions, and optional assistant features.

## Requirements

- Flutter SDK compatible with Dart `^3.9.0`
- Android SDK and Java 21 for Android builds
- Internet access when Flutter packages or the RootFS required for first-time setup must be downloaded

## Local development

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Build a release Android APK locally:

```bash
flutter build apk --release
```

GitHub Actions automatically runs analysis, tests, and an Android release build when changes are pushed to `main` or when the workflow is started manually. The current application version is `1.0.1+107`.

## Project structure

- `lib/`: Flutter UI, terminal logic, and session management.
- `android/`: Android integration and background installation/runtime services.
- `packages/xterm/`: Embedded local terminal package.
- `test/`: Flutter and application tests.
- `docs/`: Delivery notes, UI references, and RootFS documentation.
- `tools/`: Verification and source snapshot utilities.

## Project documentation

- [Contributing](CONTRIBUTING.md): development workflow and pull request checklist.
- [Security](SECURITY.md): local-first data handling and vulnerability reporting.
- [Changelog](CHANGELOG.md): release history and validation notes.
- [Release checklist](docs/RELEASE_CHECKLIST.md): pre-release quality and publishing checks.
- [Android build notes](android/README.md): SDK, NDK, and signing guidance.

## License

This project is licensed under the **MIT License**. See [LICENSE](LICENSE) for the full text.

See [POLICY.md](POLICY.md) for contribution and publishing rules.

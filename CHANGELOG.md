# Changelog

This project follows a simple release history. Each release records user-visible changes and build validation.

## [1.0.1+107] — 2026-11-26

### Improved

- Added professional contribution, security, Android build, and release documentation.
- Added Dependabot and a pull request template for repository maintenance.
- Added Android asset verification and SHA-256 generation to the release workflow.
- Clarified that CI APKs are debug-signed validation builds until a protected production keystore is configured.

### Validation

- `flutter analyze` passed.
- `flutter test` passed.
- Android asset verification passed.
- Android release packaging is covered by CI.

## [1.0.0+106] — 2026-11-26

### Added

- Published the complete Flutter/Android source project.
- Added English repository documentation, contribution guidance, and security policy.
- Added a GitHub Actions pipeline for analysis, tests, and Android APK builds.
- Added MIT licensing for the repository.

### Improved

- Hardened Android release packaging with explicit NDK and R8 configuration.
- Added bounded inline terminal image decoding and validation.
- Added RootFS verification, setup progress, background continuity, and local activity tooling from the uploaded project.

### Validation

- `flutter analyze` passed.
- `flutter test` passed.
- Android release APK build passed for `arm64-v8a` and `armeabi-v7a`.

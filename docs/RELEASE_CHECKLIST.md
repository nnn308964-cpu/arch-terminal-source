# Release Checklist

Use this checklist before publishing a new Arch Terminal release.

## Source and quality

- [ ] Update `version` in `pubspec.yaml`.
- [ ] Update `CHANGELOG.md` and the release notes.
- [ ] Run `flutter pub get`.
- [ ] Run `flutter analyze`.
- [ ] Run `flutter test`.
- [ ] Run `tools/verify_android_assets.sh`.
- [ ] Review `git diff --check` and the staged file list.
- [ ] Confirm that no secrets, local configuration, APKs, or generated directories are tracked.

## Android release

- [ ] Confirm the target SDK, compile SDK, and NDK versions are available in CI.
- [ ] Confirm both supported ABIs are present in the APK.
- [ ] Confirm RootFS archives are not embedded in the APK.
- [ ] Configure a protected production keystore before public distribution.
- [ ] Do not publish a debug-signed APK as a production build.

## GitHub release

- [ ] Merge only after the required CI check and APK build pass.
- [ ] Create a version tag matching the application version.
- [ ] Attach the APK and publish release notes.
- [ ] Record the CI run URL and SHA-256 checksum for the released APK.

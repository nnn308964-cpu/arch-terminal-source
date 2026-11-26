# Contributing to Arch Terminal

Thank you for helping improve Arch Terminal. Please keep changes focused, explain the user impact, and preserve the local-first security model.

## Before opening a pull request

Run the same checks used by CI from the repository root:

```bash
flutter pub get
flutter analyze
flutter test
tools/verify_android_assets.sh
flutter build apk --release
```

Do not commit generated directories, APK files, signing keys, local configuration, or secrets. The repository `.gitignore` contains the standard exclusions, but contributors must still review staged files before pushing.

## Change guidelines

Keep terminal execution and permission changes explicit. Any new command execution path must pass through the existing safety and approval layers. Keep user-visible strings compatible with the existing English and Arabic UI paths, and add or update tests when behavior changes.

Prefer small commits with descriptive messages. Pull requests should include a concise summary, testing performed, screenshots for UI changes, and any migration or release notes required by users.

## Pull request checklist

- [ ] The change is scoped and documented.
- [ ] `flutter analyze` passes.
- [ ] `flutter test` passes.
- [ ] Android assets were verified.
- [ ] No secrets or generated build outputs are included.
- [ ] User-visible behavior and compatibility impact are described.

# Android Build Notes

The Android module targets API 24 as its minimum install level and uses Java 17, compile SDK 37, and NDK `28.2.13676358`. The release build embeds PRoot for `arm64-v8a` and `armeabi-v7a`; Arch RootFS archives are downloaded and verified during setup instead of being bundled in the APK.

## Local build

From the repository root:

```bash
flutter pub get
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

## Signing

The repository workflow currently uses the debug signing configuration so contributors can build and validate the application without access to private signing material. Before distributing a production APK, configure a dedicated release keystore through protected CI secrets and update `android/app/build.gradle.kts` to use it. Never commit the keystore or its credentials.

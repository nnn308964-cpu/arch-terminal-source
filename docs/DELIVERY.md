# Delivery Report — Arch Terminal v1.0.1+107

## Current result

The project provides a shared Flutter application for Android, Linux, and Windows, with Android-only packaging in the current release. There is no database, account system, application server, or synchronization service. The Android app connects to the internet **once during first-time setup** to download the Arch Linux archive matching the phone ABI from public GitHub Releases. After installation, the terminal session, PRoot, and RootFS remain fully local.

| Area | Current result |
|---|---|
| Flutter / Dart | Flutter 3.35.3 / Dart 3.9.2 in CI |
| Terminal UI | xterm 4.0.0 |
| PTY | kyroon_pty 1.0.6 |
| Android APK | One universal APK supporting `arm64-v8a` and `armeabi-v7a` |
| Release APK size | 46.7 MB |
| PRoot | Embedded in the APK for both ABIs |
| Arch RootFS | Public GitHub Release; downloaded by ABI on first launch |
| Verification | SHA-256 is pinned in the app before extraction |
| Arabic and emoji | UTF-8 streaming and suitable fallback fonts with an ANSI LTR grid |
| Control UI | Dark terminal screen with a side command panel opened by `<` |
| Background setup | Android foreground service with progress notification for download, verification, and extraction |
| Battery optimization | Command-panel option to request a battery-optimization exemption |
| RootFS storage | Setting for private app storage or persistent shared storage |

## First-time setup flow

The app reads the ABI list provided by Android and selects the first supported value from `arm64-v8a` or `armeabi-v7a`. It then downloads only the matching RootFS archive from the public `arch-rootfs-v010` release and calculates the SHA-256 digest before allowing extraction into private app storage. If the connection or verification fails, the app extracts no partial archive and does not mark Arch as installed.

| ABI | Published RootFS archive | SHA-256 |
|---|---|---|
| `arm64-v8a` | `arch-aarch64.tar` | `42a4eeaa038994ffd31fa173256ef2f0ef511358eeb41b9ea1f8626391b9b319` |
| `armeabi-v7a` | `arch-armv7.tar` | `ebe0fa119dea45e3af0aa61785676bdbf417bc5f754d529b87255dbf0ca4e3f0` |

> In the default private-storage mode, the app deletes the archive after extraction completes. When the user selects persistent shared storage from the command panel, the verified archive is kept at `/storage/emulated/0/ArchTerminal/rootfs/`. It survives app removal; after reinstalling, the app verifies its SHA-256, reuses it without a new download, and extracts a fresh app-private environment.

## Public assets repository

The public [`arch-terminal-source`](https://github.com/nnn308964-cpu/arch-terminal-source) repository contains the application source, tests, documentation, and the CI workflow. RootFS archives are published separately through the `arch-rootfs-v010` GitHub Release. The `main` branch is protected and requires the CI checks to pass before updates are merged.

## UI and background continuity

The terminal screen keeps the execution area as the primary surface, while start, stop, download, and file-permission actions are available from a side panel. The status bar shows PRoot, Arch, battery, and connection indicators. The setup card shows RootFS download percentage, transferred size, speed, verification, and extraction stages. The Android foreground service mirrors this state in a persistent system notification, allowing setup to continue after the app moves to the background while Android permits the service to run.

The user can select **Allow background activity without battery optimization** from the command panel. This opens Android's system screen for the app; the app does not disable battery optimization automatically and requires explicit user approval.

The **Arch storage setup** screen allows the user to choose private app storage or persistent shared storage. It displays the actual path and its `cd` command with a copy button. The **File access** action opens the RootFS directory when Android permits it, or opens the storage-permission screen when needed.

## Core files

The main implementation is in `android/app/src/main/kotlin/com/example/arch_terminal/terminal/RootfsDownloadManager.kt` for RootFS downloading, verification, and progress reporting; `ArchInstaller.kt` for extracting verified archives; `ArchSetupService.kt` for background setup; and `MainActivity.kt` for the Flutter bridge and battery settings. The two PRoot binaries are stored in `android/app/src/main/assets/bin/`. RootFS archives are not bundled in the APK.

## Build and verification commands

```bash
flutter analyze
flutter test
tools/verify_android_assets.sh
flutter build apk --release
```

The generated file is `build/app/outputs/flutter-apk/app-release.apk`. The verification process checks that both PRoot binaries are present and that `arch-aarch64.tar` and `arch-armv7.tar` are not bundled.

## Release notes

The current Release build is signed with the debug key for testing. Before a public production release, configure a dedicated release keystore and never share its keys. Linux and Windows support remains in the source for development; those packages are not built in this delivery.

## References

[1]: https://github.com/nnn308964-cpu/arch-terminal-source/releases/tag/arch-rootfs-v010 "Arch Linux RootFS v010"
[2]: https://developer.android.com/training/data-storage/manage-all-files "Android manage all files"
[3]: https://pub.dev/packages/kyroon_pty "kyroon_pty 1.0.6"
[4]: https://pub.dev/packages/xterm/versions "xterm 4.0.0"
[5]: https://developer.android.com/develop/background-work/services/foreground-services "Android foreground services"
[6]: https://developer.android.com/training/monitoring-device-state/doze-standby "Android battery optimization"

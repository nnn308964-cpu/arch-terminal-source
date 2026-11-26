# Embedded Android Assets

The two small PRoot binaries remain inside the universal APK, while **no Arch Linux RootFS archives are included in the source tree or the APK**.

| ABI | Embedded PRoot | External RootFS archive | Download source |
|---|---|---|---|
| `arm64-v8a` | `bin/arm64-v8a/proot` | `arch-aarch64.tar` | GitHub Release `arch-rootfs-v010` |
| `armeabi-v7a` | `bin/armeabi-v7a/proot` | `arch-armv7.tar` | GitHub Release `arch-rootfs-v010` |

When the user taps **Download and set up Arch**, the app selects a supported ABI, downloads the matching archive to `files/downloads/rootfs/` inside private app storage, and verifies the SHA-256 value defined in `rootfs-release-manifest.json` and `RootfsDownloadManager.kt`. It then extracts the archive to `files/arch/<abi>/`, the path used by PRoot. The temporary archive is deleted after successful installation.

ARM64 assets are never loaded on an ARM32 device, and vice versa. The extracted Arch environment is kept locally, so later sessions do not require another download.

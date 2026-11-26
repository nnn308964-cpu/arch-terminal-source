# Security Policy

Arch Terminal is designed as a local-first application. Terminal commands, RootFS files, session history, and local file previews must remain on the device unless the user explicitly configures an external AI provider and sends a request.

## Reporting a vulnerability

Please do not publish exploitable details in a public issue. Contact the repository owner privately through the GitHub security contact or the account that owns this repository. Include the affected version, device/ABI, reproduction steps, impact, and any relevant logs with secrets removed.

Never include API keys, passwords, signing keys, personal files, or RootFS archives in a report.

## Release security notes

Release APKs built by the public workflow use the repository's test/debug signing configuration until a protected production keystore is configured. Do not treat a debug-signed APK as an official production distribution. Production signing material must be stored outside GitHub source files and supplied through protected CI secrets.

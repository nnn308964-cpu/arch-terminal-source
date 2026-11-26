# Arch Terminal Repository Policy

This repository is the official source repository for **Arch Terminal**. It contains the Flutter/Android project, tests, and documentation required to build the application.

## Publishing rules

- Never commit signing keys, passwords, tokens, or other secrets.
- Never commit local build directories such as `build/`, `.gradle/`, or `.dart_tool/`.
- APK files produced by CI are published as GitHub Actions artifacts or Releases and are not stored in the source tree.
- Run analysis and tests before merging changes.

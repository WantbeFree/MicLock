# Contributing to MicLock

Thanks for improving MicLock. The project is intentionally small: native Objective-C/AppKit, menu bar only, Apple Silicon only, macOS 13+.

## Useful contributions

- Device compatibility reports for AirPods, Sony WH-1000XM, USB/XLR microphones, docks, webcams, and displays.
- CoreAudio reliability fixes.
- Menu clarity improvements.
- Release/signing/notarization improvements.
- README, FAQ, troubleshooting, and SEO improvements.

## Local build

```bash
xcodebuild \
  -project MicLock.xcodeproj \
  -scheme MicLock \
  -configuration Debug \
  -derivedDataPath build/DebugDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

## Release build

Unsigned local test package:

```bash
scripts/build_release.sh --unsigned
```

Signed and notarized package:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_PROFILE=MicLock \
scripts/build_release.sh
```

## Pull request checklist

- Keep MicLock native and Apple Silicon focused.
- Avoid network calls, telemetry, and audio recording.
- Do not add Rosetta or x86_64-only dependencies.
- Run a local build before opening a PR.
- Update `README.md` or `CHANGELOG.md` when behavior changes.


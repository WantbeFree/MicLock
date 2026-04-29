# Security Policy

## Supported versions

Only the latest MicLock release is supported.

## Reporting a vulnerability

Open a private security advisory on GitHub or contact the maintainer through the repository owner profile.

Please include:

- MicLock version.
- macOS version.
- Hardware model.
- Steps to reproduce.
- Expected and actual behavior.

## Privacy/security model

- MicLock does not record microphone audio.
- MicLock does not send network requests.
- MicLock does not include analytics or telemetry.
- MicLock reads CoreAudio device metadata and sets the default macOS input device.
- Preferences are stored locally via `NSUserDefaults`.


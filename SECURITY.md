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

- MicLock does not record microphone audio. While its menu is open it samples the active input to draw a live level meter; the samples are discarded immediately and never written to disk.
- MicLock does not send network requests.
- MicLock does not include analytics or telemetry.
- MicLock reads CoreAudio device metadata and sets the default macOS input device.
- Preferences are stored locally via `NSUserDefaults`.
- MicLock never elevates on its own. The only privileged action is the `Revive Audio...` menu item, which you have to click: it runs the fixed command `/usr/bin/killall coreaudiod` as root after macOS prompts you for administrator approval. The command is a compile-time constant with absolute paths and contains no user or device data.


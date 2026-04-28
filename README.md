# MicLock for macOS

<p align="center">
  <img src="MicLock/AppIconSource.png" width="128" alt="MicLock app icon">
</p>

Menu bar utility that keeps macOS on a better microphone when Bluetooth headphones try to become the default input device and reduce output quality.

## Releases

- Latest: [MicLock 1.6.3](https://github.com/WantbeFree/MicLock/releases/tag/v1.6.3)
- Build: macOS 13.0+, Apple Silicon (`arm64`)
- Package: unsigned local test build; Developer ID signing/notarization required for public distribution.

## What it does

- Monitors macOS input-device changes in real time.
- Keeps a selected primary microphone active when available.
- Falls back through three user-selected backup microphones in order.
- Falls back automatically to a built-in or other non-wireless input if the saved devices are unavailable.
- Prevents Bluetooth headset microphones from taking priority unless you explicitly choose them.
- Offers manual device refresh and CoreAudio restart for USB/audio devices that disappear after sleep.

## Current behavior

- Runs as a menu bar app with no Dock icon.
- Remembers the primary input and all fallback selections between launches.
- Shows saved primary/fallback inputs near the top of the menu with a checkmark on the active one.
- Shows disconnected fallback devices as unavailable while keeping their last known names visible in the menu.
- Refreshes again after macOS wakes from sleep, because USB audio interfaces can enumerate late.
- Notifies you when the selected primary microphone disappears from CoreAudio.
- Supports Apple Silicon Macs and runs natively without Rosetta.

## Requirements

- macOS 13.0 or newer
- Apple Silicon (`arm64`)

## Status

The app is currently maintained as a native Objective-C/AppKit utility. `scripts/build_release.sh` creates signed and notarized Developer ID releases by default when signing credentials are configured. Use `--unsigned` only for local test packages.

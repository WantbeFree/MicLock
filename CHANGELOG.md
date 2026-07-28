# Changelog

All notable changes to MicLock are documented here.

## 1.7.1 - 2026-07-28

- Fixed first launch taking over the microphone you were already using. MicLock now keeps the current input and only overrides it when macOS has landed on a Bluetooth, AirPlay, or Continuity device.
- Fixed the input health panel freezing when a device appeared or disappeared while the menu was open; the menu is now rebuilt after it closes.
- Fixed the level meter running at roughly half its intended rate: the capture buffer no longer straddles the update interval.
- Fallback slots can no longer be set to the device already chosen as Primary.
- Release packages ship as `MicLock.app`, so an upgrade replaces the previous install instead of sitting beside it.
- Notarization now requires a keychain profile; the app-specific password is never passed on the command line.
- Release builds keep their dSYM and print the artifact SHA256.
- Fixed the project's development team so the app builds from Xcode without signing errors.
- Documented the `Revive Audio...` privileged command in SECURITY.md and the README.

## 1.7.0 - 2026-06-10

- Added input health panel with live input level meter, volume slider, and mute toggle.
- Fixed live mute and volume updates by registering CoreAudio listeners per channel element.
- Fixed fallback menu selection persistence.
- Enabled Hardened Runtime with the audio-input entitlement; release signing now applies entitlements so the level meter works in notarized builds.
- Fixed admin-prompt cancellation detection on non-English systems (matches AppleScript error -128).
- Fixed a data race in the input level monitor and skipped redundant RMS computation between meter updates.
- Removed deprecated NSUserDefaults synchronize calls and a dead window outlet.
- Developer ID signed and Apple notarized release.

## 1.6.7 - 2026-04-29

- Fixed fallback selection normalization so menu selections persist instead of reverting to Disabled.
- Verified fallback action with a local CoreAudio smoke test: save, menu rebuild, and submenu checkmark.
- Developer ID signed and Apple notarized release.

## 1.6.6 - 2026-04-29

- Fixed fallback slot selections being overwritten by stale CoreAudio refresh snapshots.
- Flushes Primary, Fallback, and Pause preferences immediately after changes.
- Developer ID signed and Apple notarized release.

## 1.6.5 - 2026-04-28

- Developer ID signed and Apple notarized release.
- Gatekeeper verification passes with `source=Notarized Developer ID`.
- README and repository presentation expanded for discovery.

## 1.6.4 - 2026-04-28

- Developer ID signed release package.
- Fixed AppIcon generation to write exact macOS icon pixel sizes.
- Cleans extended attributes before signing release bundles.

## 1.6.3 - 2026-04-27

- Native Apple Silicon release.
- Improved saved input menu section.
- Added Primary plus three fallback microphone slots.
- Added safer CoreAudio refresh/revive workflows.

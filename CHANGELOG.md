# Changelog

All notable changes to MicLock are documented here.

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

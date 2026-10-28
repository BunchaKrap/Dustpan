# What's New in Dustpan

<!--
Write for people using Dustpan, not for developers: say what they'll notice, in plain words.
Each release gets a "## <version> — <date>" heading and up to three groups: ### New, ### Improved, ### Fixed.
release.sh publishes the matching section as the GitHub release notes, and the app shows it after updating.
-->

## Unreleased

### Fixed
- Scanning your whole startup disk no longer reports far more space than your Mac has. Dustpan was walking into a hidden macOS folder that mirrors the entire disk and counting everything twice.

## 0.2.2 — 28 October 2026

### Fixed
- Disk Space no longer gets stuck on an endless spinner when scanning your Library or Home folder. macOS was quietly waiting for you to allow access to other apps' data, and the scan sat there until you answered.

### Improved
- If a scan is waiting on a macOS permission, Dustpan now tells you right away: which folder, why, and what to click. There's a button that opens the right page in System Settings.
- After a scan, Dustpan lists the folders macOS kept it out of, so you know which sizes are missing and how to include them.
- After an update, Dustpan shows you what changed (you're reading it).

### New
- An installer package (.pkg) is now available on the releases page for first-time installs.

## 0.2.1 — 22 October 2026

### New
- Disk Space: measure any disk or folder in one click, then browse it as a list, a map, or a list of the largest files.
- Duplicates: find identical files and keep just one copy.
- History: see everything you've cleaned, and put things back from the Trash.
- Check for Updates: get new versions of Dustpan straight from the app.

### Improved
- A fresh new design with smoother animations.

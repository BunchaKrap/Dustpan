# What's New in Dustpan

<!--
Write for people using Dustpan, not for developers: say what they'll notice, in plain words.
Each release gets a "## <version> — <date>" heading and up to three groups: ### New, ### Improved, ### Fixed.
release.sh publishes the matching section as the GitHub release notes, and the app shows it after updating.
-->

## Unreleased

### Fixed
- **Updates install reliably.** If you first installed Dustpan with the installer package, a leftover backup could stop later updates from replacing the app, and Dustpan quietly reopened the old version.
- **Clear message if an update fails.** Dustpan now says so when it reopens, explains why, and offers to try again.

### Improved
- **A tidier What's New screen.** Each change has a short headline, and the window is always the same size.

## 0.2.3 — 29 October 2026

### New
- **Activity.** See everything running on your Mac, including background processes, with live CPU and memory use. Pick one to see what it is, who made it and whether it starts by itself, then quit it if you want.
- **Warning signs for suspicious programs.** Dustpan points out apps re-signed with a certificate Apple didn't issue (as cracked apps are), programs pretending to be part of macOS, and unverified programs that start automatically, and explains why each one matters.
- **Drifting ribbons.** Slow, soft strings move behind the content. Turn them off in Settings; they hold still when Reduce Motion is on.

### Fixed
- **Full-disk scans add up again.** Scanning your startup disk no longer reports far more space than your Mac has. Dustpan was counting a hidden macOS folder that mirrors the whole disk.
- **No more cramped text.** Sizes in the sidebar, buttons and footers no longer wrap onto two lines, and the folder path in Disk Space sits next to the back and up buttons.
- **Easier to read.** Hints and secondary text are darker, in both light and dark mode.

## 0.2.2 — 28 October 2026

### Fixed
- **Disk Space no longer gets stuck.** Scanning your Library or Home folder could spin forever while macOS quietly waited for you to allow access to other apps' data.

### Improved
- **Permission prompts explained.** If a scan is waiting on macOS, Dustpan tells you which folder, why, and what to click, with a button to the right page in System Settings.
- **Skipped folders listed.** After a scan, Dustpan shows the folders macOS kept it out of, so you know which sizes are missing.
- **What's New.** After an update, Dustpan shows you what changed (you're reading it).

### New
- **Installer package.** A .pkg is available on the releases page for first-time installs.

## 0.2.1 — 22 October 2026

### New
- **Disk Space.** Measure any disk or folder in one click, then browse it as a list, a map, or the largest files.
- **Duplicates.** Find identical files and keep just one copy.
- **History.** See everything you've cleaned, and put things back from the Trash.
- **Check for Updates.** Get new versions of Dustpan straight from the app.

### Improved
- **A fresh design** with smoother animations.

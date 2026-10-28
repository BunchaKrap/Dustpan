# Dustpan

**A native macOS cleaner that shows you exactly what it will remove — and never removes anything you didn't pick.**

Dustpan is a lightweight, CleanMyMac-style utility for Apple Silicon Macs. It finds reclaimable disk space (caches, logs, developer tool leftovers), shows what's eating your disk, and fully uninstalls apps including their leftover files. It is built with Swift and SwiftUI, has no dependencies, and runs entirely offline.

> Status: v0.2. Cleanup, Duplicates, Disk Space, Uninstaller and History all work. UI follows `Redesign/Dustpan v2.dc.html`.

---

## What it is

| | |
|---|---|
| Platform | macOS 14 Sonoma or later, Apple Silicon (arm64) |
| Language / UI | Swift 5.10, SwiftUI |
| Size | ~760 KB app bundle |
| Network | Only when you click **Check for Updates** (one request to GitHub). Nothing about your files leaves the Mac. |
| Permissions | None required for v1 (home-folder only). Full Disk Access planned. |
| Philosophy | Transparent, conservative, reversible |

### Core principles

1. **Nothing is preselected.** Every scan starts with zero items checked.
2. **Always confirm.** Before anything moves, a sheet lists every full path and its size.
3. **Reversible.** Items go to the Trash, not permanent deletion. You can put them back.
4. **Everything is logged.** Every attempt is written to `~/Library/Logs/Dustpan/deletions.log`.
5. **Conservative by default.** System caches, other apps' data, and anything with a safer native tool (e.g. `docker system prune`) are shown for information only, marked with a lock.

---

## Features

### 1. Cleanup (working)

Scans known safe-to-clean locations in your home folder, measures their size on disk, and groups results by category.

| Category | Locations | Deletable |
|---|---|---|
| User Caches | `~/Library/Caches/*` (one row per app) | Yes, except `com.apple.*` |
| User Logs | `~/Library/Logs/*` | Yes, except Dustpan's own log |
| Browser Caches | Chrome, Firefox, Edge, Brave caches | Yes |
| | Safari cache | Needs Full Disk Access (skipped) |
| Xcode & Simulators | DerivedData, iOS DeviceSupport, CoreSimulator caches | Yes |
| Homebrew Cache | `~/Library/Caches/Homebrew` | Yes |
| npm / Yarn / pnpm | npm `_cacache`, Yarn cache, pnpm cache | Yes |
| | pnpm store | Info only (use `pnpm store prune`) |
| Docker | Docker Desktop data | Info only (use `docker system prune`) |
| Trash | `~/.Trash` | Needs Full Disk Access (skipped) |

#### Scan depth and options

| Depth | Adds | Typical time |
|---|---|---|
| Quick | The locations above | ~3 s |
| Standard (default) | App caches in Application Support (Slack, VS Code, Discord…), crash reports, Gradle, CocoaPods, pip, Go, Cargo, Bun, Maven, Playwright, `~/.cache`, Xcode Previews; Archives and Simulator devices (info only) | ~5 s |
| Deep | Project build files (`node_modules`, `.build`, `target`, `Pods`, `.next`, virtualenvs…), installers (`.dmg/.pkg/.iso/.xip`) in Downloads, system caches and logs (info only) | 25–60 s |

Options popover: where Deep searches for build files (home folder, entire startup disk, or chosen folders), turn categories on/off, and a minimum item size (any / 1 / 10 / 100 MB). Options persist between launches. Project build files are only recognized next to their marker file (e.g. `node_modules` needs a sibling `package.json`), so random folders named `build` are never flagged.

CLI: `dustpan-cli disk ~/Documents`, `dustpan-cli dupes ~/Downloads`, `dustpan-cli history`, `dustpan-cli apps discord`, `dustpan-cli scan --depth deep --scope disk --min-mb 10 --verbose`

Typical result on a developer Mac: 10–30 GB reclaimable.

### 2. Disk Space (working)

A "Space Lens" style view. The start screen offers one-click targets: **Scan Entire Disk** for the startup disk and any external drives (with usage bars), folder presets (Home, Applications, Downloads, Documents, Desktop, Pictures, Movies, Music, iCloud Drive, Library, Developer), **Choose Folder…**, drag-and-drop, and recent scans. The tree is measured once; then three views read from it instantly:

- **List**: folders and files by size, with Back (⌘[), Up (⌘↑) and clickable breadcrumbs.
- **Map**: a squarified treemap of the current folder; click a block to zoom in.
- **Largest Files**: the 50 biggest files anywhere below the current folder, filterable by kind (videos, images, audio, archives, installers, documents).

Whole-disk scans skip firmlinked duplicates and macOS's `/.nofollow` and `/.resolve` aliases, so nothing is counted twice.

### 2b. Duplicates (working)

Finds files with identical contents in a chosen place. A parallel walk groups files by size, a head/tail SHA-256 splits those groups cheaply, and only remaining matches are hashed in full. Hard links count once; hidden files, packages and `~/Library` are skipped. Nothing is preselected: "Select Extra Copies" ticks all but the oldest (or newest) copy, and Dustpan refuses to trash every copy of a file. Home folder, 400k files: ~20 s.

### 2c. History (working)

Every cleanup, grouped by session and source (Cleanup, Disk Space, Duplicates, Uninstaller), with totals for all time and this month. Items still in the Trash can be **Put Back** to their original location (logged as `RESTORED`).

### 3. Uninstaller (working)

Lists apps in `/Applications`. Selecting one finds its leftovers by bundle identifier — preferences, caches, Application Support folders, logs, saved state — so removing an app removes all of it, not just the `.app`.

---

## How it works

### Architecture

```
┌────────────────────────────────────────────┐
│ DustpanApp (SwiftUI)                       │
│  RootView ─ sidebar: Cleanup│Disk│Uninstall │
│  CleanupView ◄── CleanupModel (@Observable) │
│  Shared: Checkbox, TrashConfirmationSheet,  │
│          DeletionProgressOverlay, Banner    │
└───────────────┬────────────────────────────┘
                │ async calls
┌───────────────▼────────────────────────────┐
│ DustpanCore (no UI, fully testable)         │
│  JunkLocations  → what to scan              │
│  JunkScanner    → concurrent, read-only     │
│  DirectorySizer → allocated bytes on disk   │
│  SafetyPolicy   → final gate before removal │
│  Deleter        → move to Trash + log       │
│  DeletionLog    → append-only TSV log       │
└────────────────────────────────────────────┘
      dustpan-cli: terminal harness (scan, selftest, log)
```

### Scan pipeline

1. **Locations.** Each `JunkLocation` declares a category, path, granularity (`whole` folder = one row, or `children` = one row per subfolder), whether deletion is allowed, whether it needs Full Disk Access, and excluded / protected names.
2. **Concurrent scan.** `JunkScanner` scans every location in parallel using a Swift task group. Missing folders are silently skipped. Scans can be cancelled.
3. **Sizing.** `DirectorySizer` walks each item with `FileManager.enumerator`, summing *allocated* size (what's really used on disk). Symlinks are never followed. Unreadable files are counted and reported, not guessed.
4. **Classification.** Each item is marked deletable or locked, with a human-readable note explaining why.
5. **Report.** Results come back grouped by category, sorted largest first, with totals and any issues.

### Delete pipeline

1. User ticks items → clicks **Move to Trash…**
2. Confirmation sheet lists every path + size. Cancel is the keyboard default.
3. `Deleter` first checks the log is writable. **If it can't log, it deletes nothing.**
4. Every path is re-checked by `SafetyPolicy`:
   - must be inside the home folder,
   - must not be a protected folder (`~`, `~/Library`, `~/Library/Caches`, `~/Documents`, `~/Desktop`, `~/Downloads`, `~/.ssh`, `~/.Trash`, and others),
   - must not contain `..`; parent symlinks are resolved first.
5. Allowed items are moved with `FileManager.trashItem`. Results update live in a progress overlay.
6. Each attempt is logged as `TRASHED`, `FAILED` or `REFUSED`:
   ```
   2026-09-15T10:12:03Z  TRASHED  48213  /Users/me/Library/Caches/com.spotify.client  -> /Users/me/.Trash/com.spotify.client
   ```
7. Removed items disappear from the list; a banner shows space moved and any failures.

---

## Updates

Dustpan updates itself from **GitHub Releases**. It never checks on its own: the sidebar's **Check for Updates** button (or Dustpan › Check for Updates…) asks GitHub for the latest release, and if it's newer the app:

1. downloads the `Dustpan-<version>-macOS.zip` attached to the release,
2. verifies it against the SHA-256 that GitHub publishes for the file,
3. checks the unpacked app has Dustpan's bundle identifier, the expected version and a valid code signature,
4. quits, swaps itself for the new version and reopens. If the swap fails, the old version is put back.

Publishing a release (needs the GitHub CLI: `brew install gh && gh auth login`; the repo must be public):

1. Add a `## 0.3.0 — <date>` section to [`CHANGELOG.md`](CHANGELOG.md) with `### New`, `### Improved` and `### Fixed` bullets, written for people using the app.
2. Run:

```bash
./release.sh 0.3.0
```

The changelog is the update log users see: `release.sh` publishes that section as the GitHub release notes (and refuses to release a version that has none), the Check for Updates sheet shows them before installing, and after Dustpan relaunches on the new version a **What's New** screen lists everything that changed since the version they had (Dustpan › What's New in Dustpan… shows it again any time).

`release.sh` builds with that version, bakes the repo name into the app (from `gh repo view`, or `DUSTPAN_REPO=owner/name`), zips it, builds the installer `.pkg`, and creates the `v0.3.0` release with both attached. Builds made with plain `./bundle.sh` have no repo set, and their update button says updates aren't set up.

## Building and running

Requires only Xcode Command Line Tools (no Xcode app).

```bash
swift build                             # build everything
swift run dustpan-cli selftest          # 44 core checks in a temp folder
swift run dustpan-cli scan --verbose    # read-only scan in the terminal
./bundle.sh release --open              # build build/Dustpan.app and launch
./pkg.sh 0.3.0                          # build build/Dustpan-0.3.0-macOS.pkg (installs to /Applications)
```

The `.pkg` is unsigned unless `DUSTPAN_INSTALLER_IDENTITY` names a "Developer ID Installer" certificate, so after downloading, macOS blocks it the first time: right-click › Open, or System Settings › Privacy & Security › Open Anyway.

`bundle.sh` compiles with SwiftPM, assembles the `.app` (Info.plist, resources), and ad-hoc signs it. The `xcrun … PlatformPath` warning during builds is harmless (no XCTest without full Xcode).

### Project layout

```
Package.swift
bundle.sh
Sources/
  DustpanCore/   Models, JunkLocations, JunkScanner, DirectorySizer,
                 SafetyPolicy, Deleter, DeletionLog
  DustpanApp/    DustpanApp (entry + sidebar), CleanupModel, CleanupView, Components
  DustpanCLI/    main.swift
```

---

## Design brief (for UI and icon design)

### Personality

Calm, trustworthy, tidy. Not alarmist ("Your Mac is at risk!") — the opposite. Dustpan should feel like a careful friend sweeping up: clear about what it found, honest about sizes, never pushy. Native macOS look (sidebar, materials, SF Symbols), with warmth.

### App icon

- Concept: a dustpan (optionally with a small brush or a few sparkle particles).
- macOS Big Sur+ style rounded-square icon, 1024×1024 master.
- Should read clearly at 16×16 in Finder and the menu bar.

### Window structure

- Standard `NavigationSplitView`: sidebar (~200 pt) + detail.
- Minimum window: 860 × 560 pt. Light and dark mode.

### Sidebar

| Item | Current SF Symbol | Needs custom icon? |
|---|---|---|
| Cleanup | `sparkles` | Optional |
| Disk Space | `chart.pie` | Optional |
| Uninstaller | `trash.square` | Optional |

### Screen: Cleanup — states to design

1. **Empty (never scanned):** illustration/icon, "No scan yet", one-line explanation that nothing is removed without confirmation, **Scan Now** button.
2. **Scanning:** progress indicator, "Scanning caches and logs…", Stop button. (Future: live per-category progress.)
3. **Results:**
   - Header: title "Cleanup", subtitle "11.8 GB can be cleaned · scanned in 3.3s", **Rescan** button.
   - List of categories, each collapsible: tri-state checkbox (off / partial / on), category icon, name, item count, reclaimable size.
   - Item rows: checkbox or lock icon, name, optional grey note (e.g. "Apps rebuild caches as needed"), size right-aligned. Right-click: Reveal in Finder, Copy Path.
   - Issue rows: warning icon + message (e.g. "Skipped: needs Full Disk Access").
   - Footer bar: **Deletion Log** button · Select All / Deselect All · "2.4 GB selected / 12 items" · red **Move to Trash…** button.
4. **Nothing found:** "Nothing to clean" with a checkmark seal.
5. **Confirmation sheet (620 × 480):** title "Clean up selected junk?", explanation text, scrollable list of full paths + sizes, Cancel + red "Move 12 Items to Trash".
6. **Deleting:** dimmed screen, centered card with "Moving to Trash…", progress bar, "7 of 12".
7. **Done banner:** green check (or orange warning if failures), "Moved 12 items (2.4 GB) to the Trash.", hint "Empty the Trash to actually free the space.", expandable failure details, close button.

### Category icons (currently SF Symbols)

| Category | SF Symbol |
|---|---|
| User Caches | `archivebox` |
| User Logs | `doc.text` |
| Browser Caches | `globe` |
| Xcode & Simulators | `hammer` |
| Homebrew Cache | `mug` |
| npm / Yarn / pnpm | `shippingbox` |
| Docker | `cube` |
| Trash | `trash` |

Status icons: lock (`lock.fill`), warning (`exclamationmark.triangle`), success (`checkmark.circle.fill`).

### Screens still to design

- **Disk Space:** folder picker / breadcrumb path, scanning progress (files counted, current path), ranked list or treemap/sunburst of largest items with size bars, drill-down into folders, Reveal in Finder, select to trash.
- **Uninstaller:** grid or list of installed apps (icon, name, version, size), search field, detail pane for the selected app listing the `.app` plus leftovers (Preferences, Caches, Application Support, Logs) with checkboxes and total size, **Uninstall…** button reusing the same confirmation sheet.
- **Full Disk Access onboarding (future):** explains why, button to open System Settings, how to verify.

### Data the UI can rely on

- Every item has: name, full path, size in bytes (formatted like "1.82 GB"), category, deletable yes/no, optional note.
- Every category has: total size, reclaimable size, item count, issues.
- Scan report has: total reclaimable, scan duration, timestamp.
- Deletion outcome has: items removed, bytes moved, failures with reasons.

---

## Roadmap

- [x] Project scaffold, SwiftPM packaging
- [x] Core junk scanner + safety policy + Trash + log
- [x] Cleanup UI with selection, confirmation, progress
- [x] Disk Space visualizer (whole tree measured once, ~17 s for 1.5 M files; drill-down, breadcrumbs, ⌘↑, Move to Trash)
- [x] App uninstaller (bundle-ID leftover detection across 13 Library locations; name matches flagged and unticked; blocks system and running apps)
- [ ] Full Disk Access support (Safari cache, Trash, system logs)
- [x] Custom app icon and visual design (4 icons, 4 accents, light/dark)
- [ ] Empty Trash action (separately confirmed)

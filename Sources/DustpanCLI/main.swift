import Foundation
import DustpanCore
import DustpanDesign

// Terminal harness for DustpanCore. Intentionally has no command that deletes real files.

import CryptoKit

func SHA256Hex(_ url: URL) -> String {
    SHA256.hash(data: (try? Data(contentsOf: url)) ?? Data()).map { String(format: "%02x", $0) }.joined()
}

func pad(_ s: String, _ n: Int) -> String { s.padding(toLength: max(n, s.count), withPad: " ", startingAt: 0) }

func runScan(options: ScanOptions, verbose: Bool) async {
    print("\(options.depth.displayName) scan… \(options.depth.summary)")
    let report = await JunkScanner(options: options).scan()
    print(String(format: "\nJunk scan finished in %.2fs\n", report.duration))

    for category in report.categories {
        print("\(pad(category.category.displayName, 22)) \(pad(category.reclaimableBytes.formattedBytes, 10)) reclaimable"
            + "  (\(category.items.count) items, \(category.totalBytes.formattedBytes) total)")
        if verbose {
            for item in category.items {
                let flag = item.isDeletable ? "  " : "🔒"
                print("   \(flag) \(pad(item.sizeBytes.formattedBytes, 10)) \(item.name)\(item.note.map { "  — \($0)" } ?? "")")
            }
        }
        for issue in category.issues {
            print("   ⚠️  \(issue.path): \(issue.message)")
        }
    }
    print("\nTotal reclaimable: \(report.reclaimableBytes.formattedBytes)")
    if !verbose { print("(run `dustpan-cli scan --verbose` to list every item)") }
}

// MARK: - Self-test (stands in for XCTest, which Command Line Tools lack)

/// Returns the number of failed checks.
func runSelfTest() async -> Int {
    var failures = 0
    func check(_ condition: Bool, _ label: String) {
        print("  \(condition ? "PASS" : "FAIL")  \(label)")
        if !condition { failures += 1 }
    }
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("dustpan-selftest-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }

    let caches = root.appendingPathComponent("Caches")
    let appA = caches.appendingPathComponent("com.example.a")
    let appB = caches.appendingPathComponent("com.example.b")
    try! fm.createDirectory(at: appA, withIntermediateDirectories: true)
    try! fm.createDirectory(at: appB.appendingPathComponent("nested"), withIntermediateDirectories: true)
    try! Data(count: 100_000).write(to: appA.appendingPathComponent("blob"))
    try! Data(count: 50_000).write(to: appB.appendingPathComponent("nested/blob"))
    try! fm.createDirectory(at: caches.appendingPathComponent("com.apple.test"), withIntermediateDirectories: true)
    try! Data(count: 10_000).write(to: caches.appendingPathComponent("com.apple.test/blob"))
    try! fm.createSymbolicLink(at: caches.appendingPathComponent("link-to-usr"), withDestinationURL: URL(fileURLWithPath: "/usr"))

    let policy = SafetyPolicy(allowedRoots: [root], protectedPaths: [root, caches])

    print("Sizer")
    let sizer = DirectorySizer()
    check(sizer.measure(appA).bytes >= 100_000, "counts file bytes")
    check(sizer.measure(appB).bytes >= 50_000, "recurses into subfolders")
    check(sizer.measure(caches.appendingPathComponent("link-to-usr")).bytes == 0, "does not follow symlinks")

    print("Scanner granularities")
    let support = root.appendingPathComponent("Support")
    try! fm.createDirectory(at: support.appendingPathComponent("Slack/Cache"), withIntermediateDirectories: true)
    try! Data(count: 20_000).write(to: support.appendingPathComponent("Slack/Cache/blob"))
    try! fm.createDirectory(at: support.appendingPathComponent("Slack/Documents"), withIntermediateDirectories: true)
    try! Data(count: 20_000).write(to: support.appendingPathComponent("Slack/Documents/keep"))
    let supportItems = JunkScanner(locations: [], policy: policy).scan(
        JunkLocation(category: .appCaches, name: "App", url: support, granularity: .matchingSubfolders(["Cache"]))).items
    check(supportItems.map(\.name) == ["Slack › Cache"], "matchingSubfolders finds only the cache subfolder")

    let downloads = root.appendingPathComponent("Downloads")
    try! fm.createDirectory(at: downloads, withIntermediateDirectories: true)
    try! Data(count: 20_000).write(to: downloads.appendingPathComponent("Setup.DMG"))
    try! Data(count: 20_000).write(to: downloads.appendingPathComponent("taxes.pdf"))
    let downloadItems = JunkScanner(locations: [], policy: policy).scan(
        JunkLocation(category: .installers, name: "DL", url: downloads, granularity: .childrenWithExtensions(["dmg"]))).items
    check(downloadItems.map(\.name) == ["Setup.DMG"], "childrenWithExtensions matches only installers")
    let bigOnly = JunkScanner(locations: [], minimumItemBytes: 1_000_000, policy: policy).scan(
        JunkLocation(category: .installers, name: "DL", url: downloads, granularity: .children)).items
    check(bigOnly.isEmpty, "minimum size filter hides small items")

    print("Depth catalog")
    let home = URL(fileURLWithPath: "/Users/example")
    let quick = JunkLocations.locations(depth: .quick, home: home)
    let deep = JunkLocations.locations(depth: .deep, home: home)
    check(!quick.contains { $0.category == .appCaches || $0.category == .installers }, "quick excludes standard/deep locations")
    check(deep.contains { $0.category == .installers } && deep.count > quick.count, "deep includes everything")
    let genericDeep = deep.first { $0.category == .userCaches }!
    check(genericDeep.excludedNames.isSuperset(of: ["Homebrew", "CocoaPods", "Google"]), "claimed caches excluded from User Caches")
    check(!(quick.first { $0.category == .userCaches }!.excludedNames.contains("CocoaPods")), "unclaimed at quick stays in User Caches")

    print("Artifact finder")
    let projects = root.appendingPathComponent("Projects")
    let web = projects.appendingPathComponent("web")
    try! fm.createDirectory(at: web.appendingPathComponent("node_modules/dep/node_modules"), withIntermediateDirectories: true)
    try! Data("{}".utf8).write(to: web.appendingPathComponent("package.json"))
    try! Data("{}".utf8).write(to: web.appendingPathComponent("node_modules/dep/package.json"))
    try! Data(count: 30_000).write(to: web.appendingPathComponent("node_modules/dep/index.js"))
    try! fm.createDirectory(at: projects.appendingPathComponent("loose/node_modules"), withIntermediateDirectories: true)
    try! fm.createDirectory(at: projects.appendingPathComponent("py/.venv"), withIntermediateDirectories: true)
    try! Data().write(to: projects.appendingPathComponent("py/.venv/pyvenv.cfg"))
    try! fm.createDirectory(at: projects.appendingPathComponent("Tool.app/Contents/node_modules"), withIntermediateDirectories: true)
    try! Data("{}".utf8).write(to: projects.appendingPathComponent("Tool.app/Contents/package.json"))
    let found = ArtifactFinder(home: root).find(in: [projects]).matches.map(\.url.path)
    check(found.contains { $0.hasSuffix("/Projects/web/node_modules") }, "finds node_modules next to package.json")
    check(found.filter { $0.hasSuffix("node_modules") }.count == 1, "ignores nested and orphan node_modules")
    check(found.contains { $0.hasSuffix("/Projects/py/.venv") }, "finds virtualenv by pyvenv.cfg")
    check(!found.contains { $0.contains("Tool.app") }, "does not descend into app bundles")

    print("Disk usage tree")
    let tree = root.appendingPathComponent("Tree")
    try! fm.createDirectory(at: tree.appendingPathComponent("big/inner"), withIntermediateDirectories: true)
    try! Data(count: 400_000).write(to: tree.appendingPathComponent("big/inner/huge.bin"))
    for n in 0..<5 { try! Data(count: 5_000 + n).write(to: tree.appendingPathComponent("small\(n).txt")) }
    let diskResult = await DiskUsageScanner(filesPerFolder: 2).scan(tree)
    let diskRoot = diskResult.root
    check(diskRoot.fileCount == 6, "counts every file")
    check(diskRoot.children.first?.name == "big", "largest child first")
    check(diskRoot.children.count == 3 && diskRoot.hiddenFileCount == 3, "keeps top files, summarises the rest")
    let big = diskRoot.children.first!
    let before = diskRoot.sizeBytes
    let inner = big.children.first!
    big.remove(inner)
    check(diskRoot.sizeBytes == before - inner.sizeBytes && diskRoot.fileCount == 5, "remove updates totals up the tree")
    check(inner.ancestry.count == 3, "ancestry walks to root")
    let locked = tree.appendingPathComponent("locked")
    try! fm.createDirectory(at: locked, withIntermediateDirectories: true)
    try! fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
    let (fresh, _, denied) = await DiskUsageScanner().scan(tree)
    try! fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
    check(denied.isEmpty, "Unix permissions aren't reported as a privacy block")
    check(DiskUsageScanner.plainPath(URL(string: "file:///.nofollow/")!) == "/.nofollow" && DiskUsageScanner.plainPath(URL(fileURLWithPath: "/")) == "/",
          "skip list matches folders reported with a trailing slash")
    let areaHome = "/Users/x"
    check(ProtectedArea.of(areaHome + "/Library/Containers/com.a.b/Data", home: areaHome) == .otherAppsData
          && ProtectedArea.of(areaHome + "/Library/Group Containers", home: areaHome) == .otherAppsData
          && ProtectedArea.of(areaHome + "/Desktop/a", home: areaHome) == .desktop
          && ProtectedArea.of(areaHome + "/DesktopStuff", home: areaHome) == .system
          && ProtectedArea.of("/Volumes/USB/x", home: areaHome) == .otherDisk, "classifies protected folders")
    let watch = FolderAccessWatch()
    let token = watch.begin("/slow")
    check(watch.stalled(longerThan: 60) == nil && watch.stalled(longerThan: -1)?.path == "/slow", "access watch reports the oldest open")
    watch.end(token)
    check(watch.stalled(longerThan: -1) == nil, "access watch forgets finished opens")
    let largest = fresh.largestFiles(limit: 2)
    check(largest.map(\.name) == ["huge.bin", "small4.txt"], "largestFiles walks the whole tree, biggest first")
    check(fresh.largestFiles(limit: 5) { FileKind.of($0.url) == .other }.first?.name == "huge.bin", "largestFiles honours a filter")
    check(FileKind.of(URL(fileURLWithPath: "/a/Clip.MOV")) == .video && FileKind.of(URL(fileURLWithPath: "/a/x.dmg")) == .installer,
          "file kinds by extension")

    print("Duplicates")
    let dupes = root.appendingPathComponent("Dupes")
    try! fm.createDirectory(at: dupes.appendingPathComponent("a/deep"), withIntermediateDirectories: true)
    try! fm.createDirectory(at: dupes.appendingPathComponent("b"), withIntermediateDirectories: true)
    var payload = Data(count: 300_000)
    payload[150_000] = 7
    try! payload.write(to: dupes.appendingPathComponent("a/one.bin"))
    try! payload.write(to: dupes.appendingPathComponent("a/deep/two.bin"))
    try! payload.write(to: dupes.appendingPathComponent("b/three.bin"))
    var middleDiffers = payload
    middleDiffers[150_000] = 9 // same size, head and tail: only the full hash tells them apart
    try! middleDiffers.write(to: dupes.appendingPathComponent("b/different.bin"))
    try! fm.linkItem(at: dupes.appendingPathComponent("a/one.bin"), to: dupes.appendingPathComponent("b/hardlink.bin"))
    try! Data(count: 1_000).write(to: dupes.appendingPathComponent("tiny1"))
    try! Data(count: 1_000).write(to: dupes.appendingPathComponent("tiny2"))
    let dupeReport = await DuplicateFinder(minimumBytes: 100_000, skippedPaths: []).scan(dupes)
    check(dupeReport.groups.count == 1, "finds one set of identical files")
    check(dupeReport.groups.first?.files.count == 3, "groups all copies, skips hard links and the near-copy")
    check(!dupeReport.groups.flatMap(\.files).contains { $0.url.lastPathComponent.hasPrefix("tiny") }, "ignores files below the minimum")
    let smallReport = await DuplicateFinder(minimumBytes: 0, skippedPaths: []).scan(dupes)
    check(smallReport.groups.contains { $0.files.count == 2 && $0.name.hasPrefix("tiny") }, "small files compare by full contents")

    print("History")
    let sampleLog = """
    # timestamp\taction\tbytes\tpath\tdetail
    2026-10-01T10:00:00Z\tTRASHED\t100\t/Users/me/a\t-> /Users/me/.Trash/a\tCleanup
    2026-10-01T10:00:05Z\tFAILED\t50\t/Users/me/b\tdenied\tCleanup
    2026-10-01T10:00:06Z\tTRASHED\t70\t/Users/me/c\t-> /Users/me/.Trash/c\tDisk Space
    2026-10-02T09:00:00Z\tTRASHED\t30\t/Users/me/d\t-> /Users/me/.Trash/d
    2026-10-02T09:05:00Z\tRESTORED\t30\t/Users/me/d\t<- /Users/me/.Trash/d\tHistory
    """
    let records = DeletionHistory.parse(sampleLog)
    let sessions = DeletionHistory.sessions(records)
    check(records.count == 5, "parses old and new log lines")
    check(sessions.count == 3 && sessions.first?.records.first?.name == "d", "groups sessions by time and source, newest first")
    check(sessions.last?.bytesMoved == 100 && sessions.last?.problems.count == 1, "session totals count only trashed items")
    check(DeletionHistory.restoredPaths(records) == ["/Users/me/d"], "tracks restored paths")
    let trashDir = root.appendingPathComponent("fake/.Trash")
    try! fm.createDirectory(at: trashDir, withIntermediateDirectories: true)
    try! Data(count: 10).write(to: trashDir.appendingPathComponent("doc.txt"))
    let original = root.appendingPathComponent("restored/doc.txt")
    let restoreLog = DeletionLog(fileURL: root.appendingPathComponent("log/restore.log"))
    let trashedRecord = DeletionHistory.parse("2026-10-01T10:00:00Z\tTRASHED\t10\t\(original.path)\t-> \(trashDir.path)/doc.txt")[0]
    try? DeletionHistory.restore(trashedRecord, log: restoreLog)
    check(fm.fileExists(atPath: original.path), "put back moves the item to its original path")
    check(((try? String(contentsOf: restoreLog.fileURL)) ?? "").contains("RESTORED"), "put back is logged")
    let outsideTrash = DeletionHistory.parse("2026-10-01T10:00:00Z\tTRASHED\t10\t\(root.path)/x\t-> \(original.path)")[0]
    check((try? DeletionHistory.restore(outsideTrash, log: restoreLog)) == nil, "put back refuses sources outside the Trash")

    print("Uninstaller")
    let fakeHome = root.appendingPathComponent("Home")
    let apps = root.appendingPathComponent("Applications")
    func makeApp(_ name: String, id: String, bundleName: String? = nil) {
        let contents = apps.appendingPathComponent("\(name).app/Contents")
        try! fm.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": "1.0"]
        if let bundleName { info["CFBundleName"] = bundleName }
        (info as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        try! Data(count: 10_000).write(to: contents.appendingPathComponent("binary"))
    }
    makeApp("Chrome", id: "com.google.Chrome")
    makeApp("Chrome Canary", id: "com.google.Chrome.canary")
    makeApp("Visual Studio Code", id: "com.microsoft.VSCode", bundleName: "Code")
    try! fm.createDirectory(at: apps.appendingPathComponent("Utilities/Tool.app/Contents"), withIntermediateDirectories: true)
    let catalog = AppCatalog.installedApps(in: [apps])
    check(catalog.map(\.name) == ["Chrome", "Chrome Canary", "Tool", "Visual Studio Code"], "lists apps including one sub-folder level")

    func touch(_ relative: String, directory: Bool = true) {
        let url = fakeHome.appendingPathComponent(relative)
        if directory {
            try! fm.createDirectory(at: url, withIntermediateDirectories: true)
            try! Data(count: 3_000).write(to: url.appendingPathComponent("data"))
        } else {
            try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! Data(count: 3_000).write(to: url)
        }
    }
    touch("Library/Caches/com.google.Chrome")
    touch("Library/Caches/com.google.Chrome.helper")
    touch("Library/Caches/com.google.Chrome.canary")
    touch("Library/Preferences/com.google.Chrome.plist", directory: false)
    touch("Library/Saved Application State/com.google.Chrome.savedState")
    touch("Library/Group Containers/EQHXZ8M8AV.com.google.Chrome")
    touch("Library/Application Support/Code")
    touch("Library/Application Support/Chrome")

    let finder = AppLeftoverFinder(home: fakeHome)
    let chrome = catalog.first { $0.name == "Chrome" }!
    let chromeFiles = finder.leftovers(for: chrome, otherApps: catalog)
    let chromeNames = chromeFiles.map(\.url.lastPathComponent)
    check(chromeFiles.first?.isApplication == true, "app bundle listed first")
    check(chromeNames.contains("com.google.Chrome.helper") && chromeNames.contains("com.google.Chrome.plist"), "matches bundle-id prefixes")
    check(!chromeNames.contains("com.google.Chrome.canary"), "ignores another app's identifier")
    check(chromeNames.contains("com.google.Chrome.savedState") && chromeNames.contains("EQHXZ8M8AV.com.google.Chrome"), "finds saved state and group container")
    check(chromeFiles.first { $0.url.lastPathComponent == "Chrome" }?.matchedByName == true, "name matches are flagged")
    let code = finder.leftovers(for: catalog.first { $0.name == "Visual Studio Code" }!, otherApps: catalog)
    check(code.contains { $0.url.lastPathComponent == "Code" }, "uses CFBundleName for support folders")

    let uninstallPolicy = SafetyPolicy.uninstaller(home: fm.homeDirectoryForCurrentUser)
    check((try? uninstallPolicy.validate(URL(fileURLWithPath: "/Applications/Foo.app")).get()) != nil, "uninstaller may remove /Applications/*.app")
    check((try? uninstallPolicy.validate(URL(fileURLWithPath: "/Applications")).get()) == nil, "uninstaller refuses /Applications itself")
    check((try? uninstallPolicy.validate(fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")).get()) == nil,
          "uninstaller refuses ~/Library/LaunchAgents itself")

    print("Scanner")
    let location = JunkLocation(category: .userCaches, name: "Test", url: caches, granularity: .children,
                                excludedNames: ["com.example.b"], protectedNamePrefixes: ["com.apple."])
    let report = await JunkScanner(locations: [location], policy: policy).scan()
    let items = report.allItems
    check(items.contains { $0.name == "com.example.a" && $0.isDeletable }, "lists deletable child")
    check(!items.contains { $0.name == "com.example.b" }, "honors excludedNames")
    check(items.contains { $0.name == "com.apple.test" && !$0.isDeletable }, "protected prefix is not deletable")
    check(items.first?.name == "com.example.a", "sorted largest first")

    print("Safety policy")
    check((try? policy.validate(appA).get()) != nil, "allows child of root")
    check((try? policy.validate(caches).get()) == nil, "refuses protected path")
    check((try? policy.validate(root).get()) == nil, "refuses the root itself")
    check((try? policy.validate(URL(fileURLWithPath: "/usr/bin")).get()) == nil, "refuses outside roots")
    check((try? policy.validate(caches.appendingPathComponent("../../etc")).get()) == nil, "refuses '..' paths")
    check((try? SafetyPolicy.userHome().validate(fm.homeDirectoryForCurrentUser).get()) == nil, "real policy refuses ~")

    print("Deleter")
    let logURL = root.appendingPathComponent("log/deletions.log")
    let deleter = Deleter(policy: policy, log: DeletionLog(fileURL: logURL)) { url in
        try FileManager.default.removeItem(at: url) // no Trash in tests
        return nil
    }
    let outcome = await deleter.delete([
        DeletionTarget(url: appA, sizeBytes: 100_000),
        DeletionTarget(url: caches, sizeBytes: 1), // must be refused
    ])
    check(!fm.fileExists(atPath: appA.path), "removes allowed target")
    check(fm.fileExists(atPath: caches.path), "keeps refused target")
    check(outcome.removed.count == 1 && outcome.failures.count == 1, "reports outcome")
    let logText = (try? String(contentsOf: logURL)) ?? ""
    check(logText.contains("TRASHED") && logText.contains(appA.path), "logs removed path")
    check(logText.contains("REFUSED"), "logs refused path")

    print("Changelog")
    let changelogText = """
    # What's New
    <!-- notes for writers -->
    ## 0.3.0 — 1 November 2026
    ### Fixed
    - Scans no longer hang,
      even in Library.
    ### New
    - A thing
    ## v0.2.1
    Plain release notes.
    - One bullet
    ## 0.2.0 — 1 October 2026
    ### New
    - First
    """
    let changelog = Changelog.parse(changelogText)
    check(changelog.map(\.version) == ["0.3.0", "0.2.1", "0.2.0"] && changelog[0].date == "1 November 2026" && changelog[1].date == nil,
          "reads versions and dates")
    check(changelog[0].sections == [ChangelogSection(title: "Fixed", items: ["Scans no longer hang, even in Library."]),
                                    ChangelogSection(title: "New", items: ["A thing"])], "groups items and joins wrapped bullets")
    check(changelog[1].sections == [ChangelogSection(title: "", items: ["Plain release notes.", "One bullet"])], "keeps notes without headings")
    check(Changelog.entries(changelog, after: "0.2.0", through: "0.3.0").map(\.version) == ["0.3.0", "0.2.1"],
          "shows every release since the one you had, newest first")
    check(Changelog.notes(for: "v0.3.0", in: changelogText) == "### Fixed\n- Scans no longer hang,\n  even in Library.\n### New\n- A thing"
          && Changelog.notes(for: "9.9.9", in: changelogText) == nil, "extracts one release's notes for publishing")

    print("Updater")
    check(GitHubUpdater.isNewer("v0.10.0", than: "0.9.2") && !GitHubUpdater.isNewer("1.0", than: "1.0.0")
          && !GitHubUpdater.isNewer("0.2.0", than: "0.3.0"), "compares versions numerically")
    let releaseJSON = """
    {"tag_name":"v0.3.0","name":"","body":"Faster scans","html_url":"https://github.com/me/dustpan/releases/tag/v0.3.0",
     "published_at":"2026-10-23T10:00:00Z","assets":[
       {"name":"notes.txt","size":10,"browser_download_url":"https://example.com/notes.txt","digest":null},
       {"name":"Dustpan-0.3.0-macOS.zip","size":900000,"browser_download_url":"https://example.com/d.zip","digest":"sha256:abc"}]}
    """
    let parsed = try? GitHubUpdater.parseRelease(Data(releaseJSON.utf8))
    check(parsed?.version == "0.3.0" && parsed?.title == "Dustpan 0.3.0" && parsed?.digest == "sha256:abc"
          && parsed?.downloadURL.lastPathComponent == "d.zip", "parses the latest release and picks the macOS zip")
    check(!GitHubUpdater(repo: "", bundleIdentifier: "x").isConfigured && GitHubUpdater(repo: "me/dustpan", bundleIdentifier: "x").isConfigured,
          "updates need an owner/name repo")

    // Build a tiny signed app, zip it like release.sh does, and run it through the real staging pipeline.
    let fakeApp = root.appendingPathComponent("rel/Dustpan.app")
    try! fm.createDirectory(at: fakeApp.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": "com.local.dustpan", "CFBundleShortVersionString": "0.3.0",
                                "CFBundleExecutable": "Dustpan", "CFBundlePackageType": "APPL"]
    try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: fakeApp.appendingPathComponent("Contents/Info.plist"))
    try! fm.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: fakeApp.appendingPathComponent("Contents/MacOS/Dustpan"))
    func shell(_ tool: String, _ args: [String]) { let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe(); try! p.run(); p.waitUntilExit() }
    shell("/usr/bin/codesign", ["--force", "--sign", "-", fakeApp.path])
    let zipURL = root.appendingPathComponent("rel/Dustpan-0.3.0-macOS.zip")
    shell("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", fakeApp.path, zipURL.path])
    let digest = "sha256:" + SHA256Hex(zipURL)
    func release(_ digest: String?, version: String = "0.3.0") -> ReleaseInfo {
        ReleaseInfo(version: version, title: "", notes: "", pageURL: zipURL, downloadURL: zipURL, sizeBytes: 0, digest: digest, publishedAt: nil)
    }
    let updater = GitHubUpdater(repo: "me/dustpan", bundleIdentifier: "com.local.dustpan")
    let staged = try? await updater.downloadAndStage(release(digest))
    check(staged?.lastPathComponent == "Dustpan.app" && fm.fileExists(atPath: staged?.appendingPathComponent("Contents/Info.plist").path ?? ""),
          "downloads, verifies and unpacks a signed release")
    let badSum = await (try? updater.downloadAndStage(release("sha256:" + String(repeating: "0", count: 64)))) == nil
    check(badSum, "rejects a download whose checksum doesn't match")
    let otherApp = await (try? GitHubUpdater(repo: "me/dustpan", bundleIdentifier: "com.evil.app").downloadAndStage(release(digest))) == nil
    check(otherApp, "rejects an app with a different bundle identifier")
    let wrongVersion = await (try? updater.downloadAndStage(release(digest, version: "9.9.9"))) == nil
    check(wrongVersion, "rejects a build whose version doesn't match the release")

    print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
    return failures
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "scan":
    var options = ScanOptions()
    var iterator = args.dropFirst().makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--depth":
            guard let value = iterator.next(), let depth = ScanDepth(rawValue: value) else { print("--depth quick|standard|deep"); exit(2) }
            options.depth = depth
        case "--scope":
            switch iterator.next() {
            case "home": options.scope = .home
            case "disk": options.scope = .startupDisk
            case let path?: options.scope = .folders([URL(fileURLWithPath: (path as NSString).expandingTildeInPath)])
            case nil: print("--scope home|disk|<folder>"); exit(2)
            }
        case "--min-mb":
            guard let value = iterator.next(), let mb = Int64(value) else { print("--min-mb <number>"); exit(2) }
            options.minimumItemBytes = mb * 1_000_000
        default:
            break
        }
    }
    await runScan(options: options, verbose: args.contains("--verbose") || args.contains("-v"))
case "selftest":
    exit(await runSelfTest() == 0 ? 0 : 1)
case "export-iconset":
    // dustpan-cli export-iconset <sweep|paper|catch|mark> <out.iconset>
    guard args.count == 3, let style = AppIconStyle(argument: args[1]) else {
        print("usage: dustpan-cli export-iconset <sweep|paper|catch|mark> <folder.iconset>"); exit(2)
    }
    let folder = URL(fileURLWithPath: args[2])
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            guard let png = AppIconArt.pngData(style, pixels: points * scale) else { print("render failed"); exit(1) }
            try! png.write(to: folder.appendingPathComponent(name))
        }
    }
    print("Wrote \(style.displayName) icon set to \(folder.path)")
case "disk":
    let target = URL(fileURLWithPath: ((args.count > 1 ? args[1] : "~") as NSString).expandingTildeInPath)
    print("Measuring \(target.path)…")
    let started = Date()
    let (tree, unreadable, denied) = await DiskUsageScanner().scan(target)
    print(String(format: "%@ in %d files · %.1fs · %d unreadable\n", tree.sizeBytes.formattedBytes, tree.fileCount, Date().timeIntervalSince(started), unreadable))
    for (area, folders) in Dictionary(grouping: denied, by: { ProtectedArea.of($0) }).sorted(by: { $0.value.count > $1.value.count }) {
        print("  macOS refused \(folders.count) folder(s) in \(area.name): grant \(area.settingsName) to include them")
    }
    for child in tree.children.prefix(20) {
        print("  \(pad(child.sizeBytes.formattedBytes, 10)) \(child.isDirectory ? "📁" : "  ") \(child.name)")
    }
case "dupes":
    let target = URL(fileURLWithPath: ((args.count > 1 ? args[1] : "~") as NSString).expandingTildeInPath)
    print("Looking for duplicates in \(target.path)…")
    let report = await DuplicateFinder().scan(target)
    print(String(format: "%@ in extra copies · %d sets · %d files · %.1fs\n", report.wastedBytes.formattedBytes, report.groups.count, report.filesScanned, report.duration))
    for group in report.groups.prefix(15) {
        print("  \(pad(group.wastedBytes.formattedBytes, 10)) \(group.files.count)× \(group.name)")
        for file in group.files { print("      \(file.url.path)") }
    }
case "update-check":
    // dustpan-cli update-check [owner/name]: what the in-app button would find.
    let repo = args.dropFirst().first { !$0.hasPrefix("--") } ?? "BunchaKrap/Dustpan"
    do {
        let release = try await GitHubUpdater(repo: repo, bundleIdentifier: "com.local.dustpan").latestRelease()
        print("Latest release at \(repo): \(release.version) · \(release.downloadURL.lastPathComponent) · \(release.digest ?? "no digest")")
        if args.contains("--download") {
            // Runs the same download, checksum, unpack and signature checks as the app, without installing.
            let staged = try await GitHubUpdater(repo: repo, bundleIdentifier: "com.local.dustpan").downloadAndStage(release)
            print("Downloaded, verified and staged: \(staged.path)")
        }
    } catch {
        print("\(repo): \(error)")
        exit(1)
    }
case "history":
    for session in DeletionHistory.sessions(DeletionHistory.load()).prefix(20) {
        print("\(session.date.formatted())  \(pad(session.source ?? "-", 12)) \(pad(session.bytesMoved.formattedBytes, 10)) \(session.trashed.count) items")
    }
case "apps":
    let catalog = AppCatalog.installedApps()
    print("\(catalog.count) apps")
    if args.count > 1 {
        let query = args.dropFirst().joined(separator: " ").lowercased()
        guard let app = catalog.first(where: { $0.name.lowercased() == query }) ?? catalog.first(where: { $0.name.lowercased().contains(query) }) else {
            print("No app matching \(query)"); exit(1)
        }
        print("\(app.name) \(app.version ?? "") · \(app.bundleIdentifier ?? "no bundle id")\(app.isSystemApp ? " · part of macOS" : "")")
        for leftover in AppLeftoverFinder().leftovers(for: app, otherApps: catalog) {
            print("  \(pad(leftover.sizeBytes.formattedBytes, 10)) \(pad(leftover.kind, 24)) \(leftover.url.path)\(leftover.matchedByName ? "  (name match)" : "")")
        }
    } else {
        for app in catalog { print("  \(app.name) \(app.version ?? "")\(app.isSystemApp ? "  [system]" : "")") }
    }
case "log":
    print(DeletionLog.default.fileURL.path)
case "release-notes":
    // Used by release.sh: prints one version's notes from CHANGELOG.md, or fails so nothing ships without them.
    let file = args.count > 2 ? args[2] : "CHANGELOG.md"
    guard args.count > 1, let text = try? String(contentsOfFile: file, encoding: .utf8),
          let notes = Changelog.notes(for: args[1], in: text) else {
        FileHandle.standardError.write("No notes for that version in CHANGELOG.md. Add a \"## <version> — <date>\" section first.\n".data(using: .utf8)!)
        exit(1)
    }
    print(notes)
default:
    print("""
    usage: dustpan-cli <command>
      scan [options]     scan junk locations (read-only)
        --depth quick|standard|deep   (default standard)
        --scope home|disk|<folder>    where deep scan looks for build files
        --min-mb <n>                  hide items smaller than n MB
        --verbose                     list every item
      disk [folder]      largest items in a folder (default ~)
      dupes [folder]     find identical files (default ~, 1 MB and up)
      history            recent cleanups from the deletion log
      update-check [repo] [--download]  what Check for Updates would find (default BunchaKrap/Dustpan)
      apps [name]        list apps, or show an app's leftover files
      selftest           run core checks in a temporary folder
      log                print the deletion log path
      release-notes <version> [file]  print a version's notes from CHANGELOG.md
    """)
}

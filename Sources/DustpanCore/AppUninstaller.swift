import Foundation

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let bundleIdentifier: String?
    /// CFBundleName, often the name used for support folders (e.g. "Code" for Visual Studio Code).
    public let bundleName: String?
    public let version: String?
    /// Part of macOS (a symlink into the sealed system volume, like Safari); can't be removed.
    public let isSystemApp: Bool

    public var id: URL { url }
}

public enum AppCatalog {
    public static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
    }

    /// Apps directly inside the roots, plus one level of sub-folders (e.g. /Applications/Utilities).
    public static func installedApps(in roots: [URL] = defaultRoots()) -> [InstalledApp] {
        let fm = FileManager.default
        var apps: [InstalledApp] = []
        var seen = Set<String>()

        func visit(_ folder: URL, depth: Int) {
            // Not .skipsHiddenFiles: Safari's symlink carries the hidden flag.
            guard let children = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                              options: []) else { return }
            for child in children where !child.lastPathComponent.hasPrefix(".") {
                if child.pathExtension == "app" {
                    guard let app = readApp(at: child) else { continue }
                    // Symlinks that just alias another installed app would show up twice.
                    let isSymlink = (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
                    if !app.isSystemApp, isSymlink { continue }
                    if seen.insert(child.path).inserted { apps.append(app) }
                } else if depth == 0, (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    visit(child, depth: 1)
                }
            }
        }

        roots.forEach { visit($0, depth: 0) }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func readApp(at url: URL) -> InstalledApp? {
        let isSymlink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        let resolved = url.resolvingSymlinksInPath()
        let info = NSDictionary(contentsOf: resolved.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        return InstalledApp(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            bundleIdentifier: info?["CFBundleIdentifier"] as? String,
            bundleName: info?["CFBundleName"] as? String,
            version: info?["CFBundleShortVersionString"] as? String,
            isSystemApp: isSymlink || resolved.path.hasPrefix("/System/")
        )
    }
}

public struct AppLeftover: Identifiable, Hashable, Sendable {
    public let url: URL
    public let kind: String
    public let sizeBytes: Int64
    /// Found by folder name rather than bundle identifier, so less certain. Not preselected.
    public let matchedByName: Bool
    public let isApplication: Bool

    public var id: URL { url }
    public var target: DeletionTarget { DeletionTarget(url: url, sizeBytes: sizeBytes) }
}

/// Finds the files an app leaves behind in ~/Library. Read-only.
public struct AppLeftoverFinder: Sendable {
    public let home: URL
    private let sizer = DirectorySizer()

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    private enum Match {
        /// `<id>` or `<id>.<anything>`
        case identifierPrefix
        /// Exactly this name (with `%@` replaced by the bundle identifier).
        case exact(String)
        /// Ends with `.<id>` (group containers are prefixed with a team ID).
        case identifierSuffix
    }

    private struct Location {
        let kind: String
        let folder: String
        let match: Match
        let allowsNameMatch: Bool
    }

    private static let locations: [Location] = [
        Location(kind: "Application Support", folder: "Library/Application Support", match: .identifierPrefix, allowsNameMatch: true),
        Location(kind: "Caches", folder: "Library/Caches", match: .identifierPrefix, allowsNameMatch: true),
        Location(kind: "Preferences", folder: "Library/Preferences", match: .identifierPrefix, allowsNameMatch: false),
        Location(kind: "Preferences (ByHost)", folder: "Library/Preferences/ByHost", match: .identifierPrefix, allowsNameMatch: false),
        Location(kind: "Saved Application State", folder: "Library/Saved Application State", match: .exact("%@.savedState"), allowsNameMatch: false),
        Location(kind: "Logs", folder: "Library/Logs", match: .identifierPrefix, allowsNameMatch: true),
        Location(kind: "HTTP Storage", folder: "Library/HTTPStorages", match: .identifierPrefix, allowsNameMatch: false),
        Location(kind: "WebKit Data", folder: "Library/WebKit", match: .exact("%@"), allowsNameMatch: false),
        Location(kind: "Cookies", folder: "Library/Cookies", match: .exact("%@.binarycookies"), allowsNameMatch: false),
        Location(kind: "Container", folder: "Library/Containers", match: .exact("%@"), allowsNameMatch: false),
        Location(kind: "Group Container", folder: "Library/Group Containers", match: .identifierSuffix, allowsNameMatch: false),
        Location(kind: "Application Scripts", folder: "Library/Application Scripts", match: .exact("%@"), allowsNameMatch: false),
        Location(kind: "Launch Agent", folder: "Library/LaunchAgents", match: .identifierPrefix, allowsNameMatch: false),
    ]

    /// Names too generic to trust as a folder match.
    private static let genericNames: Set<String> = [
        "apple", "google", "microsoft", "adobe", "electron", "helper", "updater", "app", "application", "data", "cache", "caches", "logs",
    ]

    /// The app bundle first, then leftovers largest first.
    /// `otherApps` prevents claiming files of another installed app whose identifier or name overlaps.
    public func leftovers(for app: InstalledApp, otherApps: [InstalledApp] = []) -> [AppLeftover] {
        let fm = FileManager.default
        let others = otherApps.filter { $0.url != app.url }
        let otherIDs = others.compactMap(\.bundleIdentifier)
        let otherNames = Set(others.flatMap { [$0.name, $0.bundleName].compactMap { $0 } })

        let candidateNames = Set([app.name, app.bundleName].compactMap { $0 })
            .filter { $0.count >= 3 && !Self.genericNames.contains($0.lowercased()) && !otherNames.contains($0) }

        var found: [URL: (kind: String, byName: Bool)] = [:]

        for location in Self.locations {
            let folder = home.appendingPathComponent(location.folder)

            if let id = app.bundleIdentifier {
                switch location.match {
                case .exact(let pattern):
                    let url = folder.appendingPathComponent(pattern.replacingOccurrences(of: "%@", with: id))
                    if fm.fileExists(atPath: url.path) { found[url] = (location.kind, false) }
                case .identifierPrefix, .identifierSuffix:
                    for name in childNames(of: folder) where Self.matches(name, id: id, mode: location.match, otherIDs: otherIDs) {
                        found[folder.appendingPathComponent(name)] = (location.kind, false)
                    }
                }
            }

            if location.allowsNameMatch {
                for name in candidateNames {
                    let url = folder.appendingPathComponent(name)
                    if found[url] == nil, fm.fileExists(atPath: url.path) { found[url] = (location.kind, true) }
                }
            }
        }

        let leftovers = found.map { url, info in
            AppLeftover(url: url, kind: info.kind, sizeBytes: sizer.measure(url).bytes, matchedByName: info.byName, isApplication: false)
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }

        let bundle = AppLeftover(url: app.url, kind: "Application", sizeBytes: sizer.measure(app.url).bytes,
                                 matchedByName: false, isApplication: true)
        return [bundle] + leftovers
    }

    private func childNames(of folder: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    private static func matches(_ name: String, id: String, mode: Match, otherIDs: [String]) -> Bool {
        switch mode {
        case .identifierPrefix:
            guard name == id || name.hasPrefix(id + ".") else { return false }
            // e.g. "com.google.Chrome.canary" belongs to Chrome Canary, not Chrome.
            return !otherIDs.contains { $0.count > id.count && $0.hasPrefix(id) && (name == $0 || name.hasPrefix($0 + ".")) }
        case .identifierSuffix:
            return name.hasSuffix("." + id)
        case .exact:
            return false
        }
    }
}

public extension SafetyPolicy {
    /// Home-folder rules plus app bundles in /Applications; top-level Library folders stay protected.
    static func uninstaller(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> SafetyPolicy {
        let base = SafetyPolicy.userHome(home)
        let lib = home.appendingPathComponent("Library")
        let extra = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
            lib.appendingPathComponent("Preferences/ByHost"),
            lib.appendingPathComponent("Saved Application State"),
            lib.appendingPathComponent("HTTPStorages"),
            lib.appendingPathComponent("WebKit"),
            lib.appendingPathComponent("Cookies"),
            lib.appendingPathComponent("Application Scripts"),
            lib.appendingPathComponent("LaunchAgents"),
        ]
        return SafetyPolicy(
            allowedRoots: [home, URL(fileURLWithPath: "/Applications")],
            protectedPaths: base.protectedPaths.map { URL(fileURLWithPath: $0) } + extra
        )
    }
}

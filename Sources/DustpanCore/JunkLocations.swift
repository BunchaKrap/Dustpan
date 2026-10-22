import Foundation

/// A place on disk the junk scanner looks at.
public struct JunkLocation: Sendable {
    public enum Granularity: Sendable {
        /// Each immediate child becomes its own selectable item (e.g. one row per app cache).
        case children
        /// The whole directory is one item.
        case whole
        /// For each immediate child, these relative subfolders become items if they exist
        /// (e.g. `Slack/Cache` inside Application Support).
        case matchingSubfolders([String])
        /// Immediate children with one of these file extensions (lowercase).
        case childrenWithExtensions(Set<String>)
    }

    public let category: JunkCategory
    public let name: String
    public let url: URL
    public let granularity: Granularity
    public let depth: ScanDepth
    public let allowsDeletion: Bool
    public let requiresFullDiskAccess: Bool
    /// Child names skipped (claimed by a more specific location, or our own files).
    public var excludedNames: Set<String>
    /// Items whose names start with these prefixes are listed but never deletable.
    public let protectedNamePrefixes: [String]
    public let note: String?

    public init(
        category: JunkCategory,
        name: String,
        url: URL,
        granularity: Granularity,
        depth: ScanDepth = .quick,
        allowsDeletion: Bool = true,
        requiresFullDiskAccess: Bool = false,
        excludedNames: Set<String> = [],
        protectedNamePrefixes: [String] = [],
        note: String? = nil
    ) {
        self.category = category
        self.name = name
        self.url = url
        self.granularity = granularity
        self.depth = depth
        self.allowsDeletion = allowsDeletion
        self.requiresFullDiskAccess = requiresFullDiskAccess
        self.excludedNames = excludedNames
        self.protectedNamePrefixes = protectedNamePrefixes
        self.note = note
    }
}

public enum JunkLocations {
    /// Locations active at `depth`. Cache folders claimed by a more specific location are excluded
    /// from the generic User Caches row so nothing is counted twice.
    public static func locations(depth: ScanDepth, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [JunkLocation] {
        let caches = home.appendingPathComponent("Library/Caches")
        let active = catalog(home: home).filter { $0.depth <= depth }

        let cachesPrefix = caches.path + "/"
        let claimed = Set(active.compactMap { location -> String? in
            guard location.url.path.hasPrefix(cachesPrefix) else { return nil }
            return location.url.path.dropFirst(cachesPrefix.count).split(separator: "/").first.map(String.init)
        })

        return active.map { location in
            guard location.url == caches else { return location }
            var generic = location
            generic.excludedNames.formUnion(claimed)
            return generic
        }
    }

    static func catalog(home: URL) -> [JunkLocation] {
        let library = home.appendingPathComponent("Library")
        let caches = library.appendingPathComponent("Caches")
        let developer = library.appendingPathComponent("Developer")
        let support = library.appendingPathComponent("Application Support")

        return [
            // MARK: Quick
            JunkLocation(
                category: .userCaches, name: "User Caches", url: caches, granularity: .children,
                protectedNamePrefixes: ["com.apple."],
                note: "Apps rebuild caches as needed"
            ),
            JunkLocation(
                category: .userLogs, name: "User Logs", url: library.appendingPathComponent("Logs"),
                granularity: .children,
                excludedNames: ["Dustpan"] // never offer to delete our own deletion log
            ),

            JunkLocation(category: .browserCaches, name: "Google Chrome", url: caches.appendingPathComponent("Google/Chrome"), granularity: .whole),
            JunkLocation(category: .browserCaches, name: "Firefox", url: caches.appendingPathComponent("Firefox"), granularity: .whole),
            JunkLocation(category: .browserCaches, name: "Microsoft Edge", url: caches.appendingPathComponent("com.microsoft.edgemac"), granularity: .whole),
            JunkLocation(category: .browserCaches, name: "Brave", url: caches.appendingPathComponent("BraveSoftware"), granularity: .whole),
            JunkLocation(category: .browserCaches, name: "Safari", url: caches.appendingPathComponent("com.apple.Safari"), granularity: .whole,
                         requiresFullDiskAccess: true),

            JunkLocation(category: .xcode, name: "DerivedData", url: developer.appendingPathComponent("Xcode/DerivedData"), granularity: .children,
                         note: "Rebuilt on next Xcode build"),
            JunkLocation(category: .xcode, name: "iOS DeviceSupport", url: developer.appendingPathComponent("Xcode/iOS DeviceSupport"), granularity: .children,
                         note: "Re-downloaded when a device connects"),
            JunkLocation(category: .xcode, name: "Simulator Caches", url: developer.appendingPathComponent("CoreSimulator/Caches"), granularity: .whole),

            JunkLocation(category: .homebrew, name: "Homebrew Downloads", url: caches.appendingPathComponent("Homebrew"), granularity: .whole,
                         note: "Equivalent to `brew cleanup -s`"),

            JunkLocation(category: .packageManagers, name: "npm cache", url: home.appendingPathComponent(".npm/_cacache"), granularity: .whole),
            JunkLocation(category: .packageManagers, name: "Yarn cache", url: caches.appendingPathComponent("Yarn"), granularity: .whole),
            JunkLocation(category: .packageManagers, name: "pnpm cache", url: caches.appendingPathComponent("pnpm"), granularity: .whole),
            JunkLocation(category: .packageManagers, name: "pnpm store", url: library.appendingPathComponent("pnpm/store"), granularity: .whole,
                         allowsDeletion: false, note: "Use `pnpm store prune`; deleting it breaks linked node_modules"),

            // Inside another app's container: reading it triggers a privacy prompt, and deleting the VM disk wipes all images.
            JunkLocation(category: .docker, name: "Docker Desktop data", url: library.appendingPathComponent("Containers/com.docker.docker"),
                         granularity: .whole, allowsDeletion: false, requiresFullDiskAccess: true,
                         note: "Use `docker system prune` instead"),

            JunkLocation(category: .trash, name: "Trash", url: home.appendingPathComponent(".Trash"), granularity: .whole,
                         allowsDeletion: false, requiresFullDiskAccess: true),

            // MARK: Standard
            JunkLocation(
                category: .appCaches, name: "App Caches", url: support,
                granularity: .matchingSubfolders([
                    "Cache", "Code Cache", "GPUCache", "CachedData", "CachedExtensionVSIXs",
                    "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache", "Service Worker/CacheStorage", "Crashpad/completed",
                ]),
                depth: .standard,
                excludedNames: ["Dustpan"],
                protectedNamePrefixes: ["com.apple."],
                note: "Chromium/Electron app cache, rebuilt automatically"
            ),
            JunkLocation(category: .userLogs, name: "Crash Reporter", url: support.appendingPathComponent("CrashReporter"), granularity: .whole,
                         depth: .standard),

            JunkLocation(category: .xcode, name: "watchOS DeviceSupport", url: developer.appendingPathComponent("Xcode/watchOS DeviceSupport"),
                         granularity: .children, depth: .standard, note: "Re-downloaded when a device connects"),
            JunkLocation(category: .xcode, name: "SwiftUI Previews", url: developer.appendingPathComponent("Xcode/UserData/Previews"),
                         granularity: .whole, depth: .standard),
            JunkLocation(category: .xcode, name: "Xcode Archives", url: developer.appendingPathComponent("Xcode/Archives"),
                         granularity: .children, depth: .standard, allowsDeletion: false,
                         note: "Needed to symbolicate crash reports; remove from Xcode Organizer"),
            JunkLocation(category: .xcode, name: "Simulator Devices", url: developer.appendingPathComponent("CoreSimulator/Devices"),
                         granularity: .whole, depth: .standard, allowsDeletion: false,
                         note: "Use `xcrun simctl delete unavailable`"),

            JunkLocation(category: .packageManagers, name: "CocoaPods cache", url: caches.appendingPathComponent("CocoaPods"), granularity: .whole, depth: .standard),
            JunkLocation(category: .packageManagers, name: "pip cache", url: caches.appendingPathComponent("pip"), granularity: .whole, depth: .standard),
            JunkLocation(category: .packageManagers, name: "Go build cache", url: caches.appendingPathComponent("go-build"), granularity: .whole, depth: .standard),
            JunkLocation(category: .packageManagers, name: "Playwright browsers", url: caches.appendingPathComponent("ms-playwright"), granularity: .whole,
                         depth: .standard, note: "Re-downloaded with `npx playwright install`"),
            JunkLocation(category: .packageManagers, name: "Gradle caches", url: home.appendingPathComponent(".gradle/caches"), granularity: .whole,
                         depth: .standard, note: "Dependencies re-download on next build"),
            JunkLocation(category: .packageManagers, name: "Cargo registry cache", url: home.appendingPathComponent(".cargo/registry/cache"), granularity: .whole,
                         depth: .standard),
            JunkLocation(category: .packageManagers, name: "Bun cache", url: home.appendingPathComponent(".bun/install/cache"), granularity: .whole,
                         depth: .standard),
            JunkLocation(category: .packageManagers, name: "Maven repository", url: home.appendingPathComponent(".m2/repository"), granularity: .whole,
                         depth: .standard, note: "Dependencies re-download on next build"),
            JunkLocation(category: .packageManagers, name: "~/.cache", url: home.appendingPathComponent(".cache"), granularity: .children,
                         depth: .standard, protectedNamePrefixes: ["huggingface"],
                         note: "Tool caches, re-created as needed"),

            // MARK: Deep
            JunkLocation(category: .installers, name: "Installers in Downloads", url: home.appendingPathComponent("Downloads"),
                         granularity: .childrenWithExtensions(["dmg", "pkg", "iso", "xip"]), depth: .deep,
                         note: "Installer file, usually safe to remove once installed"),

            JunkLocation(category: .systemJunk, name: "/Library/Caches", url: URL(fileURLWithPath: "/Library/Caches"), granularity: .whole,
                         depth: .deep, allowsDeletion: false, note: "Needs administrator rights, not cleaned yet"),
            JunkLocation(category: .systemJunk, name: "/Library/Logs", url: URL(fileURLWithPath: "/Library/Logs"), granularity: .whole,
                         depth: .deep, allowsDeletion: false, note: "Needs administrator rights, not cleaned yet"),
            JunkLocation(category: .systemJunk, name: "/var/log", url: URL(fileURLWithPath: "/private/var/log"), granularity: .whole,
                         depth: .deep, allowsDeletion: false, note: "Needs administrator rights, not cleaned yet"),
        ]
    }
}

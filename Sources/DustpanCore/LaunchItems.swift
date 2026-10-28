import Foundation

/// A launchd job: the plist that makes a program start automatically. Read-only.
public struct LaunchItem: Hashable, Sendable {
    public enum Scope: String, Sendable {
        /// ~/Library/LaunchAgents: starts when you log in, as you.
        case userAgent
        /// /Library/LaunchAgents: starts when anyone logs in.
        case globalAgent
        /// /Library/LaunchDaemons: starts with the Mac, as root.
        case daemon
    }

    public let label: String
    public let plist: URL
    public let program: String?
    public let scope: Scope
    public let runsAtLoad: Bool
    /// launchd restarts it whenever it quits.
    public let keepsAlive: Bool

    public init(label: String, plist: URL, program: String?, scope: Scope, runsAtLoad: Bool, keepsAlive: Bool) {
        self.label = label
        self.plist = plist
        self.program = program
        self.scope = scope
        self.runsAtLoad = runsAtLoad
        self.keepsAlive = keepsAlive
    }

    /// Started with `brew services`: something the person installed and chose to run.
    public var isHomebrewService: Bool {
        label.hasPrefix("homebrew.mxcl.") && ["/opt/homebrew/", "/usr/local/"].contains { program?.hasPrefix($0) == true }
    }

    public var startsWhen: String {
        switch scope {
        case .userAgent: "when you log in"
        case .globalAgent: "when anyone logs in"
        case .daemon: "when the Mac starts, with full system rights"
        }
    }
}

public enum LaunchItems {
    public static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [LaunchItem] {
        let folders: [(URL, LaunchItem.Scope)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .globalAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .daemon),
        ]
        return folders.flatMap { folder, scope in
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return files.filter { $0.pathExtension == "plist" }.compactMap { parse($0, scope: scope) }
        }
    }

    public static func parse(_ plist: URL, scope: LaunchItem.Scope) -> LaunchItem? {
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = dict["Label"] as? String else { return nil }
        let program = (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first
        // KeepAlive is either true or a dictionary of conditions; both mean launchd brings it back.
        let keepAlive = (dict["KeepAlive"] as? Bool) ?? (dict["KeepAlive"] is [String: Any])
        return LaunchItem(label: label, plist: plist, program: program, scope: scope,
                          runsAtLoad: dict["RunAtLoad"] as? Bool ?? false, keepsAlive: keepAlive)
    }

    /// The launch item that started `process`. Only processes launchd started directly count, so a
    /// server's worker processes aren't each reported as starting automatically.
    public static func item(for process: RunningProcess, in items: [LaunchItem]) -> LaunchItem? {
        LaunchItemIndex(items).item(for: process)
    }

    /// The launch item whose program is the file at `path`, if any. Matches the resolved program file.
    public static func item(for path: String, in items: [LaunchItem]) -> LaunchItem? {
        LaunchItemIndex(items).item(for: path)
    }
}

/// Launch items by program path, both as written and with symlinks resolved, so matching hundreds of
/// processes doesn't resolve every item's path again for each one.
public struct LaunchItemIndex: Sendable {
    private var byProgram: [String: LaunchItem] = [:]

    public init(_ items: [LaunchItem]) {
        for item in items.reversed() {
            guard let program = item.program else { continue }
            byProgram[program] = item
            byProgram[(program as NSString).resolvingSymlinksInPath] = item
        }
    }

    public func item(for process: RunningProcess) -> LaunchItem? {
        guard process.parentPID == 1, let path = process.path else { return nil }
        return item(for: path)
    }

    public func item(for path: String) -> LaunchItem? {
        byProgram[path] ?? byProgram[(path as NSString).resolvingSymlinksInPath]
    }
}

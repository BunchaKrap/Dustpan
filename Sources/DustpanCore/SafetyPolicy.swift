import Foundation

public enum SafetyViolation: Error, CustomStringConvertible, Sendable {
    case notFileURL
    case relativeComponents
    case outsideAllowedRoots(String)
    case protectedPath(String)

    public var description: String {
        switch self {
        case .notFileURL: "Not a file URL"
        case .relativeComponents: "Path contains '..'"
        case .outsideAllowedRoots(let p): "Outside allowed locations: \(p)"
        case .protectedPath(let p): "Protected folder: \(p)"
        }
    }
}

/// Last line of defense: every path is checked here before it is moved to the Trash.
public struct SafetyPolicy: Sendable {
    public let allowedRoots: [String]
    public let protectedPaths: Set<String>

    public init(allowedRoots: [URL], protectedPaths: [URL]) {
        self.allowedRoots = allowedRoots.map(Self.canonicalPath)
        self.protectedPaths = Set(protectedPaths.map(Self.canonicalPath))
    }

    public static func userHome(_ home: URL = FileManager.default.homeDirectoryForCurrentUser) -> SafetyPolicy {
        let lib = home.appendingPathComponent("Library")
        let protected = [
            home, lib,
            lib.appendingPathComponent("Caches"),
            lib.appendingPathComponent("Logs"),
            lib.appendingPathComponent("Logs/Dustpan"),
            lib.appendingPathComponent("Application Support"),
            lib.appendingPathComponent("Preferences"),
            lib.appendingPathComponent("Containers"),
            lib.appendingPathComponent("Group Containers"),
            lib.appendingPathComponent("Mobile Documents"),
            lib.appendingPathComponent("Keychains"),
            lib.appendingPathComponent("Developer"),
            lib.appendingPathComponent("Developer/Xcode"),
            lib.appendingPathComponent("Developer/Xcode/DerivedData"),
            lib.appendingPathComponent("Developer/Xcode/iOS DeviceSupport"),
            lib.appendingPathComponent("Developer/CoreSimulator"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Pictures"),
            home.appendingPathComponent("Movies"),
            home.appendingPathComponent("Music"),
            home.appendingPathComponent(".Trash"),
            home.appendingPathComponent(".ssh"),
            home.appendingPathComponent(".npm"),
            home.appendingPathComponent(".cache"),
            home.appendingPathComponent(".gradle"),
            home.appendingPathComponent(".cargo"),
            home.appendingPathComponent(".m2"),
            home.appendingPathComponent(".bun"),
        ]
        return SafetyPolicy(allowedRoots: [home], protectedPaths: protected)
    }

    public func validate(_ url: URL) -> Result<Void, SafetyViolation> {
        guard url.isFileURL else { return .failure(.notFileURL) }
        guard !url.pathComponents.contains("..") else { return .failure(.relativeComponents) }
        let path = Self.canonicalPath(url)
        guard allowedRoots.contains(where: { path.hasPrefix($0 + "/") }) else { return .failure(.outsideAllowedRoots(path)) }
        guard !protectedPaths.contains(path) else { return .failure(.protectedPath(path)) }
        return .success(())
    }

    /// Resolves symlinks in the parent but not the item itself, so a symlink is judged by where it lives.
    static func canonicalPath(_ url: URL) -> String {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath().path
        return (parent as NSString).appendingPathComponent(standardized.lastPathComponent)
    }
}

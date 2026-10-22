import Foundation

/// A regenerable folder inside a project, recognized by its name plus a marker file.
public struct ArtifactRule: Sendable {
    public let folderName: String
    /// At least one of these must exist next to the folder (empty = no requirement).
    public let siblingMarkers: [String]
    /// This must exist inside the folder, if set.
    public let childMarker: String?
    public let note: String

    public init(_ folderName: String, siblings: [String] = [], child: String? = nil, note: String) {
        self.folderName = folderName
        self.siblingMarkers = siblings
        self.childMarker = child
        self.note = note
    }

    public static let defaults: [ArtifactRule] = [
        ArtifactRule("node_modules", siblings: ["package.json"], note: "Restore with npm / yarn / pnpm install"),
        ArtifactRule(".build", siblings: ["Package.swift"], note: "SwiftPM build output, rebuilt on next build"),
        ArtifactRule("target", siblings: ["Cargo.toml"], note: "Cargo build output, rebuilt on next build"),
        ArtifactRule("Pods", siblings: ["Podfile"], note: "Restore with pod install"),
        ArtifactRule("build", siblings: ["build.gradle", "build.gradle.kts"], note: "Gradle build output"),
        ArtifactRule(".gradle", siblings: ["settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts"], note: "Gradle project cache"),
        ArtifactRule(".next", siblings: ["package.json"], note: "Next.js build cache"),
        ArtifactRule(".nuxt", siblings: ["package.json"], note: "Nuxt build output"),
        ArtifactRule(".turbo", siblings: ["package.json"], note: "Turborepo cache"),
        ArtifactRule(".parcel-cache", siblings: ["package.json"], note: "Parcel cache"),
        ArtifactRule(".dart_tool", siblings: ["pubspec.yaml"], note: "Dart / Flutter tool cache"),
        ArtifactRule(".venv", child: "pyvenv.cfg", note: "Python virtualenv, recreate with python -m venv"),
        ArtifactRule("venv", child: "pyvenv.cfg", note: "Python virtualenv, recreate with python -m venv"),
    ]
}

public struct ArtifactMatch: Sendable {
    public let url: URL
    public let rule: ArtifactRule
}

/// Walks folder trees looking for project build output. Read-only.
public struct ArtifactFinder: Sendable {
    private let rulesByName: [String: [ArtifactRule]]
    private let skippedPaths: Set<String>

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, rules: [ArtifactRule] = ArtifactRule.defaults) {
        rulesByName = Dictionary(grouping: rules, by: \.folderName)
        // Library is covered by the location catalog; media folders hold no projects and
        // may contain protected libraries; system paths aren't user projects.
        skippedPaths = Set([
            home.appendingPathComponent("Library"),
            home.appendingPathComponent(".Trash"),
            home.appendingPathComponent("Pictures"),
            home.appendingPathComponent("Music"),
            home.appendingPathComponent("Movies"),
        ].map(\.path) + ["/System", "/Volumes", "/dev", "/private", "/cores", "/Library", "/bin", "/sbin", "/usr/bin", "/usr/lib", "/usr/libexec"])
    }

    public func find(in roots: [URL], onProgress: (@Sendable (String) -> Void)? = nil) -> (matches: [ArtifactMatch], issues: [ScanIssue]) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        let keySet = Set(keys)
        var matches: [ArtifactMatch] = []
        var issues: [ScanIssue] = []

        final class Counter: @unchecked Sendable { var value = 0 }

        for root in roots {
            let failures = Counter()
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [],
                                                 errorHandler: { _, _ in failures.value += 1; return true }) else {
                issues.append(ScanIssue(path: root.path, message: "Couldn't open folder"))
                continue
            }

            var folders = 0
            while let url = enumerator.nextObject() as? URL {
                guard let values = try? url.resourceValues(forKeys: keySet),
                      values.isDirectory == true, values.isSymbolicLink != true else { continue }

                if skippedPaths.contains(url.path) || values.isPackage == true {
                    enumerator.skipDescendants()
                    continue
                }

                folders += 1
                if folders % 1000 == 0 {
                    if Task.isCancelled { break }
                    onProgress?("Searching \(url.deletingLastPathComponent().path) · \(folders.formatted()) folders")
                }

                let name = url.lastPathComponent
                if let candidates = rulesByName[name], let rule = candidates.first(where: { Self.matches($0, folder: url, fm: fm) }) {
                    matches.append(ArtifactMatch(url: url, rule: rule))
                    enumerator.skipDescendants()
                } else if name == "node_modules" || name == ".git" {
                    enumerator.skipDescendants()
                }
            }

            if failures.value > 0 {
                issues.append(ScanIssue(path: root.path, message: "\(failures.value.formatted()) folder(s) couldn't be read and were skipped"))
            }
        }
        return (matches, issues)
    }

    private static func matches(_ rule: ArtifactRule, folder: URL, fm: FileManager) -> Bool {
        if let child = rule.childMarker, !fm.fileExists(atPath: folder.appendingPathComponent(child).path) {
            return false
        }
        guard !rule.siblingMarkers.isEmpty else { return true }
        let parent = folder.deletingLastPathComponent()
        return rule.siblingMarkers.contains { fm.fileExists(atPath: parent.appendingPathComponent($0).path) }
    }
}

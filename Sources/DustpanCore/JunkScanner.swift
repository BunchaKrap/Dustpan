import Foundation

public struct ScanProgress: Sendable {
    /// What is being looked at right now, if this update carries a message.
    public let message: String?
    /// Finished scan units (locations plus the build-file search) out of `total`, if this update carries a count.
    public let completed: Int?
    public let total: Int
}

public struct JunkScanner: Sendable {
    public var locations: [JunkLocation]
    /// Folders searched for project build files. Empty means no search.
    public var artifactRoots: [URL]
    public var minimumItemBytes: Int64
    public var policy: SafetyPolicy
    private let home: URL
    private let sizer = DirectorySizer()

    public init(options: ScanOptions = ScanOptions(),
                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                policy: SafetyPolicy = .userHome()) {
        self.init(
            locations: JunkLocations.locations(depth: options.depth, home: home).filter { options.includes($0.category) },
            artifactRoots: options.includes(.devArtifacts) ? options.scope.roots(home: home) : [],
            minimumItemBytes: options.minimumItemBytes,
            home: home,
            policy: policy
        )
    }

    public init(locations: [JunkLocation], artifactRoots: [URL] = [], minimumItemBytes: Int64 = 0,
                home: URL = FileManager.default.homeDirectoryForCurrentUser, policy: SafetyPolicy = .userHome()) {
        self.locations = locations
        self.artifactRoots = artifactRoots
        self.minimumItemBytes = minimumItemBytes
        self.home = home
        self.policy = policy
    }

    /// Scans all locations concurrently. Never modifies anything.
    public func scan(onProgress: (@Sendable (ScanProgress) -> Void)? = nil) async -> JunkScanReport {
        let start = Date()
        let total = locations.count + (artifactRoots.isEmpty ? 0 : 1)
        let report: @Sendable (String) -> Void = { onProgress?(ScanProgress(message: $0, completed: nil, total: total)) }
        var completed = 0
        var itemsByCategory: [JunkCategory: [JunkItem]] = [:]
        var issuesByCategory: [JunkCategory: [ScanIssue]] = [:]

        await withTaskGroup(of: (JunkCategory, [JunkItem], [ScanIssue]).self) { group in
            for location in locations {
                group.addTask {
                    report(location.url.path)
                    let result = scan(location)
                    return (location.category, result.items, result.issues)
                }
            }
            if !artifactRoots.isEmpty {
                group.addTask {
                    let result = scanArtifacts(onProgress: report)
                    return (.devArtifacts, result.items, result.issues)
                }
            }
            for await (category, items, issues) in group {
                completed += 1
                onProgress?(ScanProgress(message: nil, completed: completed, total: total))
                itemsByCategory[category, default: []] += items
                issuesByCategory[category, default: []] += issues
            }
        }

        let categories = JunkCategory.allCases.compactMap { category -> CategoryResult? in
            let items = itemsByCategory[category] ?? []
            let issues = issuesByCategory[category] ?? []
            guard !items.isEmpty || !issues.isEmpty else { return nil }
            return CategoryResult(category: category, items: items.sorted { $0.sizeBytes > $1.sizeBytes }, issues: issues)
        }
        return JunkScanReport(categories: categories, scannedAt: start, duration: Date().timeIntervalSince(start))
    }

    public func scan(_ location: JunkLocation) -> (items: [JunkItem], issues: [ScanIssue]) {
        let fm = FileManager.default
        let path = location.url.path
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { return ([], []) }

        if location.requiresFullDiskAccess {
            return ([], [ScanIssue(path: path, message: "Skipped: needs Full Disk Access (not enabled yet)")])
        }

        var candidates: [(url: URL, name: String)] = []
        switch location.granularity {
        case .whole:
            candidates = [(location.url, location.name)]

        case .children, .matchingSubfolders, .childrenWithExtensions:
            guard isDirectory.boolValue else { return ([], []) }
            let children: [URL]
            do {
                children = try fm.contentsOfDirectory(at: location.url, includingPropertiesForKeys: nil)
                    .filter { !location.excludedNames.contains($0.lastPathComponent) }
            } catch {
                return ([], [ScanIssue(path: path, message: error.localizedDescription)])
            }

            switch location.granularity {
            case .children:
                candidates = children.map { ($0, $0.lastPathComponent) }
            case .childrenWithExtensions(let extensions):
                candidates = children
                    .filter { extensions.contains($0.pathExtension.lowercased()) }
                    .map { ($0, $0.lastPathComponent) }
            case .matchingSubfolders(let subpaths):
                candidates = children.flatMap { child in
                    subpaths.compactMap { subpath -> (URL, String)? in
                        let url = child.appendingPathComponent(subpath)
                        var isDir: ObjCBool = false
                        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
                        return (url, "\(child.lastPathComponent) › \(subpath)")
                    }
                }
            case .whole:
                break
            }
        }

        var items: [JunkItem] = []
        var unreadable = 0
        for candidate in candidates {
            if Task.isCancelled { break }
            let measured = sizer.measure(candidate.url)
            unreadable += measured.unreadable
            guard measured.bytes > 0, measured.bytes >= minimumItemBytes else { continue }
            items.append(makeItem(category: location.category, url: candidate.url, name: candidate.name, bytes: measured.bytes,
                                  allowsDeletion: location.allowsDeletion, note: location.note,
                                  protectedPrefixes: location.protectedNamePrefixes))
        }
        return (items, unreadableIssue(path: path, count: unreadable))
    }

    private func scanArtifacts(onProgress: (@Sendable (String) -> Void)?) -> (items: [JunkItem], issues: [ScanIssue]) {
        let found = ArtifactFinder(home: home).find(in: artifactRoots, onProgress: onProgress)
        var items: [JunkItem] = []
        for match in found.matches {
            if Task.isCancelled { break }
            let bytes = sizer.measure(match.url).bytes
            guard bytes > 0, bytes >= minimumItemBytes else { continue }
            items.append(makeItem(category: .devArtifacts, url: match.url, name: abbreviate(match.url), bytes: bytes,
                                  allowsDeletion: true, note: match.rule.note, protectedPrefixes: []))
        }
        return (items, found.issues)
    }

    private func makeItem(category: JunkCategory, url: URL, name: String, bytes: Int64,
                          allowsDeletion: Bool, note: String?, protectedPrefixes: [String]) -> JunkItem {
        var deletable = allowsDeletion
        var note = note

        if protectedPrefixes.contains(where: { name.hasPrefix($0) }) {
            deletable = false
            note = "Left alone for safety"
        }
        if deletable, case .failure(let violation) = policy.validate(url) {
            deletable = false
            if case .outsideAllowedRoots = violation {
                note = "Outside your home folder, shown for information only"
            } else {
                note = violation.description
            }
        }
        return JunkItem(category: category, name: name, url: url, sizeBytes: bytes, isDeletable: deletable, note: note)
    }

    private func abbreviate(_ url: URL) -> String {
        let homePath = home.path
        return url.path.hasPrefix(homePath + "/") ? "~" + url.path.dropFirst(homePath.count) : url.path
    }

    private func unreadableIssue(path: String, count: Int) -> [ScanIssue] {
        count > 0 ? [ScanIssue(path: path, message: "\(count) item(s) could not be read and weren't counted")] : []
    }
}

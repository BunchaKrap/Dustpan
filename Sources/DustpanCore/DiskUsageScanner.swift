import Foundation

/// A file or folder in a disk-usage tree. Built off the main thread by `DiskUsageScanner`;
/// after the scan returns, mutate it (via `remove`) from one thread only.
public final class DiskNode: Identifiable, @unchecked Sendable {
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public internal(set) var sizeBytes: Int64
    /// Files contained in this node (1 for a file).
    public internal(set) var fileCount: Int
    /// Sub-folders plus the largest files, largest first.
    public internal(set) var children: [DiskNode] = []
    /// Smaller files in this folder that aren't listed individually.
    public internal(set) var hiddenFileCount = 0
    public internal(set) var hiddenFileBytes: Int64 = 0
    public internal(set) weak var parent: DiskNode?

    public var id: URL { url }

    init(url: URL, name: String, isDirectory: Bool, sizeBytes: Int64 = 0, fileCount: Int = 0) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
        self.fileCount = fileCount
    }

    /// Path from the scan root down to this node.
    public var ancestry: [DiskNode] {
        var chain: [DiskNode] = []
        var node: DiskNode? = self
        while let current = node {
            chain.insert(current, at: 0)
            node = current.parent
        }
        return chain
    }

    /// The biggest files anywhere below this node, largest first. Exact for `limit` up to the
    /// scanner's `filesPerFolder`, since every folder keeps at least that many of its largest files.
    public func largestFiles(limit: Int, where include: (DiskNode) -> Bool = { _ in true }) -> [DiskNode] {
        var top: [DiskNode] = []
        var stack: [DiskNode] = [self]
        while let node = stack.popLast() {
            for child in node.children {
                if child.isDirectory {
                    stack.append(child)
                    continue
                }
                if top.count == limit, let smallest = top.last, child.sizeBytes <= smallest.sizeBytes { continue }
                guard include(child) else { continue }
                let index = top.firstIndex { $0.sizeBytes < child.sizeBytes } ?? top.endIndex
                top.insert(child, at: index)
                if top.count > limit { top.removeLast() }
            }
        }
        return top
    }

    /// Detaches a child (e.g. after it was moved to the Trash) and updates totals up the tree.
    public func remove(_ child: DiskNode) {
        guard let index = children.firstIndex(where: { $0 === child }) else { return }
        children.remove(at: index)
        var node: DiskNode? = self
        while let current = node {
            current.sizeBytes -= child.sizeBytes
            current.fileCount -= child.fileCount
            node = current.parent
        }
    }
}

public struct DiskScanProgress: Sendable {
    public let filesSeen: Int
    public let bytesSeen: Int64
    public let currentPath: String
}

/// Measures a whole folder tree once so any folder inside can be browsed instantly. Read-only.
public struct DiskUsageScanner: Sendable {
    /// How many individual files each folder keeps; the rest are summarised.
    public var filesPerFolder: Int
    /// Never descended into (duplicate firmlinked system data, other volumes, virtual filesystems).
    public var skippedPaths: Set<String>

    public init(filesPerFolder: Int = 50,
                skippedPaths: Set<String> = ["/System/Volumes", "/Volumes", "/dev", "/private/var/vm", "/cores", "/.nofollow", "/.resolve", "/.vol"]) {
        self.filesPerFolder = filesPerFolder
        self.skippedPaths = skippedPaths
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// `denied` lists the folders macOS privacy protections refused to open (at most `Tally.deniedLimit`).
    public func scan(_ root: URL, onProgress: (@Sendable (DiskScanProgress) -> Void)? = nil) async -> (root: DiskNode, unreadable: Int, denied: [String]) {
        let tally = Tally(onProgress: onProgress)
        let rootNode = DiskNode(url: root, name: root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent, isDirectory: true)

        guard let contents = listing(of: root, tally: tally) else { return (rootNode, tally.unreadableCount, tally.deniedFolders) }
        var files: [DiskNode] = []
        var directories: [URL] = []
        for child in contents {
            switch classify(child, tally: tally) {
            case .file(let node): files.append(node)
            case .directory: directories.append(child)
            case .skip: break
            }
        }

        let subfolders = await buildInParallel(directories, depth: 1, tally: tally)
        assemble(rootNode, directories: subfolders, files: files)
        return (rootNode, tally.unreadableCount, tally.deniedFolders)
    }

    /// The top few levels fan out across cores (big trees like ~/Library are wide); deeper levels walk sequentially.
    private static let parallelDepth = 3

    private func buildInParallel(_ directories: [URL], depth: Int, tally: Tally) async -> [DiskNode] {
        await withTaskGroup(of: DiskNode.self) { group in
            for directory in directories {
                group.addTask {
                    depth < Self.parallelDepth
                        ? await buildDirectoryAsync(directory, depth: depth, tally: tally)
                        : buildDirectory(directory, tally: tally)
                }
            }
            var nodes: [DiskNode] = []
            for await node in group {
                nodes.append(node)
            }
            return nodes
        }
    }

    private func buildDirectoryAsync(_ url: URL, depth: Int, tally: Tally) async -> DiskNode {
        let node = DiskNode(url: url, name: url.lastPathComponent, isDirectory: true)
        guard !Task.isCancelled, let contents = listing(of: url, tally: tally) else { return node }

        var files: [DiskNode] = []
        var directories: [URL] = []
        for child in contents {
            switch classify(child, tally: tally) {
            case .file(let file): files.append(file)
            case .directory: directories.append(child)
            case .skip: break
            }
        }
        let subfolders = await buildInParallel(directories, depth: depth + 1, tally: tally)
        assemble(node, directories: subfolders, files: files)
        return node
    }

    private enum Entry {
        case file(DiskNode)
        case directory
        case skip
    }

    private func classify(_ url: URL, tally: Tally) -> Entry {
        guard let values = try? url.resourceValues(forKeys: Set(Self.keys)) else {
            tally.addUnreadable()
            return .skip
        }
        if values.isSymbolicLink == true { return .skip }
        if values.isDirectory == true {
            return skippedPaths.contains(Self.plainPath(url)) ? .skip : .directory
        }
        let bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        tally.addFile(bytes: bytes, path: url.path)
        return .file(DiskNode(url: url, name: url.lastPathComponent, isDirectory: false, sizeBytes: bytes, fileCount: 1))
    }

    /// Foundation reports some special folders with a trailing slash ("/.nofollow/"), which would slip past `skippedPaths`.
    public static func plainPath(_ url: URL) -> String {
        let path = url.path
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Registered with `FolderAccessWatch` because macOS may hold the open until a permission dialog is answered.
    private func listing(of url: URL, tally: Tally) -> [URL]? {
        let token = FolderAccessWatch.shared.begin(url.path)
        defer { FolderAccessWatch.shared.end(token) }
        do {
            return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Self.keys, options: [])
        } catch {
            tally.addUnreadable(deniedFolder: error.isPrivacyDenied ? url.path : nil)
            return nil
        }
    }

    private func buildDirectory(_ url: URL, tally: Tally) -> DiskNode {
        let node = DiskNode(url: url, name: url.lastPathComponent, isDirectory: true)
        guard !Task.isCancelled, let contents = listing(of: url, tally: tally) else { return node }

        var files: [DiskNode] = []
        var directories: [DiskNode] = []
        for child in contents {
            switch classify(child, tally: tally) {
            case .file(let file): files.append(file)
            case .directory: directories.append(buildDirectory(child, tally: tally))
            case .skip: break
            }
        }
        assemble(node, directories: directories, files: files)
        return node
    }

    private func assemble(_ node: DiskNode, directories: [DiskNode], files: [DiskNode]) {
        let sortedFiles = files.sorted { $0.sizeBytes > $1.sizeBytes }
        let kept = sortedFiles.prefix(filesPerFolder)
        let hidden = sortedFiles.dropFirst(filesPerFolder)

        node.children = (directories + kept).sorted { $0.sizeBytes > $1.sizeBytes }
        node.hiddenFileCount = hidden.count
        node.hiddenFileBytes = hidden.reduce(0) { $0 + $1.sizeBytes }
        node.sizeBytes = directories.reduce(0) { $0 + $1.sizeBytes } + files.reduce(0) { $0 + $1.sizeBytes }
        node.fileCount = directories.reduce(0) { $0 + $1.fileCount } + files.count
        for child in node.children {
            child.parent = node
        }
    }

    /// Thread-safe counters shared by the parallel walkers.
    private final class Tally: @unchecked Sendable {
        private let lock = NSLock()
        private let onProgress: (@Sendable (DiskScanProgress) -> Void)?
        private var files = 0
        private var bytes: Int64 = 0
        private var unreadable = 0
        private var denied: [String] = []
        private var lastReported = 0
        static let deniedLimit = 500

        init(onProgress: (@Sendable (DiskScanProgress) -> Void)?) {
            self.onProgress = onProgress
        }

        var unreadableCount: Int {
            lock.lock(); defer { lock.unlock() }
            return unreadable
        }

        var deniedFolders: [String] {
            lock.lock(); defer { lock.unlock() }
            return denied
        }

        func addUnreadable(deniedFolder: String? = nil) {
            lock.lock()
            unreadable += 1
            if let deniedFolder, denied.count < Self.deniedLimit { denied.append(deniedFolder) }
            lock.unlock()
        }

        func addFile(bytes fileBytes: Int64, path: String) {
            lock.lock()
            files += 1
            bytes += fileBytes
            var snapshot: DiskScanProgress?
            if files - lastReported >= 2000 {
                lastReported = files
                snapshot = DiskScanProgress(filesSeen: files, bytesSeen: bytes, currentPath: path)
            }
            lock.unlock()
            if let snapshot { onProgress?(snapshot) }
        }
    }
}

public struct VolumeSpace: Sendable {
    public let totalBytes: Int64
    public let availableBytes: Int64

    public static func forVolume(containing url: URL) -> VolumeSpace? {
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return VolumeSpace(totalBytes: Int64(total), availableBytes: available)
    }
}

/// A disk the user can scan as a whole: the startup disk plus anything mounted under /Volumes.
public struct MountedVolume: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let totalBytes: Int64
    public let availableBytes: Int64
    public let isStartup: Bool
    public let isInternal: Bool

    public var id: URL { url }
    public var usedBytes: Int64 { max(totalBytes - availableBytes, 0) }

    public static func all() -> [MountedVolume] {
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey, .volumeIsBrowsableKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url -> MountedVolume? in
            let isStartup = url.path == "/"
            guard isStartup || url.path.hasPrefix("/Volumes/"),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable != false,
                  let total = values.volumeTotalCapacity, total > 0 else { return nil }
            let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
            return MountedVolume(
                url: url,
                name: values.volumeLocalizedName ?? url.lastPathComponent,
                totalBytes: Int64(total),
                availableBytes: available,
                isStartup: isStartup,
                isInternal: values.volumeIsInternal ?? isStartup
            )
        }
        .sorted { ($0.isStartup ? 0 : 1, $0.name) < ($1.isStartup ? 0 : 1, $1.name) }
    }
}

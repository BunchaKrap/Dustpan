import CryptoKit
import Foundation

public struct DuplicateFile: Identifiable, Hashable, Sendable {
    public let url: URL
    public let sizeBytes: Int64
    public let modified: Date?

    public var id: URL { url }
    public var target: DeletionTarget { DeletionTarget(url: url, sizeBytes: sizeBytes) }
}

/// Files with identical contents. `files` is ordered oldest first, so the first is most likely the original.
public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public var files: [DuplicateFile]

    public var sizeBytes: Int64 { files.first?.sizeBytes ?? 0 }
    /// Space freed by keeping just one copy.
    public var wastedBytes: Int64 { sizeBytes * Int64(max(files.count - 1, 0)) }
    public var name: String { files.first?.url.lastPathComponent ?? "" }
}

public struct DuplicateReport: Sendable {
    public let groups: [DuplicateGroup]
    public let filesScanned: Int
    public let unreadable: Int
    public let duration: TimeInterval

    public var wastedBytes: Int64 { groups.reduce(0) { $0 + $1.wastedBytes } }
}

public struct DuplicateScanProgress: Sendable {
    public enum Phase: Sendable { case searching, comparing }
    public let phase: Phase
    public let filesSeen: Int
    public let compared: Int
    public let toCompare: Int
    public let currentPath: String
}

/// Finds identical files: a parallel walk groups files by size, then a cheap head/tail hash
/// splits the groups, and only files that still match get a full SHA-256. Read-only.
public struct DuplicateFinder: Sendable {
    public var minimumBytes: Int64
    /// Never searched: app data that shouldn't be deduplicated by hand.
    public var skippedPaths: Set<String>

    public init(minimumBytes: Int64 = 1_000_000,
                skippedPaths: Set<String> = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path]) {
        self.minimumBytes = minimumBytes
        self.skippedPaths = skippedPaths
    }

    private static let keys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
        .totalFileAllocatedSizeKey, .contentModificationDateKey, .fileIdentifierKey,
    ]

    private struct Candidate: Sendable {
        let url: URL
        let logicalSize: Int64
        let file: DuplicateFile
        let fileID: UInt64?
    }

    public func scan(_ root: URL, onProgress: (@Sendable (DuplicateScanProgress) -> Void)? = nil) async -> DuplicateReport {
        let started = Date()
        let tally = Tally(onProgress: onProgress)

        // 1. Walk: top-level folders in parallel, like the disk scanner.
        var candidates: [Candidate] = []
        var subfolders: [URL] = []
        let topLevel = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: Self.keys,
                                                                       options: [.skipsHiddenFiles])) ?? []
        for url in topLevel {
            guard let values = try? url.resourceValues(forKeys: Set(Self.keys)) else { tally.addUnreadable(); continue }
            if values.isDirectory == true, values.isSymbolicLink != true {
                if !skippedPaths.contains(url.path) && !Self.isPackage(url) { subfolders.append(url) }
            } else if let candidate = candidate(url, values: values, tally: tally) {
                candidates.append(candidate)
            }
        }
        candidates += await withTaskGroup(of: [Candidate].self) { group in
            for folder in subfolders {
                group.addTask { walk(folder, tally: tally) }
            }
            var all: [Candidate] = []
            for await found in group { all += found }
            return all
        }
        guard !Task.isCancelled else { return DuplicateReport(groups: [], filesScanned: 0, unreadable: 0, duration: 0) }

        // Hard links are one file on disk, so keep a single path per file ID.
        var seenIDs = Set<UInt64>()
        candidates = candidates.filter { candidate in
            guard let id = candidate.fileID else { return true }
            return seenIDs.insert(id).inserted
        }

        // 2. Same size is required for same contents.
        let sameSize = Dictionary(grouping: candidates, by: \.logicalSize).values.filter { $0.count > 1 }
        tally.startComparing(total: sameSize.reduce(0) { $0 + $1.count })

        // 3. Head + tail hash, then 4. full hash on the survivors.
        let quickGroups = await split(Array(sameSize), tally: tally, countsProgress: true) { Self.quickHash($0.url) }
        let fullGroups = await split(quickGroups, tally: tally, countsProgress: false) { candidate in
            candidate.logicalSize <= Self.sampleBytes * 2 ? "small" : Self.fullHash(candidate.url)
        }

        let groups = fullGroups.map { members -> DuplicateGroup in
            let files = members.map(\.file).sorted { ($0.modified ?? .distantPast, $0.url.path) < ($1.modified ?? .distantPast, $1.url.path) }
            return DuplicateGroup(id: files.map(\.url.path).joined(separator: "|"), files: files)
        }
        .sorted { $0.wastedBytes > $1.wastedBytes }

        return DuplicateReport(groups: groups, filesScanned: tally.filesCount, unreadable: tally.unreadableCount,
                               duration: Date().timeIntervalSince(started))
    }

    // MARK: Walking

    private func walk(_ folder: URL, tally: Tally) -> [Candidate] {
        var found: [Candidate] = []
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: Self.keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in tally.addUnreadable(); return true }
        ) else { return found }

        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? url.resourceValues(forKeys: Set(Self.keys)) else { tally.addUnreadable(); continue }
            if values.isDirectory == true {
                if skippedPaths.contains(url.path) || Self.isPackage(url) { enumerator.skipDescendants() }
                continue
            }
            if let candidate = candidate(url, values: values, tally: tally) { found.append(candidate) }
        }
        return found
    }

    private func candidate(_ url: URL, values: URLResourceValues, tally: Tally) -> Candidate? {
        guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        tally.addFile(path: url.path)
        let logical = Int64(values.fileSize ?? 0)
        guard logical >= minimumBytes else { return nil }
        let file = DuplicateFile(url: url, sizeBytes: Int64(values.totalFileAllocatedSize ?? Int(logical)),
                                 modified: values.contentModificationDate)
        return Candidate(url: url, logicalSize: logical, file: file, fileID: values.fileIdentifier)
    }

    /// Bundles like Photos libraries look like folders but must be managed by their app.
    private static func isPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
    }

    // MARK: Hashing

    /// Splits each group by a key computed in parallel; groups left with one member are dropped.
    private func split(_ groups: [[Candidate]], tally: Tally, countsProgress: Bool,
                       key: @escaping @Sendable (Candidate) -> String?) async -> [[Candidate]] {
        let jobs = groups.enumerated().flatMap { index, members in members.map { (index, $0) } }
        let width = max(ProcessInfo.processInfo.activeProcessorCount, 2)
        var keyed: [(group: Int, key: String, candidate: Candidate)] = []

        await withTaskGroup(of: (Int, String?, Candidate).self) { group in
            var next = 0
            func enqueue() {
                guard next < jobs.count else { return }
                let (index, candidate) = jobs[next]
                next += 1
                group.addTask { Task.isCancelled ? (index, nil, candidate) : (index, key(candidate), candidate) }
            }
            for _ in 0..<width { enqueue() }
            for await (index, value, candidate) in group {
                if countsProgress { tally.addCompared(path: candidate.url.path) }
                if let value { keyed.append((index, value, candidate)) } else { tally.addUnreadable() }
                enqueue()
            }
        }

        return Dictionary(grouping: keyed) { "\($0.group)/\($0.key)" }
            .values
            .map { $0.map(\.candidate) }
            .filter { $0.count > 1 }
    }

    static let sampleBytes: Int64 = 64 * 1024

    static func quickHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        // read(upToCount:) returns nil at end of file, so only a thrown error means unreadable.
        guard let head = try? handle.read(upToCount: Int(sampleBytes)) ?? Data() else { return nil }
        hasher.update(data: head)
        // Small files are read whole here, so this hash is already exact for them.
        guard let end = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: end > UInt64(sampleBytes) * 2 ? end - UInt64(sampleBytes) : UInt64(head.count))
        guard let tail = try? handle.read(upToCount: Int(sampleBytes)) ?? Data() else { return nil }
        hasher.update(data: tail)
        return hex(hasher.finalize())
    }

    static func fullHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if Task.isCancelled { return nil }
            guard let chunk = try? handle.read(upToCount: 4 << 20) ?? Data() else { return nil }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Progress

    private final class Tally: @unchecked Sendable {
        private let lock = NSLock()
        private let onProgress: (@Sendable (DuplicateScanProgress) -> Void)?
        private var files = 0
        private var unreadable = 0
        private var compared = 0
        private var toCompare = 0
        private var phase = DuplicateScanProgress.Phase.searching
        private var lastReported = Date.distantPast

        init(onProgress: (@Sendable (DuplicateScanProgress) -> Void)?) {
            self.onProgress = onProgress
        }

        var filesCount: Int { lock.withLock { files } }
        var unreadableCount: Int { lock.withLock { unreadable } }

        func addUnreadable() { lock.withLock { unreadable += 1 } }

        func addFile(path: String) {
            report(path) { files += 1 }
        }

        func startComparing(total: Int) {
            report("", force: true) {
                phase = .comparing
                toCompare = total
            }
        }

        func addCompared(path: String) {
            report(path) { compared += 1 }
        }

        /// Applies a change and reports at most ~20 times a second.
        private func report(_ path: String, force: Bool = false, _ change: () -> Void) {
            lock.lock()
            change()
            var snapshot: DuplicateScanProgress?
            let now = Date()
            if force || now.timeIntervalSince(lastReported) > 0.05 {
                lastReported = now
                snapshot = DuplicateScanProgress(phase: phase, filesSeen: files, compared: compared, toCompare: toCompare, currentPath: path)
            }
            lock.unlock()
            if let snapshot { onProgress?(snapshot) }
        }
    }
}

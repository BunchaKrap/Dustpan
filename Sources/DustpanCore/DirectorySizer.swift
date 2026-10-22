import Foundation

/// Measures on-disk (allocated) size of files and directories.
public struct DirectorySizer: Sendable {
    public init() {}

    private static let keys: [URLResourceKey] = [
        .isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// Symlinks are never followed. Unreadable descendants are skipped and counted in `unreadable`.
    public func measure(_ url: URL) -> (bytes: Int64, unreadable: Int) {
        let keySet = Set(Self.keys)
        guard let values = try? url.resourceValues(forKeys: keySet) else { return (0, 1) }
        if values.isSymbolicLink == true { return (0, 0) }
        if values.isRegularFile == true { return (Self.allocatedBytes(values), 0) }

        final class Counter: @unchecked Sendable { var value = 0 }
        let failures = Counter()
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Self.keys,
            options: [],
            errorHandler: { _, _ in failures.value += 1; return true }
        ) else { return (0, 1) }

        var total: Int64 = 0
        var visited = 0
        for case let child as URL in enumerator {
            visited += 1
            if visited % 2000 == 0, Task.isCancelled { break }
            guard let v = try? child.resourceValues(forKeys: keySet), v.isRegularFile == true else { continue }
            total += Self.allocatedBytes(v)
        }
        return (total, failures.value)
    }

    private static func allocatedBytes(_ v: URLResourceValues) -> Int64 {
        Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
    }
}

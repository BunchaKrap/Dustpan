import Foundation

/// Append-only, tab-separated record of every removal attempt:
/// `timestamp  ACTION  bytes  path  detail  [source]`
public struct DeletionLog: Sendable {
    public enum Action: String, Sendable {
        case trashed = "TRASHED"
        case failed = "FAILED"
        case refused = "REFUSED"
        /// Put back from the Trash by the History screen.
        case restored = "RESTORED"
    }

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var `default`: DeletionLog {
        DeletionLog(fileURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Dustpan/deletions.log"))
    }

    /// Ensures the log exists and is writable.
    public func prepare() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fileURL.path) {
            try Data("# timestamp\taction\tbytes\tpath\tdetail\n".utf8).write(to: fileURL)
        }
        guard fm.isWritableFile(atPath: fileURL.path) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: fileURL.path])
        }
    }

    /// `source` names the screen that removed the item (Cleanup, Disk Space…), shown in History.
    public func record(_ action: Action, target: DeletionTarget, detail: String? = nil, source: String? = nil) {
        var fields = [
            ISO8601DateFormatter().string(from: Date()),
            action.rawValue,
            String(target.sizeBytes),
            target.url.path,
            detail ?? "",
        ]
        if let source { fields.append(source) }
        let line = fields.joined(separator: "\t") + "\n"
        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            FileHandle.standardError.write(Data("Dustpan: could not write deletion log: \(error)\n\(line)".utf8))
        }
    }
}

import Foundation

/// One parsed line of the deletion log.
public struct DeletionRecord: Identifiable, Hashable, Sendable {
    public let id: Int
    public let date: Date
    public let action: DeletionLog.Action
    public let sizeBytes: Int64
    public let path: String
    public let detail: String
    public let source: String?

    /// Where the item went in the Trash, for TRASHED lines.
    public var trashPath: String? {
        guard action == .trashed, detail.hasPrefix("-> ") else { return nil }
        return String(detail.dropFirst(3))
    }

    public var name: String { (path as NSString).lastPathComponent }
}

/// Removals that happened together (one confirmation), newest first in `DeletionHistory.sessions`.
public struct DeletionSession: Identifiable, Hashable, Sendable {
    public let records: [DeletionRecord]

    public var id: Int { records.first?.id ?? 0 }
    public var date: Date { records.first?.date ?? .distantPast }
    public var trashed: [DeletionRecord] { records.filter { $0.action == .trashed } }
    public var problems: [DeletionRecord] { records.filter { $0.action == .failed || $0.action == .refused } }
    public var bytesMoved: Int64 { trashed.reduce(0) { $0 + $1.sizeBytes } }
    public var source: String? { records.lazy.compactMap(\.source).first }
}

public enum DeletionHistory {
    /// Lines further apart than this start a new session.
    static let sessionGap: TimeInterval = 90

    public static func load(_ log: DeletionLog = .default) -> [DeletionRecord] {
        guard let text = try? String(contentsOf: log.fileURL) else { return [] }
        return parse(text)
    }

    public static func parse(_ text: String) -> [DeletionRecord] {
        let formatter = ISO8601DateFormatter()
        var records: [DeletionRecord] = []
        for (index, line) in text.split(separator: "\n").enumerated() where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4,
                  let date = formatter.date(from: fields[0]),
                  let action = DeletionLog.Action(rawValue: fields[1]) else { continue }
            records.append(DeletionRecord(
                id: index,
                date: date,
                action: action,
                sizeBytes: Int64(fields[2]) ?? 0,
                path: fields[3],
                detail: fields.count > 4 ? fields[4] : "",
                source: fields.count > 5 && !fields[5].isEmpty ? fields[5] : nil
            ))
        }
        return records
    }

    /// Groups removal attempts into sessions, newest first. Restore lines are left out.
    public static func sessions(_ records: [DeletionRecord]) -> [DeletionSession] {
        var sessions: [[DeletionRecord]] = []
        for record in records where record.action != .restored {
            if let last = sessions.last?.last,
               record.date.timeIntervalSince(last.date) < sessionGap,
               record.source == last.source {
                sessions[sessions.count - 1].append(record)
            } else {
                sessions.append([record])
            }
        }
        return sessions.reversed().map { DeletionSession(records: $0) }
    }

    /// Original paths that were later put back.
    public static func restoredPaths(_ records: [DeletionRecord]) -> Set<String> {
        Set(records.filter { $0.action == .restored }.map(\.path))
    }

    public enum RestoreError: Error, CustomStringConvertible {
        case notInTrash
        case originalExists

        public var description: String {
            switch self {
            case .notInTrash: "It's no longer in the Trash."
            case .originalExists: "Something already exists at the original location."
            }
        }
    }

    /// Moves a trashed item back to where it was and records that in the log.
    public static func restore(_ record: DeletionRecord, log: DeletionLog = .default) throws {
        let fm = FileManager.default
        // Only ever move things out of a Trash folder.
        guard let trashPath = record.trashPath, trashPath.contains("/.Trash/") || trashPath.contains("/.Trashes/"),
              fm.fileExists(atPath: trashPath) else { throw RestoreError.notInTrash }
        guard !fm.fileExists(atPath: record.path) else { throw RestoreError.originalExists }
        let original = URL(fileURLWithPath: record.path)
        try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: URL(fileURLWithPath: trashPath), to: original)
        try? log.prepare()
        log.record(.restored, target: DeletionTarget(url: original, sizeBytes: record.sizeBytes), detail: "<- \(trashPath)", source: "History")
    }

    public static func isInTrash(_ record: DeletionRecord) -> Bool {
        record.trashPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
    }
}

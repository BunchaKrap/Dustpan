import AppKit
import DustpanCore
import SwiftUI

@MainActor
@Observable
final class HistoryModel {
    enum ItemState {
        case inTrash, emptied, restored, failed, refused
    }

    private(set) var sessions: [DeletionSession] = []
    private(set) var isLoading = false
    private(set) var states: [Int: ItemState] = [:]
    var expanded: Set<Int> = []
    var sourceFilter: String?
    var message: (text: String, isError: Bool)?

    var sources: [String] { Array(Set(sessions.compactMap(\.source))).sorted() }
    var filteredSessions: [DeletionSession] {
        guard let sourceFilter else { return sessions }
        return sessions.filter { $0.source == sourceFilter }
    }

    var totalBytes: Int64 { sessions.reduce(0) { $0 + $1.bytesMoved } }
    var totalItems: Int { sessions.reduce(0) { $0 + $1.trashed.count } }
    var bytesThisMonth: Int64 {
        let start = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? .distantPast
        return sessions.filter { $0.date >= start }.reduce(0) { $0 + $1.bytesMoved }
    }
    var restorableCount: Int { states.values.filter { $0 == .inTrash }.count }

    func load() {
        isLoading = true
        Task {
            let (sessions, states) = await Task.detached { () -> ([DeletionSession], [Int: ItemState]) in
                let records = DeletionHistory.load()
                let restored = DeletionHistory.restoredPaths(records)
                let sessions = DeletionHistory.sessions(records)
                var states: [Int: ItemState] = [:]
                for record in sessions.flatMap(\.records) {
                    states[record.id] = switch record.action {
                    case .failed: .failed
                    case .refused: .refused
                    case .restored: .restored
                    case .trashed:
                        DeletionHistory.isInTrash(record) ? .inTrash
                            : (restored.contains(record.path) && FileManager.default.fileExists(atPath: record.path) ? .restored : .emptied)
                    }
                }
                return (sessions, states)
            }.value
            self.sessions = sessions
            self.states = states
            if expanded.isEmpty, let newest = sessions.first { expanded = [newest.id] }
            isLoading = false
        }
    }

    func toggle(_ session: DeletionSession) {
        if expanded.contains(session.id) { expanded.remove(session.id) } else { expanded.insert(session.id) }
    }

    func putBack(_ record: DeletionRecord) {
        do {
            try DeletionHistory.restore(record)
            states[record.id] = .restored
            message = ("Put \(record.name) back in \(ScanPlaces.display((record.path as NSString).deletingLastPathComponent)).", false)
        } catch {
            message = ("Couldn't put back \(record.name): \(error)", true)
        }
    }

    func putBackAll(in session: DeletionSession) {
        var restored = 0
        var failed = 0
        for record in session.trashed where states[record.id] == .inTrash {
            do {
                try DeletionHistory.restore(record)
                states[record.id] = .restored
                restored += 1
            } catch {
                failed += 1
            }
        }
        message = failed == 0
            ? ("Put back \(restored) \(restored == 1 ? "item" : "items").", false)
            : ("Put back \(restored) items; \(failed) couldn't be restored.", true)
    }

    func reveal(_ record: DeletionRecord) {
        let path = states[record.id] == .inTrash ? record.trashPath ?? record.path : record.path
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openTrash() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
    }

    func logLines(limit: Int = 500) -> [String] {
        guard let text = try? String(contentsOf: DeletionLog.default.fileURL) else { return [] }
        return text.split(separator: "\n")
            .filter { !$0.hasPrefix("#") }
            .suffix(limit)
            .reversed()
            .map { $0.replacingOccurrences(of: "\t", with: "  ") }
    }

    func revealLog() {
        let log = DeletionLog.default
        try? log.prepare()
        NSWorkspace.shared.activateFileViewerSelecting([log.fileURL])
    }
}

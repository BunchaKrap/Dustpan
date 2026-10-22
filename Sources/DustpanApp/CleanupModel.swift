import AppKit
import DustpanCore
import DustpanDesign
import SwiftUI

struct DeletionProgress: Equatable {
    var completed: Int
    var total: Int
}

@MainActor
@Observable
final class CleanupModel {
    private(set) var report: JunkScanReport?
    private(set) var isScanning = false
    private(set) var scanStatus = ""
    private(set) var scanFraction = 0.0
    /// Persisted between launches.
    var options: ScanOptions = CleanupModel.loadOptions() {
        didSet { Self.saveOptions(options) }
    }
    private(set) var deletionProgress: DeletionProgress?
    var lastOutcome: DeletionOutcome?
    /// URLs of selected items. Starts empty after every scan; nothing is preselected.
    var selection: Set<URL> = []
    var expanded: Set<JunkCategory> = []

    private var scanTask: Task<Void, Never>?

    var isBusy: Bool { isScanning || deletionProgress != nil }

    var selectedItems: [JunkItem] {
        (report?.allItems ?? []).filter { $0.isDeletable && selection.contains($0.url) }
    }

    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }

    // MARK: Scanning

    func scan() {
        scanTask?.cancel()
        isScanning = true
        selection = []
        lastOutcome = nil
        scanStatus = "Starting \(options.depth.displayName.lowercased()) scan…"
        scanFraction = 0
        let scanner = JunkScanner(options: options)
        scanTask = Task {
            let result = await scanner.scan { progress in
                Task { @MainActor [weak self] in
                    guard let self, self.isScanning else { return }
                    if let message = progress.message {
                        self.scanStatus = message.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                    }
                    if let completed = progress.completed, progress.total > 0 {
                        self.scanFraction = max(self.scanFraction, Double(completed) / Double(progress.total))
                    }
                }
            }
            guard !Task.isCancelled else { return }
            report = result
            isScanning = false
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    // MARK: Options

    private static let optionsKey = "scanOptions"

    private static func loadOptions() -> ScanOptions {
        guard let data = UserDefaults.standard.data(forKey: optionsKey),
              let options = try? JSONDecoder().decode(ScanOptions.self, from: data) else { return ScanOptions() }
        return options
    }

    private static func saveOptions(_ options: ScanOptions) {
        if let data = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(data, forKey: optionsKey)
        }
    }

    // MARK: Selection

    func isSelected(_ item: JunkItem) -> Bool { selection.contains(item.url) }

    func toggle(_ item: JunkItem) {
        guard item.isDeletable else { return }
        if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
    }

    func checkState(for category: CategoryResult) -> CheckState {
        let deletable = category.items.filter(\.isDeletable)
        let selectedCount = deletable.filter { selection.contains($0.url) }.count
        if selectedCount == 0 { return .off }
        return selectedCount == deletable.count ? .on : .mixed
    }

    func toggle(_ category: CategoryResult) {
        let urls = category.items.filter(\.isDeletable).map(\.url)
        if checkState(for: category) == .on { selection.subtract(urls) } else { selection.formUnion(urls) }
    }

    func selectAllDeletable() {
        selection = Set((report?.allItems ?? []).filter(\.isDeletable).map(\.url))
    }

    func expansion(for category: JunkCategory) -> Binding<Bool> {
        Binding(
            get: { self.expanded.contains(category) },
            set: { isOpen in
                if isOpen { self.expanded.insert(category) } else { self.expanded.remove(category) }
            }
        )
    }

    // MARK: Deletion (called only from the confirmation sheet)

    func trashSelected() async {
        let targets = selectedItems.map(\.target)
        guard !targets.isEmpty, !isBusy else { return }

        deletionProgress = DeletionProgress(completed: 0, total: targets.count)
        let outcome = await Deleter(source: "Cleanup").delete(targets) { completed, total in
            Task { @MainActor [weak self] in
                guard let self, let current = self.deletionProgress else { return }
                self.deletionProgress = DeletionProgress(completed: max(current.completed, completed), total: total)
            }
        }

        let removed = Set(outcome.removed.map(\.url))
        report = report?.removing(removed)
        selection.subtract(removed)
        lastOutcome = outcome
        deletionProgress = nil
    }

    // MARK: Finder

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealDeletionLog() {
        let log = DeletionLog.default
        try? log.prepare()
        reveal(log.fileURL)
    }

    /// Newest entries first, without the header line.
    func deletionLogLines(limit: Int = 500) -> [String] {
        guard let text = try? String(contentsOf: DeletionLog.default.fileURL) else { return [] }
        return text.split(separator: "\n")
            .filter { !$0.hasPrefix("#") }
            .suffix(limit)
            .reversed()
            .map { $0.replacingOccurrences(of: "\t", with: "  ") }
    }
}

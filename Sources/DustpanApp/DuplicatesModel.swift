import AppKit
import DustpanCore
import SwiftUI

@MainActor
@Observable
final class DuplicatesModel {
    private(set) var report: DuplicateReport?
    private(set) var groups: [DuplicateGroup] = []
    private(set) var rootURL: URL?
    private(set) var isScanning = false
    private(set) var progress: DuplicateScanProgress?
    private(set) var deletionProgress: DeletionProgress?
    var lastOutcome: DeletionOutcome?
    var checked: Set<URL> = []
    var expanded: Set<String> = []
    /// Files smaller than this are ignored.
    var minimumBytes: Int64 = 1_000_000

    private var scanTask: Task<Void, Never>?

    var isBusy: Bool { isScanning || deletionProgress != nil }
    var checkedFiles: [DuplicateFile] { groups.flatMap(\.files).filter { checked.contains($0.url) } }
    var checkedBytes: Int64 { checkedFiles.reduce(0) { $0 + $1.sizeBytes } }
    var wastedBytes: Int64 { groups.reduce(0) { $0 + $1.wastedBytes } }
    /// Groups where every copy is ticked: trashing them would lose the file entirely.
    var fullyCheckedGroups: [DuplicateGroup] { groups.filter { $0.files.allSatisfy { checked.contains($0.url) } } }

    // MARK: Scanning

    func scan(_ url: URL? = nil) {
        guard let target = url ?? rootURL else { return }
        scanTask?.cancel()
        rootURL = target
        report = nil
        groups = []
        checked = []
        expanded = []
        lastOutcome = nil
        progress = nil
        isScanning = true

        let finder = DuplicateFinder(minimumBytes: minimumBytes)
        scanTask = Task {
            let result = await finder.scan(target) { progress in
                Task { @MainActor [weak self] in
                    guard let self, self.isScanning else { return }
                    self.progress = progress
                }
            }
            guard !Task.isCancelled else { return }
            report = result
            groups = result.groups
            expanded = Set(result.groups.prefix(3).map(\.id))
            isScanning = false
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func chooseFolder() {
        if let url = ScanPlaces.chooseFolder(startingAt: rootURL, message: "Choose a folder to search for duplicates", prompt: "Search") {
            scan(url)
        }
    }

    func startOver() {
        cancelScan()
        report = nil
        groups = []
        checked = []
        rootURL = nil
    }

    // MARK: Selection

    func toggle(_ file: DuplicateFile) {
        if checked.contains(file.url) { checked.remove(file.url) } else { checked.insert(file.url) }
    }

    func toggleExpanded(_ group: DuplicateGroup) {
        if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) }
    }

    /// Ticks every copy except one per group. Keeps the oldest (likely the original) or the newest.
    func selectExtraCopies(keepingOldest: Bool) {
        checked = Set(groups.flatMap { group -> [URL] in
            let keep = keepingOldest ? group.files.first : group.files.last
            return group.files.filter { $0 != keep }.map(\.url)
        })
    }

    func deselectAll() {
        checked = []
    }

    // MARK: Actions

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func canTrash(_ file: DuplicateFile) -> Bool {
        (try? SafetyPolicy.userHome().validate(file.url).get()) != nil
    }

    /// Called only from the confirmation sheet.
    func trashChecked() async {
        let targets = checkedFiles.map(\.target)
        guard !targets.isEmpty, fullyCheckedGroups.isEmpty, !isBusy else { return }
        let outcome = await performDeletion(targets, policy: .userHome(), source: "Duplicates") { self.deletionProgress = $0 }
        let removed = Set(outcome.removed.map(\.url))
        groups = groups.compactMap { group in
            var group = group
            group.files.removeAll { removed.contains($0.url) }
            return group.files.count > 1 ? group : nil
        }
        checked.subtract(removed)
        lastOutcome = outcome
    }
}

import AppKit
import DustpanCore
import SwiftUI

enum DiskViewMode: String, CaseIterable {
    case list, map, largest
}

@MainActor
@Observable
final class DiskSpaceModel {
    private(set) var root: DiskNode?
    /// The folder being browsed.
    private(set) var current: DiskNode?
    private(set) var rootURL = FileManager.default.homeDirectoryForCurrentUser
    private(set) var isScanning = false
    private(set) var filesSeen = 0
    private(set) var bytesSeen: Int64 = 0
    private(set) var currentPath = ""
    private(set) var unreadable = 0
    private(set) var duration: TimeInterval = 0
    private(set) var volume = VolumeSpace.forVolume(containing: FileManager.default.homeDirectoryForCurrentUser)
    private(set) var deletionProgress: DeletionProgress?
    var lastOutcome: DeletionOutcome?
    /// Bumped whenever the (non-observable) tree changes so views refresh.
    private(set) var revision = 0

    /// The start screen with drives and folder presets. Results are kept while it shows.
    private(set) var isShowingLauncher = true
    private(set) var volumes: [MountedVolume] = []
    private(set) var recents: [URL] = []
    var viewMode = DiskViewMode.list
    var kindFilter: FileKind?

    /// Folders visited before the current one, for Back.
    private var backStack: [DiskNode] = []
    private var largestCache: (key: String, files: [DiskNode])?
    private var scanTask: Task<Void, Never>?
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private static let recentsKey = "diskSpaceRecents"

    var isBusy: Bool { isScanning || deletionProgress != nil }
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoUp: Bool { current?.parent != nil }

    init() {
        recents = (UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        refreshVolumes()
    }

    // MARK: Scanning

    func scan(_ url: URL? = nil) {
        let target = url ?? rootURL
        scanTask?.cancel()
        rootURL = target
        root = nil
        current = nil
        backStack = []
        largestCache = nil
        lastOutcome = nil
        isShowingLauncher = false
        isScanning = true
        filesSeen = 0
        bytesSeen = 0
        currentPath = display(target.path)
        volume = VolumeSpace.forVolume(containing: target)
        remember(target)

        let started = Date()
        scanTask = Task {
            let result = await DiskUsageScanner().scan(target) { progress in
                Task { @MainActor [weak self] in
                    guard let self, self.isScanning else { return }
                    self.filesSeen = progress.filesSeen
                    self.bytesSeen = progress.bytesSeen
                    self.currentPath = self.display(progress.currentPath)
                }
            }
            guard !Task.isCancelled else { return }
            root = result.root
            current = result.root
            unreadable = result.unreadable
            duration = Date().timeIntervalSince(started)
            isScanning = false
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        if root == nil { isShowingLauncher = true }
    }

    func chooseFolder() {
        if let url = ScanPlaces.chooseFolder(startingAt: rootURL, message: "Choose a folder to measure") {
            scan(url)
        }
    }

    func showLauncher() {
        refreshVolumes()
        isShowingLauncher = true
    }

    func hideLauncher() {
        guard root != nil else { return }
        isShowingLauncher = false
    }

    func refreshVolumes() {
        volumes = MountedVolume.all()
    }

    func forgetRecents() {
        recents = []
        UserDefaults.standard.removeObject(forKey: Self.recentsKey)
    }

    private func remember(_ url: URL) {
        recents.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        recents.insert(url, at: 0)
        recents = Array(recents.prefix(6))
        UserDefaults.standard.set(recents.map(\.path), forKey: Self.recentsKey)
    }

    /// A friendly name for a scanned location ("Macintosh HD", "Downloads").
    func title(for url: URL) -> String {
        if let volume = volumes.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) { return volume.name }
        if url.standardizedFileURL == home.standardizedFileURL { return "Home Folder" }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    // MARK: Navigation

    func isOpenable(_ node: DiskNode) -> Bool {
        node.isDirectory && (!node.children.isEmpty || node.hiddenFileCount > 0)
    }

    func open(_ node: DiskNode) {
        guard isOpenable(node), let current, node !== current else { return }
        backStack.append(current)
        self.current = node
    }

    func goUp() {
        guard let parent = current?.parent else { return }
        go(to: parent)
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        current = previous
    }

    func go(to node: DiskNode) {
        guard let current, node !== current else { return }
        backStack.append(current)
        self.current = node
    }

    /// Largest files below the current folder, honouring the kind filter. Cached per folder and filter.
    func largestFiles(limit: Int = 50) -> [DiskNode] {
        guard let current else { return [] }
        let key = "\(current.url.path)|\(revision)|\(kindFilter?.rawValue ?? "all")"
        if let cache = largestCache, cache.key == key { return cache.files }
        let kind = kindFilter
        let files = current.largestFiles(limit: limit) { kind == nil || FileKind.of($0.url) == kind }
        largestCache = (key, files)
        return files
    }

    // MARK: Actions

    func reveal(_ node: DiskNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func canTrash(_ node: DiskNode) -> Bool {
        node.parent != nil && (try? SafetyPolicy.userHome().validate(node.url).get()) != nil
    }

    func trash(_ node: DiskNode) async {
        guard canTrash(node), !isBusy else { return }
        let outcome = await performDeletion([DeletionTarget(url: node.url, sizeBytes: node.sizeBytes)],
                                            policy: .userHome(), source: "Disk Space") {
            self.deletionProgress = $0
        }
        if !outcome.removed.isEmpty, let parent = node.parent {
            parent.remove(node)
            backStack.removeAll { $0 === node || $0.ancestry.contains { $0 === node } }
            revision += 1
        }
        volume = VolumeSpace.forVolume(containing: rootURL)
        lastOutcome = outcome
    }

    func display(_ path: String) -> String {
        path.hasPrefix(home.path) ? "~" + path.dropFirst(home.path.count) : path
    }
}

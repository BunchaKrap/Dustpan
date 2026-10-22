import AppKit
import DustpanCore
import DustpanDesign
import SwiftUI

@MainActor
@Observable
final class UninstallerModel {
    private(set) var apps: [InstalledApp] = []
    private(set) var appSizes: [URL: Int64] = [:]
    private(set) var isLoadingApps = false
    var query = ""

    private(set) var selectedApp: InstalledApp?
    private(set) var leftovers: [AppLeftover] = []
    private(set) var isLoadingLeftovers = false
    var checked: Set<URL> = []

    private(set) var deletionProgress: DeletionProgress?
    var lastOutcome: DeletionOutcome?
    /// Bumped to re-check whether the selected app is running.
    private(set) var runningCheck = 0

    private var leftoverTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var icons: [URL: NSImage] = [:]

    var filteredApps: [InstalledApp] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(trimmed) || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(trimmed) }
    }

    var checkedLeftovers: [AppLeftover] { leftovers.filter { checked.contains($0.url) } }
    var checkedBytes: Int64 { checkedLeftovers.reduce(0) { $0 + $1.sizeBytes } }
    var totalBytes: Int64 { leftovers.reduce(0) { $0 + $1.sizeBytes } }

    // MARK: Loading

    func loadAppsIfNeeded() {
        guard apps.isEmpty, !isLoadingApps else { return }
        reloadApps()
    }

    func reloadApps() {
        isLoadingApps = true
        Task {
            let catalog = await Task.detached { AppCatalog.installedApps() }.value
            apps = catalog
            isLoadingApps = false
            if let selected = selectedApp, let refreshed = catalog.first(where: { $0.url == selected.url }) {
                select(refreshed)
            } else {
                select(catalog.first { !$0.isSystemApp })
            }
            measureApps(catalog)
        }
    }

    private func measureApps(_ catalog: [InstalledApp]) {
        sizeTask?.cancel()
        sizeTask = Task {
            let sizer = DirectorySizer()
            for app in catalog {
                if Task.isCancelled { return }
                let bytes = await Task.detached { sizer.measure(app.url).bytes }.value
                appSizes[app.url] = bytes
            }
        }
    }

    func select(_ app: InstalledApp?) {
        guard selectedApp != app || leftovers.isEmpty else { return }
        selectedApp = app
        leftovers = []
        checked = []
        lastOutcome = nil
        leftoverTask?.cancel()
        guard let app else { return }

        isLoadingLeftovers = true
        let others = apps
        leftoverTask = Task {
            let found = await Task.detached { AppLeftoverFinder().leftovers(for: app, otherApps: others) }.value
            guard !Task.isCancelled, selectedApp == app else { return }
            leftovers = found
            // Name-only matches are shown but left for the user to tick.
            checked = app.isSystemApp ? [] : Set(found.filter { !$0.matchedByName }.map(\.url))
            isLoadingLeftovers = false
        }
    }

    // MARK: App state

    func icon(for app: InstalledApp) -> NSImage {
        if let cached = icons[app.url] { return cached }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        icons[app.url] = image
        return image
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        _ = runningCheck
        guard let id = app.bundleIdentifier else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    func quit(_ app: InstalledApp) {
        guard let id = app.bundleIdentifier else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
        Task {
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(400))
                runningCheck += 1
                if !isRunning(app) { return }
            }
        }
    }

    func toggle(_ leftover: AppLeftover) {
        if checked.contains(leftover.url) { checked.remove(leftover.url) } else { checked.insert(leftover.url) }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Uninstall (called only from the confirmation sheet)

    func uninstall() async {
        guard let app = selectedApp, !app.isSystemApp, !isRunning(app) else { return }
        let targets = checkedLeftovers.map(\.target)
        guard !targets.isEmpty else { return }

        let outcome = await performDeletion(targets, policy: .uninstaller(), source: "Uninstaller") { self.deletionProgress = $0 }
        let removed = Set(outcome.removed.map(\.url))

        if removed.contains(app.url) {
            let index = apps.firstIndex(of: app) ?? 0
            apps.removeAll { $0 == app }
            appSizes[app.url] = nil
            selectedApp = nil
            select(apps.indices.contains(index) ? apps[index] : apps.last)
        } else {
            leftovers.removeAll { removed.contains($0.url) }
            checked.subtract(removed)
        }
        lastOutcome = outcome
    }
}

import AppKit
import DustpanCore
import SwiftUI

enum ActivityFilter: String, CaseIterable {
    case all = "All", apps = "Apps", background = "Background", flagged = "Needs a Look"
}

enum ActivitySort {
    case cpu, memory, name
}

/// A process plus everything the Activity screen says about it.
struct ActivityRow: Identifiable {
    let process: RunningProcess
    let name: String
    /// "Part of Slack", "macOS", "Homebrew" or the owner.
    let subtitle: String
    let isApp: Bool
    let cpuPercent: Double?
    let launchItem: LaunchItem?
    /// Nil until the signature check for this process has run.
    let assessment: ProcessAssessment?
    let signer: CodeSigner?

    var id: Int32 { process.pid }
    var level: TrustLevel? { assessment?.level }
}

/// Live list of running processes. Samples every 3 s while the Activity screen is visible, and never changes
/// anything unless the person chooses Quit or Force Quit.
@MainActor
@Observable
final class ActivityModel {
    private(set) var rows: [ActivityRow] = []
    private(set) var isLoaded = false
    var query = ""
    var filter = ActivityFilter.all
    var sort = ActivitySort.cpu
    var selectedPID: Int32?
    /// Shown above the details after Quit / Force Quit.
    private(set) var message: (text: String, isError: Bool)?
    var pendingStop: ActivityRow?

    private var snapshot: [RunningProcess] = []
    private var launchItems = LaunchItemIndex([])
    private var lastSample: (cpu: [Int32: UInt64], at: Date)?
    private var cpuPercent: [Int32: Double] = [:]
    /// Keyed by pid and program so a reused pid gets checked again.
    private var signers: [String: CodeSigner] = [:]
    private var checking: Set<String> = []
    private var icons: [String: NSImage] = [:]
    private var refreshTask: Task<Void, Never>?
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    var selected: ActivityRow? { rows.first { $0.id == selectedPID } }
    /// Counted once per sample; the sidebar pill and the filter read it on every redraw.
    private(set) var flaggedCount = 0
    var totalCPU: Double { rows.compactMap(\.cpuPercent).reduce(0, +) }
    var totalMemory: Int64 { rows.compactMap(\.process.memoryBytes).reduce(0, +) }

    var visibleRows: [ActivityRow] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = rows.filter { row in
            switch filter {
            case .all: true
            case .apps: row.isApp
            case .background: !row.isApp
            case .flagged: (row.level ?? .trusted) >= .caution
            }
        }
        .filter { needle.isEmpty || $0.name.lowercased().contains(needle) || $0.subtitle.lowercased().contains(needle)
            || String($0.process.pid) == needle || ($0.process.path?.lowercased().contains(needle) ?? false) }

        switch sort {
        case .cpu: return filtered.sorted { ($0.cpuPercent ?? -1, $1.name) > ($1.cpuPercent ?? -1, $0.name) }
        case .memory: return filtered.sorted { ($0.process.memoryBytes ?? -1, $1.name) > ($1.process.memoryBytes ?? -1, $0.name) }
        case .name: return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    // MARK: Sampling

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        let (processes, items) = await Task.detached(priority: .utility) {
            (ProcessList.snapshot(), LaunchItemIndex(LaunchItems.all()))
        }.value
        let now = Date()
        let cpu = Dictionary(processes.compactMap { p in p.cpuNanoseconds.map { (p.pid, $0) } }, uniquingKeysWith: { a, _ in a })
        if let last = lastSample {
            let elapsed = now.timeIntervalSince(last.at) * 1e9
            cpuPercent = cpu.reduce(into: [:]) { result, entry in
                guard let before = last.cpu[entry.key], entry.value >= before, elapsed > 0 else { return }
                result[entry.key] = Double(entry.value - before) / elapsed * 100
            }
        }
        lastSample = (cpu, now)
        snapshot = processes
        launchItems = items
        rebuildRows()
        isLoaded = true
        checkSignatures()
    }

    /// Signature checks take a few milliseconds each, so they run once per process, off the main thread.
    private func checkSignatures() {
        let pending = snapshot.filter { signers[key(for: $0)] == nil && !checking.contains(key(for: $0)) }
        guard !pending.isEmpty else { return }
        let keys = pending.map(key(for:))
        checking.formUnion(keys)
        Task {
            let results = await Task.detached(priority: .utility) {
                pending.map { CodeTrust.signer(pid: $0.pid, path: $0.path) }
            }.value
            for (key, signer) in zip(keys, results) { signers[key] = signer }
            checking.subtract(keys)
            rebuildRows()
        }
    }

    private func key(for process: RunningProcess) -> String {
        "\(process.pid)|\(process.path ?? process.shortName)"
    }

    private func rebuildRows() {
        let apps = Dictionary(NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        rows = snapshot.map { process in
            let app = apps[process.pid]
            let isApp = app?.activationPolicy == .regular
            let launchItem = launchItems.item(for: process)
            let signer = signers[key(for: process)]
            return ActivityRow(
                process: process,
                name: (isApp ? app?.localizedName : nil) ?? process.displayName,
                subtitle: isApp ? "App" : subtitle(for: process, signer: signer),
                isApp: isApp,
                cpuPercent: cpuPercent[process.pid],
                launchItem: launchItem,
                assessment: signer.map { ProcessAssessment.assess(process, signer: $0, launchItem: launchItem, home: home) },
                signer: signer
            )
        }
        flaggedCount = rows.filter { ($0.level ?? .trusted) >= .caution }.count
        if let selectedPID, !rows.contains(where: { $0.id == selectedPID }) { self.selectedPID = nil }
    }

    private func subtitle(for process: RunningProcess, signer: CodeSigner?) -> String {
        if let app = process.appBundlePath {
            let appName = (app as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            if appName.lowercased() != process.displayName.lowercased() { return "Part of \(appName)" }
        }
        let path = process.path ?? ""
        if signer == .apple || path.hasPrefix("/System/") || path.hasPrefix("/usr/") || path.hasPrefix("/sbin/") { return "macOS" }
        if path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/usr/local/Cellar/") { return "Homebrew" }
        return process.uid == getuid() ? "Runs as you" : "Runs as \(process.userName)"
    }

    func icon(for row: ActivityRow) -> NSImage {
        let key = row.process.appBundlePath ?? row.process.path ?? ""
        if let cached = icons[key] { return cached }
        // A running app's own icon is fully loaded; NSWorkspace's file icons can arrive as a blank placeholder.
        let owner = row.process.appBundlePath.flatMap { bundle in
            NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == bundle }
        }
        let image = owner?.icon ?? NSRunningApplication(processIdentifier: row.process.pid)?.icon
            ?? (key.isEmpty ? NSWorkspace.shared.icon(for: .unixExecutable) : NSWorkspace.shared.icon(forFile: key))
        icons[key] = image
        return image
    }

    // MARK: Actions

    func requestStop(_ row: ActivityRow) {
        message = nil
        pendingStop = row
    }

    /// Apps get the same polite request as Quit in the Dock, so they can ask to save; everything else gets SIGTERM.
    func stop(_ row: ActivityRow, force: Bool) {
        pendingStop = nil
        let name = row.name
        if !force, row.isApp, let app = NSRunningApplication(processIdentifier: row.process.pid), ProcessControl.protectionReason(for: row.process) == nil {
            message = app.terminate()
                ? ("Asked \(name) to quit. If it has unsaved work it may ask you first.", false)
                : ("\(name) didn't accept the request to quit. Try Force Quit.", true)
        } else {
            switch ProcessControl.stop(row.process, force: force) {
            case .success:
                var text = force ? "Force quit \(name)." : "Asked \(name) to quit."
                if let item = row.launchItem, item.keepsAlive {
                    text += " macOS will start it again because \(item.plist.lastPathComponent) keeps it running."
                }
                message = (text, false)
            case .failure(let error):
                message = ("Couldn't stop \(name). \(error.description)", true)
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            await refresh()
        }
    }

    func dismissMessage() {
        message = nil
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

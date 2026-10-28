import AppKit
import DustpanCore
import SwiftUI

@MainActor
@Observable
final class UpdateModel {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(ReleaseInfo)
        case downloading(ReleaseInfo)
        case ready(ReleaseInfo, URL)
        case failed(String)
    }

    private(set) var phase = Phase.idle
    var isShowingSheet = false
    /// What's New: releases since the version that ran before, newest first.
    private(set) var whatsNew: [ChangelogEntry] = []
    /// True when shown because Dustpan just updated, rather than from the menu.
    private(set) var isAfterUpdate = false
    /// The version the person updated from, when known.
    private(set) var updatedFrom: String?
    var isShowingWhatsNew = false

    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    private let updater = GitHubUpdater(
        // Set by bundle.sh from DUSTPAN_REPO; empty in builds that don't ship updates.
        repo: Bundle.main.infoDictionary?["DustpanUpdateRepo"] as? String ?? "",
        bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.local.dustpan"
    )
    private var task: Task<Void, Never>?
    private static let lastVersionKey = "lastLaunchedVersion"
    private static let updatedFromKey = "updatedFromVersion"
    private static let updatingToKey = "updatingToVersion"

    init() {
        if !reportFailedUpdate() { showWhatsNewIfUpdated() }
        Task.detached(priority: .background) { GitHubUpdater.removeLeftoverDownloads() }
    }

    var isConfigured: Bool { updater.isConfigured }
    var releasesPage: URL? { updater.releasesPage }
    var hasUpdate: Bool {
        switch phase {
        case .available, .downloading, .ready: true
        default: false
        }
    }

    /// Updates can only be installed in place when running from a writable .app bundle.
    var canInstallInPlace: Bool {
        let app = Bundle.main.bundleURL
        return app.pathExtension == "app" && FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    /// Opens the Updates sheet and checks GitHub. The only place Dustpan goes online.
    func checkNow() {
        isShowingSheet = true
        guard !isBusy else { return }
        guard updater.isConfigured else {
            phase = .failed(UpdateError.notConfigured.description)
            return
        }
        phase = .checking
        task = Task {
            do {
                let release = try await updater.latestRelease()
                phase = GitHubUpdater.isNewer(release.version, than: currentVersion) ? .available(release) : .upToDate(release.version)
            } catch {
                phase = .failed(Self.message(error))
            }
        }
    }

    func download() {
        guard case .available(let release) = phase else { return }
        phase = .downloading(release)
        task = Task {
            do {
                let staged = try await updater.downloadAndStage(release)
                phase = .ready(release, staged)
            } catch {
                phase = .failed(Self.message(error))
            }
        }
    }

    func installAndRelaunch() {
        guard case .ready(let release, let staged) = phase else { return }
        do {
            try GitHubUpdater.installAndRelaunch(staged: staged, replacing: Bundle.main.bundleURL)
            // Read back on relaunch: What's New if the new version is running, an explanation if it isn't.
            UserDefaults.standard.set(currentVersion, forKey: Self.updatedFromKey)
            UserDefaults.standard.set(release.version, forKey: Self.updatingToKey)
            NSApp.terminate(nil)
        } catch {
            phase = .failed("Couldn't start the installer: \(error.localizedDescription)")
        }
    }

    func openReleasePage(_ release: ReleaseInfo? = nil) {
        if let url = release?.pageURL ?? releasesPage { NSWorkspace.shared.open(url) }
    }

    func dismiss() {
        isShowingSheet = false
        if case .downloading = phase { return }
        if case .failed = phase { phase = .idle }
        if case .upToDate = phase { phase = .idle }
    }

    // MARK: What's New

    /// Notes for every release in the app's bundled CHANGELOG.md; empty in `swift run` builds.
    private var changelog: [ChangelogEntry] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Changelog.parse(text)
    }

    /// Dustpan > What's New in Dustpan…: the current release and the ones before it.
    func showWhatsNew() {
        whatsNew = Changelog.entries(changelog, after: "0", through: currentVersion)
        isAfterUpdate = false
        updatedFrom = nil
        isShowingWhatsNew = !whatsNew.isEmpty
    }

    func dismissWhatsNew() {
        isShowingWhatsNew = false
    }

    /// After Install & Relaunch, if this is still the old version the swap failed. Says so, with macOS's reason,
    /// instead of quietly reopening the old app. Returns true when it reported a failure.
    private func reportFailedUpdate() -> Bool {
        let defaults = UserDefaults.standard
        guard let target = defaults.string(forKey: Self.updatingToKey) else { return false }
        defaults.removeObject(forKey: Self.updatingToKey)
        guard GitHubUpdater.isNewer(target, than: currentVersion) else { return false }
        defaults.removeObject(forKey: Self.updatedFromKey)

        let log = (try? String(contentsOf: GitHubUpdater.installLog, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reason = log.isEmpty ? "" : " macOS said: \(log.split(separator: "\n").first ?? "")."
        phase = .failed("The update to \(target) didn't install, so you're still on \(currentVersion). Dustpan couldn't replace itself in \(Bundle.main.bundleURL.deletingLastPathComponent().path).\(reason) Try again, or download it from GitHub and drag it into Applications.")
        isShowingSheet = true
        return true
    }

    /// Runs once per launch, before anything else writes to UserDefaults.
    private func showWhatsNewIfUpdated() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: Self.updatedFromKey) ?? defaults.string(forKey: Self.lastVersionKey)
        // 0.2.1 didn't record its version, so an existing preferences file is the sign it was used before.
        let usedBefore = previous != nil || !(defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]).isEmpty
        defaults.removeObject(forKey: Self.updatedFromKey)
        defaults.set(currentVersion, forKey: Self.lastVersionKey)
        guard usedBefore, previous.map({ GitHubUpdater.isNewer(currentVersion, than: $0) }) ?? true else { return }

        let entries = changelog
        // Without a known previous version, show just this release rather than the whole history.
        whatsNew = previous.map { Changelog.entries(entries, after: $0, through: currentVersion) }
            ?? entries.filter { $0.version == GitHubUpdater.normalized(currentVersion) }
        isAfterUpdate = true
        updatedFrom = previous
        isShowingWhatsNew = !whatsNew.isEmpty
    }

    private var isBusy: Bool {
        switch phase {
        case .checking, .downloading: true
        default: false
        }
    }

    private static func message(_ error: Error) -> String {
        if let error = error as? UpdateError { return error.description }
        if (error as? URLError)?.code == .notConnectedToInternet { return "You're offline. Connect to the internet and try again." }
        return error.localizedDescription
    }
}

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

    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    private let updater = GitHubUpdater(
        // Set by bundle.sh from DUSTPAN_REPO; empty in builds that don't ship updates.
        repo: Bundle.main.infoDictionary?["DustpanUpdateRepo"] as? String ?? "",
        bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.local.dustpan"
    )
    private var task: Task<Void, Never>?

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
        guard case .ready(_, let staged) = phase else { return }
        do {
            try GitHubUpdater.installAndRelaunch(staged: staged, replacing: Bundle.main.bundleURL)
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

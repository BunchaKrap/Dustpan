import CryptoKit
import Foundation

/// A published release on GitHub that the app can update to.
public struct ReleaseInfo: Sendable, Equatable {
    public let version: String
    public let title: String
    public let notes: String
    public let pageURL: URL
    public let downloadURL: URL
    public let sizeBytes: Int64
    /// `sha256:<hex>` as GitHub reports it for uploaded assets, when available.
    public let digest: String?
    public let publishedAt: Date?

    public init(version: String, title: String, notes: String, pageURL: URL, downloadURL: URL,
                sizeBytes: Int64, digest: String?, publishedAt: Date?) {
        self.version = version
        self.title = title
        self.notes = notes
        self.pageURL = pageURL
        self.downloadURL = downloadURL
        self.sizeBytes = sizeBytes
        self.digest = digest
        self.publishedAt = publishedAt
    }
}

public enum UpdateError: Error, CustomStringConvertible, Sendable {
    case notConfigured
    case noRelease
    case noDownload
    case http(Int)
    case checksumMismatch
    case badArchive(String)
    case wrongApp(String)
    case signature(String)

    public var description: String {
        switch self {
        case .notConfigured: "Updates aren't set up for this build yet."
        case .noRelease: "No releases have been published yet."
        case .noDownload: "The latest release has no macOS download attached."
        case .http(let code): code == 403 ? "GitHub is rate-limiting requests. Try again in a few minutes." : "GitHub returned an error (\(code))."
        case .checksumMismatch: "The download didn't match its published checksum, so it wasn't installed."
        case .badArchive(let detail): "The download couldn't be unpacked: \(detail)"
        case .wrongApp(let detail): "The download isn't a Dustpan build: \(detail)"
        case .signature(let detail): "The downloaded app failed its code signature check: \(detail)"
        }
    }
}

/// Checks GitHub Releases for a newer build, downloads it and stages it for installation.
/// Only talks to the network when asked; nothing here runs on its own.
public struct GitHubUpdater: Sendable {
    /// `owner/name` of the public GitHub repository.
    public let repo: String
    public let bundleIdentifier: String

    public init(repo: String, bundleIdentifier: String) {
        self.repo = repo
        self.bundleIdentifier = bundleIdentifier
    }

    public var isConfigured: Bool {
        let parts = repo.split(separator: "/")
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty }
    }

    public var releasesPage: URL? { isConfigured ? URL(string: "https://github.com/\(repo)/releases") : nil }

    // MARK: Checking

    public func latestRelease() async throws -> ReleaseInfo {
        guard isConfigured, let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { throw UpdateError.notConfigured }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Dustpan-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw UpdateError.noRelease }
        guard status == 200 else { throw UpdateError.http(status) }
        return try Self.parseRelease(data)
    }

    /// Reads GitHub's `releases/latest` JSON. Prefers a `*-macOS.zip` asset, else any `.zip`.
    public static func parseRelease(_ data: Data) throws -> ReleaseInfo {
        struct Asset: Decodable {
            let name: String
            let size: Int64
            let browser_download_url: URL
            let digest: String?
        }
        struct Release: Decodable {
            let tag_name: String
            let name: String?
            let body: String?
            let html_url: URL
            let published_at: Date?
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(Release.self, from: data)
        let zips = release.assets.filter { $0.name.lowercased().hasSuffix(".zip") }
        guard let asset = zips.first(where: { $0.name.lowercased().hasSuffix("-macos.zip") }) ?? zips.first else { throw UpdateError.noDownload }
        let version = normalized(release.tag_name)
        return ReleaseInfo(
            version: version,
            title: release.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Dustpan \(version)",
            notes: release.body ?? "",
            pageURL: release.html_url,
            downloadURL: asset.browser_download_url,
            sizeBytes: asset.size,
            digest: asset.digest,
            publishedAt: release.published_at
        )
    }

    /// "v0.3.0" → "0.3.0".
    public static func normalized(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespaces).drop { $0 == "v" || $0 == "V" }.description
    }

    /// Compares dotted numeric versions: 0.10.0 is newer than 0.9.2; 1.0 equals 1.0.0.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = normalized(candidate).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let b = normalized(current).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Downloading & staging

    /// Downloads the release, verifies it and unpacks it. Returns the staged `.app`, ready to swap in.
    public func downloadAndStage(_ release: ReleaseInfo) async throws -> URL {
        var request = URLRequest(url: release.downloadURL, timeoutInterval: 120)
        request.setValue("Dustpan-Updater", forHTTPHeaderField: "User-Agent")
        let (downloaded, response) = try await URLSession.shared.download(for: request)
        // file:// URLs are allowed so the self-test can exercise the whole pipeline offline.
        let status = (response as? HTTPURLResponse)?.statusCode ?? (release.downloadURL.isFileURL ? 200 : 0)
        guard status == 200 else { throw UpdateError.http(status) }

        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("DustpanUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let zip = staging.appendingPathComponent("update.zip")
        try fm.moveItem(at: downloaded, to: zip)

        if let digest = release.digest, digest.hasPrefix("sha256:") {
            guard try Self.sha256(of: zip) == digest.dropFirst("sha256:".count).lowercased() else { throw UpdateError.checksumMismatch }
        }

        let unpacked = staging.appendingPathComponent("unpacked")
        try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) { UpdateError.badArchive($0) }
        guard let app = try fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.badArchive("no app inside")
        }

        guard let info = Bundle(url: app)?.infoDictionary else { throw UpdateError.wrongApp("missing Info.plist") }
        let identifier = info["CFBundleIdentifier"] as? String ?? ""
        guard identifier == bundleIdentifier else { throw UpdateError.wrongApp("bundle identifier \(identifier)") }
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        guard Self.normalized(version) == release.version else { throw UpdateError.wrongApp("version \(version), expected \(release.version)") }

        try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) { UpdateError.signature($0) }
        // Downloaded through URLSession, so there's no quarantine flag to clear, but be safe.
        try? Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path]) { UpdateError.badArchive($0) }
        return app
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func run(_ tool: String, _ arguments: [String], error: (String) -> UpdateError) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw error(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "exit \(process.terminationStatus)" : message)
        }
    }

    // MARK: Installing

    /// Starts a detached helper that waits for this process to quit, swaps the bundles and relaunches.
    /// If the swap fails the old app is put back and reopened. Paths are passed as arguments, never interpolated.
    public static func installAndRelaunch(staged: URL, replacing current: URL, pid: Int32 = ProcessInfo.processInfo.processIdentifier) throws {
        let backup = current.deletingLastPathComponent().appendingPathComponent(".\(current.lastPathComponent).previous")
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$4"
        if mv "$2" "$4" && mv "$3" "$2"; then
          rm -rf "$4"
        else
          [ -e "$2" ] || mv "$4" "$2"
        fi
        open "$2"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "dustpan-update", String(pid), current.path, staged.path, backup.path]
        try process.run()
    }
}

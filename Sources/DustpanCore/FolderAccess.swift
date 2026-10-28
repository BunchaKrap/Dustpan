import Foundation

/// Opening some folders makes macOS hold the calling thread until a privacy decision is made (another app's
/// data, Desktop, Documents, Downloads, other disks). If nobody answers the permission dialog the call never
/// returns, so walkers register every folder they open here and the UI can say what it is waiting on.
public final class FolderAccessWatch: @unchecked Sendable {
    public static let shared = FolderAccessWatch()

    private let lock = NSLock()
    private var opening: [Int: (path: String, started: UInt64)] = [:]
    private var nextToken = 0

    public init() {}

    public func begin(_ path: String) -> Int {
        let started = DispatchTime.now().uptimeNanoseconds
        lock.lock(); defer { lock.unlock() }
        nextToken += 1
        opening[nextToken] = (path, started)
        return nextToken
    }

    public func end(_ token: Int) {
        lock.lock(); opening[token] = nil; lock.unlock()
    }

    /// The folder that has been opening the longest, if that is longer than `threshold` seconds.
    public func stalled(longerThan threshold: TimeInterval) -> (path: String, seconds: TimeInterval)? {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock(); defer { lock.unlock() }
        guard let oldest = opening.values.min(by: { $0.started < $1.started }) else { return nil }
        let seconds = Double(now - oldest.started) / 1e9
        return seconds > threshold ? (oldest.path, seconds) : nil
    }
}

/// Which macOS privacy protection a folder falls under, so the app can explain a block in plain words.
public enum ProtectedArea: String, CaseIterable, Sendable {
    case otherAppsData, desktop, documents, downloads, iCloudDrive, otherDisk, system

    public static func of(_ path: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> ProtectedArea {
        func inside(_ folder: String) -> Bool { path == folder || path.hasPrefix(folder + "/") }
        if inside(home + "/Library/Containers") || inside(home + "/Library/Group Containers") { return .otherAppsData }
        if inside(home + "/Desktop") { return .desktop }
        if inside(home + "/Documents") { return .documents }
        if inside(home + "/Downloads") { return .downloads }
        if inside(home + "/Library/Mobile Documents") || inside(home + "/Library/CloudStorage") { return .iCloudDrive }
        if inside("/Volumes") { return .otherDisk }
        return .system
    }

    public var name: String {
        switch self {
        case .otherAppsData: "Other apps' data"
        case .desktop: "Desktop"
        case .documents: "Documents"
        case .downloads: "Downloads"
        case .iCloudDrive: "iCloud Drive and cloud storage"
        case .otherDisk: "Other disks"
        case .system: "Folders macOS protects"
        }
    }

    /// Why macOS stepped in, written for the person using the app.
    public var explanation: String {
        switch self {
        case .otherAppsData: "macOS asks before Dustpan can look inside the data other apps keep in Library/Containers."
        case .desktop, .documents, .downloads: "macOS asks before Dustpan can read your \(name) folder."
        case .iCloudDrive: "macOS asks before Dustpan can read cloud folders, and may need to fetch their listings from the internet."
        case .otherDisk: "macOS asks before Dustpan can read external and network disks. A disconnected network disk can also stop responding."
        case .system: "macOS only lets apps with Full Disk Access read these folders."
        }
    }

    /// The System Settings pane where the permission can be granted.
    public var settingsURL: URL {
        switch self {
        case .desktop, .documents, .downloads, .otherDisk:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
        case .otherAppsData, .iCloudDrive, .system:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        }
    }

    public var settingsName: String {
        settingsURL.absoluteString.hasSuffix("Privacy_AllFiles") ? "Full Disk Access" : "Files & Folders"
    }
}

extension Error {
    /// True when a macOS privacy protection refused access (EPERM). Plain Unix permissions give EACCES,
    /// which no System Settings switch fixes, so those count as ordinary unreadable items.
    var isPrivacyDenied: Bool {
        let error = self as NSError
        let posix = (error.userInfo[NSUnderlyingErrorKey] as? NSError) ?? error
        return posix.domain == NSPOSIXErrorDomain && posix.code == Int(EPERM)
    }
}

import Foundation

/// How much a process deserves a closer look. Ordered from least to most concerning.
public enum TrustLevel: Int, Comparable, Sendable {
    /// Apple, the App Store, or a developer Apple has checked (notarized).
    case trusted
    /// No warning signs, but nobody Apple knows vouches for it. Normal for tools you installed yourself.
    case unverified
    /// One or more warning signs worth checking.
    case caution
    /// Signs that often go with malware.
    case suspicious

    public static func < (a: TrustLevel, b: TrustLevel) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self {
        case .trusted: "No warning signs"
        case .unverified: "Not verified by Apple"
        case .caution: "Worth a look"
        case .suspicious: "Looks suspicious"
        }
    }
}

/// One reason behind a verdict, written for the person using the app.
public struct WarningSign: Hashable, Sendable {
    public let level: TrustLevel
    public let title: String
    public let detail: String
}

public struct ProcessAssessment: Sendable {
    public let level: TrustLevel
    /// One-line verdict, e.g. "Signed by Slack Technologies, Inc. and checked by Apple."
    public let summary: String
    public let signs: [WarningSign]

    /// Rules are deliberately conservative: each sign is something malware commonly does, explained so a
    /// person can judge it. Nothing here proves a program is harmful or safe.
    public static func assess(_ process: RunningProcess, signer: CodeSigner, launchItem: LaunchItem?,
                              home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> ProcessAssessment {
        var signs: [WarningSign] = []
        let path = process.path ?? ""
        let isVerified: Bool
        let summary: String

        switch signer {
        case .apple:
            isVerified = true
            summary = "Signed by Apple."
        case .appStore(let organization):
            isVerified = true
            summary = "From the Mac App Store\(organization.map { ", made by \($0)" } ?? "")."
        case .developerID(let organization, _, let notarized):
            isVerified = notarized
            let who = organization ?? "an identified developer"
            summary = notarized ? "Signed by \(who) and checked by Apple." : "Signed by \(who), but not checked (notarized) by Apple."
        case .untrustedCertificate(let name):
            isVerified = false
            summary = "Signed by \(name.map { "\"\($0)\"" } ?? "an unknown certificate"), which Apple didn't issue."
            signs.append(WarningSign(level: .caution, title: "Signed with a certificate Apple doesn't recognise",
                                     detail: "Real developers sign with a certificate from Apple. Cracked or repackaged apps are re-signed like this, and they're one of the most common ways malware gets onto Macs. If you didn't get it from the developer, replace it with a copy that is."))
        case .adHoc, .unsigned:
            isVerified = false
            summary = "Not signed by an identified developer. That's normal for tools you build or install yourself (Homebrew, Node, Python), unusual for downloaded apps."
        case .invalid:
            isVerified = false
            summary = "Its signature doesn't match the program."
            signs.append(WarningSign(level: .suspicious, title: "Broken signature",
                                     detail: "The program was changed after its developer signed it. Updates sometimes cause this briefly, but tampered software looks exactly like this."))
        case .unknown:
            isVerified = false
            summary = "macOS didn't let Dustpan check who made it."
        }
        let isUnsigned = signer == .adHoc || signer == .unsigned || signer == .invalid

        // A macOS process name on a program Apple didn't sign: a classic disguise.
        if signer != .apple, signer != .unknown, appleProcessNames.contains(process.displayName) || appleProcessNames.contains(process.shortName) {
            signs.append(WarningSign(level: .suspicious, title: "Uses a macOS process name",
                                     detail: "It's called \(process.displayName), like a part of macOS, but Apple didn't sign it. Malware often borrows system names to blend in."))
        }

        let tempFolders = ["/tmp/", "/private/tmp/", "/private/var/folders/", "/var/folders/", "/Users/Shared/", home + "/Downloads/"]
        if tempFolders.contains(where: path.hasPrefix) {
            signs.append(WarningSign(level: isUnsigned ? .suspicious : .caution, title: "Runs from a temporary or shared folder",
                                     detail: "Installed software normally lives in Applications or a system folder. Programs running from temporary, shared or Downloads folders are often installers, or something that doesn't want to be noticed."))
        } else if path.hasPrefix(home + "/"), path.dropFirst(home.count + 1).split(separator: "/").dropLast().contains(where: { $0.hasPrefix(".") }), isUnsigned {
            signs.append(WarningSign(level: .caution, title: "Runs from a hidden folder",
                                     detail: "It lives in a folder that starts with a dot, which Finder hides. Developer tools (.nvm, .cargo, .vscode) do this legitimately; if you don't recognise it, look closer."))
        }

        if process.executableIsMissing {
            signs.append(WarningSign(level: isUnsigned ? .suspicious : .caution, title: "Its program file is gone",
                                     detail: "The file it was started from no longer exists. Apps that updated while running do this until restarted; malware sometimes deletes itself to hide."))
        }

        if let launchItem, !isVerified, !launchItem.isHomebrewService {
            signs.append(WarningSign(level: .caution, title: "Starts automatically, unverified",
                                     detail: "\(launchItem.plist.lastPathComponent) starts it \(launchItem.startsWhen)\(launchItem.keepsAlive ? " and restarts it if it quits" : ""). Unverified programs that keep themselves running deserve a check."))
        }

        let worst = signs.map(\.level).max()
        let level = worst ?? (isVerified ? .trusted : .unverified)
        return ProcessAssessment(level: level, summary: summary, signs: signs)
    }

    /// Names of macOS processes that malware likes to imitate.
    static let appleProcessNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "Finder", "Dock", "SystemUIServer", "mds", "mds_stores",
        "mdworker", "mdworker_shared", "softwareupdated", "cloudd", "bird", "trustd", "securityd", "syspolicyd", "XProtect",
        "coreaudiod", "bluetoothd", "airportd", "sharingd", "nsurlsessiond", "opendirectoryd", "Spotlight", "systemstats",
    ]
}

/// Plain-English notes for common processes, so people know what they're looking at before stopping anything.
public enum ProcessGuide {
    public static func description(for name: String) -> String? { known[name] }

    static let known: [String: String] = [
        "kernel_task": "The core of macOS. High CPU here usually means the Mac is hot and macOS is slowing things down to cool it.",
        "launchd": "Starts and supervises every other process on the Mac.",
        "WindowServer": "Draws everything on your screen. Busy when lots of windows, animations or displays are active.",
        "loginwindow": "Your login session. Quitting it logs you out.",
        "Finder": "The Finder app: desktop, windows and file browsing.",
        "Dock": "The Dock, Mission Control and Launchpad.",
        "SystemUIServer": "Menu bar items such as the clock, Wi-Fi and battery.",
        "ControlCenter": "Control Center and its menu bar icons.",
        "mds": "Spotlight's index server. Busy after big file changes or a macOS update; settles down by itself.",
        "mds_stores": "Spotlight writing its search index. Temporary high CPU is normal.",
        "mdworker_shared": "Spotlight reading new or changed files so you can search them.",
        "mdworker": "Spotlight reading new or changed files so you can search them.",
        "photoanalysisd": "Photos finding faces, objects and memories in your library. Runs mostly while the Mac is idle.",
        "mediaanalysisd": "Analyses photos and videos for search and Live Text.",
        "cloudd": "iCloud sync for apps and iCloud Drive.",
        "bird": "iCloud Drive syncing files.",
        "fileproviderd": "Keeps cloud storage folders (iCloud Drive, Dropbox, Google Drive) in sync with Finder.",
        "backupd": "Time Machine making a backup.",
        "softwareupdated": "Checks for and downloads macOS updates.",
        "nsurlsessiond": "Downloads and uploads in the background for apps and the system.",
        "coreaudiod": "All sound in and out of the Mac.",
        "bluetoothd": "Bluetooth connections.",
        "airportd": "Wi-Fi.",
        "sharingd": "AirDrop, Handoff and the Shared Computers list.",
        "trustd": "Checks certificates for secure websites and signed apps.",
        "syspolicyd": "Gatekeeper: checks apps before they open.",
        "XProtect": "Apple's built-in malware scanner.",
        "XprotectService": "Apple's built-in malware scanner.",
        "secd": "Keychain and password storage.",
        "tccd": "Privacy permissions: decides which apps may use the camera, microphone, files and so on.",
        "powerd": "Sleep, battery and power management.",
        "corespotlightd": "Spotlight indexing content inside apps.",
        "spotlightknowledged": "Spotlight suggestions.",
        "siriactionsd": "Siri and Shortcuts.",
        "remindd": "Reminders sync.",
        "calaccessd": "Calendar access for apps.",
        "accountsd": "Internet accounts (iCloud, Google, mail accounts) shared between apps.",
        "WallpaperAgent": "Your desktop picture.",
        "NotificationCenter": "Notifications and widgets.",
        "UserEventAgent": "Reacts to system events such as network changes and devices connecting.",
        "distnoted": "Lets apps notify each other about changes.",
        "cfprefsd": "Reads and saves app settings.",
        "logd": "Collects system logs.",
        "symptomsd": "Monitors network health.",
        "rapportd": "Lets your Apple devices find each other (Handoff, Universal Clipboard).",
        "com.apple.WebKit.WebContent": "A web page in Safari or another app's web view. One per open tab or page.",
        "com.apple.WebKit.Networking": "Network requests for Safari and web views.",
        "com.apple.WebKit.GPU": "Graphics for Safari and web views.",
        "Google Chrome Helper": "A Chrome tab, extension or plug-in. Chrome runs one per tab.",
        "Google Chrome Helper (Renderer)": "A Chrome tab or extension. Chrome runs one per tab.",
        "Electron": "An app built on Electron (web technology), such as VS Code, Slack or Discord.",
        "node": "Node.js, a JavaScript runtime used by developer tools and local servers.",
        "python3": "Python, used by scripts, developer tools and some apps.",
        "Python": "Python, used by scripts, developer tools and some apps.",
        "ruby": "Ruby, used by scripts and developer tools.",
        "java": "Java, used by some apps and developer tools.",
        "docker": "Docker containers.",
        "com.docker.backend": "Docker Desktop.",
        "ssh-agent": "Holds your SSH keys for Terminal and Git.",
        "zsh": "A Terminal shell.",
        "bash": "A Terminal shell.",
        "login": "A Terminal session.",
    ]
}

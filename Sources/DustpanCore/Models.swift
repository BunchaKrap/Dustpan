import Foundation

public enum JunkCategory: String, CaseIterable, Sendable, Codable {
    case userCaches
    case appCaches
    case userLogs
    case browserCaches
    case xcode
    case homebrew
    case packageManagers
    case devArtifacts
    case installers
    case docker
    case systemJunk
    case trash

    public var displayName: String {
        switch self {
        case .userCaches: "User Caches"
        case .appCaches: "App Caches"
        case .userLogs: "Logs & Crash Reports"
        case .browserCaches: "Browser Caches"
        case .xcode: "Xcode & Simulators"
        case .homebrew: "Homebrew Cache"
        case .packageManagers: "Developer Tool Caches"
        case .devArtifacts: "Project Build Files"
        case .installers: "Old Installers"
        case .docker: "Docker"
        case .systemJunk: "System Caches & Logs"
        case .trash: "Trash"
        }
    }

    /// SF Symbol name for the UI.
    public var symbolName: String {
        switch self {
        case .userCaches: "archivebox"
        case .appCaches: "square.stack.3d.up"
        case .userLogs: "doc.text"
        case .browserCaches: "globe"
        case .xcode: "hammer"
        case .homebrew: "mug"
        case .packageManagers: "shippingbox"
        case .devArtifacts: "folder.badge.gearshape"
        case .installers: "arrow.down.app"
        case .docker: "cube"
        case .systemJunk: "gearshape.2"
        case .trash: "trash"
        }
    }

    /// The shallowest scan depth that includes this category.
    public var minimumDepth: ScanDepth {
        switch self {
        case .appCaches: .standard
        case .devArtifacts, .installers, .systemJunk: .deep
        default: .quick
        }
    }
}

// MARK: - Scan options

public enum ScanDepth: String, CaseIterable, Codable, Sendable, Comparable {
    case quick
    case standard
    case deep

    public var displayName: String {
        switch self {
        case .quick: "Quick"
        case .standard: "Standard"
        case .deep: "Deep"
        }
    }

    public var summary: String {
        switch self {
        case .quick:
            "Common caches, logs, browsers, Xcode, Homebrew and npm/Yarn/pnpm. A few seconds."
        case .standard:
            "Adds app caches (Slack, VS Code, Discord…), crash reports, Gradle, CocoaPods, pip, Cargo, Go and more."
        case .deep:
            "Adds a search for project build files (node_modules, .build, target, Pods…), installers in Downloads, and system caches. Can take minutes."
        }
    }

    private var order: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (lhs: ScanDepth, rhs: ScanDepth) -> Bool { lhs.order < rhs.order }
}

/// Where a Deep scan searches for project build files.
public enum ScanScope: Codable, Hashable, Sendable {
    case home
    case startupDisk
    case folders([URL])

    public func roots(home: URL) -> [URL] {
        switch self {
        case .home: [home]
        case .startupDisk: [URL(fileURLWithPath: "/")]
        case .folders(let urls): urls
        }
    }
}

public struct ScanOptions: Codable, Hashable, Sendable {
    public var depth: ScanDepth
    public var scope: ScanScope
    public var excludedCategories: Set<JunkCategory>
    /// Items smaller than this are left out of the report.
    public var minimumItemBytes: Int64

    public init(depth: ScanDepth = .standard, scope: ScanScope = .home,
                excludedCategories: Set<JunkCategory> = [], minimumItemBytes: Int64 = 0) {
        self.depth = depth
        self.scope = scope
        self.excludedCategories = excludedCategories
        self.minimumItemBytes = minimumItemBytes
    }

    public func includes(_ category: JunkCategory) -> Bool {
        category.minimumDepth <= depth && !excludedCategories.contains(category)
    }
}

// MARK: - Results

public struct JunkItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let category: JunkCategory
    public let name: String
    public let url: URL
    public let sizeBytes: Int64
    /// False when the item is shown for information only (protected, needs FDA, or has a safer tool).
    public let isDeletable: Bool
    public let note: String?

    public var target: DeletionTarget { DeletionTarget(url: url, sizeBytes: sizeBytes) }
}

public struct ScanIssue: Hashable, Sendable {
    public let path: String
    public let message: String
}

public struct CategoryResult: Identifiable, Sendable {
    public var id: JunkCategory { category }
    public let category: JunkCategory
    public let items: [JunkItem]
    public let issues: [ScanIssue]

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    public var reclaimableBytes: Int64 { items.filter(\.isDeletable).reduce(0) { $0 + $1.sizeBytes } }
}

public struct JunkScanReport: Sendable {
    public let categories: [CategoryResult]
    public let scannedAt: Date
    public let duration: TimeInterval

    public var reclaimableBytes: Int64 { categories.reduce(0) { $0 + $1.reclaimableBytes } }
    public var allItems: [JunkItem] { categories.flatMap(\.items) }
}

public extension JunkScanReport {
    /// The same report without the given items (e.g. after they were moved to the Trash).
    func removing(_ urls: Set<URL>) -> JunkScanReport {
        let remaining = categories.compactMap { category -> CategoryResult? in
            let items = category.items.filter { !urls.contains($0.url) }
            guard !items.isEmpty || !category.issues.isEmpty else { return nil }
            return CategoryResult(category: category.category, items: items, issues: category.issues)
        }
        return JunkScanReport(categories: remaining, scannedAt: scannedAt, duration: duration)
    }
}

public extension Int64 {
    var formattedBytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

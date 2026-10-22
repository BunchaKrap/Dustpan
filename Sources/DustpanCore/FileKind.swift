import Foundation

/// Rough file type from the extension, used to filter the Largest Files view.
public enum FileKind: String, CaseIterable, Sendable {
    case video, image, audio, archive, installer, document, other

    public var displayName: String {
        switch self {
        case .video: "Videos"
        case .image: "Images"
        case .audio: "Audio"
        case .archive: "Archives"
        case .installer: "Installers"
        case .document: "Documents"
        case .other: "Other"
        }
    }

    private static let byExtension: [String: FileKind] = {
        var map: [String: FileKind] = [:]
        let table: [(FileKind, [String])] = [
            (.video, ["mov", "mp4", "m4v", "mkv", "avi", "wmv", "webm", "mpg", "mpeg", "flv", "3gp", "mts", "braw", "r3d"]),
            (.image, ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp", "raw", "cr2", "cr3", "nef", "arw", "dng", "psd", "svg", "exr"]),
            (.audio, ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "ogg", "opus", "caf", "alac", "logicx"]),
            (.archive, ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "lz4", "cpgz"]),
            (.installer, ["dmg", "pkg", "mpkg", "iso", "xip", "ipsw", "img", "exe", "msi"]),
            (.document, ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers", "txt", "rtf", "csv", "epub", "md"]),
        ]
        for (kind, extensions) in table {
            for ext in extensions { map[ext] = kind }
        }
        return map
    }()

    public static func of(_ url: URL) -> FileKind {
        byExtension[url.pathExtension.lowercased()] ?? .other
    }
}

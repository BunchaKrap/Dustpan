import AppKit
import SwiftUI

/// Outline icons from the design file, drawn from their original SVG path data.
public enum Glyph: String, CaseIterable, Sendable {
    // Sidebar & chrome
    case navCleanup, navDisk, navUninstaller, appearance, settings, rescan, close, sliders, search, logDocument
    // States
    case emptyPan, okCircle, cleanSeal, warning, lock, check, chevron
    // Categories
    case caches, appCaches, logs, browser, xcode, brew, node, devFolder, installer, docker, gear, trash, folder, file
    // Places, views & navigation
    case navDuplicates, navHistory, home, drive, externalDrive, download, desktop, apps, photo, film, music, cloud, library
    case folderPlus, list, treemap, ranking, back, up, archive, restore, plus, arrowRight

    var path: String {
        switch self {
        case .navCleanup: "M6.4 2.2l1 2.6 2.6 1-2.6 1-1 2.6-1-2.6-2.6-1 2.6-1z M11.6 8.4l.7 1.7 1.7.7-1.7.7-.7 1.7-.7-1.7-1.7-.7 1.7-.7z"
        case .navDisk: "M8 2a6 6 0 100 12A6 6 0 008 2z M8 8V2 M8 8l5.2 3"
        case .navUninstaller: "M2.5 3.5h11v9a1 1 0 01-1 1h-9a1 1 0 01-1-1z M5 6h6l-.5 5.5h-5z M6.6 6V5h2.8v1"
        case .appearance: "M8 3a5 5 0 100 10A5 5 0 008 3z M8 3v10"
        case .settings, .gear:
            "M8 5.6a2.4 2.4 0 100 4.8 2.4 2.4 0 000-4.8z M8 1.8v1.8M8 12.4v1.8M1.8 8h1.8M12.4 8h1.8M3.6 3.6l1.3 1.3M11.1 11.1l1.3 1.3M3.6 12.4l1.3-1.3M11.1 4.9l1.3-1.3"
        case .rescan: "M13.5 8a5.5 5.5 0 11-1.9-4.2 M13.6 2.6v3.1h-3.1"
        case .close: "M3.5 3.5l9 9M12.5 3.5l-9 9"
        case .sliders: "M2.5 4.5h11M2.5 8h11M2.5 11.5h11 M5.5 3v3 M10.5 6.5v3 M7 10v3"
        case .search: "M7 2.2a4.8 4.8 0 100 9.6 4.8 4.8 0 000-9.6z M10.5 10.5l3 3"
        case .logDocument: "M4 2h5l3 3v9H4z M6 8h4M6 10.5h4"
        case .emptyPan: "M2.4 6.6h11.2l-1.5 6.2a1 1 0 01-1 .8H4.9a1 1 0 01-1-.8z M10.2 6.6l1.8-4.2 1.7.7"
        case .okCircle: "M8 1.6a6.4 6.4 0 100 12.8A6.4 6.4 0 008 1.6z M5.2 8.2l2 2 3.6-4"
        case .cleanSeal: "M8 1.4a6.6 6.6 0 100 13.2A6.6 6.6 0 008 1.4z M8 2.8a5.2 5.2 0 100 10.4A5.2 5.2 0 008 2.8z M5.4 8.2l1.9 1.9 3.4-3.9"
        case .warning: "M8 2.4l6 11H2z M8 6v3.6M8 11.3v.6"
        case .lock: "M4 7.2h8v6H4z M5.7 7.2V5a2.3 2.3 0 014.6 0v2.2"
        case .check: "M2.4 6.2l2.3 2.3 4.6-5"
        case .chevron: "M4 2l4 4-4 4"
        case .caches: "M2.2 3.6h11.6v2.6H2.2z M3.4 6.2v6.4a.8.8 0 00.8.8h7.6a.8.8 0 00.8-.8V6.2 M6.3 8.7h3.4"
        case .appCaches: "M8 2.2l5.6 2.8L8 7.8 2.4 5z M2.4 8L8 10.8 13.6 8 M2.4 11L8 13.8 13.6 11"
        case .logs: "M4 2h5l3 3v9H4z M9 2v3h3 M6 8.2h4 M6 10.6h4"
        case .browser: "M8 2a6 6 0 100 12A6 6 0 008 2z M2 8h12 M8 2c2.6 3.4 2.6 8.6 0 12 M8 2C5.4 5.4 5.4 10.6 8 14"
        case .xcode: "M2.8 13.2l5-5 M8.6 4l3.4 3.4-1.8 1.8L6.8 5.8z M11.4 2.2l2.4 2.4-1.5 1.5-2.4-2.4z"
        case .brew: "M3.4 5h7.2v6.2a1.8 1.8 0 01-1.8 1.8H5.2a1.8 1.8 0 01-1.8-1.8z M10.6 6.4h2.2a1.5 1.5 0 010 3h-2.2"
        case .node: "M2.6 5.2L8 2.6l5.4 2.6v5.6L8 13.4 2.6 10.8z M2.6 5.2L8 7.8m0 0l5.4-2.6M8 7.8v5.6"
        case .devFolder: "M2 4.4h4.2l1.2 1.6h6.6v6.6a.8.8 0 01-.8.8H2.8a.8.8 0 01-.8-.8z M6.6 8.2l-1.4 1.5 1.4 1.5 M9.4 8.2l1.4 1.5-1.4 1.5"
        case .installer: "M3 9.5h10v3.7a.8.8 0 01-.8.8H3.8a.8.8 0 01-.8-.8z M8 2v6 M5.6 5.8L8 8.2l2.4-2.4"
        case .docker: "M2.8 6.6h3.2v3.4H2.8z M7.4 6.6h3.2v3.4H7.4z M5.2 2.6h3.4v3.2H5.2z M1.8 12.4h12.4"
        case .trash: "M3.6 5h8.8l-.8 8.2a.8.8 0 01-.8.8H5.2a.8.8 0 01-.8-.8z M2.4 5h11.2 M6.4 3h3.2v2H6.4z"
        case .folder: "M2 4.4h4.2l1.2 1.6h6.6v6.6a.8.8 0 01-.8.8H2.8a.8.8 0 01-.8-.8z"
        case .file: "M4 2h5l3 3v9H4z M9 2v3h3"
        case .navDuplicates: "M5.5 2.5h7.5v9H5.5z M3 5v8.5h7.5"
        case .navHistory, .restore: "M2.6 8a5.4 5.4 0 101.6-3.8 M2.4 2.4v2.8h2.8 M8 5v3.2l2.2 1.4"
        case .home: "M2.5 7.5L8 2.8l5.5 4.7 M4 6.4v7h8v-7 M6.6 13.4V9.8h2.8v3.6"
        case .drive: "M2 9.5h12v3.5H2z M3 9.5l1.6-6h6.8l1.6 6 M11 11.25h.8"
        case .externalDrive: "M3.5 2.5h9v11h-9z M5.5 11h5 M8 5a1.3 1.3 0 100 2.6A1.3 1.3 0 008 5z"
        case .download: "M8 2v8 M4.8 7L8 10.2 11.2 7 M2.5 11.5v2h11v-2"
        case .desktop: "M2 3h12v8H2z M6 14h4 M8 11v3"
        case .apps: "M2.5 2.5h4.5v4.5H2.5z M9 2.5h4.5v4.5H9z M2.5 9h4.5v4.5H2.5z M9 9h4.5v4.5H9z"
        case .photo: "M2 3.5h12v9H2z M2 10.5l3.5-3.2 3 2.7 2-1.7 3.5 3 M10.5 5.4a.9.9 0 100 1.8.9.9 0 000-1.8z"
        case .film: "M2 3h12v10H2z M5 3v10 M11 3v10 M2 6.3h3M2 9.7h3M11 6.3h3M11 9.7h3"
        case .music: "M6 12a1.8 1.8 0 11-3.6 0 1.8 1.8 0 013.6 0z M6 12V3.5l7-1.5v8.5 M13 10.5a1.8 1.8 0 11-3.6 0 1.8 1.8 0 013.6 0z"
        case .cloud: "M4.6 12.5a2.8 2.8 0 0 1-.5-5.6 4 4 0 0 1 7.7-.8 2.8 2.8 0 0 1 .2 6.4z"
        case .library: "M3 2.5v11 M6 2.5v11 M8.8 3.2l3.6 10"
        case .folderPlus: "M2 4.4h4.2l1.2 1.6h6.6v6.6a.8.8 0 01-.8.8H2.8a.8.8 0 01-.8-.8z M8 7.6v3.8 M6.1 9.5h3.8"
        case .list: "M2.5 4h11M2.5 8h11M2.5 12h11"
        case .treemap: "M2 2.5h12v11H2z M8.5 2.5v11 M2 9h6.5 M8.5 7h5.5"
        case .ranking: "M2.5 13.5h11 M4.5 13.5V9 M8 13.5V3.5 M11.5 13.5V6.5"
        case .back: "M10 3L5 8l5 5"
        case .up: "M3 10l5-5 5 5"
        case .archive: "M2.5 3h11v3h-11z M3.5 6v7h9V6 M6.5 8.5h3"
        case .plus: "M8 3v10M3 8h10"
        case .arrowRight: "M3 8h10M9 4l4 4-4 4"
        }
    }

    /// Check and chevron are drawn on a 12-unit grid, everything else on 16.
    var viewBox: Int { self == .check || self == .chevron ? 12 : 16 }

    var roundCaps: Bool { [.check, .chevron, .back, .up, .navHistory, .restore, .plus, .arrowRight].contains(self) }

    public var defaultLineWidth: CGFloat {
        switch self {
        case .check: 2
        case .chevron, .close: 1.8
        case .back, .up, .plus: 1.6
        case .arrowRight: 2
        case .rescan, .okCircle, .search: 1.5
        case .lock, .warning, .logDocument: 1.3
        case .navCleanup, .navDisk, .navUninstaller: 1.25
        case .emptyPan, .cleanSeal: 1.1
        default: 1.2
        }
    }
}

@MainActor
enum GlyphCache {
    private static var images: [String: NSImage] = [:]

    static func image(_ glyph: Glyph, size: CGFloat, lineWidth: CGFloat) -> NSImage {
        let key = "\(glyph.rawValue)|\(size)|\(lineWidth)"
        if let cached = images[key] { return cached }
        let box = glyph.viewBox
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(box)" height="\(box)" viewBox="0 0 \(box) \(box)" \
        fill="none" stroke="#000" stroke-width="\(lineWidth)" stroke-linejoin="round" stroke-linecap="\(glyph.roundCaps ? "round" : "butt")">\
        <path d="\(glyph.path)"/></svg>
        """
        let image = NSImage(data: Data(svg.utf8)) ?? NSImage()
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        images[key] = image
        return image
    }
}

/// A design glyph tinted with the current foreground style.
public struct GlyphView: View {
    let glyph: Glyph
    let size: CGFloat
    let lineWidth: CGFloat?

    public init(_ glyph: Glyph, size: CGFloat = 16, lineWidth: CGFloat? = nil) {
        self.glyph = glyph
        self.size = size
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Image(nsImage: GlyphCache.image(glyph, size: size, lineWidth: lineWidth ?? glyph.defaultLineWidth))
            .renderingMode(.template)
            .frame(width: size, height: size)
    }
}

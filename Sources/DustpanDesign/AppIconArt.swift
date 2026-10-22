import AppKit

/// The four icon directions from "Dustpan Icon.dc.html", rebuilt as 1024 px Big Sur-grid artwork.
public enum AppIconStyle: String, CaseIterable, Codable, Sendable {
    case sweep, paper, catchDust, mark

    public var displayName: String {
        switch self {
        case .sweep: "Sweep"
        case .paper: "Paper"
        case .catchDust: "Catch"
        case .mark: "Mark"
        }
    }

    public var tagline: String {
        switch self {
        case .sweep: "Warm gradient, sparkles"
        case .paper: "Light ground, pan and brush"
        case .catchDust: "Dark slate, dust falling in"
        case .mark: "Sage, solid silhouette"
        }
    }

    /// Accepts the short names used by `bundle.sh` (`DUSTPAN_ICON=catch`).
    public init?(argument: String) {
        switch argument.lowercased() {
        case "sweep": self = .sweep
        case "paper": self = .paper
        case "catch", "catchdust": self = .catchDust
        case "mark": self = .mark
        default: return nil
        }
    }
}

public enum AppIconArt {
    // Shared geometry on the design's 100-unit glyph grid.
    private static let wall = #"<path d="M26 38h48a4 4 0 014 4v10H22V42a4 4 0 014-4z""#
    private static let scoop = #"<path d="M22 52h56l14 26H8z"/>"#
    private static let floor = #"<path d="M8 78h84a4 4 0 014 4v2a4 4 0 01-4 4H8a4 4 0 01-4-4v-2a4 4 0 014-4z"/>"#
    private static let handle = #"<rect x="74" y="2" width="10" height="36" rx="5" transform="rotate(20 79 20)""#

    public static func svg(_ style: AppIconStyle) -> String {
        let background: String
        let glyph: String
        var border = ""

        switch style {
        case .sweep:
            background = gradient(x1: 0.35, x2: 0.65, stops: [(0, "#d79a54"), (0.48, "#b4753a"), (1, "#905a2a")])
            glyph = """
            <g fill="#fff8f0">\(wall) opacity=".68"/>\(scoop)\(floor)\(handle)/>
            <path d="M22 13l3.2 7.6 7.6 3.2-7.6 3.2L22 34.6l-3.2-7.6L11.2 24l7.6-3.2z"/>
            <path d="M43 5l2 4.6 4.6 2-4.6 2L43 18.2l-2-4.6-4.6-2 4.6-2z"/></g>
            """
        case .paper:
            background = gradient(x1: 0.41, x2: 0.59, stops: [(0, "#faf6ef"), (1, "#e8ddcb")])
            border = ##"<rect x="102" y="102" width="820" height="820" rx="183" fill="none" stroke="#000" stroke-opacity=".1" stroke-width="4"/>"##
            glyph = """
            <g fill="#8a5a2c">
            <rect x="4" y="10" width="13" height="23" rx="4.5" transform="rotate(-20 10.5 21.5)" fill="#c98b4b"/>
            <path d="M9 35.5l4.6 6.6" stroke="#a8703c" stroke-width="3.4" stroke-linecap="round"/>
            <path d="M15.5 32.5l4.2 6" stroke="#a8703c" stroke-width="3.4" stroke-linecap="round"/>
            \(wall) opacity=".55"/>\(scoop)\(floor)\(handle) fill="#b4753a"/></g>
            """
        case .catchDust:
            background = gradient(x1: 0.35, x2: 0.65, stops: [(0, "#45444a"), (0.55, "#2c2b30"), (1, "#1c1b1f")])
            glyph = """
            <g fill="#e9c49a">
            <circle cx="34" cy="20" r="6" fill="#8d8a93"/><circle cx="53" cy="10" r="4.2" fill="#8d8a93"/><circle cx="65" cy="24" r="3.2" fill="#8d8a93"/>
            \(wall) opacity=".6"/>\(scoop)\(floor)\(handle)/></g>
            """
        case .mark:
            background = gradient(x1: 0.35, x2: 0.65, stops: [(0, "#6f8f7c"), (0.52, "#4c6b5b"), (1, "#354c40")])
            glyph = """
            <g fill="#ffffff">
            <path d="M24 34h52a5 5 0 015 5v13H19V39a5 5 0 015-5z"/><path d="M19 52h62l15 26H4z"/>
            <path d="M4 78h92a4 4 0 014 4v2a4 4 0 01-4 4H4a4 4 0 01-4-4v-2a4 4 0 014-4z"/>
            <rect x="72" y="0" width="12" height="36" rx="6" transform="rotate(20 78 18)"/></g>
            """
        }

        // 824 pt rounded square centred on a 1024 canvas (Big Sur grid); glyph fills 70% of it like the design cards.
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
        <defs>\(background)</defs>
        <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>\(border)
        <g transform="translate(223.6 223.6) scale(5.768)">\(glyph)</g>
        </svg>
        """
    }

    private static func gradient(x1: Double, x2: Double, stops: [(Double, String)]) -> String {
        let stopTags = stops.map { #"<stop offset="\#($0.0)" stop-color="\#($0.1)"/>"# }.joined()
        return #"<linearGradient id="bg" x1="\#(x1)" y1="0" x2="\#(x2)" y2="1">\#(stopTags)</linearGradient>"#
    }

    public static func image(_ style: AppIconStyle) -> NSImage {
        NSImage(data: Data(svg(style).utf8)) ?? NSImage()
    }

    /// PNG rendering at an exact pixel size (for building the .icns).
    public static func pngData(_ style: AppIconStyle, pixels: Int) -> Data? {
        guard let source = NSImage(data: Data(svg(style).utf8)),
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

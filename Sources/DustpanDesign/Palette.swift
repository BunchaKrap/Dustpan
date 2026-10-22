import SwiftUI

public enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    case system, light, dark

    public var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public enum AccentTheme: String, CaseIterable, Codable, Sendable {
    case walnut, sage, slate, plum

    public var displayName: String {
        switch self {
        case .walnut: "Walnut"
        case .sage: "Sage"
        case .slate: "Slate"
        case .plum: "Plum"
        }
    }

    public var color: Color {
        switch self {
        case .walnut: Color(hex: 0xA8703C)
        case .sage: Color(hex: 0x4B6B5A)
        case .slate: Color(hex: 0x4A6A8F)
        case .plum: Color(hex: 0x8A6A99)
        }
    }
}

/// Colour tokens from the Dustpan design file (`THEMES` light / dark).
public struct Palette {
    public let isDark: Bool
    public let accent: Color

    public let bg: Color
    public let panel: Color
    /// Raised cards on the sidebar (New Scan, disk usage).
    public let card: Color
    public let sidebar: Color
    public let bar: Color
    public let sheet: Color
    public let field: Color
    public let text: Color
    public let text2: Color
    public let text3: Color
    public let sep: Color
    public let hair: Color
    public let rowHover: Color
    public let chip: Color
    public let btn: Color
    public let btnBorder: Color
    public let btnHover: Color
    public let okBg: Color
    public let okBorder: Color
    public let warnBg: Color
    public let warnBorder: Color

    public static let danger = Color(hex: 0xD0402F)
    public static let okInk = Color(hex: 0x2F9E4F)
    public static let warnInk = Color(hex: 0xC98A2E)
    public static let disabledFill = Color(hex: 0xB6B2AD)

    public static func make(dark: Bool, accent: AccentTheme) -> Palette {
        dark
            ? Palette(
                isDark: true, accent: accent.color,
                bg: Color(hex: 0x1F1E1C), panel: Color(hex: 0x262523), card: .white.opacity(0.07), sidebar: Color(hex: 0x282522),
                bar: Color(red: 34 / 255, green: 33 / 255, blue: 31 / 255).opacity(0.8), sheet: Color(hex: 0x2B2927),
                field: Color(hex: 0x2C2B28), text: Color(hex: 0xF2F1EF), text2: Color(hex: 0x948F89), text3: Color(hex: 0x6D6862),
                sep: .black.opacity(0.6), hair: .white.opacity(0.09), rowHover: .white.opacity(0.05), chip: Color(hex: 0x312F2C),
                btn: Color(hex: 0x3A3835), btnBorder: .black.opacity(0.5), btnHover: Color(hex: 0x454340),
                okBg: Color(hex: 0x1F2D22), okBorder: Color(red: 80 / 255, green: 190 / 255, blue: 110 / 255).opacity(0.28),
                warnBg: Color(hex: 0x2E2719), warnBorder: warnInk.opacity(0.3)
            )
            : Palette(
                isDark: false, accent: accent.color,
                bg: .white, panel: Color(hex: 0xFBFAF8), card: .white.opacity(0.85), sidebar: Color(hex: 0xF1EBE4),
                bar: .white.opacity(0.72), sheet: Color(hex: 0xF7F5F2),
                field: .white, text: Color(hex: 0x1D1D1F), text2: Color(hex: 0x86868B), text3: Color(hex: 0xB0ACA6),
                sep: .black.opacity(0.14), hair: .black.opacity(0.09), rowHover: .black.opacity(0.04), chip: Color(hex: 0xF4F1ED),
                btn: .white, btnBorder: .black.opacity(0.2), btnHover: Color(hex: 0xF2F0ED),
                okBg: Color(hex: 0xEEF6EF), okBorder: Color(red: 52 / 255, green: 160 / 255, blue: 80 / 255).opacity(0.3),
                warnBg: Color(hex: 0xFDF5E8), warnBorder: warnInk.opacity(0.35)
            )
    }
}

/// The v2 design's saturated tints for category and section icon tiles.
public enum Tint {
    public static let orange = Color(hex: 0xD9822F)
    public static let blue = Color(hex: 0x3D7FDC)
    public static let purple = Color(hex: 0x8A5ED2)
    public static let grey = Color(hex: 0x7F7A73)
    public static let teal = Color(hex: 0x2A9D97)
    public static let green = Color(hex: 0x2F9E4F)

    public static let caches = Color(hex: 0x4F8FE6)
    public static let logs = Color(hex: 0x7D8A99)
    public static let browser = Color(hex: 0xF08A3C)
    public static let xcode = Color(hex: 0x5F6EE0)
    public static let brew = Color(hex: 0xE0A83A)
    public static let node = Color(hex: 0x4FB36A)
    public static let docker = Color(hex: 0x2FA8C9)
    public static let pink = Color(hex: 0xD0477A)
    public static let lilac = Color(hex: 0x9A7AD8)
    public static let stone = Color(hex: 0x9A948D)

    /// Rotating tints for lists of folders (Disk Space rows, places).
    public static let cycle: [Color] = [lilac, caches, browser, brew, node, docker, pink, logs, xcode]
}

public extension Color {
    /// Mixes towards white, like CSS `color-mix(in srgb, c 70%, white)` for fraction 0.3.
    func lightened(_ fraction: CGFloat) -> Color {
        Color(nsColor: NSColor(self).usingColorSpace(.sRGB)?.blended(withFraction: fraction, of: .white) ?? NSColor(self))
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.make(dark: false, accent: .walnut)
}

public extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

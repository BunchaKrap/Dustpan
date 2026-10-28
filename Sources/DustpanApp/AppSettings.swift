import AppKit
import DustpanDesign
import SwiftUI

/// User-facing look & feel. Persisted in UserDefaults and applied app-wide.
@MainActor
@Observable
final class AppSettings {
    var appearance: AppearanceMode {
        didSet { save(appearance.rawValue, "appearance"); applyAppearance() }
    }
    var accent: AccentTheme {
        didSet { save(accent.rawValue, "accent") }
    }
    var appIcon: AppIconStyle {
        didSet { save(appIcon.rawValue, "appIcon"); applyIcon() }
    }
    /// The slow ribbons behind the content. macOS's Reduce Motion holds them still either way.
    var backgroundMotion: Bool {
        didSet { UserDefaults.standard.set(backgroundMotion, forKey: "backgroundMotion") }
    }

    init() {
        let defaults = UserDefaults.standard
        appearance = defaults.string(forKey: "appearance").flatMap(AppearanceMode.init) ?? .system
        accent = defaults.string(forKey: "accent").flatMap(AccentTheme.init) ?? .walnut
        appIcon = defaults.string(forKey: "appIcon").flatMap(AppIconStyle.init(rawValue:)) ?? .sweep
        backgroundMotion = defaults.object(forKey: "backgroundMotion") as? Bool ?? true
    }

    func applyAll() {
        applyAppearance()
        applyIcon()
    }

    /// Flips between light and dark (the sidebar's half-moon button).
    func toggleAppearance(current scheme: ColorScheme) {
        appearance = scheme == .dark ? .light : .dark
    }

    private func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func applyIcon() {
        NSApp.applicationIconImage = AppIconArt.image(appIcon)
    }

    private func save(_ value: String, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

/// Injects the palette for the effective colour scheme and chosen accent.
struct Themed<Content: View>: View {
    let settings: AppSettings
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .environment(\.palette, Palette.make(dark: scheme == .dark, accent: settings.accent))
            .tint(settings.accent.color)
    }
}

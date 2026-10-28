import AppKit
import DustpanCore
import DustpanDesign
import SwiftUI

// Locations offered as one-click scan targets, plus the navigation controls shared by every screen.

struct ScanPlace: Identifiable, Hashable {
    let url: URL
    let title: String
    let detail: String
    let glyph: Glyph
    let tint: Color

    var id: URL { url }
}

enum ScanPlaces {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Common folders that exist on this Mac. `forDuplicates` leaves out places full of app data.
    static func folders(forDuplicates: Bool = false) -> [ScanPlace] {
        let candidates: [ScanPlace?] = [
            ScanPlace(url: home, title: "Home Folder", detail: forDuplicates ? "Everything you own, minus app data" : "Everything you own",
                      glyph: .home, tint: Tint.orange),
            forDuplicates ? nil : ScanPlace(url: URL(fileURLWithPath: "/Applications"), title: "Applications", detail: "Installed apps",
                                            glyph: .apps, tint: Tint.purple),
            ScanPlace(url: home.appendingPathComponent("Downloads"), title: "Downloads", detail: "Installers, archives, leftovers",
                      glyph: .download, tint: Tint.docker),
            ScanPlace(url: home.appendingPathComponent("Documents"), title: "Documents", detail: "Your files and projects",
                      glyph: .logs, tint: Tint.caches),
            ScanPlace(url: home.appendingPathComponent("Desktop"), title: "Desktop", detail: "Files on your desktop",
                      glyph: .desktop, tint: Tint.xcode),
            ScanPlace(url: home.appendingPathComponent("Pictures"), title: "Pictures", detail: "Photos and images",
                      glyph: .photo, tint: Tint.browser),
            ScanPlace(url: home.appendingPathComponent("Movies"), title: "Movies", detail: "Videos and projects",
                      glyph: .film, tint: Tint.pink),
            ScanPlace(url: home.appendingPathComponent("Music"), title: "Music", detail: "Songs and audio",
                      glyph: .music, tint: Tint.lilac),
            ScanPlace(url: home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"), title: "iCloud Drive",
                      detail: "Only what's downloaded", glyph: .cloud, tint: Tint.blue),
            forDuplicates ? nil : ScanPlace(url: home.appendingPathComponent("Library"), title: "Library", detail: "App data, caches, containers",
                                            glyph: .library, tint: Tint.stone),
            ScanPlace(url: home.appendingPathComponent("Developer"), title: "Developer", detail: "Code and build output",
                      glyph: .devFolder, tint: Tint.node),
        ]
        return candidates.compactMap { $0 }.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    static func chooseFolder(startingAt url: URL?, message: String, prompt: String = "Scan") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = url
        panel.prompt = prompt
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func display(_ path: String) -> String {
        path.hasPrefix(home.path) ? "~" + path.dropFirst(home.path.count) : path
    }
}

// MARK: - Buttons

/// A clear navigation button: glyph plus label, 30 pt tall.
struct NavButton: View {
    let title: String
    let glyph: Glyph
    var kind: DPButtonKind = .secondary
    var height: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                GlyphView(glyph, size: 13)
                Text(title)
            }
        }
        .buttonStyle(DPButtonStyle(kind, height: height, horizontalPadding: 12, fontSize: 13))
    }
}

/// Square glyph-only navigation button (back, up) with a tooltip.
struct NavIconButton: View {
    let glyph: Glyph
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlyphView(glyph, size: 13).frame(width: 14)
        }
        .buttonStyle(DPButtonStyle(.secondary, height: 30, horizontalPadding: 8, fontSize: 13))
        .help(help)
    }
}

/// Toolbar segmented control with glyphs, sized for easy clicking.
struct ModePicker<Mode: Hashable>: View {
    let modes: [(mode: Mode, title: String, glyph: Glyph)]
    @Binding var selection: Mode
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(modes, id: \.mode) { item in
                let isSelected = item.mode == selection
                Button {
                    selection = item.mode
                } label: {
                    HStack(spacing: 5) {
                        GlyphView(item.glyph, size: 12)
                        Text(item.title).font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    }
                    .foregroundStyle(isSelected ? Color.white : palette.text)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(isSelected ? palette.accent : .clear, in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .segmentedContainer(palette)
    }
}

// MARK: - Breadcrumbs

/// Path as clickable chips: `[⌂ ~] › Documents › Projects`.
struct BreadcrumbBar: View {
    let crumbs: [(id: URL, title: String)]
    let onSelect: (Int) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        // Sits next to the navigation buttons while it fits; scrolls (showing the deepest folder) once it doesn't.
        ViewThatFits(in: .horizontal) {
            trail.frame(maxWidth: .infinity, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) { trail }
                .defaultScrollAnchor(.trailing)
        }
    }

    private var trail: some View {
        HStack(spacing: 2) {
            ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
                if index > 0 {
                    GlyphView(.chevron, size: 8).foregroundStyle(palette.text3).padding(.horizontal, 2)
                }
                let isLast = index == crumbs.count - 1
                Button {
                    onSelect(index)
                } label: {
                    HStack(spacing: 5) {
                        if index == 0 { GlyphView(.folder, size: 12).foregroundStyle(palette.accent) }
                        Text(crumb.title)
                            .font(.system(size: 13, weight: isLast ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isLast ? palette.text : palette.text2)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(isLast ? palette.chip : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .hoverFill(palette.rowHover, cornerRadius: 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isLast)
            }
        }
    }
}

// MARK: - Location tiles

/// A one-click location card used by the Disk Space and Duplicates start screens.
struct PlaceTile: View {
    let glyph: Glyph
    var tint: Color = Tint.stone
    let title: String
    let detail: String
    var dashed = false
    let action: () -> Void
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                TintTile(glyph, tint: tint, size: 34, glyphSize: 17, radius: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.text)
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(palette.text2).lineLimit(1)
                }
                Spacer(minLength: 0)
                GlyphView(.chevron, size: 9)
                    .foregroundStyle(palette.text3)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 11)
            .frame(height: 58)
            .hoverSurface(palette, hovering: hovering, radius: 14, dashed: dashed)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in withAnimation(Motion.hover) { hovering = isHovering } }
    }
}

/// A whole-disk card with a usage bar.
struct VolumeTile: View {
    let volume: MountedVolume
    let action: () -> Void
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 11) {
                    TintTile(volume.isStartup || volume.isInternal ? .drive : .externalDrive,
                             tint: volume.isStartup ? Tint.blue : Tint.docker, size: 40, glyphSize: 20, radius: 11)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(volume.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.text)
                        Text(volume.isStartup ? "Startup disk" : (volume.isInternal ? "Internal disk" : "External disk"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.text2)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        Text(volume.isStartup ? "Scan Entire Disk" : "Scan Disk")
                        GlyphView(.arrowRight, size: 11)
                            .frame(width: 22, height: 22)
                            .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.leading, 14)
                    .padding(.trailing, 5)
                    .frame(height: 34)
                    .background(palette.accent, in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: palette.accent.opacity(0.4), radius: 6, y: 4)
                    .brightness(hovering ? 0.05 : 0)
                }
                ProgressBar(fraction: Double(volume.usedBytes) / Double(max(volume.totalBytes, 1)))
                HStack {
                    Text("\(volume.usedBytes.formattedBytes) used").foregroundStyle(palette.text)
                    Spacer()
                    Text("\(volume.availableBytes.formattedBytes) free of \(volume.totalBytes.formattedBytes)")
                        .foregroundStyle(palette.text2)
                }
                .font(.system(size: 12))
                .monospacedDigit()
            }
            .padding(16)
            .hoverSurface(palette, hovering: hovering, radius: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in withAnimation(Motion.hover) { hovering = isHovering } }
    }
}

/// Small uppercase section label used on the start screens.
struct SectionLabel: View {
    let text: String
    @Environment(\.palette) private var palette

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.66)
            .foregroundStyle(palette.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - v2 building blocks

/// The large call-to-action from the v2 empty states: label plus an arrow chip.
struct HeroButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).font(.system(size: 14, weight: .semibold))
                GlyphView(.arrowRight, size: 12)
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.leading, 12)
            .padding(.trailing, -4)
        }
        .buttonStyle(DPButtonStyle(.primary, height: 40, horizontalPadding: 8, fontSize: 14))
    }
}

/// Circular scan progress with the percentage in the middle.
struct ProgressRing: View {
    let fraction: Double
    var size: CGFloat = 140
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            Circle().stroke(palette.hair, lineWidth: 10)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0.02), 1))
                .stroke(palette.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: fraction)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(Int((fraction * 100).rounded()))")
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                Text("%").font(.system(size: 15)).foregroundStyle(palette.text2)
            }
        }
        .frame(width: size - 20, height: size - 20)
        .frame(width: size, height: size)
    }
}

/// Chevron in a small chip that rotates when its card is open.
struct ExpandChevron: View {
    let isExpanded: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        GlyphView(.chevron, size: 9)
            .foregroundStyle(palette.text2)
            .frame(width: 22, height: 22)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 7))
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .animation(.easeOut(duration: 0.15), value: isExpanded)
    }
}

extension View {
    /// A solid card whose hover tint and accent ring fade in as separate layers. Animating opacity rather
    /// than swapping a solid fill for a translucent one avoids the grey flash of interpolating between them.
    func hoverSurface(_ palette: Palette, hovering: Bool, radius: CGFloat, dashed: Bool = false) -> some View {
        let dash: [CGFloat] = dashed ? [4, 3] : []
        return background {
            ZStack {
                RoundedRectangle(cornerRadius: radius).fill(palette.panel)
                RoundedRectangle(cornerRadius: radius).fill(palette.rowHover).opacity(hovering ? 1 : 0)
            }
        }
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(palette.hair, style: StrokeStyle(lineWidth: 0.5, dash: dash))
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(palette.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: dash))
                    .opacity(hovering ? 1 : 0)
            }
        }
    }

    /// The v2 card: 14 pt corners, hairline ring and a faint shadow.
    func cardStyle(_ palette: Palette, radius: CGFloat = 14) -> some View {
        background(palette.panel)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(palette.hair, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
    }
}

extension JunkCategory {
    var tint: Color {
        switch self {
        case .userCaches: Tint.caches
        case .appCaches: Tint.lilac
        case .userLogs: Tint.logs
        case .browserCaches: Tint.browser
        case .xcode: Tint.xcode
        case .homebrew: Tint.brew
        case .packageManagers: Tint.node
        case .devArtifacts: Tint.pink
        case .installers: Tint.docker
        case .docker: Color(hex: 0x2F8FD8)
        case .systemJunk: Tint.stone
        case .trash: Tint.stone
        }
    }
}

import AppKit
import DustpanCore
import DustpanDesign
import SwiftUI

@main
@MainActor
struct DustpanApp: App {
    @State private var settings = AppSettings()
    @State private var updates = UpdateModel()

    init() {
        // Lets `swift run Dustpan` show a normal window even without the .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Dustpan") {
            Themed(settings: settings) {
                RootView(settings: settings, updates: updates)
            }
            .frame(minWidth: 860, minHeight: 560)
            .onAppear { settings.applyAll() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1020, height: 664)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updates.checkNow() }
            }
        }

        Settings {
            Themed(settings: settings) {
                SettingsView(settings: settings)
            }
        }
        .windowResizability(.contentSize)
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case cleanup = "Cleanup"
    case duplicates = "Duplicates"
    case diskSpace = "Disk Space"
    case uninstaller = "Uninstaller"
    case history = "History"

    var id: Self { self }

    var glyph: Glyph {
        switch self {
        case .cleanup: .navCleanup
        case .diskSpace: .navDisk
        case .duplicates: .navDuplicates
        case .uninstaller: .navUninstaller
        case .history: .navHistory
        }
    }

    var tint: Color {
        switch self {
        case .cleanup: Tint.orange
        case .duplicates: Tint.teal
        case .diskSpace: Tint.blue
        case .uninstaller: Tint.purple
        case .history: Tint.grey
        }
    }

    /// Sidebar group headings, as in the v2 design.
    static let groups: [(title: String, sections: [SidebarSection])] = [
        ("Clean", [.cleanup, .duplicates]),
        ("Inspect", [.diskSpace, .uninstaller]),
        ("History", [.history]),
    ]

    /// ⌘1…⌘5 switch sections.
    var shortcut: KeyEquivalent {
        KeyEquivalent(Character("\(Self.allCases.firstIndex(of: self)! + 1)"))
    }
}

@MainActor
struct RootView: View {
    let settings: AppSettings
    let updates: UpdateModel
    // `open Dustpan.app --args -DustpanStartSection "Disk Space" -DustpanScanFolder ~/Documents` opens straight to a screen.
    @State private var selection = UserDefaults.standard.string(forKey: "DustpanStartSection").flatMap(SidebarSection.init) ?? .cleanup
    // Owned here so results survive switching sidebar sections.
    @State private var cleanup = CleanupModel()
    @State private var diskSpace = DiskSpaceModel()
    @State private var duplicates = DuplicatesModel()
    @State private var uninstaller = UninstallerModel()
    @State private var history = HistoryModel()
    @State private var startupDisk = MountedVolume.all().first(where: \.isStartup)
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(
                selection: $selection,
                settings: settings,
                pills: pills,
                startupDisk: startupDisk,
                cleanableBytes: cleanup.report?.reclaimableBytes ?? 0,
                updates: updates,
                onNewScan: newScan
            )
            Rectangle().fill(palette.sep).frame(width: 0.5)

            Group {
                switch selection {
                case .cleanup:
                    CleanupView(model: cleanup)
                case .diskSpace:
                    DiskSpaceView(model: diskSpace)
                case .duplicates:
                    DuplicatesView(model: duplicates)
                case .uninstaller:
                    UninstallerView(model: uninstaller)
                case .history:
                    HistoryView(model: history)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.bg)
        }
        .foregroundStyle(palette.text)
        .font(.system(size: 13))
        .ignoresSafeArea()
        .focusEffectDisabled()
        .overlay {
            if updates.isShowingSheet { UpdateSheet(model: updates) }
        }
        .animation(Motion.hover, value: updates.isShowingSheet)
        .onAppear {
            history.load()
            if let folder = UserDefaults.standard.string(forKey: "DustpanScanFolder") {
                diskSpace.scan(URL(fileURLWithPath: (folder as NSString).expandingTildeInPath))
            }
        }
        .onChange(of: selection) {
            startupDisk = MountedVolume.all().first(where: \.isStartup)
            if selection != .history { history.load() }
        }
    }

    /// Counts shown at the right of each sidebar row.
    private var pills: [SidebarSection: String] {
        var pills: [SidebarSection: String] = [:]
        if cleanup.isScanning {
            pills[.cleanup] = "\(Int(cleanup.scanFraction * 100))%"
        } else if let report = cleanup.report {
            pills[.cleanup] = report.reclaimableBytes.formattedBytes
        }
        if duplicates.report != nil { pills[.duplicates] = duplicates.wastedBytes.formattedBytes }
        if let root = diskSpace.root {
            let _ = diskSpace.revision
            pills[.diskSpace] = root.sizeBytes.formattedBytes
        }
        if !uninstaller.apps.isEmpty { pills[.uninstaller] = "\(uninstaller.apps.count)" }
        if !history.sessions.isEmpty { pills[.history] = "\(history.sessions.count)" }
        return pills
    }

    /// The sidebar's New Scan button starts over in the current section.
    private func newScan() {
        switch selection {
        case .cleanup, .history:
            selection = .cleanup
            if !cleanup.isBusy { cleanup.scan() }
        case .diskSpace:
            if !diskSpace.isBusy { diskSpace.showLauncher() }
        case .duplicates:
            if !duplicates.isBusy { duplicates.startOver() }
        case .uninstaller:
            uninstaller.reloadApps()
        }
    }
}

@MainActor
private struct Sidebar: View {
    @Binding var selection: SidebarSection
    let settings: AppSettings
    let pills: [SidebarSection: String]
    let startupDisk: MountedVolume?
    let cleanableBytes: Int64
    let updates: UpdateModel
    let onNewScan: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @State private var newScanHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the traffic lights; draggable like a title bar.
            WindowDragArea().frame(height: 52)

            Button(action: onNewScan) {
                HStack(spacing: 8) {
                    GlyphView(.plus, size: 14)
                    Text("New Scan").font(.system(size: 13.5, weight: .medium))
                    Spacer(minLength: 0)
                    Text("⌘N").font(.system(size: 11.5)).foregroundStyle(palette.text2)
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(palette.card)
                        RoundedRectangle(cornerRadius: 10).fill(palette.rowHover).opacity(newScanHover ? 1 : 0)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n")
            .onHover { isHovering in withAnimation(Motion.hover) { newScanHover = isHovering } }
            .help("Start over in the current section")
            .padding(.horizontal, 12)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(SidebarSection.groups.enumerated()), id: \.offset) { index, group in
                    Text(group.title.uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(palette.text2)
                        .padding(.horizontal, 8)
                        .padding(.top, index == 0 ? 0 : 14)
                        .padding(.bottom, 4)
                    ForEach(group.sections) { section in
                        row(section)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 18)

            Spacer()

            if let disk = startupDisk {
                diskCard(disk)
                    .padding(.horizontal, 12)
            }

            UpdateButton(model: updates)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            HStack(spacing: 2) {
                Text("v\(updates.currentVersion) · offline")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.text2)
                    .help("Dustpan only goes online when you check for updates.")
                Spacer()
                SidebarIconButton(glyph: .settings, help: "Settings (⌘,)") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                SidebarIconButton(glyph: .appearance, help: "Toggle appearance") {
                    settings.toggleAppearance(current: scheme)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(width: 236)
        .background(palette.sidebar)
    }

    private func row(_ section: SidebarSection) -> some View {
        let isSelected = section == selection
        return Button {
            selection = section
        } label: {
            HStack(spacing: 10) {
                TintTile(section.glyph, tint: section.tint, size: 22, glyphSize: 13, radius: 6)
                Text(section.rawValue)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let pill = pills[section] {
                    Text(pill)
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.white : palette.text2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(isSelected ? palette.accent : palette.text.opacity(0.06), in: Capsule())
                }
            }
            .padding(.leading, 7)
            .padding(.trailing, 6)
            .frame(height: 32)
            .background(isSelected ? palette.text.opacity(palette.isDark ? 0.09 : 0.065) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .hoverFill(isSelected ? .clear : palette.rowHover, cornerRadius: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(section.shortcut, modifiers: .command)
    }

    /// Startup disk usage, with the part Cleanup found shown separately.
    private func diskCard(_ disk: MountedVolume) -> some View {
        let total = Double(max(disk.totalBytes, 1))
        let cleanable = min(cleanableBytes, disk.usedBytes)
        let used = disk.usedBytes - cleanable
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(disk.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Spacer()
                Text("\(disk.usedBytes.formattedBytes) / \(disk.totalBytes.formattedBytes)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(palette.text2)
            }
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2).fill(Tint.lilac)
                        .frame(width: max(proxy.size.width * Double(used) / total - 2, 0))
                    if cleanable > 0 {
                        RoundedRectangle(cornerRadius: 2).fill(Tint.browser)
                            .frame(width: max(proxy.size.width * Double(cleanable) / total, 3))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 7)
            .background(palette.hair, in: RoundedRectangle(cornerRadius: 4))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.top, 9)
            HStack(spacing: 10) {
                legend("Used", Tint.lilac)
                if cleanable > 0 { legend("Cleanable", Tint.browser) }
                legend("\(disk.availableBytes.formattedBytes) free", palette.hair)
            }
            .padding(.top, 8)
        }
        .padding(12)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
        .help("Startup disk. The orange part is what Cleanup found that can be cleaned.")
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 10.5)).foregroundStyle(palette.text2).lineLimit(1)
        }
    }
}

private struct SidebarIconButton: View {
    let glyph: Glyph
    let help: String
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            GlyphView(glyph, size: 14)
                .frame(width: 22, height: 22)
                .hoverFill(palette.rowHover, cornerRadius: 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.text2)
        .help(help)
    }
}

/// Shared 52 pt toolbar from the design.
struct DetailToolbar<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold)).tracking(-0.15).fixedSize(horizontal: true, vertical: false)
            Text(subtitle).font(.system(size: 12.5)).foregroundStyle(palette.text2).lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.leading, 22)
        .padding(.trailing, 18)
        .frame(height: 56)
        .background { ZStack { palette.bar; WindowDragArea() } }
        .overlay(alignment: .bottom) { Rectangle().fill(palette.hair).frame(height: 0.5) }
    }
}

struct ComingSoonView: View {
    let title: String
    let subtitle: String
    let glyph: Glyph
    let message: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            DetailToolbar(title: title, subtitle: subtitle) { EmptyView() }
            VStack(spacing: 6) {
                GlyphView(glyph, size: 34, lineWidth: 1.1)
                    .foregroundStyle(palette.accent)
                    .frame(width: 72, height: 72)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.bottom, 10)
                Text("Coming soon").font(.system(size: 17, weight: .semibold))
                Text(message)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(palette.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            .padding(.horizontal, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

import AppKit
import DustpanCore
import DustpanDesign
import SwiftUI

@MainActor
struct UninstallerView: View {
    @Bindable var model: UninstallerModel
    @Environment(\.palette) private var palette
    @State private var isConfirming = false

    var body: some View {
        VStack(spacing: 0) {
            DetailToolbar(title: "Uninstaller", subtitle: model.isLoadingApps ? "loading…" : "\(model.apps.count) applications") {
                NavButton(title: "Refresh", glyph: .rescan) { model.reloadApps() }
                .keyboardShortcut("r")
                .disabled(model.isLoadingApps || model.deletionProgress != nil)
            }

            HStack(spacing: 0) {
                appList
                    .frame(width: 268)
                Rectangle().fill(palette.hair).frame(width: 0.5)
                detail
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear { model.loadAppsIfNeeded() }
        .overlay { overlays }
        .animation(.easeOut(duration: 0.15), value: isConfirming)
        .animation(.easeOut(duration: 0.15), value: model.deletionProgress != nil)
    }

    // MARK: App list

    private var appList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                GlyphView(.search, size: 12).opacity(0.4)
                TextField("Search applications", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(palette.field, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.btnBorder.opacity(0.9), lineWidth: 0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if model.isLoadingApps && model.apps.isEmpty {
                Spinner().frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.filteredApps) { app in
                            AppRow(
                                app: app,
                                icon: model.icon(for: app),
                                meta: meta(for: app),
                                isSelected: model.selectedApp == app
                            )
                            .onTapGesture { model.select(app) }
                            .contextMenu {
                                Button("Reveal in Finder") { model.reveal(app.url) }
                            }
                        }
                        if model.filteredApps.isEmpty {
                            Text("No matching apps")
                                .font(.system(size: 12.5))
                                .foregroundStyle(palette.text2)
                                .padding(.top, 20)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private func meta(for app: InstalledApp) -> String {
        let size = model.appSizes[app.url].map(\.formattedBytes) ?? "…"
        return [app.version, size].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(nsImage: model.icon(for: app))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.system(size: 20, weight: .bold)).tracking(-0.3)
                        Text([app.bundleIdentifier ?? "no bundle identifier", app.version].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.text2)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)

                Text(model.isLoadingLeftovers
                     ? "Looking for files that belong to this app…"
                     : "Found \(model.leftovers.count) \(model.leftovers.count == 1 ? "item" : "items") belonging to this app, \(model.totalBytes.formattedBytes) total.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.text2)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)

                notices(for: app)

                ScrollView {
                    if model.isLoadingLeftovers {
                        Spinner().padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(model.leftovers) { leftover in
                                LeftoverRow(
                                    leftover: leftover,
                                    display: display(leftover.url.path),
                                    isChecked: model.checked.contains(leftover.url),
                                    isLocked: app.isSystemApp
                                )
                                .onTapGesture { if !app.isSystemApp { model.toggle(leftover) } }
                                .help(leftover.url.path)
                                .contextMenu {
                                    Button("Reveal in Finder") { model.reveal(leftover.url) }
                                    Button("Copy Path") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(leftover.url.path, forType: .string)
                                    }
                                }
                            }
                        }
                        .cardStyle(palette)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                    }
                }

                footer(for: app)
            }
        } else {
            VStack(spacing: 6) {
                TintTile(.navUninstaller, tint: Tint.purple, size: 92, glyphSize: 44, radius: 24)
                    .padding(.bottom, 14)
                Text("Select an app").font(.system(size: 24, weight: .bold)).tracking(-0.4)
                Text("Dustpan lists the app together with its preferences, caches, containers and logs.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func notices(for app: InstalledApp) -> some View {
        VStack(spacing: 8) {
            if let outcome = model.lastOutcome {
                OutcomeBanner(outcome: outcome) { model.lastOutcome = nil }
            }
            if app.isSystemApp {
                Notice(glyph: .lock, text: "\(app.name) is part of macOS and can't be removed. Its files are shown for information only.")
            } else if model.isRunning(app) {
                Notice(glyph: .warning, text: "\(app.name) is running. Quit it before uninstalling.") {
                    Button("Quit \(app.name)") { model.quit(app) }
                        .buttonStyle(DPButtonStyle(.secondary, height: 22, horizontalPadding: 9, fontSize: 11.5))
                }
            }
            if model.leftovers.contains(where: \.matchedByName), !app.isSystemApp {
                Notice(glyph: .warning, text: "Items marked \"matched by name\" aren't selected. Check they belong to \(app.name) before ticking them.")
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private func footer(for app: InstalledApp) -> some View {
        let selected = model.checkedLeftovers
        let blocked = app.isSystemApp || model.isRunning(app)
        return HStack(spacing: 12) {
            Text("\(selected.count) of \(model.leftovers.count) items selected · \(model.checkedBytes.formattedBytes)")
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(palette.text2)
            if !selected.contains(where: \.isApplication), !selected.isEmpty {
                Text("App bundle not selected: only leftovers will be removed")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.warnInk)
            }
            Spacer()
            Button { isConfirming = true } label: {
                HStack(spacing: 8) {
                    GlyphView(.trash, size: 15, lineWidth: 1.5)
                    Text("Uninstall…")
                }
            }
            .buttonStyle(DPButtonStyle(.destructive, height: 40, horizontalPadding: 16, fontSize: 13.5))
                .disabled(selected.isEmpty || blocked || model.isLoadingLeftovers || model.deletionProgress != nil)
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .frame(height: 64)
        .background(palette.bar)
        .overlay(alignment: .top) { Rectangle().fill(palette.hair).frame(height: 0.5) }
    }

    private func display(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlays: some View {
        if isConfirming, let app = model.selectedApp {
            TrashConfirmationSheet(
                title: "Uninstall \(app.name)?",
                targets: model.checkedLeftovers.map(\.target),
                onCancel: { isConfirming = false },
                onConfirm: {
                    isConfirming = false
                    Task { await model.uninstall() }
                }
            )
        } else if let progress = model.deletionProgress {
            DeletionProgressOverlay(progress: progress)
        }
    }
}

// MARK: - Rows

private struct AppRow: View {
    let app: InstalledApp
    let icon: NSImage
    let meta: String
    let isSelected: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(meta)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .opacity(0.72)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if app.isSystemApp {
                GlyphView(.lock, size: 11).opacity(0.5)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .foregroundStyle(isSelected ? Color.white : palette.text)
        .background(isSelected ? palette.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
        .hoverFill(isSelected ? .clear : palette.rowHover, cornerRadius: 7)
        .contentShape(Rectangle())
    }
}

private struct LeftoverRow: View {
    let leftover: AppLeftover
    let display: String
    let isChecked: Bool
    let isLocked: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isLocked {
                    GlyphView(.lock, size: 12).opacity(0.45)
                } else {
                    DPCheckbox(isChecked ? .on : .off)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(leftover.kind).font(.system(size: 12.5))
                    if leftover.matchedByName {
                        Text("matched by name")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Palette.warnInk)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Palette.warnInk.opacity(0.12), in: Capsule())
                    }
                }
                Text(display)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(leftover.sizeBytes.formattedBytes)
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(palette.text2)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
        .contentShape(Rectangle())
        .hoverFill(palette.rowHover)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.hair.opacity(0.7)).frame(height: 0.5) }
    }
}

private struct Notice<Accessory: View>: View {
    let glyph: Glyph
    let text: String
    @ViewBuilder let accessory: Accessory
    @Environment(\.palette) private var palette

    init(glyph: Glyph, text: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.glyph = glyph
        self.text = text
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 8) {
            GlyphView(glyph, size: 13).foregroundStyle(Palette.warnInk)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            accessory
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.warnBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.warnBorder, lineWidth: 0.5))
    }
}

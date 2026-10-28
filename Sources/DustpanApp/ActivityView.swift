import AppKit
import DustpanCore
import DustpanDesign
import SwiftUI

/// Everything running on the Mac, what each process is, and whether anything about it looks off.
@MainActor
struct ActivityView: View {
    @Bindable var model: ActivityModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            DetailToolbar(title: "Activity", subtitle: subtitle) {
                HStack(spacing: 6) {
                    GlyphView(.search, size: 12).opacity(0.4)
                    TextField("Search processes", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                }
                .padding(.horizontal, 10)
                .frame(width: 210, height: 30)
                .background(palette.field, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.btnBorder.opacity(0.9), lineWidth: 0.5))
            }

            // The details pane gives up width first, so the list stays readable in a small window.
            GeometryReader { proxy in
                let detailWidth = min(340, max(260, proxy.size.width * 0.4))
                HStack(spacing: 0) {
                    list(compact: proxy.size.width - detailWidth < 480)
                        .frame(maxWidth: .infinity)
                    Rectangle().fill(palette.hair).frame(width: 0.5)
                    detail
                        .frame(width: detailWidth)
                }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .overlay { if let row = model.pendingStop { StopConfirmation(row: row, model: model) } }
        .animation(Motion.hover, value: model.pendingStop?.id)
    }

    private var subtitle: String {
        guard model.isLoaded else { return "loading…" }
        return "\(model.rows.count) processes · \(Int(model.totalCPU.rounded()))% CPU · \(model.totalMemory.compactBytes) memory"
    }

    // MARK: List

    /// `compact` swaps the warning badge text for an icon when the list is narrow.
    private func list(compact: Bool) -> some View {
        VStack(spacing: 0) {
            // The segmented filter when there's room, a dropdown when the window is narrow.
            ViewThatFits(in: .horizontal) {
                ModePicker(modes: [
                    (ActivityFilter.all, "All", Glyph.list),
                    (.apps, "Apps", .apps),
                    (.background, "Background", .gear),
                    (.flagged, flaggedTitle, .warning),
                ], selection: $model.filter)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)

                Picker("Show", selection: $model.filter) {
                    ForEach(ActivityFilter.allCases, id: \.self) { filter in
                        Text(filter == .flagged ? flaggedTitle : filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            header
                .padding(.horizontal, 18)

            if !model.isLoaded {
                Spinner().frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.visibleRows) { row in
                            ProcessRow(row: row, icon: model.icon(for: row), isSelected: model.selectedPID == row.id, compact: compact)
                                .onTapGesture { model.selectedPID = row.id }
                                .contextMenu { menu(for: row) }
                        }
                        if model.visibleRows.isEmpty {
                            Text(model.filter == .flagged && model.query.isEmpty ? "Nothing running has any warning signs." : "No matching processes")
                                .font(.system(size: 12.5))
                                .foregroundStyle(palette.text2)
                                .padding(.vertical, 28)
                        }
                    }
                    .cardStyle(palette)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
            }
        }
    }

    private var flaggedTitle: String {
        model.flaggedCount > 0 ? "Needs a Look · \(model.flaggedCount)" : "Needs a Look"
    }

    private var header: some View {
        HStack(spacing: 10) {
            sortButton("Process", .name).frame(maxWidth: .infinity, alignment: .leading)
            sortButton("CPU", .cpu).frame(width: 50, alignment: .trailing)
            sortButton("Memory", .memory).frame(width: 70, alignment: .trailing)
        }
        .padding(.leading, 44)
        .padding(.trailing, 12)
        .frame(height: 26)
    }

    private func sortButton(_ title: String, _ sort: ActivitySort) -> some View {
        Button { model.sort = sort } label: {
            HStack(spacing: 3) {
                Text(title.uppercased())
                if model.sort == sort { GlyphView(.chevron, size: 7).rotationEffect(.degrees(sort == .name ? -90 : 90)) }
            }
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.5)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(model.sort == sort ? palette.text : palette.text2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func menu(for row: ActivityRow) -> some View {
        if let path = row.process.path {
            Button("Reveal in Finder") { model.reveal(row.process.appBundlePath ?? path) }
        }
        if let item = row.launchItem {
            Button("Reveal Launch Item") { model.reveal(item.plist.path) }
        }
        Divider()
        Button("Quit…") { model.requestStop(row) }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let row = model.selected {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(nsImage: model.icon(for: row))
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .font(.system(size: 18, weight: .bold))
                                    .tracking(-0.3)
                                    .lineLimit(2)
                                Text(row.subtitle).font(.system(size: 12)).foregroundStyle(palette.text2)
                            }
                        }

                        if let message = model.message {
                            MessageBanner(text: message.text, isError: message.isError) { model.dismissMessage() }
                        }

                        VerdictCard(assessment: row.assessment)

                        section("What it is") {
                            Text(description(of: row))
                                .font(.system(size: 12.5))
                                .lineSpacing(2)
                                .foregroundStyle(palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        section("Details") {
                            VStack(spacing: 0) {
                                fact("Process ID", "\(row.process.pid)")
                                fact("Runs as", row.process.uid == getuid() ? "You (\(row.process.userName))" : row.process.userName)
                                if let started = row.process.started {
                                    fact("Started", started.formatted(.relative(presentation: .named)))
                                }
                                fact("CPU", row.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "Not available")
                                fact("Memory", row.process.memoryBytes.map(\.formattedBytes) ?? "Not available")
                                fact("Signed by", signedBy(row.signer))
                                if case .developerID(_, let team?, _) = row.signer { fact("Team ID", team) }
                                if let item = row.launchItem {
                                    fact("Starts", "Automatically \(item.startsWhen)\(item.keepsAlive ? ", restarts if quit" : "")")
                                }
                                fact("Program", row.process.path.map(display) ?? "Hidden by macOS", monospaced: true, last: true)
                            }
                            .cardStyle(palette, radius: 10)
                        }

                        Text("Dustpan looks for common warning signs. It can't prove a program is safe or harmful, so if something looks off, find out what it is before stopping it.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                }
                footer(for: row)
            }
            .background(palette.bg)
            .animation(Motion.hover, value: model.message?.text)
        } else {
            VStack(spacing: 6) {
                TintTile(.navActivity, tint: Tint.pink, size: 72, glyphSize: 34, radius: 19)
                    .padding(.bottom, 12)
                Text("Select a process").font(.system(size: 20, weight: .bold)).tracking(-0.3)
                Text("See what it is, who made it, whether it starts by itself, and any warning signs.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(palette.text2)
            content()
        }
    }

    private func fact(_ label: String, _ value: String, monospaced: Bool = false, last: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(palette.text2)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(size: 11, design: .monospaced) : .system(size: 12))
                .foregroundStyle(palette.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(palette.hair.opacity(0.7)).frame(height: 0.5) } }
    }

    private func footer(for row: ActivityRow) -> some View {
        HStack(spacing: 8) {
            if let path = row.process.path {
                Button("Reveal") { model.reveal(row.process.appBundlePath ?? path) }
                    .buttonStyle(DPButtonStyle(.secondary, height: 32, horizontalPadding: 12, fontSize: 12.5))
                    .help("Reveal the program in Finder")
            }
            if let item = row.launchItem {
                Button("Launch Item") { model.reveal(item.plist.path) }
                    .buttonStyle(DPButtonStyle(.secondary, height: 32, horizontalPadding: 12, fontSize: 12.5))
                    .help("Reveal \(item.plist.lastPathComponent), the file that starts it automatically")
            }
            Spacer(minLength: 0)
            Button("Quit…") { model.requestStop(row) }
                .buttonStyle(DPButtonStyle(.destructive, height: 32, horizontalPadding: 14, fontSize: 12.5))
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .background(palette.bar)
        .overlay(alignment: .top) { Rectangle().fill(palette.hair).frame(height: 0.5) }
    }

    private func signedBy(_ signer: CodeSigner?) -> String {
        switch signer {
        case nil: "Checking…"
        case .apple: "Apple"
        case .appStore(let organization): "\(organization ?? "Unknown developer") (Mac App Store)"
        case .developerID(let organization, _, let notarized): "\(organization ?? "Unknown developer")\(notarized ? ", notarized by Apple" : ", not notarized")"
        case .untrustedCertificate(let name): "\"\(name ?? "Unknown")\", a certificate Apple didn't issue"
        case .adHoc: "Nobody (ad-hoc signature)"
        case .unsigned: "Nobody (unsigned)"
        case .invalid: "Broken signature"
        case .unknown: "Couldn't check"
        }
    }

    private func description(of row: ActivityRow) -> String {
        if let known = ProcessGuide.description(for: row.process.displayName) ?? ProcessGuide.description(for: row.name) { return known }
        if row.isApp { return "The \(row.name) app." }
        if row.subtitle.hasPrefix("Part of ") {
            return "A helper that \(row.subtitle.dropFirst("Part of ".count)) runs in the background. It quits when the app does."
        }
        if let item = row.launchItem {
            return "A background program that starts automatically \(item.startsWhen) (\(item.label))."
        }
        if row.subtitle == "macOS" { return "A part of macOS that provides a system feature in the background. Best left running." }
        if row.subtitle == "Homebrew" { return "A command-line tool installed with Homebrew." }
        return "A background program. If you don't recognise it, check who signed it and where it lives below."
    }

    private func display(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: - Row

private struct ProcessRow: View {
    let row: ActivityRow
    let icon: NSImage
    let isSelected: Bool
    let compact: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(.system(size: 13)).lineLimit(1)
                Text(row.subtitle).font(.system(size: 11)).foregroundStyle(palette.text2).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let level = row.level, level >= .caution {
                if compact {
                    GlyphView(.warning, size: 13)
                        .foregroundStyle(level == .suspicious ? Palette.danger : Palette.warnInk)
                        .help(level.title)
                } else {
                    LevelBadge(level: level)
                }
            }
            Text(row.cpuPercent.map { $0 < 0.05 ? "0" : String(format: "%.1f", $0) } ?? "–")
                .frame(width: 50, alignment: .trailing)
            Text(row.process.memoryBytes.map(\.compactBytes) ?? "–")
                .frame(width: 70, alignment: .trailing)
        }
        .font(.system(size: 12.5))
        .monospacedDigit()
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background { if isSelected { palette.accent.opacity(0.13) } }
        .hoverFill(isSelected ? .clear : palette.rowHover)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.hair.opacity(0.7)).frame(height: 0.5) }
        .contentShape(Rectangle())
    }
}

private struct LevelBadge: View {
    let level: TrustLevel

    var body: some View {
        let color = level == .suspicious ? Palette.danger : Palette.warnInk
        Text(level.title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.13), in: Capsule())
    }
}

// MARK: - Verdict

private struct VerdictCard: View {
    let assessment: ProcessAssessment?
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if assessment == nil {
                    ProgressView().controlSize(.small)
                } else {
                    GlyphView(glyph, size: 15).foregroundStyle(ink)
                }
                Text(assessment?.level.title ?? "Checking signature…").font(.system(size: 13.5, weight: .semibold))
            }
            if let assessment {
                Text(assessment.summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(assessment.signs, id: \.title) { sign in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sign.title).font(.system(size: 12.5, weight: .semibold))
                        Text(sign.detail)
                            .font(.system(size: 12))
                            .lineSpacing(1.5)
                            .foregroundStyle(palette.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(ink.opacity(0.5)).frame(width: 2) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border, lineWidth: 0.5))
    }

    private var level: TrustLevel { assessment?.level ?? .unverified }

    private var glyph: Glyph {
        switch level {
        case .trusted: .okCircle
        case .unverified: .lock
        case .caution, .suspicious: .warning
        }
    }

    private var ink: Color {
        switch level {
        case .trusted: Palette.okInk
        case .unverified: palette.text2
        case .caution: Palette.warnInk
        case .suspicious: Palette.danger
        }
    }

    private var background: Color {
        switch level {
        case .trusted: palette.okBg
        case .unverified: palette.panel
        case .caution: palette.warnBg
        case .suspicious: Palette.danger.opacity(0.08)
        }
    }

    private var border: Color {
        switch level {
        case .trusted: palette.okBorder
        case .unverified: palette.hair
        case .caution: palette.warnBorder
        case .suspicious: Palette.danger.opacity(0.35)
        }
    }
}

private struct MessageBanner: View {
    let text: String
    let isError: Bool
    let onDismiss: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            GlyphView(isError ? .warning : .okCircle, size: 14)
                .foregroundStyle(isError ? Palette.warnInk : Palette.okInk)
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                GlyphView(.close, size: 9)
                    .frame(width: 16, height: 16)
                    .hoverFill(.black.opacity(0.06), cornerRadius: 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.text2)
        }
        .padding(10)
        .background(isError ? palette.warnBg : palette.okBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isError ? palette.warnBorder : palette.okBorder, lineWidth: 0.5))
        .transition(.opacity)
    }
}

// MARK: - Confirmation

/// Says plainly what stopping a process will and won't do before anything happens.
private struct StopConfirmation: View {
    let row: ActivityRow
    let model: ActivityModel
    @Environment(\.palette) private var palette

    private var blocker: String? {
        if let reason = ProcessControl.protectionReason(for: row.process) { return reason }
        if row.process.uid != getuid() {
            return "\(row.name) runs as \(row.process.userName), so macOS doesn't let Dustpan stop it."
        }
        return nil
    }

    private var notes: [String] {
        var notes: [String] = []
        if row.isApp {
            notes.append("Quit asks \(row.name) to close, like quitting from the Dock, so it can offer to save. Force Quit ends it immediately and unsaved work is lost.")
        } else {
            notes.append("Quit asks it to finish up and exit. Force Quit ends it immediately.")
        }
        if let item = row.launchItem, item.keepsAlive {
            notes.append("It will start again straight away, because \(item.plist.lastPathComponent) keeps it running. To stop it for good, uninstall what it belongs to or remove that launch item.")
        }
        if row.subtitle == "macOS" {
            notes.append("This is part of macOS. It's usually restarted automatically, and some features may misbehave until it is.")
        }
        return notes
    }

    var body: some View {
        ModalBackdrop {
            VStack(alignment: .leading, spacing: 12) {
                Text(blocker == nil ? "Quit \(row.name)?" : "Dustpan can't stop \(row.name)")
                    .font(.system(size: 16, weight: .bold))
                ForEach(blocker.map { [$0] } ?? notes, id: \.self) { note in
                    Text(note)
                        .font(.system(size: 12.5))
                        .lineSpacing(2)
                        .foregroundStyle(palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Spacer()
                    Button(blocker == nil ? "Cancel" : "OK") { model.pendingStop = nil }
                        .buttonStyle(DPButtonStyle(.secondary, height: 32, horizontalPadding: 16, fontSize: 13))
                        .keyboardShortcut(.cancelAction)
                    if blocker == nil {
                        Button("Force Quit") { model.stop(row, force: true) }
                            .buttonStyle(DPButtonStyle(.destructive, height: 32, horizontalPadding: 16, fontSize: 13))
                        Button("Quit") { model.stop(row, force: false) }
                            .buttonStyle(DPButtonStyle(.primary, height: 32, horizontalPadding: 16, fontSize: 13))
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.top, 6)
            }
            .padding(22)
            .frame(width: 420)
            .background(palette.sheet, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 25, y: 20)
        }
    }
}

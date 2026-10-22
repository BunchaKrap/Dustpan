import AppKit
import DustpanCore
import DustpanDesign
import SwiftUI

@MainActor
struct HistoryView: View {
    @Bindable var model: HistoryModel
    @Environment(\.palette) private var palette
    @State private var logLines: [String]?

    var body: some View {
        VStack(spacing: 0) {
            DetailToolbar(title: "History", subtitle: model.sessions.isEmpty ? "" : "\(model.sessions.count) cleanups") {
                NavButton(title: "Open Trash", glyph: .trash) { model.openTrash() }
                NavButton(title: "Raw Log", glyph: .logDocument) { logLines = model.logLines() }
                NavButton(title: "Refresh", glyph: .rescan) { model.load() }
                    .keyboardShortcut("r")
                    .disabled(model.isLoading)
            }

            if model.isLoading && model.sessions.isEmpty {
                Spinner().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.sessions.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .onAppear { model.load() }
        .overlay {
            if let lines = logLines {
                DeletionLogWindow(lines: lines, onReveal: { model.revealLog() }, onClose: { logLines = nil })
            }
        }
        .animation(.easeOut(duration: 0.15), value: logLines != nil)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            TintTile(.navHistory, tint: Tint.grey, size: 92, glyphSize: 44, radius: 24)
                .padding(.bottom, 14)
            Text("Nothing cleaned yet").font(.system(size: 24, weight: .bold)).tracking(-0.4)
            Text("Everything Dustpan moves to the Trash shows up here, so you can see what was removed and put it back while it's still in the Trash.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(palette.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    StatCard(title: "Moved to Trash", value: model.totalBytes.formattedBytes, detail: "\(model.totalItems.formatted()) items in total")
                    StatCard(title: "This month", value: model.bytesThisMonth.formattedBytes, detail: Date().formatted(.dateTime.month(.wide).year()))
                    StatCard(title: "Can be put back", value: model.restorableCount.formatted(), detail: "items still in the Trash")
                }

                if let message = model.message {
                    HStack(spacing: 8) {
                        GlyphView(message.isError ? .warning : .okCircle, size: 14)
                            .foregroundStyle(message.isError ? Palette.warnInk : Palette.okInk)
                        Text(message.text).font(.system(size: 12.5))
                        Spacer()
                        Button { model.message = nil } label: { GlyphView(.close, size: 10) }
                            .buttonStyle(.plain)
                            .foregroundStyle(palette.text2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(message.isError ? palette.warnBg : palette.okBg, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(message.isError ? palette.warnBorder : palette.okBorder, lineWidth: 0.5))
                }

                if model.sources.count > 1 {
                    HStack(spacing: 6) {
                        filterChip("All", isSelected: model.sourceFilter == nil) { model.sourceFilter = nil }
                        ForEach(model.sources, id: \.self) { source in
                            filterChip(source, isSelected: model.sourceFilter == source) { model.sourceFilter = source }
                        }
                        Spacer()
                    }
                }

                LazyVStack(spacing: 10) {
                    ForEach(model.filteredSessions) { session in
                        SessionCard(model: model, session: session)
                    }
                }

                Text("Items in the Trash can be put back to their original location. Once the Trash is emptied they're gone for good.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
        }
    }

    private func filterChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? palette.accent : palette.text2)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(isSelected ? palette.accent.opacity(0.14) : palette.chip, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let detail: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(palette.text2)
            Text(value).font(.system(size: 28, weight: .bold)).tracking(-0.8).monospacedDigit()
            Text(detail).font(.system(size: 11.5)).foregroundStyle(palette.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardStyle(palette)
    }
}

@MainActor
private struct SessionCard: View {
    let model: HistoryModel
    let session: DeletionSession
    @Environment(\.palette) private var palette

    private var isExpanded: Bool { model.expanded.contains(session.id) }
    private var restorable: Int { session.trashed.filter { model.states[$0.id] == .inTrash }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TintTile(glyph, tint: tint, size: 34, glyphSize: 17, radius: 9)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 13.5, weight: .medium))
                        Text(session.date.formatted(.relative(presentation: .named)))
                            .font(.system(size: 12))
                            .foregroundStyle(palette.text2)
                    }
                    Text(summary).font(.system(size: 12)).foregroundStyle(palette.text2)
                }
                Spacer(minLength: 8)
                Text(session.bytesMoved.formattedBytes)
                    .font(.system(size: 13.5, weight: .medium))
                    .monospacedDigit()
                ExpandChevron(isExpanded: isExpanded)
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(height: 58)
            .contentShape(Rectangle())
            .onTapGesture { model.toggle(session) }

            if isExpanded {
                Rectangle().fill(palette.hair).frame(height: 0.5)
                ForEach(session.records) { record in
                    HistoryRow(record: record, state: model.states[record.id] ?? .emptied,
                               onPutBack: { model.putBack(record) }, onReveal: { model.reveal(record) })
                }
                if restorable > 1 {
                    HStack {
                        Spacer()
                        NavButton(title: "Put Back All \(restorable)", glyph: .restore, height: 28) { model.putBackAll(in: session) }
                    }
                    .padding(10)
                }
            }
        }
        .cardStyle(palette)
    }

    private var tint: Color {
        SidebarSection(rawValue: session.source ?? "")?.tint ?? Tint.stone
    }

    private var glyph: Glyph {
        switch session.source {
        case "Cleanup": .navCleanup
        case "Disk Space": .navDisk
        case "Duplicates": .navDuplicates
        case "Uninstaller": .navUninstaller
        default: .trash
        }
    }

    private var summary: String {
        var parts = ["\(session.source ?? "Dustpan")", "\(session.trashed.count) \(session.trashed.count == 1 ? "item" : "items") moved to Trash"]
        if !session.problems.isEmpty { parts.append("\(session.problems.count) not removed") }
        if restorable > 0 { parts.append("\(restorable) can be put back") }
        return parts.joined(separator: " · ")
    }
}

private struct HistoryRow: View {
    let record: DeletionRecord
    let state: HistoryModel.ItemState
    let onPutBack: () -> Void
    let onReveal: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(record.name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                Text(ScanPlaces.display((record.path as NSString).deletingLastPathComponent))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.text2)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            badge
            Text(record.sizeBytes.formattedBytes)
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(palette.text2)
                .frame(width: 72, alignment: .trailing)
            if state == .inTrash {
                Button("Put Back", action: onPutBack)
                    .buttonStyle(DPButtonStyle(.secondary, height: 26, horizontalPadding: 10, fontSize: 12))
            } else {
                Color.clear.frame(width: 74, height: 1)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .hoverFill(palette.rowHover)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.hair.opacity(0.7)).frame(height: 0.5) }
        .help(record.detail.isEmpty ? record.path : "\(record.path)\n\(record.detail)")
        .contextMenu {
            Button("Reveal in Finder", action: onReveal).disabled(state == .emptied || state == .failed || state == .refused)
            Button("Copy Original Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.path, forType: .string)
            }
        }
    }

    private var badge: some View {
        let (text, color): (String, Color) = switch state {
        case .inTrash: ("In Trash", palette.accent)
        case .emptied: ("Trash emptied", palette.text2)
        case .restored: ("Put back", Palette.okInk)
        case .failed: ("Failed", Palette.danger)
        case .refused: ("Blocked", Palette.warnInk)
        }
        return Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

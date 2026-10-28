import DustpanCore
import DustpanDesign
import SwiftUI

// Overlays shared by Cleanup now and by the Uninstaller later. Styled after the design file.

/// Runs a confirmed deletion, reporting progress until it finishes.
@MainActor
func performDeletion(_ targets: [DeletionTarget], policy: SafetyPolicy, source: String,
                     progress: @escaping (DeletionProgress?) -> Void) async -> DeletionOutcome {
    final class Finished: @unchecked Sendable { var value = false }
    let finished = Finished()
    progress(DeletionProgress(completed: 0, total: targets.count))
    let outcome = await Deleter(policy: policy, source: source).delete(targets) { completed, total in
        Task { @MainActor in
            // Late updates must not resurrect the overlay after completion.
            if !finished.value { progress(DeletionProgress(completed: completed, total: total)) }
        }
    }
    finished.value = true
    progress(nil)
    return outcome
}

/// Dimmed backdrop that hosts a card.
struct ModalBackdrop<Content: View>: View {
    var dim: Double = 0.18
    var alignment: Alignment = .center
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: alignment) {
            Color.black.opacity(dim)
                .contentShape(Rectangle())
                .onTapGesture {} // swallow clicks behind the card
            content
        }
        .transition(.opacity)
    }
}

/// The explicit confirmation step: lists every path before anything is touched.
struct TrashConfirmationSheet: View {
    let title: String
    let targets: [DeletionTarget]
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @Environment(\.palette) private var palette

    private var totalBytes: Int64 { targets.reduce(0) { $0 + $1.sizeBytes } }

    var body: some View {
        ModalBackdrop(alignment: .top) {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text("These \(targets.count) items (\(totalBytes.formattedBytes)) will be moved to the Trash. Nothing is deleted permanently, so you can put them back.")
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .foregroundStyle(palette.text2)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 12)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(targets.sorted { $0.sizeBytes > $1.sizeBytes }, id: \.url) { target in
                            HStack(spacing: 10) {
                                Text(target.url.path)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                Text(target.sizeBytes.formattedBytes)
                                    .font(.system(size: 12))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.text2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(minHeight: 34)
                            .overlay(alignment: .bottom) { Rectangle().fill(palette.hair.opacity(0.6)).frame(height: 0.5) }
                        }
                    }
                }
                .background(palette.field, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.hair, lineWidth: 0.5))
                .padding(.horizontal, 24)

                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(DPButtonStyle(.secondary, height: 28, horizontalPadding: 16, fontSize: 13, focusRing: true))
                        .keyboardShortcut(.cancelAction)
                    Button("Move \(targets.count) Items to Trash", action: onConfirm)
                        .buttonStyle(DPButtonStyle(.destructive, height: 28, horizontalPadding: 16, fontSize: 13))
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 18)
            }
            .frame(width: 620, height: 480)
            .background(palette.sheet, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 25, y: 20)
            .padding(.top, 78)
        }
    }
}

struct DeletionProgressOverlay: View {
    let progress: DeletionProgress
    @Environment(\.palette) private var palette

    var body: some View {
        ModalBackdrop(dim: 0.24) {
            VStack(spacing: 0) {
                Text("Moving to Trash…").font(.system(size: 13.5, weight: .medium))
                ProgressBar(fraction: Double(progress.completed) / Double(max(progress.total, 1)))
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                Text("\(progress.completed) of \(progress.total)")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(palette.text2)
            }
            .padding(22)
            .frame(width: 300)
            .background(palette.sheet, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.32), radius: 22, y: 18)
        }
    }
}

struct DeletionLogWindow: View {
    let lines: [String]
    let onReveal: () -> Void
    let onClose: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        ModalBackdrop {
            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) {
                        Circle().fill(Color(hex: 0xFF5F57)).frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    Text("deletions.log").font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Color.clear.frame(width: 12, height: 12)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.hair).frame(height: 0.5) }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if lines.isEmpty {
                            Text("Nothing has been removed yet.")
                                .foregroundStyle(palette.text2)
                        }
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .foregroundStyle(lineColor(line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 3)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .background(palette.field)

                HStack {
                    Text(DeletionLog.default.fileURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.text2)
                    Spacer()
                    Button("Reveal in Finder", action: onReveal)
                        .buttonStyle(DPButtonStyle(.secondary, height: 22, horizontalPadding: 9, fontSize: 11.5))
                }
                .padding(.horizontal, 14)
                .frame(height: 38)
                .overlay(alignment: .top) { Rectangle().fill(palette.hair).frame(height: 0.5) }
            }
            .frame(width: 660, height: 400)
            .background(palette.sheet, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 25, y: 20)
        }
    }

    private func lineColor(_ line: String) -> Color {
        if line.contains("  FAILED  ") { return Palette.danger }
        if line.contains("  REFUSED  ") { return Palette.warnInk }
        return palette.text
    }
}

struct OutcomeBanner: View {
    let outcome: DeletionOutcome
    let onDismiss: () -> Void
    @Environment(\.palette) private var palette
    @State private var showsDetails = false

    private var succeeded: Bool { outcome.failures.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            GlyphView(succeeded ? .okCircle : .warning, size: 16)
                .foregroundStyle(succeeded ? Palette.okInk : Palette.warnInk)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Moved \(outcome.removed.count) items (\(outcome.bytesFreed.formattedBytes)) to the Trash."
                    + (succeeded ? "" : " \(outcome.failures.count) couldn't be removed."))
                    .font(.system(size: 13, weight: .medium))
                Text("Empty the Trash to actually free the space.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.text2)
                if !succeeded {
                    Button(showsDetails ? "Hide details" : "Show details") { showsDetails.toggle() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.accent)
                        .padding(.top, 4)
                    if showsDetails {
                        ForEach(outcome.failures, id: \.target.url) { failure in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(failure.target.url.path).font(.system(size: 11, design: .monospaced))
                                Text(failure.reason).font(.system(size: 11)).foregroundStyle(palette.text2)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                GlyphView(.close, size: 10)
                    .frame(width: 18, height: 18)
                    .hoverFill(.black.opacity(0.06), cornerRadius: 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.text2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(succeeded ? palette.okBg : palette.warnBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(succeeded ? palette.okBorder : palette.warnBorder, lineWidth: 0.5))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Explains a macOS privacy block in plain words and links to the System Settings pane that lifts it.
struct AccessNotice: View {
    let title: String
    let lines: [String]
    let areas: [ProtectedArea]
    var onDismiss: (() -> Void)?
    @Environment(\.palette) private var palette

    /// One button per settings pane, however many areas share it.
    private var panes: [ProtectedArea] {
        var seen = Set<String>()
        return areas.filter { seen.insert($0.settingsName).inserted }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            GlyphView(.lock, size: 16)
                .foregroundStyle(Palette.warnInk)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12))
                        .lineSpacing(1.5)
                        .foregroundStyle(palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    ForEach(panes, id: \.self) { area in
                        Button("Open \(area.settingsName) Settings") { NSWorkspace.shared.open(area.settingsURL) }
                            .buttonStyle(DPButtonStyle(.secondary, height: 28, horizontalPadding: 11, fontSize: 12.5))
                    }
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button(action: onDismiss) {
                    GlyphView(.close, size: 10)
                        .frame(width: 18, height: 18)
                        .hoverFill(.black.opacity(0.06), cornerRadius: 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.text2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(palette.warnBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.warnBorder, lineWidth: 0.5))
        .transition(.opacity)
    }
}

extension JunkCategory {
    var glyph: Glyph {
        switch self {
        case .userCaches: .caches
        case .appCaches: .appCaches
        case .userLogs: .logs
        case .browserCaches: .browser
        case .xcode: .xcode
        case .homebrew: .brew
        case .packageManagers: .node
        case .devArtifacts: .devFolder
        case .installers: .installer
        case .docker: .docker
        case .systemJunk: .gear
        case .trash: .trash
        }
    }
}

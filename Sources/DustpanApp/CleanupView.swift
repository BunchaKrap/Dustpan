import AppKit
import DustpanCore
import DustpanDesign
import SwiftUI

@MainActor
struct CleanupView: View {
    @Bindable var model: CleanupModel
    @Environment(\.palette) private var palette
    @State private var isConfirming = false
    @State private var showsOptions = false
    @State private var logLines: [String]?

    private enum Phase { case empty, scanning, clean, results }

    private var phase: Phase {
        if model.isScanning { return .scanning }
        guard let report = model.report else { return .empty }
        return report.categories.isEmpty ? .clean : .results
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ScrollView {
                VStack(spacing: 0) {
                    if let outcome = model.lastOutcome {
                        OutcomeBanner(outcome: outcome) { withAnimation(.easeOut(duration: 0.2)) { model.lastOutcome = nil } }
                            .padding(.horizontal, 22)
                            .padding(.top, 16)
                    }
                    content
                }
                .frame(maxWidth: .infinity)
            }
            .scrollDisabled(phase != .results)
            if phase == .results {
                footer
            }
        }
        .overlay { overlays }
        .animation(.easeOut(duration: 0.15), value: isConfirming)
        .animation(.easeOut(duration: 0.15), value: model.deletionProgress != nil)
        .animation(.easeOut(duration: 0.15), value: logLines != nil)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        DetailToolbar(title: "Cleanup", subtitle: subtitle) {
            HStack(spacing: 0) {
                ForEach(ScanDepth.allCases, id: \.self) { depth in
                    SegmentButton(title: depth.displayName, isSelected: model.options.depth == depth) {
                        model.options.depth = depth
                    }
                    .help(depth.summary)
                }
            }
            .segmentedContainer(palette)
            .disabled(model.isBusy)

            Button {
                showsOptions.toggle()
            } label: {
                GlyphView(.sliders, size: 13, lineWidth: 1.4).frame(width: 14)
            }
            .buttonStyle(DPButtonStyle(.secondary, height: 30, horizontalPadding: 8))
            .help("Scan options")
            .disabled(model.isBusy)
            .popover(isPresented: $showsOptions, arrowEdge: .bottom) {
                ScanOptionsView(options: $model.options)
            }

            NavIconButton(glyph: .logDocument, help: "Deletion log") { logLines = model.deletionLogLines() }

            if phase == .results || phase == .clean {
                NavButton(title: "Rescan", glyph: .rescan) { model.scan() }
                    .keyboardShortcut("r")
                    .disabled(model.isBusy)
            }
        }
    }

    private var subtitle: String {
        let depth = model.options.depth.displayName.lowercased()
        switch phase {
        case .results: return "\(depth) scan · \(model.report?.categories.count ?? 0) categories"
        case .scanning: return "\(depth) scan"
        case .empty, .clean: return ""
        }
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .empty: emptyState
        case .scanning: scanningState
        case .clean: cleanState
        case .results: if let report = model.report { results(report) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            TintTile(.emptyPan, tint: Tint.orange, size: 92, glyphSize: 46, radius: 24)
                .padding(.bottom, 14)
            Text("Start a scan").font(.system(size: 24, weight: .bold)).tracking(-0.4)
            Text("Dustpan reads your home folder and reports what could be reclaimed. Nothing is selected, and nothing moves until you confirm it.")
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .foregroundStyle(palette.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            HeroButton(title: "Scan Home Folder") { model.scan() }
                .keyboardShortcut("r")
                .padding(.top, 20)

            Text("LOOKS IN")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1)
                .foregroundStyle(palette.text2)
                .padding(.top, 28)
            FlowRow(spacing: 8) {
                ForEach(JunkCategory.allCases.filter { model.options.includes($0) }, id: \.self) { category in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(category.tint).frame(width: 8, height: 8)
                        Text(category.displayName).font(.system(size: 12.5))
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 12)
                    .frame(height: 28)
                    .background(palette.btn, in: Capsule())
                    .overlay(Capsule().strokeBorder(palette.btnBorder.opacity(0.7), lineWidth: 0.5))
                }
            }
            .frame(maxWidth: 560)
            .padding(.top, 4)
            Text("\(model.options.depth.displayName) scan: \(model.options.depth.summary)")
                .font(.system(size: 12))
                .foregroundStyle(palette.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.top, 14)
        }
        .padding(.horizontal, 60)
        .frame(minHeight: 560)
    }

    private var scanningState: some View {
        VStack(spacing: 10) {
            ProgressRing(fraction: model.scanFraction)
                .padding(.bottom, 10)
            Text(model.options.depth == .deep ? "Scanning caches, logs and projects…" : "Scanning caches and logs…")
                .font(.system(size: 17, weight: .semibold))
            Text(model.scanStatus)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(palette.text2)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(palette.chip, in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 460)
            NavButton(title: "Stop", glyph: .close) { model.cancelScan() }
                .keyboardShortcut(.cancelAction)
                .padding(.top, 12)
        }
        .frame(minHeight: 560)
    }

    private var cleanState: some View {
        VStack(spacing: 6) {
            TintTile(.check, tint: Tint.green, size: 92, glyphSize: 44, radius: 24)
                .padding(.bottom, 14)
            Text("Nothing to clean").font(.system(size: 24, weight: .bold)).tracking(-0.4)
            Text("Everything Dustpan can reach is already tidy.")
                .font(.system(size: 13.5))
                .foregroundStyle(palette.text2)
        }
        .frame(minHeight: 560)
    }

    // MARK: Results

    private func results(_ report: JunkScanReport) -> some View {
        let segments = report.categories
            .map { ($0.category, $0.reclaimableBytes) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        let parts = report.reclaimableBytes.formattedBytes.split(separator: " ", maxSplits: 1).map(String.init)

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("READY TO CLEAN")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(palette.text2)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(parts.first ?? "")
                            .font(.system(size: 52, weight: .bold))
                            .tracking(-1.8)
                            .monospacedDigit()
                        Text(parts.count > 1 ? parts[1] : "")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(palette.text2)
                    }
                    Text("across \(segments.count) \(segments.count == 1 ? "category" : "categories") · scanned in \(String(format: "%.1f", report.duration)) s")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.text2)
                }
                .padding(.top, 2)

                if !segments.isEmpty {
                    GeometryReader { proxy in
                        let gaps = CGFloat(segments.count - 1) * 3
                        let total = Double(max(report.reclaimableBytes, 1))
                        HStack(spacing: 3) {
                            ForEach(segments, id: \.0) { category, bytes in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(category.tint)
                                    .frame(width: max((proxy.size.width - gaps) * Double(bytes) / total, 6))
                                    .help("\(category.displayName) · \(bytes.formattedBytes)")
                            }
                        }
                    }
                    .frame(height: 12)
                    .padding(.top, 16)

                    FlowRow(spacing: 16) {
                        ForEach(segments, id: \.0) { category, bytes in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 3).fill(category.tint).frame(width: 8, height: 8)
                                Text(category.displayName).foregroundStyle(palette.text2)
                                Text(bytes.formattedBytes).fontWeight(.semibold).monospacedDigit()
                            }
                            .font(.system(size: 12))
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 18)

            LazyVStack(spacing: 8) {
                ForEach(report.categories) { category in
                    CategoryCard(model: model, category: category)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 24)
    }

    // MARK: Footer

    private var footer: some View {
        let selected = model.selectedItems
        let allDeletable = model.report?.allItems.filter(\.isDeletable) ?? []
        let allOn = !allDeletable.isEmpty && selected.count == allDeletable.count

        return HStack(spacing: 14) {
            Button(allOn ? "Deselect All" : "Select All") {
                if allOn { model.selection.removeAll() } else { model.selectAllDeletable() }
            }
            .buttonStyle(DPButtonStyle(.secondary, height: 30, horizontalPadding: 12, fontSize: 12.5))

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(selected.isEmpty ? "Nothing selected" : model.selectedBytes.formattedBytes)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                Text(selected.isEmpty ? "Pick items to clean" : "\(selected.count) items selected")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.text2)
            }

            Button { isConfirming = true } label: {
                HStack(spacing: 8) {
                    GlyphView(.trash, size: 15, lineWidth: 1.5)
                    Text("Move to Trash…")
                }
            }
            .buttonStyle(DPButtonStyle(.destructive, height: 40, horizontalPadding: 16, fontSize: 13.5))
            .disabled(selected.isEmpty || model.isBusy)
        }
        .padding(.leading, 22)
        .padding(.trailing, 16)
        .frame(height: 64)
        .background(palette.bar)
        .overlay(alignment: .top) { Rectangle().fill(palette.hair).frame(height: 0.5) }
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlays: some View {
        if isConfirming {
            TrashConfirmationSheet(
                title: "Clean up selected junk?",
                targets: model.selectedItems.map(\.target),
                onCancel: { isConfirming = false },
                onConfirm: {
                    isConfirming = false
                    Task { await model.trashSelected() }
                }
            )
        } else if let progress = model.deletionProgress {
            DeletionProgressOverlay(progress: progress)
        } else if let lines = logLines {
            DeletionLogWindow(lines: lines, onReveal: { model.revealDeletionLog() }, onClose: { logLines = nil })
        }
    }
}

// MARK: - Cards & rows

@MainActor
private struct CategoryCard: View {
    let model: CleanupModel
    let category: CategoryResult
    @Environment(\.palette) private var palette

    private var isExpanded: Bool { model.expanded.contains(category.category) }
    private var hasDeletable: Bool { category.items.contains(where: \.isDeletable) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                DPCheckbox(model.checkState(for: category))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
                    .onTapGesture { if hasDeletable { model.toggle(category) } }
                    .opacity(hasDeletable ? 1 : 0.35)
                TintTile(category.category.glyph, tint: category.category.tint, size: 34, glyphSize: 17, radius: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.category.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(category.items.isEmpty ? "no items" : "\(category.items.count) \(category.items.count == 1 ? "item" : "items")")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.text2)
                }
                Spacer(minLength: 8)
                Text(category.reclaimableBytes.formattedBytes)
                    .font(.system(size: 13.5, weight: .semibold))
                    .monospacedDigit()
                ExpandChevron(isExpanded: isExpanded)
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .frame(height: 58)
            .contentShape(Rectangle())
            .hoverFill(palette.rowHover)
            .onTapGesture { model.expansion(for: category.category).wrappedValue.toggle() }

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(category.items) { item in
                        JunkItemRow(item: item, isSelected: model.isSelected(item),
                                    onToggle: { model.toggle(item) },
                                    onReveal: { model.reveal(item.url) })
                    }
                    ForEach(Array(category.issues.enumerated()), id: \.offset) { _, issue in
                        HStack(spacing: 8) {
                            GlyphView(.warning, size: 13).foregroundStyle(Palette.warnInk)
                            Text(issue.message).font(.system(size: 11.5)).foregroundStyle(palette.text2)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 66)
                        .padding(.trailing, 14)
                        .frame(minHeight: 32)
                        .help(issue.path)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 6)
                .overlay(alignment: .top) { Rectangle().fill(palette.hair).frame(height: 0.5) }
            }
        }
        .cardStyle(palette)
    }
}

private struct JunkItemRow: View {
    let item: JunkItem
    let isSelected: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if item.isDeletable {
                    DPCheckbox(isSelected ? .on : .off)
                } else {
                    GlyphView(.lock, size: 12).opacity(0.45)
                }
            }
            .frame(width: 22, height: 22)

            Text(item.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if let note = item.note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.text2)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 6))
            }
            Spacer(minLength: 8)
            Text(item.sizeBytes.formattedBytes)
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(palette.text2)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, 56)
        .padding(.trailing, 14)
        .frame(minHeight: 34)
        .contentShape(Rectangle())
        .hoverFill(palette.rowHover)
        .onTapGesture(perform: onToggle)
        .help(item.url.path)
        .contextMenu {
            Button("Reveal in Finder", action: onReveal)
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
            Divider()
            Text(item.url.path)
        }
    }
}

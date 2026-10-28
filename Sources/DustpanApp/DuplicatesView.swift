import AppKit
import DustpanCore
import DustpanDesign
import SwiftUI

@MainActor
struct DuplicatesView: View {
    @Bindable var model: DuplicatesModel
    @Environment(\.palette) private var palette
    @State private var isConfirming = false
    @State private var isDropTargeted = false

    private static let thresholds: [(label: String, bytes: Int64)] = [
        ("100 KB", 100_000), ("1 MB", 1_000_000), ("10 MB", 10_000_000), ("100 MB", 100_000_000),
    ]

    var body: some View {
        VStack(spacing: 0) {
            DetailToolbar(title: "Duplicates", subtitle: subtitle) {
                if model.report != nil, !model.isScanning {
                    NavButton(title: "Locations", glyph: .back) { model.startOver() }
                        .disabled(model.isBusy)
                    NavButton(title: "Rescan", glyph: .rescan) { model.scan() }
                        .keyboardShortcut("r")
                        .disabled(model.isBusy)
                }
            }

            if model.isScanning {
                scanningState
            } else if let report = model.report {
                results(report)
            } else {
                launcher
            }
        }
        .overlay { overlays }
        .animation(.easeOut(duration: 0.15), value: isConfirming)
        .animation(.easeOut(duration: 0.15), value: model.deletionProgress != nil)
    }

    private var subtitle: String {
        guard let root = model.rootURL, model.report != nil else { return "" }
        return ScanPlaces.display(root.path)
    }

    // MARK: Launcher

    private var launcher: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find duplicate files").font(.system(size: 24, weight: .bold)).tracking(-0.4)
                    Text("Dustpan compares file contents, not names, so only true copies are listed. Nothing is selected for you; pick which copies to keep.")
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .foregroundStyle(palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    SectionLabel("Where to look")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 196), spacing: 10)], spacing: 10) {
                        ForEach(ScanPlaces.folders(forDuplicates: true)) { place in
                            PlaceTile(glyph: place.glyph, tint: place.tint, title: place.title, detail: place.detail) { model.scan(place.url) }
                                .help(ScanPlaces.display(place.url.path))
                        }
                        PlaceTile(glyph: .folderPlus, title: "Choose Folder…", detail: "Or drop a folder here", dashed: true) {
                            model.chooseFolder()
                        }
                    }
                }

                VStack(spacing: 10) {
                    SectionLabel("Ignore files smaller than")
                    HStack {
                        HStack(spacing: 0) {
                            ForEach(Self.thresholds, id: \.bytes) { threshold in
                                SegmentButton(title: threshold.label, isSelected: model.minimumBytes == threshold.bytes) {
                                    model.minimumBytes = threshold.bytes
                                }
                            }
                        }
                        .segmentedContainer(palette)
                        Text("Bigger thresholds are faster and find the copies that matter most.")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.text2)
                        Spacer()
                    }
                }

                Text("Hidden files, app bundles, Photos libraries and ~/Library are skipped, because their contents are managed by apps.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.text2)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(palette.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay { Text("Drop to search this folder").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.accent) }
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let folder = urls.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }) else { return false }
            model.scan(folder)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    // MARK: Scanning

    private var scanningState: some View {
        VStack(spacing: 14) {
            Spinner()
            if let progress = model.progress, progress.phase == .comparing {
                Text("Comparing contents…").font(.system(size: 14, weight: .medium))
                ProgressBar(fraction: Double(progress.compared) / Double(max(progress.toCompare, 1)), width: 280)
                Text("\(progress.compared.formatted()) of \(progress.toCompare.formatted()) same-size files checked")
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(palette.text2)
            } else {
                Text("Looking through \(model.rootURL.map { ScanPlaces.display($0.path) } ?? "")…").font(.system(size: 14, weight: .medium))
                Text("\((model.progress?.filesSeen ?? 0).formatted()) files seen")
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(palette.text2)
            }
            Text(ScanPlaces.display(model.progress?.currentPath ?? ""))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(palette.text2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 480)
            NavButton(title: "Stop", glyph: .close) { model.cancelScan() }
                .keyboardShortcut(.cancelAction)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Results

    @ViewBuilder
    private func results(_ report: DuplicateReport) -> some View {
        if model.groups.isEmpty {
            VStack(spacing: 8) {
                if let outcome = model.lastOutcome {
                    OutcomeBanner(outcome: outcome) { model.lastOutcome = nil }.frame(maxWidth: 560).padding(.bottom, 20)
                }
                TintTile(.check, tint: Tint.green, size: 92, glyphSize: 44, radius: 24).padding(.bottom, 14)
                Text("No duplicates found").font(.system(size: 24, weight: .bold)).tracking(-0.4)
                Text("Checked \(report.filesScanned.formatted()) files in \(String(format: "%.1f", report.duration)) s.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.text2)
                NavButton(title: "Search Another Folder", glyph: .back) { model.startOver() }
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    if let outcome = model.lastOutcome {
                        OutcomeBanner(outcome: outcome) { model.lastOutcome = nil }
                    }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("EXTRA COPIES")
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(1)
                                .foregroundStyle(palette.text2)
                            Text(model.wastedBytes.formattedBytes)
                                .font(.system(size: 40, weight: .bold))
                                .tracking(-1.2)
                                .monospacedDigit()
                            Text("\(model.groups.count) sets of identical files · checked \(report.filesScanned.formatted()) files in \(String(format: "%.1f", report.duration)) s")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.text2)
                        }
                        Spacer()
                        Menu {
                            Button("Keep Oldest Copy of Each") { model.selectExtraCopies(keepingOldest: true) }
                            Button("Keep Newest Copy of Each") { model.selectExtraCopies(keepingOldest: false) }
                            Divider()
                            Button("Deselect All") { model.deselectAll() }
                        } label: {
                            Text("Select Extra Copies")
                        }
                        .menuStyle(.button)
                        .controlSize(.large)
                        .fixedSize()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.groups) { group in
                          VStack(spacing: 0) {
                            GroupHeaderRow(
                                group: group,
                                checkedCount: group.files.filter { model.checked.contains($0.url) }.count,
                                isExpanded: model.expanded.contains(group.id)
                            )
                            .onTapGesture { model.toggleExpanded(group) }
                            if model.expanded.contains(group.id) {
                                Rectangle().fill(palette.hair).frame(height: 0.5)
                                ForEach(Array(group.files.enumerated()), id: \.element.id) { position, file in
                                    DuplicateRow(
                                        file: file,
                                        isChecked: model.checked.contains(file.url),
                                        isOldest: position == 0,
                                        isLocked: !model.canTrash(file)
                                    )
                                    .onTapGesture { if model.canTrash(file) { model.toggle(file) } }
                                    .contextMenu {
                                        Button("Reveal in Finder") { model.reveal(file.url) }
                                        Button("Copy Path") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(file.url.path, forType: .string)
                                        }
                                    }
                                }
                            }
                          }
                          .cardStyle(palette)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                }

                footer
            }
        }
    }

    private var footer: some View {
        let blocked = model.fullyCheckedGroups
        return HStack(spacing: 12) {
            Text("\(model.checkedFiles.count) files selected · \(model.checkedBytes.formattedBytes)")
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(palette.text2)
            if let first = blocked.first {
                HStack(spacing: 5) {
                    GlyphView(.warning, size: 12)
                    Text("Every copy of \(first.name) is selected. Keep at least one.")
                        .lineLimit(1)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.warnInk)
            }
            Spacer()
            Button { isConfirming = true } label: {
                HStack(spacing: 8) {
                    GlyphView(.trash, size: 15, lineWidth: 1.5)
                    Text("Move to Trash…")
                }
            }
            .buttonStyle(DPButtonStyle(.destructive, height: 40, horizontalPadding: 16, fontSize: 13.5))
                .disabled(model.checkedFiles.isEmpty || !blocked.isEmpty || model.isBusy)
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
                title: "Move duplicate copies to the Trash?",
                targets: model.checkedFiles.map(\.target),
                onCancel: { isConfirming = false },
                onConfirm: {
                    isConfirming = false
                    Task { await model.trashChecked() }
                }
            )
        } else if let progress = model.deletionProgress {
            DeletionProgressOverlay(progress: progress)
        }
    }
}

// MARK: - Rows

private struct GroupHeaderRow: View {
    let group: DuplicateGroup
    let checkedCount: Int
    let isExpanded: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        let kind = FileKind.of(group.files.first?.url ?? URL(fileURLWithPath: "/"))
        HStack(spacing: 12) {
            TintTile(kind.glyph, tint: kind.tint, size: 34, glyphSize: 17, radius: 9)
            Text(group.name).font(.system(size: 13.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
            Text("\(group.files.count) copies · \(group.sizeBytes.formattedBytes) each")
                .font(.system(size: 12))
                .foregroundStyle(palette.text2)
                .lineLimit(1)
            if checkedCount > 0 {
                Text("\(checkedCount) selected")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(palette.accent.opacity(0.12), in: Capsule())
            }
            Spacer(minLength: 8)
            Text("\(group.wastedBytes.formattedBytes) extra")
                .font(.system(size: 13.5, weight: .semibold))
                .monospacedDigit()
            ExpandChevron(isExpanded: isExpanded)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(height: 58)
        .contentShape(Rectangle())
        .hoverFill(palette.rowHover)
    }
}

private struct DuplicateRow: View {
    let file: DuplicateFile
    let isChecked: Bool
    let isOldest: Bool
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
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(ScanPlaces.display(file.url.deletingLastPathComponent().path))
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                if let modified = file.modified {
                    Text("Modified \(modified.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.text2)
                }
            }
            if isOldest {
                Text("oldest")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.okInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Palette.okInk.opacity(0.12), in: Capsule())
            }
            Spacer(minLength: 8)
        }
        .padding(.leading, 56)
        .padding(.trailing, 14)
        .frame(minHeight: 42)
        .contentShape(Rectangle())
        .hoverFill(palette.rowHover)
        .help(isLocked ? "Outside your home folder, so Dustpan won't remove it" : file.url.path)
    }
}

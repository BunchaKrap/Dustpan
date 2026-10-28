import AppKit
import DustpanCore
import DustpanDesign
import SwiftUI

@MainActor
struct DiskSpaceView: View {
    @Bindable var model: DiskSpaceModel
    @Environment(\.palette) private var palette
    @State private var pendingTrash: DiskNode?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            DetailToolbar(title: "Disk Space", subtitle: subtitle) {
                if model.root != nil, !model.isScanning {
                    if model.isShowingLauncher {
                        NavButton(title: "Back to Results", glyph: .back) { model.hideLauncher() }
                    } else {
                        NavButton(title: "Locations", glyph: .drive) { model.showLauncher() }
                            .disabled(model.isBusy)
                            .help("Pick another disk or folder to scan")
                        NavButton(title: "Rescan", glyph: .rescan) { model.scan() }
                            .keyboardShortcut("r")
                            .disabled(model.isBusy)
                    }
                }
            }

            if model.isScanning {
                scanningState
            } else if model.isShowingLauncher || model.current == nil {
                launcher
            } else if let current = model.current {
                browser(current)
            }
        }
        .overlay { overlays }
        .animation(.easeOut(duration: 0.15), value: pendingTrash != nil)
        .animation(.easeOut(duration: 0.15), value: model.deletionProgress != nil)
    }

    private var subtitle: String {
        guard let volume = model.volume else { return "read-only" }
        return "\(volume.availableBytes.formattedBytes) free of \(volume.totalBytes.formattedBytes)"
    }

    // MARK: Launcher

    private var launcher: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What would you like to measure?").font(.system(size: 24, weight: .bold)).tracking(-0.4)
                    Text("Pick a disk or folder. Dustpan measures everything inside once, then you can click into any folder instantly. Nothing is changed unless you choose Move to Trash.")
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .foregroundStyle(palette.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    SectionLabel("Disks")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                        ForEach(model.volumes) { volume in
                            VolumeTile(volume: volume) { model.scan(volume.url) }
                                .help(volume.isStartup
                                      ? "Measures the whole startup disk. Folders macOS protects are skipped and counted as unreadable."
                                      : "Measures everything on \(volume.name).")
                        }
                    }
                }

                VStack(spacing: 10) {
                    SectionLabel("Folders")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 196), spacing: 10)], spacing: 10) {
                        ForEach(ScanPlaces.folders()) { place in
                            PlaceTile(glyph: place.glyph, tint: place.tint, title: place.title, detail: place.detail) { model.scan(place.url) }
                                .help(model.display(place.url.path))
                        }
                        PlaceTile(glyph: .folderPlus, title: "Choose Folder…", detail: "Or drop a folder here", dashed: true) {
                            model.chooseFolder()
                        }
                    }
                }

                if !model.recents.isEmpty {
                    VStack(spacing: 8) {
                        HStack {
                            SectionLabel("Recent")
                            Button("Clear") { model.forgetRecents() }
                                .buttonStyle(.plain)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.accent)
                        }
                        FlowRow(spacing: 8) {
                            ForEach(model.recents, id: \.self) { url in
                                Button {
                                    model.scan(url)
                                } label: {
                                    HStack(spacing: 6) {
                                        GlyphView(.navHistory, size: 12).foregroundStyle(palette.text2)
                                        Text(model.display(url.path)).lineLimit(1).truncationMode(.middle)
                                    }
                                    .frame(maxWidth: 280)
                                }
                                .buttonStyle(DPButtonStyle(.secondary, height: 28, horizontalPadding: 11, fontSize: 12.5))
                            }
                        }
                    }
                }

                Text("macOS may ask for permission to read Desktop, Documents, Downloads or other apps' data. Grant Full Disk Access in System Settings to measure everything.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.text3)
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
                    .overlay { Text("Drop to scan this folder").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.accent) }
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let folder = urls.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }) else { return false }
            model.scan(folder)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .onAppear { model.refreshVolumes() }
    }

    // MARK: Scanning

    private var scanningState: some View {
        VStack(spacing: 14) {
            Spinner()
            Text("Measuring \(model.title(for: model.rootURL))…").font(.system(size: 14, weight: .medium))
            Text("\(model.filesSeen.formatted()) files · \(model.bytesSeen.formattedBytes) so far")
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(palette.text2)
            Text(model.currentPath)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(palette.text2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 480)
            NavButton(title: "Stop", glyph: .close) { model.cancelScan() }
                .keyboardShortcut(.cancelAction)
                .padding(.top, 4)
            if let stall = model.stall {
                stallNotice(stall)
                    .frame(maxWidth: 520)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stallNotice(_ stall: AccessStall) -> some View {
        let asksPermission = stall.area != .system
        return AccessNotice(
            title: asksPermission ? "Waiting for your permission in macOS" : "Waiting for macOS to open a folder",
            lines: [
                "Dustpan has been waiting \(stall.seconds) s to open \(stall.path). \(stall.area.explanation)",
                "Look for a macOS dialog and click Allow, or Don't Allow to skip these folders. The scan carries on as soon as you answer.",
                "No dialog? It may be hidden behind another window, or the disk isn't responding. Stop the scan, turn on \(stall.area.settingsName) for Dustpan in System Settings, then scan again.",
            ],
            areas: [stall.area]
        )
    }

    private var deniedNotice: some View {
        let total = model.deniedAreas.reduce(0) { $0 + $1.folders }
        return AccessNotice(
            title: "macOS kept Dustpan out of \(total.formatted()) \(total == 1 ? "folder" : "folders"), so they aren't counted",
            lines: model.deniedAreas.map { "\($0.area.name): \($0.folders.formatted()) \($0.folders == 1 ? "folder" : "folders"). \($0.area.explanation)" }
                + ["Allow Dustpan in System Settings, then Rescan to include them."],
            areas: model.deniedAreas.map(\.area)
        ) {
            withAnimation(.easeInOut(duration: 0.2)) { model.showsDeniedNotice = false }
        }
    }

    // MARK: Browser

    private func browser(_ folder: DiskNode) -> some View {
        let _ = model.revision

        return VStack(spacing: 0) {
            if let outcome = model.lastOutcome {
                OutcomeBanner(outcome: outcome) { model.lastOutcome = nil }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
            }
            if model.showsDeniedNotice {
                deniedNotice
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
            }

            HStack(spacing: 6) {
                NavIconButton(glyph: .back, help: "Back (⌘[)") { model.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!model.canGoBack)
                NavIconButton(glyph: .up, help: "Enclosing folder (⌘↑)") { model.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(!model.canGoUp)

                BreadcrumbBar(crumbs: folder.ancestry.enumerated().map { index, node in
                    (node.url, index == 0 ? model.title(for: node.url) : node.name)
                }) { index in
                    model.go(to: folder.ancestry[index])
                }
                .padding(.leading, 4)

                Text("\(folder.sizeBytes.formattedBytes) · \(folder.fileCount.formatted()) files")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(palette.text2)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                ModePicker(modes: [
                    (DiskViewMode.list, "List", Glyph.list),
                    (.map, "Map", .treemap),
                    (.largest, "Largest Files", .ranking),
                ], selection: $model.viewMode)
                if model.viewMode == .largest {
                    kindChips
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            switch model.viewMode {
            case .list: listView(folder)
            case .map: mapView(folder)
            case .largest: largestView(folder)
            }
        }
    }

    private func listView(_ folder: DiskNode) -> some View {
        let maxChild = max(folder.children.first?.sizeBytes ?? 0, folder.hiddenFileBytes, 1)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(folder.children.enumerated()), id: \.element.id) { index, node in
                    DiskRow(
                        name: node.name,
                        glyph: node.isDirectory ? .folder : .file,
                        tint: Tint.cycle[index % Tint.cycle.count],
                        sizeBytes: node.sizeBytes,
                        barFraction: Double(node.sizeBytes) / Double(maxChild),
                        shareText: share(node.sizeBytes, of: folder.sizeBytes),
                        isOpenable: model.isOpenable(node)
                    )
                    .onTapGesture { model.open(node) }
                    .help(node.url.path)
                    .contextMenu { menu(for: node) }
                }
                if folder.hiddenFileCount > 0 {
                    DiskRow(
                        name: "\(folder.hiddenFileCount.formatted()) smaller files",
                        glyph: .file,
                        tint: Tint.stone,
                        sizeBytes: folder.hiddenFileBytes,
                        barFraction: Double(folder.hiddenFileBytes) / Double(maxChild),
                        shareText: share(folder.hiddenFileBytes, of: folder.sizeBytes),
                        isOpenable: false,
                        isSummary: true
                    )
                }
                if folder.children.isEmpty && folder.hiddenFileCount == 0 {
                    Text("This folder is empty or couldn't be read.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.text2)
                        .frame(height: 40)
                }
            }
            .panelStyle(palette)

            footnote("Click a folder to open it. Right-click any row to reveal it in Finder or move it to the Trash.")
        }
        .padding(.horizontal, 18)
    }

    private func mapView(_ folder: DiskNode) -> some View {
        VStack(spacing: 0) {
            TreemapView(
                folder: folder,
                isOpenable: model.isOpenable,
                onOpen: { model.open($0) },
                menu: { AnyView(menu(for: $0)) }
            )
            .id("\(folder.url.path)|\(model.revision)")
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.hair, lineWidth: 0.5))
            footnote("Each block's area matches its size. Click a folder to zoom in.")
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 2)
    }

    private func largestView(_ folder: DiskNode) -> some View {
        let files = model.largestFiles()
        let maxSize = max(files.first?.sizeBytes ?? 1, 1)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(files.enumerated()), id: \.element.id) { index, node in
                    LargeFileRow(
                        rank: index + 1,
                        node: node,
                        location: relativeLocation(of: node, in: folder),
                        barFraction: Double(node.sizeBytes) / Double(maxSize)
                    )
                    .onTapGesture { model.reveal(node) }
                    .help("Click to reveal in Finder · \(node.url.path)")
                    .contextMenu { menu(for: node) }
                }
                if files.isEmpty {
                    Text(model.kindFilter == nil ? "No files here." : "No \(model.kindFilter!.displayName.lowercased()) found in this folder.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.text2)
                        .frame(height: 44)
                }
            }
            .panelStyle(palette)

            footnote("The \(files.count) biggest files anywhere inside \(folder.name). Click one to reveal it in Finder; right-click to move it to the Trash.")
        }
        .padding(.horizontal, 18)
    }

    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All", isSelected: model.kindFilter == nil) { model.kindFilter = nil }
                ForEach(FileKind.allCases, id: \.self) { kind in
                    chip(kind.displayName, isSelected: model.kindFilter == kind) { model.kindFilter = kind }
                }
            }
        }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? palette.accent : palette.text2)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(isSelected ? palette.accent.opacity(0.14) : palette.chip, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func menu(for node: DiskNode) -> some View {
        if model.isOpenable(node) {
            Button("Open") { model.open(node) }
        }
        Button("Reveal in Finder") { model.reveal(node) }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.url.path, forType: .string)
        }
        Divider()
        Button("Move to Trash…") { pendingTrash = node }
            .disabled(!model.canTrash(node) || model.isBusy)
    }

    private func footnote(_ lead: String) -> some View {
        var text = lead + String(format: " Measured in %.1f s.", model.duration)
        if model.unreadable > 0 {
            text += " \(model.unreadable.formatted()) items couldn't be read and aren't counted."
        }
        return Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(palette.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
    }

    private func relativeLocation(of node: DiskNode, in folder: DiskNode) -> String {
        let parent = node.url.deletingLastPathComponent().path
        let base = folder.url.path
        guard parent.hasPrefix(base) else { return model.display(parent) }
        let rest = parent.dropFirst(base.count).drop { $0 == "/" }
        return rest.isEmpty ? folder.name : "\(folder.name)/\(rest)"
    }

    private func share(_ bytes: Int64, of total: Int64) -> String {
        guard total > 0 else { return "0%" }
        let percent = Double(bytes) / Double(total) * 100
        return percent < 1 && bytes > 0 ? "<1%" : "\(Int(percent.rounded()))%"
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlays: some View {
        if let node = pendingTrash {
            TrashConfirmationSheet(
                title: "Move \(node.name) to the Trash?",
                targets: [DeletionTarget(url: node.url, sizeBytes: node.sizeBytes)],
                onCancel: { pendingTrash = nil },
                onConfirm: {
                    pendingTrash = nil
                    Task { await model.trash(node) }
                }
            )
        } else if let progress = model.deletionProgress {
            DeletionProgressOverlay(progress: progress)
        }
    }
}

extension View {
    /// The rounded list panel used by Disk Space and Duplicates.
    func panelStyle(_ palette: Palette) -> some View {
        cardStyle(palette)
    }
}

extension FileKind {
    var tint: Color {
        switch self {
        case .video: Tint.pink
        case .image: Tint.browser
        case .audio: Tint.lilac
        case .archive: Tint.brew
        case .installer: Tint.docker
        case .document: Tint.caches
        case .other: Tint.logs
        }
    }

    var glyph: Glyph {
        switch self {
        case .video: .film
        case .image: .photo
        case .audio: .music
        case .archive: .archive
        case .installer: .installer
        case .document: .logs
        case .other: .file
        }
    }
}

private struct DiskRow: View {
    let name: String
    let glyph: Glyph
    let tint: Color
    let sizeBytes: Int64
    let barFraction: Double
    let shareText: String
    let isOpenable: Bool
    var isSummary = false
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            TintTile(glyph, tint: tint, size: 26, glyphSize: 14, radius: 7)
                .opacity(isSummary ? 0.6 : 1)
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(isSummary ? palette.text2 : palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 220, alignment: .leading)
            SizeBar(fraction: barFraction, tint: tint, dimmed: isSummary, hasSize: sizeBytes > 0)
            Text(sizeBytes.formattedBytes)
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(palette.text2)
                .frame(width: 74, alignment: .trailing)
            Text(shareText)
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(palette.text3)
                .frame(width: 42, alignment: .trailing)
            GlyphView(.chevron, size: 10)
                .foregroundStyle(palette.text2)
                .frame(width: 22, height: 22)
                .background(palette.chip, in: RoundedRectangle(cornerRadius: 6))
                .opacity(isOpenable ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .contentShape(Rectangle())
        .hoverFill(palette.rowHover)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.hair.opacity(0.7)).frame(height: 0.5) }
    }
}

private struct LargeFileRow: View {
    let rank: Int
    let node: DiskNode
    let location: String
    let barFraction: Double
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(palette.text3)
                .frame(width: 22, alignment: .trailing)
            TintTile(FileKind.of(node.url).glyph, tint: FileKind.of(node.url).tint, size: 26, glyphSize: 14, radius: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                Text(location)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.text2)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .frame(width: 260, alignment: .leading)
            SizeBar(fraction: barFraction, tint: FileKind.of(node.url).tint, dimmed: false, hasSize: node.sizeBytes > 0)
            Text(node.sizeBytes.formattedBytes)
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(palette.text2)
                .frame(width: 74, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .contentShape(Rectangle())
        .hoverFill(palette.rowHover)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.hair.opacity(0.7)).frame(height: 0.5) }
    }
}

private struct SizeBar: View {
    let fraction: Double
    let tint: Color
    let dimmed: Bool
    let hasSize: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.hair)
                Capsule()
                    .fill(tint.opacity(dimmed ? 0.4 : 1))
                    .frame(width: max(proxy.size.width * min(fraction, 1), hasSize ? 3 : 0))
            }
        }
        .frame(height: 8)
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var y: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

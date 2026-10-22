import DustpanCore
import DustpanDesign
import SwiftUI

/// Squarified treemap of one folder's children: area is proportional to size.
struct TreemapView: View {
    let folder: DiskNode
    let isOpenable: (DiskNode) -> Bool
    let onOpen: (DiskNode) -> Void
    let menu: (DiskNode) -> AnyView
    @Environment(\.palette) private var palette
    @State private var hovered: URL?

    /// Beyond this many tiles the rest are drawn as one "other items" block.
    private static let maxTiles = 60

    private struct Tile: Identifiable {
        let id: URL
        let node: DiskNode?
        let title: String
        let sizeBytes: Int64
        let rect: CGRect
    }

    var body: some View {
        GeometryReader { proxy in
            let tiles = layout(in: CGRect(origin: .zero, size: proxy.size))
            ZStack(alignment: .topLeading) {
                palette.panel
                ForEach(tiles) { tile in
                    tileView(tile)
                        .frame(width: max(tile.rect.width - 2, 0), height: max(tile.rect.height - 2, 0))
                        .offset(x: tile.rect.minX + 1, y: tile.rect.minY + 1)
                }
            }
        }
        .frame(minHeight: 260)
    }

    @ViewBuilder
    private func tileView(_ tile: Tile) -> some View {
        let node = tile.node
        let isFolder = node?.isDirectory == true
        let isHovered = hovered == tile.id
        let showsLabel = tile.rect.width > 64 && tile.rect.height > 34

        RoundedRectangle(cornerRadius: 5)
            .fill(fill(for: tile, isFolder: isFolder))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(palette.accent, lineWidth: 1.5)
                    .opacity(isHovered ? 1 : 0)
            }
            .overlay(alignment: .topLeading) {
                if showsLabel {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            if node != nil {
                                GlyphView(isFolder ? .folder : .file, size: 11)
                            }
                            Text(tile.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        }
                        Text(tile.sizeBytes.formattedBytes)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .opacity(0.8)
                    }
                    .foregroundStyle(isFolder ? Color.white : palette.text)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovering in
                withAnimation(Motion.hover) { hovered = isHovering ? tile.id : (hovered == tile.id ? nil : hovered) }
            }
            .onTapGesture { if let node, isOpenable(node) { onOpen(node) } }
            .help("\(tile.title) · \(tile.sizeBytes.formattedBytes)\(node.map { isOpenable($0) ? " · click to open" : "" } ?? "")")
            .contextMenu { if let node { menu(node) } }
    }

    /// Folders in the accent colour, larger ones stronger; files and the remainder in neutral tints.
    private func fill(for tile: Tile, isFolder: Bool) -> Color {
        guard tile.node != nil else { return palette.hair }
        let share = Double(tile.sizeBytes) / Double(max(folder.sizeBytes, 1))
        if isFolder { return palette.accent.opacity(0.55 + min(share * 1.5, 0.4)) }
        return palette.accent.opacity(0.16 + min(share, 0.2))
    }

    private func layout(in rect: CGRect) -> [Tile] {
        var entries: [(id: URL, node: DiskNode?, title: String, size: Int64)] = folder.children
            .filter { $0.sizeBytes > 0 }
            .prefix(Self.maxTiles)
            .map { ($0.url, $0, $0.name, $0.sizeBytes) }
        let shown = entries.reduce(0) { $0 + $1.size }
        let rest = folder.sizeBytes - shown
        if rest > 0 {
            let count = folder.children.count - entries.count + folder.hiddenFileCount
            entries.append((folder.url.appendingPathComponent("…other"), nil, "\(count.formatted()) other items", rest))
        }
        let rects = Squarify.layout(entries.map { Double($0.size) }, in: rect)
        return zip(entries, rects).map { Tile(id: $0.id, node: $0.node, title: $0.title, sizeBytes: $0.size, rect: $1) }
    }
}

/// Bruls, Huizing & van Wijk's squarified treemap: rows are grown while they keep tiles close to square.
enum Squarify {
    static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return values.map { _ in .zero } }
        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { $0 * scale }

        var rects: [CGRect] = []
        var remaining = rect
        var start = 0
        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            while end < areas.count, worst(areas[start...end], side: side) <= worst(areas[start..<end], side: side) {
                end += 1
            }
            let row = areas[start..<end]
            let rowArea = row.reduce(0, +)
            if remaining.width >= remaining.height {
                let width = CGFloat(rowArea / Double(remaining.height))
                var y = remaining.minY
                for area in row {
                    let height = CGFloat(area) / width
                    rects.append(CGRect(x: remaining.minX, y: y, width: width, height: height))
                    y += height
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY, width: max(remaining.width - width, 0), height: remaining.height)
            } else {
                let height = CGFloat(rowArea / Double(remaining.width))
                var x = remaining.minX
                for area in row {
                    let width = CGFloat(area) / height
                    rects.append(CGRect(x: x, y: remaining.minY, width: width, height: height))
                    x += width
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height, width: remaining.width, height: max(remaining.height - height, 0))
            }
            start = end
        }
        return rects
    }

    /// The worst aspect ratio in a row laid along a side of the given length.
    private static func worst(_ row: ArraySlice<Double>, side: Double) -> Double {
        let sum = row.reduce(0, +)
        guard sum > 0, side > 0, let largest = row.max(), let smallest = row.min(), smallest > 0 else { return .infinity }
        return max(side * side * largest / (sum * sum), (sum * sum) / (side * side * smallest))
    }
}

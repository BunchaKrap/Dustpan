import AppKit
import DustpanCore
import SwiftUI

struct ScanOptionsView: View {
    @Binding var options: ScanOptions

    private static let sizeThresholds: [(label: String, bytes: Int64)] = [
        ("Show everything", 0),
        ("1 MB or larger", 1_000_000),
        ("10 MB or larger", 10_000_000),
        ("100 MB or larger", 100_000_000),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                depthSection
                Divider()
                scopeSection
                Divider()
                categoriesSection
                Divider()
                sizeSection
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { options = ScanOptions() }
                }
            }
            .padding(18)
        }
        .frame(width: 400, height: 600)
    }

    // MARK: Depth

    private var depthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan depth").font(.headline)
            ForEach(ScanDepth.allCases, id: \.self) { depth in
                Button {
                    options.depth = depth
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: options.depth == depth ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(options.depth == depth ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(depth.displayName).fontWeight(.medium)
                            Text(depth.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Scope

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where to look for project build files").font(.headline)
            Text(options.depth == .deep ? "Searches for node_modules, .build, target, Pods, virtualenvs and similar folders."
                                        : "Only used by Deep scans.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Scope", selection: scopeKind) {
                Text("Home folder").tag(ScopeKind.home)
                Text("Entire startup disk").tag(ScopeKind.startupDisk)
                Text("Specific folders").tag(ScopeKind.folders)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if case .startupDisk = options.scope {
                Label("Items outside your home folder are listed but can't be removed. System folders are skipped.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case .folders(let folders) = options.scope {
                VStack(alignment: .leading, spacing: 4) {
                    if folders.isEmpty {
                        Text("No folders chosen yet.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(folders, id: \.self) { folder in
                        HStack {
                            Image(systemName: "folder")
                            Text(folder.path).lineLimit(1).truncationMode(.middle).font(.callout)
                            Spacer()
                            Button {
                                options.scope = .folders(folders.filter { $0 != folder })
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("Add Folder…") { addFolders(to: folders) }
                }
            }

            Label("macOS may ask permission to read Desktop, Documents or Downloads.", systemImage: "hand.raised")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(options.depth != .deep)
        .opacity(options.depth == .deep ? 1 : 0.5)
    }

    private enum ScopeKind: Hashable { case home, startupDisk, folders }

    private var scopeKind: Binding<ScopeKind> {
        Binding(
            get: {
                switch options.scope {
                case .home: .home
                case .startupDisk: .startupDisk
                case .folders: .folders
                }
            },
            set: { kind in
                switch kind {
                case .home: options.scope = .home
                case .startupDisk: options.scope = .startupDisk
                case .folders:
                    if case .folders = options.scope { return }
                    options.scope = .folders([])
                }
            }
        )
    }

    private func addFolders(to existing: [URL]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.filter { !existing.contains($0) }
        options.scope = .folders(existing + added)
    }

    // MARK: Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Categories").font(.headline)
            ForEach(JunkCategory.allCases, id: \.self) { category in
                let available = category.minimumDepth <= options.depth
                Toggle(isOn: categoryBinding(category)) {
                    HStack(spacing: 6) {
                        Image(systemName: category.symbolName).frame(width: 18)
                        Text(category.displayName)
                        if !available {
                            Text(category.minimumDepth.displayName)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!available)
                .help(available ? "" : "Included in \(category.minimumDepth.displayName) scans")
            }
        }
    }

    private func categoryBinding(_ category: JunkCategory) -> Binding<Bool> {
        Binding(
            get: { !options.excludedCategories.contains(category) },
            set: { isOn in
                if isOn { options.excludedCategories.remove(category) } else { options.excludedCategories.insert(category) }
            }
        )
    }

    // MARK: Size

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Minimum item size").font(.headline)
            Picker("Minimum item size", selection: $options.minimumItemBytes) {
                ForEach(Self.sizeThresholds, id: \.bytes) { threshold in
                    Text(threshold.label).tag(threshold.bytes)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
        }
    }
}

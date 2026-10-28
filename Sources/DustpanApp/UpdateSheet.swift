import DustpanCore
import DustpanDesign
import SwiftUI

/// Check for Updates: shows the latest GitHub release and installs it on request.
@MainActor
struct UpdateSheet: View {
    let model: UpdateModel
    @Environment(\.palette) private var palette

    var body: some View {
        ModalBackdrop {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    TintTile(tileGlyph, tint: tileTint, size: 64, glyphSize: 30, radius: 17)
                        .padding(.bottom, 10)
                    Text(title).font(.system(size: 19, weight: .bold)).tracking(-0.3)
                    Text(message)
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .foregroundStyle(palette.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .padding(.top, 26)

                if let release = shownRelease, !release.notes.isEmpty {
                    ScrollView {
                        ReleaseNotesList(sections: Changelog.sections(release.notes))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .frame(maxHeight: 220)
                    .background(palette.field, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.hair, lineWidth: 0.5))
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }

                if case .downloading = model.phase {
                    HStack(spacing: 10) {
                        Spinner()
                        Text("Downloading and verifying…").font(.system(size: 12.5)).foregroundStyle(palette.text2)
                    }
                    .padding(.top, 18)
                }

                buttons
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 22)
            }
            .frame(width: 460)
            .background(palette.sheet, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 25, y: 20)
        }
    }

    // MARK: Content per phase

    private var shownRelease: ReleaseInfo? {
        switch model.phase {
        case .available(let release), .downloading(let release), .ready(let release, _): release
        default: nil
        }
    }

    private var tileGlyph: Glyph {
        switch model.phase {
        case .upToDate: .check
        case .failed: .warning
        default: .download
        }
    }

    private var tileTint: Color {
        switch model.phase {
        case .upToDate: Tint.green
        case .failed: Tint.brew
        default: Tint.blue
        }
    }

    private var title: String {
        switch model.phase {
        case .idle, .checking: "Checking for updates…"
        case .upToDate: "Dustpan is up to date"
        case .available(let release), .downloading(let release): "Dustpan \(release.version) is available"
        case .ready(let release, _): "Ready to install \(release.version)"
        case .failed: "Couldn't check for updates"
        }
    }

    private var message: String {
        switch model.phase {
        case .idle, .checking:
            return "Looking at the latest release on GitHub."
        case .upToDate(let latest):
            return "You have version \(model.currentVersion). The latest release is \(latest)."
        case .available(let release), .downloading(let release):
            let size = release.sizeBytes > 0 ? " (\(release.sizeBytes.formattedBytes))" : ""
            return "You have \(model.currentVersion). The download\(size) is checked before anything is replaced."
        case .ready:
            return "Dustpan will quit, replace itself with the new version and open again. If anything goes wrong, the current version is kept."
        case .failed(let reason):
            return reason
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 10) {
            if let page = shownRelease {
                Button("View on GitHub") { model.openReleasePage(page) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.accent)
            } else if model.releasesPage != nil, case .failed = model.phase {
                Button("Open Releases Page") { model.openReleasePage() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.accent)
            }
            Spacer()
            Button(isTerminal ? "Done" : "Later") { model.dismiss() }
                .buttonStyle(DPButtonStyle(.secondary, height: 32, horizontalPadding: 16, fontSize: 13))
                .keyboardShortcut(.cancelAction)
            switch model.phase {
            case .available(let release):
                if model.canInstallInPlace {
                    Button("Download & Install") { model.download() }
                        .buttonStyle(DPButtonStyle(.primary, height: 32, horizontalPadding: 16, fontSize: 13))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Download from GitHub") { model.openReleasePage(release) }
                        .buttonStyle(DPButtonStyle(.primary, height: 32, horizontalPadding: 16, fontSize: 13))
                        .help("This copy of Dustpan isn't in a folder it can update, so get the new version from GitHub.")
                }
            case .downloading:
                Button("Download & Install") {}
                    .buttonStyle(DPButtonStyle(.primary, height: 32, horizontalPadding: 16, fontSize: 13))
                    .disabled(true)
            case .ready:
                Button("Install & Relaunch") { model.installAndRelaunch() }
                    .buttonStyle(DPButtonStyle(.primary, height: 32, horizontalPadding: 16, fontSize: 13))
                    .keyboardShortcut(.defaultAction)
            case .failed:
                if model.isConfigured {
                    Button("Try Again") { model.checkNow() }
                        .buttonStyle(DPButtonStyle(.primary, height: 32, horizontalPadding: 16, fontSize: 13))
                }
            default:
                EmptyView()
            }
        }
    }

    private var isTerminal: Bool {
        switch model.phase {
        case .upToDate, .failed: true
        default: false
        }
    }
}

/// Sidebar button: "Check for Updates", or a highlighted "Update available" once a check found one.
@MainActor
struct UpdateButton: View {
    let model: UpdateModel
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button { model.hasUpdate ? (model.isShowingSheet = true) : model.checkNow() } label: {
            HStack(spacing: 8) {
                GlyphView(.download, size: 13)
                    .foregroundStyle(model.hasUpdate ? Color.white : palette.text2)
                Text(model.hasUpdate ? "Update available" : "Check for Updates")
                    .font(.system(size: 12.5, weight: model.hasUpdate ? .semibold : .regular))
                    .foregroundStyle(model.hasUpdate ? Color.white : palette.text)
                Spacer(minLength: 0)
                if case .checking = model.phase {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(model.hasUpdate ? palette.accent : palette.card)
                    RoundedRectangle(cornerRadius: 9).fill(palette.rowHover).opacity(hovering && !model.hasUpdate ? 1 : 0)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in withAnimation(Motion.hover) { hovering = isHovering } }
        .animation(Motion.hover, value: model.hasUpdate)
        .help(model.isConfigured ? "Checks GitHub for a newer version. This is the only time Dustpan goes online." : "Updates aren't set up for this build.")
    }
}

/// Shown after Dustpan relaunches on a new version (and from Dustpan › What's New in Dustpan…).
@MainActor
struct WhatsNewSheet: View {
    let model: UpdateModel
    @Environment(\.palette) private var palette

    private var subtitle: String {
        guard model.isAfterUpdate else { return "Recent changes to Dustpan." }
        if let from = model.updatedFrom { return "You've updated from \(from). Here's what changed." }
        return "Dustpan has been updated. Here's what changed."
    }

    var body: some View {
        ModalBackdrop {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    TintTile(.navCleanup, tint: Tint.purple, size: 64, glyphSize: 30, radius: 17)
                        .padding(.bottom, 10)
                    Text("What's new in Dustpan \(model.currentVersion)").font(.system(size: 19, weight: .bold)).tracking(-0.3)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.text2)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .padding(.top, 26)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(model.whatsNew, id: \.version) { entry in
                            VStack(alignment: .leading, spacing: 12) {
                                if model.whatsNew.count > 1 {
                                    Text(["Version \(entry.version)", entry.date].compactMap { $0 }.joined(separator: " · "))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.text2)
                                }
                                ReleaseNotesList(sections: entry.sections)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .frame(maxHeight: 340)
                .fixedSize(horizontal: false, vertical: true)
                .background(palette.field, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.hair, lineWidth: 0.5))
                .padding(.horizontal, 24)
                .padding(.top, 18)

                HStack {
                    Spacer()
                    Button("Continue") { model.dismissWhatsNew() }
                        .buttonStyle(DPButtonStyle(.primary, height: 32, horizontalPadding: 18, fontSize: 13))
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 22)
            }
            .frame(width: 500)
            .background(palette.sheet, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 25, y: 20)
        }
    }
}

/// Release notes as labelled groups ("New", "Improved", "Fixed") of readable bullets.
struct ReleaseNotesList: View {
    let sections: [ChangelogSection]
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                let tint = Self.tint(for: section.title)
                VStack(alignment: .leading, spacing: 8) {
                    if !section.title.isEmpty {
                        Text(section.title.uppercased())
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(tint.opacity(0.13), in: Capsule())
                    }
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Circle().fill(tint).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1.5 }
                            Text(Self.inline(item))
                                .font(.system(size: 13))
                                .lineSpacing(2.5)
                                .foregroundStyle(palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private static func tint(for title: String) -> Color {
        switch title.lowercased() {
        case "new", "added": Tint.blue
        case "improved", "changed": Tint.green
        case "fixed": Tint.orange
        default: Tint.grey
        }
    }

    /// Keeps **bold**, *italic*, `code` and links from the Markdown source.
    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

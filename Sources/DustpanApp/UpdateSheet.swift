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
                            .padding(16)
                    }
                    .frame(height: 240)
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
/// Always the same size, whatever the window or the amount of notes; the notes scroll inside it.
@MainActor
struct WhatsNewSheet: View {
    let model: UpdateModel
    @Environment(\.palette) private var palette

    private var subtitle: String {
        guard model.isAfterUpdate else { return "The latest changes" }
        if let from = model.updatedFrom { return "Updated from \(from)" }
        return "Just updated"
    }

    var body: some View {
        ModalBackdrop {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("What's new in Dustpan").font(.system(size: 19, weight: .bold)).tracking(-0.3)
                        HStack(spacing: 8) {
                            Text(model.currentVersion)
                                .font(.system(size: 11.5, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(palette.accent, in: Capsule())
                            Text(subtitle).font(.system(size: 12.5)).foregroundStyle(palette.text2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 26)
                .padding(.top, 24)
                .padding(.bottom, 18)

                Rectangle().fill(palette.hair).frame(height: 0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        ForEach(model.whatsNew, id: \.version) { entry in
                            VStack(alignment: .leading, spacing: 16) {
                                if model.whatsNew.count > 1 {
                                    Text(["Version \(entry.version)", entry.date].compactMap { $0 }.joined(separator: " · "))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(palette.text)
                                }
                                ReleaseNotesList(sections: entry.sections)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
                .frame(maxHeight: .infinity)
                // Fades out at the bottom so it's clear the list carries on.
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 36)
                    }
                }

                Rectangle().fill(palette.hair).frame(height: 0.5)

                HStack {
                    if model.releasesPage != nil {
                        Button("All releases on GitHub") { model.openReleasePage() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.accent)
                    }
                    Spacer()
                    Button("Continue") { model.dismissWhatsNew() }
                        .buttonStyle(DPButtonStyle(.primary, height: 32, horizontalPadding: 18, fontSize: 13))
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24)
                .frame(height: 64)
            }
            .frame(width: 540, height: 500)
            .background(palette.sheet, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 25, y: 20)
        }
    }
}

/// Release notes grouped under "New", "Improved" and "Fixed". An item written as `**Headline.** detail`
/// shows the headline in bold with the detail beneath it.
struct ReleaseNotesList: View {
    let sections: [ChangelogSection]
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                let style = Self.style(for: section.title)
                VStack(alignment: .leading, spacing: 14) {
                    if !section.title.isEmpty {
                        HStack(spacing: 10) {
                            Text(section.title.uppercased())
                                .font(.system(size: 10.5, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(style.tint)
                                .fixedSize()
                            Rectangle().fill(palette.hair).frame(height: 0.5)
                        }
                    }
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        let parts = Self.split(item)
                        HStack(alignment: .top, spacing: 12) {
                            TintTile(style.glyph, tint: style.tint, size: 26, glyphSize: 13, radius: 7)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Self.inline(parts.headline))
                                    .font(.system(size: 13.5, weight: parts.detail == nil ? .regular : .semibold))
                                    .foregroundStyle(palette.text)
                                if let detail = parts.detail {
                                    Text(Self.inline(detail))
                                        .font(.system(size: 12.5))
                                        .lineSpacing(2)
                                        .foregroundStyle(palette.text2)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.top, 3)
                        }
                    }
                }
            }
        }
    }

    private static func style(for title: String) -> (tint: Color, glyph: Glyph) {
        switch title.lowercased() {
        case "new", "added": (Tint.blue, .plus)
        case "improved", "changed": (Tint.green, .navCleanup)
        case "fixed": (Tint.orange, .check)
        default: (Tint.grey, .arrowRight)
        }
    }

    /// "**Activity.** See everything…" → ("Activity", "See everything…"). Plain items have no detail.
    static func split(_ item: String) -> (headline: String, detail: String?) {
        guard item.hasPrefix("**"), let end = item.range(of: "**", range: item.index(item.startIndex, offsetBy: 2)..<item.endIndex) else {
            return (item, nil)
        }
        var headline = String(item[item.index(item.startIndex, offsetBy: 2)..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
        if headline.hasSuffix(".") || headline.hasSuffix(":") { headline.removeLast() }
        let detail = item[end.upperBound...].trimmingCharacters(in: .whitespaces)
        return (headline, detail.isEmpty ? nil : detail)
    }

    /// Keeps **bold**, *italic*, `code` and links from the Markdown source.
    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

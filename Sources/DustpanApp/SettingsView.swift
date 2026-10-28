import DustpanDesign
import SwiftUI

@MainActor
struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            section("Appearance") {
                HStack(spacing: 0) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        SegmentButton(title: mode.displayName, isSelected: settings.appearance == mode) {
                            settings.appearance = mode
                        }
                    }
                }
                .segmentedContainer(palette)
            }

            section("Background") {
                Toggle(isOn: $settings.backgroundMotion) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drifting ribbons").font(.system(size: 13))
                        Text("Slow, soft strings that move behind the content. They hold still when Reduce Motion is on in System Settings.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            section("Accent colour") {
                HStack(spacing: 18) {
                    ForEach(AccentTheme.allCases, id: \.self) { accent in
                        let isSelected = settings.accent == accent
                        Button {
                            settings.accent = accent
                        } label: {
                            VStack(spacing: 7) {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if isSelected {
                                            GlyphView(.check, size: 12).foregroundStyle(.white)
                                        }
                                    }
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(isSelected ? accent.color : .clear, lineWidth: 2))
                                Text(accent.displayName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(isSelected ? palette.text : palette.text2)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            section("App icon") {
                HStack(spacing: 12) {
                    ForEach(AppIconStyle.allCases, id: \.self) { style in
                        let isSelected = settings.appIcon == style
                        Button {
                            settings.appIcon = style
                        } label: {
                            VStack(spacing: 6) {
                                Image(nsImage: AppIconArt.image(style))
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 88, height: 88)
                                Text(style.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                Text(style.tagline)
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.text2)
                                    .multilineTextAlignment(.center)
                                    .frame(height: 28, alignment: .top)
                            }
                            .frame(width: 118)
                            .padding(.vertical, 10)
                            .background(isSelected ? palette.chip : palette.panel, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(isSelected ? palette.accent : palette.hair, lineWidth: isSelected ? 2 : 0.5)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("The Dock icon changes right away. The Finder icon is chosen when the app is built: `DUSTPAN_ICON=paper ./bundle.sh`")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(palette.bg)
        .foregroundStyle(palette.text)
        .navigationTitle("Dustpan Settings")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.66)
                .foregroundStyle(palette.text2)
            content()
        }
    }
}

/// One pill inside the design-styled segmented control.
struct SegmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Color.white : palette.text)
                .padding(.horizontal, 11)
                .frame(height: 24)
                .background(isSelected ? palette.accent : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func segmentedContainer(_ palette: Palette) -> some View {
        padding(2)
            .background(palette.btn, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.btnBorder, lineWidth: 0.5))
    }
}

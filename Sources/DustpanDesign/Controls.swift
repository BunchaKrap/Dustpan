import AppKit
import SwiftUI

// MARK: - Motion

/// Hover timing. Large surfaces (tiles, rows, cards) ease in and out gently; tiny controls stay snappy.
public enum Motion {
    public static let hover = Animation.easeInOut(duration: 0.22)
    public static let quick = Animation.easeOut(duration: 0.1)
}

// MARK: - Buttons

public enum DPButtonKind {
    case secondary, primary, destructive
}

/// The design's toolbar / footer / sheet buttons.
public struct DPButtonStyle: ButtonStyle {
    var kind: DPButtonKind
    var height: CGFloat
    var horizontalPadding: CGFloat
    var fontSize: CGFloat
    var focusRing: Bool

    public init(_ kind: DPButtonKind = .secondary, height: CGFloat = 26, horizontalPadding: CGFloat = 10,
                fontSize: CGFloat = 12.5, focusRing: Bool = false) {
        self.kind = kind
        self.height = height
        self.horizontalPadding = horizontalPadding
        self.fontSize = fontSize
        self.focusRing = focusRing
    }

    public func makeBody(configuration: Configuration) -> some View {
        DPButtonBody(configuration: configuration, style: self)
    }
}

private struct DPButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let style: DPButtonStyle
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var radius: CGFloat { style.height >= 40 ? 12 : style.height >= 30 ? 9 : style.height >= 28 ? 7 : 6 }
    private var isLarge: Bool { style.height >= 36 }

    var body: some View {
        configuration.label
            .font(.system(size: style.fontSize, weight: style.kind == .secondary ? .regular : .medium))
            // A button label never wraps; the layout around it has to make room instead.
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(style.kind == .secondary ? palette.text : Color.white)
            .padding(.horizontal, style.horizontalPadding)
            .frame(height: style.height)
            .background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay {
                if style.kind == .secondary {
                    RoundedRectangle(cornerRadius: radius).strokeBorder(palette.btnBorder.opacity(0.8), lineWidth: 0.5)
                } else if isEnabled {
                    // Soft top highlight from the v2 design.
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
                }
            }
            .overlay {
                if style.focusRing {
                    RoundedRectangle(cornerRadius: radius + 3)
                        .stroke(palette.accent.opacity(0.4), lineWidth: 3)
                        .padding(-3)
                }
            }
            .shadow(color: .black.opacity(style.kind == .secondary ? 0.07 : 0.16), radius: 1, y: 1)
            .shadow(color: glow.opacity(isLarge && isEnabled ? 0.45 : 0), radius: 7, y: 5)
            .brightness(style.kind != .secondary && hovering && isEnabled ? 0.05 : 0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : (style.kind == .secondary ? 0.5 : 0.6))
            .contentShape(Rectangle())
            .onHover { isHovering in withAnimation(Motion.quick) { hovering = isHovering } }
    }

    private var fill: AnyShapeStyle {
        switch style.kind {
        case .secondary: AnyShapeStyle(hovering && isEnabled ? palette.btnHover : palette.btn)
        case .primary: AnyShapeStyle(isEnabled ? palette.accent : Palette.disabledFill)
        case .destructive:
            isEnabled
                ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xE8604E), Color(hex: 0xC9392A)], startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(Palette.disabledFill)
        }
    }

    private var glow: Color {
        switch style.kind {
        case .secondary: .clear
        case .primary: palette.accent
        case .destructive: Palette.danger
        }
    }
}

// MARK: - Checkbox

public enum CheckState {
    case on, off, mixed
}

public struct DPCheckbox: View {
    let state: CheckState
    @Environment(\.palette) private var palette

    public init(_ state: CheckState) {
        self.state = state
    }

    public var body: some View {
        ZStack {
            switch state {
            case .on:
                RoundedRectangle(cornerRadius: 5).fill(palette.accent)
                GlyphView(.check, size: 10).foregroundStyle(.white)
            case .mixed:
                RoundedRectangle(cornerRadius: 5).fill(palette.accent)
                RoundedRectangle(cornerRadius: 1).fill(.white).frame(width: 8, height: 2)
            case .off:
                RoundedRectangle(cornerRadius: 5).fill(palette.field)
                RoundedRectangle(cornerRadius: 5).strokeBorder(palette.btnBorder, lineWidth: 1)
            }
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Tinted icon tile

/// White glyph on a tinted gradient square: the v2 design's icon treatment.
public struct TintTile: View {
    let glyph: Glyph
    let tint: Color
    let size: CGFloat
    let glyphSize: CGFloat
    let radius: CGFloat

    public init(_ glyph: Glyph, tint: Color, size: CGFloat = 34, glyphSize: CGFloat? = nil, radius: CGFloat? = nil) {
        self.glyph = glyph
        self.tint = tint
        self.size = size
        self.glyphSize = glyphSize ?? (size * 0.5).rounded()
        self.radius = radius ?? (size * 0.27).rounded()
    }

    public var body: some View {
        GlyphView(glyph, size: glyphSize, lineWidth: 1.45)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [tint.lightened(0.3), tint], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: radius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center), lineWidth: 0.75)
            }
            .shadow(color: tint.opacity(0.35), radius: size > 40 ? 9 : 2.5, y: size > 40 ? 6 : 1.5)
    }
}

// MARK: - Misc

public struct HoverFill: ViewModifier {
    let color: Color
    let cornerRadius: CGFloat
    @State private var hovering = false

    public func body(content: Content) -> some View {
        content
            .background(color.opacity(hovering ? 1 : 0), in: RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { isHovering in withAnimation(Motion.hover) { hovering = isHovering } }
    }
}

public extension View {
    func hoverFill(_ color: Color, cornerRadius: CGFloat = 0) -> some View {
        modifier(HoverFill(color: color, cornerRadius: cornerRadius))
    }
}

public struct Spinner: View {
    @Environment(\.palette) private var palette
    @State private var spinning = false

    public init() {}

    public var body: some View {
        Circle()
            .stroke(palette.hair, lineWidth: 2.5)
            .overlay {
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(palette.accent, lineWidth: 2.5)
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spinning)
            }
            .frame(width: 26, height: 26)
            .onAppear { spinning = true }
    }
}

public struct ProgressBar: View {
    let fraction: Double
    let width: CGFloat?
    @Environment(\.palette) private var palette

    public init(fraction: Double, width: CGFloat? = nil) {
        self.fraction = fraction
        self.width = width
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.hair)
                Capsule().fill(palette.accent)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                    .animation(.linear(duration: 0.2), value: fraction)
            }
        }
        .frame(width: width, height: 5)
    }
}

/// Lets an area behave like a title bar: drag moves the window, double-click zooms.
public struct WindowDragArea: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView { DragView() }
    public func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }
}

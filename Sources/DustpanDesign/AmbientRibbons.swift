import AppKit
import SwiftUI

/// Slow "velvet strings" drifting behind the content so the app doesn't feel static. Each ribbon is a bundle of
/// thin strings that twist like folded fabric over a soft glow.
///
/// The ribbons are drawn once into images and moved by Core Animation, which runs in the window server: the app
/// itself spends no CPU on them between resizes. Under Reduce Motion they're drawn but don't move.
public struct AmbientRibbons: NSViewRepresentable {
    let colors: [Color]
    let intensity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(colors: [Color], intensity: Double = 1) {
        self.colors = colors
        self.intensity = intensity
    }

    public func makeNSView(context: Context) -> RibbonsView { RibbonsView() }

    public func updateNSView(_ view: RibbonsView, context: Context) {
        view.configure(colors: colors.map { NSColor($0) }, intensity: intensity, moves: !reduceMotion)
    }
}

public final class RibbonsView: NSView {
    private struct Ribbon {
        /// Resting height, as a fraction of the view.
        let y: CGFloat
        /// Wave height, as a fraction of the view.
        let amplitude: CGFloat
        /// Whole waves per view width, so the strip repeats seamlessly as it drifts.
        let waves: (CGFloat, CGFloat)
        let phase: CGFloat
        let strings: Int
        /// Points between neighbouring strings where the ribbon is widest.
        let spread: CGFloat
        let color: Int
        /// Seconds to drift one view width; negative drifts the other way.
        let drift: CFTimeInterval
        /// Seconds for one slow rise and fall, and one widen and narrow.
        let sway: CFTimeInterval
        let breathe: CFTimeInterval
    }

    private static let ribbons = [
        Ribbon(y: 0.28, amplitude: 0.08, waves: (1, 2), phase: 0.0, strings: 18, spread: 4.5, color: 0, drift: 140, sway: 19, breathe: 23),
        Ribbon(y: 0.60, amplitude: 0.11, waves: (1, 3), phase: 2.1, strings: 24, spread: 5.5, color: 1, drift: -190, sway: 26, breathe: 31),
        Ribbon(y: 0.86, amplitude: 0.06, waves: (2, 3), phase: 4.0, strings: 14, spread: 4, color: 2, drift: 160, sway: 17, breathe: 29),
    ]

    private var colors: [NSColor] = []
    /// sRGB components of `colors`: NSColors bridged from SwiftUI are new objects on every update and never
    /// compare equal, which would redraw the ribbons on every SwiftUI refresh.
    private var colorKey: [CGFloat] = []
    private var intensity = 1.0
    private var moves = true
    private var renderedSize = CGSize.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override public func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(colors: [NSColor], intensity: Double, moves: Bool) {
        let key = colors.flatMap { color -> [CGFloat] in
            guard let rgb = color.usingColorSpace(.sRGB) else { return [-1] }
            return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
        }
        guard key != colorKey || intensity != self.intensity || moves != self.moves else { return }
        colorKey = key
        self.colors = colors
        self.intensity = intensity
        self.moves = moves
        rebuild()
    }

    override public func layout() {
        super.layout()
        if bounds.size != renderedSize { rebuild() }
    }

    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuild()
    }

    private func rebuild() {
        guard let host = layer, bounds.width > 1, bounds.height > 1, !colors.isEmpty else { return }
        renderedSize = bounds.size
        host.sublayers?.forEach { $0.removeFromSuperlayer() }
        let scale = window?.backingScaleFactor ?? 2

        // Fade at the left and right so ribbons drift in and out rather than being cut off.
        let fade = CAGradientLayer()
        fade.frame = bounds
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.clear, .black, .black, .clear].map(\.cgColor)
        fade.locations = [0, 0.22, 0.78, 1]
        host.mask = fade

        for ribbon in Self.ribbons {
            let (image, bandHeight) = render(ribbon, width: bounds.width, height: bounds.height, scale: scale)
            let strip = CALayer()
            strip.contents = image
            strip.contentsScale = scale
            strip.anchorPoint = CGPoint(x: 0, y: 0.5)
            strip.bounds = CGRect(x: 0, y: 0, width: bounds.width * 2, height: bandHeight)
            strip.position = CGPoint(x: 0, y: bounds.height * (1 - ribbon.y))
            host.addSublayer(strip)
            if moves { animate(strip, ribbon) }
        }
    }

    private func animate(_ strip: CALayer, _ ribbon: Ribbon) {
        let width = bounds.width
        let drift = CABasicAnimation(keyPath: "position.x")
        drift.fromValue = ribbon.drift > 0 ? 0 : -width
        drift.toValue = ribbon.drift > 0 ? -width : 0
        drift.duration = abs(ribbon.drift)
        drift.repeatCount = .infinity

        let sway = CABasicAnimation(keyPath: "transform.translation.y")
        sway.fromValue = -bounds.height * 0.025
        sway.toValue = bounds.height * 0.025
        sway.duration = ribbon.sway
        sway.autoreverses = true
        sway.repeatCount = .infinity
        sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // Widening and narrowing reads as the fabric slowly turning.
        let breathe = CABasicAnimation(keyPath: "transform.scale.y")
        breathe.fromValue = 0.82
        breathe.toValue = 1.12
        breathe.duration = ribbon.breathe
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        strip.add(drift, forKey: "drift")
        strip.add(sway, forKey: "sway")
        strip.add(breathe, forKey: "breathe")
    }

    /// Draws one ribbon across two view widths. Its shape repeats every view width, so drifting by one width loops.
    private func render(_ ribbon: Ribbon, width: CGFloat, height: CGFloat, scale: CGFloat) -> (CGImage?, CGFloat) {
        let amplitude = ribbon.amplitude * height
        let halfBundle = ribbon.spread * CGFloat(ribbon.strings) / 2
        let glowWidth = ribbon.spread * CGFloat(ribbon.strings) * 0.8 * 2.2
        let bandHeight = ceil((amplitude * 1.3 + halfBundle + glowWidth / 2) * 2)
        let stripWidth = width * 2
        guard let context = CGContext(data: nil, width: Int(stripWidth * scale), height: Int(bandHeight * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (nil, bandHeight) }
        context.scaleBy(x: scale, y: scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let color = colors[ribbon.color % colors.count]
        let middle = CGFloat(ribbon.strings - 1) / 2
        func path(string: CGFloat) -> CGPath {
            let path = CGMutablePath()
            for x in stride(from: CGFloat(0), through: stripWidth, by: 8) {
                let u = x / width
                let wave = sin(u * .pi * 2 * ribbon.waves.0 + ribbon.phase) * amplitude
                    + sin(u * .pi * 2 * ribbon.waves.1 + ribbon.phase * 1.3) * amplitude * 0.3
                // Signed, so the bundle narrows to a pinch and flips over like a twisted ribbon.
                let twist = sin(u * .pi * 2 + ribbon.phase)
                let point = CGPoint(x: x, y: bandHeight / 2 + wave + (string - middle) * ribbon.spread * twist)
                x == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            return path
        }

        // A soft glow under the strings, from a few wide, faint strokes.
        let body = path(string: middle)
        for (widthScale, opacity) in [(2.2, 0.025), (1.5, 0.035), (0.9, 0.045)] {
            context.addPath(body)
            context.setLineWidth(ribbon.spread * CGFloat(ribbon.strings) * 0.8 * widthScale)
            context.setStrokeColor(color.withAlphaComponent(opacity * intensity).cgColor)
            context.strokePath()
        }
        for string in 0..<ribbon.strings {
            // Strings at the ribbon's edges are fainter, which gives it a soft, velvety body.
            let edge = sin(.pi * CGFloat(string) / CGFloat(max(ribbon.strings - 1, 1)))
            context.addPath(path(string: CGFloat(string)))
            context.setLineWidth(0.7)
            context.setStrokeColor(color.withAlphaComponent((0.12 + 0.3 * edge) * intensity).cgColor)
            context.strokePath()
        }
        return (context.makeImage(), bandHeight)
    }
}

import SwiftUI

/// The fanous from the child's world, drawn flat: navy enamel cap and base,
/// a brass frame, and amber glass that fills with light as `level` goes
/// from 0 to 1. It shows how far the headset's lantern has charged, never
/// anything about the treatment itself.
///
/// The light eases between levels; when full, a few stars twinkle slowly.
/// Under Reduce Motion both are still.
struct LanternProgressView: View {
    /// 0 is unlit, 1 is fully charged.
    var level: Double
    /// Draw the decorative stars around the lantern.
    var showsStars = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var twinkle = false

    private var lit: Double { min(max(level, 0), 1) }
    private var isFull: Bool { lit >= 0.999 }

    var body: some View {
        ZStack {
            // Halo behind the glass: a gradient, not a blur, so it costs nothing to redraw.
            Ellipse()
                .fill(EllipticalGradient(colors: [Palette.brightGold.opacity(0.6), Palette.gold.opacity(0.18), .clear],
                                         center: UnitPoint(x: 0.5, y: 0.55),
                                         startRadiusFraction: 0, endRadiusFraction: 0.5))
                .scaleEffect(1.5)
                .opacity(lit)

            // Enamel cap, collar and base.
            FanousShape.enamel
                .fill(LinearGradient(colors: [Palette.elevated, Palette.background],
                                     startPoint: .top, endPoint: .bottom))
            FanousShape.enamel
                .stroke(brass, lineWidth: 1.5)

            // Glass: cool and dark when unlit, warming to amber.
            FanousShape.glass
                .fill(Palette.coolBlue.opacity(0.16))
            FanousShape.glass
                .fill(EllipticalGradient(colors: [Palette.text, Palette.brightGold, Palette.gold, Palette.brass],
                                         center: UnitPoint(x: 0.5, y: 0.55),
                                         startRadiusFraction: 0, endRadiusFraction: 0.75))
                .opacity(0.06 + 0.94 * lit)
                .saturation(0.4 + 0.6 * lit)

            // Brass frame over the glass: outline, ribs, waist and arch.
            FanousShape.frame
                .stroke(brass, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            FanousShape.filigree
                .stroke(Palette.brightGold.opacity(0.55), style: StrokeStyle(lineWidth: 1, lineCap: .round))

            if showsStars { stars }
        }
        .aspectRatio(FanousShape.aspect, contentMode: .fit)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: lit)
        .onAppear { updateTwinkle() }
        .onChange(of: isFull) { _, _ in updateTwinkle() }
        .onChange(of: reduceMotion) { _, _ in updateTwinkle() }
        .accessibilityElement()
        .accessibilityLabel("Lantern")
        .accessibilityValue("\(Int((lit * 100).rounded())) percent lit")
    }

    private var brass: LinearGradient {
        LinearGradient(colors: [Palette.brightGold, Palette.gold, Palette.brass],
                       startPoint: .top, endPoint: .bottom)
    }

    /// Four sparkles in fixed spots. Faint until the lantern is full.
    private var stars: some View {
        GeometryReader { geo in
            let spots: [(x: Double, y: Double, size: Double, phase: Bool)] = [
                (0.06, 0.30, 0.10, true), (0.95, 0.22, 0.08, false),
                (0.02, 0.70, 0.07, false), (0.98, 0.62, 0.11, true),
            ]
            ForEach(spots.indices, id: \.self) { i in
                let spot = spots[i]
                let size = geo.size.width * spot.size
                Sparkle()
                    .fill(Palette.brightGold)
                    .frame(width: size, height: size)
                    .position(x: geo.size.width * spot.x, y: geo.size.height * spot.y)
                    .opacity(starOpacity(phase: spot.phase))
            }
        }
        .allowsHitTesting(false)
    }

    private func starOpacity(phase: Bool) -> Double {
        guard isFull else { return 0.15 + 0.35 * lit }
        if reduceMotion { return 0.85 }
        return (twinkle == phase) ? 0.95 : 0.4
    }

    private func updateTwinkle() {
        guard isFull, !reduceMotion else {
            twinkle = false
            return
        }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            twinkle = true
        }
    }
}

/// The lantern's parts, in a 120 by 200 drawing scaled to the frame.
nonisolated enum FanousShape {
    static let aspect: CGFloat = 120 / 200

    /// Finial ring, onion dome, collar band, base and foot.
    static let enamel = Drawing { d in
        var p = Path()
        p.addEllipse(in: d.rect(54, 2, 12, 12))
        p.move(to: d.pt(60, 14))
        p.addCurve(to: d.pt(24, 50), control1: d.pt(56, 26), control2: d.pt(26, 32))
        p.addLine(to: d.pt(96, 50))
        p.addCurve(to: d.pt(60, 14), control1: d.pt(94, 32), control2: d.pt(64, 26))
        p.closeSubpath()
        p.addRoundedRect(in: d.rect(16, 50, 88, 9), cornerSize: d.size(3, 3))
        p.addRoundedRect(in: d.rect(26, 160, 68, 9), cornerSize: d.size(3, 3))
        p.move(to: d.pt(32, 169))
        p.addLine(to: d.pt(88, 169))
        p.addLine(to: d.pt(72, 186))
        p.addLine(to: d.pt(60, 196))
        p.addLine(to: d.pt(48, 186))
        p.closeSubpath()
        return p
    }

    /// The glass body: widest at the waist, tapering to the base.
    static let glass = Drawing { d in
        var p = Path()
        p.move(to: d.pt(22, 59))
        p.addLine(to: d.pt(98, 59))
        p.addLine(to: d.pt(108, 112))
        p.addLine(to: d.pt(92, 160))
        p.addLine(to: d.pt(28, 160))
        p.addLine(to: d.pt(12, 112))
        p.closeSubpath()
        return p
    }

    /// Outline of the glass, two ribs and the waist band.
    static let frame = Drawing { d in
        var p = glass.path(in: d.bounds)
        p.move(to: d.pt(46, 59)); p.addLine(to: d.pt(43, 112)); p.addLine(to: d.pt(49, 160))
        p.move(to: d.pt(74, 59)); p.addLine(to: d.pt(77, 112)); p.addLine(to: d.pt(71, 160))
        p.move(to: d.pt(12, 112)); p.addLine(to: d.pt(108, 112))
        return p
    }

    /// A pointed arch in the front pane and dots along the cap.
    static let filigree = Drawing { d in
        var p = Path()
        p.move(to: d.pt(50, 106))
        p.addLine(to: d.pt(50, 84))
        p.addQuadCurve(to: d.pt(60, 68), control: d.pt(50, 72))
        p.addQuadCurve(to: d.pt(70, 84), control: d.pt(70, 72))
        p.addLine(to: d.pt(70, 106))
        p.move(to: d.pt(52, 152))
        p.addQuadCurve(to: d.pt(68, 152), control: d.pt(60, 122))
        for x in [40.0, 60, 80] {
            p.addEllipse(in: d.rect(x - 1.6, 40, 3.2, 3.2))
        }
        return p
    }

    /// A shape drawn in lantern units.
    nonisolated struct Drawing: Shape {
        let draw: @Sendable (Space) -> Path
        init(_ draw: @escaping @Sendable (Space) -> Path) { self.draw = draw }
        func path(in rect: CGRect) -> Path { draw(Space(bounds: rect)) }
    }

    nonisolated struct Space: Sendable {
        let bounds: CGRect
        private var sx: CGFloat { bounds.width / 120 }
        private var sy: CGFloat { bounds.height / 200 }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: bounds.minX + x * sx, y: bounds.minY + y * sy) }
        func size(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w * sx, height: h * sy) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(origin: pt(x, y), size: size(w, h))
        }
    }
}

/// A four-pointed star.
nonisolated struct Sparkle: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let k = r * 0.22
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - k, y: c.y - k))
        return p
    }
}

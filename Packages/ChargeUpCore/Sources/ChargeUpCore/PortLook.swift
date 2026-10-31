import Foundation
import simd

/// How the designed port (port_ring, port_plate) looks: a small amber-and-
/// brass jewel. Only its glass glows, gently and always amber. The step
/// visuals still say how bright each moment is (cream warming, frost
/// shimmer, the three countdown pulses), but those levels are scaled down
/// and capped here, so nothing overexposes in room light.
public struct PortLookConfig: Codable, Equatable, Sendable {
    /// The glass's own tint and opacity (the LanternGlass shader's
    /// glassColor and glassOpacity on the port only).
    public var glassColor: String
    public var glassOpacity: Double
    /// The glass's light: always this colour, whatever tint a step asks for.
    public var glowColor: String
    /// A step's emissive level times glowScale, never above glowMax.
    public var glowScale: Double
    public var glowMax: Double
    /// The port model sits this far below the estimated skin. The anchor is
    /// ARKit's forearm joints, which lie on the bone axis, plus
    /// forearm.forearmRadiusMm: an estimate with no skin surface behind it.
    /// The real arm never hides virtual content here
    /// (upperLimbVisibility .hidden), so sinking a little cannot show,
    /// while floating a little would.
    public var sinkMm: Double
    /// A few small golden motes drifting up from the port while it is on the arm.
    public var motes: PortMotesConfig

    public var glassRGB: SIMD3<Float> { hexRGB(glassColor) ?? SIMD3(1, 0.7, 0.28) }
    public var glowRGB: SIMD3<Float> { hexRGB(glowColor) ?? SIMD3(1, 0.65, 0.23) }
    public var sink: Float { Float(sinkMm / 1000) }

    /// The glass's emissive intensity for a step's requested level.
    public func glow(for stepLevel: Float) -> Float {
        min(Float(glowMax), max(0, stepLevel) * Float(glowScale))
    }

    func validate() -> Bool {
        hexRGB(glassColor) != nil && (0...1).contains(glassOpacity) && hexRGB(glowColor) != nil
            && glowScale > 0 && glowMax > 0 && sinkMm >= 0 && motes.validate()
    }
}

public struct PortMotesConfig: Codable, Equatable, Sendable {
    public var perSecond: Double
    public var lifeMs: Int
    public var sizeMm: Double
    /// How fast they rise off the skin.
    public var riseMmPerS: Double
    /// They are born within this radius of the port's centre.
    public var spreadMm: Double
    public var color: String

    public var rgb: SIMD3<Float> { hexRGB(color) ?? SIMD3(1, 0.82, 0.48) }
    public var life: TimeInterval { Double(lifeMs) / 1000 }

    func validate() -> Bool {
        perSecond >= 0 && lifeMs > 0 && sizeMm > 0 && riseMmPerS >= 0 && spreadMm > 0 && hexRGB(color) != nil
    }
}

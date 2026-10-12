import Foundation

/// How a step hands over to the next one.
public enum Advance: Equatable, Sendable {
    /// The nurse taps the button. `label` is what the button shows; nil means the default.
    case nurseTap(label: String?)
    /// The host advances on its own `durationMs` after the step is entered.
    case auto(durationMs: Int)

    /// The text the nurse button shows for this step.
    public var buttonLabel: String {
        switch self {
        case .nurseTap(let label): return label ?? Advance.defaultLabel
        case .auto: return Advance.defaultLabel
        }
    }

    public static let defaultLabel = "Next"

    public var isNurseTap: Bool {
        if case .nurseTap = self { return true }
        return false
    }

    public var autoDurationMs: Int? {
        if case .auto(let ms) = self { return ms }
        return nil
    }
}

extension Advance: Codable {
    private enum CodingKeys: String, CodingKey { case kind, label, durationMs }
    private enum Kind: String, Codable { case nurseTap, auto }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .nurseTap:
            self = .nurseTap(label: try c.decodeIfPresent(String.self, forKey: .label))
        case .auto:
            let ms = try c.decode(Int.self, forKey: .durationMs)
            guard ms > 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .durationMs, in: c, debugDescription: "durationMs must be > 0")
            }
            self = .auto(durationMs: ms)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .nurseTap(let label):
            try c.encode(Kind.nurseTap, forKey: .kind)
            try c.encodeIfPresent(label, forKey: .label)
        case .auto(let ms):
            try c.encode(Kind.auto, forKey: .kind)
            try c.encode(ms, forKey: .durationMs)
        }
    }
}

/// What the phone in the child's free hand does during a step.
public enum Haptic: String, Codable, Equatable, Sendable {
    case none, pulse, ramp
}

/// One row of the congruency map.
public struct Step: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var clinicalCue: String
    public var perceived: String
    public var childAction: String
    public var haptic: Haptic
    public var audio: String
    public var advance: Advance

    public init(id: String, name: String, clinicalCue: String, perceived: String,
                childAction: String, haptic: Haptic, audio: String, advance: Advance) {
        self.id = id
        self.name = name
        self.clinicalCue = clinicalCue
        self.perceived = perceived
        self.childAction = childAction
        self.haptic = haptic
        self.audio = audio
        self.advance = advance
    }
}

/// Which arm the nurse holds.
public enum HeldArm: String, Codable, Equatable, Sendable {
    case left, right
}

/// A signed local axis of a tracked joint, as written in JSON: "+y", "-z", ...
public struct SignedAxis: Codable, Equatable, Sendable {
    public enum Axis: Character, Sendable { case x = "x", y = "y", z = "z" }
    public var axis: Axis
    public var sign: Double

    public init(axis: Axis, sign: Double) {
        self.axis = axis
        self.sign = sign
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard raw.count == 2, let axis = Axis(rawValue: raw.last!), "+-".contains(raw.first!) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "axis must be one of +x -x +y -y +z -z, got '\(raw)'")
        }
        self.axis = axis
        self.sign = raw.first == "-" ? -1 : 1
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode("\(sign < 0 ? "-" : "+")\(axis.rawValue)")
    }
}

/// Everything the forearm anchor needs. Lives in config so the dorsal axis,
/// offsets and smoothing can be tuned on the arm without a code change.
public struct ForearmConfig: Codable, Equatable, Sendable {
    public var heldArm: HeldArm
    /// From the forearmWrist joint toward the elbow, along the forearm.
    public var portOffsetProximalMm: Double
    /// From the bone line out to the skin, along the dorsal axis.
    public var forearmRadiusMm: Double
    /// Which local axis of the forearmWrist joint points out of the back of the forearm.
    public var dorsalAxis: SignedAxis
    /// After tracking drops, keep the last pose this long before fading.
    public var holdLastPoseMs: Int
    /// Opacity the port fades to while tracking is lost.
    public var occludedOpacity: Double
    /// Length of the fade in either direction.
    public var fadeMs: Int
    public var filterMinCutoffHz: Double
    public var filterBeta: Double
    public var filterDerivativeCutoffHz: Double
    /// The filter never integrates a gap longer than this, so a re-acquired
    /// pose eases in over a few frames instead of snapping.
    public var filterMaxStepMs: Int

    public var portOffsetProximal: Float { Float(portOffsetProximalMm / 1000) }
    public var forearmRadius: Float { Float(forearmRadiusMm / 1000) }
    public var holdLastPose: TimeInterval { Double(holdLastPoseMs) / 1000 }
    public var fade: TimeInterval { Double(fadeMs) / 1000 }
    public var filterMaxStep: TimeInterval { Double(filterMaxStepMs) / 1000 }
}

/// Tunables shared by all three apps. Every value here is read from sequence.json.
public struct SequenceConfig: Codable, Equatable, Sendable {
    public var stillnessThresholdMps: Double
    public var stillnessWindowMs: Int
    public var headOnPortDegrees: Double
    public var chargeRatePerSecond: Double
    /// Two values: intensity at the start and at the end of the ramp, each 0...1.
    public var rampIntensity: [Double]
    public var rampSharpness: Double
    /// How long the haptic ramp takes to go from rampIntensity[0] to rampIntensity[1].
    public var rampDurationMs: Int
    public var forearm: ForearmConfig

    public var rampStartIntensity: Double { rampIntensity[0] }
    public var rampEndIntensity: Double { rampIntensity[1] }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stillnessThresholdMps = try c.decode(Double.self, forKey: .stillnessThresholdMps)
        stillnessWindowMs = try c.decode(Int.self, forKey: .stillnessWindowMs)
        headOnPortDegrees = try c.decode(Double.self, forKey: .headOnPortDegrees)
        chargeRatePerSecond = try c.decode(Double.self, forKey: .chargeRatePerSecond)
        rampIntensity = try c.decode([Double].self, forKey: .rampIntensity)
        rampSharpness = try c.decode(Double.self, forKey: .rampSharpness)
        rampDurationMs = try c.decode(Int.self, forKey: .rampDurationMs)
        forearm = try c.decode(ForearmConfig.self, forKey: .forearm)
        guard rampIntensity.count == 2, rampIntensity.allSatisfy({ (0...1).contains($0) }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .rampIntensity, in: c,
                debugDescription: "rampIntensity must be exactly two values in 0...1")
        }
        guard rampDurationMs > 0, chargeRatePerSecond > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .rampDurationMs, in: c,
                debugDescription: "rampDurationMs and chargeRatePerSecond must be > 0")
        }
        guard forearm.holdLastPoseMs >= 0, forearm.fadeMs > 0, forearm.filterMaxStepMs > 0,
              (0...1).contains(forearm.occludedOpacity), forearm.filterMinCutoffHz > 0,
              forearm.filterDerivativeCutoffHz > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .forearm, in: c, debugDescription: "forearm config values out of range")
        }
    }
}

/// Step ids the apps key behaviour on. The Vision app renders visuals by id,
/// the reducer gates `connect` on the countdown step and accrues charge on
/// the charge step. Content, order, labels and timing still come from JSON.
public enum StepID {
    public static let hold = "hold"
    public static let swab = "swab"
    public static let countdown = "countdown"
    public static let connect = "connect"
    public static let charge = "charge"
    public static let release = "release"
    public static let seal = "seal"
}

public enum SequenceError: Error, Equatable, CustomStringConvertible {
    case noSteps
    case duplicateStepId(String)
    case missingStep(String)
    case resourceMissing

    public var description: String {
        switch self {
        case .noSteps: return "sequence.json has no steps"
        case .duplicateStepId(let id): return "sequence.json has duplicate step id '\(id)'"
        case .missingStep(let id): return "sequence.json is missing required step '\(id)'"
        case .resourceMissing: return "sequence.json is not in the ChargeUpCore bundle"
        }
    }
}

/// The congruency map. Source of truth for all three apps.
public struct ChargeSequence: Codable, Equatable, Sendable {
    public var version: Int
    public var object: String
    public var steps: [Step]
    public var config: SequenceConfig

    /// Decode and validate. Throws on any missing field, bad value, duplicate
    /// id, or a missing step that the reducer depends on.
    public static func load(from data: Data) throws -> ChargeSequence {
        let decoded = try JSONDecoder().decode(ChargeSequence.self, from: data)
        try decoded.validate()
        return decoded
    }

    /// The sequence.json shipped inside the package.
    public static func shipped() throws -> ChargeSequence {
        guard let url = Bundle.module.url(forResource: "sequence", withExtension: "json") else {
            throw SequenceError.resourceMissing
        }
        return try load(from: Data(contentsOf: url))
    }

    public func validate() throws {
        guard !steps.isEmpty else { throw SequenceError.noSteps }
        var seen = Set<String>()
        for step in steps {
            guard seen.insert(step.id).inserted else { throw SequenceError.duplicateStepId(step.id) }
        }
        for required in [StepID.countdown, StepID.charge] where !seen.contains(required) {
            throw SequenceError.missingStep(required)
        }
    }

    public func index(of stepId: String) -> Int? {
        steps.firstIndex { $0.id == stepId }
    }

    public func step(id: String) -> Step? {
        steps.first { $0.id == id }
    }
}

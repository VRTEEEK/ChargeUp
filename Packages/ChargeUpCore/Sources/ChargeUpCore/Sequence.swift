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

/// A slow closed path the port follows when there is no hand tracking (the
/// simulator, or a desk test). Metres from the space origin at the floor.
public struct SimulatedPathConfig: Codable, Equatable, Sendable {
    public var center: [Double]
    public var radiusMm: Double
    public var periodS: Double
    /// Skin normal of the fake forearm, so the port faces somewhere sensible.
    public var normal: [Double]

    public var centre: SIMD3<Float> { SIMD3(Float(center[0]), Float(center[1]), Float(center[2])) }
    public var radius: Float { Float(radiusMm / 1000) }
    public var normalVector: SIMD3<Float> { SIMD3(Float(normal[0]), Float(normal[1]), Float(normal[2])) }
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
    /// When hand tracking is unsupported on this device, drive the port along
    /// `simulatedPath` and report the child as still and looking at the port.
    public var simulatedForearm: Bool
    public var simulatedPath: SimulatedPathConfig

    public var portOffsetProximal: Float { Float(portOffsetProximalMm / 1000) }
    public var forearmRadius: Float { Float(forearmRadiusMm / 1000) }
    public var holdLastPose: TimeInterval { Double(holdLastPoseMs) / 1000 }
    public var fade: TimeInterval { Double(fadeMs) / 1000 }
    public var filterMaxStep: TimeInterval { Double(filterMaxStepMs) / 1000 }
}

/// The lantern sky: every completed session's lantern, kept on the headset.
public struct SkyConfig: Codable, Equatable, Sendable {
    /// Fake past sessions written on first launch so the demo sky is not empty.
    public var seededSessions: Int
    /// How long the current lantern takes to rise into the cluster at release.
    public var riseSeconds: Double
    /// Cluster placement relative to the current lantern: up, back, and side spread.
    public var clusterHeightM: Double
    public var clusterBehindM: Double
    public var clusterSpreadM: Double
    /// Scale of a sky lantern relative to the current one.
    public var smallScale: Double

    public var rise: TimeInterval { riseSeconds }
}

/// How the lantern fills during the infusion. Time-based by default: a
/// real infusion runs for hours, the demo compresses it to demoDurationSec.
public struct ChargeConfig: Codable, Equatable, Sendable {
    /// When true, the fill only advances while armStill and headOnPort (the
    /// original needle-moment rule). Off for the chemotherapy session.
    public var gatedByPresence: Bool
    /// Seconds for the fill to go from 0 to 1 while advancing.
    public var demoDurationSec: Double
    /// Nice to have: when the head turns to within this angle of the lantern
    /// during charge, the lantern brightens briefly and shows its fill.
    public var glanceDegrees: Double
    /// How long that brightening takes to settle.
    public var glanceSeconds: Double

    public var ratePerSecond: Double { 1 / demoDurationSec }
}

/// Timings and counts for the per-step visuals. Each maps to a row's
/// "perceived" text; nothing here invents a visual.
public struct VisualsConfig: Codable, Equatable, Sendable {
    /// cream: the port glow grows under the skin over this long.
    public var creamGlowMs: Int
    /// countdown: this many pulses of light, this far apart.
    public var countdownPulseCount: Int
    public var countdownPulseMs: Int
    /// connect: the cable reaches the port in this long.
    public var cableSnapMs: Int
    /// flush: the first spark takes this long to climb the cable.
    public var flushSparkMs: Int
    /// release: the cable pulls back in this long.
    public var cableRetractMs: Int
    /// release: the mark fades onto the dressing over this long.
    public var markFadeMs: Int
    /// charge: energy packets along the cable, and their speed while flowing.
    public var flowPacketCount: Int
    public var flowSpeedMps: Double
    /// swab: sparkles orbiting the port.
    public var frostSparkleCount: Int

    public var creamGlow: TimeInterval { Double(creamGlowMs) / 1000 }
    public var flushSpark: TimeInterval { Double(flushSparkMs) / 1000 }
    public var countdownPulse: TimeInterval { Double(countdownPulseMs) / 1000 }
    public var cableSnap: TimeInterval { Double(cableSnapMs) / 1000 }
    public var cableRetract: TimeInterval { Double(cableRetractMs) / 1000 }
    public var markFade: TimeInterval { Double(markFadeMs) / 1000 }
}

/// Two spatial sources: per-step sounds at the port, the flow loop at the
/// lantern. Which ids go to the lantern and which loop is data, not code.
public struct AudioConfig: Codable, Equatable, Sendable {
    public var portGainDb: Double
    public var lanternGainDb: Double
    /// Audio ids played at the lantern instead of the port.
    public var lanternSounds: [String]
    /// Audio ids that loop until the step changes.
    public var loopingSounds: [String]

    public func playsAtLantern(_ id: String) -> Bool { lanternSounds.contains(id) }
    public func loops(_ id: String) -> Bool { loopingSounds.contains(id) }
}

/// Where the charge object sits. Placed once at session start from the
/// head pose, then world-anchored so it does not follow the head.
public struct LanternConfig: Codable, Equatable, Sendable {
    /// Distance in front of the head along its forward direction on the floor plane.
    public var forwardM: Double
    /// Drop from head height to chest height.
    public var belowHeadM: Double
    /// Head height to assume if no device pose arrives (simulator, desk test).
    public var fallbackHeadHeightM: Double
    /// How long to wait for the first device pose before using the fallback.
    public var headPoseWaitMs: Int
    /// Used instead of forwardM / belowHeadM while the simulated forearm is
    /// active, so the lantern sits inside the simulator's fixed camera frame.
    public var simulatedForwardM: Double
    public var simulatedBelowHeadM: Double

    public var forward: Float { Float(forwardM) }
    public var belowHead: Float { Float(belowHeadM) }
    public var fallbackHeadHeight: Float { Float(fallbackHeadHeightM) }
    public var headPoseWait: TimeInterval { Double(headPoseWaitMs) / 1000 }
}

/// Tunables shared by all three apps. Every value here is read from sequence.json.
public struct SequenceConfig: Codable, Equatable, Sendable {
    public var visuals: VisualsConfig
    public var audio: AudioConfig
    public var lantern: LanternConfig
    public var sky: SkyConfig
    public var charge: ChargeConfig
    public var stillnessThresholdMps: Double
    public var stillnessWindowMs: Int
    public var headOnPortDegrees: Double
    /// Two values: intensity at the start and at the end of the ramp, each 0...1.
    public var rampIntensity: [Double]
    public var rampSharpness: Double
    /// How long the haptic ramp takes to go from rampIntensity[0] to rampIntensity[1].
    public var rampDurationMs: Int
    /// Rehearsal mode on the nurse app taps the button this often.
    public var rehearsalIntervalMs: Int
    public var forearm: ForearmConfig

    public var rehearsalInterval: TimeInterval { Double(rehearsalIntervalMs) / 1000 }

    public var rampStartIntensity: Double { rampIntensity[0] }
    public var rampEndIntensity: Double { rampIntensity[1] }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        visuals = try c.decode(VisualsConfig.self, forKey: .visuals)
        audio = try c.decode(AudioConfig.self, forKey: .audio)
        lantern = try c.decode(LanternConfig.self, forKey: .lantern)
        sky = try c.decode(SkyConfig.self, forKey: .sky)
        charge = try c.decode(ChargeConfig.self, forKey: .charge)
        stillnessThresholdMps = try c.decode(Double.self, forKey: .stillnessThresholdMps)
        stillnessWindowMs = try c.decode(Int.self, forKey: .stillnessWindowMs)
        headOnPortDegrees = try c.decode(Double.self, forKey: .headOnPortDegrees)
        rampIntensity = try c.decode([Double].self, forKey: .rampIntensity)
        rampSharpness = try c.decode(Double.self, forKey: .rampSharpness)
        rampDurationMs = try c.decode(Int.self, forKey: .rampDurationMs)
        rehearsalIntervalMs = try c.decode(Int.self, forKey: .rehearsalIntervalMs)
        forearm = try c.decode(ForearmConfig.self, forKey: .forearm)
        guard rampIntensity.count == 2, rampIntensity.allSatisfy({ (0...1).contains($0) }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .rampIntensity, in: c,
                debugDescription: "rampIntensity must be exactly two values in 0...1")
        }
        guard rehearsalIntervalMs > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .rehearsalIntervalMs, in: c, debugDescription: "rehearsalIntervalMs must be > 0")
        }
        guard rampDurationMs > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .rampDurationMs, in: c, debugDescription: "rampDurationMs must be > 0")
        }
        guard sky.seededSessions >= 0, sky.riseSeconds > 0, sky.smallScale > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .sky, in: c, debugDescription: "sky config values out of range")
        }
        guard charge.demoDurationSec > 0, charge.glanceDegrees > 0, charge.glanceSeconds > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .charge, in: c, debugDescription: "charge config values must be > 0")
        }
        guard visuals.countdownPulseCount > 0, visuals.countdownPulseMs > 0, visuals.cableSnapMs > 0,
              visuals.cableRetractMs > 0, visuals.markFadeMs > 0, visuals.creamGlowMs > 0, visuals.flushSparkMs > 0,
              visuals.flowPacketCount > 0, visuals.flowSpeedMps > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .visuals, in: c, debugDescription: "visuals config values must be > 0")
        }
        guard forearm.holdLastPoseMs >= 0, forearm.fadeMs > 0, forearm.filterMaxStepMs > 0,
              (0...1).contains(forearm.occludedOpacity), forearm.filterMinCutoffHz > 0,
              forearm.filterDerivativeCutoffHz > 0, forearm.simulatedPath.center.count == 3,
              forearm.simulatedPath.normal.count == 3, forearm.simulatedPath.periodS > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .forearm, in: c, debugDescription: "forearm config values out of range")
        }
    }
}

/// Step ids the apps key behaviour on. The Vision app renders visuals by id,
/// the reducer gates `connect` on the countdown step and accrues charge on
/// the charge step. Content, order, labels and timing still come from JSON.
public enum StepID {
    public static let cream = "cream"
    public static let clean = "clean"
    public static let countdown = "countdown"
    public static let connect = "connect"
    public static let flush = "flush"
    public static let charge = "charge"
    public static let release = "release"
}

public enum SequenceError: Error, Equatable, CustomStringConvertible {
    case noSteps
    case duplicateStepId(String)
    case missingStep(String)
    case missingPrompt(String)
    case resourceMissing

    public var description: String {
        switch self {
        case .noSteps: return "sequence.json has no steps"
        case .duplicateStepId(let id): return "sequence.json has duplicate step id '\(id)'"
        case .missingStep(let id): return "sequence.json is missing required step '\(id)'"
        case .missingPrompt(let id): return "sequence.json prompts has no line for '\(id)'"
        case .resourceMissing: return "sequence.json is not in the ChargeUpCore bundle"
        }
    }
}

/// The congruency map. Source of truth for all three apps.
public struct ChargeSequence: Codable, Equatable, Sendable {
    public var version: Int
    public var object: String
    public var steps: [Step]
    /// What the parent says, keyed by step id plus `idle` and `complete`.
    public var prompts: [String: String]
    public var config: SequenceConfig

    /// The parent's line for a step id or session marker. Empty if none.
    public func prompt(for id: String) -> String { prompts[id] ?? "" }

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
        for id in steps.map(\.id) + [SessionMarker.idle, SessionMarker.complete]
        where (prompts[id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            throw SequenceError.missingPrompt(id)
        }
    }

    /// Every audio id any step names, in step order, without duplicates.
    public var audioIds: [String] {
        var seen = Set<String>()
        return steps.map(\.audio).filter { seen.insert($0).inserted }
    }

    public func index(of stepId: String) -> Int? {
        steps.firstIndex { $0.id == stepId }
    }

    public func step(id: String) -> Step? {
        steps.first { $0.id == id }
    }
}

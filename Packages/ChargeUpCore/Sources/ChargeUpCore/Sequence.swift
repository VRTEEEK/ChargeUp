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

/// What the companion character does during a step. Absent means idle.
public enum CompanionCue: String, Codable, Equatable, Sendable {
    /// Fade in, then one Agree clip.
    case appear
    /// First frame of Agree held still, plus the bob.
    case idle
    /// One Agree clip sped to the countdown pulses, then frozen on its last frame.
    case agreeHold
    /// Keep whatever frame is showing (connect: still frozen from the countdown).
    case hold
    /// Idle plus the slow turn toward the lantern every turnEverySMin...Max seconds.
    case charging
    /// One Cheer clip, then one Heart clip as the lantern rises.
    case cheerHeart
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
    /// Optional; nil means the companion idles.
    public var companion: CompanionCue?

    public init(id: String, name: String, clinicalCue: String, perceived: String,
                childAction: String, haptic: Haptic, audio: String, advance: Advance,
                companion: CompanionCue? = nil) {
        self.id = id
        self.name = name
        self.clinicalCue = clinicalCue
        self.perceived = perceived
        self.childAction = childAction
        self.haptic = haptic
        self.audio = audio
        self.advance = advance
        self.companion = companion
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

/// The companion character beside the lantern. Off unless enabled.
public struct CompanionConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Standing height in metres after scaling.
    public var heightM: Double
    /// Gap between the lantern's side and the character.
    public var gapM: Double
    /// Fade-in length at the appear cue.
    public var fadeS: Double
    /// Procedural bob while idle.
    public var bobAmplitudeM: Double
    public var bobPeriodS: Double
    /// During charge: a slow turn toward the lantern at a random interval in this range.
    public var turnEverySMin: Double
    public var turnEverySMax: Double
    public var turnDurationS: Double
    public var turnHoldS: Double

    public var height: Float { Float(heightM) }
    public var gap: Float { Float(gapM) }
    public var bobAmplitude: Float { Float(bobAmplitudeM) }
}

/// The textured replacement over the access site: a tube around the forearm
/// (arm) or a flat surround under the plate (chest). The tile is a PNG slot
/// name; sleeve_tile_soft falls back to sleeve_tile when the file is absent.
public struct SleeveConfig: Codable, Equatable, Sendable {
    public var tile: String
    /// 0...1 opacity of the tiled surface.
    public var opacity: Double
    /// Arm: length of the tube along the forearm, centred on the port.
    public var lengthMm: Double
    /// How many times the tile repeats around the tube / across the surround.
    public var tileRepeat: Double
    /// Chest: width and height of the surround under the plate.
    public var surroundSizeMm: [Double]

    public var length: Float { Float(lengthMm / 1000) }
    public var surroundSize: SIMD2<Float> { SIMD2(Float(surroundSizeMm[0]), Float(surroundSizeMm[1])) / 1000 }
}

/// Per-slot tweaks for designed assets, keyed by slot file name.
public struct AssetOverride: Codable, Equatable, Sendable {
    /// When false, the Glass shader's fill is held at 1 so the glow is a
    /// constant emissive with no UV mask (for small domes where a mask
    /// would read as the whole thing switching on at once).
    public var glassMask: Bool

    public init(glassMask: Bool = true) { self.glassMask = glassMask }
}

/// Where the needle goes. `arm` uses the forearm hand-tracking anchor and the
/// sleeve; `chestPort` uses a printed marker on the port dressing and a plate.
public enum AccessSite: String, Codable, Equatable, Sendable {
    case arm, chestPort
}

/// The chest port: a high-contrast marker stuck to the dressing, tracked
/// with ARKit image tracking, and an offset from the marker centre to the
/// port itself. Untested on a device.
public struct ChestPortConfig: Codable, Equatable, Sendable {
    /// Bundle image name (PNG) that matches docs/port-marker.pdf.
    public var markerImage: String
    /// Printed side length. The PDF is laid out to this size at 100 %.
    public var markerSizeMm: Double
    /// Which local axis of the image anchor points out of the marker toward the viewer.
    public var markerNormalAxis: SignedAxis
    /// From marker centre to the port, in the marker's own frame (x along the
    /// marker's width, y along its normal, z along its height), millimetres.
    public var portOffsetFromMarkerMm: [Double]
    /// The soft-edged plate drawn over the dressing area, width and height.
    public var plateSizeMm: [Double]

    public var markerSize: Float { Float(markerSizeMm / 1000) }
    public var portOffset: SIMD3<Float> {
        SIMD3(Float(portOffsetFromMarkerMm[0]), Float(portOffsetFromMarkerMm[1]), Float(portOffsetFromMarkerMm[2])) / 1000
    }
    public var plateSize: SIMD2<Float> { SIMD2(Float(plateSizeMm[0]), Float(plateSizeMm[1])) / 1000 }
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
    /// Emissive intensity of a designed lantern's Glass shader (glowIntensity)
    /// in each state; glowGlance is added while the child looks at it during
    /// the infusion. The procedural placeholder has its own fixed values.
    public var glowDark: Double
    public var glowCharging: Double
    public var glowGlance: Double
    public var glowLit: Double

    public var forward: Float { Float(forwardM) }
    public var belowHead: Float { Float(belowHeadM) }
    public var fallbackHeadHeight: Float { Float(fallbackHeadHeightM) }
    public var headPoseWait: TimeInterval { Double(headPoseWaitMs) / 1000 }
}

/// Tunables shared by all three apps. Every value here is read from sequence.json.
public struct SequenceConfig: Codable, Equatable, Sendable {
    public var companion: CompanionConfig
    public var accessSite: AccessSite
    public var sleeve: SleeveConfig
    /// Keyed by asset slot name; absent means defaults.
    public var assetOverrides: [String: AssetOverride]
    public var chestPort: ChestPortConfig
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
        companion = try c.decode(CompanionConfig.self, forKey: .companion)
        accessSite = try c.decode(AccessSite.self, forKey: .accessSite)
        sleeve = try c.decode(SleeveConfig.self, forKey: .sleeve)
        assetOverrides = try c.decodeIfPresent([String: AssetOverride].self, forKey: .assetOverrides) ?? [:]
        chestPort = try c.decode(ChestPortConfig.self, forKey: .chestPort)
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
        guard lantern.glowDark >= 0, lantern.glowCharging >= 0, lantern.glowGlance >= 0, lantern.glowLit >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .lantern, in: c, debugDescription: "lantern glow values must be >= 0")
        }
        guard sky.seededSessions >= 0, sky.riseSeconds > 0, sky.smallScale > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .sky, in: c, debugDescription: "sky config values out of range")
        }
        guard charge.demoDurationSec > 0, charge.glanceDegrees > 0, charge.glanceSeconds > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .charge, in: c, debugDescription: "charge config values must be > 0")
        }
        guard companion.heightM > 0, companion.fadeS > 0, companion.bobPeriodS > 0,
              companion.turnEverySMin > 0, companion.turnEverySMax >= companion.turnEverySMin,
              companion.turnDurationS > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .companion, in: c, debugDescription: "companion config out of range")
        }
        guard (0...1).contains(sleeve.opacity), sleeve.lengthMm > 0, sleeve.tileRepeat > 0,
              sleeve.surroundSizeMm.count == 2, ["sleeve_tile", "sleeve_tile_soft"].contains(sleeve.tile) else {
            throw DecodingError.dataCorruptedError(
                forKey: .sleeve, in: c, debugDescription: "sleeve config out of range or unknown tile")
        }
        guard chestPort.markerSizeMm > 0, chestPort.portOffsetFromMarkerMm.count == 3,
              chestPort.plateSizeMm.count == 2, !chestPort.markerImage.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .chestPort, in: c, debugDescription: "chestPort config values out of range")
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

/// Languages every prompt must carry. Decoding fails if one is missing.
public enum PromptLanguage: String, Codable, CaseIterable, Sendable {
    case en, ar

    public var isRightToLeft: Bool { self == .ar }
    public var localeIdentifier: String { rawValue }
}

/// One line the parent reads out, in every language.
public struct Prompt: Codable, Equatable, Sendable {
    public var en: String
    public var ar: String

    public init(en: String, ar: String) {
        self.en = en
        self.ar = ar
    }

    public func text(_ language: PromptLanguage) -> String {
        switch language {
        case .en: return en
        case .ar: return ar
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
    /// What the parent says, keyed by step id plus `idle` and `complete`, in every language.
    public var prompts: [String: Prompt]
    public var config: SequenceConfig

    /// The parent's line for a step id or session marker. Empty if none.
    public func prompt(for id: String, in language: PromptLanguage = .en) -> String {
        prompts[id]?.text(language) ?? ""
    }

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
        for id in steps.map(\.id) + [SessionMarker.idle, SessionMarker.complete] {
            guard let p = prompts[id],
                  PromptLanguage.allCases.allSatisfy({ !p.text($0).trimmingCharacters(in: .whitespaces).isEmpty })
            else { throw SequenceError.missingPrompt(id) }
        }
    }

    /// Every audio id any step names, in step order, without duplicates.
    public var audioIds: [String] {
        var seen = Set<String>()
        return steps.map(\.audio).filter { seen.insert($0).inserted }
    }

    /// The override for a slot, or defaults.
    public func assetOverride(_ slot: String) -> AssetOverride {
        config.assetOverrides[slot] ?? AssetOverride()
    }

    public func index(of stepId: String) -> Int? {
        steps.firstIndex { $0.id == stepId }
    }

    public func step(id: String) -> Step? {
        steps.first { $0.id == id }
    }
}

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
    /// Fade in, wave once, then idle.
    case waveIn
    /// The breathing idle loop.
    case idle
    /// Listen, kept running across following steps that also say listen.
    case listen
    /// Look around once, then idle.
    case lookOnce
    /// Idle with an occasional variety clip (config.companion.chargeVariety).
    case charging
    /// Heart once as the lantern lights, then cheer once as it rises.
    case heartCheer
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
    /// Who it can be; the first is who it is at the start of every session.
    public var characters: [CompanionCharacter]
    /// Standing height in metres after scaling.
    public var heightM: Double
    /// Gap between the lantern's side and the character.
    public var gapM: Double
    /// Fade-in length at the waveIn cue.
    public var fadeS: Double
    /// Changing character: the old one fades out over this, the new one in.
    public var switchFadeS: Double
    /// Playback speed for every clip unless overridden.
    public var speed: Double
    /// Transition length between any two clips, including into idle.
    public var crossfadeS: Double
    /// Per-clip speed, keyed by clip name (wave, sway, cheer, ...).
    public var speedOverrides: [String: Double]
    /// During charge: one variety clip at a random interval in this range.
    public var chargeVarietyEverySMin: Double
    public var chargeVarietyEverySMax: Double
    /// Clip names drawn from, never repeating the last.
    public var chargeVariety: [String]
    /// The fidget clip plays at most this many times per session.
    public var fidgetMaxPerSession: Int
    /// Waving back at the child, and playing when touched (Wave.swift).
    public var wave: CompanionWaveConfig
    public var touch: CompanionTouchConfig
    /// Its voice is per character (CompanionCharacter.voices): for a clip
    /// named there, one of those sounds plays from its head as the clip
    /// starts, taking turns. Clips not named are silent, so it never chatters
    /// while the child rests through the infusion, nor on the countdown.
    public var voiceGainDb: Double

    /// Every voice sound, for loading.
    public var voiceIds: [String] {
        Array(Set(characters.flatMap { ($0.voices ?? [:]).values.flatMap { $0 } })).sorted()
    }
    /// Every model and clip file of every character, for loading.
    public var characterFiles: [String] {
        Array(Set(characters.flatMap { [$0.model] + $0.clips.values })).sorted()
    }

    public var height: Float { Float(heightM) }
    public var gap: Float { Float(gapM) }
    public func speed(for clip: String) -> Double { speedOverrides[clip] ?? speed }
}

/// How often the cable's tube mesh may be regenerated.
public struct CableConfig: Codable, Equatable, Sendable {
    /// Upper bound on rebuilds per second.
    public var rebuildHz: Double
    /// Either endpoint moving more than this forces a rebuild (at the rate above).
    public var moveThresholdMm: Double

    public var minInterval: TimeInterval { 1 / rebuildHz }
    public var moveThreshold: Float { Float(moveThresholdMm / 1000) }
}

public enum SleeveStyle: String, Codable, Equatable, Sendable {
    /// Placeholder tube or flat surround carrying the tile.
    case tube
    /// Soft radial glow at the port, growing along the forearm with the charge.
    case glow
    /// Nothing on the skin around the port: the port alone, as a jewel.
    case none
}

/// The glow style's numbers.
public struct SiteGlowConfig: Codable, Equatable, Sendable {
    /// How faintly the tile shows inside the glow.
    public var tileOpacity: Double
    /// Extent along the forearm at zero and at full charge.
    public var extentMinMm: Double
    public var extentMaxMm: Double
    /// Across the forearm.
    public var widthMm: Double
    /// Chest: disc diameter around the dome.
    public var chestDiscMm: Double
    /// How much brighter a countdown pulse makes it (0 = none).
    public var pulseGain: Double
    public var intensity: Double

    public var extentMin: Float { Float(extentMinMm / 1000) }
    public var extentMax: Float { Float(extentMaxMm / 1000) }
    public var width: Float { Float(widthMm / 1000) }
    public var chestDisc: Float { Float(chestDiscMm / 1000) }
}

/// The textured replacement over the access site: a tube around the forearm
/// (arm) or a flat surround under the plate (chest). The tile is a PNG slot
/// name; sleeve_tile_soft falls back to sleeve_tile when the file is absent.
public struct SleeveConfig: Codable, Equatable, Sendable {
    public var style: SleeveStyle
    public var tile: String
    public var glow: SiteGlowConfig
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
    /// The energy stream's pace while flowing, as a fraction of the path per
    /// second, so a jittering arm that stretches or shortens the path does
    /// not change it.
    public var flowCableFractionPerSecond: Double
    /// Each firefly fades in over this first fraction of the path and out
    /// over the same last fraction, so none pops at either end.
    public var flowFadeFraction: Double
    /// The energy stream (EnergyPath, FireflySwarm): golden fireflies flowing
    /// along a cubic Bezier from the port's glass into the lantern's glass,
    /// over a very thin, faint amber core that breathes.
    /// Each control arm of the path as a fraction of its span.
    public var streamBend: Double
    /// The stream leaves the port this far above the skin, out of the glass.
    public var streamPortLiftMm: Double
    /// The core: diameter, opacity, and a slow breathing of that opacity.
    public var streamCoreMm: Double
    public var streamCoreOpacity: Double
    public var streamPulseHz: Double
    public var streamPulseDepth: Double
    /// The fireflies: how many at once, head size and its spread, speed
    /// spread, how far they wander off the path, colours (amber and pale
    /// gold), and the short soft trail each leaves.
    public var fireflyCount: Int
    public var fireflySizeMm: Double
    public var fireflySizeJitter: Double
    public var fireflySpeedJitter: Double
    public var fireflyWanderMm: Double
    public var fireflyColors: [String]
    public var fireflyTrailPerSecond: Double
    public var fireflyTrailLifeMs: Int
    /// The flush step's single first spark: a firefly this many times larger.
    public var sparkScale: Double
    /// The badge left on the arm where the port was (charge_mark): this long
    /// along the forearm, its width from the image's own shape, self-lit in
    /// its own colours and breathing: `markGlowBase` ± `markGlowDepth` of the
    /// image's full brightness over `markGlowPeriodMs`, never above full, so
    /// it cannot wash out to white.
    public var markLengthMm: Double
    public var markGlowBase: Double
    public var markGlowDepth: Double
    public var markGlowPeriodMs: Int

    /// The badge's brightness at `time` seconds, 0...1 of the image's own.
    public func markGlow(at time: Double) -> Float {
        let b = markGlowBase + markGlowDepth * sin(2 * .pi * time * 1000 / Double(max(1, markGlowPeriodMs)))
        return Float(max(0, min(1, b)))
    }

    public func fireflyRGB(_ index: Int) -> SIMD3<Float> {
        guard !fireflyColors.isEmpty else { return SIMD3(1, 0.7, 0.28) }
        return hexRGB(fireflyColors[index % fireflyColors.count]) ?? SIMD3(1, 0.7, 0.28)
    }
    public var fireflyTrailLife: TimeInterval { Double(fireflyTrailLifeMs) / 1000 }
    public var streamPortLift: Float { Float(streamPortLiftMm / 1000) }
    /// swab: sparkles orbiting the port.
    public var frostSparkleCount: Int
    /// The skin-clean sparkles circle the port in these colours, one each,
    /// round the ring in order; each leaves a short glowing trail in its
    /// colour, `frostSparkleTrailPerSecond` specks living
    /// `frostSparkleTrailLifeMs`, so the ring reads as a circle of light.
    public var frostSparkleColors: [String]
    public var frostSparkleTrailPerSecond: Double
    public var frostSparkleTrailLifeMs: Int

    /// Colour of sparkle `index`, cycling through the palette.
    public func frostSparkleRGB(_ index: Int) -> SIMD3<Float> {
        guard !frostSparkleColors.isEmpty else { return SIMD3(0.85, 0.95, 1) }
        return hexRGB(frostSparkleColors[index % frostSparkleColors.count]) ?? SIMD3(0.85, 0.95, 1)
    }
    public var frostSparkleTrailLife: TimeInterval { Double(frostSparkleTrailLifeMs) / 1000 }
    /// The stream core's colour, "#RRGGBB".
    public var cableColor: String
    /// While charging, the lantern's light pulses: one beat every
    /// chargePulseStartMs when empty, quickening to chargePulseEndMs when
    /// full, brightness swinging chargePulseDepth either side (ChargePulse).
    public var chargePulseStartMs: Int
    public var chargePulseEndMs: Int
    public var chargePulseDepth: Double

    /// 0...1 components of cableColor.
    public var cableRGB: SIMD3<Float> {
        var hex = cableColor
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return SIMD3(1, 0.7, 0.28) }
        return SIMD3(Float((v >> 16) & 0xFF), Float((v >> 8) & 0xFF), Float(v & 0xFF)) / 255
    }

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
    /// Background music under the whole experience (MusicConfig).
    public var music: MusicConfig
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
    /// The light inside a designed lantern rises as a gradient: lightColorBottom
    /// at the base of its Glass mesh to lightColorTop at the top. glassColor
    /// tints the glass itself, lit or not. Hex, "#RRGGBB".
    public var lightColorBottom: String
    public var lightColorTop: String
    public var glassColor: String

    public var lightBottomRGB: SIMD3<Float> { hexRGB(lightColorBottom) ?? SIMD3(1, 0.42, 0.04) }
    public var lightTopRGB: SIMD3<Float> { hexRGB(lightColorTop) ?? SIMD3(1, 0.8, 0.15) }
    public var glassRGB: SIMD3<Float> { hexRGB(glassColor) ?? SIMD3(1, 0.86, 0.6) }

    public var forward: Float { Float(forwardM) }
    public var belowHead: Float { Float(belowHeadM) }
    public var fallbackHeadHeight: Float { Float(fallbackHeadHeightM) }
    public var headPoseWait: TimeInterval { Double(headPoseWaitMs) / 1000 }
}

/// Tunables shared by all three apps. Every value here is read from sequence.json.
public struct SequenceConfig: Codable, Equatable, Sendable {
    public var companion: CompanionConfig
    public var accessSite: AccessSite
    public var cable: CableConfig
    public var sleeve: SleeveConfig
    public var port: PortLookConfig
    /// Keyed by asset slot name; absent means defaults.
    public var assetOverrides: [String: AssetOverride]
    public var chestPort: ChestPortConfig
    public var visuals: VisualsConfig
    public var audio: AudioConfig
    public var lantern: LanternConfig
    public var sky: SkyConfig
    public var tree: TreeConfig
    /// Sparkles on the lantern or monkey the child's head points at.
    public var lookSparkle: LookSparkleConfig
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
        cable = try c.decode(CableConfig.self, forKey: .cable)
        sleeve = try c.decode(SleeveConfig.self, forKey: .sleeve)
        port = try c.decode(PortLookConfig.self, forKey: .port)
        assetOverrides = try c.decodeIfPresent([String: AssetOverride].self, forKey: .assetOverrides) ?? [:]
        chestPort = try c.decode(ChestPortConfig.self, forKey: .chestPort)
        visuals = try c.decode(VisualsConfig.self, forKey: .visuals)
        audio = try c.decode(AudioConfig.self, forKey: .audio)
        lantern = try c.decode(LanternConfig.self, forKey: .lantern)
        sky = try c.decode(SkyConfig.self, forKey: .sky)
        tree = try c.decode(TreeConfig.self, forKey: .tree)
        lookSparkle = try c.decode(LookSparkleConfig.self, forKey: .lookSparkle)
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
        guard lookSparkle.validate() else {
            throw DecodingError.dataCorruptedError(
                forKey: .lookSparkle, in: c, debugDescription: "lookSparkle values out of range")
        }
        guard audio.music.validate() else {
            throw DecodingError.dataCorruptedError(
                forKey: .audio, in: c, debugDescription: "audio.music values out of range")
        }
        guard lantern.glowDark >= 0, lantern.glowCharging >= 0, lantern.glowGlance >= 0, lantern.glowLit >= 0,
              hexRGB(lantern.lightColorBottom) != nil, hexRGB(lantern.lightColorTop) != nil,
              hexRGB(lantern.glassColor) != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .lantern, in: c, debugDescription: "lantern glow values must be >= 0 and its colours #RRGGBB")
        }
        guard port.validate() else {
            throw DecodingError.dataCorruptedError(
                forKey: .port, in: c, debugDescription: "port look values out of range or colours not #RRGGBB")
        }
        guard sky.seededSessions >= 0, sky.riseSeconds > 0, sky.smallScale > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .sky, in: c, debugDescription: "sky config values out of range")
        }
        guard charge.demoDurationSec > 0, charge.glanceDegrees > 0, charge.glanceSeconds > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .charge, in: c, debugDescription: "charge config values must be > 0")
        }
        guard !companion.characters.isEmpty, companion.characters.allSatisfy({ $0.validate() }),
              Set(companion.characters.map(\.name)).count == companion.characters.count,
              companion.heightM > 0, companion.fadeS > 0, companion.switchFadeS > 0, companion.speed > 0,
              companion.crossfadeS >= 0,
              companion.chargeVarietyEverySMin > 0,
              companion.chargeVarietyEverySMax >= companion.chargeVarietyEverySMin,
              !companion.chargeVariety.isEmpty, companion.fidgetMaxPerSession >= 0, companion.wave.validate(),
              companion.touch.validate(),
              companion.speedOverrides.values.allSatisfy({ $0 > 0 }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .companion, in: c, debugDescription: "companion config out of range")
        }
        guard cable.rebuildHz > 0, cable.moveThresholdMm >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .cable, in: c, debugDescription: "cable config out of range")
        }
        guard (0...1).contains(sleeve.glow.tileOpacity), sleeve.glow.extentMinMm > 0,
              sleeve.glow.extentMaxMm >= sleeve.glow.extentMinMm, sleeve.glow.widthMm > 0,
              sleeve.glow.chestDiscMm > 0, sleeve.glow.pulseGain >= 0, sleeve.glow.intensity >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .sleeve, in: c, debugDescription: "sleeve.glow config out of range")
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
              visuals.flowCableFractionPerSecond > 0, (0...0.5).contains(visuals.flowFadeFraction),
              visuals.streamBend > 0, visuals.streamPortLiftMm >= 0,
              visuals.streamCoreMm > 0, (0...1).contains(visuals.streamCoreOpacity),
              visuals.streamPulseHz >= 0, (0...1).contains(visuals.streamPulseDepth),
              visuals.fireflyCount > 0, visuals.fireflySizeMm > 0,
              (0..<1).contains(visuals.fireflySizeJitter), (0..<1).contains(visuals.fireflySpeedJitter),
              visuals.fireflyWanderMm >= 0, !visuals.fireflyColors.isEmpty,
              visuals.fireflyColors.allSatisfy({ hexRGB($0) != nil }),
              visuals.fireflyTrailPerSecond >= 0, visuals.fireflyTrailLifeMs > 0, visuals.sparkScale > 0,
              visuals.markLengthMm > 0, (0...1).contains(visuals.markGlowBase), (0...1).contains(visuals.markGlowDepth),
              visuals.markGlowPeriodMs > 0,
              visuals.cableColor.count == 7, visuals.cableColor.hasPrefix("#"),
              visuals.chargePulseStartMs > 0, visuals.chargePulseEndMs > 0,
              !visuals.frostSparkleColors.isEmpty, visuals.frostSparkleColors.allSatisfy({ hexRGB($0) != nil }),
              visuals.frostSparkleTrailPerSecond >= 0, visuals.frostSparkleTrailLifeMs > 0,
              (0...0.9).contains(visuals.chargePulseDepth) else {
            throw DecodingError.dataCorruptedError(
                forKey: .visuals, in: c, debugDescription: "visuals config values must be > 0")
        }
        guard tree.validate() else {
            throw DecodingError.dataCorruptedError(
                forKey: .tree, in: c, debugDescription: "tree config out of range or hooks malformed")
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
        for required in [StepID.countdown, StepID.charge] + [config.tree.touch.fromStep].compactMap({ $0 }) where !seen.contains(required) {
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

/// Background music: one gentle track looping under the whole experience,
/// from when the space opens. It fades in over `fadeInMs`, and dips to
/// `duckDb` below its level on `duckSteps` (the countdown and the needle),
/// so the port's click and pulses stay clear and the child's attention stays
/// on the port, easing over `duckMs`. Not spatial: it surrounds the child.
public struct MusicConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// In Audio/Music, with its extension.
    public var file: String
    public var gainDb: Double
    public var duckDb: Double
    public var duckSteps: [String]
    public var fadeInMs: Int
    public var duckMs: Int

    public var fadeIn: TimeInterval { Double(fadeInMs) / 1000 }
    public var duck: TimeInterval { Double(duckMs) / 1000 }

    /// The music's level on this step.
    public func level(stepId: String) -> Double {
        duckSteps.contains(stepId) ? gainDb - duckDb : gainDb
    }

    func validate() -> Bool { !file.isEmpty && gainDb <= 0 && duckDb >= 0 && fadeInMs >= 0 && duckMs >= 0 }
}

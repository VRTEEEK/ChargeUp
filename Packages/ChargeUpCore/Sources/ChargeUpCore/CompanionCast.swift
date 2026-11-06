import Foundation
import simd

/// Every clip a companion can play, by the name config and cues use.
public enum CompanionClip: String, CaseIterable, Sendable {
    case idle, idleAlt, wave, listen, look, sway, fidget, heart, cheer, hello

    /// This clip if the character has it, otherwise idle.
    public func orIdle(in available: Set<CompanionClip>) -> CompanionClip {
        available.contains(self) ? self : .idle
    }
}

/// One character the companion can be: a model and its own clip files, all
/// USDZ names in the assets package, without extension. The model's own clip
/// is its idle loop, so `clips` never names idle; a clip it does not name
/// plays as idle. `voices` is by clip name, as sounds in Audio/Sounds without
/// .wav; a character with none is silent.
public struct CompanionCharacter: Codable, Equatable, Sendable {
    public var name: String
    public var model: String
    public var clips: [String: String]
    public var voices: [String: [String]]?

    public init(name: String, model: String, clips: [String: String], voices: [String: [String]]? = nil) {
        self.name = name
        self.model = model
        self.clips = clips
        self.voices = voices
    }

    public var clipFiles: [CompanionClip: String] {
        Dictionary(uniqueKeysWithValues: clips.compactMap { key, file in
            CompanionClip(rawValue: key).map { ($0, file) }
        })
    }

    func validate() -> Bool {
        !name.isEmpty && !model.isEmpty
            && clips.allSatisfy { key, file in
                !file.isEmpty && key != CompanionClip.idle.rawValue && CompanionClip(rawValue: key) != nil
            }
            && (voices ?? [:]).values.allSatisfy { !$0.isEmpty && $0.allSatisfy { !$0.isEmpty } }
    }
}

/// Look, pinch and drag on the companion, then release: which character
/// comes next. Left across the child's head is the next character, right
/// goes back, and the list wraps.
public enum CompanionSwitch {
    /// +1 for a drag at least `threshold` metres to the left of the child's
    /// head, -1 for as far to the right, 0 for anything shorter. Only the
    /// travel across the head counts, so reaching forward or up never
    /// changes the character.
    public static func step(from start: SIMD3<Float>, to end: SIMD3<Float>, head: simd_float4x4, threshold: Float) -> Int {
        let across = simd_dot(end - start, WaveDetector.right(of: head))
        if across <= -threshold { return 1 }
        if across >= threshold { return -1 }
        return 0
    }

    /// The character `step` places along from `index`, wrapping.
    public static func index(from index: Int, by step: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + step) % count + count) % count
    }
}

import Foundation
import RealityKit
import ChargeUpCore

/// Loads one AudioFileResource per audio id in the sequence and plays them
/// from two spatial sources: one riding on the port, one on the lantern.
/// Which ids go where, and which loop, comes from config.audio.
@MainActor
final class SoundBank {
    private let config: AudioConfig
    private var resources: [String: AudioFileResource] = [:]
    private var loopController: AudioPlaybackController?
    private var loopingId: String?

    /// Attach these to the port root and the lantern root.
    let portSource = Entity()
    let lanternSource = Entity()
    /// Rides on the companion's head, for its voice.
    let companionSource = Entity()
    /// Moved to whichever hung lantern was pinched, for its chime.
    let chimeSource = Entity()
    /// The background music, all around the child (config.audio.music).
    let musicSource = Entity()
    private var music: AudioFileResource?
    private var musicController: AudioPlaybackController?
    private var musicLevel: Double?
    /// Which voice each clip plays next.
    private var voiceTurns: [String: Int] = [:]

    /// For the operator window: "7 loaded" or the first failure.
    private(set) var status = "not loaded"
    private(set) var missing: [String] = []

    init(config: AudioConfig, companionGainDb: Double, chimeGainDb: Double) {
        self.config = config
        chimeSource.name = "lanternChime"
        chimeSource.components.set(SpatialAudioComponent(gain: Audio.Decibel(chimeGainDb)))
        companionSource.name = "companionVoice"
        companionSource.components.set(SpatialAudioComponent(gain: Audio.Decibel(companionGainDb)))
        musicSource.name = "music"
        musicSource.components.set(AmbientAudioComponent(gain: Audio.Decibel(config.music.gainDb)))
        portSource.name = "portAudio"
        portSource.components.set(SpatialAudioComponent(gain: Audio.Decibel(config.portGainDb)))
        lanternSource.name = "lanternAudio"
        lanternSource.components.set(SpatialAudioComponent(gain: Audio.Decibel(config.lanternGainDb)))
    }

    /// Load every id the sequence names. A missing file is reported, not fatal,
    /// so one bad asset does not take the demo down; the operator sees it.
    func load(ids: [String], bundle: Bundle = .main) async {
        for id in ids {
            var configuration = AudioFileResource.Configuration()
            configuration.shouldLoop = config.loops(id)
            do {
                resources[id] = try await AudioFileResource(named: "\(id).wav", in: bundle, configuration: configuration)
            } catch {
                missing.append(id)
            }
        }
        if config.music.enabled {
            var configuration = AudioFileResource.Configuration()
            configuration.shouldLoop = true
            do {
                music = try await AudioFileResource(named: config.music.file, in: bundle, configuration: configuration)
            } catch {
                missing.append(config.music.file)
            }
        }
        status = missing.isEmpty ? "\(resources.count) loaded\(music == nil ? "" : ", music")" : "missing \(missing.joined(separator: ", "))"
    }

    /// Plays sound `id` from `position` (world), for a pinched lantern.
    func playChime(_ id: String, at position: SIMD3<Float>) {
        guard let resource = resources[id] else { return }
        chimeSource.position = position
        chimeSource.playAudio(resource)
    }

    /// Starts the music from silence, fading in to its level.
    func startMusic() {
        guard let music, musicController == nil else { return }
        let c = musicSource.playAudio(music)
        c.gain = -80
        c.fade(to: Audio.Decibel(config.music.gainDb), duration: config.music.fadeIn)
        musicController = c
        musicLevel = config.music.gainDb
    }

    /// Eases the music to its level for this step (dipped on the needle steps).
    func setMusic(forStep stepId: String) {
        guard let c = musicController else { return }
        let level = config.music.level(stepId: stepId)
        guard level != musicLevel else { return }
        musicLevel = level
        c.fade(to: Audio.Decibel(level), duration: config.music.duck)
    }

    /// Play the sound for a step. Looping sounds keep going until `stopLoop`
    /// or the next step that is not the same id.
    func play(_ id: String) {
        if loopingId != nil, loopingId != id { stopLoop() }
        guard let resource = resources[id] else { return }
        let source = config.playsAtLantern(id) ? lanternSource : portSource
        let controller = source.playAudio(resource)
        if config.loops(id) {
            loopController = controller
            loopingId = id
        }
    }

    /// The companion's voice for a clip it has just started, from
    /// config.companion.voices, the clip's sounds taking turns. Clips with no
    /// voices stay silent.
    func playVoice(forClip clip: String, voices: [String: [String]]) {
        guard let ids = voices[clip], !ids.isEmpty else { return }
        let turn = voiceTurns[clip, default: 0]
        voiceTurns[clip] = turn + 1
        guard let resource = resources[ids[turn % ids.count]] else { return }
        companionSource.playAudio(resource)
    }

    func stopLoop() {
        loopController?.stop()
        loopController = nil
        loopingId = nil
    }
}

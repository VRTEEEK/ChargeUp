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

    /// For the operator window: "7 loaded" or the first failure.
    private(set) var status = "not loaded"
    private(set) var missing: [String] = []

    init(config: AudioConfig) {
        self.config = config
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
        status = missing.isEmpty ? "\(resources.count) loaded" : "missing \(missing.joined(separator: ", "))"
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

    func stopLoop() {
        loopController?.stop()
        loopController = nil
        loopingId = nil
    }
}

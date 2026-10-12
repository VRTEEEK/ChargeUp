import SwiftUI
import RealityKit
import QuartzCore
import ChargeUpCore

/// The child's view. No UI lives here; the operator window carries all
/// text and status. Milestone 2 task 1: the port follows the held forearm.
struct ImmersiveView: View {
    static let id = "charge"

    @ObservedObject var controller: SessionController
    @State private var frameSubscription: EventSubscription?

    var body: some View {
        RealityView { content in
            let port = PortEntity.make()
            port.isEnabled = false
            content.add(port)
            frameSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                guard let pose = controller.frame(now: CACurrentMediaTime()) else {
                    port.isEnabled = false
                    return
                }
                port.isEnabled = true
                PortEntity.apply(pose, to: port)
            }
        }
        .task {
            await controller.portSource.start()
        }
        .onDisappear {
            controller.portSource.stop()
            frameSubscription = nil
        }
    }
}

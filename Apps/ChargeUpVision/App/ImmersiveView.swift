import SwiftUI
import RealityKit
import QuartzCore
import ChargeUpCore

/// The child's view. No UI lives here; the operator window carries all
/// text and status. Everything visible is owned by SceneDirector. The one
/// gesture is the system's look and pinch, on the hung lanterns (all the
/// time, config.tree.touch) and on the monkey (config.companion.touch).
struct ImmersiveView: View {
    static let id = "charge"

    @ObservedObject var controller: SessionController
    @State private var director: SceneDirector?
    @State private var frameSubscription: EventSubscription?

    var body: some View {
        RealityView { content in
            let director = SceneDirector(controller: controller)
            director.attach(to: content)
            self.director = director
            Task { await director.loadSounds() }
            frameSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                director.frame(now: CACurrentMediaTime())
            }
        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            director?.pinch(value.entity)
        })
        .task {
            await controller.portSource.start()
            await controller.headPose.start()
            let head = await controller.headPose.first(timeout: controller.sequence.config.lantern.headPoseWait)
            director?.placeLantern(head: head)
            controller.noteLanternPlacement(fromHeadPose: head != nil,
                                            head: head.map { ForearmPoseSolver.translation(of: $0) },
                                            lantern: director?.anchor.position ?? .zero)
        }
        .onDisappear {
            controller.portSource.stop()
            controller.headPose.stop()
            frameSubscription = nil
            director = nil
        }
    }
}

import SwiftUI
import RealityKit
import ChargeUpCore

/// Milestone 1 placeholder: a floating label with the current step name so
/// the chain nurse -> headset is visible end to end. Milestone 2 replaces
/// this with the port, sleeve and lantern driven by step id.
struct ImmersiveView: View {
    static let id = "charge"

    @ObservedObject var controller: SessionController

    /// Where the label floats, in metres from the space origin at the user's feet.
    private static let labelPosition = SIMD3<Float>(0, 1.3, -1.5)

    var body: some View {
        RealityView { content, attachments in
            let root = Entity()
            root.position = ImmersiveView.labelPosition
            if let label = attachments.entity(for: "step") {
                root.addChild(label)
            }
            content.add(root)
        } attachments: {
            Attachment(id: "step") {
                Text(controller.currentStep?.name ?? controller.currentStepId)
                    .font(.system(size: 48, weight: .bold))
                    .padding(32)
                    .glassBackgroundEffect()
            }
        }
    }
}

import SwiftUI
import ChargeUpCore

@main
struct ChargeUpVisionApp: App {
    @StateObject private var controller = SessionController()

    var body: some Scene {
        WindowGroup(id: OperatorWindow.id) {
            OperatorWindow(controller: controller)
        }
        // Sized by its content: the 16:9 start screen, then the status panel.
        .windowResizability(.contentSize)

        ImmersiveSpace(id: ImmersiveView.id) {
            ImmersiveView(controller: controller)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        // The system would otherwise draw the real hands and arms over any
        // virtual content near them, which puts the port, glow and cable
        // "under the skin". Hidden lets our geometry draw over the arm.
        .upperLimbVisibility(.hidden)
    }
}

import SwiftUI
import RealityKit
import ImageIO
import os

/// The start screen's key art as a spatial scene, the depth effect the
/// Photos app gives a flat picture (visionOS 26 and later). The scene is
/// generated on the headset from App/StartBackground.jpg; that takes a few
/// seconds, so it starts when the app launches, and the window shows a soft
/// placeholder until it is ready rather than the flat picture: the art
/// appears in 3D from the start. The generated scene is kept for the rest
/// of the launch, so returning to the start screen after Stop is instant.
/// The flat picture appears only where generation fails or is unavailable.
/// Replace App/StartBackground.jpg to change the picture.
@MainActor
final class SpatialStartArt: ObservableObject {
    static let shared = SpatialStartArt()
    static let fileName = "StartBackground"
    static let fileExtension = "jpg"
    private static let logger = Logger(subsystem: "com.vrteek.chargeup", category: "start")

    enum State { case generating, ready, flat }
    @Published private(set) var state: State = .generating
    /// The generated `ImagePresentationComponent.Spatial3DImage` (visionOS 26+).
    private(set) var image: AnyObject?
    private var started = false

    static var url: URL? { Bundle.main.url(forResource: fileName, withExtension: fileExtension) }

    /// Starts generating once per launch; later calls do nothing.
    func prepare() {
        guard !started else { return }
        started = true
        guard #available(visionOS 26.0, *), let url = Self.url else {
            state = .flat
            return
        }
        Task {
            do {
                let image = try await ImagePresentationComponent.Spatial3DImage(contentsOf: url)
                try await image.generate()
                self.image = image
                state = .ready
            } catch {
                Self.logger.error("spatial start art unavailable, showing it flat: \(String(describing: error), privacy: .public)")
                state = .flat
            }
        }
    }
}

struct SpatialStartBackground: View {
    let size: CGSize
    @ObservedObject private var art = SpatialStartArt.shared

    var body: some View {
        ZStack {
            switch art.state {
            case .generating:
                // A soft night-sky placeholder, never the flat picture.
                LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.16), Color(red: 0.16, green: 0.10, blue: 0.20)],
                               startPoint: .top, endPoint: .bottom)
                    .overlay { ProgressView().controlSize(.large).tint(.orange) }
                    .transition(.opacity)
            case .ready:
                if #available(visionOS 26.0, *), let image = art.image as? ImagePresentationComponent.Spatial3DImage {
                    SpatialArtView(image: image, size: size)
                        .transition(.opacity)
                }
            case .flat:
                if let url = SpatialStartArt.url, let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .animation(.easeInOut(duration: 0.8), value: art.state)
        .onAppear { art.prepare() }
        .accessibilityHidden(true)
    }
}

/// The generated scene sized to the window's actual frame in the scene,
/// measured with the RealityView's own conversion: windows scale with
/// distance, so a fixed points-to-metres factor would make it larger than
/// the window and spill over the Start button below it.
@available(visionOS 26.0, *)
private struct SpatialArtView: View {
    let image: ImagePresentationComponent.Spatial3DImage
    let size: CGSize

    var body: some View {
        GeometryReader3D { proxy in
            RealityView { content in
                let frame = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
                var component = ImagePresentationComponent(spatial3DImage: image)
                component.desiredViewingMode = .spatial3D
                let height = frame.extents.y, width = frame.extents.x
                // Fit inside the window whatever the generated scene's aspect.
                if let aspect = component.aspectRatio(for: .spatial3D), aspect > 0 {
                    component.screenHeight = min(height, width / aspect)
                } else {
                    component.screenHeight = height
                }
                let entity = Entity()
                entity.name = "spatialStartArt"
                entity.position = frame.center
                entity.components.set(component)
                content.add(entity)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

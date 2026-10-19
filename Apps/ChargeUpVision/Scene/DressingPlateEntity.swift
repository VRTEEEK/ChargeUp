import RealityKit
import UIKit
import ChargeUpCore

/// Chest port replacement: instead of a sleeve, a soft-edged plate over the
/// dressing area, centred on the port, in the port's frame (+Y out of the
/// skin). Opaque so it occludes the real dressing under upperLimbVisibility
/// rules for the chest, which do not apply (that modifier hides arms only);
/// here the plate simply draws over passthrough. COMPILE-ONLY, like the
/// marker source.
@MainActor
enum DressingPlateEntity {
    private static let thickness: Float = 0.003
    private static let tint = UIColor(red: 0.16, green: 0.2, blue: 0.3, alpha: 1)

    static func make(size: SIMD2<Float>, assets: AssetCatalog? = nil) -> Entity {
        if let model = assets?.model(.portPlate) {
            model.name = "dressingPlate"
            return model
        }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: tint)
        material.roughness = 0.85
        material.emissiveColor = .init(color: UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        material.emissiveIntensity = 0.15
        let radius = min(size.x, size.y) * 0.25
        let mesh = MeshResource.generateBox(width: size.x, height: thickness, depth: size.y, cornerRadius: radius)
        let plate = ModelEntity(mesh: mesh, materials: [material])
        plate.name = "dressingPlate"
        plate.position.y = -thickness
        return plate
    }
}

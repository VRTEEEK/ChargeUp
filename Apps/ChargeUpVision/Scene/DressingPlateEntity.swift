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
    static let designedName = "dressingPlateDesigned"
    private static let thickness: Float = 0.003
    private static let tint = UIColor(red: 0.16, green: 0.2, blue: 0.3, alpha: 1)

    /// Designed plate: the file's origin is the plate centre on the skin, but
    /// the port pose (the rig origin) is the dome centre, so the model is
    /// shifted by minus the dome's XZ centre, measured from the Glass mesh at
    /// load and logged, and `glassMask` false holds its fill at 1.
    static func make(size: SIMD2<Float>, assets: AssetCatalog? = nil, glassMask: Bool = true) -> Entity {
        if let model = assets?.model(.portPlate) {
            model.name = designedName
            if let glass = AssetCatalog.glassBounds(in: model) {
                let dome = glass.center
                model.position = SIMD3(-dome.x, 0, -dome.z)
                AssetCatalog.logger.info("port_plate: dome centre from plate origin x \(dome.x, format: .fixed(precision: 4)) z \(dome.z, format: .fixed(precision: 4)) m; plate shifted by the negative so the dome sits at the port pose")
            }
            if !glassMask { AssetCatalog.setParameter(AssetCatalog.fillParameter, 1, in: model) }
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

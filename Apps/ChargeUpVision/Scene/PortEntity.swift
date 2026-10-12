import RealityKit
import ChargeUpCore

/// Milestone 2 task 1 placeholder for the charging port: a flat disc whose
/// +Y is the surface normal, so it lies on the skin where the solver puts
/// it. Task 5 replaces the look; the anchoring stays.
@MainActor
enum PortEntity {
    /// Disc diameter and thickness in metres. Visual only; the anchor maths does not use them.
    private static let diameter: Float = 0.040
    private static let thickness: Float = 0.004

    static func make() -> ModelEntity {
        let mesh = MeshResource.generateCylinder(height: thickness, radius: diameter / 2)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(red: 0.2, green: 0.7, blue: 1.0, alpha: 1))
        material.emissiveColor = .init(color: .init(red: 0.2, green: 0.7, blue: 1.0, alpha: 1))
        material.emissiveIntensity = 2
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "port"
        entity.components.set(OpacityComponent(opacity: 1))
        return entity
    }

    /// Apply a solved pose. Called every frame; cheap.
    static func apply(_ pose: PortPose, to entity: Entity) {
        entity.position = pose.position
        entity.orientation = pose.orientation
        entity.components[OpacityComponent.self]?.opacity = pose.opacity
    }
}

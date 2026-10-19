import Foundation
import RealityKit
import UIKit
import ChargeUpCore
import ChargeUpAssets
import os

/// Every designed asset the scene can take, by the file name it is loaded
/// under. The contract is docs/assets.md. Nothing else in the app names an
/// asset file.
enum AssetSlot: String, CaseIterable {
    case lanternHero = "lantern_hero"
    case lanternRound = "lantern_round"
    case lanternTall = "lantern_tall"
    case lanternSquare = "lantern_square"
    case portRing = "port_ring"
    case portPlate = "port_plate"
    case plug = "plug"
    case spark = "spark"
    case sleeveTile = "sleeve_tile"
    case chargeMark = "charge_mark"
    case portMarker = "port_marker"

    /// PNGs are read as images; everything else is a USDZ model.
    var isImage: Bool { self == .sleeveTile || self == .portMarker }

    static let lanternVariants: [AssetSlot] = [.lanternRound, .lanternTall, .lanternSquare]
}

/// Loads whatever designed assets are present in the ChargeUpAssets package
/// and hands out clones. A slot with no file stays a placeholder: the
/// procedural geometry already in the scene is used and the operator window
/// says so.
@MainActor
final class AssetCatalog {
    private static let logger = Logger(subsystem: "com.vrteek.chargeup", category: "assets")
    static let glassMaterialName = "Glass"
    static let glassMaterialPath = "/Root/LanternGlass"
    static let glassMaterialFile = "Materials/LanternGlass.usda"
    static let fillParameter = "fill"
    static let glowIntensityParameter = "glowIntensity"
    static let glowColorParameter = "glowColor"

    private var models: [AssetSlot: Entity] = [:]
    private var images: [AssetSlot: CGImage] = [:]
    private(set) var glass: ShaderGraphMaterial?
    private(set) var placeholders: [AssetSlot] = AssetSlot.allCases
    private(set) var loaded = false
    private(set) var status = "not loaded"

    /// Try every slot once. Missing files are expected; a file that exists
    /// but fails to load is reported by name.
    func load() async {
        guard !loaded else { return }
        var found: [String] = []
        var broken: [String] = []
        var missing: [AssetSlot] = []
        for slot in AssetSlot.allCases {
            if slot.isImage {
                if let image = Self.loadImage(named: slot.rawValue) {
                    images[slot] = image
                    found.append(slot.rawValue)
                } else {
                    missing.append(slot)
                }
            } else {
                do {
                    let entity = try await Entity(named: slot.rawValue, in: chargeUpAssetsBundle)
                    models[slot] = entity
                    found.append(slot.rawValue)
                } catch {
                    // "not found" is the normal placeholder case; anything else is a broken
                    // file, reported by name. Either way the placeholder is used.
                    Self.logger.info("slot \(slot.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
                    if !Self.looksLikeNotFound(error) { broken.append("\(slot.rawValue): \(error.localizedDescription)") }
                    missing.append(slot)
                }
            }
        }
        do {
            glass = try await ShaderGraphMaterial(named: Self.glassMaterialPath, from: Self.glassMaterialFile, in: chargeUpAssetsBundle)
        } catch {
            Self.logger.error("LanternGlass: \(String(describing: error), privacy: .public)")
            broken.append("LanternGlass: \(error.localizedDescription)")
        }
        placeholders = missing
        loaded = true
        var parts = ["\(found.count) designed, \(missing.count) placeholder"]
        parts.append(glass == nil ? "glass shader missing" : "glass shader ok")
        if !broken.isEmpty { parts.append("broken: " + broken.joined(separator: "; ")) }
        status = parts.joined(separator: ", ")
    }

    /// A fresh copy of a designed model, with every material named `Glass`
    /// replaced by the LanternGlass shader. Nil means use the placeholder.
    func model(_ slot: AssetSlot) -> Entity? {
        guard let prototype = models[slot] else { return nil }
        let copy = prototype.clone(recursive: true)
        let found = Self.materialNames(in: copy)
        var replaced = 0
        if let glass { replaced = Self.applyGlass(glass, to: copy) }
        let bounds = copy.visualBounds(relativeTo: nil)
        Self.logger.info("model \(slot.rawValue, privacy: .public): materials \(found.joined(separator: ", "), privacy: .public); Glass replaced on \(replaced) model component(s); bounds min \(bounds.min.description, privacy: .public) max \(bounds.max.description, privacy: .public)")
        return copy
    }

    /// "entity/material" for every material in the tree, for the operator log.
    static func materialNames(in entity: Entity) -> [String] {
        var names: [String] = []
        if let model = entity.components[ModelComponent.self] {
            for m in model.materials { names.append("\(entity.name)/\(m.name ?? "unnamed")") }
        }
        for child in entity.children { names += materialNames(in: child) }
        return names
    }

    func image(_ slot: AssetSlot) -> CGImage? { images[slot] }

    /// Read a PNG from the package's Textures folder by name, no extension.
    nonisolated static func loadImage(named name: String) -> CGImage? {
        guard let url = chargeUpAssetsBundle.url(forResource: name, withExtension: "png", subdirectory: "Textures")
                ?? chargeUpAssetsBundle.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)?.cgImage
    }

    /// Replace materials named `Glass` throughout an entity tree. Returns how
    /// many model components had a Glass material replaced.
    @discardableResult
    static func applyGlass(_ glass: ShaderGraphMaterial, to entity: Entity) -> Int {
        var count = 0
        if var model = entity.components[ModelComponent.self] {
            var changed = false
            model.materials = model.materials.map { material in
                if material.name == glassMaterialName {
                    changed = true
                    return glass
                }
                return material
            }
            if changed {
                entity.components.set(model)
                count += 1
            }
        }
        for child in entity.children { count += applyGlass(glass, to: child) }
        return count
    }

    /// Set a float parameter on every ShaderGraph material in the tree that has it.
    static func setParameter(_ name: String, _ value: Float, in entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            var changed = false
            model.materials = model.materials.map { material in
                guard var sg = material as? ShaderGraphMaterial, sg.parameterNames.contains(name) else { return material }
                try? sg.setParameter(name: name, value: .float(value))
                changed = true
                return sg
            }
            if changed { entity.components.set(model) }
        }
        for child in entity.children { setParameter(name, value, in: child) }
    }

    /// Set a colour parameter on every ShaderGraph material in the tree that has it.
    static func setColorParameter(_ name: String, _ color: UIColor, in entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            var changed = false
            model.materials = model.materials.map { material in
                guard var sg = material as? ShaderGraphMaterial, sg.parameterNames.contains(name) else { return material }
                try? sg.setParameter(name: name, value: .color(color.cgColor))
                changed = true
                return sg
            }
            if changed { entity.components.set(model) }
        }
        for child in entity.children { setColorParameter(name, color, in: child) }
    }

    /// Set the emissive intensity on every PhysicallyBasedMaterial named `Glow`.
    static func setGlow(_ intensity: Float, tint: UIColor?, in entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            var changed = false
            model.materials = model.materials.map { material in
                guard material.name == "Glow", var pbr = material as? PhysicallyBasedMaterial else { return material }
                pbr.emissiveIntensity = intensity
                if let tint { pbr.emissiveColor = .init(color: tint) }
                changed = true
                return pbr
            }
            if changed { entity.components.set(model) }
        }
        for child in entity.children { setGlow(intensity, tint: tint, in: child) }
    }

    private static func looksLikeNotFound(_ error: Error) -> Bool {
        // RealityKit reports a missing rkassets entry as resourceNotFound("name").
        let text = String(describing: error).lowercased()
        return text.contains("notfound") || text.contains("not find") || text.contains("not found") || text.contains("no such")
    }
}

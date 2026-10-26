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
    case sleeveTileSoft = "sleeve_tile_soft"
    case chargeMark = "charge_mark"
    case portMarker = "port_marker"
    case companionModel = "companion_model"
    case companionClipAgree = "companion_clip_agree"
    case companionClipHeart = "companion_clip_heart"
    case companionClipCheer = "companion_clip_cheer"
    case companionClipSpin = "companion_clip_spin"

    /// PNGs are read as images; everything else is a USDZ model.
    var isImage: Bool { self == .sleeveTile || self == .sleeveTileSoft || self == .portMarker || self == .chargeMark || self == .spark }

    /// port_ring and port_plate are alternatives, not layers: the ring is the
    /// arm's port, the plate is the chest's. The other one is never loaded.
    var isCompanion: Bool {
        switch self {
        case .companionModel, .companionClipAgree, .companionClipHeart, .companionClipCheer, .companionClipSpin: return true
        default: return false
        }
    }

    func applies(to site: AccessSite, companionEnabled: Bool) -> Bool {
        if isCompanion { return companionEnabled }
        switch self {
        case .portRing: return site == .arm
        case .portPlate: return site == .chestPort
        default: return true
        }
    }

    static let lanternVariants: [AssetSlot] = [.lanternRound, .lanternTall, .lanternSquare]
}

/// Loads whatever designed assets are present in the ChargeUpAssets package
/// and hands out clones. A slot with no file stays a placeholder: the
/// procedural geometry already in the scene is used and the operator window
/// says so.
@MainActor
final class AssetCatalog {
    static let logger = Logger(subsystem: "com.vrteek.chargeup", category: "assets")
    static let glassMaterialName = "Glass"
    static let glassMaterialPath = "/Root/LanternGlass"
    static let glassMaterialFile = "Materials/LanternGlass.usda"
    static let fillParameter = "fill"
    static let glowIntensityParameter = "glowIntensity"
    static let glowColorParameter = "glowColor"

    private var models: [AssetSlot: Entity] = [:]
    private var images: [AssetSlot: CGImage] = [:]
    private var textures: [AssetSlot: TextureResource] = [:]
    /// Single-channel alpha of the sprite PNGs, because an opacity map reads
    /// one colour channel, not the alpha, of an RGBA texture.
    private var alphaMasks: [AssetSlot: TextureResource] = [:]
    /// Fraction of the canvas the sprite's opaque pixels span (width, height),
    /// so a glyph drawn small in a large canvas is still shown at full size.
    private var spriteExtents: [AssetSlot: SIMD2<Float>] = [:]
    private(set) var glass: ShaderGraphMaterial?
    private(set) var placeholders: [AssetSlot] = AssetSlot.allCases
    private(set) var skipped: [AssetSlot] = []
    private(set) var loaded = false
    private(set) var status = "not loaded"

    /// Try every slot that applies to the access site once. Missing files are
    /// expected; a file that exists but fails to load is reported by name.
    func load(accessSite: AccessSite, companionEnabled: Bool = false) async {
        guard !loaded else { return }
        var found: [String] = []
        var broken: [String] = []
        var missing: [AssetSlot] = []
        skipped = AssetSlot.allCases.filter { !$0.applies(to: accessSite, companionEnabled: companionEnabled) }
        for slot in AssetSlot.allCases where slot.applies(to: accessSite, companionEnabled: companionEnabled) {
            if slot.isImage {
                if let image = Self.loadImage(named: slot.rawValue) {
                    images[slot] = image
                    // The marker stays a CGImage for image tracking; the rest become textures.
                    if slot != .portMarker {
                        do {
                            textures[slot] = try await TextureResource(image: image, withName: slot.rawValue,
                                                                       options: .init(semantic: .color))
                            if slot == .chargeMark || slot == .spark, let (alpha, extent) = Self.alphaImage(of: image) {
                                alphaMasks[slot] = try await TextureResource(image: alpha, withName: slot.rawValue + "_alpha",
                                                                             options: .init(semantic: .raw))
                                spriteExtents[slot] = extent
                                Self.logger.info("sprite \(slot.rawValue, privacy: .public): opaque extent \(extent.x, format: .fixed(precision: 2)) x \(extent.y, format: .fixed(precision: 2)) of the canvas")
                            }
                        } catch {
                            broken.append("\(slot.rawValue): \(error.localizedDescription)")
                        }
                    }
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
        let skippedText = skipped.contains(where: \.isCompanion) ? "companion off, " : ""
        var parts = ["\(found.count) designed, \(missing.count) placeholder, \(skippedText)\(skipped.filter { !$0.isCompanion }.map(\.rawValue).joined(separator: " ")) not loaded (\(accessSite.rawValue))"]
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
        if let glass = Self.glassBounds(in: copy) {
            Self.logger.info("model \(slot.rawValue, privacy: .public): Glass mesh bounds min \(glass.min.description, privacy: .public) max \(glass.max.description, privacy: .public) centre \(glass.center.description, privacy: .public) (file frame, metres)")
        }
        return copy
    }

    /// Bounds of every mesh carrying a material named `Glass` (or the shader
    /// that replaced it), in the model's own frame. Nil if there is none.
    static func glassBounds(in entity: Entity, root: Entity? = nil) -> BoundingBox? {
        let root = root ?? entity
        var result: BoundingBox?
        if let model = entity.components[ModelComponent.self],
           model.materials.contains(where: { $0.name == glassMaterialName || $0 is ShaderGraphMaterial }) {
            let b = entity.visualBounds(relativeTo: root)
            result = result.map { $0.union(b) } ?? b
        }
        for child in entity.children {
            if let b = glassBounds(in: child, root: root) { result = result.map { $0.union(b) } ?? b }
        }
        return result
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
    func texture(_ slot: AssetSlot) -> TextureResource? { textures[slot] }

    /// The sleeve tile named in config, falling back to the plain tile when
    /// the soft one is absent. Nil means neither file is present.
    func sleeveTexture(named name: String) -> (slot: AssetSlot, texture: TextureResource)? {
        if let slot = AssetSlot(rawValue: name), let t = textures[slot] { return (slot, t) }
        if let t = textures[.sleeveTile] { return (.sleeveTile, t) }
        return nil
    }

    /// Tiled, translucent surface material for the sleeve and the plate surround.
    static func sleeveMaterial(_ texture: TextureResource, opacity: Float, tiling: Float) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .white, texture: .init(texture))
        m.roughness = 0.8
        m.metallic = 0.0
        m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        m.textureCoordinateTransform = .init(scale: SIMD2(tiling, tiling))
        return m
    }

    /// Sprite material for a slot: colour from the PNG, opacity from its alpha mask.
    func spriteMaterial(_ slot: AssetSlot) -> UnlitMaterial? {
        guard let texture = textures[slot] else { return nil }
        var m = UnlitMaterial()
        m.color = .init(tint: .white, texture: .init(texture))
        if let alpha = alphaMasks[slot] {
            m.blending = .transparent(opacity: .init(scale: 1, texture: .init(alpha)))
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: 1))
        }
        return m
    }

    /// How much to scale a sprite plane so its opaque content fills the
    /// intended size: 1 when the glyph fills the canvas, larger when it does not.
    func spriteScale(_ slot: AssetSlot) -> Float {
        guard let e = spriteExtents[slot], e.x > 0.01, e.y > 0.01 else { return 1 }
        return 1 / max(e.x, e.y)
    }

    /// The alpha channel of an image as an 8-bit grey image, plus the fraction
    /// of the canvas covered by pixels with alpha above half.
    static func alphaImage(of image: CGImage) -> (CGImage, SIMD2<Float>)? {
        let w = image.width, h = image.height
        guard let rgba = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        rgba.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let src = rgba.data else { return nil }
        var alpha = [UInt8](repeating: 0, count: w * h)
        let bytes = src.assumingMemoryBound(to: UInt8.self)
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                let a = bytes[(y * w + x) * 4 + 3]
                alpha[y * w + x] = a
                if a > 127 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(alpha) as CFData),
              let grey = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                 provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        let extent = maxX >= minX
            ? SIMD2<Float>(Float(maxX - minX + 1) / Float(w), Float(maxY - minY + 1) / Float(h))
            : SIMD2<Float>(1, 1)
        return (grey, extent)
    }

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

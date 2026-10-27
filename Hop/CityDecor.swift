import SceneKit
import UIKit
import simd

/// Builds the detailed city on top of the street grid: buildings with shop fronts, awnings,
/// cornices and rooftop gear; landmarks (park, gas station, parking garage); trees and street
/// furniture on the sidewalks; road decals; soft contact shadows; and a far skyline. Everything
/// static is written into a few merged meshes (one draw call per material).
enum CityDecor {
    // MARK: Materials

    private static var materials: [String: SCNMaterial] = [:]

    private static func material(_ key: String, _ make: () -> SCNMaterial) -> SCNMaterial {
        if let cached = materials[key] { return cached }
        let material = make()
        materials[key] = material
        return material
    }

    private static func textured(_ key: String, _ image: UIImage, lit: Bool = true) -> SCNMaterial {
        material(key) {
            let material = lit ? Mat.lambert(image) : SCNMaterial()
            if !lit {
                material.lightingModel = .constant
                material.diffuse.contents = image
            }
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.diffuse.mipFilter = .linear
            return material
        }
    }

    private static func color(_ key: String, _ color: UIColor, metal: CGFloat = 0, rough: CGFloat = 0.8) -> SCNMaterial {
        material(key) { Mat.pbr(color, metal: metal, rough: rough) }
    }

    /// Transparent ground overlay (shadows, decals): no depth writes, drawn after the ground.
    private static func overlay(_ key: String, _ image: UIImage) -> SCNMaterial {
        material(key) {
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = image
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.writesToDepthBuffer = false
            material.blendMode = .alpha
            return material
        }
    }

    private static func facadeMaterial(_ style: CityArt.Style, _ variant: Int) -> SCNMaterial {
        let key = "facade-\(style.rawValue)-\(variant)"
        if style == .office {
            return material(key) {
                let material = Mat.pbr(.white, metal: 0.55, rough: 0.22)
                material.diffuse.contents = CityArt.facade(style, variant: variant)
                material.diffuse.wrapS = .repeat
                material.diffuse.wrapT = .repeat
                material.diffuse.mipFilter = .linear
                return material
            }
        }
        return textured(key, CityArt.facade(style, variant: variant))
    }

    // MARK: Entry point

    /// Static city detail for a level. `world` is the level size in world units.
    static func build(level: LevelDef, city: CityMap) -> SCNNode {
        let root = SCNNode()
        let solid = MeshBuilder()      // casts shadows
        let ground = MeshBuilder()     // flat overlays: no shadows
        let far = MeshBuilder()        // skyline: no shadows
        var rng = SplitMix64(seed: UInt64(level.obstacles.count) &* 7919 &+ UInt64(city.xs.count))

        for obstacle in level.obstacles where obstacle.kind == .building {
            switch obstacle.tint {
            case Levels.park: park(obstacle, solid: solid, ground: ground, rng: &rng)
            case Levels.gasStation: gasStation(obstacle, solid: solid, ground: ground)
            case Levels.parkingGarage: garage(obstacle, solid: solid, ground: ground, rng: &rng)
            default: building(obstacle, solid: solid, ground: ground, rng: &rng)
            }
        }
        sidewalks(city: city, world: level.world, solid: solid, ground: ground, rng: &rng)
        roadDecals(city: city, world: level.world, ground: ground, rng: &rng)
        skyline(world: level.world, far: far, ground: ground, rng: &rng)

        if let geometry = solid.build() {
            root.addChildNode(SCNNode(geometry: geometry))
        }
        if let geometry = ground.build() {
            let node = SCNNode(geometry: geometry)
            node.castsShadow = false
            node.renderingOrder = 5
            root.addChildNode(node)
        }
        if let geometry = far.build() {
            let node = SCNNode(geometry: geometry)
            node.castsShadow = false
            root.addChildNode(node)
        }
        // Wide urban ground under the skyline (hides the grass beyond the map)
        let size = level.world
        let apron = SCNPlane(width: size.width / 10 + 400, height: size.height / 10 + 400)
        apron.materials = [color("apron", UIColor(red: 0.47, green: 0.49, blue: 0.48, alpha: 1), rough: 0.95)]
        let apronNode = SCNNode(geometry: apron)
        apronNode.eulerAngles.x = -Float.pi / 2
        let center = World3D.vec(CGPoint(x: size.width / 2, y: size.height / 2), y: -0.04)
        apronNode.position = center
        apronNode.castsShadow = false
        root.addChildNode(apronNode)
        return root
    }

    // MARK: Helpers

    private static func v(_ p: CGPoint, _ y: Float = 0) -> SIMD3<Float> {
        let s = World3D.vec(p)
        return SIMD3(s.x, y, s.z)
    }

    /// Footprint of an axis-aligned obstacle in scene meters: center, x extent, z extent.
    private static func footprint(_ obstacle: ObstacleDef) -> (center: SIMD3<Float>, w: Float, l: Float) {
        (v(obstacle.center), Float(obstacle.size.width / 10), Float(obstacle.size.height / 10))
    }

    private static func box(_ mesh: MeshBuilder, _ c: SIMD3<Float>, _ w: Float, _ h: Float, _ l: Float,
                            _ wall: SCNMaterial, _ roof: SCNMaterial? = nil, angle: Float = 0,
                            repeats: ((Float) -> SIMD2<Float>)? = nil) {
        mesh.addBox(center: c, width: w, height: h, length: l, angle: angle, wall: wall, roof: roof ?? wall,
                    wallRepeats: repeats ?? { _ in SIMD2(1, 1) })
    }

    /// Soft shadow around a rectangle on the ground (strips fading outward from each edge).
    private static func contactShadow(_ ground: MeshBuilder, center c: SIMD3<Float>, w: Float, l: Float, width: Float = 1.8, y: Float = 0.1) {
        let shadow = overlay("contact", CityArt.contactShadow)
        // +x, -x edges (strips run along z), +z, -z edges (strips run along x)
        ground.addDecal(center: SIMD3(c.x + w / 2 + width / 2, y, c.z), direction: SIMD2(-1, 0), length: width, width: l, material: shadow)
        ground.addDecal(center: SIMD3(c.x - w / 2 - width / 2, y, c.z), direction: SIMD2(1, 0), length: width, width: l, material: shadow)
        ground.addDecal(center: SIMD3(c.x, y, c.z + l / 2 + width / 2), direction: SIMD2(0, -1), length: width, width: w, material: shadow)
        ground.addDecal(center: SIMD3(c.x, y, c.z - l / 2 - width / 2), direction: SIMD2(0, 1), length: width, width: w, material: shadow)
    }

    // MARK: Buildings

    private static func building(_ obstacle: ObstacleDef, solid: MeshBuilder, ground: MeshBuilder, rng: inout SplitMix64) {
        let (c, w, l) = footprint(obstacle)
        let style = CityArt.Style(rawValue: obstacle.tint % 4) ?? .apartment
        let variant = obstacle.tint / 4
        let height = Float(max(8, obstacle.height))
        let shopHeight: Float = 4.2
        let roof = textured("roof", CityArt.roof)
        let wallColor = CityArt.wallColor(style, variant: variant)
        let trim = color("trim-\(style.rawValue)-\(variant)", wallColor.darker(by: style == .office ? 0.45 : 0.18), rough: 0.7)

        // Ground floor: shops (or a glass lobby for offices)
        let shopVariant = rng.int(4)
        let base = style == .office ? textured("lobby", CityArt.lobby) : textured("shop-\(shopVariant)", CityArt.storefront(shopVariant))
        box(solid, c, w, shopHeight, l, base, roof, repeats: { span in SIMD2(max(1, (span / 6).rounded()), 1) })

        // Upper floors, sometimes in two tiers
        let facade = facadeMaterial(style, variant)
        let floorHeight: Float = 3.2
        let tiered = height > 17 && rng.unit() < 0.55
        let lowerTop = tiered ? shopHeight + ((height - shopHeight) * 0.62 / floorHeight).rounded() * floorHeight : height
        func body(from bottom: Float, to top: Float, inset: Float) {
            let bw = w - inset * 2, bl = l - inset * 2
            let floors = max(1, ((top - bottom) / floorHeight).rounded())
            box(solid, SIMD3(c.x, bottom, c.z), bw, top - bottom, bl, facade, roof,
                repeats: { span in SIMD2(max(1, (span / 4).rounded()), floors) })
            // Cornice slab with a gravel roof
            box(solid, SIMD3(c.x, top, c.z), bw + 0.5, 0.45, bl + 0.5, trim, roof)
        }
        // Band between shops and the floors above
        box(solid, SIMD3(c.x, shopHeight - 0.05, c.z), w + 0.3, 0.35, l + 0.3, trim)
        body(from: shopHeight + 0.3, to: lowerTop, inset: 0)
        var roofTop = lowerTop + 0.45
        var roofW = w, roofL = l
        if tiered {
            let inset: Float = min(2.4, min(w, l) * 0.18)
            body(from: lowerTop + 0.45, to: height, inset: inset)
            roofTop = height + 0.45
            roofW = w - inset * 2
            roofL = l - inset * 2
        }

        // Awnings over the shop windows
        if style != .office {
            let cloth = textured("awning-\(shopVariant)", CityArt.awning(shopVariant))
            let depth: Float = 0.95
            for (dx, dz, span) in [(Float(1), Float(0), l), (-1, 0, l), (0, 1, w), (0, -1, w)] {
                let along = min(span * 0.7, 9)
                let center = SIMD3(c.x + dx * (w / 2 + depth / 2), 3.0, c.z + dz * (l / 2 + depth / 2))
                if dx != 0 {
                    box(solid, center, depth, 0.12, along, cloth, cloth, repeats: { s in SIMD2(max(1, (s / 1.2).rounded()), 1) })
                } else {
                    box(solid, center, along, 0.12, depth, cloth, cloth, repeats: { s in SIMD2(max(1, (s / 1.2).rounded()), 1) })
                }
            }
        }

        // Rooftop gear
        let metal = color("roofMetal", UIColor(white: 0.62, alpha: 1), metal: 0.6, rough: 0.45)
        let dark = color("roofDark", UIColor(white: 0.25, alpha: 1), rough: 0.7)
        func spot() -> SIMD3<Float> {
            SIMD3(c.x + Float(rng.range(-0.5, 0.5)) * max(0, roofW - 3), roofTop, c.z + Float(rng.range(-0.5, 0.5)) * max(0, roofL - 3))
        }
        for _ in 0..<(1 + rng.int(3)) {
            let p = spot()
            box(solid, p, 1.4, 0.9, 1.0, metal)
            box(solid, p + SIMD3(0, 0.9, 0), 0.8, 0.08, 0.8, dark)
        }
        if rng.unit() < 0.7 {
            box(solid, spot(), 2.6, 2.4, 2.6, color("hut-\(style.rawValue)-\(variant)", wallColor.darker(by: 0.08)), roof)
        }
        if (style == .apartment || style == .brick) && rng.unit() < 0.6 {
            let p = spot()
            for (dx, dz) in [(Float(-0.6), Float(-0.6)), (0.6, -0.6), (-0.6, 0.6), (0.6, 0.6)] {
                box(solid, p + SIMD3(dx, 0, dz), 0.12, 1.0, 0.12, dark)
            }
            solid.addPrism(center: p + SIMD3(0, 1.0, 0), radius: 1.0, height: 1.7, sides: 8,
                           material: color("tank", UIColor(red: 0.55, green: 0.42, blue: 0.32, alpha: 1), rough: 0.8))
        }
        if rng.unit() < 0.5 {
            box(solid, spot(), 0.08, 3.5, 0.08, dark)
        }
        contactShadow(ground, center: c, w: w + (style == .office ? 0 : 0.2), l: l + (style == .office ? 0 : 0.2))
    }

    // MARK: Landmarks

    private static func gasStation(_ obstacle: ObstacleDef, solid: MeshBuilder, ground: MeshBuilder) {
        let (c, w, l) = footprint(obstacle)
        let roof = textured("roof", CityArt.roof)
        // Concrete forecourt
        ground.addDecal(center: SIMD3(c.x, 0.1, c.z), direction: SIMD2(0, -1), length: l, width: w,
                        material: textured("forecourt", CityArt.junction), uvScale: SIMD2(w / 8, l / 8))
        // Shop at the back (+x side)
        let shopW = w * 0.34
        let shopCenter = SIMD3(c.x + w / 2 - shopW / 2, 0, c.z)
        box(solid, shopCenter, shopW, 4.2, l * 0.9, textured("shop-2", CityArt.storefront(2)), roof,
            repeats: { span in SIMD2(max(1, (span / 6).rounded()), 1) })
        box(solid, shopCenter + SIMD3(0, 4.2, 0), shopW + 0.4, 0.6, l * 0.9 + 0.4, textured("canopyBand", CityArt.canopyBand), roof)
        // Canopy on pillars over the pumps
        let canopyW = w * 0.56, canopyL = l * 0.8
        let canopyCenter = SIMD3(c.x - w / 2 + canopyW / 2 + 0.5, 0, c.z)
        let pillar = color("pillar", UIColor(white: 0.9, alpha: 1), rough: 0.5)
        for (dx, dz) in [(Float(-0.3), Float(-0.3)), (0.3, -0.3), (-0.3, 0.3), (0.3, 0.3)] {
            box(solid, canopyCenter + SIMD3(dx * canopyW, 0, dz * canopyL), 0.45, 5.2, 0.45, pillar)
        }
        box(solid, canopyCenter + SIMD3(0, 5.2, 0), canopyW, 0.8, canopyL, textured("canopyBand", CityArt.canopyBand),
            color("canopyTop", UIColor(white: 0.92, alpha: 1)), repeats: { span in SIMD2(max(1, (span / 4).rounded()), 1) })
        // Pump islands
        let island = color("island", UIColor(white: 0.75, alpha: 1))
        let pump = color("pump", UIColor(red: 0.10, green: 0.55, blue: 0.30, alpha: 1), rough: 0.5)
        let screen = material("pumpScreen") { Mat.glow(UIColor(red: 0.6, green: 0.95, blue: 1.0, alpha: 1)) }
        for dz in [Float(-0.22), 0.22] {
            let p = canopyCenter + SIMD3(0, 0, dz * canopyL)
            box(solid, p, canopyW * 0.55, 0.2, 1.1, island)
            for dx in [Float(-0.15), 0.15] {
                let q = p + SIMD3(dx * canopyW, 0.2, 0)
                box(solid, q, 0.7, 1.6, 0.5, pump)
                box(solid, q + SIMD3(0, 1.1, 0), 0.5, 0.3, 0.52, screen)
            }
        }
        // Tall price sign at the street corner
        let corner = SIMD3(c.x - w / 2 + 0.8, 0, c.z + l / 2 - 0.8)
        box(solid, corner, 0.35, 6.0, 0.35, color("signPole", UIColor(white: 0.3, alpha: 1), metal: 0.5, rough: 0.4))
        box(solid, corner + SIMD3(0, 6.0, 0), 1.6, 3.2, 0.4, material("fuelSign") {
            let material = Mat.lambert(CityArt.fuelSign)
            material.emission.contents = CityArt.fuelSign
            material.emission.intensity = 0.35
            return material
        })
        contactShadow(ground, center: shopCenter, w: shopW, l: l * 0.9)
    }

    private static func garage(_ obstacle: ObstacleDef, solid: MeshBuilder, ground: MeshBuilder, rng: inout SplitMix64) {
        let (c, w, l) = footprint(obstacle)
        let concrete = color("garageConcrete", UIColor(white: 0.74, alpha: 1), rough: 0.9)
        let band = color("garageBand", UIColor(red: 0.95, green: 0.75, blue: 0.15, alpha: 1), rough: 0.6)
        let deckTop = textured("junction", CityArt.junction)
        let levels = 4
        let story: Float = 3.0
        let carColors = CarArt.parkedColors
        for level in 0...levels {
            let y = Float(level) * story
            // Deck slab (the ground level is the street)
            if level > 0 {
                box(solid, SIMD3(c.x, y - 0.35, c.z), w, 0.35, l, concrete, deckTop)
                // Parapet walls with a yellow safety stripe
                for (dx, dz, span) in [(Float(1), Float(0), l), (-1, 0, l), (0, 1, w), (0, -1, w)] {
                    let p = SIMD3(c.x + dx * (w / 2 - 0.1), y, c.z + dz * (l / 2 - 0.1))
                    if dx != 0 {
                        box(solid, p, 0.2, 1.0, span, concrete)
                        box(solid, p + SIMD3(dx * 0.02, 0.75, 0), 0.22, 0.12, span, band)
                    } else {
                        box(solid, p, span, 1.0, 0.2, concrete)
                        box(solid, p + SIMD3(0, 0.75, dz * 0.02), span, 0.12, 0.22, band)
                    }
                }
            }
            // Columns
            if level < levels {
                let nx = max(2, Int(w / 7)), nz = max(2, Int(l / 7))
                for i in 0...nx {
                    for j in 0...nz where i == 0 || i == nx || j == 0 || j == nz {
                        let p = SIMD3(c.x - w / 2 + 0.3 + Float(i) / Float(nx) * (w - 0.6), y, c.z - l / 2 + 0.3 + Float(j) / Float(nz) * (l - 0.6))
                        box(solid, p, 0.45, story - 0.35, 0.45, concrete)
                    }
                }
            }
            // Parked cars on the upper decks
            if level > 0 {
                var x = c.x - w / 2 + 2.0
                while x < c.x + w / 2 - 2.0 {
                    for row in [Float(-1), 1] where rng.unit() < 0.55 {
                        let pick = rng.int(carColors.count)
                        let paint = color("garageCar-\(pick)", carColors[pick], metal: 0.3, rough: 0.4)
                        let p = SIMD3(x, y, c.z + row * (l / 2 - 3.2))
                        box(solid, p + SIMD3(0, 0.25, 0), 1.8, 0.75, 4.0, paint)
                        box(solid, p + SIMD3(0, 1.0, 0.2), 1.5, 0.55, 2.0, color("garageGlass", UIColor(red: 0.12, green: 0.16, blue: 0.22, alpha: 1), metal: 0.5, rough: 0.2))
                    }
                    x += 2.7
                }
            }
        }
        // Stair tower and the P sign on the roof
        let tower = SIMD3(c.x + w / 2 - 2.0, 0, c.z - l / 2 + 2.0)
        box(solid, tower, 3.2, Float(levels) * story + 2.6, 3.2, color("garageTower", UIColor(red: 0.38, green: 0.42, blue: 0.50, alpha: 1)), concrete)
        let sign = material("parkingSign") {
            let material = Mat.lambert(CityArt.parkingSign)
            material.emission.contents = CityArt.parkingSign
            material.emission.intensity = 0.5
            return material
        }
        box(solid, tower + SIMD3(0, Float(levels) * story + 2.6, 0), 2.6, 2.6, 2.6, sign)
        contactShadow(ground, center: c, w: w, l: l)
    }

    private static func park(_ obstacle: ObstacleDef, solid: MeshBuilder, ground: MeshBuilder, rng: inout SplitMix64) {
        let (c, w, l) = footprint(obstacle)
        ground.addDecal(center: SIMD3(c.x, 0.1, c.z), direction: SIMD2(0, -1), length: l, width: w,
                        material: textured("lawn", CityArt.lawn), uvScale: SIMD2(w / 4, l / 4))
        let paving = textured("pavers", CityArt.pavers)
        ground.addDecal(center: SIMD3(c.x, 0.11, c.z), direction: SIMD2(1, 0), length: w, width: 3.2, material: paving,
                        uvScale: SIMD2(w / 2, 1.6))
        ground.addDecal(center: SIMD3(c.x, 0.11, c.z), direction: SIMD2(0, 1), length: l, width: 3.2, material: paving,
                        uvScale: SIMD2(l / 2, 1.6))
        // Fountain
        let stone = color("stone", UIColor(white: 0.80, alpha: 1), rough: 0.7)
        let water = material("water") {
            let material = Mat.pbr(UIColor(red: 0.25, green: 0.55, blue: 0.80, alpha: 1), metal: 0.4, rough: 0.05)
            return material
        }
        solid.addPrism(center: c, radius: 3.6, height: 0.6, sides: 12, material: stone)
        solid.addPrism(center: c + SIMD3(0, 0.6, 0), radius: 3.1, height: 0.02, sides: 12, material: water)
        solid.addPrism(center: c, radius: 0.5, height: 1.6, sides: 8, material: stone)
        solid.addPrism(center: c + SIMD3(0, 1.6, 0), radius: 1.2, height: 0.3, sides: 10, material: stone, topRadius: 1.4)
        solid.addPrism(center: c + SIMD3(0, 1.9, 0), radius: 1.0, height: 0.01, sides: 10, material: water)
        // Hedge border with gaps for the paths
        let hedge = color("hedge", UIColor(red: 0.20, green: 0.42, blue: 0.20, alpha: 1), rough: 0.9)
        for (dx, dz, span) in [(Float(1), Float(0), l), (-1, 0, l), (0, 1, w), (0, -1, w)] {
            let half = (span - 4) / 2
            for side in [Float(-1), 1] {
                let offset = side * (2 + half / 2)
                let p = SIMD3(c.x + dx * (w / 2 - 0.5) + (dx == 0 ? offset : 0), 0, c.z + dz * (l / 2 - 0.5) + (dz == 0 ? offset : 0))
                if dx != 0 { box(solid, p, 0.9, 0.8, half, hedge) } else { box(solid, p, half, 0.8, 0.9, hedge) }
            }
        }
        // Trees and benches in the four lawns
        for qx in [Float(-1), 1] {
            for qz in [Float(-1), 1] {
                for _ in 0..<(3 + rng.int(2)) {
                    let p = SIMD3(c.x + qx * Float(rng.range(4.5, CGFloat(w / 2 - 2.5))), 0, c.z + qz * Float(rng.range(4.5, CGFloat(l / 2 - 2.5))))
                    tree(solid, ground, at: p, size: Float(rng.range(0.9, 1.3)), variant: rng.int(2))
                }
                bench(solid, at: SIMD3(c.x + qx * 6, 0, c.z + qz * 2.4), alongX: true, facingPositive: qz < 0)
            }
        }
    }

    // MARK: Sidewalks

    private static func tree(_ solid: MeshBuilder, _ ground: MeshBuilder, at p: SIMD3<Float>, size: Float, variant: Int) {
        let trunk = color("trunk", UIColor(red: 0.40, green: 0.28, blue: 0.18, alpha: 1))
        let leaves = [color("leaves0", UIColor(red: 0.26, green: 0.52, blue: 0.24, alpha: 1)),
                      color("leaves1", UIColor(red: 0.36, green: 0.60, blue: 0.26, alpha: 1))]
        solid.addPrism(center: p, radius: 0.16 * size, height: 2.8 * size, sides: 6, material: trunk)
        solid.addBall(center: p + SIMD3(0, 3.9 * size, 0), radius: 1.55 * size, squash: 0.85, material: leaves[variant % 2])
        solid.addBall(center: p + SIMD3(0.45 * size, 5.0 * size, -0.3 * size), radius: 1.0 * size, squash: 0.9,
                      material: leaves[(variant + 1) % 2], rings: 3, segments: 6)
        ground.addDecal(center: SIMD3(p.x, 0.105, p.z), direction: SIMD2(0, 1), length: 3.4 * size, width: 3.4 * size,
                        material: overlay("blob", CityArt.blobShadow))
    }

    private static func bench(_ solid: MeshBuilder, at p: SIMD3<Float>, alongX: Bool, facingPositive: Bool) {
        let wood = color("benchWood", UIColor(red: 0.55, green: 0.36, blue: 0.20, alpha: 1))
        let iron = color("benchIron", UIColor(white: 0.18, alpha: 1), metal: 0.6, rough: 0.5)
        let back: Float = facingPositive ? -0.22 : 0.22
        if alongX {
            box(solid, p + SIMD3(0, 0.42, 0), 1.7, 0.07, 0.5, wood)
            box(solid, p + SIMD3(0, 0.55, back), 1.7, 0.4, 0.06, wood)
            for dx in [Float(-0.7), 0.7] { box(solid, p + SIMD3(dx, 0, 0), 0.08, 0.42, 0.45, iron) }
        } else {
            box(solid, p + SIMD3(0, 0.42, 0), 0.5, 0.07, 1.7, wood)
            box(solid, p + SIMD3(back, 0.55, 0), 0.06, 0.4, 1.7, wood)
            for dz in [Float(-0.7), 0.7] { box(solid, p + SIMD3(0, 0, dz), 0.45, 0.42, 0.08, iron) }
        }
    }

    /// The street lamp positions World3D places (trees keep clear of them).
    private static func lampPoints(city: CityMap, world: CGSize) -> [CGPoint] {
        var result: [CGPoint] = []
        for (j, y) in city.ys.enumerated() {
            var x: CGFloat = 260
            while x < world.width - 200 {
                if !city.xs.contains(where: { abs($0 - x) < 170 }) {
                    if j > 0 { result.append(CGPoint(x: x, y: y - 108)) }
                    if j < city.rows - 1 { result.append(CGPoint(x: x + 200, y: y + 108)) }
                }
                x += 400
            }
        }
        for (i, x) in city.xs.enumerated() {
            var y: CGFloat = 260
            while y < world.height - 200 {
                if !city.ys.contains(where: { abs($0 - y) < 170 }) {
                    if i > 0 { result.append(CGPoint(x: x - 108, y: y)) }
                    if i < city.cols - 1 { result.append(CGPoint(x: x + 108, y: y + 200)) }
                }
                y += 400
            }
        }
        return result
    }

    /// Street trees, benches, bins, hydrants and bus stops along every block edge, plus the soft
    /// shadow the curb throws onto the road.
    private static func sidewalks(city: CityMap, world: CGSize, solid: MeshBuilder, ground: MeshBuilder, rng: inout SplitMix64) {
        let lamps = lampPoints(city: city, world: world)
        let bin = color("bin", UIColor(red: 0.16, green: 0.30, blue: 0.22, alpha: 1), rough: 0.6)
        let hydrant = color("hydrant", UIColor(red: 0.85, green: 0.15, blue: 0.12, alpha: 1), rough: 0.5)
        let shelterFrame = color("shelterFrame", UIColor(white: 0.25, alpha: 1), metal: 0.6, rough: 0.4)
        let shelterGlass = material("shelterGlass") {
            let material = Mat.pbr(UIColor(red: 0.6, green: 0.75, blue: 0.85, alpha: 1), metal: 0.3, rough: 0.1)
            material.transparency = 0.45
            material.isDoubleSided = true
            return material
        }
        let adPanel = material("adPanel") { Mat.glow(UIColor(red: 0.95, green: 0.55, blue: 0.75, alpha: 1)) }
        let pit = color("treePit", UIColor(red: 0.30, green: 0.24, blue: 0.18, alpha: 1), rough: 1)
        let curbShadow = overlay("contact", CityArt.contactShadow)
        var busStops = 0

        for block in city.blocks {
            // Edges as (start, end, inward normal) in world units; trees 12 units (1.2 m) inside the curb
            let edges: [(CGPoint, CGPoint, CGVector)] = [
                (CGPoint(x: block.minX, y: block.minY), CGPoint(x: block.maxX, y: block.minY), CGVector(dx: 0, dy: 1)),
                (CGPoint(x: block.minX, y: block.maxY), CGPoint(x: block.maxX, y: block.maxY), CGVector(dx: 0, dy: -1)),
                (CGPoint(x: block.minX, y: block.minY), CGPoint(x: block.minX, y: block.maxY), CGVector(dx: 1, dy: 0)),
                (CGPoint(x: block.maxX, y: block.minY), CGPoint(x: block.maxX, y: block.maxY), CGVector(dx: -1, dy: 0))
            ]
            for (start, end, inward) in edges {
                let length = hypot(end.x - start.x, end.y - start.y)
                let dir = CGVector(dx: (end.x - start.x) / length, dy: (end.y - start.y) / length)
                let alongX = abs(dir.dx) > 0.5

                // Curb shadow on the road: strip just outside the block edge, dark at the curb
                let mid = CGPoint(x: (start.x + end.x) / 2 - inward.dx * 5, y: (start.y + end.y) / 2 - inward.dy * 5)
                let toCurb = SIMD2<Float>(Float(inward.dx), Float(-inward.dy))
                ground.addDecal(center: v(mid, 0.036), direction: toCurb, length: 1.0, width: Float(length / 10), material: curbShadow)

                var t: CGFloat = 55
                var slot = 0
                while t < length - 55 {
                    let p = CGPoint(x: start.x + dir.dx * t + inward.dx * 13, y: start.y + dir.dy * t + inward.dy * 13)
                    let nearLamp = lamps.contains { abs($0.x - p.x) < 30 && abs($0.y - p.y) < 30 }
                    if slot % 2 == 0 {
                        if !nearLamp {
                            ground.addDecal(center: v(p, 0.095), direction: SIMD2(1, 0), length: 1.3, width: 1.3, material: pit)
                            tree(solid, ground, at: v(p), size: Float(rng.range(0.85, 1.1)), variant: rng.int(2))
                        }
                    } else {
                        let q = CGPoint(x: p.x + inward.dx * 2, y: p.y + inward.dy * 2)
                        let roll = rng.unit()
                        // Bench backs face the buildings: seat faces the road (against `inward`)
                        let facingPositive = alongX ? (inward.dy < 0) : (inward.dx < 0)
                        if roll < 0.06 && busStops < 4 && !nearLamp {
                            busStops += 1
                            busStop(solid, at: v(q), alongX: alongX, awayFromRoad: inward, frame: shelterFrame, glass: shelterGlass, ad: adPanel)
                        } else if roll < 0.36 {
                            bench(solid, at: v(q), alongX: alongX, facingPositive: alongX ? inward.dy > 0 : inward.dx > 0)
                            _ = facingPositive
                        } else if roll < 0.58 {
                            solid.addPrism(center: v(q), radius: 0.3, height: 0.95, sides: 8, material: bin,
                                           top: color("binLid", UIColor(white: 0.15, alpha: 1)))
                        } else if roll < 0.70 {
                            solid.addPrism(center: v(p), radius: 0.16, height: 0.6, sides: 8, material: hydrant)
                            solid.addPrism(center: v(p, 0.6), radius: 0.12, height: 0.12, sides: 8, material: hydrant)
                        }
                    }
                    slot += 1
                    t += 60
                }
            }
        }
    }

    private static func busStop(_ solid: MeshBuilder, at p: SIMD3<Float>, alongX: Bool, awayFromRoad inward: CGVector,
                                frame: SCNMaterial, glass: SCNMaterial, ad: SCNMaterial) {
        let back = SIMD3<Float>(Float(inward.dx), 0, Float(-inward.dy)) * 0.7
        let w: Float = alongX ? 4.0 : 1.6
        let l: Float = alongX ? 1.6 : 4.0
        box(solid, p + SIMD3(0, 2.5, 0), w + 0.2, 0.12, l + 0.2, frame)
        box(solid, p + back, alongX ? 4.0 : 0.06, 2.3, alongX ? 0.06 : 4.0, glass)
        let end = alongX ? SIMD3<Float>(2.0, 0, 0) : SIMD3<Float>(0, 0, 2.0)
        for s in [Float(-1), 1] { box(solid, p + back + end * s, 0.1, 2.5, 0.1, frame) }
        box(solid, p + back + end * 0.98 + SIMD3(0, 0.4, 0), alongX ? 0.12 : 1.3, 1.8, alongX ? 1.3 : 0.12, ad)
        bench(solid, at: p + back * 0.4, alongX: alongX, facingPositive: alongX ? inward.dy > 0 : inward.dx > 0)
    }

    // MARK: Road decals

    private static func roadDecals(city: CityMap, world: CGSize, ground: MeshBuilder, rng: inout SplitMix64) {
        let arrow = overlay("laneArrow", CityArt.laneArrow)
        let manhole = overlay("manhole", CityArt.manhole)
        for j in 0..<city.rows {
            for i in 0..<city.cols {
                let cx = city.xs[i], cy = city.ys[j]
                // (lane center, travel direction in world units, exists)
                let approaches: [(CGPoint, CGVector, Bool)] = [
                    (CGPoint(x: cx - 200, y: cy - 35), CGVector(dx: 1, dy: 0), i > 0),
                    (CGPoint(x: cx + 200, y: cy + 35), CGVector(dx: -1, dy: 0), i < city.cols - 1),
                    (CGPoint(x: cx + 35, y: cy - 200), CGVector(dx: 0, dy: 1), j > 0),
                    (CGPoint(x: cx - 35, y: cy + 200), CGVector(dx: 0, dy: -1), j < city.rows - 1)
                ]
                for (point, travel, exists) in approaches where exists {
                    ground.addDecal(center: v(point, 0.034), direction: SIMD2(Float(travel.dx), Float(-travel.dy)),
                                    length: 5.0, width: 1.25, material: arrow)
                }
            }
        }
        // Manholes along every street segment
        for (j, y) in city.ys.enumerated() {
            _ = j
            var x: CGFloat = 150
            while x < world.width - 150 {
                if !city.xs.contains(where: { abs($0 - x) < 150 }) {
                    let lane: CGFloat = rng.unit() < 0.5 ? 35 : -35
                    ground.addDecal(center: v(CGPoint(x: x, y: y + lane), 0.034), direction: SIMD2(1, 0), length: 1.0, width: 1.0, material: manhole)
                }
                x += 230 + rng.range(0, 120)
            }
        }
        for x in city.xs {
            var y: CGFloat = 150
            while y < world.height - 150 {
                if !city.ys.contains(where: { abs($0 - y) < 150 }) {
                    let lane: CGFloat = rng.unit() < 0.5 ? 35 : -35
                    ground.addDecal(center: v(CGPoint(x: x + lane, y: y), 0.034), direction: SIMD2(0, 1), length: 1.0, width: 1.0, material: manhole)
                }
                y += 230 + rng.range(0, 120)
            }
        }
    }

    // MARK: Skyline

    /// Two rows of towers around the map, fading into the fog.
    private static func skyline(world: CGSize, far: MeshBuilder, ground: MeshBuilder, rng: inout SplitMix64) {
        let minX = Float(-50), maxX = Float(world.width / 10 - 50)
        let maxZ = Float(25), minZ = Float(25 - world.height / 10)
        let facade = textured("skyline", CityArt.skyline)
        let roofColor = color("skylineRoof", UIColor(red: 0.42, green: 0.48, blue: 0.56, alpha: 1))
        for row in 0..<2 {
            let distance: Float = row == 0 ? 30 : 70
            let depthRange: ClosedRange<CGFloat> = row == 0 ? 10...18 : 14...26
            let heightRange: ClosedRange<CGFloat> = row == 0 ? 14...42 : 30...85
            // Walk around the rectangle grown by `distance`
            let x0 = minX - distance, x1 = maxX + distance, z0 = minZ - distance, z1 = maxZ + distance
            let sides: [(SIMD3<Float>, SIMD3<Float>)] = [
                (SIMD3(x0, 0, z0), SIMD3(x1, 0, z0)), (SIMD3(x1, 0, z0), SIMD3(x1, 0, z1)),
                (SIMD3(x1, 0, z1), SIMD3(x0, 0, z1)), (SIMD3(x0, 0, z1), SIMD3(x0, 0, z0))
            ]
            for (a, b) in sides {
                let span = simd_length(b - a)
                let dir = (b - a) / span
                var t: Float = 0
                while t < span {
                    let width = Float(rng.range(10, 22))
                    let depth = Float(rng.range(depthRange.lowerBound, depthRange.upperBound))
                    let height = Float(rng.range(heightRange.lowerBound, heightRange.upperBound))
                    let center = a + dir * (t + width / 2)
                    let alongX = abs(dir.x) > 0.5
                    far.addBox(center: center, width: alongX ? width : depth, height: height, length: alongX ? depth : width,
                               angle: 0, wall: facade, roof: roofColor,
                               wallRepeats: { s in SIMD2(max(1, (s / 6.4).rounded()), max(1, (height / 12.8).rounded())) })
                    t += width + Float(rng.range(1, 6))
                }
            }
        }
    }
}

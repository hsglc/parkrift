import SceneKit
import UIKit
import simd

/// Where a parking level takes place. The level itself (the 100 x 50 m lot, its spots and the
/// cars in it) is the same; what is round it changes: the town, a rooftop deck above it, a mall,
/// a container harbour or a warehouse yard. Everything stays outside the lot and back from its
/// edge (the chase camera swings out up to 14 m past it).
///
/// Surfaces use Poly Haven (CC0) textures, as asset-catalog texture sets ("v_*"); the barrels,
/// crates and concrete barriers are Poly Haven (CC0) models (tools/convert_polyhaven_props.py).
enum Venue: Int, CaseIterable {
    case town, rooftop, mall, harbor, yard

    /// Three levels in a row in each place, round the five places.
    static func of(level index: Int) -> Venue {
        guard index >= 0, index < Levels.cityBase else { return .town }
        return Venue.allCases[(index / 3) % Venue.allCases.count]
    }

    /// Town rows round the lot this venue replaces.
    var skippedSides: Set<String> {
        switch self {
        case .town, .rooftop: return []
        case .mall: return ["n"]
        case .harbor: return ["n", "s", "e", "w"]
        case .yard: return ["n", "w"]
        }
    }

    /// How far the town (and the ground it stands on) sits below the lot: the rooftop deck is
    /// five floors up.
    var townDrop: Float { self == .rooftop ? -15 : 0 }

    /// The lot's own surface: asphalt in town and at the mall, painted concrete elsewhere.
    var lotSurface: String? {
        switch self {
        case .town, .mall: return nil
        case .rooftop: return "v_wall"
        case .harbor, .yard: return "v_yard"
        }
    }

    /// Darkens a light surface so the painted bays still stand out on it
    var lotTint: UIColor? {
        self == .rooftop ? UIColor(white: 0.72, alpha: 1) : nil
    }
}

enum VenueDecor {
    private static var cache: [Venue: SCNNode] = [:]
    private static var materials: [String: SCNMaterial] = [:]

    /// The venue's buildings and props (nil for the town: the lot's usual surroundings).
    static func node(_ venue: Venue) -> SCNNode? {
        if venue == .town { return nil }
        if let cached = cache[venue] { return cached }
        let root = SCNNode()
        switch venue {
        case .rooftop: rooftop(root)
        case .mall: mall(root)
        case .harbor: harbor(root)
        case .yard: yard(root)
        case .town: break
        }
        cache[venue] = root
        return root
    }

    // MARK: Materials

    /// A texture-set material (colour, normal, roughness) for surfaces tiled by their UVs, with
    /// an optional colour multiplied in (container paint).
    static func surface(_ set: String, tint: UIColor? = nil, rough: CGFloat? = nil, metal: CGFloat = 0) -> SCNMaterial {
        let key = set + (tint.map { "\($0)" } ?? "") + "\(rough ?? -1)\(metal)"
        if let cached = materials[key] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = Scenery.texture(set + "_diff")
        material.normal.contents = Scenery.texture(set + "_nor")
        if let rough = rough {
            material.roughness.contents = NSNumber(value: Double(rough))
        } else {
            material.roughness.contents = Scenery.texture(set + "_rough")
        }
        material.metalness.contents = NSNumber(value: Double(metal))
        if let tint = tint { material.multiply.contents = tint }
        for property in [material.diffuse, material.normal, material.roughness] where property.contents is MTLTexture {
            property.wrapS = .repeat
            property.wrapT = .repeat
            property.mipFilter = .linear
            property.maxAnisotropy = 8
            // Texture sets are stored bottom-up: flip v (the UVs from the mesh builder tile it)
            property.contentsTransform = SCNMatrix4MakeScale(1, -1, 1)
        }
        materials[key] = material
        return material
    }

    private static func plain(_ key: String, _ make: () -> SCNMaterial) -> SCNMaterial {
        if let cached = materials[key] { return cached }
        let material = make()
        materials[key] = material
        return material
    }

    /// Repeats for a texture `tile` metres across.
    private static func every(_ tile: Float) -> (Float) -> SIMD2<Float> {
        { length in SIMD2(max(1, (length / tile).rounded()), 1) }
    }

    private static func attach(_ builder: MeshBuilder, to root: SCNNode, shadows: Bool = true) {
        guard let geometry = builder.build() else { return }
        let node = SCNNode(geometry: geometry)
        node.castsShadow = shadows
        root.addChildNode(node)
    }

    /// Clones of a model prop placed round the venue.
    private static func scatter(_ name: String, near: CGFloat, far: CGFloat, at spots: [(SIMD3<Float>, Float)],
                                scale: Float = 1, into root: SCNNode) {
        guard let template = Scenery.prop(name, near: near, far: far, hidden: 120) else { return }
        for (position, yaw) in spots {
            let node = template.clone()
            node.simdPosition = position
            node.eulerAngles.y = yaw
            if scale != 1 { node.scale = SCNVector3(scale, scale, scale) }
            root.addChildNode(node)
        }
    }

    /// A tall lamp post: a slim pole and a glowing head reaching over the lot.
    private static func lampPost(_ mesh: MeshBuilder, at base: SIMD3<Float>, facing yaw: Float, height: Float = 8) {
        let metal = plain("lampMetal") { Mat.pbr(UIColor(white: 0.32, alpha: 1), metal: 0.85, rough: 0.35) }
        let light = plain("lampGlow") { Mat.glow(UIColor(red: 1.0, green: 0.96, blue: 0.86, alpha: 1)) }
        mesh.addPrism(center: base, radius: 0.13, height: height, sides: 8, material: metal, topRadius: 0.09)
        let reach: Float = 1.6
        let head = base + SIMD3<Float>(cos(yaw) * reach / 2, height - 0.1, -sin(yaw) * reach / 2)
        mesh.addBox(center: head, width: reach, height: 0.12, length: 0.18, angle: yaw, wall: metal, roof: metal,
                    wallRepeats: { _ in SIMD2(1, 1) })
        let lamp = base + SIMD3<Float>(cos(yaw) * (reach - 0.2), height - 0.22, -sin(yaw) * (reach - 0.2))
        mesh.addBox(center: lamp, width: 0.7, height: 0.12, length: 0.32, angle: yaw, wall: light, roof: metal,
                    wallRepeats: { _ in SIMD2(1, 1) })
    }

    // MARK: Rooftop

    /// The top deck of a car park, five floors up: a concrete slab with parapets, stair and lift
    /// towers at its corners, lamp posts, and the town (dropped by `townDrop`) all round below.
    private static func rooftop(_ root: SCNNode) {
        let mesh = MeshBuilder()
        let deck = surface("v_wall", tint: UIColor(white: 0.72, alpha: 1))
        let wall = surface("v_wall")
        let halfX: Float = 70, halfZ: Float = 44, thick: Float = 1.2
        // The slab (its top a hair under the lot's surface) and its edge
        mesh.addBox(center: SIMD3(0, -thick - 0.03, 0), width: halfX * 2, height: thick, length: halfZ * 2, angle: 0,
                    wall: wall, roof: deck, wallRepeats: every(4), roofRepeats: SIMD2(Float(halfX * 2 / 6), Float(halfZ * 2 / 6)))
        // Columns down to the street under the edge
        for x in stride(from: -halfX + 4, through: halfX - 4, by: 12) {
            for z in [-halfZ + 1.5, halfZ - 1.5] {
                mesh.addBox(center: SIMD3(x, -15, z), width: 1.0, height: 15 - thick, length: 1.0, angle: 0,
                            wall: wall, roof: wall, wallRepeats: every(3))
            }
        }
        // Parapets round the deck
        let h: Float = 1.15, t: Float = 0.35
        mesh.addBox(center: SIMD3(0, 0, -halfZ + t / 2), width: halfX * 2, height: h, length: t, angle: 0, wall: wall, roof: wall, wallRepeats: every(3))
        mesh.addBox(center: SIMD3(0, 0, halfZ - t / 2), width: halfX * 2, height: h, length: t, angle: 0, wall: wall, roof: wall, wallRepeats: every(3))
        mesh.addBox(center: SIMD3(-halfX + t / 2, 0, 0), width: t, height: h, length: halfZ * 2, angle: 0, wall: wall, roof: wall, wallRepeats: every(3))
        mesh.addBox(center: SIMD3(halfX - t / 2, 0, 0), width: t, height: h, length: halfZ * 2, angle: 0, wall: wall, roof: wall, wallRepeats: every(3))
        // Stair and lift towers outside two corners, with a lit door and a sign band
        let glass = plain("towerGlass") { Mat.pbr(UIColor(red: 0.12, green: 0.18, blue: 0.24, alpha: 1), metal: 0.6, rough: 0.12) }
        let band = plain("towerBand") { Mat.glow(UIColor(red: 0.25, green: 0.75, blue: 1.0, alpha: 1)) }
        for (x, z) in [(-halfX - 3.5, -halfZ + 6), (halfX + 3.5, halfZ - 6)] {
            mesh.addBox(center: SIMD3(Float(x), -16, Float(z)), width: 7, height: 26, length: 8, angle: 0, wall: wall, roof: wall, wallRepeats: every(3))
            mesh.addBox(center: SIMD3(Float(x), 7.6, Float(z)), width: 7.2, height: 0.5, length: 8.2, angle: 0, wall: band, roof: wall, wallRepeats: { _ in SIMD2(1, 1) })
            let face: Float = x < 0 ? 1 : -1
            mesh.addBox(center: SIMD3(Float(x) + face * 3.52, 0, Float(z)), width: 0.05, height: 2.4, length: 2.2, angle: 0, wall: glass, roof: glass, wallRepeats: { _ in SIMD2(1, 1) })
        }
        // Lamp posts along the parapets, heads towards the deck
        for x in stride(from: Float(-60), through: 60, by: 24) {
            lampPost(mesh, at: SIMD3(x, 0, -halfZ + 0.9), facing: -.pi / 2)
            lampPost(mesh, at: SIMD3(x, 0, halfZ - 0.9), facing: .pi / 2)
        }
        attach(mesh, to: root)
        // Concrete barriers by the ramp lane and the towers
        scatter("v_barrier", near: 12, far: 30, at: [
            (SIMD3(-halfX + 3, 0, 0), .pi / 2), (SIMD3(-halfX + 3, 0, 1.5), .pi / 2),
            (SIMD3(halfX - 3, 0, -2), .pi / 2), (SIMD3(halfX - 3, 0, -0.5), .pi / 2)
        ], into: root)
    }

    // MARK: Mall

    /// A shopping centre along the north side: a long glass front under a tiled facade, a lit
    /// entrance canopy and the centre's name in light, with planted trees and benches before it.
    private static func mall(_ root: SCNNode) {
        let mesh = MeshBuilder()
        let facade = surface("v_facade")
        let wall = surface("v_wall")
        let glass = plain("mallGlass") {
            let m = Mat.pbr(UIColor(red: 0.10, green: 0.16, blue: 0.22, alpha: 1), metal: 0.7, rough: 0.08)
            m.emission.contents = UIColor(red: 0.10, green: 0.09, blue: 0.06, alpha: 1)
            return m
        }
        let frame = plain("mallFrame") { Mat.pbr(UIColor(white: 0.85, alpha: 1), metal: 0.8, rough: 0.3) }
        let warm = plain("mallWarm") { Mat.glow(UIColor(red: 1.0, green: 0.86, blue: 0.62, alpha: 1)) }
        let front: Float = -37        // the building's face (12 m north of the lot)
        let depth: Float = 34, width: Float = 150, height: Float = 17
        let centre = SIMD3<Float>(0, 0, front - depth / 2)
        mesh.addBox(center: centre, width: width, height: height, length: depth, angle: 0, wall: facade, roof: wall,
                    wallRepeats: { length in SIMD2(max(1, (length / 6).rounded()), max(1, (height / 6).rounded())) })
        // Ground floor: a glass front with mullions, recessed under the facade
        mesh.addBox(center: SIMD3(0, 0, front + 0.05), width: width - 2, height: 6, length: 0.1, angle: 0, wall: glass, roof: glass,
                    wallRepeats: { _ in SIMD2(1, 1) })
        for x in stride(from: -width / 2 + 3, through: width / 2 - 3, by: 4) {
            mesh.addBox(center: SIMD3(x, 0, front + 0.12), width: 0.18, height: 6, length: 0.12, angle: 0, wall: frame, roof: frame,
                        wallRepeats: { _ in SIMD2(1, 1) })
        }
        mesh.addBox(center: SIMD3(0, 6, front + 0.15), width: width - 2, height: 0.35, length: 0.3, angle: 0, wall: frame, roof: frame,
                    wallRepeats: { _ in SIMD2(1, 1) })
        // Entrance canopy with a warm light under it, and a second one further along
        for x: Float in [-38, 38] {
            mesh.addBox(center: SIMD3(x, 5.2, front + 3), width: 14, height: 0.5, length: 6, angle: 0, wall: frame, roof: wall,
                        wallRepeats: { _ in SIMD2(1, 1) })
            mesh.addBox(center: SIMD3(x, 5.1, front + 3), width: 12, height: 0.1, length: 4.4, angle: 0, wall: warm, roof: warm,
                        wallRepeats: { _ in SIMD2(1, 1) })
            for side: Float in [-6.6, 6.6] {
                mesh.addPrism(center: SIMD3(x + side, 0, front + 5.6), radius: 0.18, height: 5.2, sides: 8, material: frame)
            }
        }
        // Lamp posts at the lot's edge facing the mall
        for x in stride(from: Float(-55), through: 55, by: 22) {
            lampPost(mesh, at: SIMD3(x, 0, -28.5), facing: -.pi / 2)
        }
        attach(mesh, to: root)
        // The centre's name in light above the entrance
        let sign = SCNNode(geometry: SCNPlane(width: 30, height: 4.2))
        let signMaterial = SCNMaterial()
        signMaterial.lightingModel = .constant
        signMaterial.diffuse.contents = signImage(Strings.pick("PARKRIFT AVM", "PARKRIFT MALL", "PARKRIFT CENTRO"))
        signMaterial.isDoubleSided = false
        signMaterial.transparencyMode = .aOne
        sign.geometry?.materials = [signMaterial]
        sign.position = SCNVector3(0, 11.5, front + 0.2)
        sign.castsShadow = false
        root.addChildNode(sign)
        // Trees in planters and benches along the front
        if let tree = Scenery.trees.first {
            for x: Float in [-58, -20, 20, 58] {
                let node = tree.clone()
                node.simdPosition = SIMD3(x, 0, front + 9)
                node.eulerAngles.y = x * 0.37
                root.addChildNode(node)
            }
        }
        scatter("v_barrier", near: 12, far: 30, at: [(SIMD3(-66, 0, -30), 0), (SIMD3(66, 0, -30), 0)], into: root)
    }

    /// The mall's name in light: glowing letters with a soft halo, on transparency.
    private static func signImage(_ text: String) -> UIImage {
        let size = CGSize(width: 1400, height: 196)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let font = UIFont(name: "AvenirNext-Heavy", size: 150) ?? UIFont.systemFont(ofSize: 150, weight: .heavy)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(red: 1, green: 0.97, blue: 0.9, alpha: 1)]
            let textSize = (text as NSString).size(withAttributes: attributes)
            let origin = CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2)
            context.cgContext.setShadow(offset: .zero, blur: 26, color: UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 1).cgColor)
            for _ in 0..<2 { (text as NSString).draw(at: origin, withAttributes: attributes) }
        }
    }

    // MARK: Harbour

    /// A container terminal: a concrete quay round the lot with bollards on its edge, the sea to
    /// the south and east (a ship and a quay crane on it), and stacks of containers north and west.
    private static func harbor(_ root: SCNNode) {
        let mesh = MeshBuilder()
        let quay = surface("v_yard")
        let wall = surface("v_wall")
        // Quay slab: the lot sits in it; it ends at the water 16 m south and east of the lot
        let minX: Float = -140, maxX: Float = 66, minZ: Float = -120, maxZ: Float = 41
        mesh.addBox(center: SIMD3((minX + maxX) / 2, -2.4, (minZ + maxZ) / 2), width: maxX - minX, height: 2.37, length: maxZ - minZ,
                    angle: 0, wall: wall, roof: quay, wallRepeats: every(4), roofRepeats: SIMD2((maxX - minX) / 5, (maxZ - minZ) / 5))
        // Bollards and a painted edge line along the water
        let iron = plain("bollard") { Mat.pbr(UIColor(white: 0.12, alpha: 1), metal: 0.6, rough: 0.5) }
        let yellow = plain("quayEdge") { Mat.pbr(UIColor(red: 0.95, green: 0.78, blue: 0.12, alpha: 1), rough: 0.6) }
        for x in stride(from: minX + 6, through: maxX - 2, by: 9) {
            mesh.addPrism(center: SIMD3(x, 0, maxZ - 1), radius: 0.28, height: 0.7, sides: 10, material: iron, topRadius: 0.36)
        }
        for z in stride(from: minZ + 6, through: maxZ - 2, by: 9) {
            mesh.addPrism(center: SIMD3(maxX - 1, 0, z), radius: 0.28, height: 0.7, sides: 10, material: iron, topRadius: 0.36)
        }
        mesh.addBox(center: SIMD3((minX + maxX) / 2, 0, maxZ - 0.25), width: maxX - minX, height: 0.03, length: 0.4, angle: 0,
                    wall: yellow, roof: yellow, wallRepeats: { _ in SIMD2(1, 1) })
        mesh.addBox(center: SIMD3(maxX - 0.25, 0, (minZ + maxZ) / 2), width: 0.4, height: 0.03, length: maxZ - minZ, angle: 0,
                    wall: yellow, roof: yellow, wallRepeats: { _ in SIMD2(1, 1) })
        attach(mesh, to: root)

        // Container stacks: 40 ft boxes in six liveries, one to three high
        let liveries: [UIColor] = [UIColor(red: 0.72, green: 0.16, blue: 0.12, alpha: 1), UIColor(red: 0.12, green: 0.32, blue: 0.62, alpha: 1),
                                   UIColor(red: 0.16, green: 0.46, blue: 0.26, alpha: 1), UIColor(red: 0.92, green: 0.52, blue: 0.12, alpha: 1),
                                   UIColor(white: 0.62, alpha: 1), UIColor(red: 0.90, green: 0.88, blue: 0.82, alpha: 1)]
        let boxes = MeshBuilder()
        var rng = SplitMix64(seed: 77)
        func container(_ c: SIMD3<Float>, angle: Float) {
            let paint = surface("v_container", tint: liveries[rng.int(liveries.count)], metal: 0.35)
            boxes.addBox(center: c, width: 12.2, height: 2.6, length: 2.44, angle: angle, wall: paint, roof: paint,
                         wallRepeats: { length in SIMD2(max(1, (length / 3).rounded()), 1) }, roofRepeats: SIMD2(4, 1))
        }
        // North: rows along x, 13 m and more from the lot
        for row in 0..<4 {
            let z = -39 - Float(row) * 3.2 - Float(row / 2) * 6
            for k in 0..<9 {
                let x = -66 + Float(k) * 13.4
                let high = 1 + rng.int(3)
                for level in 0..<high { container(SIMD3(x, Float(level) * 2.6, z), angle: 0) }
            }
        }
        // West: rows along z
        for row in 0..<3 {
            let x = -64 - Float(row) * 3.2 - Float(row / 2) * 6
            for k in 0..<5 {
                let z = -24 + Float(k) * 12.8
                let high = 1 + rng.int(3)
                for level in 0..<high { container(SIMD3(x, Float(level) * 2.6, z), angle: .pi / 2) }
            }
        }
        attach(boxes, to: root)

        // The sea: a wide plane with a moving ripple normal map and the sky in it
        let water = SCNPlane(width: 1400, height: 1400)
        let sea = SCNMaterial()
        sea.lightingModel = .physicallyBased
        sea.diffuse.contents = UIColor(red: 0.05, green: 0.17, blue: 0.22, alpha: 1)
        sea.metalness.contents = NSNumber(value: 0.25)
        sea.roughness.contents = NSNumber(value: 0.06)
        if let ripples = Scenery.texture("v_water_nor") {
            sea.normal.contents = ripples
            sea.normal.intensity = 0.8
            sea.normal.wrapS = .repeat
            sea.normal.wrapT = .repeat
            sea.normal.contentsTransform = SCNMatrix4MakeScale(140, -140, 1)
        }
        water.materials = [sea]
        let waterNode = SCNNode(geometry: water)
        waterNode.eulerAngles.x = -.pi / 2
        waterNode.position = SCNVector3(0, -1.6, 0)
        waterNode.castsShadow = false
        // Ripples drift slowly
        waterNode.runAction(.repeatForever(.customAction(duration: 60) { node, elapsed in
            let shift = Float(elapsed) / 60
            node.geometry?.firstMaterial?.normal.contentsTransform =
                SCNMatrix4Mult(SCNMatrix4MakeScale(140, -140, 1), SCNMatrix4MakeTranslation(shift * 3, shift * 2, 0))
        }))
        root.addChildNode(waterNode)

        // A quay crane on the east edge, its boom over the water, and a container ship beyond
        let crane = MeshBuilder()
        let red = plain("craneRed") { Mat.pbr(UIColor(red: 0.78, green: 0.18, blue: 0.12, alpha: 1), metal: 0.5, rough: 0.45) }
        let white = plain("craneWhite") { Mat.pbr(UIColor(white: 0.9, alpha: 1), metal: 0.4, rough: 0.5) }
        for z: Float in [-36, -20] {
            for x: Float in [61, 75] {
                crane.addBox(center: SIMD3(x, -1.6, z), width: 1.2, height: 34, length: 1.2, angle: 0, wall: red, roof: red, wallRepeats: { _ in SIMD2(1, 1) })
            }
        }
        crane.addBox(center: SIMD3(80, 30, -28), width: 64, height: 2.2, length: 4, angle: 0, wall: white, roof: white, wallRepeats: { _ in SIMD2(1, 1) })
        crane.addBox(center: SIMD3(68, 32.2, -28), width: 8, height: 4, length: 6, angle: 0, wall: white, roof: red, wallRepeats: { _ in SIMD2(1, 1) })
        attach(crane, to: root)
        let ship = MeshBuilder()
        let hull = plain("shipHull") { Mat.pbr(UIColor(red: 0.10, green: 0.14, blue: 0.22, alpha: 1), metal: 0.3, rough: 0.5) }
        let bottom = plain("shipBottom") { Mat.pbr(UIColor(red: 0.55, green: 0.12, blue: 0.10, alpha: 1), rough: 0.6) }
        ship.addBox(center: SIMD3(150, -4, -10), width: 26, height: 3, length: 190, angle: 0, wall: bottom, roof: bottom, wallRepeats: { _ in SIMD2(1, 1) })
        ship.addBox(center: SIMD3(150, -1, -10), width: 26, height: 8, length: 190, angle: 0, wall: hull, roof: hull, wallRepeats: { _ in SIMD2(1, 1) })
        ship.addBox(center: SIMD3(150, 7, 72), width: 22, height: 16, length: 12, angle: 0, wall: white, roof: white, wallRepeats: { _ in SIMD2(1, 1) })
        var shipRng = SplitMix64(seed: 5)
        for k in 0..<12 {
            for lane in 0..<3 {
                let paint = surface("v_container", tint: liveries[shipRng.int(liveries.count)], metal: 0.35)
                let high = 1 + shipRng.int(3)
                for level in 0..<high {
                    ship.addBox(center: SIMD3(141 + Float(lane) * 8.5, 7 + Float(level) * 2.6, -88 + Float(k) * 13),
                                width: 2.44, height: 2.6, length: 12.2, angle: 0, wall: paint, roof: paint,
                                wallRepeats: { length in SIMD2(max(1, (length / 3).rounded()), 1) })
                }
            }
        }
        attach(ship, to: root, shadows: false)
        // Barrels and crates by the containers
        scatter("v_barrel", near: 10, far: 26, at: [
            (SIMD3(-40, 0, -33), 0), (SIMD3(-39.3, 0, -33.4), 1), (SIMD3(-40.4, 0, -32.3), 2),
            (SIMD3(30, 0, -33.5), 0.4), (SIMD3(30.7, 0, -33), 1.3)
        ], into: root)
        scatter("v_crate", near: 10, far: 26, at: [
            (SIMD3(-58, 0, -32), 0.1), (SIMD3(-58, 0.75, -32), 0.3), (SIMD3(12, 0, -33), -0.2)
        ], into: root)
    }

    // MARK: Yard

    /// A warehouse yard: two long corrugated sheds (north and west) with roll-up doors and loading
    /// docks, floodlights, pallet stacks, barrels and crates, and barriers along the open sides.
    private static func yard(_ root: SCNNode) {
        let mesh = MeshBuilder()
        let iron = surface("v_corrugated", metal: 0.45)
        let roofSheet = surface("v_corrugated", tint: UIColor(white: 0.7, alpha: 1), metal: 0.45)
        let shutter = surface("v_shutter")
        let concrete = surface("v_wall")
        let flood = plain("floodGlow") { Mat.glow(UIColor(red: 1, green: 0.97, blue: 0.9, alpha: 1)) }
        let bumper = plain("dockBumper") { Mat.pbr(UIColor(white: 0.08, alpha: 1), rough: 0.8) }
        // North shed: its front 13 m from the lot, docks along it
        let front: Float = -38
        mesh.addBox(center: SIMD3(0, 0, front - 15), width: 150, height: 12, length: 30, angle: 0, wall: iron, roof: roofSheet,
                    wallRepeats: { length in SIMD2(max(1, (length / 2.5).rounded()), 4) }, roofRepeats: SIMD2(50, 10))
        mesh.addBox(center: SIMD3(0, 0, front + 1.5), width: 150, height: 1.2, length: 3, angle: 0, wall: concrete, roof: concrete,
                    wallRepeats: every(3))
        for x in stride(from: Float(-60), through: 60, by: 15) {
            mesh.addWall(from: SIMD3(x - 2, 1.2, front + 0.01), to: SIMD3(x + 2, 1.2, front + 0.01), height: 4.2,
                         normal: SIMD3(0, 0, 1), material: shutter, uvMax: SIMD2(1, 1))
            for side: Float in [-2.3, 2.3] {
                mesh.addBox(center: SIMD3(x + side, 0.4, front + 3.05), width: 0.35, height: 0.7, length: 0.3, angle: 0,
                            wall: bumper, roof: bumper, wallRepeats: { _ in SIMD2(1, 1) })
            }
            mesh.addBox(center: SIMD3(x, 6.4, front + 0.3), width: 1.2, height: 0.35, length: 0.6, angle: 0, wall: flood, roof: iron,
                        wallRepeats: { _ in SIMD2(1, 1) })
        }
        // West shed
        let side: Float = -63
        mesh.addBox(center: SIMD3(side - 13, 0, -6), width: 26, height: 10, length: 80, angle: 0, wall: iron, roof: roofSheet,
                    wallRepeats: { length in SIMD2(max(1, (length / 2.5).rounded()), 3) }, roofRepeats: SIMD2(10, 30))
        for z in stride(from: Float(-30), through: 18, by: 16) {
            mesh.addWall(from: SIMD3(side + 0.01, 0, z - 2), to: SIMD3(side + 0.01, 0, z + 2), height: 4.5,
                         normal: SIMD3(1, 0, 0), material: shutter, uvMax: SIMD2(1, 1))
            mesh.addBox(center: SIMD3(side + 0.3, 5.4, z), width: 0.6, height: 0.35, length: 1.2, angle: 0, wall: flood, roof: iron,
                        wallRepeats: { _ in SIMD2(1, 1) })
        }
        // Pallet stacks: slatted wooden boxes
        let wood = surface("v_pier", rough: 0.8)
        var rng = SplitMix64(seed: 31)
        for (x, z) in [(-50.0, -32.0), (-46.0, -32.5), (40.0, -32.0), (44.5, -33.0), (-58.0, 28.0), (-58.5, 18.0)] {
            let layers = 2 + rng.int(4)
            for level in 0..<layers {
                mesh.addBox(center: SIMD3(Float(x), Float(level) * 0.16, Float(z)), width: 1.2, height: 0.14, length: 1.0,
                            angle: Float(rng.range(-0.08, 0.08)), wall: wood, roof: wood, wallRepeats: { _ in SIMD2(1, 1) })
            }
        }
        attach(mesh, to: root)
        scatter("v_barrel", near: 10, far: 26, at: [
            (SIMD3(-30, 0, -33), 0), (SIMD3(-29.3, 0, -33.4), 1), (SIMD3(-30.5, 0, -32.4), 2), (SIMD3(-29.6, 0, -32.2), 3),
            (SIMD3(-58, 0, 6), 0.5), (SIMD3(-58.4, 0, 6.7), 1.5)
        ], into: root)
        scatter("v_crate", near: 10, far: 26, at: [
            (SIMD3(20, 0, -33), 0.05), (SIMD3(20, 0.75, -33), -0.1), (SIMD3(22.2, 0, -33.2), 0.12), (SIMD3(-57.5, 0, -14), 1.6)
        ], into: root)
        // Concrete barriers along the open south and east sides, back from the camera's swing
        var barriers: [(SIMD3<Float>, Float)] = []
        for x in stride(from: Float(-60), through: 60, by: 4.2) { barriers.append((SIMD3(x, 0, 42), 0)) }
        for z in stride(from: Float(-30), through: 38, by: 4.2) { barriers.append((SIMD3(68, 0, z), .pi / 2)) }
        scatter("v_barrier", near: 12, far: 30, at: barriers, into: root)
    }
}

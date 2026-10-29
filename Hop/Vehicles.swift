import SceneKit
import UIKit
import simd

/// A traffic car: model files, wheel spots and size (meters, +x forward). Numbers from
/// tools/convert_meshy_cars.py (NPC=1).
struct TrafficModel {
    let id: String
    let wheels: [(Float, Float, Float, Bool)]
    let wheelRadius: Float
    /// Side (z sign) the exported wheel model sits on; the other side is turned around.
    let wheelModelSide: Float
    let length: Float
    let width: Float
    let height: Float
    /// Rear end (x) of the body.
    let rear: Float
    /// Painted through a mask in many colours (the police car keeps its livery).
    let painted: Bool

    var file: String { "npc_" + id }
}

/// Traffic, parked and patrol cars, and the police car: five original cars generated with Meshy
/// AI (4K PBR, maps at 2K for the game). The four everyday cars come in many paints; each paint is
/// a material sharing the car's mesh and textures, so more colours cost no extra memory.
enum TrafficVehicles {
    static let models: [String: TrafficModel] = [
        "hatch": TrafficModel(id: "hatch", wheels: [(1.189, 0.299, -0.727, true), (1.189, 0.299, 0.738, true), (-1.287, 0.302, -0.726, false), (-1.286, 0.302, 0.734, false)],
                              wheelRadius: 0.301, wheelModelSide: -1, length: 4.0, width: 2.010, height: 1.701, rear: -2.000, painted: true),
        "sedan": TrafficModel(id: "sedan", wheels: [(1.383, 0.319, -0.753, true), (1.383, 0.319, 0.746, true), (-1.249, 0.319, -0.753, false), (-1.245, 0.321, 0.740, false)],
                              wheelRadius: 0.320, wheelModelSide: -1, length: 4.7, width: 2.010, height: 1.422, rear: -2.350, painted: true),
        "suv": TrafficModel(id: "suv", wheels: [(1.434, 0.392, -0.829, true), (1.435, 0.394, 0.832, true), (-1.349, 0.391, -0.829, false), (-1.352, 0.391, 0.828, false)],
                            wheelRadius: 0.392, wheelModelSide: -1, length: 4.6, width: 2.173, height: 2.016, rear: -2.300, painted: true),
        "pickup": TrafficModel(id: "pickup", wheels: [(1.653, 0.359, -0.819, true), (1.655, 0.359, 0.799, true), (-1.443, 0.359, -0.819, false), (-1.453, 0.361, 0.799, false)],
                               wheelRadius: 0.360, wheelModelSide: -1, length: 5.3, width: 2.241, height: 1.738, rear: -2.650, painted: true),
        "police": TrafficModel(id: "police", wheels: [(1.367, 0.324, -0.725, true), (1.367, 0.325, 0.730, true), (-1.309, 0.334, -0.725, false), (-1.309, 0.334, 0.725, false)],
                               wheelRadius: 0.329, wheelModelSide: -1, length: 4.9, width: 1.910, height: 1.453, rear: -2.450, painted: false),
    ]

    /// How often each car shows up in traffic and car parks.
    private static let mix: [(String, Int)] = [("hatch", 3), ("sedan", 3), ("suv", 2), ("pickup", 2)]
    private static let pool: [String] = mix.flatMap { Array(repeating: $0.0, count: $0.1) }

    /// Everyday car paints.
    static let paints: [UIColor] = [
        UIColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 1),   // white
        UIColor(red: 0.62, green: 0.64, blue: 0.67, alpha: 1),   // silver
        UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1),   // black
        UIColor(red: 0.26, green: 0.28, blue: 0.31, alpha: 1),   // graphite
        UIColor(red: 0.62, green: 0.05, blue: 0.06, alpha: 1),   // red
        UIColor(red: 0.08, green: 0.22, blue: 0.55, alpha: 1),   // blue
        UIColor(red: 0.30, green: 0.52, blue: 0.75, alpha: 1),   // sky blue
        UIColor(red: 0.10, green: 0.30, blue: 0.20, alpha: 1),   // dark green
        UIColor(red: 0.72, green: 0.64, blue: 0.50, alpha: 1),   // beige
        UIColor(red: 0.92, green: 0.62, blue: 0.08, alpha: 1),   // amber
        UIColor(red: 0.40, green: 0.10, blue: 0.14, alpha: 1)    // wine
    ]
    /// White, silver, black and grey show up more often, as on real streets.
    private static let paintPool: [Int] = [0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10]

    private static let lock = NSRecursiveLock()
    private static var meshes: [String: SCNNode] = [:]
    private static var wheelMeshes: [String: SCNNode] = [:]
    private static var bodies: [String: SCNNode] = [:]
    private static var wheels: [String: SCNNode] = [:]
    private static var wheelSets: [String: SCNNode] = [:]
    private static var parkedTemplates: [String: SCNNode] = [:]
    private static var images: [String: UIImage] = [:]

    /// A car for this seed (same seed, same car).
    static func pick(_ seed: Int) -> TrafficModel? {
        let index = (abs(seed &* 2654435761) >> 7) % pool.count
        return models[pool[index]]
    }

    /// A paint for this seed (same seed, same paint).
    static func paint(_ seed: Int) -> Int {
        paintPool[(abs(seed &* 40503 &+ 977) >> 3) % paintPool.count]
    }

    private static func image(_ name: String) -> UIImage? {
        if let cached = images[name] { return cached }
        let loaded = UIImage(named: name)
        images[name] = loaded
        return loaded
    }

    /// The car's own texture and maps (one material per car and paint, shared by every copy).
    private static func material(_ model: TrafficModel, paint: Int?) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = image(model.file + "_basecolor.jpg")
        material.diffuse.mipFilter = .linear
        material.normal.contents = image(model.file + "_normal.jpg")
        material.normal.mipFilter = .linear
        material.roughness.contents = image(model.file + "_rough.jpg")
        material.roughness.mipFilter = .linear
        material.metalness.contents = image(model.file + "_metal.jpg")
        material.metalness.mipFilter = .linear
        material.isDoubleSided = true
        guard let paint = paint else { return material }
        if let mask = image(model.file + "_mask.png") {
            material.clearCoat.contents = mask
            material.clearCoat.intensity = 0.9
            material.clearCoatRoughness.contents = NSNumber(value: 0.05)
            CarModels.applyPaintShader(material, mask: mask, color: paints[paint % paints.count])
        }
        return material
    }

    /// Body and wheel meshes as read from the files (any thread).
    private static func mesh(_ model: TrafficModel) -> SCNNode? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = meshes[model.id] { return cached }
        let node = CarModels.load(model.file + "_body")
        meshes[model.id] = node
        return node
    }

    private static var lodShells: [String: SCNGeometry] = [:]
    /// The body's textured shell reduced for distance (tools/make_npc_lods.py).
    private static func lodShell(_ model: TrafficModel) -> SCNGeometry? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = lodShells[model.id] { return cached }
        var found: SCNGeometry?
        CarModels.load(model.file + "_body_lod")?.enumerateHierarchy { node, stop in
            if node.name == "textured", let geometry = node.geometry { found = geometry; stop.pointee = true }
        }
        if let found = found { lodShells[model.id] = found }
        return found
    }

    private static func wheelMesh(_ model: TrafficModel) -> SCNNode? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = wheelMeshes[model.id] { return cached }
        let node = CarModels.load(model.file + "_wheel")
        wheelMeshes[model.id] = node
        return node
    }

    /// The body in a paint (`nil`: its own livery).
    static func body(_ model: TrafficModel, paint: Int?) -> SCNNode? {
        lock.lock()
        defer { lock.unlock() }
        let key = model.id + "/" + (paint.map(String.init) ?? "-")
        if let cached = bodies[key] { return cached }
        guard let source = mesh(model) else { return nil }
        let body = source.clone()
        let paintMaterial = material(model, paint: model.painted ? paint : nil)
        body.enumerateHierarchy { node, _ in
            guard let name = node.name, let geometry = node.geometry?.copy() as? SCNGeometry else { return }
            switch name {
            case "textured":
                geometry.materials = [paintMaterial]
                // A light shell (a fifth of the triangles) a little way off
                if let lod = lodShell(model)?.copy() as? SCNGeometry {
                    lod.materials = [paintMaterial]
                    geometry.levelsOfDetail = [SCNLevelOfDetail(geometry: lod, worldSpaceDistance: 24)]
                }
            case "lamp_red", "lamp_blue":
                // Found by these colours and flashed by the police chase
                let lamp = Mat.pbr(name == "lamp_red" ? UIColor(red: 0.9, green: 0.05, blue: 0.05, alpha: 1)
                                                      : UIColor(red: 0.05, green: 0.2, blue: 0.9, alpha: 1), metal: 0, rough: 0.2)
                lamp.emission.contents = UIColor.black
                geometry.materials = [lamp]
            default:
                return
            }
            node.geometry = geometry
        }
        bodies[key] = body
        return body
    }

    private static var wheelMaterials: [String: SCNMaterial] = [:]
    private static func wheelMaterial(_ model: TrafficModel) -> SCNMaterial {
        if let cached = wheelMaterials[model.id] { return cached }
        let made = material(model, paint: nil)
        wheelMaterials[model.id] = made
        return made
    }

    /// One wheel (tyre and rim) with the car's texture.
    static func wheel(_ model: TrafficModel) -> SCNNode? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = wheels[model.id] { return cached }
        guard let source = wheelMesh(model) else { return nil }
        let wheel = source.clone()
        let shared = wheelMaterial(model)
        wheel.enumerateHierarchy { node, _ in
            node.castsShadow = false
            guard let geometry = node.geometry?.copy() as? SCNGeometry else { return }
            geometry.materials = [shared]
            node.geometry = geometry
        }
        wheels[model.id] = wheel
        return wheel
    }

    /// All four wheels as one mesh, for cars that never move.
    private static func wheelSet(_ model: TrafficModel) -> SCNNode? {
        if let cached = wheelSets[model.id] { return cached }
        guard let wheel = wheel(model) else { return nil }
        let holder = SCNNode()
        for spot in model.wheels {
            let copy = wheel.clone()
            copy.position = SCNVector3(spot.0, spot.1, spot.2)
            if (spot.2 > 0) != (model.wheelModelSide > 0) { copy.eulerAngles.y = Float.pi }
            holder.addChildNode(copy)
        }
        let set = SCNNode()
        // No normal map on the merged wheels: SceneKit crashed building tangents for a mesh made
        // in code (and the tyres' fine relief is not seen on parked cars anyway)
        let flatWheels = wheelMaterial(model).copy() as! SCNMaterial
        flatWheels.normal.contents = nil
        if let merged = MeshMerge.merge(holder, material: flatWheels) {
            // Past 40 m the wheels of a parked car are hidden under its body anyway
            merged.levelsOfDetail = [SCNLevelOfDetail(geometry: nil, worldSpaceDistance: 40)]
            set.geometry = merged
        } else {
            // Could not merge: the four wheels as they are
            set.addChildNode(holder)
        }
        set.castsShadow = false
        wheelSets[model.id] = set
        return set
    }

    /// A parked car: its body and one merged wheel mesh.
    static func parked(_ model: TrafficModel, paint: Int) -> SCNNode? {
        lock.lock()
        defer { lock.unlock() }
        let key = model.id + "/" + String(paint)
        if let cached = parkedTemplates[key] { return cached }
        guard let body = body(model, paint: paint) else { return nil }
        let holder = SCNNode()
        holder.addChildNode(body.clone())
        if let wheels = wheelSet(model) { holder.addChildNode(wheels.clone()) }
        parkedTemplates[key] = holder
        return holder
    }

    /// The police car of a chase. Its wheels are nodes named "wheel…" whose x rotation rolls them
    /// (what `PoliceChase` turns), and its light bar lenses are red and blue materials.
    static func policeTemplate() -> SCNNode? {
        guard let model = models["police"], let body = body(model, paint: nil) else { return nil }
        let holder = SCNNode()
        holder.addChildNode(body.clone())
        if let wheel = wheel(model) {
            for (index, spot) in model.wheels.enumerated() {
                // Turned so that the node's x axis is the axle: rolling is a turn about x
                let pivot = SCNNode()
                pivot.name = "wheel\(index)"
                pivot.position = SCNVector3(spot.0, spot.1, spot.2)
                pivot.eulerAngles.y = Float.pi / 2
                let copy = wheel.clone()
                copy.eulerAngles.y = -Float.pi / 2 + ((spot.2 > 0) != (model.wheelModelSide > 0) ? Float.pi : 0)
                pivot.addChildNode(copy)
                holder.addChildNode(pivot)
            }
        }
        return holder
    }

    /// Reads every car's meshes (background thread); materials are made when first used.
    static func preload() {
        for model in models.values {
            _ = mesh(model)
            _ = wheelMesh(model)
        }
    }

    /// Geometry of every car made so far, for the GPU warm-up.
    static var allGeometries: [SCNGeometry] {
        lock.lock()
        let nodes = Array(bodies.values) + Array(wheels.values) + Array(wheelSets.values)
        lock.unlock()
        var result: [SCNGeometry] = []
        for node in nodes {
            node.enumerateHierarchy { child, _ in
                if let geometry = child.geometry { result.append(geometry) }
            }
        }
        return result
    }
}

/// Merges the meshes under some nodes into one triangle mesh (positions, normals and the first
/// UV set, in the holder's space) with one material. SceneKit's flattenedClone dropped the
/// traffic cars' wheels (parked cars stood on bare wheel arches), so the four wheels are joined
/// here by hand: one draw call per parked car instead of eight.
enum MeshMerge {
    static func floats(_ source: SCNGeometrySource, components: Int) -> [[Float]] {
        guard source.usesFloatComponents, source.bytesPerComponent == 4 else { return [] }
        var result: [[Float]] = []
        result.reserveCapacity(source.vectorCount)
        source.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<source.vectorCount {
                let base = source.dataOffset + i * source.dataStride
                var v = [Float](repeating: 0, count: components)
                for c in 0..<min(components, source.componentsPerVector) {
                    v[c] = raw.load(fromByteOffset: base + c * 4, as: Float.self)
                }
                result.append(v)
            }
        }
        return result
    }

    static func indices(_ element: SCNGeometryElement) -> [UInt32] {
        guard element.primitiveType == .triangles else { return [] }
        let count = element.primitiveCount * 3
        var out: [UInt32] = []
        out.reserveCapacity(count)
        element.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<count {
                switch element.bytesPerIndex {
                case 1: out.append(UInt32(raw.load(fromByteOffset: i, as: UInt8.self)))
                case 2: out.append(UInt32(raw.load(fromByteOffset: i * 2, as: UInt16.self)))
                default: out.append(raw.load(fromByteOffset: i * 4, as: UInt32.self))
                }
            }
        }
        return out
    }

    static func merge(_ holder: SCNNode, material: SCNMaterial) -> SCNGeometry? {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var all: [UInt32] = []
        holder.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry,
                  let vertexSource = geometry.sources(for: .vertex).first else { return }
            let transform = node.simdConvertTransform(matrix_identity_float4x4, to: holder)
            let normalMatrix = simd_float3x3(SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                                             SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                                             SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
            let p = floats(vertexSource, components: 3)
            let n = geometry.sources(for: .normal).first.map { floats($0, components: 3) } ?? []
            let t = geometry.sources(for: .texcoord).first.map { floats($0, components: 2) } ?? []
            let base = UInt32(positions.count)
            for i in 0..<p.count {
                let w = transform * SIMD4<Float>(p[i][0], p[i][1], p[i][2], 1)
                positions.append(SCNVector3(w.x, w.y, w.z))
                if i < n.count {
                    let nn = simd_normalize(normalMatrix * SIMD3<Float>(n[i][0], n[i][1], n[i][2]))
                    normals.append(SCNVector3(nn.x, nn.y, nn.z))
                } else {
                    normals.append(SCNVector3(0, 1, 0))
                }
                uvs.append(i < t.count ? CGPoint(x: CGFloat(t[i][0]), y: CGFloat(t[i][1])) : .zero)
            }
            for element in geometry.elements {
                all += indices(element).map { $0 + base }
            }
        }
        guard !positions.isEmpty, !all.isEmpty else { return nil }
        // UVs as 32-bit floats (the CGPoint initializer may keep doubles on 64-bit devices)
        var uvFloats: [Float] = []
        uvFloats.reserveCapacity(uvs.count * 2)
        for uv in uvs { uvFloats.append(Float(uv.x)); uvFloats.append(Float(uv.y)) }
        let uvData = uvFloats.withUnsafeBufferPointer { Data(buffer: $0) }
        let uvSource = SCNGeometrySource(data: uvData, semantic: .texcoord, vectorCount: uvs.count, usesFloatComponents: true,
                                         componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals), uvSource],
                                   elements: [SCNGeometryElement(indices: all, primitiveType: .triangles)])
        geometry.materials = [material]
        return geometry
    }
}

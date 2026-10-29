import SceneKit
import UIKit
import MetalKit

/// Photo-scanned ground, walls and skies (Poly Haven, CC0): asphalt, paving slabs, concrete and
/// grass PBR sets (colour, normal and roughness maps, 1K, tiled in metres) and two sky panoramas
/// (a partly cloudy day and an overcast one) used as background and as the light the scene
/// reflects.
enum Scenery {
    /// Triangles read from a model file: positions, normals, UVs, indices (in the model's space).
    struct MeshData {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
    }

    /// The meshes of a USDZ file in the bundle, by node name.
    static func meshes(_ file: String) -> [String: MeshData] {
        guard let url = Bundle.main.url(forResource: file, withExtension: "usdz"),
              let scene = try? SCNScene(url: url, options: nil) else { return [:] }
        var result: [String: MeshData] = [:]
        scene.rootNode.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry, let name = node.name,
                  let vertexSource = geometry.sources(for: .vertex).first else { return }
            let transform = node.simdConvertTransform(matrix_identity_float4x4, to: scene.rootNode)
            let normalMatrix = simd_float3x3(SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                                             SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                                             SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
            let p = MeshMerge.floats(vertexSource, components: 3)
            let n = geometry.sources(for: .normal).first.map { MeshMerge.floats($0, components: 3) } ?? []
            let t = geometry.sources(for: .texcoord).first.map { MeshMerge.floats($0, components: 2) } ?? []
            var mesh = result[name] ?? MeshData()
            let base = UInt32(mesh.positions.count)
            for i in 0..<p.count {
                let w = transform * SIMD4<Float>(p[i][0], p[i][1], p[i][2], 1)
                mesh.positions.append(SIMD3(w.x, w.y, w.z))
                mesh.normals.append(i < n.count ? simd_normalize(normalMatrix * SIMD3(n[i][0], n[i][1], n[i][2])) : SIMD3(0, 1, 0))
                mesh.uvs.append(i < t.count ? SIMD2(t[i][0], t[i][1]) : .zero)
            }
            for element in geometry.elements { mesh.indices += MeshMerge.indices(element).map { $0 + base } }
            result[name] = mesh
        }
        return result
    }

    /// GPU textures from the asset catalog's texture sets (tools/make_texture_sets.py): stored
    /// ASTC-compressed with their mipmaps, so a 2K map takes a quarter of the memory of a decoded
    /// JPEG and nothing is kept in CPU memory. Falls back to a bundle JPEG of the same name.
    private static let textureLock = NSLock()
    private static var textures: [String: Any] = [:]
    private static let textureLoader: MTKTextureLoader? = MTLCreateSystemDefaultDevice().map { MTKTextureLoader(device: $0) }
    /// One texture read at a time: the loader is shared by the launch preloads, the garage and
    /// the level build on different threads.
    private static let loaderLock = NSLock()

    static func texture(_ name: String) -> Any? {
        textureLock.lock()
        defer { textureLock.unlock() }
        if let cached = textures[name] { return cached }
        var result: Any?
        if let loader = textureLoader {
            let options: [MTKTextureLoader.Option: Any] = [
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
            ]
            do {
                loaderLock.lock()
                defer { loaderLock.unlock() }
                result = try loader.newTexture(name: name, scaleFactor: 1, bundle: .main, options: options)
            } catch {
                if PerfSettings.benchmark {
                    FileHandle.standardError.write("PPTEX \(name) failed: \(error)\n".data(using: .utf8)!)
                }
            }
        }
        if result == nil { result = UIImage(named: name + ".jpg") }
        textures[name] = result
        return result
    }

    /// A bundle image (JPEG or PNG) read straight into a GPU texture with its mipmaps, the same
    /// pixels as the image (not compressed): SceneKit given a UIImage keeps the decoded picture in
    /// memory as well as its GPU copy (a 4K car map is 64 MB of that), a texture loaded this way
    /// is only on the GPU. `srgb` for colour maps; normal, roughness, metal and mask maps are data.
    static func loadTexture(file: String, srgb: Bool) -> MTLTexture? {
        let ext = (file as NSString).pathExtension
        guard let loader = textureLoader,
              let url = Bundle.main.url(forResource: (file as NSString).deletingPathExtension, withExtension: ext.isEmpty ? nil : ext)
        else { return nil }
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: NSNumber(value: srgb),
            // Rows in the image's own order, as SceneKit lays out an image: no flip needed (unlike
            // the asset catalog's texture sets, stored bottom-up)
            .origin: MTKTextureLoader.Origin.topLeft,
            .generateMipmaps: NSNumber(value: true),
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
        ]
        do {
            loaderLock.lock()
            defer { loaderLock.unlock() }
            return try loader.newTexture(URL: url, options: options)
        } catch {
            if PerfSettings.benchmark {
                FileHandle.standardError.write("PPTEX \(file) failed: \(error)\n".data(using: .utf8)!)
            }
            return nil
        }
    }

    /// Texture-set textures are stored bottom-up, images top-down: flips v for a property showing
    /// one so the model's UVs land where they were painted. (Not for `loadTexture`'s.)
    static func orient(_ property: SCNMaterialProperty) {
        guard property.contents is MTLTexture else { return }
        property.wrapS = .repeat
        property.wrapT = .repeat
        property.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(1, -1, 1), SCNMatrix4MakeTranslation(0, 1, 0))
    }

    /// The material of a Meshy prop or person: its own colour, normal and roughness maps.
    static func modelMaterial(_ name: String) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = texture("\(name)_diff")
        material.normal.contents = texture("\(name)_nor")
        material.roughness.contents = texture("\(name)_rough")
        material.metalness.contents = NSNumber(value: 0)
        for property in [material.diffuse, material.normal, material.roughness] {
            property.mipFilter = .linear
            property.maxAnisotropy = 4
            orient(property)
        }
        return material
    }

    /// Draws nothing on screen but casts the shadow: a prop's light mesh stands in for its
    /// detailed one in the shadow map.
    static let shadowCaster: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.colorBufferWriteMask = []
        return material
    }()

    /// A street prop modelled with Meshy from the reference sheet (tools/convert_meshy_street.py):
    /// the close-up mesh "<name>", "<name>_lod" (a fifth of it) from `near` metres and
    /// "<name>_far" (about 2,500 triangles) from `far` metres. The shadow is cast by the far mesh
    /// alone, so the detail costs nothing in the shadow pass. Clones share all of it.
    static func prop(_ name: String, near: CGFloat, far: CGFloat, hidden: CGFloat = 150) -> SCNNode? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz"),
              let scene = try? SCNScene(url: url, options: nil) else { return nil }
        var meshes: [String: SCNNode] = [:]
        scene.rootNode.enumerateHierarchy { node, _ in
            if node.geometry != nil, let n = node.name { meshes[n] = node }
        }
        guard let mesh = meshes[name], let geometry = mesh.geometry else { return nil }
        let material = modelMaterial(name)
        geometry.materials = [material]
        var levels: [SCNLevelOfDetail] = []
        if let mid = meshes[name + "_lod"]?.geometry {
            mid.materials = [material]
            levels.append(SCNLevelOfDetail(geometry: mid, worldSpaceDistance: near))
        }
        let farGeometry = meshes[name + "_far"]?.geometry
        if let low = farGeometry {
            low.materials = [material]
            levels.append(SCNLevelOfDetail(geometry: low, worldSpaceDistance: far))
        }
        // Past `hidden` metres (deep in the fog, mostly behind buildings) the prop is not drawn
        levels.append(SCNLevelOfDetail(geometry: nil, worldSpaceDistance: hidden))
        geometry.levelsOfDetail = levels
        let transform = mesh.simdConvertTransform(matrix_identity_float4x4, to: scene.rootNode)
        let node = SCNNode(geometry: geometry)
        node.simdTransform = transform
        let holder = SCNNode()
        holder.addChildNode(node)
        node.categoryBitMask = World3D.propCategory
        if let low = farGeometry?.copy() as? SCNGeometry {
            low.materials = [shadowCaster]
            // The shadow only matters within the shadow distance
            low.levelsOfDetail = [SCNLevelOfDetail(geometry: nil, worldSpaceDistance: 70)]
            let shadow = SCNNode(geometry: low)
            shadow.simdTransform = transform
            shadow.castsShadow = true
            // Drawn after the scene's solids, so its depth never hides the visible mesh
            shadow.renderingOrder = 50
            shadow.categoryBitMask = World3D.propCategory
            node.castsShadow = false
            holder.addChildNode(shadow)
        } else {
            node.castsShadow = true
        }
        return holder
    }

    /// The four street trees in their kerbed planters: green, light green, yellow, blossom.
    static let trees: [SCNNode] = ["tree_green", "tree_light", "tree_yellow", "tree_pink"]
        .compactMap { prop($0, near: 16, far: 42) }

    private static var cache: [String: SCNMaterial] = [:]

    /// A PBR set from Hop/Textures/ph_<name>_{diff,nor,rough}.jpg, repeated every `tile` metres
    /// over a surface of `size` metres (each call its own material so its repeat fits its size).
    static func surface(_ name: String, tile: Float, size: CGSize, normal: CGFloat = 1) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = image("ph_\(name)_diff.jpg")
        material.normal.contents = image("ph_\(name)_nor.jpg")
        material.normal.intensity = normal
        material.roughness.contents = image("ph_\(name)_rough.jpg")
        material.metalness.contents = NSNumber(value: 0)
        let repeats = SCNMatrix4MakeScale(Float(size.width) / tile, Float(size.height) / tile, 1)
        for property in [material.diffuse, material.normal, material.roughness] {
            property.wrapS = .repeat
            property.wrapT = .repeat
            property.contentsTransform = repeats
            property.mipFilter = .linear
            property.maxAnisotropy = 8
        }
        return material
    }

    /// Shared material for many small surfaces with the same repeat (walls, pillars).
    static func shared(_ name: String, tile: Float, size: CGSize) -> SCNMaterial {
        let key = "\(name)-\(tile)-\(Int(size.width * 10))x\(Int(size.height * 10))"
        if let cached = cache[key] { return cached }
        let material = surface(name, tile: tile, size: size)
        cache[key] = material
        return material
    }

    private static var images: [String: UIImage] = [:]
    static func image(_ name: String) -> UIImage? {
        if let cached = images[name] { return cached }
        let loaded = UIImage(named: name)
        images[name] = loaded
        return loaded
    }

    /// Sky panoramas: a sunny day with clouds, and grey overcast (rain and snow).
    static var daySky: Any { image("sky_day.jpg") ?? CityArt.sky }
    static var overcastSky: Any { image("sky_overcast.jpg") ?? CityArt.rainSky }

    /// Fine asphalt grain for the street texture (multiplied over its markings, its own repeat).
    static func addAsphaltDetail(to material: SCNMaterial, size: CGSize) {
        material.multiply.contents = image("ph_asphalt_detail.jpg")
        material.multiply.wrapS = .repeat
        material.multiply.wrapT = .repeat
        material.multiply.mipFilter = .linear
        material.multiply.contentsTransform = SCNMatrix4MakeScale(Float(size.width) / 3.5, Float(size.height) / 3.5, 1)
        material.normal.contents = image("ph_asphalt_nor.jpg")
        material.normal.intensity = 0.9
        material.normal.contentsTransform = material.multiply.contentsTransform
        material.normal.wrapS = .repeat
        material.normal.wrapT = .repeat
        material.roughness.contents = image("ph_asphalt_rough.jpg")
        material.roughness.contentsTransform = material.multiply.contentsTransform
        material.roughness.wrapS = .repeat
        material.roughness.wrapT = .repeat
    }

    // MARK: Parking lot markings

    /// White lines painted on the lot for every row of parked cars (between neighbours and at the
    /// open ends), drawn once per level on a transparent 2048 x 1024 overlay of the 100 x 50 m lot.
    static func markings(for level: LevelDef) -> UIImage {
        let size = CGSize(width: 2048, height: 1024)
        let scale = size.width / level.world.width
        let cars = level.obstacles.filter { $0.kind == .car }
        return CarArt.image(size, scale: 1) { context, _ in
            context.setLineCap(.butt)
            func line(_ a: CGPoint, _ b: CGPoint, width: CGFloat, alpha: CGFloat) {
                context.setStrokeColor(UIColor(white: 0.96, alpha: alpha).cgColor)
                context.setLineWidth(width * scale)
                context.move(to: CGPoint(x: a.x * scale, y: size.height - a.y * scale))
                context.addLine(to: CGPoint(x: b.x * scale, y: size.height - b.y * scale))
                context.strokePath()
            }
            var drawn: [CGPoint] = []
            for car in cars {
                let along = CGVector(dx: cos(car.angle), dy: sin(car.angle))
                let across = CGVector(dx: -along.dy, dy: along.dx)
                // Neighbours parked the same way beside it
                var sides: [CGFloat] = []
                for other in cars where other.center != car.center {
                    guard abs(CGFloat.angleDelta(other.angle, car.angle).truncatingRemainder(dividingBy: .pi)) < 0.12 else { continue }
                    let dx = other.center.x - car.center.x, dy = other.center.y - car.center.y
                    let lateral = dx * across.dx + dy * across.dy
                    let longitudinal = dx * along.dx + dy * along.dy
                    if abs(longitudinal) < 9 && abs(lateral) > 22 && abs(lateral) < 60 { sides.append(lateral) }
                }
                guard !sides.isEmpty else { continue }
                // Lines halfway to the nearest neighbour, on both sides (shared lines drawn once)
                let half = sides.map { abs($0) }.min()! / 2
                let offsets = [1, -1]
                for side in offsets {
                    let offset = CGFloat(side) * half
                    let mid = CGPoint(x: car.center.x + across.dx * offset, y: car.center.y + across.dy * offset)
                    if drawn.contains(where: { hypot($0.x - mid.x, $0.y - mid.y) < 6 }) { continue }
                    drawn.append(mid)
                    let reach: CGFloat = 27
                    line(CGPoint(x: mid.x - along.dx * reach, y: mid.y - along.dy * reach),
                         CGPoint(x: mid.x + along.dx * reach, y: mid.y + along.dy * reach), width: 1.3, alpha: 0.82)
                }
            }
            // A painted border round the lot
            let inset: CGFloat = 12
            context.setStrokeColor(UIColor(red: 0.98, green: 0.82, blue: 0.2, alpha: 0.75).cgColor)
            context.setLineWidth(1.4 * scale)
            context.stroke(CGRect(x: inset * scale, y: inset * scale, width: size.width - 2 * inset * scale, height: size.height - 2 * inset * scale))
        }
    }

    /// The overlay plane for a level's lot markings.
    static func markingsNode(for level: LevelDef) -> SCNNode {
        let plane = SCNPlane(width: level.world.width / 10, height: level.world.height / 10)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = markings(for: level)
        material.diffuse.mipFilter = .linear
        material.roughness.contents = NSNumber(value: 0.6)
        material.metalness.contents = NSNumber(value: 0)
        material.transparencyMode = .aOne
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -Float.pi / 2
        node.position = World3D.vec(CGPoint(x: level.world.width / 2, y: level.world.height / 2), y: 0.012)
        node.castsShadow = false
        node.renderingOrder = 2
        return node
    }
}

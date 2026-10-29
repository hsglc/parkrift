import SceneKit
import UIKit

/// The player cars in the garage: Polyfork's free low poly cars converted by
/// tools/convert_polyfork_cars.py (see README credits); the numbers come from that script.
/// Garage cars (Meshy AI designs). Raw values are kept from earlier versions (saved choices and
/// owned cars); 1 and 2 were cars that left the garage.
enum CarModelID: Int, CaseIterable {
    case italia = 0
    case strada = 3
    case toro = 4
    case arrow = 5
    case bison = 6
    case classico = 7

    /// Position in the garage (0...).
    var order: Int { CarModelID.allCases.firstIndex(of: self) ?? 0 }
}

/// A car plus paint, as picked in the garage (and sent to the friend online).
struct CarChoice: Equatable {
    var model: CarModelID
    var paint: Int
    var rim: Int = 0

    var rimColor: UIColor { CarSpec.rims[max(0, min(CarSpec.rims.count - 1, rim))] }

    /// While `CarSpec.paintChoice` is off every car wears the first paint.
    var color: UIColor { CarSpec.paints[CarSpec.paintChoice ? max(0, min(CarSpec.paints.count - 1, paint)) : 0].color }
    var spec: CarSpec { CarSpec.of(model) }

    static let defaultChoice = CarChoice(model: .italia, paint: 0)
    /// What the friend drives until their choice arrives.
    static let friendDefault = CarChoice(model: .italia, paint: 1)

    var message: [String: Any] { ["t": "car", "m": model.rawValue, "p": paint, "r": rim] }

    init(model: CarModelID, paint: Int) {
        self.model = model
        self.paint = paint
    }

    init?(message: [String: Any]) {
        guard let raw = message["m"] as? Int, let model = CarModelID(rawValue: raw) else { return nil }
        self.model = model
        self.paint = max(0, min(CarSpec.paints.count - 1, message["p"] as? Int ?? 0))
        self.rim = max(0, min(CarSpec.rims.count - 1, message["r"] as? Int ?? 0))
    }

    /// Saved garage choice.
    static var saved: CarChoice {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: "pp.car") != nil else { return defaultChoice }
            var choice = CarChoice(model: CarModelID(rawValue: defaults.integer(forKey: "pp.car")) ?? .italia,
                                   paint: max(0, min(CarSpec.paints.count - 1, defaults.integer(forKey: "pp.paint"))))
            choice.rim = max(0, min(CarSpec.rims.count - 1, defaults.integer(forKey: "pp.rim")))
            return choice
        }
        set {
            UserDefaults.standard.set(newValue.model.rawValue, forKey: "pp.car")
            UserDefaults.standard.set(newValue.paint, forKey: "pp.paint")
            UserDefaults.standard.set(newValue.rim, forKey: "pp.rim")
        }
    }
}

/// What a car really does on the road, from its ratings and its upgrades. The garage bars and
/// the driving model both come from here, so a higher bar always means a faster, quicker or
/// grippier car, and every upgrade level is felt.
struct CarPerformance {
    /// Top speed in km/h on race and city rounds (parking levels run calmer, see the scene).
    let topKmh: CGFloat
    /// Engine pull relative to the top speed (how fast it gets there).
    let acceleration: CGFloat
    /// Steering and tyre grip multiplier.
    let handling: CGFloat
    /// Nitro push multiplier and refill time multiplier (lower refills faster).
    let nitroPower: CGFloat
    let nitroFill: CGFloat

    private static func span(_ value: Double, _ low: Double, _ high: Double) -> CGFloat {
        CGFloat(max(0, min(1, (value - low) / (high - low))))
    }

    static func of(_ spec: CarSpec, upgrades: Progression.Upgrades) -> CarPerformance {
        let stats = spec.stats
        let engine = CGFloat(upgrades.engine), grip = CGFloat(upgrades.grip), boost = CGFloat(upgrades.nitro)
        return CarPerformance(
            topKmh: 66 + 26 * span(stats.speed, 0.80, 0.96) + 5 * engine,
            acceleration: 0.85 + 0.40 * span(stats.acceleration, 0.80, 0.90) + 0.08 * engine,
            handling: 0.85 + 0.32 * span(stats.handling, 0.70, 0.90) + 0.06 * grip,
            nitroPower: 0.85 + 0.45 * span(stats.nitro, 0.72, 0.92) + 0.10 * boost,
            nitroFill: 1.15 - 0.35 * span(stats.nitro, 0.72, 0.92) - 0.08 * boost)
    }

    /// Garage bars (0...1) including the upgrades bought for this car.
    static func ratings(_ spec: CarSpec, upgrades: Progression.Upgrades) -> CarStats {
        let s = spec.stats
        return CarStats(speed: min(1, s.speed + 0.03 * Double(upgrades.engine)),
                        acceleration: min(1, s.acceleration + 0.03 * Double(upgrades.engine)),
                        handling: min(1, s.handling + 0.03 * Double(upgrades.grip)),
                        nitro: min(1, s.nitro + 0.025 * Double(upgrades.nitro)))
    }
}

struct CarStats {
    /// 0...1 bars shown in the garage.
    let speed: Double
    let acceleration: Double
    let handling: Double
    let nitro: Double
}

struct CarSpec {
    let id: CarModelID
    let file: String
    let name: String
    let maker: String
    let className: String
    let stats: CarStats
    /// Wheel centers (x forward, y up, z right; meters) and whether the wheel steers.
    let wheelSpots: [(Float, Float, Float, Bool)]
    let wheelRadius: Float
    /// Side (z sign) the exported wheel model sits on; the other side is turned around.
    let wheelModelSide: Float
    let exhausts: [SCNVector3]
    /// Driving model multipliers (kept close to 1 so online races stay fair).
    let topSpeed: CGFloat
    let acceleration: CGFloat
    let steering: CGFloat
    let nitroPower: CGFloat
    let nitroFill: CGFloat
    /// Painted through a tinted texture instead of a paint material.
    let textured: Bool
    /// Texture painted by tinting: grey base with the paint areas and their mask.
    var textureBase: String? = nil
    var textureMask: String? = nil
    /// Fine surface detail (panel lines, grilles, tyre treads) and gloss per texel, from the
    /// 4K Meshy retexture.
    var textureNormal: String? = nil
    var textureRough: String? = nil
    var textureMetal: String? = nil
    /// Keeps its own colors (police, taxi): no paint choice.
    var fixedLivery = false
    /// Body height, for the garage camera and lights.
    var height: Float = 1.2

    struct Paint {
        let name: String
        let color: UIColor
    }

    static let paints: [Paint] = [
        Paint(name: Strings.paintRed, color: UIColor(red: 0.82, green: 0.04, blue: 0.06, alpha: 1)),
        Paint(name: Strings.paintBlue, color: UIColor(red: 0.07, green: 0.26, blue: 0.78, alpha: 1)),
        Paint(name: Strings.paintLime, color: UIColor(red: 0.50, green: 0.86, blue: 0.06, alpha: 1)),
        Paint(name: Strings.paintYellow, color: UIColor(red: 1.00, green: 0.74, blue: 0.02, alpha: 1)),
        Paint(name: Strings.paintOrange, color: UIColor(red: 1.00, green: 0.38, blue: 0.04, alpha: 1)),
        Paint(name: Strings.paintPurple, color: UIColor(red: 0.42, green: 0.12, blue: 0.78, alpha: 1)),
        Paint(name: Strings.paintWhite, color: UIColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1)),
        Paint(name: Strings.paintBlack, color: UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1))
    ]

    /// Rim colours: silver, black, gold, bronze, white, red, blue.
    /// Paint choice in the garage; off for now: every car is the same racing red.
    static let paintChoice = false

    static let rims: [UIColor] = [
        UIColor(white: 0.72, alpha: 1), UIColor(white: 0.08, alpha: 1),
        UIColor(red: 0.85, green: 0.66, blue: 0.22, alpha: 1), UIColor(red: 0.55, green: 0.36, blue: 0.2, alpha: 1),
        UIColor(white: 0.95, alpha: 1), UIColor(red: 0.8, green: 0.08, blue: 0.08, alpha: 1),
        UIColor(red: 0.12, green: 0.35, blue: 0.85, alpha: 1)
    ]

    static let all: [CarSpec] = [
        meshy(.italia, name: "Rosso GT", maker: "CORSA", className: "S",
              stats: CarStats(speed: 0.88, acceleration: 0.85, handling: 0.88, nitro: 0.74),
              tuning: (1.02, 1.0, 1.02, 1.0, 1.0),
              wheels: [(1.180, 0.330, -0.818, true), (1.181, 0.330, 0.824, true), (-1.400, 0.334, -0.814, false), (-1.398, 0.332, 0.814, false)],
              radius: 0.332, rear: -2.250, height: 1.136),
        meshy(.strada, name: "Strada S", maker: "NORDWERK", className: "A",
              stats: CarStats(speed: 0.81, acceleration: 0.90, handling: 0.90, nitro: 0.78),
              tuning: (1.0, 1.04, 1.04, 1.0, 1.0),
              wheels: [(1.077, 0.410, -0.929, true), (1.084, 0.410, 0.930, true), (-1.272, 0.415, -0.929, false), (-1.270, 0.415, 0.930, false)],
              radius: 0.413, rear: -2.050, height: 1.753),
        meshy(.toro, name: "Volta R", maker: "VOLTA", className: "S+",
              stats: CarStats(speed: 0.96, acceleration: 0.89, handling: 0.78, nitro: 0.82),
              tuning: (1.06, 1.04, 0.98, 1.02, 1.0),
              wheels: [(1.086, 0.297, -0.822, true), (1.086, 0.297, 0.825, true), (-1.449, 0.309, -0.819, false), (-1.447, 0.309, 0.823, false)],
              radius: 0.303, rear: -2.375, height: 0.860),
        meshy(.arrow, name: "Arrow GT", maker: "ARROWWORKS", className: "S",
              stats: CarStats(speed: 0.92, acceleration: 0.86, handling: 0.84, nitro: 0.76),
              tuning: (1.04, 1.02, 1.04, 1.0, 1.0),
              wheels: [(1.401, 0.335, -0.798, true), (1.401, 0.333, 0.791, true), (-1.295, 0.335, -0.797, false), (-1.301, 0.333, 0.789, false)],
              radius: 0.334, rear: -2.350, height: 1.215),
        meshy(.bison, name: "Bison", maker: "ATLAS", className: "A",
              stats: CarStats(speed: 0.80, acceleration: 0.82, handling: 0.72, nitro: 0.92),
              tuning: (0.98, 1.0, 0.94, 1.1, 0.88),
              wheels: [(1.350, 0.382, -0.855, true), (1.353, 0.381, 0.855, true), (-1.313, 0.380, -0.865, false), (-1.313, 0.380, 0.865, false)],
              radius: 0.381, rear: -2.250, height: 2.088),
        meshy(.classico, name: "Classico 87", maker: "VINTAGE", className: "S",
              stats: CarStats(speed: 0.90, acceleration: 0.80, handling: 0.76, nitro: 0.88),
              tuning: (1.05, 0.97, 0.96, 1.08, 0.92),
              wheels: [(1.306, 0.318, -0.731, true), (1.306, 0.318, 0.743, true), (-1.092, 0.316, -0.740, false), (-1.092, 0.317, 0.744, false)],
              radius: 0.317, rear: -2.200, height: 1.253)
    ].sorted { $0.id.rawValue < $1.id.rawValue }

    /// An original car generated with Meshy AI and refined and converted with
    /// tools/convert_meshy_cars.py: a textured body painted through its mask, glass and lamp
    /// meshes the game lights, and a separate wheel.
    private static func meshy(_ id: CarModelID, name: String, maker: String, className: String, stats: CarStats,
                              tuning: (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat),
                              wheels: [(Float, Float, Float, Bool)], radius: Float, rear: Float, height: Float) -> CarSpec {
        let file = "\(id)"
        return CarSpec(id: id, file: file, name: name, maker: maker, className: className, stats: stats,
                       wheelSpots: wheels, wheelRadius: radius, wheelModelSide: -1,
                       exhausts: [SCNVector3(rear - 0.02, 0.32, 0.34), SCNVector3(rear - 0.02, 0.32, -0.34)],
                       topSpeed: tuning.0, acceleration: tuning.1, steering: tuning.2, nitroPower: tuning.3, nitroFill: tuning.4,
                       textured: true, textureBase: file + "_basecolor.jpg", textureMask: file + "_mask.png",
                       textureNormal: file + "_normal.jpg", textureRough: file + "_rough.jpg",
                       textureMetal: file + "_metal.jpg", height: height)
    }

    /// A free low poly car from Polyfork, converted with tools/convert_polyfork_cars.py: one body
    /// mesh coloured through a small palette texture (painted where its mask is white), lamp
    /// meshes the game lights, and a separate wheel.
    private static func polyfork(_ id: CarModelID, name: String, maker: String, className: String, stats: CarStats,
                                 tuning: (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat),
                                 wheels: [(Float, Float, Float, Bool)], radius: Float, rear: Float, height: Float) -> CarSpec {
        let file = "\(id)"
        return CarSpec(id: id, file: file, name: name, maker: maker, className: className, stats: stats,
                       wheelSpots: wheels, wheelRadius: radius, wheelModelSide: -1,
                       exhausts: [SCNVector3(rear - 0.02, 0.32, 0.34), SCNVector3(rear - 0.02, 0.32, -0.34)],
                       topSpeed: tuning.0, acceleration: tuning.1, steering: tuning.2, nitroPower: tuning.3, nitroFill: tuning.4,
                       textured: true, textureBase: file + "_palette.png", textureMask: file + "_mask.png", height: height)
    }

    static func of(_ id: CarModelID) -> CarSpec { all.first { $0.id == id } ?? all[0] }
}

/// Loads the USDZ car models once and gives them the game's materials.
enum CarModels {
    private static var bodies: [CarModelID: SCNNode] = [:]
    private static var wheels: [CarModelID: SCNNode] = [:]
    private static var textures: [String: UIImage] = [:]
    private static let loadLock = NSRecursiveLock()

    static func body(_ id: CarModelID) -> SCNNode? {
        loadLock.lock()
        defer { loadLock.unlock() }
        if let cached = bodies[id] { return cached }
        let node = load(CarSpec.of(id).file + "_body")
        bodies[id] = node
        return node
    }

    static func wheel(_ id: CarModelID) -> SCNNode? {
        loadLock.lock()
        defer { loadLock.unlock() }
        if let cached = wheels[id] { return cached }
        let node = load(CarSpec.of(id).file + "_wheel")
        wheels[id] = node
        return node
    }

    /// Reads all car models on a background thread (parsing the USDZ files blocked the menu for
    /// a second or two); `completion` runs on the main thread when they are ready.
    static func preload(completion: @escaping () -> Void) {
        // Shared materials are created here on the main thread first
        _ = [CarShapes.canopy, CarShapes.led, CarShapes.chrome, CarShapes.carbon, CarShapes.trim, CarShapes.graphite,
             tire, rim, caliper, interior, accent, retroWheel, kenney]
        DispatchQueue.global(qos: .userInitiated).async {
            for id in CarModelID.allCases {
                _ = body(id)
                _ = wheel(id)
            }
            TrafficVehicles.preload()
            _ = World3D.signalTemplates
            _ = Scenery.trees
            // People and street props too: built on first use they held up the city's loading
            _ = PedestrianModels.all
            _ = StreetProps.allGeometries
            DispatchQueue.main.async { completion() }
        }
    }

    /// Geometry of every loaded model, for uploading to the GPU ahead of time.
    static var allGeometries: [SCNGeometry] {
        var result: [SCNGeometry] = []
        for node in Array(bodies.values.compactMap { $0 }) + Array(wheels.values.compactMap { $0 }) {
            node.enumerateHierarchy { child, _ in
                if let geometry = child.geometry { result.append(geometry) }
            }
        }
        return result
    }

    /// Both sides drawn: the generated wheels have open tyre walls and rim barrels that showed
    /// holes from some angles with back faces culled.
    static let tire: SCNMaterial = {
        let material = Mat.pbr(UIColor(white: 0.07, alpha: 1), metal: 0, rough: 0.85)
        material.isDoubleSided = true
        return material
    }()
    static let rim: SCNMaterial = {
        let material = Mat.pbr(UIColor(white: 0.72, alpha: 1), metal: 0.95, rough: 0.25)
        material.isDoubleSided = true
        return material
    }()
    /// Simplified cabin seen through the windows.
    static let interior = Mat.pbr(UIColor(white: 0.07, alpha: 1), metal: 0, rough: 0.8)
    /// Brake discs and calipers: dark metal (bright yellow covered the whole wheel face).
    static let caliper = Mat.pbr(UIColor(white: 0.28, alpha: 1), metal: 0.8, rough: 0.35)
    /// Glossy black for the concept car's second paint tone.
    static let accent: SCNMaterial = {
        let material = Mat.pbr(UIColor(white: 0.04, alpha: 1), metal: 0.5, rough: 0.2)
        material.clearCoat.contents = NSNumber(value: 1.0)
        material.clearCoatRoughness.contents = NSNumber(value: 0.05)
        return material
    }()
    /// The retro car's texture as it comes (wheels keep their colors whatever the paint).
    static let retroWheel: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(white: 0.6, alpha: 1)
        material.metalness.contents = NSNumber(value: 0.2)
        material.roughness.contents = NSNumber(value: 0.45)
        return material
    }()

    /// Kenney's palette texture, shared by every Kenney vehicle.
    static let kenney: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIImage(named: "kenney_colormap.png")
        material.diffuse.magnificationFilter = .nearest
        material.metalness.contents = NSNumber(value: 0.15)
        material.roughness.contents = NSNumber(value: 0.42)
        return material
    }()

    static func load(_ name: String) -> SCNNode? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz"),
              let scene = try? SCNScene(url: url, options: nil) else { return nil }
        let holder = SCNNode()
        for child in scene.rootNode.childNodes { holder.addChildNode(child) }
        let materials: [String: SCNMaterial] = [
            "glass": CarShapes.canopy, "headlight": CarShapes.led, "chrome": CarShapes.chrome,
            "carbon": CarShapes.carbon, "darkplastic": CarShapes.trim, "metal": CarShapes.graphite,
            "tire": tire, "rim": rim, "caliper": caliper, "hub": CarShapes.chrome,
            "paint": Mat.pbr(.gray), "paint2": accent, "textured": retroWheel, "interior": interior, "kenney": kenney,
            "taillight": Mat.glow(UIColor(red: 0.55, green: 0.04, blue: 0.05, alpha: 1))
        ]
        holder.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry, let name = node.name, let material = materials[name] else { return }
            if name == "glass" {
                // Thin shells: draw both sides so decimation gaps do not show the inside
                let glass = material.copy() as! SCNMaterial
                glass.isDoubleSided = true
                geometry.materials = [glass]
            } else {
                geometry.materials = [material]
            }
            if ["tire", "rim", "hub", "caliper"].contains(name) { node.castsShadow = false }
        }
        return holder
    }

    /// Paint for the textured cars is applied on the GPU: the base texture is multiplied by the
    /// paint color where the mask is white. Changing the paint only changes a shader value, so no
    /// image is drawn and nothing new is uploaded (each first paint or car used to draw a
    /// 1024 px image on the main thread and upload it, which made the garage stutter).
    private static let paintShader = """
    #pragma arguments
    texture2d<float> paintMask;
    float3 paintColor;
    #pragma body
    constexpr sampler maskSampler(filter::linear, mip_filter::none, address::repeat);
    float paintAmount = paintMask.sample(maskSampler, _surface.diffuseTexcoord).r;
    _surface.diffuse.rgb = mix(_surface.diffuse.rgb, _surface.diffuse.rgb * paintColor, paintAmount);
    """

    private static let textureLock = NSLock()
    private static var images: [String: UIImage] = [:]

    /// A car texture. Only the small ones are decoded up front and kept: the 4K base texture
    /// alone is 64 MB decoded, so big images stay in UIKit's purgeable cache and SceneKit holds
    /// its own copy only while a material that uses it is alive (garage cars that are not shown
    /// let theirs go).
    private static func image(_ name: String, keep: Bool = true) -> UIImage? {
        textureLock.lock()
        defer { textureLock.unlock() }
        if let cached = images[name] { return cached }
        if let ready = decoded[name] { return ready }
        guard let loaded = UIImage(named: name) else { return nil }
        let small = loaded.size.width * loaded.scale <= 1024
        guard keep, small else { return loaded }
        let decoded = loaded.preparingForDisplay() ?? loaded
        images[name] = decoded
        return decoded
    }

    /// Big images decoded ahead on a background thread, handed to the next material that asks.
    private static var decoded: [String: UIImage] = [:]
    private static let decodeQueue = DispatchQueue(label: "car-textures", qos: .userInitiated)

    /// Decodes a car's 4K maps off the main thread, then runs `then` on the main thread. Applying
    /// the textures right after costs no decoding there (a 4K JPEG decoded on the main thread froze
    /// the garage for a moment on every entry and every car change).
    static func whenDecoded(_ spec: CarSpec, then: @escaping () -> Void) {
        let names = [spec.textureBase, spec.textureMask, spec.textureNormal, spec.textureRough, spec.textureMetal].compactMap { $0 }
        decodeQueue.async {
            var ready: [String: UIImage] = [:]
            for name in names {
                textureLock.lock()
                let known = images[name] ?? decoded[name]
                textureLock.unlock()
                if known != nil { continue }
                if let loaded = UIImage(named: name) { ready[name] = loaded.preparingForDisplay() ?? loaded }
            }
            textureLock.lock()
            decoded.merge(ready) { a, _ in a }
            textureLock.unlock()
            DispatchQueue.main.async {
                then()
                // The materials hold what they took; the cache lets go so nothing extra stays
                textureLock.lock()
                for name in names { decoded[name] = nil }
                textureLock.unlock()
            }
        }
    }

    /// Decodes the player's car images on a background thread at launch (the others load when
    /// they are first shown).
    static func prewarmRetroTextures(_ id: CarModelID? = nil) {
        let specs = CarSpec.all.filter { $0.textureBase != nil && $0.id == (id ?? CarChoice.saved.model) }
        DispatchQueue.global(qos: .utility).async {
            for spec in specs {
                if let base = spec.textureBase { _ = image(base) }
                if let mask = spec.textureMask { _ = image(mask) }
                if let normal = spec.textureNormal { _ = image(normal) }
                if let rough = spec.textureRough { _ = image(rough) }
                if let metal = spec.textureMetal { _ = image(metal) }
            }
        }
    }

    /// The retro car in a paint (kept for callers that only know the color).

    /// Normal, gloss and metal maps of a Meshy car, used texel for texel.
    private static func applyMeshyMaps(_ spec: CarSpec, to material: SCNMaterial) {
        if let name = spec.textureNormal, let normal = image(name) {
            material.normal.contents = normal
            material.normal.mipFilter = .linear
        }
        if let name = spec.textureRough, let rough = image(name) {
            material.roughness.contents = rough
            material.roughness.mipFilter = .linear
        }
        if let name = spec.textureMetal, let metal = image(name) {
            material.metalness.contents = metal
            material.metalness.mipFilter = .linear
        }
    }

    /// Tyre or rim material with the car's own texture and maps (`loaded`), or plain rubber /
    /// metal in `solid` with no textures at all.
    static func setWheelMaps(_ spec: CarSpec, on material: SCNMaterial, loaded: Bool, solid: UIColor) {
        if loaded, let base = spec.textureBase {
            material.diffuse.contents = image(base)
            material.diffuse.mipFilter = .linear
            applyMeshyMaps(spec, to: material)
        } else {
            material.diffuse.contents = solid
            material.normal.contents = nil
            material.roughness.contents = NSNumber(value: solid == UIColor(white: 0.07, alpha: 1) ? 0.85 : 0.25)
            material.metalness.contents = NSNumber(value: solid == UIColor(white: 0.07, alpha: 1) ? 0 : 0.95)
        }
    }

    /// Stand-in for a hidden garage car's body (no textures held).
    static let placeholder = Mat.pbr(UIColor(white: 0.5, alpha: 1), metal: 0, rough: 0.6)

    /// An unpainted Meshy material (tyres and rims): the car's own texture and maps.
    static func meshyMaterial(_ spec: CarSpec) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        if let base = spec.textureBase {
            material.diffuse.contents = image(base)
            material.diffuse.mipFilter = .linear
        }
        applyMeshyMaps(spec, to: material)
        return material
    }

    /// Material for a textured car (its own copy, so each car keeps its own paint), or the plain
    /// Kenney palette for cars with a fixed livery.
    static func texturePaint(_ spec: CarSpec, _ color: UIColor) -> SCNMaterial {
        guard let base = spec.textureBase, let maskName = spec.textureMask else { return kenney }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = image(base)
        // Palette cells: no mipmaps, so far-away faces do not blend with the next colour; painted
        // textures (Meshy cars) are mipmapped so they stay smooth far away
        material.diffuse.mipFilter = base.hasSuffix("_palette.png") ? .none : .linear
        // Glossy car paint with a clear coat (glass, chrome and trim are their own meshes now)
        material.metalness.contents = NSNumber(value: 0.2)
        material.roughness.contents = NSNumber(value: 0.3)
        material.clearCoat.contents = NSNumber(value: 1.0)
        material.clearCoatRoughness.contents = NSNumber(value: 0.05)
        if spec.textureNormal != nil {
            // Meshy's own maps as they are; the clear coat only where the paint is
            applyMeshyMaps(spec, to: material)
            if let mask = image(maskName) {
                material.clearCoat.contents = mask
                material.clearCoat.intensity = 0.9
            }
        }
        material.shaderModifiers = [.surface: paintShader]
        // Generated bodies have a few open shells (mirrors, spoilers): draw both sides
        material.isDoubleSided = true
        if let mask = image(maskName) {
            material.setValue(SCNMaterialProperty(contents: mask), forKey: "paintMask")
        }
        setPaint(material, color)
        return material
    }

    /// Paints a textured material through its mask on the GPU (traffic cars).
    static func applyPaintShader(_ material: SCNMaterial, mask: UIImage, color: UIColor) {
        material.shaderModifiers = [.surface: paintShader]
        material.setValue(SCNMaterialProperty(contents: mask), forKey: "paintMask")
        setPaint(material, color)
    }

    /// Changes a textured car material's paint (a shader value only).
    static func setPaint(_ material: SCNMaterial, _ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        // The texture is sampled in linear color: multiply by the linear paint color
        func linear(_ c: CGFloat) -> Float { Float(pow(max(0, min(1, c)), 2.2)) }
        material.setValue(NSValue(scnVector3: SCNVector3(linear(r), linear(g), linear(b))), forKey: "paintColor")
    }
}

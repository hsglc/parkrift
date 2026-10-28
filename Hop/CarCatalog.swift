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

    var color: UIColor { CarSpec.paints[max(0, min(CarSpec.paints.count - 1, paint))].color }
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
    static let rims: [UIColor] = [
        UIColor(white: 0.72, alpha: 1), UIColor(white: 0.08, alpha: 1),
        UIColor(red: 0.85, green: 0.66, blue: 0.22, alpha: 1), UIColor(red: 0.55, green: 0.36, blue: 0.2, alpha: 1),
        UIColor(white: 0.95, alpha: 1), UIColor(red: 0.8, green: 0.08, blue: 0.08, alpha: 1),
        UIColor(red: 0.12, green: 0.35, blue: 0.85, alpha: 1)
    ]

    static let all: [CarSpec] = [
        meshy(.italia, name: "Rosso GT", maker: "CORSA", className: "S",
              stats: CarStats(speed: 0.88, acceleration: 0.84, handling: 0.86, nitro: 0.72),
              tuning: (1.02, 1.0, 1.02, 1.0, 1.0),
              wheels: [(1.180, 0.330, -0.818, true), (1.181, 0.330, 0.824, true), (-1.400, 0.334, -0.814, false), (-1.398, 0.332, 0.814, false)],
              radius: 0.332, rear: -2.250, height: 1.136),
        meshy(.strada, name: "Strada S", maker: "NORDWERK", className: "A",
              stats: CarStats(speed: 0.82, acceleration: 0.90, handling: 0.90, nitro: 0.74),
              tuning: (1.0, 1.04, 1.04, 1.0, 1.0),
              wheels: [(1.077, 0.410, -0.929, true), (1.084, 0.410, 0.930, true), (-1.272, 0.415, -0.929, false), (-1.270, 0.415, 0.930, false)],
              radius: 0.413, rear: -2.050, height: 1.753),
        meshy(.toro, name: "Volta R", maker: "VOLTA", className: "S+",
              stats: CarStats(speed: 0.96, acceleration: 0.90, handling: 0.82, nitro: 0.78),
              tuning: (1.06, 1.04, 0.98, 1.02, 1.0),
              wheels: [(1.086, 0.297, -0.822, true), (1.086, 0.297, 0.825, true), (-1.449, 0.309, -0.819, false), (-1.447, 0.309, 0.823, false)],
              radius: 0.303, rear: -2.375, height: 0.860),
        meshy(.arrow, name: "Arrow GT", maker: "ARROWWORKS", className: "S",
              stats: CarStats(speed: 0.92, acceleration: 0.86, handling: 0.88, nitro: 0.76),
              tuning: (1.04, 1.02, 1.04, 1.0, 1.0),
              wheels: [(1.401, 0.335, -0.798, true), (1.401, 0.333, 0.791, true), (-1.295, 0.335, -0.797, false), (-1.301, 0.333, 0.789, false)],
              radius: 0.334, rear: -2.350, height: 1.215),
        meshy(.bison, name: "Bison", maker: "ATLAS", className: "A",
              stats: CarStats(speed: 0.80, acceleration: 0.84, handling: 0.70, nitro: 0.92),
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
                       textured: true, textureBase: file + "_basecolor.jpg", textureMask: file + "_mask.png", height: height)
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
            _ = World3D.signalTemplate
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

    private static let textureLock = NSLock()
    private static var images: [String: UIImage] = [:]

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

    /// The base and mask images of every textured car, decoded once (thread-safe).
    private static func image(_ name: String) -> UIImage? {
        textureLock.lock()
        defer { textureLock.unlock() }
        if let cached = images[name] { return cached }
        guard let loaded = UIImage(named: name) else { return nil }
        // Decode now (UIImage decodes lazily, on first draw)
        let decoded = loaded.preparingForDisplay() ?? loaded
        images[name] = decoded
        return decoded
    }

    /// Decodes the textured cars' images on a background thread at launch.
    static func prewarmRetroTextures() {
        let specs = CarSpec.all.filter { $0.textureBase != nil }
        DispatchQueue.global(qos: .utility).async {
            for spec in specs {
                if let base = spec.textureBase { _ = image(base) }
                if let mask = spec.textureMask { _ = image(mask) }
            }
        }
    }

    /// The retro car in a paint (kept for callers that only know the color).

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
        material.shaderModifiers = [.surface: paintShader]
        // Generated bodies have a few open shells (mirrors, spoilers): draw both sides
        material.isDoubleSided = true
        if let mask = image(maskName) {
            material.setValue(SCNMaterialProperty(contents: mask), forKey: "paintMask")
        }
        setPaint(material, color)
        return material
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

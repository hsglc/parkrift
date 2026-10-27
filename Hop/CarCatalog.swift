import SceneKit
import UIKit

/// The player cars in the garage. Models are converted from free assets by tools/convert_cars.py
/// and tools/convert_kenney.py (see README credits); the numbers come from those scripts.
enum CarModelID: Int, CaseIterable {
    case italia
    case concept
    case retro
    case strada
    case toro
    case arrow
    case bison
    case classico
}

/// A car plus paint, as picked in the garage (and sent to the friend online).
struct CarChoice: Equatable {
    var model: CarModelID
    var paint: Int

    var color: UIColor { CarSpec.paints[max(0, min(CarSpec.paints.count - 1, paint))].color }
    var spec: CarSpec { CarSpec.of(model) }

    static let defaultChoice = CarChoice(model: .italia, paint: 0)
    /// What the friend drives until their choice arrives.
    static let friendDefault = CarChoice(model: .italia, paint: 1)

    var message: [String: Any] { ["t": "car", "m": model.rawValue, "p": paint] }

    init(model: CarModelID, paint: Int) {
        self.model = model
        self.paint = paint
    }

    init?(message: [String: Any]) {
        guard let raw = message["m"] as? Int, let model = CarModelID(rawValue: raw) else { return nil }
        self.model = model
        self.paint = max(0, min(CarSpec.paints.count - 1, message["p"] as? Int ?? 0))
    }

    /// Saved garage choice.
    static var saved: CarChoice {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: "pp.car") != nil else { return defaultChoice }
            return CarChoice(model: CarModelID(rawValue: defaults.integer(forKey: "pp.car")) ?? .italia,
                             paint: max(0, min(CarSpec.paints.count - 1, defaults.integer(forKey: "pp.paint"))))
        }
        set {
            UserDefaults.standard.set(newValue.model.rawValue, forKey: "pp.car")
            UserDefaults.standard.set(newValue.paint, forKey: "pp.paint")
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

    static let all: [CarSpec] = [
        CarSpec(id: .italia, file: "italia", name: "Rosso GT", maker: "CORSA", className: "S",
                stats: CarStats(speed: 0.86, acceleration: 0.82, handling: 0.80, nitro: 0.70),
                wheelSpots: [(1.121, 0.347, -0.818, true), (1.121, 0.347, 0.811, true),
                             (-1.451, 0.347, -0.799, false), (-1.451, 0.347, 0.799, false)],
                wheelRadius: 0.347, wheelModelSide: -1,
                exhausts: [SCNVector3(-2.24, 0.42, 0.13), SCNVector3(-2.24, 0.42, -0.13)],
                topSpeed: 1.0, acceleration: 1.0, steering: 1.0, nitroPower: 1.0, nitroFill: 1.0, textured: false),
        CarSpec(id: .concept, file: "concept", name: "Vector X", maker: "AERO", className: "S+",
                stats: CarStats(speed: 0.96, acceleration: 0.72, handling: 0.70, nitro: 0.80),
                wheelSpots: [(1.259, 0.388, -0.985, true), (1.259, 0.388, 0.985, true),
                             (-1.568, 0.388, -0.994, false), (-1.568, 0.388, 0.994, false)],
                wheelRadius: 0.386, wheelModelSide: -1,
                exhausts: [SCNVector3(-2.22, 0.38, 0.32), SCNVector3(-2.22, 0.38, -0.32)],
                topSpeed: 1.06, acceleration: 0.94, steering: 0.95, nitroPower: 1.05, nitroFill: 1.0, textured: false),
        CarSpec(id: .retro, file: "retro", name: "Hot Rod 55", maker: "CLASSIC", className: "A",
                stats: CarStats(speed: 0.72, acceleration: 0.92, handling: 0.94, nitro: 0.96),
                wheelSpots: [(1.562, 0.301, -0.862, true), (1.562, 0.301, 0.862, true),
                             (-1.198, 0.301, -0.858, false), (-1.198, 0.301, 0.858, false)],
                wheelRadius: 0.301, wheelModelSide: -1,
                exhausts: [SCNVector3(-2.22, 0.3, 0.45)],
                topSpeed: 0.94, acceleration: 1.07, steering: 1.08, nitroPower: 1.1, nitroFill: 0.85, textured: true,
                textureBase: "retro_basecolor.jpg", textureMask: "retro_mask.png", height: 1.33),
        detailed(.strada, name: "Strada S", maker: "NORDWERK", className: "A",
                 stats: CarStats(speed: 0.84, acceleration: 0.88, handling: 0.86, nitro: 0.74),
                 tuning: (1.0, 1.04, 1.03, 1.0, 1.0),
                 wheels: [(1.490, 0.344, -0.766, true), (1.490, 0.344, 0.766, true), (-1.282, 0.347, -0.756, false), (-1.282, 0.347, 0.756, false)],
                 radius: 0.344, rear: -2.326, height: 1.386),
        detailed(.toro, name: "Tempesta", maker: "VOLTA", className: "S+",
                 stats: CarStats(speed: 0.95, acceleration: 0.90, handling: 0.82, nitro: 0.78),
                 tuning: (1.06, 1.04, 0.98, 1.02, 1.0),
                 wheels: [(1.187, 0.342, -0.827, true), (1.187, 0.342, 0.820, true), (-1.463, 0.359, -0.829, false), (-1.463, 0.359, 0.828, false)],
                 radius: 0.342, rear: -2.275, height: 1.146),
        detailed(.arrow, name: "Arrow GT", maker: "ARROWWORKS", className: "S",
                 stats: CarStats(speed: 0.92, acceleration: 0.86, handling: 0.88, nitro: 0.76),
                 tuning: (1.04, 1.02, 1.04, 1.0, 1.0),
                 wheels: [(1.201, 0.323, -0.835, true), (1.201, 0.323, 0.835, true), (-1.489, 0.357, -0.810, false), (-1.489, 0.357, 0.810, false)],
                 radius: 0.323, rear: -2.275, height: 1.196),
        detailed(.bison, name: "Bison", maker: "ATLAS", className: "A",
                 stats: CarStats(speed: 0.80, acceleration: 0.84, handling: 0.70, nitro: 0.92),
                 tuning: (0.98, 1.0, 0.94, 1.1, 0.88),
                 wheels: [(1.469, 0.383, -0.810, true), (1.469, 0.383, 0.811, true), (-1.444, 0.382, -0.812, false), (-1.444, 0.382, 0.812, false)],
                 radius: 0.383, rear: -2.475, height: 1.618),
        detailed(.classico, name: "Classico 87", maker: "VINTAGE", className: "S",
                 stats: CarStats(speed: 0.90, acceleration: 0.80, handling: 0.76, nitro: 0.88),
                 tuning: (1.05, 0.97, 0.96, 1.08, 0.92),
                 wheels: [(1.138, 0.325, -0.786, true), (1.138, 0.325, 0.780, true), (-1.313, 0.325, -0.784, false), (-1.313, 0.325, 0.779, false)],
                 radius: 0.325, rear: -2.200, height: 1.140)
    ]

    /// A detailed car converted with tools/convert_garage_cars.py (textured materials; the paint,
    /// glass and red lamp materials are named so the game can restyle them).
    private static func detailed(_ id: CarModelID, name: String, maker: String, className: String, stats: CarStats,
                                 tuning: (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat),
                                 wheels: [(Float, Float, Float, Bool)], radius: Float, rear: Float, height: Float) -> CarSpec {
        let file: String
        switch id {
        case .strada: file = "strada"
        case .toro: file = "toro"
        case .arrow: file = "arrow"
        case .bison: file = "bison"
        default: file = "classico"
        }
        return CarSpec(id: id, file: file, name: name, maker: maker, className: className, stats: stats,
                       wheelSpots: wheels, wheelRadius: radius, wheelModelSide: -1,
                       exhausts: [SCNVector3(rear - 0.02, 0.32, 0.34), SCNVector3(rear - 0.02, 0.32, -0.34)],
                       topSpeed: tuning.0, acceleration: tuning.1, steering: tuning.2, nitroPower: tuning.3, nitroFill: tuning.4,
                       textured: false, height: height)
    }

    static func of(_ id: CarModelID) -> CarSpec { all[id.rawValue] }
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

    static let tire = Mat.pbr(UIColor(white: 0.05, alpha: 1), metal: 0, rough: 0.85)
    static let rim = Mat.pbr(UIColor(white: 0.78, alpha: 1), metal: 0.95, rough: 0.22)
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
        material.diffuse.contents = UIImage(named: "retro_basecolor.jpg")
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

    private static var paints: [String: SCNMaterial] = [:]
    private static let textureLock = NSLock()
    private static var tintedTextures: [String: UIImage] = [:]

    /// Draws the tinted textures of the saved car (every paint) on a background thread, so
    /// picking a color does not draw an image on the main thread.
    static func prewarmRetroTextures() {
        let colors = CarSpec.paints.map { $0.color }
        let specs = CarSpec.all.filter { $0.textureBase != nil }
        DispatchQueue.global(qos: .utility).async {
            for spec in specs {
                guard let base = spec.textureBase, let mask = spec.textureMask else { continue }
                for color in colors {
                    let key = base + CarFactory.colorKey(color)
                    textureLock.lock()
                    let done = tintedTextures[key] != nil
                    textureLock.unlock()
                    if done { continue }
                    guard let image = tintedTexture(base: base, mask: mask, color: color) else { continue }
                    textureLock.lock()
                    tintedTextures[key] = image
                    textureLock.unlock()
                }
            }
        }
    }

    /// The retro car in a paint (kept for callers that only know the color).
    static func retroPaint(_ color: UIColor) -> SCNMaterial { texturePaint(CarSpec.of(.retro), color) }

    /// Material for a textured car: its texture with the paint areas tinted `color`, or the
    /// plain Kenney palette for cars with a fixed livery. Made once per car and color.
    static func texturePaint(_ spec: CarSpec, _ color: UIColor) -> SCNMaterial {
        guard let base = spec.textureBase, let mask = spec.textureMask else { return kenney }
        let key = base + CarFactory.colorKey(color)
        if let cached = paints[key] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        textureLock.lock()
        let ready = tintedTextures[key]
        textureLock.unlock()
        material.diffuse.contents = ready ?? tintedTexture(base: base, mask: mask, color: color)
        if base.hasPrefix("kenney") { material.diffuse.magnificationFilter = .nearest }
        material.metalness.contents = NSNumber(value: 0.35)
        material.roughness.contents = NSNumber(value: 0.3)
        material.clearCoat.contents = NSNumber(value: 0.8)
        material.clearCoatRoughness.contents = NSNumber(value: 0.08)
        paints[key] = material
        return material
    }

    private static func tintedTexture(base baseName: String, mask maskName: String, color: UIColor) -> UIImage? {
        guard let base = UIImage(named: baseName)?.cgImage,
              let mask = UIImage(named: maskName)?.cgImage else { return nil }
        let size = CGSize(width: base.width, height: base.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            // Core Graphics draws images bottom-up; flip so the result keeps the texture's layout
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            cg.draw(base, in: rect)
            cg.saveGState()
            if let alpha = maskImage(from: mask) { cg.clip(to: rect, mask: alpha) }
            cg.setBlendMode(.multiply)
            cg.setFillColor(color.cgColor)
            cg.fill(rect)
            cg.restoreGState()
        }
    }

    /// A grayscale image mask (white = paint) from the stored PNG.
    private static func maskImage(from image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

import SceneKit
import UIKit

/// The three player cars in the garage. Models are converted from free assets by
/// tools/convert_cars.py (see README credits); the numbers below come from that script's output.
enum CarModelID: Int, CaseIterable {
    case italia
    case concept
    case retro
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
        CarSpec(id: .italia, file: "italia", name: "Italia GT", maker: "ROSSO", className: "S",
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
                topSpeed: 0.94, acceleration: 1.07, steering: 1.08, nitroPower: 1.1, nitroFill: 0.85, textured: true)
    ]

    static func of(_ id: CarModelID) -> CarSpec { all[id.rawValue] }
}

/// Loads the USDZ car models once and gives them the game's materials.
enum CarModels {
    private static var bodies: [CarModelID: SCNNode] = [:]
    private static var wheels: [CarModelID: SCNNode] = [:]
    private static var textures: [String: UIImage] = [:]

    static func body(_ id: CarModelID) -> SCNNode? {
        if let cached = bodies[id] { return cached }
        let node = load(CarSpec.of(id).file + "_body")
        bodies[id] = node
        return node
    }

    static func wheel(_ id: CarModelID) -> SCNNode? {
        if let cached = wheels[id] { return cached }
        let node = load(CarSpec.of(id).file + "_wheel")
        wheels[id] = node
        return node
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
    static let caliper = Mat.pbr(UIColor(red: 0.95, green: 0.78, blue: 0.1, alpha: 1), metal: 0.3, rough: 0.4)
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

    private static func load(_ name: String) -> SCNNode? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz"),
              let scene = try? SCNScene(url: url, options: nil) else { return nil }
        let holder = SCNNode()
        for child in scene.rootNode.childNodes { holder.addChildNode(child) }
        let materials: [String: SCNMaterial] = [
            "glass": CarShapes.canopy, "headlight": CarShapes.led, "chrome": CarShapes.chrome,
            "carbon": CarShapes.carbon, "darkplastic": CarShapes.trim, "metal": CarShapes.graphite,
            "tire": tire, "rim": rim, "caliper": caliper, "hub": CarShapes.chrome,
            "paint": Mat.pbr(.gray), "paint2": accent, "textured": retroWheel, "interior": interior,
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

    private static var retroPaints: [String: SCNMaterial] = [:]
    private static let textureLock = NSLock()
    private static var retroTextures: [String: UIImage] = [:]

    /// Draws the retro car's texture in every paint on a background thread, so picking a color
    /// in the garage (or loading a race) does not draw a 1024² image on the main thread.
    static func prewarmRetroTextures() {
        let colors = CarSpec.paints.map { $0.color }
        DispatchQueue.global(qos: .utility).async {
            for color in colors {
                let key = CarFactory.colorKey(color)
                textureLock.lock()
                let done = retroTextures[key] != nil
                textureLock.unlock()
                if done { continue }
                guard let image = tintedRetroTexture(color) else { continue }
                textureLock.lock()
                retroTextures[key] = image
                textureLock.unlock()
            }
        }
    }

    /// The retro car's texture with its body areas tinted `color` (decals, chrome and tyres keep
    /// their own colors). Made once per color.
    static func retroPaint(_ color: UIColor) -> SCNMaterial {
        let key = CarFactory.colorKey(color)
        if let cached = retroPaints[key] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        textureLock.lock()
        let ready = retroTextures[key]
        textureLock.unlock()
        material.diffuse.contents = ready ?? tintedRetroTexture(color)
        material.metalness.contents = NSNumber(value: 0.35)
        material.roughness.contents = NSNumber(value: 0.3)
        material.clearCoat.contents = NSNumber(value: 0.8)
        material.clearCoatRoughness.contents = NSNumber(value: 0.08)
        retroPaints[key] = material
        return material
    }

    private static func tintedRetroTexture(_ color: UIColor) -> UIImage? {
        guard let base = UIImage(named: "retro_basecolor.jpg")?.cgImage,
              let mask = UIImage(named: "retro_mask.png")?.cgImage else { return nil }
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

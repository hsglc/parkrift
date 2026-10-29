import SceneKit
import UIKit

/// Photo-scanned ground, walls and skies (Poly Haven, CC0): asphalt, paving slabs, concrete and
/// grass PBR sets (colour, normal and roughness maps, 1K, tiled in metres) and two sky panoramas
/// (a partly cloudy day and an overcast one) used as background and as the light the scene
/// reflects.
enum Environment {
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

import SceneKit
import UIKit

// MARK: - Materials

private enum Mat {
    static func pbr(_ color: UIColor, metal: CGFloat = 0, rough: CGFloat = 0.6) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.metalness.contents = NSNumber(value: Double(metal))
        material.roughness.contents = NSNumber(value: Double(rough))
        return material
    }

    static func lambert(_ contents: Any) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = contents
        return material
    }

    static func glow(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.emission.contents = color
        return material
    }
}

// MARK: - Car model

enum CarStyle: Int, CaseIterable {
    case sedan
    case hatch
    case suv
    case racer
}

/// Shared car geometry (built once per style, copied per car so each can have its own paint).
private enum CarShapes {
    struct Profile {
        let body: UIBezierPath
        let cabin: UIBezierPath
        let window: UIBezierPath
        let windshield: (CGPoint, CGPoint)
        let rearWindow: (CGPoint, CGPoint)
        let roofHeight: CGFloat
    }

    /// Side silhouette of the lower body with wheel arches (x forward, y up, meters).
    static func bodyPath(nose: CGFloat, hood: CGFloat, deck: CGFloat, tail: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let bottom: CGFloat = 0.30
        let arch: CGFloat = 0.47
        path.move(to: CGPoint(x: 2.12, y: bottom))
        path.addLine(to: CGPoint(x: 1.35 + arch, y: bottom))
        path.addArc(withCenter: CGPoint(x: 1.35, y: 0.37), radius: arch, startAngle: -0.15, endAngle: CGFloat.pi + 0.15, clockwise: true)
        path.addLine(to: CGPoint(x: -1.35 + arch, y: bottom))
        path.addArc(withCenter: CGPoint(x: -1.35, y: 0.37), radius: arch, startAngle: -0.15, endAngle: CGFloat.pi + 0.15, clockwise: true)
        path.addLine(to: CGPoint(x: -2.12, y: bottom))
        path.addQuadCurve(to: CGPoint(x: -2.22, y: tail), controlPoint: CGPoint(x: -2.24, y: bottom + 0.05))
        path.addQuadCurve(to: CGPoint(x: -1.95, y: deck), controlPoint: CGPoint(x: -2.22, y: deck))
        path.addLine(to: CGPoint(x: 1.2, y: hood))
        path.addQuadCurve(to: CGPoint(x: 2.2, y: nose), controlPoint: CGPoint(x: 2.08, y: hood - 0.02))
        path.addQuadCurve(to: CGPoint(x: 2.12, y: bottom), controlPoint: CGPoint(x: 2.26, y: bottom + 0.05))
        path.close()
        path.flatness = 0.02
        return path
    }

    static func polygon(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        path.close()
        return path
    }

    static func profile(_ style: CarStyle) -> Profile {
        switch style {
        case .sedan:
            let rearBase = CGPoint(x: -1.45, y: 0.97), rearTop = CGPoint(x: -0.9, y: 1.46)
            let frontTop = CGPoint(x: 0.25, y: 1.48), frontBase = CGPoint(x: 1.12, y: 0.97)
            return Profile(body: bodyPath(nose: 0.74, hood: 0.96, deck: 0.98, tail: 0.78),
                           cabin: polygon([rearBase, rearTop, frontTop, frontBase]),
                           window: polygon([CGPoint(x: -1.2, y: 1.03), CGPoint(x: -0.82, y: 1.39),
                                            CGPoint(x: 0.2, y: 1.41), CGPoint(x: 0.88, y: 1.03)]),
                           windshield: (frontTop, frontBase), rearWindow: (rearBase, rearTop), roofHeight: 1.48)
        case .hatch:
            let rearBase = CGPoint(x: -2.0, y: 0.98), rearTop = CGPoint(x: -1.72, y: 1.5)
            let frontTop = CGPoint(x: 0.3, y: 1.52), frontBase = CGPoint(x: 1.1, y: 0.97)
            return Profile(body: bodyPath(nose: 0.76, hood: 0.96, deck: 0.98, tail: 0.82),
                           cabin: polygon([rearBase, rearTop, frontTop, frontBase]),
                           window: polygon([CGPoint(x: -1.72, y: 1.04), CGPoint(x: -1.55, y: 1.43),
                                            CGPoint(x: 0.24, y: 1.45), CGPoint(x: 0.86, y: 1.04)]),
                           windshield: (frontTop, frontBase), rearWindow: (rearBase, rearTop), roofHeight: 1.52)
        case .racer:
            let rearBase = CGPoint(x: -1.35, y: 0.8), rearTop = CGPoint(x: -0.55, y: 1.2)
            let frontTop = CGPoint(x: 0.1, y: 1.22), frontBase = CGPoint(x: 1.05, y: 0.72)
            return Profile(body: bodyPath(nose: 0.46, hood: 0.7, deck: 0.82, tail: 0.76),
                           cabin: polygon([rearBase, rearTop, frontTop, frontBase]),
                           window: polygon([CGPoint(x: -1.1, y: 0.86), CGPoint(x: -0.5, y: 1.15),
                                            CGPoint(x: 0.06, y: 1.16), CGPoint(x: 0.82, y: 0.79)]),
                           windshield: (frontTop, frontBase), rearWindow: (rearBase, rearTop), roofHeight: 1.22)
        case .suv:
            let rearBase = CGPoint(x: -2.08, y: 1.12), rearTop = CGPoint(x: -1.98, y: 1.82)
            let frontTop = CGPoint(x: 0.55, y: 1.84), frontBase = CGPoint(x: 1.25, y: 1.12)
            return Profile(body: bodyPath(nose: 0.9, hood: 1.1, deck: 1.12, tail: 0.95),
                           cabin: polygon([rearBase, rearTop, frontTop, frontBase]),
                           window: polygon([CGPoint(x: -1.9, y: 1.2), CGPoint(x: -1.84, y: 1.74),
                                            CGPoint(x: 0.5, y: 1.76), CGPoint(x: 1.02, y: 1.2)]),
                           windshield: (frontTop, frontBase), rearWindow: (rearBase, rearTop), roofHeight: 1.84)
        }
    }

    private static var cache: [CarStyle: (body: SCNGeometry, cabin: SCNGeometry, window: SCNGeometry)] = [:]

    static func geometry(_ style: CarStyle) -> (body: SCNGeometry, cabin: SCNGeometry, window: SCNGeometry) {
        if let cached = cache[style] { return cached }
        let p = profile(style)
        let body = SCNShape(path: p.body, extrusionDepth: 2.0)
        body.chamferRadius = 0.1
        body.chamferMode = .both
        let cabin = SCNShape(path: p.cabin, extrusionDepth: style == .racer ? 1.5 : 1.7)
        cabin.chamferRadius = 0.08
        cabin.chamferMode = .both
        let window = SCNShape(path: p.window, extrusionDepth: 0.02)
        let result = (body: body as SCNGeometry, cabin: cabin as SCNGeometry, window: window as SCNGeometry)
        cache[style] = result
        return result
    }

    static let tyre: SCNGeometry = {
        let tyre = SCNCylinder(radius: 0.36, height: 0.26)
        tyre.radialSegmentCount = 18
        tyre.materials = [Mat.pbr(UIColor(white: 0.06, alpha: 1), metal: 0, rough: 0.9)]
        return tyre
    }()

    static let rim: SCNGeometry = {
        let rim = SCNCylinder(radius: 0.23, height: 0.28)
        rim.radialSegmentCount = 12
        rim.materials = [Mat.pbr(UIColor(white: 0.78, alpha: 1), metal: 0.9, rough: 0.3)]
        return rim
    }()

    static let hubcap: SCNGeometry = {
        let cap = SCNCylinder(radius: 0.08, height: 0.3)
        cap.radialSegmentCount = 8
        cap.materials = [Mat.pbr(UIColor(white: 0.25, alpha: 1), metal: 0.7, rough: 0.4)]
        return cap
    }()

    static let glass = Mat.pbr(UIColor(red: 0.08, green: 0.12, blue: 0.19, alpha: 1), metal: 0.7, rough: 0.08)
    static let trim = Mat.pbr(UIColor(white: 0.10, alpha: 1), metal: 0.1, rough: 0.75)
    static let chrome = Mat.pbr(UIColor(white: 0.82, alpha: 1), metal: 0.95, rough: 0.2)
    static let headlight = Mat.glow(UIColor(red: 1.0, green: 0.97, blue: 0.86, alpha: 1))
    static let stripe = Mat.pbr(UIColor(white: 0.97, alpha: 1), metal: 0.2, rough: 0.35)
    static let carbon = Mat.pbr(UIColor(white: 0.06, alpha: 1), metal: 0.5, rough: 0.35)

    /// Thin slices of the body/cabin silhouettes, used as racing stripes.
    private static var stripeCache: (body: SCNGeometry, cabin: SCNGeometry)?
    static func stripes() -> (body: SCNGeometry, cabin: SCNGeometry) {
        if let cached = stripeCache { return cached }
        let p = profile(.racer)
        let body = SCNShape(path: p.body, extrusionDepth: 0.2)
        body.chamferRadius = 0.04
        let cabin = SCNShape(path: p.cabin, extrusionDepth: 0.2)
        cabin.chamferRadius = 0.04
        stripeCache = (body, cabin)
        return (body, cabin)
    }

    static let flameOuter: SCNGeometry = {
        let cone = SCNCone(topRadius: 0, bottomRadius: 0.16, height: 1.0)
        cone.radialSegmentCount = 10
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(red: 0.25, green: 0.6, blue: 1.0, alpha: 0.85)
        material.blendMode = .add
        material.writesToDepthBuffer = false
        cone.materials = [material]
        return cone
    }()

    static let flameInner: SCNGeometry = {
        let cone = SCNCone(topRadius: 0, bottomRadius: 0.08, height: 0.6)
        cone.radialSegmentCount = 8
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 1)
        material.blendMode = .add
        material.writesToDepthBuffer = false
        cone.materials = [material]
        return cone
    }()
}

/// Builds and caches car geometry. With optimizations on, every car's static parts are one merged
/// geometry (a few draw calls), shared by all cars of the same style and color, with a simple
/// far-distance version (level of detail).
private enum CarFactory {
    static func colorKey(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.3f-%.3f-%.3f", r, g, b)
    }

    private static var paints: [String: SCNMaterial] = [:]
    static func paint(_ color: UIColor) -> SCNMaterial {
        let key = colorKey(color)
        if let cached = paints[key] { return cached }
        let paint = Mat.pbr(color, metal: 0.35, rough: 0.32)
        paint.fresnelExponent = 1.5
        paints[key] = paint
        return paint
    }

    static let parkedBrake = Mat.glow(UIColor(red: 0.45, green: 0.03, blue: 0.04, alpha: 1))

    /// All static parts of a car (body, cabin, glass, trim, lights, racer extras), in car space.
    static func buildParts(style: CarStyle, paint: SCNMaterial) -> SCNNode {
        let profile = CarShapes.profile(style)
        let shapes = CarShapes.geometry(style)
        let parts = SCNNode()

        func add(_ geometry: SCNGeometry, _ material: SCNMaterial, at position: SCNVector3,
                 rotation: SCNVector3 = SCNVector3Zero, to parent: SCNNode) {
            let copy = geometry.copy() as! SCNGeometry
            copy.materials = [material]
            let child = SCNNode(geometry: copy)
            // Center extruded shapes on the requested z, whatever their extrusion origin
            let (low, high) = copy.boundingBox
            child.position = SCNVector3(position.x, position.y, position.z - (low.z + high.z) / 2)
            child.eulerAngles = rotation
            parent.addChildNode(child)
        }
        func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ chamfer: CGFloat, _ material: SCNMaterial,
                 at position: SCNVector3, rotationZ: Float = 0, to parent: SCNNode) {
            let geometry = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
            geometry.chamferSegmentCount = 2
            geometry.materials = [material]
            let child = SCNNode(geometry: geometry)
            child.position = position
            child.eulerAngles.z = rotationZ
            parent.addChildNode(child)
        }

        // Body and cabin (extruded along z, centered)
        add(shapes.body, paint, at: SCNVector3(0, 0, 0), to: parts)
        add(shapes.cabin, paint, at: SCNVector3(0, -0.01, 0), to: parts)
        // Side windows
        add(shapes.window, CarShapes.glass, at: SCNVector3(0, 0, 0.862), to: parts)
        add(shapes.window, CarShapes.glass, at: SCNVector3(0, 0, -0.862), to: parts)
        // B-pillar
        let pillarX = Float((profile.windshield.0.x + profile.rearWindow.1.x) / 2)
        box(0.1, profile.roofHeight - 1.0, 1.74, 0.02, CarShapes.trim,
            at: SCNVector3(pillarX, Float((profile.roofHeight + 1.0) / 2), 0), to: parts)
        // Windshield and rear window as tilted glass panels
        for (a, b) in [profile.windshield, profile.rearWindow] {
            let length = hypot(b.x - a.x, b.y - a.y)
            let angle = atan2(b.y - a.y, b.x - a.x)
            let normal = CGPoint(x: -sin(angle), y: cos(angle))
            let outward: CGFloat = a.x > 0 || b.x > 0 ? 1 : -1
            let mid = CGPoint(x: (a.x + b.x) / 2 + normal.x * 0.012 * outward, y: (a.y + b.y) / 2 + normal.y * 0.012 * outward)
            box(length * 0.9, 0.02, 1.5, 0.005, CarShapes.glass,
                at: SCNVector3(Float(mid.x), Float(mid.y), 0), rotationZ: Float(angle), to: parts)
        }
        // Bumpers, grille, mirrors
        box(0.18, 0.2, 1.96, 0.08, CarShapes.trim, at: SCNVector3(2.16, 0.38, 0), to: parts)
        box(0.18, 0.2, 1.96, 0.08, CarShapes.trim, at: SCNVector3(-2.16, 0.38, 0), to: parts)
        box(0.05, 0.16, 0.9, 0.03, CarShapes.trim, at: SCNVector3(2.2, 0.58, 0), to: parts)
        box(0.04, 0.03, 0.86, 0.01, CarShapes.chrome, at: SCNVector3(2.225, 0.64, 0), to: parts)
        let mirrorY = Float(profile.windshield.1.y + 0.08)
        let mirrorX = Float(profile.windshield.1.x - 0.12)
        for z: Float in [1.0, -1.0] {
            box(0.16, 0.12, 0.2, 0.04, paint, at: SCNVector3(mirrorX, mirrorY, z), to: parts)
            // Door handles
            box(0.14, 0.03, 0.02, 0.01, CarShapes.chrome, at: SCNVector3(0.25, 0.86, z * 1.005), to: parts)
            box(0.14, 0.03, 0.02, 0.01, CarShapes.chrome, at: SCNVector3(-0.75, 0.86, z * 1.005), to: parts)
        }
        // Headlights
        let headlightY: Float = style == .racer ? 0.56 : 0.72
        for z: Float in [0.66, -0.66] {
            box(0.08, 0.11, 0.4, 0.04, CarShapes.headlight, at: SCNVector3(2.17, headlightY, z), to: parts)
        }
        if style == .racer {
            // Twin racing stripes over nose, roof and tail
            let stripes = CarShapes.stripes()
            for z: Float in [0.2, -0.2] {
                let bodyStripe = SCNNode(geometry: stripes.body.copy() as? SCNGeometry)
                bodyStripe.geometry?.materials = [CarShapes.stripe]
                bodyStripe.scale = SCNVector3(1.004, 1.012, 1)
                let bodyStripeBox = bodyStripe.boundingBox
                bodyStripe.position = SCNVector3(0, -0.004, z - (bodyStripeBox.min.z + bodyStripeBox.max.z) / 2)
                parts.addChildNode(bodyStripe)
                let cabinStripe = SCNNode(geometry: stripes.cabin.copy() as? SCNGeometry)
                cabinStripe.geometry?.materials = [CarShapes.stripe]
                cabinStripe.scale = SCNVector3(1.006, 1.012, 1)
                let cabinStripeBox = cabinStripe.boundingBox
                cabinStripe.position = SCNVector3(0, -0.012, z - (cabinStripeBox.min.z + cabinStripeBox.max.z) / 2)
                parts.addChildNode(cabinStripe)
            }
            // Rear wing on two struts
            for z: Float in [0.62, -0.62] {
                box(0.1, 0.36, 0.07, 0.02, CarShapes.carbon, at: SCNVector3(-1.95, 0.98, z), to: parts)
            }
            box(0.5, 0.07, 2.1, 0.03, CarShapes.carbon, at: SCNVector3(-2.0, 1.17, 0), to: parts)
            for z: Float in [1.05, -1.05] {
                box(0.55, 0.22, 0.04, 0.02, paint, at: SCNVector3(-2.0, 1.12, z), to: parts)
                // Side skirts
                box(2.4, 0.1, 0.08, 0.03, CarShapes.carbon, at: SCNVector3(0, 0.31, z * 0.97), to: parts)
            }
            // Front splitter and hood scoop
            box(0.35, 0.05, 2.0, 0.02, CarShapes.carbon, at: SCNVector3(2.12, 0.27, 0), to: parts)
            box(0.5, 0.08, 0.5, 0.04, CarShapes.carbon, at: SCNVector3(1.5, 0.74, 0), to: parts)
            // Exhaust pipes
            let pipe = SCNCylinder(radius: 0.07, height: 0.25)
            pipe.radialSegmentCount = 10
            pipe.materials = [CarShapes.chrome]
            for z: Float in [0.42, -0.42] {
                let pipeNode = SCNNode(geometry: pipe)
                pipeNode.eulerAngles.z = Float.pi / 2
                pipeNode.position = SCNVector3(-2.2, 0.36, z)
                parts.addChildNode(pipeNode)
            }
        }
        return parts
    }

    static func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ chamfer: CGFloat, _ material: SCNMaterial,
                    at position: SCNVector3, to parent: SCNNode) -> SCNNode {
        let geometry = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
        geometry.chamferSegmentCount = 2
        geometry.materials = [material]
        let child = SCNNode(geometry: geometry)
        child.position = position
        parent.addChildNode(child)
        return child
    }

    static let wheelSpots: [(Float, Float, Bool)] = [(1.35, 0.92, true), (1.35, -0.92, true), (-1.35, 0.92, false), (-1.35, -0.92, false)]

    static func tailY(_ style: CarStyle) -> Float { style == .suv ? 0.88 : 0.8 }

    /// Tyre + rim + hubcap as one geometry, hidden beyond the detail distance.
    static let wheel: SCNGeometry = {
        let holder = SCNNode()
        for geometry in [CarShapes.tyre, CarShapes.rim, CarShapes.hubcap] {
            let part = SCNNode(geometry: geometry)
            part.eulerAngles.x = Float.pi / 2
            holder.addChildNode(part)
        }
        let merged = GeometryMerger.merge(holder) ?? CarShapes.tyre
        merged.levelsOfDetail = [SCNLevelOfDetail(geometry: nil, worldSpaceDistance: PerfSettings.carDetailDistance)]
        return merged
    }()

    /// Simple far-away car: body block and dark cabin.
    private static func lowDetail(style: CarStyle, paint: SCNMaterial) -> SCNGeometry? {
        let holder = SCNNode()
        let profile = CarShapes.profile(style)
        let bodyTop: CGFloat = style == .racer ? 0.8 : (style == .suv ? 1.1 : 0.98)
        _ = box(4.3, bodyTop - 0.28, 2.0, 0.15, paint, at: SCNVector3(0, Float((bodyTop + 0.28) / 2), 0), to: holder)
        let cabinLength = abs(profile.windshield.1.x - profile.rearWindow.0.x) * 0.8
        let cabinX = Float((profile.windshield.1.x + profile.rearWindow.0.x) / 2)
        _ = box(cabinLength, profile.roofHeight - bodyTop, style == .racer ? 1.5 : 1.7, 0.12, CarShapes.glass,
                at: SCNVector3(cabinX, Float((profile.roofHeight + bodyTop) / 2), 0), to: holder)
        for spot in wheelSpots {
            _ = box(0.7, 0.6, 0.26, 0.1, CarShapes.trim, at: SCNVector3(spot.0, 0.33, spot.1), to: holder)
        }
        return GeometryMerger.merge(holder)
    }

    private static var bodies: [String: SCNGeometry] = [:]

    /// Merged static geometry for a moving car (lights and wheels are separate) or a parked car
    /// (everything baked in).
    static func body(style: CarStyle, color: UIColor, parked: Bool) -> SCNGeometry {
        let key = "\(style.rawValue)-\(colorKey(color))-\(parked)"
        if let cached = bodies[key] { return cached }
        let paintMaterial = paint(color)
        let parts = buildParts(style: style, paint: paintMaterial)
        if parked {
            for z: Float in [0.66, -0.66] {
                _ = box(0.07, 0.12, 0.42, 0.03, parkedBrake, at: SCNVector3(-2.2, tailY(style), z), to: parts)
            }
            for spot in wheelSpots {
                let wheelNode = SCNNode()
                wheelNode.position = SCNVector3(spot.0, 0.36, spot.1)
                for geometry in [CarShapes.tyre, CarShapes.rim, CarShapes.hubcap] {
                    let part = SCNNode(geometry: geometry)
                    part.eulerAngles.x = Float.pi / 2
                    wheelNode.addChildNode(part)
                }
                parts.addChildNode(wheelNode)
            }
        }
        let merged = GeometryMerger.merge(parts) ?? SCNBox(width: 4.3, height: 1, length: 2, chamferRadius: 0.2)
        if let low = lowDetail(style: style, paint: paintMaterial) {
            merged.levelsOfDetail = [SCNLevelOfDetail(geometry: low, worldSpaceDistance: PerfSettings.carDetailDistance)]
        }
        bodies[key] = merged
        return merged
    }
}

/// 3D car: extruded body silhouette with wheel arches, cabin, glass, lights, bumpers and mirrors.
/// Faces +x in its local frame (meters).
final class Car3D {
    let node = SCNNode()
    private let body = SCNNode()
    private var steerPivots: [SCNNode] = []
    private var spinNodes: [SCNNode] = []
    private let brakeMaterial: SCNMaterial
    private let reverseMaterial: SCNMaterial
    private var spin: CGFloat = 0
    private var lastPosition: CGPoint?
    private var flames: [SCNNode] = []
    private var nitroOn = false
    private var lastBraking: Bool?
    private var lastReversing: Bool?

    /// `parked`: a car that never moves (wheels and lights baked into one geometry).
    init(color: UIColor, style: CarStyle = .sedan, parked: Bool = false) {
        brakeMaterial = Mat.glow(UIColor(red: 0.55, green: 0.04, blue: 0.05, alpha: 1))
        reverseMaterial = Mat.glow(UIColor(white: 0.35, alpha: 1))
        node.addChildNode(body)

        if PerfSettings.optimized {
            body.addChildNode(SCNNode(geometry: CarFactory.body(style: style, color: color, parked: parked)))
            if parked { return }
        } else {
            let paint = Mat.pbr(color, metal: 0.35, rough: 0.32)
            paint.fresnelExponent = 1.5
            body.addChildNode(CarFactory.buildParts(style: style, paint: paint).flattenedClone())
        }

        if style == .racer {
            for z: Float in [0.42, -0.42] {
                let flame = SCNNode()
                flame.position = SCNVector3(-2.32, 0.36, z)
                let outer = SCNNode(geometry: CarShapes.flameOuter)
                outer.eulerAngles.z = Float.pi / 2
                outer.position = SCNVector3(-0.5, 0, 0)
                flame.addChildNode(outer)
                let inner = SCNNode(geometry: CarShapes.flameInner)
                inner.eulerAngles.z = Float.pi / 2
                inner.position = SCNVector3(-0.3, 0, 0)
                flame.addChildNode(inner)
                flame.isHidden = true
                body.addChildNode(flame)
                flames.append(flame)
            }
        }

        // Lights that change at runtime stay separate
        let tailY = CarFactory.tailY(style)
        var lights: [SCNNode] = []
        for z: Float in [0.66, -0.66] {
            lights.append(CarFactory.box(0.07, 0.12, 0.42, 0.03, brakeMaterial, at: SCNVector3(-2.2, tailY, z), to: body))
        }
        lights.append(CarFactory.box(0.06, 0.08, 0.26, 0.02, reverseMaterial, at: SCNVector3(-2.2, tailY - 0.14, 0), to: body))
        if PerfSettings.optimized {
            for light in lights {
                light.castsShadow = false
                light.geometry?.levelsOfDetail = [SCNLevelOfDetail(geometry: nil, worldSpaceDistance: PerfSettings.carDetailDistance)]
            }
        }

        // Wheels: pivot (steering) -> spin (rolling) -> tyre + rim
        for spot in CarFactory.wheelSpots {
            let pivot = SCNNode()
            pivot.position = SCNVector3(spot.0, 0.36, spot.1)
            let spinner = SCNNode()
            if PerfSettings.optimized {
                let wheelNode = SCNNode(geometry: CarFactory.wheel)
                wheelNode.castsShadow = false
                spinner.addChildNode(wheelNode)
            } else {
                for geometry in [CarShapes.tyre, CarShapes.rim, CarShapes.hubcap] {
                    let part = SCNNode(geometry: geometry)
                    part.eulerAngles.x = Float.pi / 2
                    spinner.addChildNode(part)
                }
            }
            pivot.addChildNode(spinner)
            node.addChildNode(pivot)
            spinNodes.append(spinner)
            if spot.2 { steerPivots.append(pivot) }
        }
    }

    func update(position: CGPoint, heading: CGFloat, steer: CGFloat,
                pitch: CGFloat = 0, roll: CGFloat = 0, braking: Bool = false, reversing: Bool = false) {
        node.position = World3D.vec(position)
        node.eulerAngles = SCNVector3(0, Float(heading), 0)
        for pivot in steerPivots { pivot.eulerAngles.y = Float(steer) }
        body.eulerAngles = SCNVector3(Float(roll), 0, Float(pitch))

        if let last = lastPosition {
            let dx = position.x - last.x
            let dy = position.y - last.y
            let travelled = (dx * cos(heading) + dy * sin(heading)) / 10   // meters
            spin -= travelled / 0.37
            for spinner in spinNodes { spinner.eulerAngles.z = Float(spin) }
        }
        lastPosition = position

        if !PerfSettings.optimized || lastBraking != braking {
            lastBraking = braking
            brakeMaterial.emission.contents = braking
                ? UIColor(red: 1.0, green: 0.10, blue: 0.08, alpha: 1)
                : UIColor(red: 0.55, green: 0.04, blue: 0.05, alpha: 1)
        }
        if !PerfSettings.optimized || lastReversing != reversing {
            lastReversing = reversing
            reverseMaterial.emission.contents = reversing ? UIColor.white : UIColor(white: 0.35, alpha: 1)
        }
        if nitroOn {
            for flame in flames {
                let length = Float.random(in: 0.75...1.35)
                let width = Float.random(in: 0.85...1.15)
                flame.scale = SCNVector3(length, width, width)
            }
        }
    }

    /// Exhaust flames while the nitro burns.
    func setNitro(_ on: Bool) {
        guard on != nitroOn else { return }
        nitroOn = on
        for flame in flames { flame.isHidden = !on }
    }

    var isHidden: Bool {
        get { node.isHidden }
        set { node.isHidden = newValue }
    }
}

// MARK: - World

/// The 3D parking lot: chase camera behind the player's car, sun with shadows, lot, scenery and level props.
final class World3D {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let levelRoot = SCNNode()
    /// Classic parking lot ground, curbs, trees and poles (hidden in the city).
    private let lotRoot = SCNNode()
    private let fxRoot = SCNNode()
    private(set) var arrowNode: SCNNode?
    private var myNeon: SCNNode?
    private var viewSize = CGSize(width: 852, height: 393)
    private let skidGeometry: SCNPlane

    /// World units (1000 x 500, y up) -> scene meters (x right, z towards the camera).
    static func vec(_ point: CGPoint, y: CGFloat = 0) -> SCNVector3 {
        SCNVector3(Float(point.x / 10 - 50), Float(y), Float(25 - point.y / 10))
    }

    init() {
        skidGeometry = SCNPlane(width: 0.42, height: 0.36)
        let skidMaterial = SCNMaterial()
        skidMaterial.lightingModel = .constant
        skidMaterial.diffuse.contents = UIColor(white: 0.03, alpha: 0.5)
        skidMaterial.writesToDepthBuffer = false
        skidGeometry.materials = [skidMaterial]

        scene.background.contents = CarArt.skyImage()
        scene.fogColor = UIColor(red: 0.84, green: 0.90, blue: 0.97, alpha: 1)
        scene.fogStartDistance = 70
        scene.fogEndDistance = 200
        scene.lightingEnvironment.contents = CarArt.skyImage()
        scene.lightingEnvironment.intensity = 1.1
        buildLights()
        scene.rootNode.addChildNode(lotRoot)
        buildGround()
        buildScenery()
        scene.rootNode.addChildNode(levelRoot)
        scene.rootNode.addChildNode(fxRoot)

        let camera = SCNCamera()
        camera.fieldOfView = fieldOfView
        camera.projectionDirection = .vertical
        camera.zNear = 0.3
        camera.zFar = 260
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        follow(position: CGPoint(x: 500, y: 250), heading: 0, dt: 0, snap: true)
    }

    private func buildLights() {
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1150
        sun.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        sun.castsShadow = true
        sun.shadowMode = .forward
        sun.shadowSampleCount = PerfSettings.optimized ? 4 : 16
        sun.shadowRadius = 3
        sun.shadowColor = UIColor.black.withAlphaComponent(0.5)
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.orthographicScale = 60
        sun.automaticallyAdjustsShadowProjection = true
        sun.maximumShadowDistance = 60
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.95, 0.6, 0)
        scene.rootNode.addChildNode(sunNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 420
        ambient.color = UIColor(red: 0.80, green: 0.86, blue: 1.0, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
    }

    private func flat(_ plane: SCNPlane, y: Float) -> SCNNode {
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -Float.pi / 2
        node.position.y = y
        return node
    }

    private func buildGround() {
        // Grass all around
        let grass = SCNPlane(width: 600, height: 600)
        let grassMaterial = Mat.lambert(CarArt.grassImage(size: CGSize(width: 128, height: 128)))
        grassMaterial.diffuse.wrapS = .repeat
        grassMaterial.diffuse.wrapT = .repeat
        grassMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(120, 120, 1)
        grass.materials = [grassMaterial]
        scene.rootNode.addChildNode(flat(grass, y: -0.06))

        // Asphalt lot
        let lot = SCNPlane(width: 100, height: 50)
        let lotMaterial = Mat.lambert(CarArt.asphaltImage(size: Levels.world))
        lot.materials = [lotMaterial]
        lotRoot.addChildNode(flat(lot, y: 0))

        // Raised curbs
        let concrete = Mat.pbr(UIColor(red: 0.78, green: 0.78, blue: 0.80, alpha: 1), rough: 0.9)
        let curbs: [(CGFloat, CGFloat, Float, Float)] = [(101, 1.0, 0, -24.6), (101, 1.0, 0, 24.6), (1.0, 50, -49.6, 0), (1.0, 50, 49.6, 0)]
        for curb in curbs {
            let geometry = SCNBox(width: curb.0, height: 0.22, length: curb.1, chamferRadius: 0.06)
            geometry.materials = [concrete]
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(curb.2, 0.11, curb.3)
            lotRoot.addChildNode(node)
        }
    }

    private func buildScenery() {
        let trees = SCNNode()
        let trunk = SCNCylinder(radius: 0.22, height: 1.6)
        trunk.radialSegmentCount = 5
        trunk.materials = [Mat.lambert(UIColor(red: 0.42, green: 0.28, blue: 0.17, alpha: 1))]
        let crownA = SCNSphere(radius: 1.7)
        crownA.segmentCount = 5
        crownA.materials = [Mat.lambert(UIColor(red: 0.24, green: 0.55, blue: 0.27, alpha: 1))]
        let crownB = SCNSphere(radius: 1.2)
        crownB.segmentCount = 4
        crownB.materials = [Mat.lambert(UIColor(red: 0.36, green: 0.66, blue: 0.32, alpha: 1))]

        var generator = SystemRandomNumberGenerator()
        var placed = 0
        var attempts = 0
        while placed < 90 && attempts < 1500 {
            attempts += 1
            let x = Float.random(in: -95...95, using: &generator)
            let z = Float.random(in: -70...70, using: &generator)
            if abs(x) < 62 && abs(z) < 37 { continue }
            let tree = SCNNode()
            tree.position = SCNVector3(x, 0, z)
            let scale = Float.random(in: 0.8...1.4, using: &generator)
            tree.scale = SCNVector3(scale, scale, scale)
            let trunkNode = SCNNode(geometry: trunk)
            trunkNode.position.y = 0.8
            tree.addChildNode(trunkNode)
            let crown = SCNNode(geometry: crownA)
            crown.position.y = 2.6
            tree.addChildNode(crown)
            let top = SCNNode(geometry: crownB)
            top.position = SCNVector3(0.5, 3.6, -0.3)
            tree.addChildNode(top)
            trees.addChildNode(tree)
            placed += 1
        }
        lotRoot.addChildNode(trees.flattenedClone())

        // Light poles at the lot corners
        let pole = SCNCylinder(radius: 0.12, height: 6)
        pole.radialSegmentCount = 6
        pole.materials = [Mat.pbr(UIColor(white: 0.35, alpha: 1), metal: 0.8, rough: 0.4)]
        let lamp = SCNBox(width: 1.2, height: 0.2, length: 0.5, chamferRadius: 0.08)
        lamp.materials = [Mat.glow(UIColor(red: 1.0, green: 0.95, blue: 0.8, alpha: 1))]
        for corner: (Float, Float) in [(-51.5, -26.5), (51.5, -26.5), (-51.5, 26.5), (51.5, 26.5)] {
            let poleNode = SCNNode(geometry: pole)
            poleNode.position = SCNVector3(corner.0, 3, corner.1)
            lotRoot.addChildNode(poleNode)
            let lampNode = SCNNode(geometry: lamp)
            lampNode.position = SCNVector3(corner.0 + (corner.0 > 0 ? -0.6 : 0.6), 6, corner.1)
            lotRoot.addChildNode(lampNode)
        }
    }

    // MARK: Camera

    /// Chase camera settings (meters / degrees).
    private let chaseDistance: Float = 13.5
    private let chaseHeight: Float = 7.2
    private let lookAhead: Float = 6.5
    private let lookHeight: Float = 0.6
    private var fieldOfView: CGFloat = 56
    private var cameraYaw: Float = 0
    private var cameraFocus = SIMD3<Float>(0, 0, 0)
    private var cameraReady = false
    private var shakeAmount: Float = 0

    /// Keeps the projection in sync with the view size.
    func fit(size: CGSize, insets: UIEdgeInsets, topReserved: CGFloat) {
        viewSize = size
    }

    /// Third-person camera behind the car, looking the way the car points.
    // MARK: Finish cinematic

    private var cinematicAngle: Float = 0
    private var cinematicTime: Float = 0
    private var cinematicActive = false

    /// Camera swings around the car while confetti and fireworks go off at the finish line.
    func startFinishCinematic(at position: CGPoint, heading: CGFloat, finishLine: CGPoint) {
        cinematicActive = true
        cinematicTime = 0
        cinematicAngle = Float(heading) + Float.pi * 1.15
        let finish = World3D.vec(finishLine, y: 6.4)
        let confetti = SCNParticleSystem()
        confetti.birthRate = 900
        confetti.emissionDuration = 0.35
        confetti.loops = false
        confetti.particleLifeSpan = 3.2
        confetti.particleLifeSpanVariation = 0.8
        confetti.particleVelocity = 11
        confetti.particleVelocityVariation = 6
        confetti.emittingDirection = SCNVector3(0, 1, 0)
        confetti.spreadingAngle = 75
        confetti.acceleration = SCNVector3(0, -7, 0)
        confetti.dampingFactor = 1.2
        confetti.particleSize = 0.14
        confetti.particleSizeVariation = 0.06
        confetti.particleColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1)
        confetti.particleColorVariation = SCNVector4(1, 0.4, 0.2, 0)
        confetti.particleAngularVelocity = 400
        confetti.particleAngularVelocityVariation = 300
        confetti.particleImage = CarArt.squareParticle()
        let confettiNode = SCNNode()
        confettiNode.position = finish
        confettiNode.addParticleSystem(confetti)
        fxRoot.addChildNode(confettiNode)

        // Three firework bursts above the finish line
        for (index, offset) in [SIMD3<Float>(-5, 9, 0), SIMD3<Float>(4, 11, 2), SIMD3<Float>(0, 13, -3)].enumerated() {
            let burst = SCNParticleSystem()
            burst.birthRate = 1400
            burst.emissionDuration = 0.08
            burst.loops = false
            burst.particleLifeSpan = 1.3
            burst.particleLifeSpanVariation = 0.4
            burst.particleVelocity = 9
            burst.particleVelocityVariation = 2
            burst.spreadingAngle = 180
            burst.acceleration = SCNVector3(0, -3, 0)
            burst.dampingFactor = 1.5
            burst.particleSize = 0.22
            burst.blendMode = .additive
            burst.particleColor = [UIColor(red: 1, green: 0.82, blue: 0.2, alpha: 1),
                                   UIColor(red: 0.3, green: 0.85, blue: 1, alpha: 1),
                                   UIColor(red: 1, green: 0.35, blue: 0.6, alpha: 1)][index]
            burst.particleColorVariation = SCNVector4(0.05, 0.1, 0.1, 0)
            burst.particleImage = CarArt.glowParticle()
            let propertyAnimation = CAKeyframeAnimation()
            propertyAnimation.values = [1.0, 1.0, 0.0]
            propertyAnimation.keyTimes = [0, 0.6, 1]
            let controller = SCNParticlePropertyController(animation: propertyAnimation)
            burst.propertyControllers = [.opacity: controller]
            let node = SCNNode()
            node.position = SCNVector3(finish.x + offset.x, offset.y, finish.z + offset.z)
            fxRoot.addChildNode(node)
            node.runAction(.sequence([.wait(duration: 0.25 + Double(index) * 0.45), .run { $0.addParticleSystem(burst) }]))
        }
    }

    func stopCinematic() {
        cinematicActive = false
    }

    func follow(position: CGPoint, heading: CGFloat, dt: CGFloat, snap: Bool = false) {
        let carPoint = World3D.vec(position)
        let focus = SIMD3<Float>(carPoint.x, carPoint.y, carPoint.z)
        if cinematicActive && !snap {
            cinematicTime += Float(dt)
            cinematicAngle += Float(dt) * (0.9 - min(cinematicTime, 2.5) * 0.25)
            cameraFocus += (focus - cameraFocus) * min(1, Float(dt) * 8)
            let radius = 10 - min(cinematicTime, 2) * 1.6
            let height = 2.2 + sin(min(cinematicTime, 3) * 0.6) * 1.6
            let eye = cameraFocus + SIMD3<Float>(cos(cinematicAngle) * radius, height, -sin(cinematicAngle) * radius)
            cameraNode.simdPosition = eye
            cameraNode.simdLook(at: cameraFocus + SIMD3<Float>(0, 0.9, 0), up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
            return
        }
        let yaw = Float(heading)
        if snap || !cameraReady {
            cameraYaw = yaw
            cameraFocus = focus
            cameraReady = true
        } else {
            let k = 1 - exp(-Float(dt) * 4.5)
            cameraYaw += Float(CGFloat.angleDelta(CGFloat(cameraYaw), CGFloat(yaw))) * k
            let p = 1 - exp(-Float(dt) * 14)
            cameraFocus += (focus - cameraFocus) * p
        }
        // Car forward in scene space: world (cos h, sin h) -> scene (cos h, 0, -sin h)
        let forward = SIMD3<Float>(cos(cameraYaw), 0, -sin(cameraYaw))
        let side = SIMD3<Float>(sin(cameraYaw), 0, cos(cameraYaw))
        var eye = cameraFocus - forward * chaseDistance + SIMD3<Float>(0, chaseHeight, 0)
        if shakeAmount > 0.001 {
            eye += side * Float.random(in: -shakeAmount...shakeAmount)
            eye.y += Float.random(in: -shakeAmount...shakeAmount) * 0.5
            shakeAmount *= exp(-Float(dt) * 14)
        }
        let target = cameraFocus + forward * lookAhead + SIMD3<Float>(0, lookHeight, 0)
        cameraNode.simdPosition = eye
        cameraNode.simdLook(at: target, up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
    }

    /// Screen position (SpriteKit coordinates, origin bottom-left) of a world point at a height in meters.
    /// Points behind the camera are returned far off-screen.
    func project(_ point: CGPoint, height: CGFloat = 0) -> CGPoint {
        let p = World3D.vec(point, y: height)
        let c = cameraNode.simdWorldTransform.inverse * SIMD4<Float>(p.x, p.y, p.z, 1)
        guard c.z < -0.1 else { return CGPoint(x: -10000, y: -10000) }
        let focal = (viewSize.height / 2) / tan(fieldOfView * CGFloat.pi / 360)
        let depth = CGFloat(-c.z)
        return CGPoint(x: viewSize.width / 2 + CGFloat(c.x) / depth * focal,
                       y: viewSize.height / 2 + CGFloat(c.y) / depth * focal)
    }

    /// Nitro: widen the view (0 = normal, 1 = full boost).
    func setBoost(_ amount: CGFloat) {
        fieldOfView = 56 + 16 * amount
        cameraNode.camera?.fieldOfView = fieldOfView
    }

    func shake(strength: CGFloat) {
        shakeAmount = max(shakeAmount, Float(strength) * 0.05)
    }

    // MARK: Level

    func makeCar(color: UIColor, style: CarStyle = .sedan) -> Car3D {
        let car = Car3D(color: color, style: style)
        scene.rootNode.addChildNode(car.node)
        return car
    }

    func load(level: LevelDef, spotSlots: [Int], mySlot: Int) {
        levelRoot.childNodes.forEach { $0.removeFromParentNode() }
        fxRoot.childNodes.forEach { $0.removeFromParentNode() }
        myNeon = nil
        cinematicActive = false
        arrowNode = nil
        lotRoot.isHidden = level.city != nil
        if let city = level.city {
            buildCity(city, world: level.world)
        }

        if level.race { buildFinish(level.spots[0]) }
        for spotSlot in (level.race ? [] : spotSlots) {
            let def = level.spots[spotSlot]
            let color = CarArt.playerColors[spotSlot]
            let holder = SCNNode()
            holder.position = World3D.vec(def.center, y: 0.02)
            holder.eulerAngles.y = Float(def.angle)
            let plane = SCNPlane(width: def.size.width / 10, height: def.size.height / 10)
            let material = Mat.lambert(CarArt.spotImage(size: def.size, color: color))
            material.isDoubleSided = true
            plane.materials = [material]
            holder.addChildNode(flat(plane, y: 0))

            let outline = SCNPlane(width: def.size.width / 10 + 0.3, height: def.size.height / 10 + 0.3)
            let outlineMaterial = SCNMaterial()
            outlineMaterial.lightingModel = .constant
            outlineMaterial.diffuse.contents = CarArt.spotOutlineImage(size: CGSize(width: def.size.width + 3, height: def.size.height + 3), color: color)
            outlineMaterial.blendMode = .add
            outlineMaterial.writesToDepthBuffer = false
            outlineMaterial.isDoubleSided = true
            outline.materials = [outlineMaterial]
            let neon = flat(outline, y: 0.02)
            holder.addChildNode(neon)
            if spotSlot == mySlot {
                neon.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.35, duration: 0.7), .fadeOpacity(to: 1.0, duration: 0.7)])))
                myNeon = neon
            } else {
                neon.opacity = 0.5
            }
            levelRoot.addChildNode(holder)

            if level.city != nil {
                let beam = SCNCylinder(radius: 1.4, height: 40)
                beam.radialSegmentCount = 12
                let beamMaterial = SCNMaterial()
                beamMaterial.lightingModel = .constant
                beamMaterial.diffuse.contents = color.withAlphaComponent(spotSlot == mySlot ? 0.35 : 0.18)
                beamMaterial.blendMode = .add
                beamMaterial.writesToDepthBuffer = false
                beamMaterial.isDoubleSided = true
                beam.materials = [beamMaterial]
                let beamNode = SCNNode(geometry: beam)
                beamNode.position = World3D.vec(def.center, y: 20)
                levelRoot.addChildNode(beamNode)
            }
            if spotSlot == mySlot {
                let pyramid = SCNPyramid(width: 1.3, height: 1.5, length: 1.3)
                pyramid.materials = [Mat.glow(color.lighter(by: 0.2))]
                let arrow = SCNNode(geometry: pyramid)
                arrow.eulerAngles.x = Float.pi
                let arrowHolder = SCNNode()
                arrowHolder.position = World3D.vec(def.center, y: level.city != nil ? 6.5 : 4.6)
                if level.city != nil { arrowHolder.scale = SCNVector3(1.8, 1.8, 1.8) }
                arrowHolder.addChildNode(arrow)
                arrowHolder.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.8, z: 0, duration: 0.45),
                                                                 .moveBy(x: 0, y: -0.8, z: 0, duration: 0.45)])))
                arrowHolder.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 2.5)))
                levelRoot.addChildNode(arrowHolder)
                arrowNode = arrowHolder
            }
        }

        let concrete = Mat.pbr(UIColor(red: 0.74, green: 0.74, blue: 0.77, alpha: 1), rough: 0.85)
        let coneOrange = Mat.pbr(UIColor(red: 1.0, green: 0.42, blue: 0.08, alpha: 1), rough: 0.5)
        let coneWhite = Mat.pbr(UIColor(white: 0.95, alpha: 1), rough: 0.5)
        let coneBase = Mat.pbr(UIColor(white: 0.1, alpha: 1), rough: 0.8)

        let parkedCars = SCNNode()
        var roofCache: [Int: SCNMaterial] = [:]
        // Optimized: all buildings become one geometry with one facade/roof material per color
        let buildingsRoot = SCNNode()
        var facadeCache: [Int: SCNMaterial] = [:]
        var facadeRepeats: [ObjectIdentifier: (CGFloat, CGFloat, CGFloat)] = [:]
        defer {
            if PerfSettings.optimized {
                if let merged = GeometryMerger.merge(buildingsRoot, uvScale: { node, element in
                    guard let r = facadeRepeats[ObjectIdentifier(node)], element < 4 else { return SIMD2(1, 1) }
                    let span = element % 2 == 0 ? r.0 : r.1
                    return SIMD2(Float(max(1, (span / 4).rounded())), Float(max(1, (r.2 / 3.2).rounded())))
                }) {
                    levelRoot.addChildNode(SCNNode(geometry: merged))
                }
            } else {
                levelRoot.addChildNode(parkedCars.flattenedClone())
            }
        }
        for obstacle in level.obstacles {
            switch obstacle.kind {
            case .car:
                let car = Car3D(color: CarArt.parkedColors[obstacle.tint % CarArt.parkedColors.count],
                                style: CarStyle(rawValue: (obstacle.tint + Int(obstacle.center.x)) % 3) ?? .sedan,
                                parked: true)
                car.update(position: obstacle.center, heading: obstacle.angle, steer: 0)
                if PerfSettings.optimized {
                    levelRoot.addChildNode(car.node)
                } else {
                    parkedCars.addChildNode(car.node)
                }
            case .building:
                let height = obstacle.height
                let width = obstacle.size.width / 10
                let length = obstacle.size.height / 10
                let box = SCNBox(width: width, height: height, length: length, chamferRadius: 0)
                if PerfSettings.optimized {
                    let facade: SCNMaterial
                    if let cached = facadeCache[obstacle.tint] {
                        facade = cached
                    } else {
                        facade = Mat.lambert(CarArt.facadeImage(tint: obstacle.tint))
                        facade.diffuse.wrapS = .repeat
                        facade.diffuse.wrapT = .repeat
                        facadeCache[obstacle.tint] = facade
                    }
                    let roof: SCNMaterial
                    if let cached = roofCache[obstacle.tint] {
                        roof = cached
                    } else {
                        roof = Mat.lambert(CarArt.buildingColors[obstacle.tint % CarArt.buildingColors.count].darker(by: 0.3))
                        roofCache[obstacle.tint] = roof
                    }
                    box.materials = [facade, facade, facade, facade, roof, roof]
                    let node = SCNNode(geometry: box)
                    node.position = World3D.vec(obstacle.center, y: height / 2)
                    node.eulerAngles.y = Float(obstacle.angle)
                    facadeRepeats[ObjectIdentifier(node)] = (width, length, height)
                    buildingsRoot.addChildNode(node)
                    continue
                }
                func facade(_ span: CGFloat) -> SCNMaterial {
                    let material = Mat.lambert(CarArt.facadeImage(tint: obstacle.tint))
                    material.diffuse.wrapS = .repeat
                    material.diffuse.wrapT = .repeat
                    material.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(max(1, (span / 4).rounded())),
                                                                             Float(max(1, (height / 3.2).rounded())), 1)
                    return material
                }
                let roof: SCNMaterial
                if let cached = roofCache[obstacle.tint] {
                    roof = cached
                } else {
                    roof = Mat.lambert(CarArt.buildingColors[obstacle.tint % CarArt.buildingColors.count].darker(by: 0.3))
                    roofCache[obstacle.tint] = roof
                }
                box.materials = [facade(width), facade(length), facade(width), facade(length), roof, roof]
                let node = SCNNode(geometry: box)
                node.position = World3D.vec(obstacle.center, y: height / 2)
                node.eulerAngles.y = Float(obstacle.angle)
                levelRoot.addChildNode(node)
            case .wall:
                let geometry = SCNBox(width: obstacle.size.width / 10, height: 1.1,
                                      length: obstacle.size.height / 10, chamferRadius: 0.06)
                geometry.chamferSegmentCount = 1
                let top = Mat.lambert(CarArt.wallImage(size: obstacle.size))
                geometry.materials = [concrete, concrete, concrete, concrete, top, concrete]
                let node = SCNNode(geometry: geometry)
                node.position = World3D.vec(obstacle.center, y: 0.55)
                node.eulerAngles.y = Float(obstacle.angle)
                levelRoot.addChildNode(node)
            case .cone:
                let holder = SCNNode()
                holder.position = World3D.vec(obstacle.center)
                let base = SCNBox(width: 1.0, height: 0.08, length: 1.0, chamferRadius: 0.05)
                base.materials = [coneBase]
                let baseNode = SCNNode(geometry: base)
                baseNode.position.y = 0.04
                holder.addChildNode(baseNode)
                let body = SCNCone(topRadius: 0.06, bottomRadius: 0.4, height: 1.0)
                body.radialSegmentCount = 8
                body.materials = [coneOrange]
                let bodyNode = SCNNode(geometry: body)
                bodyNode.position.y = 0.58
                holder.addChildNode(bodyNode)
                let band = SCNCone(topRadius: 0.2, bottomRadius: 0.26, height: 0.16)
                band.radialSegmentCount = 8
                band.materials = [coneWhite]
                let bandNode = SCNNode(geometry: band)
                bandNode.position.y = 0.66
                holder.addChildNode(bandNode)
                levelRoot.addChildNode(holder)
            }
        }
    }

    /// Checkered finish line across the street with two posts, a banner and a light beam.
    private func buildFinish(_ def: SpotDef) {
        let holder = SCNNode()
        holder.position = World3D.vec(def.center)
        holder.eulerAngles.y = Float(def.angle)
        let checker = CarArt.checkerImage()
        let across = def.size.height / 10

        let strip = SCNPlane(width: 3, height: across)
        let stripMaterial = Mat.lambert(checker)
        stripMaterial.diffuse.wrapS = .repeat
        stripMaterial.diffuse.wrapT = .repeat
        stripMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(0.5, Float(across / 6), 1)
        strip.materials = [stripMaterial]
        holder.addChildNode(flat(strip, y: 0.06))

        let pole = SCNCylinder(radius: 0.25, height: 6.5)
        pole.radialSegmentCount = 8
        pole.materials = [Mat.pbr(UIColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1), rough: 0.5)]
        for side: Float in [-1, 1] {
            let node = SCNNode(geometry: pole)
            node.position = SCNVector3(0, 3.25, side * Float(across / 2 + 0.6))
            holder.addChildNode(node)
        }
        let banner = SCNBox(width: 0.4, height: 1.5, length: across + 1.6, chamferRadius: 0.05)
        let bannerMaterial = Mat.lambert(checker)
        bannerMaterial.diffuse.wrapS = .repeat
        bannerMaterial.diffuse.wrapT = .repeat
        bannerMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(Float((across + 1.6) / 3), 0.5, 1)
        banner.materials = [bannerMaterial]
        let bannerNode = SCNNode(geometry: banner)
        bannerNode.position = SCNVector3(0, 6.2, 0)
        holder.addChildNode(bannerNode)

        let beam = SCNCylinder(radius: 2.0, height: 50)
        beam.radialSegmentCount = 12
        let beamMaterial = SCNMaterial()
        beamMaterial.lightingModel = .constant
        beamMaterial.diffuse.contents = UIColor(red: 1.0, green: 0.82, blue: 0.2, alpha: 0.3)
        beamMaterial.blendMode = .add
        beamMaterial.writesToDepthBuffer = false
        beamMaterial.isDoubleSided = true
        beam.materials = [beamMaterial]
        let beamNode = SCNNode(geometry: beam)
        beamNode.position = SCNVector3(0, 25, 0)
        holder.addChildNode(beamNode)
        levelRoot.addChildNode(holder)
    }

    /// Streets, intersections, sidewalks and edge barriers for a city level.
    private func buildCity(_ city: CityMap, world: CGSize) {
        let roadTexture = CarArt.roadImage()
        let roadWidth = CityMap.roadHalf * 2
        func roadMaterial(length: CGFloat) -> SCNMaterial {
            let material = Mat.lambert(roadTexture)
            material.diffuse.wrapS = .repeat
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(length / roadWidth), 1, 1)
            return material
        }
        let ground = SCNNode()
        for y in city.ys {
            let plane = SCNPlane(width: world.width / 10, height: roadWidth / 10)
            plane.materials = [roadMaterial(length: world.width)]
            let node = flat(plane, y: 0.01)
            let center = World3D.vec(CGPoint(x: world.width / 2, y: y))
            node.position.x = center.x
            node.position.z = center.z
            ground.addChildNode(node)
        }
        for x in city.xs {
            let plane = SCNPlane(width: world.height / 10, height: roadWidth / 10)
            plane.materials = [roadMaterial(length: world.height)]
            let holder = SCNNode()
            holder.position = World3D.vec(CGPoint(x: x, y: world.height / 2), y: 0.02)
            holder.eulerAngles.y = Float.pi / 2
            holder.addChildNode(flat(plane, y: 0))
            ground.addChildNode(holder)
        }
        let junction = SCNPlane(width: roadWidth / 10, height: roadWidth / 10)
        junction.materials = [Mat.lambert(UIColor(red: 0.27, green: 0.28, blue: 0.31, alpha: 1))]
        let stripe = SCNPlane(width: 0.5, height: 3.2)
        stripe.materials = [Mat.lambert(UIColor(white: 0.93, alpha: 1))]
        for x in city.xs {
            for y in city.ys {
                let node = flat(junction, y: 0.03)
                let p = World3D.vec(CGPoint(x: x, y: y))
                node.position.x = p.x
                node.position.z = p.z
                ground.addChildNode(node)
                // Zebra crossings on all four sides
                for side in 0..<4 {
                    let angle = Float(side) * Float.pi / 2
                    for k in -6...6 {
                        let along = Float(k) * 0.95
                        let out: Float = 11.4
                        let holder = SCNNode()
                        holder.position = SCNVector3(p.x + cos(angle) * out - sin(angle) * along, 0,
                                                     p.z + sin(angle) * out + cos(angle) * along)
                        holder.eulerAngles.y = -angle + Float.pi / 2
                        holder.addChildNode(flat(stripe, y: 0.04))
                        ground.addChildNode(holder)
                    }
                }
            }
        }
        // Sidewalks / plazas on each block
        let sidewalk = Mat.lambert(UIColor(red: 0.74, green: 0.73, blue: 0.70, alpha: 1))
        let lawn = Mat.lambert(UIColor(red: 0.42, green: 0.62, blue: 0.36, alpha: 1))
        for block in city.blocks {
            let plane = SCNPlane(width: block.width / 10, height: block.height / 10)
            plane.materials = [sidewalk]
            let node = flat(plane, y: 0.08)
            let p = World3D.vec(CGPoint(x: block.midX, y: block.midY))
            node.position.x = p.x
            node.position.z = p.z
            ground.addChildNode(node)
            let inner = SCNPlane(width: block.width / 10 - 3, height: block.height / 10 - 3)
            inner.materials = [lawn]
            let innerNode = flat(inner, y: 0.09)
            innerNode.position.x = p.x
            innerNode.position.z = p.z
            ground.addChildNode(innerNode)
        }
        // Low barriers around the map edge
        let barrier = Mat.pbr(UIColor(red: 0.85, green: 0.85, blue: 0.86, alpha: 1), rough: 0.8)
        let edges: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: world.width / 2, y: -4), world.width + 16, 8),
            (CGPoint(x: world.width / 2, y: world.height + 4), world.width + 16, 8),
            (CGPoint(x: -4, y: world.height / 2), 8, world.height + 16),
            (CGPoint(x: world.width + 4, y: world.height / 2), 8, world.height + 16)
        ]
        for edge in edges {
            let box = SCNBox(width: edge.1 / 10, height: 0.9, length: edge.2 / 10, chamferRadius: 0.1)
            box.materials = [barrier]
            let node = SCNNode(geometry: box)
            node.position = World3D.vec(edge.0, y: 0.45)
            ground.addChildNode(node)
        }
        levelRoot.addChildNode(ground.flattenedClone())
    }

    /// Menu backdrop: a level with both cars parked and a camera slowly circling the lot.
    func setupShowcase() {
        let level = Levels.all[2]
        load(level: level, spotSlots: [0, 1], mySlot: 0)
        arrowNode?.isHidden = true
        for slot in 0..<2 {
            let car = makeCar(color: CarArt.playerColors[slot], style: .racer)
            let spot = level.spots[slot]
            car.update(position: spot.center, heading: spot.angle, steer: 0)
        }
        let pivot = SCNNode()
        scene.rootNode.addChildNode(pivot)
        cameraNode.removeFromParentNode()
        pivot.addChildNode(cameraNode)
        cameraNode.simdPosition = SIMD3<Float>(0, 24, 44)
        cameraNode.simdLook(at: SIMD3<Float>(0, 0, 2), up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
        pivot.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 120)))
    }

    func markParked() {
        arrowNode?.isHidden = true
        myNeon?.removeAllActions()
        myNeon?.opacity = 1
        if let material = myNeon?.geometry?.firstMaterial {
            material.multiply.contents = UIColor(red: 0.5, green: 1.0, blue: 0.6, alpha: 1)
        }
    }

    func addSkid(at point: CGPoint) {
        let mark = SCNNode(geometry: skidGeometry)
        mark.eulerAngles.x = -Float.pi / 2
        mark.position = World3D.vec(point, y: 0.015)
        fxRoot.addChildNode(mark)
        mark.runAction(.sequence([.wait(duration: 3), .fadeOut(duration: 2), .removeFromParentNode()]))
    }
}

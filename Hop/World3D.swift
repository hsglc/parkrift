import SceneKit
import UIKit

// MARK: - Materials

enum Mat {
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
enum CarShapes {
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

    static func racerBodyPath() -> UIBezierPath {
        let path = UIBezierPath()
        let bottom: CGFloat = 0.28
        let arch: CGFloat = 0.48
        path.move(to: CGPoint(x: 2.2, y: bottom))
        path.addLine(to: CGPoint(x: 1.35 + arch, y: bottom))
        path.addArc(withCenter: CGPoint(x: 1.35, y: 0.38), radius: arch, startAngle: -0.2, endAngle: CGFloat.pi + 0.2, clockwise: true)
        path.addLine(to: CGPoint(x: -1.35 + arch, y: bottom))
        path.addArc(withCenter: CGPoint(x: -1.35, y: 0.38), radius: arch, startAngle: -0.2, endAngle: CGFloat.pi + 0.2, clockwise: true)
        path.addLine(to: CGPoint(x: -2.15, y: bottom))
        path.addQuadCurve(to: CGPoint(x: -2.28, y: 0.62), controlPoint: CGPoint(x: -2.3, y: 0.3))
        path.addQuadCurve(to: CGPoint(x: -2.1, y: 0.92), controlPoint: CGPoint(x: -2.3, y: 0.88))
        path.addLine(to: CGPoint(x: -1.65, y: 0.87))
        path.addCurve(to: CGPoint(x: 0.95, y: 0.8), controlPoint1: CGPoint(x: -0.6, y: 0.9), controlPoint2: CGPoint(x: 0.4, y: 0.86))
        path.addCurve(to: CGPoint(x: 2.25, y: 0.42), controlPoint1: CGPoint(x: 1.6, y: 0.76), controlPoint2: CGPoint(x: 2.2, y: 0.62))
        path.addQuadCurve(to: CGPoint(x: 2.2, y: bottom), controlPoint: CGPoint(x: 2.32, y: 0.32))
        path.close()
        path.flatness = 0.01
        return path
    }

    static func racerCanopyPath() -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -1.6, y: 0.84))
        path.addCurve(to: CGPoint(x: -0.2, y: 1.22), controlPoint1: CGPoint(x: -1.3, y: 1.05), controlPoint2: CGPoint(x: -0.75, y: 1.22))
        path.addLine(to: CGPoint(x: 0.25, y: 1.21))
        path.addCurve(to: CGPoint(x: 1.2, y: 0.78), controlPoint1: CGPoint(x: 0.65, y: 1.18), controlPoint2: CGPoint(x: 0.95, y: 0.95))
        path.close()
        path.flatness = 0.01
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
            // Modern supercar: smooth wedge with a ducktail and a low teardrop canopy
            return Profile(body: racerBodyPath(), cabin: racerCanopyPath(), window: racerCanopyPath(),
                           windshield: (CGPoint(x: 0.25, y: 1.21), CGPoint(x: 1.2, y: 0.8)),
                           rearWindow: (CGPoint(x: -1.6, y: 0.86), CGPoint(x: -0.2, y: 1.22)), roofHeight: 1.22)
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
        let cabin = SCNShape(path: p.cabin, extrusionDepth: style == .racer ? 1.55 : 1.7)
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
    static let led = Mat.glow(UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 1))
    static let graphite = Mat.pbr(UIColor(white: 0.16, alpha: 1), metal: 0.8, rough: 0.3)
    static let canopy: SCNMaterial = {
        let material = Mat.pbr(UIColor(red: 0.04, green: 0.06, blue: 0.1, alpha: 1), metal: 0.9, rough: 0.05)
        material.clearCoat.contents = NSNumber(value: 1.0)
        material.clearCoatRoughness.contents = NSNumber(value: 0.02)
        return material
    }()

    /// Big five-spoke wheel with a low-profile tyre for the players' cars.
    static let racerWheel: SCNNode = {
        let holder = SCNNode()
        let tyre = SCNCylinder(radius: 0.39, height: 0.3)
        tyre.radialSegmentCount = 24
        tyre.materials = [Mat.pbr(UIColor(white: 0.05, alpha: 1), metal: 0, rough: 0.85)]
        let rim = SCNCylinder(radius: 0.31, height: 0.31)
        rim.radialSegmentCount = 24
        rim.materials = [graphite]
        for geometry in [tyre, rim] {
            let part = SCNNode(geometry: geometry)
            part.eulerAngles.x = Float.pi / 2
            holder.addChildNode(part)
        }
        let spoke = SCNBox(width: 0.07, height: 0.29, length: 0.33, chamferRadius: 0.02)
        spoke.materials = [chrome]
        for k in 0..<5 {
            let node = SCNNode(geometry: spoke)
            let angle = Float(k) * 2 * Float.pi / 5
            node.eulerAngles.z = angle
            node.position = SCNVector3(-sin(angle) * 0.145, cos(angle) * 0.145, 0)
            holder.addChildNode(node)
        }
        let cap = SCNCylinder(radius: 0.06, height: 0.34)
        cap.radialSegmentCount = 10
        cap.materials = [chrome]
        let capNode = SCNNode(geometry: cap)
        capNode.eulerAngles.x = Float.pi / 2
        holder.addChildNode(capNode)
        let flat = holder.flattenedClone()
        flat.castsShadow = false
        return flat
    }()
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

    /// Additive material for glowing effects (HDR intensity lets bloom pick it up).
    static func additive(_ contents: Any, intensity: CGFloat = 1.6, tint: UIColor? = nil) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = contents
        material.diffuse.intensity = intensity
        if let tint = tint { material.multiply.contents = tint }
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.isDoubleSided = true
        return material
    }

    static let flamePlane: SCNGeometry = {
        let plane = SCNPlane(width: 1.7, height: 0.42)
        plane.materials = [additive(CarArt.flameImage, intensity: 2.2)]
        return plane
    }()
    static let glowSprite: SCNGeometry = {
        let plane = SCNPlane(width: 1, height: 1)
        plane.materials = [additive(CarArt.glowParticle(), intensity: 2.0, tint: UIColor(red: 0.45, green: 0.8, blue: 1.0, alpha: 1))]
        return plane
    }()
    static let groundGlow: SCNGeometry = {
        let plane = SCNPlane(width: 3.4, height: 2.2)
        plane.materials = [additive(CarArt.glowParticle(), intensity: 1.2, tint: UIColor(red: 0.2, green: 0.55, blue: 1.0, alpha: 1))]
        return plane
    }()

    /// One exhaust flame: two crossed textured planes, a hot glow at the nozzle and three shock
    /// diamonds. Pointing along -x from the node's origin.
    static func makeFlame() -> (root: SCNNode, diamonds: [SCNNode]) {
        let root = SCNNode()
        for angle: Float in [0, Float.pi / 2] {
            let plane = SCNNode(geometry: flamePlane)
            plane.position = SCNVector3(-0.85, 0, 0)
            plane.eulerAngles.x = angle
            plane.castsShadow = false
            root.addChildNode(plane)
        }
        let billboard = SCNBillboardConstraint()
        let core = SCNNode(geometry: glowSprite)
        core.scale = SCNVector3(0.75, 0.75, 0.75)
        core.constraints = [billboard]
        core.castsShadow = false
        root.addChildNode(core)
        var diamonds: [SCNNode] = []
        for (k, x) in [Float(-0.35), -0.7, -1.05].enumerated() {
            let diamond = SCNNode(geometry: glowSprite)
            let size = 0.26 - Float(k) * 0.05
            diamond.scale = SCNVector3(size, size, size)
            diamond.position = SCNVector3(x, 0, 0)
            diamond.constraints = [billboard]
            diamond.castsShadow = false
            root.addChildNode(diamond)
            diamonds.append(diamond)
        }
        return (root, diamonds)
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
enum CarFactory {
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

        if style == .racer {
            // Body, glossy blacked-out canopy and a body-colored roof band
            add(shapes.body, paint, at: SCNVector3(0, 0, 0), to: parts)
            add(shapes.cabin, CarShapes.canopy, at: SCNVector3(0, -0.01, 0), to: parts)
            let roof = SCNShape(path: CarShapes.racerCanopyPath(), extrusionDepth: 0.6)
            roof.chamferRadius = 0.03
            let roofNode = SCNNode()
            add(roof, paint, at: SCNVector3(0, 0, 0), to: roofNode)
            roofNode.scale = SCNVector3(0.97, 1.012, 1)
            roofNode.position = SCNVector3(0.0, -0.006, 0)
            parts.addChildNode(roofNode)
            // Twin stripes over the nose and tail
            let stripes = CarShapes.stripes()
            for z: Float in [0.17, -0.17] {
                let stripeNode = SCNNode()
                add(stripes.body, CarShapes.stripe, at: SCNVector3(0, 0, 0), to: stripeNode)
                stripeNode.scale = SCNVector3(1.003, 1.01, 1)
                stripeNode.position = SCNVector3(0, -0.003, z)
                parts.addChildNode(stripeNode)
            }
            // Full-width LED light bar and angled LED eyes
            box(0.04, 0.035, 1.5, 0.015, CarShapes.led, at: SCNVector3(2.22, 0.4, 0), to: parts)
            for z: Float in [0.62, -0.62] {
                box(0.34, 0.045, 0.34, 0.02, CarShapes.led, at: SCNVector3(2.02, 0.56, z), rotationZ: -0.3, to: parts)
                // Mirrors on thin stalks
                box(0.2, 0.08, 0.14, 0.035, paint, at: SCNVector3(0.92, 0.94, z * 1.5), to: parts)
                box(0.05, 0.12, 0.05, 0.01, CarShapes.carbon, at: SCNVector3(0.92, 0.87, z * 1.4), to: parts)
            }
            // Aero: splitter, diffuser with fins, ducktail lip, side intakes, accent line
            box(0.34, 0.04, 2.0, 0.015, CarShapes.carbon, at: SCNVector3(2.12, 0.27, 0), to: parts)
            box(0.32, 0.12, 1.7, 0.02, CarShapes.carbon, at: SCNVector3(-2.14, 0.31, 0), to: parts)
            for z: Float in [-0.5, -0.17, 0.17, 0.5] {
                box(0.34, 0.14, 0.03, 0.005, CarShapes.carbon, at: SCNVector3(-2.17, 0.31, z), to: parts)
            }
            box(0.34, 0.04, 1.9, 0.015, CarShapes.carbon, at: SCNVector3(-2.06, 0.93, 0), rotationZ: 0.18, to: parts)
            for z: Float in [1.0, -1.0] {
                box(0.62, 0.17, 0.05, 0.03, CarShapes.carbon, at: SCNVector3(-0.75, 0.56, z), to: parts)
                box(3.0, 0.022, 0.02, 0.005, CarShapes.stripe, at: SCNVector3(0.15, 0.46, z * 1.004), to: parts)
            }
            // Center exhaust pair inside the diffuser
            let pipe = SCNCylinder(radius: 0.065, height: 0.22)
            pipe.radialSegmentCount = 12
            pipe.materials = [CarShapes.chrome]
            for z: Float in [0.24, -0.24] {
                let pipeNode = SCNNode(geometry: pipe)
                pipeNode.eulerAngles.z = Float.pi / 2
                pipeNode.position = SCNVector3(-2.22, 0.33, z)
                parts.addChildNode(pipeNode)
            }
            return parts
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

    static func tailY(_ style: CarStyle) -> Float {
        switch style {
        case .suv: return 0.88
        case .racer: return 0.74
        default: return 0.8
        }
    }

    private static var racerPaints: [String: SCNMaterial] = [:]
    /// Metallic paint with a clear coat for the players' cars.
    static func racerPaint(_ color: UIColor) -> SCNMaterial {
        let key = colorKey(color)
        if let cached = racerPaints[key] { return cached }
        let paint = Mat.pbr(color, metal: 0.4, rough: 0.34)
        paint.clearCoat.contents = NSNumber(value: 0.6)
        paint.clearCoatRoughness.contents = NSNumber(value: 0.12)
        racerPaints[key] = paint
        return paint
    }

    /// Flattens a node tree with SceneKit (which resolves its own primitives correctly).
    static func flattened(_ node: SCNNode) -> SCNNode {
        node.flattenedClone()
    }

    /// Tyre + rim + hubcap as one flattened node, hidden beyond the detail distance.
    static let wheelTemplate: SCNNode = {
        let holder = SCNNode()
        for geometry in [CarShapes.tyre, CarShapes.rim, CarShapes.hubcap] {
            let part = SCNNode(geometry: geometry)
            part.eulerAngles.x = Float.pi / 2
            holder.addChildNode(part)
        }
        let flat = flattened(holder)
        flat.castsShadow = false
        return flat
    }()

    /// Simple far-away car: body block, dark cabin and wheel blocks (vertex data written directly;
    /// SceneKit needs a real mesh for a level of detail).
    private static func lowDetail(style: CarStyle, paint: SCNMaterial) -> SCNGeometry? {
        let mesh = MeshBuilder()
        let profile = CarShapes.profile(style)
        let bodyTop: Float = style == .racer ? 0.8 : (style == .suv ? 1.1 : 0.98)
        mesh.addBox(center: SIMD3(0, 0.28, 0), width: 4.3, height: bodyTop - 0.28, length: 2.0, angle: 0,
                    wall: paint, roof: paint, wallRepeats: { _ in SIMD2(1, 1) })
        let cabinLength = Float(abs(profile.windshield.1.x - profile.rearWindow.0.x)) * 0.8
        let cabinX = Float((profile.windshield.1.x + profile.rearWindow.0.x) / 2)
        mesh.addBox(center: SIMD3(cabinX, bodyTop, 0), width: cabinLength, height: Float(profile.roofHeight) - bodyTop,
                    length: style == .racer ? 1.5 : 1.7, angle: 0,
                    wall: CarShapes.glass, roof: paint, wallRepeats: { _ in SIMD2(1, 1) })
        for spot in wheelSpots {
            mesh.addBox(center: SIMD3(spot.0, 0.03, spot.1), width: 0.7, height: 0.6, length: 0.28, angle: 0,
                        wall: CarShapes.trim, roof: CarShapes.trim, wallRepeats: { _ in SIMD2(1, 1) })
        }
        return mesh.build()
    }

    private static var bodies: [String: SCNNode] = [:]
    private static var lowTemplates: [String: SCNNode] = [:]

    /// Simple far-away version for the same style and color (built with `body`).
    static func lowBody(style: CarStyle, color: UIColor, parked: Bool) -> SCNNode? {
        lowTemplates["\(style.rawValue)-\(colorKey(color))-\(parked)"]
    }

    /// Every cached geometry including far-distance versions, for warming up the GPU.
    static var allGeometries: [SCNGeometry] {
        var result: [SCNGeometry] = [CarShapes.flameOuter, CarShapes.flameInner]
        if let wheel = wheelTemplate.geometry { result.append(wheel) }
        for template in bodies.values {
            if let geometry = template.geometry { result.append(geometry) }
        }
        for template in lowTemplates.values {
            if let geometry = template.geometry { result.append(geometry) }
        }
        return result
    }

    /// Merged static geometry for a moving car (lights and wheels are separate) or a parked car
    /// (everything baked in).
    static func body(style: CarStyle, color: UIColor, parked: Bool) -> SCNNode {
        let key = "\(style.rawValue)-\(colorKey(color))-\(parked)"
        if let cached = bodies[key] { return cached }
        let paintMaterial = style == .racer ? racerPaint(color) : paint(color)
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
        let template = flattened(parts)
        bodies[key] = template
        if lowTemplates[key] == nil, let low = lowDetail(style: style, paint: paintMaterial) {
            lowTemplates[key] = SCNNode(geometry: low)
        }
        return template
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
    private var flameDiamonds: [SCNNode] = []
    private var boostGlow: SCNNode?
    private var flameClock: Float = 0
    private var nitroOn = false
    private var lastBraking: Bool?
    private var lastReversing: Bool?
    /// Wheels and lights, hidden for far-away traffic.
    private var detailNodes: [SCNNode] = []
    private var detailVisible = true
    private var lowNode: SCNNode?

    /// `parked`: a car that never moves (wheels and lights baked into one geometry).
    /// Wheel radius used for the rolling animation.
    private var wheelRadius: CGFloat = 0.37
    /// Body meshes that carry the paint (model cars only), for repainting in the garage.
    private var paintedNode: SCNNode?
    private var texturedNode: SCNNode?

    private var headlight: SCNNode?

    /// Headlight beam for the night (one spot light on the player's car).
    func setHeadlights(_ on: Bool) {
        if on, headlight == nil {
            let light = SCNLight()
            light.type = .spot
            light.intensity = 2200
            light.color = UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1)
            light.spotInnerAngle = 25
            light.spotOuterAngle = 62
            light.attenuationStartDistance = 4
            light.attenuationEndDistance = 38
            light.castsShadow = false
            // Spot lights shine along -z: a holder turns it to +x (forward), the light tips down
            let beam = SCNNode()
            beam.position = SCNVector3(1.9, 0.75, 0)
            beam.eulerAngles.y = -Float.pi / 2
            let tilt = SCNNode()
            tilt.light = light
            tilt.eulerAngles.x = -0.18
            beam.addChildNode(tilt)
            node.addChildNode(beam)
            headlight = beam
        }
        headlight?.isHidden = !on
    }

    /// Water spray behind the rear wheels in the rain; `amount` 0...1 follows the speed.
    private var sprays: [SCNParticleSystem] = []
    func setSpray(_ amount: CGFloat) {
        if sprays.isEmpty {
            guard amount > 0 else { return }
            for side: Float in [-0.82, 0.82] {
                let emitter = SCNNode()
                emitter.position = SCNVector3(-1.55, 0.12, side)
                let system = World3D.makeSpray()
                emitter.addParticleSystem(system)
                node.addChildNode(emitter)
                sprays.append(system)
            }
        }
        for system in sprays { system.birthRate = 160 * max(0, min(1, amount)) }
    }

    /// Rim colour: the wheels get their own rim and tyre materials (one per car).
    private var rimMaterial: SCNMaterial?
    private var tireMaterial: SCNMaterial?
    private var rimTint = CarSpec.rims[0]
    private var paintColor = UIColor.red
    /// Meshy cars: whether the big textures are on (garage cars that are not shown drop them).
    private var texturesLoaded = true

    func setRim(_ color: UIColor) {
        rimTint = color
        ensureWheelMaterials()
        applyRimTint()
    }

    private func ensureWheelMaterials() {
        guard rimMaterial == nil else { return }
        let rim = CarModels.rim.copy() as! SCNMaterial
        let tire = CarModels.tire.copy() as! SCNMaterial
        rimMaterial = rim
        tireMaterial = tire
        for spinner in spinNodes {
            spinner.enumerateHierarchy { node, _ in
                guard let name = node.name, name == "rim" || name == "tire",
                      let geometry = node.geometry?.copy() as? SCNGeometry else { return }
                geometry.materials = [name == "rim" ? rim : tire]
                node.geometry = geometry
            }
        }
        if let spec = carSpec, spec.textureNormal != nil {
            CarModels.setWheelMaps(spec, on: rim, loaded: texturesLoaded, solid: rimTint)
            CarModels.setWheelMaps(spec, on: tire, loaded: texturesLoaded, solid: UIColor(white: 0.07, alpha: 1))
        }
    }

    private func applyRimTint() {
        guard let rim = rimMaterial else { return }
        if texturesLoaded, carSpec?.textureNormal != nil {
            // Meshy rims keep their texture: the colour tints it (the standard silver leaves it as is)
            rim.multiply.contents = rimTint == CarSpec.rims[0] ? UIColor.white : rimTint.lighter(by: 0.15)
        } else {
            rim.multiply.contents = UIColor.white
            rim.diffuse.contents = rimTint
        }
    }

    /// Loads or drops the car's big textures (body and wheels). A garage car that is not on the
    /// platform keeps none, so six 4K cars never sit in memory at once.
    func setTexturesLoaded(_ loaded: Bool) {
        guard let spec = carSpec, spec.textureNormal != nil, loaded != texturesLoaded else { return }
        texturesLoaded = loaded
        texturedNode?.geometry?.materials = [loaded ? CarModels.texturePaint(spec, paintColor) : CarModels.placeholder]
        ensureWheelMaterials()
        if let rim = rimMaterial, let tire = tireMaterial {
            CarModels.setWheelMaps(spec, on: rim, loaded: loaded, solid: rimTint)
            CarModels.setWheelMaps(spec, on: tire, loaded: loaded, solid: UIColor(white: 0.07, alpha: 1))
        }
        applyRimTint()
    }

    /// Swaps the paint material only (no new geometry, no new shader).
    func setPaint(_ color: UIColor) {
        paintColor = color
        paintedNode?.geometry?.materials = [CarFactory.racerPaint(color)]
        if let material = texturedNode?.geometry?.firstMaterial, carSpec?.textureBase != nil {
            CarModels.setPaint(material, color)
        }
    }
    private var carSpec: CarSpec?

    /// `model`: which garage car a player's racer uses.
    init(color: UIColor, style: CarStyle = .sedan, parked: Bool = false, model carModel: CarModelID = .italia,
         variety: Int = 0, vehicle forcedVehicle: String? = nil) {
        brakeMaterial = Mat.glow(UIColor(red: 0.55, green: 0.04, blue: 0.05, alpha: 1))
        // Thin tail light strips: lit from both sides whatever their winding
        brakeMaterial.isDoubleSided = true
        reverseMaterial = Mat.glow(UIColor(white: 0.35, alpha: 1))
        node.addChildNode(body)
        let model = style == .racer ? CarModels.body(carModel) : nil
        let spec = CarSpec.of(carModel)
        carSpec = spec
        paintColor = color

        // Traffic, parked and patrol cars: the Meshy traffic cars, each in a paint of its own
        if style != .racer, PerfSettings.optimized,
           let vehicle = forcedVehicle.flatMap({ TrafficVehicles.models[$0] }) ?? TrafficVehicles.pick(variety &* 31 &+ style.rawValue) {
            let paint = TrafficVehicles.paint(variety &* 7 &+ style.rawValue &* 131)
            if parked {
                if let template = TrafficVehicles.parked(vehicle, paint: paint) { body.addChildNode(template.clone()) }
                return
            }
            guard let template = TrafficVehicles.body(vehicle, paint: paint) else { return }
            let car = template.clone()
            // Its tail lamps glow when it brakes (a material of this car's own)
            if let tail = car.childNode(withName: "taillight", recursively: true) {
                tail.geometry = tail.geometry?.copy() as? SCNGeometry
                tail.geometry?.materials = [brakeMaterial]
            }
            body.addChildNode(car)
            if let wheelModel = TrafficVehicles.wheel(vehicle) {
                wheelRadius = CGFloat(vehicle.wheelRadius)
                for spot in vehicle.wheels {
                    let pivot = SCNNode()
                    pivot.position = SCNVector3(spot.0, spot.1, spot.2)
                    let spinner = SCNNode()
                    let wheel = wheelModel.clone()
                    if (spot.2 > 0) != (vehicle.wheelModelSide > 0) { wheel.eulerAngles.y = Float.pi }
                    spinner.addChildNode(wheel)
                    pivot.addChildNode(spinner)
                    node.addChildNode(pivot)
                    detailNodes.append(pivot)
                    spinNodes.append(spinner)
                    if spot.3 { steerPivots.append(pivot) }
                }
            }
            return
        }

        if let model = model {
            // Real car model: per-car paint and brake-light materials on copies of those meshes
            let car = model.clone()
            if let paintNode = car.childNode(withName: "paint", recursively: true) {
                paintNode.geometry = paintNode.geometry?.copy() as? SCNGeometry
                paintNode.geometry?.materials = [CarFactory.racerPaint(color)]
                paintedNode = paintNode
            }
            if let textured = car.childNode(withName: "textured", recursively: true)
                ?? car.childNode(withName: "kenney", recursively: true) {
                textured.geometry = textured.geometry?.copy() as? SCNGeometry
                textured.geometry?.materials = [CarModels.texturePaint(spec, color)]
                texturedNode = textured
            }
            if let tail = car.childNode(withName: "taillight", recursively: true) {
                tail.geometry = tail.geometry?.copy() as? SCNGeometry
                tail.geometry?.materials = [brakeMaterial]
            }
            body.addChildNode(car)
        } else if PerfSettings.optimized {
            // clone() shares the cached geometry with every car of this style and color
            let high = CarFactory.body(style: style, color: color, parked: parked).clone()
            body.addChildNode(high)
            detailNodes.append(high)
            if let low = CarFactory.lowBody(style: style, color: color, parked: parked)?.clone() {
                low.isHidden = true
                body.addChildNode(low)
                lowNode = low
            }
            if parked { return }
        } else {
            let paint = Mat.pbr(color, metal: 0.35, rough: 0.32)
            paint.fresnelExponent = 1.5
            body.addChildNode(CarFactory.buildParts(style: style, paint: paint).flattenedClone())
        }

        if style == .racer {
            let exhausts = model != nil ? spec.exhausts : [SCNVector3(-2.3, 0.33, 0.24), SCNVector3(-2.3, 0.33, -0.24)]
            for exhaust in exhausts {
                let made = CarShapes.makeFlame()
                let flame = made.root
                flame.position = exhaust
                // Kept in the scene but shrunk to nothing when off, so its shaders are compiled
                // with the level instead of on the first nitro
                flame.scale = SCNVector3(0.001, 0.001, 0.001)
                body.addChildNode(flame)
                flames.append(flame)
                flameDiamonds += made.diamonds
            }
            let glow = SCNNode(geometry: CarShapes.groundGlow)
            glow.eulerAngles.x = -Float.pi / 2
            glow.position = SCNVector3(-2.6, 0.05, 0)
            glow.scale = SCNVector3(0.001, 0.001, 0.001)
            glow.castsShadow = false
            node.addChildNode(glow)
            boostGlow = glow
        }

        // Lights that change at runtime stay separate
        let tailY = CarFactory.tailY(style)
        var lights: [SCNNode] = []
        if style == .racer {
            if model == nil {
                // One full-width LED brake bar
                lights.append(CarFactory.box(0.05, 0.06, 1.75, 0.02, brakeMaterial, at: SCNVector3(-2.27, tailY, 0), to: body))
                lights.append(CarFactory.box(0.05, 0.05, 0.3, 0.02, reverseMaterial, at: SCNVector3(-2.27, tailY - 0.11, 0), to: body))
            }
        } else {
            for z: Float in [0.66, -0.66] {
                lights.append(CarFactory.box(0.07, 0.12, 0.42, 0.03, brakeMaterial, at: SCNVector3(-2.2, tailY, z), to: body))
            }
            lights.append(CarFactory.box(0.06, 0.08, 0.26, 0.02, reverseMaterial, at: SCNVector3(-2.2, tailY - 0.14, 0), to: body))
        }
        if PerfSettings.optimized {
            for light in lights { light.castsShadow = false }
            detailNodes += lights
        }

        // Wheels: pivot (steering) -> spin (rolling) -> tyre + rim
        if model != nil, let wheelModel = CarModels.wheel(carModel) {
            wheelRadius = CGFloat(spec.wheelRadius)
            for spot in spec.wheelSpots {
                let pivot = SCNNode()
                pivot.position = SCNVector3(spot.0, spot.1, spot.2)
                let spinner = SCNNode()
                let wheel = wheelModel.clone()
                // The model is a wheel from one side; turn it around for the other side
                if (spot.2 > 0) != (spec.wheelModelSide > 0) { wheel.eulerAngles.y = Float.pi }
                spinner.addChildNode(wheel)
                pivot.addChildNode(spinner)
                node.addChildNode(pivot)
                detailNodes.append(pivot)
                spinNodes.append(spinner)
                if spot.3 { steerPivots.append(pivot) }
            }
            // Meshy tyres and rims with the car's own texture and maps
            if spec.textureNormal != nil { ensureWheelMaterials(); applyRimTint() }
            return
        }
        for spot in CarFactory.wheelSpots {
            let pivot = SCNNode()
            pivot.position = SCNVector3(spot.0, style == .racer ? 0.39 : 0.36, spot.1)
            let spinner = SCNNode()
            if style == .racer {
                spinner.addChildNode(CarShapes.racerWheel.clone())
            } else if PerfSettings.optimized {
                spinner.addChildNode(CarFactory.wheelTemplate.clone())
            } else {
                for geometry in [CarShapes.tyre, CarShapes.rim, CarShapes.hubcap] {
                    let part = SCNNode(geometry: geometry)
                    part.eulerAngles.x = Float.pi / 2
                    spinner.addChildNode(part)
                }
            }
            pivot.addChildNode(spinner)
            node.addChildNode(pivot)
            detailNodes.append(pivot)
            spinNodes.append(spinner)
            if spot.2 { steerPivots.append(pivot) }
        }
    }

    func update(position: CGPoint, heading: CGFloat, steer: CGFloat,
                pitch: CGFloat = 0, roll: CGFloat = 0, braking: Bool = false, reversing: Bool = false, lift: Float = 0) {
        node.position = World3D.vec(position)
        node.position.y = lift
        node.eulerAngles = SCNVector3(0, Float(heading), 0)
        for pivot in steerPivots { pivot.eulerAngles.y = Float(steer) }
        body.eulerAngles = SCNVector3(Float(roll), 0, Float(pitch))

        if let last = lastPosition {
            let dx = position.x - last.x
            let dy = position.y - last.y
            let travelled = (dx * cos(heading) + dy * sin(heading)) / 10   // meters
            spin -= travelled / wheelRadius
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
            flameClock += 1
            for flame in flames {
                let length = Float.random(in: 0.8...1.3)
                let width = Float.random(in: 0.88...1.12)
                flame.scale = SCNVector3(length, width, width)
            }
            for (k, diamond) in flameDiamonds.enumerated() {
                let pulse = 0.75 + 0.35 * sin(flameClock * 0.9 + Float(k) * 1.7)
                let base: Float = 0.26 - Float(k % 3) * 0.05
                diamond.scale = SCNVector3(base * pulse, base * pulse, base * pulse)
            }
            let flicker = Float.random(in: 0.85...1.1)
            boostGlow?.scale = SCNVector3(flicker, flicker, flicker)
        }
    }

    /// Shows or hides wheels and lights (far-away traffic only needs the simple body).
    /// Returns true when it changed.
    @discardableResult
    func setDetail(_ visible: Bool) -> Bool {
        guard PerfSettings.optimized, visible != detailVisible else { return false }
        detailVisible = visible
        for detail in detailNodes { detail.isHidden = !visible }
        lowNode?.isHidden = visible
        return true
    }

    /// Exhaust flames while the nitro burns.
    func setNitro(_ on: Bool) {
        guard on != nitroOn else { return }
        nitroOn = on
        let off = SCNVector3(0.001, 0.001, 0.001)
        for flame in flames { flame.scale = on ? SCNVector3(1, 1, 1) : off }
        boostGlow?.scale = on ? SCNVector3(1, 1, 1) : off
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
    /// The view drawing this world; used to upload geometry and compile shaders ahead of time.
    weak var renderer: SCNView?
    let cameraNode = SCNNode()
    private let levelRoot = SCNNode()
    private var parkedCars3D: [(car: Car3D, position: CGPoint)] = []
    /// Lit lamp of every traffic light head, moved between the red/yellow/green slots.
    private var signalHeads: [(node: Int, horizontal: Bool, lamp: SCNNode, slots: [SCNVector3], state: Int)] = []
    private var cityMap: CityMap?
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

        scene.background.contents = Scenery.daySky
        scene.fogColor = UIColor(red: 0.84, green: 0.90, blue: 0.97, alpha: 1)
        scene.fogStartDistance = 70
        scene.fogEndDistance = 200
        scene.lightingEnvironment.contents = Scenery.daySky
        scene.lightingEnvironment.intensity = 1.0
        buildLights()
        scene.rootNode.addChildNode(lotRoot)
        buildGround()
        buildScenery()
        scene.rootNode.addChildNode(levelRoot)
        scene.rootNode.addChildNode(fxRoot)
        // A tiny skid mark always in front of the camera: its material is then compiled with the
        // level, not on the first skid (which stalled the race around the first corner)
        let warmSkid = SCNNode(geometry: skidGeometry)
        warmSkid.scale = SCNVector3(0.001, 0.001, 0.001)
        warmSkid.position = SCNVector3(0, 0, -3)
        warmSkid.castsShadow = false
        cameraNode.addChildNode(warmSkid)

        let camera = SCNCamera()
        camera.fieldOfView = fieldOfView
        camera.projectionDirection = .vertical
        camera.zNear = 0.3
        camera.zFar = 260
        if PerfSettings.optimized {
            // Always-on post-processing (set once, never toggled, so no mid-game pipeline rebuilds):
            // HDR with bloom so LEDs, lamps and nitro flames glow, and a light color grade
            // (ambient occlusion was tried and dropped: about twice the render cost)
            camera.wantsHDR = true
            camera.wantsExposureAdaptation = false
            camera.exposureOffset = 0.15
            camera.bloomIntensity = 0.55
            camera.bloomThreshold = 0.85
            camera.bloomBlurRadius = 8
            camera.saturation = 1.1
            camera.contrast = 0.08
        }
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        follow(position: CGPoint(x: 500, y: 250), heading: 0, dt: 0, snap: true)
    }

    private let sunLight = SCNLight()
    private let ambientLight = SCNLight()
    /// The street materials, for the wet look in the rain.
    private var roadMaterials: [SCNMaterial] = []
    /// Warm light pools under the street lamps (shown at night).
    private var lampPools: SCNNode?
    private var rain: SCNNode?
    private var snow: SCNNode?
    /// The parking lot's ground materials (wet or snowy with the weather, like the streets).
    var lotMaterials: [SCNMaterial] = []
    private(set) var weather: Weather = .day

    private func buildLights() {
        let sun = sunLight
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

        let ambient = ambientLight
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
        // Paving all around (Poly Haven slabs), under the town that rings the lot
        let apronSize = CGSize(width: 400, height: 400)
        let apron = SCNPlane(width: apronSize.width, height: apronSize.height)
        let apronMaterial = Scenery.surface("pavement", tile: 2.5, size: apronSize, normal: 0.8)
        apron.materials = [apronMaterial]
        scene.rootNode.addChildNode(flat(apron, y: -0.06))

        // Asphalt lot: photo-scanned asphalt every 3.5 m, a large stain map over it breaks the repeat
        let lotSize = CGSize(width: 100, height: 50)
        let lot = SCNPlane(width: lotSize.width, height: lotSize.height)
        let lotMaterial = Scenery.surface("asphalt", tile: 3.5, size: lotSize)
        lotMaterial.multiply.contents = UIImage(named: "street_stains.jpg")
        lotMaterial.multiply.contentsTransform = SCNMatrix4MakeScale(2, 1, 1)
        lotMaterial.multiply.wrapS = .repeat
        lotMaterial.multiply.wrapT = .repeat
        lot.materials = [lotMaterial]
        lotMaterials = [lotMaterial, apronMaterial]
        lotRoot.addChildNode(flat(lot, y: 0))
        // The town round the lot (shared meshes, one copy per scene)
        lotRoot.addChildNode(CityDecor.lotSurroundings.clone())

        // Raised curbs
        let concrete = Scenery.shared("concrete", tile: 2, size: CGSize(width: 100, height: 1))
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
    private var cinematicShotB = false
    private var shotAEye = SIMD3<Float>(0, 0, 0)
    private var celebrationPoint = SCNVector3Zero

    /// Shot A: a low camera past the finish line watches the car come in (slow motion is applied by
    /// the game), with a shallow depth of field.
    func startFinishCinematic(at position: CGPoint, heading: CGFloat, finishLine: CGPoint) {
        cinematicActive = true
        cinematicShotB = false
        cinematicTime = 0
        orbitReach = 99
        let p = World3D.vec(position)
        let car = SIMD3<Float>(p.x, p.y, p.z)
        let forward = SIMD3<Float>(cos(Float(heading)), 0, -sin(Float(heading)))
        let side = SIMD3<Float>(sin(Float(heading)), 0, cos(Float(heading)))
        // The low pass shot from ahead of the car, on whichever side has a clear view: crossing the
        // line while turning used to put the camera behind a wall, so the shot began on a wall
        let candidates: [SIMD3<Float>] = [
            forward * 16 + side * 3.4, forward * 16 - side * 3.4,
            forward * 11 + side * 4.5, forward * 11 - side * 4.5,
            forward * 7 + side * 6, forward * 7 - side * 6,
            side * 8 + forward * 2, -side * 8 + forward * 2,
        ]
        let target = car + SIMD3<Float>(0, 0.9, 0)
        shotAEye = car - forward * 7 + SIMD3<Float>(0, 3.2, 0)   // fallback: high behind the car
        for offset in candidates {
            let eye = car + offset + SIMD3<Float>(0, 0.75, 0)
            if lineIsClear(from: target, to: eye, margin: 1.2) {
                shotAEye = eye
                break
            }
        }
        celebrationPoint = World3D.vec(finishLine, y: 6.4)
        // Only the lens changes: post-processing (depth of field, HDR, bloom) would make the GPU
        // rebuild its pipelines mid-frame and stall
        cameraNode.camera?.fieldOfView = 38
    }

    /// True when nothing solid (buildings, walls, props, parked cars) lies between two points,
    /// also checking `margin` meters past the end so the camera never sits inside a wall.
    private func lineIsClear(from start: SIMD3<Float>, to end: SIMD3<Float>, margin: Float = 0) -> Bool {
        hitDistance(from: start, to: end, margin: margin) == nil
    }

    /// Distance from `start` to the first solid hit towards `end` (+ margin), or nil.
    private func hitDistance(from start: SIMD3<Float>, to end: SIMD3<Float>, margin: Float = 0) -> Float? {
        let direction = end - start
        let length = simd_length(direction)
        guard length > 0.01 else { return nil }
        let far = start + direction / length * (length + margin)
        let options: [String: Any] = [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue,
                                      SCNHitTestOption.ignoreHiddenNodes.rawValue: true,
                                      SCNHitTestOption.backFaceCulling.rawValue: false]
        var nearest: Float?
        for root in [levelRoot, lotRoot] where !root.isHidden {
            let hits = root.hitTestWithSegment(from: SCNVector3(start.x, start.y, start.z),
                                               to: SCNVector3(far.x, far.y, far.z), options: options)
            if let hit = hits.first {
                let w = hit.worldCoordinates
                let d = simd_distance(start, SIMD3<Float>(w.x, w.y, w.z))
                nearest = min(nearest ?? d, d)
            }
        }
        return nearest
    }

    /// How far the orbit camera may go from the car before a wall (smoothed).
    private var orbitReach: Float = 99

    /// Shot B: hard cut to an orbit around the car, fireworks, confetti and a graded, glowing image.
    func celebrate() {
        cinematicShotB = true
        cinematicTime = 0
        let toCamera = shotAEye - cameraFocus
        cinematicAngle = atan2(-toCamera.z, toCamera.x) + 0.6
        // Start the orbit where the car can be seen
        let look = cameraFocus + SIMD3<Float>(0, 0.9, 0)
        for step in 0..<8 {
            let angle = cinematicAngle + Float(step) * .pi / 4
            let eye = cameraFocus + SIMD3<Float>(cos(angle) * 5.4, 0.55, -sin(angle) * 5.4)
            if lineIsClear(from: look, to: eye, margin: 0.8) {
                cinematicAngle = angle
                break
            }
        }
        orbitReach = 99
        // Fireworks and confetti are drawn by the 2D layer: 3D particle systems stalled a frame
        // the first time they appeared
        cameraNode.camera?.fieldOfView = 52
    }

    /// Stops (or resumes) drawing the 3D view, e.g. while the results card covers it.
    func setRenderingPaused(_ paused: Bool) {
        renderer?.isPlaying = !paused
        renderer?.rendersContinuously = !paused
        // Running actions (spinning pickups, arrows) would keep asking for redraws
        scene.isPaused = paused
    }

    /// Confetti and firework systems, built before the finish so nothing is created mid-animation.
    private var celebration: [(node: SCNNode, system: SCNParticleSystem, delay: TimeInterval)] = []
    private var finishPoint: SCNVector3?

    private static func confettiSystem() -> SCNParticleSystem {
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
        return confetti
    }

    private static func fireworkSystem(color: UIColor) -> SCNParticleSystem {
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
        burst.particleColor = color
        burst.particleColorVariation = SCNVector4(0.05, 0.1, 0.1, 0)
        burst.particleImage = CarArt.glowParticle()
        let propertyAnimation = CAKeyframeAnimation()
        propertyAnimation.values = [1.0, 1.0, 0.0]
        propertyAnimation.keyTimes = [0, 0.6, 1]
        burst.propertyControllers = [.opacity: SCNParticlePropertyController(animation: propertyAnimation)]
        return burst
    }

    /// Builds the celebration for the current finish line and fires a tiny invisible burst of each
    /// particle kind so their shaders are compiled during loading, not at the finish.
    private func prepareCelebration() {
        celebration.removeAll()
        guard let finish = finishPoint else { return }
        let confettiNode = SCNNode()
        confettiNode.position = finish
        fxRoot.addChildNode(confettiNode)
        celebration.append((confettiNode, World3D.confettiSystem(), 0))
        let colors = [UIColor(red: 1, green: 0.82, blue: 0.2, alpha: 1), UIColor(red: 0.3, green: 0.85, blue: 1, alpha: 1),
                      UIColor(red: 1, green: 0.35, blue: 0.6, alpha: 1)]
        for (index, offset) in [SIMD3<Float>(-5, 9, 0), SIMD3<Float>(4, 11, 2), SIMD3<Float>(0, 13, -3)].enumerated() {
            let node = SCNNode()
            node.position = SCNVector3(finish.x + offset.x, offset.y, finish.z + offset.z)
            fxRoot.addChildNode(node)
            celebration.append((node, World3D.fireworkSystem(color: colors[index]), 0.15 + Double(index) * 0.45))
        }
        // Warm-up: one tiny, short burst of each kind
        for warm in [World3D.confettiSystem(), World3D.fireworkSystem(color: colors[0])] {
            warm.birthRate = 20
            warm.emissionDuration = 0.05
            warm.particleLifeSpan = 0.1
            warm.particleLifeSpanVariation = 0
            warm.particleSize = 0.001
            warm.particleSizeVariation = 0
            let node = SCNNode()
            node.position = finish
            fxRoot.addChildNode(node)
            node.addParticleSystem(warm)
        }
    }

    func stopCinematic() {
        cinematicActive = false
        cinematicShotB = false
        cameraNode.camera?.fieldOfView = fieldOfView
    }

    /// While the loading screen covers the view, the camera turns around the start point (low and
    /// then high) so every material, texture and mesh of the level is drawn once and the GPU work
    /// for first sightings happens before the race, not at the first corner.
    private var sweepClock: Float = -1

    /// A police car parked under the start while the loading screen is up, so its meshes and
    /// shaders are drawn once before the first chase.
    private var warmPolice: SCNNode?

    func beginWarmupSweep() {
        sweepClock = 0
        warmPolice?.removeFromParentNode()
        warmPolice = cityMap != nil ? makePoliceNode() : nil
        warmPolice?.position = SCNVector3(0, -40, 0)
        // Every parked car at full detail while the screen is covered, so their wheels and lights
        // are drawn once now
        for entry in parkedCars3D { entry.car.setDetail(true) }
    }
    func endWarmupSweep() {
        warmPolice?.removeFromParentNode()
        warmPolice = nil
        guard sweepClock >= 0 else { return }
        sweepClock = -1
        // The next frame puts the camera straight behind the car (no swing from the sweep)
        cameraReady = false
        cameraNode.camera?.zFar = 260
        cameraNode.camera?.fieldOfView = fieldOfView
    }

    func follow(position: CGPoint, heading: CGFloat, dt: CGFloat, snap: Bool = false) {
        let carPoint = World3D.vec(position)
        // In view of the touring camera, just beside the start
        warmPolice?.position = SCNVector3(carPoint.x + 7, carPoint.y, carPoint.z + 4)
        if sweepClock >= 0 {
            if sweepClock < 1.0 {
                // Show every signal color once while the screen is covered
                let state = Int(sweepClock * 3) % 3
                for index in signalHeads.indices {
                    signalHeads[index].lamp.geometry?.materials = [World3D.signalMaterials[state]]
                    signalHeads[index].state = -1
                }
            }
            sweepClock += Float(dt)
            let turn: Float = 1.2
            let phase = Int(sweepClock / turn) % 3
            if phase == 0, let map = cityMap {
                // Straight down over the whole map: every car and building in view at once
                let world = CGSize(width: map.xs.last.map { $0 + 100 } ?? 1000, height: map.ys.last.map { $0 + 100 } ?? 500)
                let center = World3D.vec(CGPoint(x: world.width / 2, y: world.height / 2))
                cameraNode.camera?.zFar = 420
                cameraNode.camera?.fieldOfView = 75
                cameraNode.simdPosition = SIMD3<Float>(center.x, 200, center.z)
                cameraNode.simdLook(at: SIMD3<Float>(center.x, 0, center.z), up: SIMD3<Float>(0, 0, -1), localFront: SIMD3<Float>(0, 0, -1))
                return
            }
            cameraNode.camera?.zFar = 260
            cameraNode.camera?.fieldOfView = fieldOfView
            let angle = sweepClock / turn * 2 * .pi
            let high = phase == 2
            let eye = SIMD3<Float>(carPoint.x, high ? 30 : 4.5, carPoint.z)
            let look = SIMD3<Float>(carPoint.x + cos(angle) * 40, high ? 0 : 3, carPoint.z - sin(angle) * 40)
            cameraNode.simdPosition = eye
            cameraNode.simdLook(at: look, up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
            return
        }
        let focus = SIMD3<Float>(carPoint.x, carPoint.y, carPoint.z)
        if cinematicActive && !snap && !cinematicShotB {
            cameraFocus += (focus - cameraFocus) * min(1, Float(dt) * 10)
            let target = cameraFocus + SIMD3<Float>(0, 0.6, 0)
            cameraNode.simdPosition = shotAEye
            cameraNode.simdLook(at: target, up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
            cameraNode.camera?.focusDistance = CGFloat(simd_distance(shotAEye, target))
            return
        }
        if cinematicActive && !snap {
            cinematicTime += Float(dt)
            let t = cinematicTime
            cameraFocus += (focus - cameraFocus) * min(1, Float(dt) * 8)
            // Two moves: a fast, low sweep close past the car's nose, then the camera eases out and
            // cranes up into a wide shot over the car with the fireworks behind
            let crane = easeStep(1.3, 2.9, t)
            cinematicAngle += Float(dt) * (1.7 * (1 - crane) + 0.32 * crane)
            var radius = 5.4 + crane * 5.6
            let height = 0.55 + crane * 4.6
            // Never behind a wall: pull in before anything solid between the car and the camera
            let look = cameraFocus + SIMD3<Float>(0, 0.9 + crane * 0.3, 0)
            let direction = SIMD3<Float>(cos(cinematicAngle), 0, -sin(cinematicAngle))
            let wanted = cameraFocus + direction * radius + SIMD3<Float>(0, height, 0)
            if let hit = hitDistance(from: look, to: wanted, margin: 0.8) {
                orbitReach = min(orbitReach, max(2.2, hit - 0.8))
            } else {
                orbitReach += (99 - orbitReach) * min(1, Float(dt) * 1.5)
            }
            radius = min(radius, orbitReach)
            let eye = cameraFocus + direction * radius + SIMD3<Float>(0, height, 0)
            cameraNode.simdPosition = eye
            cameraNode.simdLook(at: look, up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
            cameraNode.camera?.focusDistance = CGFloat(radius)
            cameraNode.camera?.fieldOfView = CGFloat(44 + crane * 10)
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
        if !cinematicActive { cameraNode.camera?.fieldOfView = fieldOfView }
    }

    func shake(strength: CGFloat) {
        shakeAmount = max(shakeAmount, Float(strength) * 0.05)
    }

    // MARK: Level

    func makeCar(color: UIColor, style: CarStyle = .sedan, model: CarModelID = .italia, variety: Int = 0) -> Car3D {
        let car = Car3D(color: color, style: style, model: model, variety: variety)
        scene.rootNode.addChildNode(car.node)
        return car
    }

    /// The loose cones, barrels and bins of a city level.
    func addProps(_ defs: [PropDef]) -> StreetProps {
        StreetProps(defs: defs, parent: levelRoot)
    }

    /// Day, night (dark sky, moonlight, lamp light pools) or rain (overcast, wet shiny streets,
    /// falling rain around the camera).
    func setWeather(_ newWeather: Weather) {
        weather = newWeather
        let night = newWeather == .night
        let wet = newWeather == .rain
        let snowy = newWeather == .snow
        switch newWeather {
        case .day:
            scene.background.contents = Scenery.daySky
            scene.lightingEnvironment.contents = Scenery.daySky
            scene.lightingEnvironment.intensity = 1.0
            scene.fogColor = UIColor(red: 0.80, green: 0.86, blue: 0.94, alpha: 1)
            scene.fogStartDistance = 70
            scene.fogEndDistance = 200
            sunLight.intensity = 1150
            sunLight.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
            ambientLight.intensity = 420
            ambientLight.color = UIColor(red: 0.80, green: 0.86, blue: 1.0, alpha: 1)
        case .night:
            scene.background.contents = CityArt.nightSky
            scene.lightingEnvironment.contents = CityArt.nightSky
            scene.lightingEnvironment.intensity = 0.9
            scene.fogColor = UIColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 1)
            scene.fogStartDistance = 45
            scene.fogEndDistance = 170
            sunLight.intensity = 260
            sunLight.color = UIColor(red: 0.55, green: 0.66, blue: 1.0, alpha: 1)
            ambientLight.intensity = 210
            ambientLight.color = UIColor(red: 0.45, green: 0.52, blue: 0.80, alpha: 1)
        case .rain:
            // Overcast and soft: a grey day, light mist, the wet street catches the lights
            scene.background.contents = Scenery.overcastSky
            scene.lightingEnvironment.contents = Scenery.overcastSky
            scene.lightingEnvironment.intensity = 1.2
            scene.fogColor = UIColor(red: 0.46, green: 0.50, blue: 0.56, alpha: 1)
            scene.fogStartDistance = 32
            scene.fogEndDistance = 175
            sunLight.intensity = 560
            sunLight.color = UIColor(red: 0.84, green: 0.88, blue: 0.96, alpha: 1)
            ambientLight.intensity = 380
            ambientLight.color = UIColor(red: 0.68, green: 0.74, blue: 0.84, alpha: 1)
        case .snow:
            // Bright white overcast: soft shadows, pale blue mist, snow on the ground
            scene.background.contents = Scenery.overcastSky
            scene.lightingEnvironment.contents = Scenery.overcastSky
            scene.lightingEnvironment.intensity = 1.55
            scene.fogColor = UIColor(red: 0.80, green: 0.84, blue: 0.90, alpha: 1)
            scene.fogStartDistance = 26
            scene.fogEndDistance = 155
            sunLight.intensity = 720
            sunLight.color = UIColor(red: 0.92, green: 0.95, blue: 1.0, alpha: 1)
            ambientLight.intensity = 560
            ambientLight.color = UIColor(red: 0.84, green: 0.89, blue: 1.0, alpha: 1)
        }
        lampPools?.isHidden = !night
        // Wet asphalt: darker and glossy, with puddles and rain rings (World3D.wetRoadShader)
        for material in roadMaterials + lotMaterials {
            material.roughness.intensity = wet ? 0.5 : 1
            material.diffuse.intensity = wet ? 0.78 : 1
            let detail = detailMaterials.contains(ObjectIdentifier(material))
            material.shaderModifiers = World3D.groundShader(detail: detail, wet: wet, snowy: snowy).map { [.surface: $0] }
        }
        if wet {
            if rain == nil { rain = World3D.makeRain() }
            if let rain = rain, rain.parent == nil { cameraNode.addChildNode(rain) }
            if rainGround.parent == nil {
                rainGround.addParticleSystem(World3D.makeSplashes())
                scene.rootNode.addChildNode(rainGround)
            }
        } else {
            rain?.removeFromParentNode()
            rainGround.removeFromParentNode()
        }
        if snowy {
            if snow == nil { snow = World3D.makeSnow() }
            if let snow = snow, snow.parent == nil { cameraNode.addChildNode(snow) }
        } else {
            snow?.removeFromParentNode()
        }
    }

    /// Ground splashes follow the point in front of the camera.
    private let rainGround = SCNNode()
    func updateRain() {
        guard rainGround.parent != nil else { return }
        let eye = cameraNode.simdWorldPosition
        let front = cameraNode.simdWorldFront
        let ahead = SIMD2<Float>(front.x, front.z)
        let flat = simd_length(ahead) > 0.01 ? simd_normalize(ahead) : SIMD2<Float>(0, -1)
        rainGround.simdPosition = SIMD3<Float>(eye.x + flat.x * 11, 0.04, eye.z + flat.y * 11)
    }

    /// A lightning flash: the sky and the street light up twice, quickly.
    func lightning() {
        guard weather == .rain else { return }
        let sun = sunLight.intensity
        let ambient = ambientLight.intensity
        let sky = scene.lightingEnvironment.intensity
        let peaks: [(TimeInterval, CGFloat)] = [(0, 1), (0.07, 0.25), (0.13, 0.85), (0.22, 0.1), (0.32, 0)]
        for (delay, amount) in peaks {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.weather == .rain else { return }
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.05
                self.sunLight.intensity = sun + 2400 * amount
                self.ambientLight.intensity = ambient + 900 * amount
                self.scene.lightingEnvironment.intensity = sky + 1.6 * amount
                SCNTransaction.commit()
            }
        }
    }

    /// Wet street: puddles (glossy, darker, a noise mask in world space) and the rings of the
    /// drops landing on them (cells of 0.7 m, each with its own random timing).
    static let wetRoadShader = """
    #pragma body
    float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
    float2 p = wp.xz;
    float2 q = p * 0.16;
    float puddle = sin(q.x * 1.7 + sin(q.y * 1.3) * 1.2) * sin(q.y * 1.9 + sin(q.x * 0.9) * 1.4);
    puddle = smoothstep(0.1, 0.5, puddle);
    float2 ripple = float2(0.0);
    float2 g = p / 0.7;
    float2 cell = floor(g);
    float h = fract(sin(dot(cell, float2(127.1, 311.7))) * 43758.5453);
    float2 d = fract(g) - 0.5 - (float2(fract(h * 13.1), fract(h * 71.7)) - 0.5) * 0.5;
    float t = fract(scn_frame.time * 1.25 + h);
    float r = length(d);
    ripple += d / max(r, 0.001) * exp(-pow((r - t * 0.42) * 26.0, 2.0)) * (1.0 - t);
    g = p / 0.53 + 0.37;
    cell = floor(g);
    h = fract(sin(dot(cell, float2(269.5, 183.3))) * 43758.5453);
    d = fract(g) - 0.5 - (float2(fract(h * 17.3), fract(h * 53.9)) - 0.5) * 0.5;
    t = fract(scn_frame.time * 1.6 + h);
    r = length(d);
    ripple += d / max(r, 0.001) * exp(-pow((r - t * 0.42) * 26.0, 2.0)) * (1.0 - t);
    float3 bend = (scn_frame.viewTransform * float4(ripple.x, 0.0, ripple.y, 0.0)).xyz;
    _surface.normal = normalize(_surface.normal + bend * (0.25 + puddle * 0.45));
    _surface.roughness = mix(_surface.roughness, 0.04, puddle * 0.9);
    _surface.diffuse.rgb *= mix(1.0, 0.62, puddle);
    """

    /// Asphalt materials that also get the close-up photo grain.
    private var detailMaterials = Set<ObjectIdentifier>()
    private static let detailMap: SCNMaterialProperty = {
        let property = SCNMaterialProperty(contents: Scenery.image("ph_asphalt_detail.jpg") as Any)
        property.mipFilter = .linear
        property.wrapS = .repeat
        property.wrapT = .repeat
        return property
    }()
    private static let detailNormal: SCNMaterialProperty = {
        let property = SCNMaterialProperty(contents: Scenery.image("ph_asphalt_nor.jpg") as Any)
        property.mipFilter = .linear
        property.wrapS = .repeat
        property.wrapT = .repeat
        return property
    }()

    /// Street asphalt gets Poly Haven's scanned asphalt as a second, fine layer in world space
    /// (a tile every 2.4 m, about 4 px per centimetre): sharp stones and pores close to the
    /// camera, fading out with distance where the street texture alone looks right.
    private func addAsphaltDetail(_ material: SCNMaterial) {
        material.setValue(World3D.detailMap, forKey: "detailMap")
        material.setValue(World3D.detailNormal, forKey: "detailNormal")
        detailMaterials.insert(ObjectIdentifier(material))
    }

    private static let detailBody = """
    {
        constexpr sampler ds(filter::linear, mip_filter::linear, address::repeat);
        float3 dw = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
        float fade = 1.0 - smoothstep(10.0, 42.0, length(_surface.position));
        float2 duv = dw.xz * 0.42;
        float grain = detailMap.sample(ds, duv).r;
        _surface.diffuse.rgb *= mix(1.0, grain / 0.9, fade * 0.75);
        float3 dn = detailNormal.sample(ds, duv).rgb * 2.0 - 1.0;
        float3 bend = (scn_frame.viewTransform * float4(dn.x, 0.0, -dn.y, 0.0)).xyz;
        _surface.normal = normalize(_surface.normal + bend * 0.45 * fade);
    }
    """

    /// The ground's surface shader: the asphalt grain, then the wet or snowy look (each in its
    /// own block so their variables never clash).
    static func groundShader(detail: Bool, wet: Bool, snowy: Bool) -> String? {
        func body(_ shader: String) -> String {
            "{\n" + shader.replacingOccurrences(of: "#pragma body", with: "") + "\n}\n"
        }
        var text = ""
        if detail { text += detailBody + "\n" }
        if wet { text += body(wetRoadShader) } else if snowy { text += body(snowRoadShader) }
        guard !text.isEmpty else { return nil }
        let arguments = detail ? "#pragma arguments\ntexture2d<float> detailMap;\ntexture2d<float> detailNormal;\n" : ""
        return arguments + "#pragma body\n" + text
    }

    /// Snow on the ground: drifts in world space (whiter, rough, a soft sparkle), the tracks the
    /// traffic keeps clearer along the lanes.
    static let snowRoadShader = """
    #pragma body
    float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
    float2 p = wp.xz;
    float n = sin(p.x * 0.31 + sin(p.y * 0.23) * 1.7) * sin(p.y * 0.37 + sin(p.x * 0.19) * 1.3);
    n = n * 0.5 + 0.5;
    float fine = fract(sin(dot(floor(p * 9.0), float2(12.9898, 78.233))) * 43758.5453);
    float cover = clamp(0.55 + 0.45 * smoothstep(0.25, 0.75, n) - 0.08 * fine, 0.0, 1.0);
    float3 snowColor = float3(0.90, 0.93, 0.98) - 0.05 * fine;
    _surface.diffuse.rgb = mix(_surface.diffuse.rgb, snowColor, cover * 0.82);
    _surface.roughness = mix(_surface.roughness, 0.78, cover);
    _surface.metalness = mix(_surface.metalness, 0.0, cover);
    """

    /// Snow around the camera: soft round flakes drifting down slowly, near and far.
    private static func makeSnow() -> SCNNode {
        func layer(birthRate: CGFloat, box: CGFloat, size: CGFloat, alpha: CGFloat, speed: CGFloat, life: CGFloat) -> SCNParticleSystem {
            let system = SCNParticleSystem()
            system.birthRate = birthRate
            system.emitterShape = SCNBox(width: box, height: 0.1, length: box, chamferRadius: 0)
            system.particleLifeSpan = life
            system.particleLifeSpanVariation = life * 0.15
            system.particleVelocity = speed
            system.particleVelocityVariation = speed * 0.35
            system.emittingDirection = SCNVector3(0.22, -1, 0.08)
            system.spreadingAngle = 18
            system.particleSize = size
            system.particleSizeVariation = size * 0.45
            system.particleColor = UIColor(white: 1, alpha: alpha)
            system.particleColorVariation = SCNVector4(0, 0, 0, 0.3)
            system.particleImage = CarArt.glowParticle()
            system.blendMode = .alpha
            system.isLightingEnabled = false
            system.isAffectedByGravity = false
            system.loops = true
            // Flakes sway as they fall
            system.particleAngularVelocity = 40
            system.particleAngularVelocityVariation = 80
            return system
        }
        let node = SCNNode()
        node.position = SCNVector3(0, 8, -9)
        node.addParticleSystem(layer(birthRate: 320, box: 24, size: 0.09, alpha: 0.9, speed: 1.7, life: 5.5))
        let far = SCNNode()
        far.position = SCNVector3(0, 6, -26)
        far.addParticleSystem(layer(birthRate: 520, box: 60, size: 0.16, alpha: 0.55, speed: 1.4, life: 6))
        node.addChildNode(far)
        return node
    }

    /// Rain around the camera: a near layer of thin, quick streaks and a far, soft curtain.
    private static func makeRain() -> SCNNode {
        func layer(birthRate: CGFloat, box: CGFloat, size: CGFloat, alpha: CGFloat, speed: CGFloat) -> SCNParticleSystem {
            let system = SCNParticleSystem()
            system.birthRate = birthRate
            system.emitterShape = SCNBox(width: box, height: 0.1, length: box, chamferRadius: 0)
            system.particleLifeSpan = 0.85
            system.particleVelocity = speed
            system.particleVelocityVariation = speed * 0.12
            // Slanted by the wind
            system.emittingDirection = SCNVector3(0.16, -1, 0.06)
            system.spreadingAngle = 2
            system.particleSize = size
            system.particleSizeVariation = size * 0.3
            system.stretchFactor = 0.026
            system.particleColor = UIColor(red: 0.80, green: 0.85, blue: 0.92, alpha: alpha)
            system.particleColorVariation = SCNVector4(0, 0, 0.05, 0.3)
            system.particleImage = CarArt.rainStreak()
            system.blendMode = .alpha
            system.isLightingEnabled = false
            system.isAffectedByGravity = false
            system.loops = true
            return system
        }
        let node = SCNNode()
        node.position = SCNVector3(0, 13, -9)
        node.addParticleSystem(layer(birthRate: 750, box: 22, size: 0.03, alpha: 0.32, speed: 28))
        let far = SCNNode()
        far.position = SCNVector3(0, 4, -26)
        far.addParticleSystem(layer(birthRate: 800, box: 60, size: 0.06, alpha: 0.14, speed: 24))
        node.addChildNode(far)
        return node
    }

    /// Small drops bouncing up where the rain lands, in front of the camera.
    private static func makeSplashes() -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.birthRate = 260
        system.emitterShape = SCNPlane(width: 26, height: 26)
        system.particleLifeSpan = 0.22
        system.particleLifeSpanVariation = 0.08
        system.particleVelocity = 1.8
        system.particleVelocityVariation = 0.8
        system.emittingDirection = SCNVector3(0, 1, 0)
        system.spreadingAngle = 35
        system.particleSize = 0.025
        system.particleSizeVariation = 0.01
        system.particleColor = UIColor(red: 0.85, green: 0.9, blue: 1.0, alpha: 0.32)
        system.particleImage = CarArt.glowParticle()
        system.blendMode = .additive
        system.isLightingEnabled = false
        system.isAffectedByGravity = true
        system.loops = true
        system.particleColorVariation = SCNVector4(0, 0, 0, 0.3)
        return system
    }

    /// Water thrown up behind the rear wheels on a wet street.
    static func makeSpray() -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.birthRate = 0
        system.particleLifeSpan = 0.55
        system.particleLifeSpanVariation = 0.15
        system.particleVelocity = 3.5
        system.particleVelocityVariation = 1.5
        system.emittingDirection = SCNVector3(-1, 0.55, 0)
        system.spreadingAngle = 22
        system.particleSize = 0.22
        system.particleSizeVariation = 0.1
        system.particleColor = UIColor(red: 0.82, green: 0.86, blue: 0.92, alpha: 0.22)
        system.particleImage = CarArt.glowParticle()
        system.blendMode = .alpha
        system.isLightingEnabled = false
        system.isAffectedByGravity = true
        system.dampingFactor = 1.5
        system.loops = true
        let grow = CABasicAnimation(keyPath: "size")
        grow.fromValue = 0.6
        grow.toValue = 2.4
        grow.duration = 1
        system.propertyControllers = [.size: SCNParticlePropertyController(animation: grow)]
        let fade = CAKeyframeAnimation()
        fade.values = [0.0, 1.0, 0.0]
        fade.keyTimes = [0, 0.2, 1]
        fade.duration = 1
        system.propertyControllers?[.opacity] = SCNParticlePropertyController(animation: fade)
        return system
    }

    /// The police car (Meshy, its own livery): every chase shares its meshes and materials.
    static let policeTemplate: SCNNode? = {
        guard let holder = TrafficVehicles.policeTemplate() else { return nil }
        holder.enumerateHierarchy { node, _ in
            node.castsShadow = node.name?.hasPrefix("wheel") == false
        }
        return holder
    }()

    /// The police car of a chase, added to the level (its materials are copied per chase).
    /// A node that lives as long as the level (patrol cars of a parking challenge).
    func addLevelNode(_ node: SCNNode) { levelRoot.addChildNode(node) }

    func makePoliceNode() -> SCNNode {
        let node: SCNNode
        if let template = World3D.policeTemplate {
            // Shares the template's meshes and materials (already on the GPU from the warm-up):
            // copying them made the first crash of a level stall while the copies were uploaded.
            // Every police car's light bar therefore flashes in step.
            node = template.clone()
        } else {
            node = Car3D(color: .white, style: .sedan, vehicle: "sedan").node
        }
        levelRoot.addChildNode(node)
        return node
    }

    func load(level: LevelDef, spotSlots: [Int], mySlot: Int) {
        levelRoot.childNodes.forEach { $0.removeFromParentNode() }
        fxRoot.childNodes.forEach { $0.removeFromParentNode() }
        buildSkidPool()
        myNeon = nil
        stopCinematic()
        setRenderingPaused(false)
        parkedCars3D.removeAll()
        arrowNode = nil
        lotRoot.isHidden = level.city != nil
        cityMap = nil
        signalHeads.removeAll()
        roadMaterials.removeAll()
        detailMaterials.removeAll()
        lampPools = nil
        var clock = CACurrentMediaTime()
        func lap(_ what: String) {
            guard PerfSettings.benchmark else { return }
            let now = CACurrentMediaTime()
            FileHandle.standardError.write(String(format: "PPTIME %@ %.0f ms\n", what, (now - clock) * 1000).data(using: .utf8)!)
            clock = now
        }
        if let city = level.city {
            buildCity(city, world: level.world)
            lap("buildCity")
            levelRoot.addChildNode(CityDecor.build(level: level, city: city))
            lap("cityDecor")
        }
        // City rounds have their weather; a parking lot can be wet (a harder level)
        setWeather(level.city != nil || level.weather == .rain || level.weather == .snow ? level.weather : .day)
        lap("weather")

        if level.city == nil {
            levelRoot.addChildNode(Scenery.markingsNode(for: level))
        }
        if level.race {
            buildFinish(level.spots[0])
            finishPoint = World3D.vec(level.spots[0].center, y: 6.4)
        } else {
            finishPoint = nil
            celebration.removeAll()
        }
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
                myNeonHolding = false
                let outlineSize = CGSize(width: def.size.width + 3, height: def.size.height + 3)
                myNeonImages = (CarArt.spotOutlineImage(size: outlineSize, color: color),
                                CarArt.spotOutlineImage(size: outlineSize, color: UIColor(red: 0.3, green: 1.0, blue: 0.5, alpha: 1)))
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

        lap("spots")
        defer { lap("obstacles (parked cars)") }
        let parkedCars = SCNNode()
        var roofCache: [Int: SCNMaterial] = [:]
        // Optimized: all buildings become one geometry with one facade/roof material per color
        let buildingMesh = MeshBuilder()
        var facadeCache: [Int: SCNMaterial] = [:]
        defer {
            if PerfSettings.optimized {
                if let merged = buildingMesh.build() {
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
                                parked: true, variety: obstacle.tint &* 977 &+ Int(obstacle.center.x) &+ Int(obstacle.center.y) &* 3)
                car.update(position: obstacle.center, heading: obstacle.angle, steer: 0)
                if PerfSettings.optimized {
                    levelRoot.addChildNode(car.node)
                    parkedCars3D.append((car, obstacle.center))
                } else {
                    parkedCars.addChildNode(car.node)
                }
            case .building:
                // City blocks are drawn in detail by CityDecor
                if level.city != nil { continue }
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
                    let base = World3D.vec(obstacle.center)
                    let floors = Float(max(1, (height / 3.2).rounded()))
                    buildingMesh.addBox(center: SIMD3(base.x, base.y, base.z), width: Float(width), height: Float(height),
                                        length: Float(length), angle: Float(obstacle.angle), wall: facade, roof: roof,
                                        wallRepeats: { span in SIMD2(max(1, (span / 4).rounded()), floors) })
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
                let long = Scenery.shared("concrete", tile: 2, size: CGSize(width: max(obstacle.size.width, obstacle.size.height) / 10, height: 1.1))
                let short = Scenery.shared("concrete", tile: 2, size: CGSize(width: min(obstacle.size.width, obstacle.size.height) / 10, height: 1.1))
                let top = Scenery.shared("concrete", tile: 2, size: CGSize(width: obstacle.size.width / 10, height: obstacle.size.height / 10))
                let alongX = obstacle.size.width >= obstacle.size.height
                // SCNBox faces: front, right, back, left, top, bottom
                geometry.materials = alongX ? [long, short, long, short, top, concrete] : [short, long, short, long, top, concrete]
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
        // Posts stand on the sidewalks, clear of the whole street (they were in the parking lanes)
        let across = max(def.size.height / 10, cityMap != nil ? CityMap.roadHalf * 2 / 10 + 0.4 : 0)

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

    /// Physically based asphalt with its normal and roughness maps (one material per call).
    static func asphaltMaterial(albedo: String, normal: String, rough: String) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIImage(named: albedo)
        material.normal.contents = UIImage(named: normal)
        material.normal.intensity = 0.8
        material.roughness.contents = UIImage(named: rough)
        material.metalness.contents = NSNumber(value: 0)
        for property in [material.diffuse, material.normal, material.roughness] {
            property.mipFilter = .linear
            property.maxAnisotropy = 8
        }
        return material
    }

    /// Streets, intersections, sidewalks and edge barriers for a city level.
    private func buildCity(_ city: CityMap, world: CGSize) {
        let roadWidth = CityMap.roadHalf * 2
        // Realistic asphalt (tools/make_road_textures.py): albedo, normal and roughness maps for
        // a 20 m tile repeated along the street, and a large stain map that hides the repeat
        func roadMaterial(length: CGFloat) -> SCNMaterial {
            let material = World3D.asphaltMaterial(albedo: "road_albedo.jpg", normal: "road_normal.jpg", rough: "road_rough.jpg")
            let repeatAlong = SCNMatrix4MakeScale(Float(length / roadWidth), 1, 1)
            for property in [material.diffuse, material.normal, material.roughness] {
                property.wrapS = .repeat
                property.contentsTransform = repeatAlong
            }
            material.multiply.contents = UIImage(named: "street_stains.jpg")
            material.multiply.wrapS = .repeat
            material.multiply.wrapT = .repeat
            material.multiply.contentsTransform = SCNMatrix4MakeScale(Float(length / 1200), Float(roadWidth / 1200), 1)
            roadMaterials.append(material)
            addAsphaltDetail(material)
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
        // North-south streets: the same plane turned a quarter around a holder (so the texture and
        // its normal map run along the street)
        for x in city.xs {
            let plane = SCNPlane(width: world.height / 10, height: roadWidth / 10)
            plane.materials = [roadMaterial(length: world.height)]
            let node = flat(plane, y: 0.02)
            let holder = SCNNode()
            holder.eulerAngles.y = Float.pi / 2
            holder.addChildNode(node)
            let center = World3D.vec(CGPoint(x: x, y: world.height / 2))
            holder.position = SCNVector3(center.x, 0, center.z)
            ground.addChildNode(holder)
        }
        let junction = SCNPlane(width: roadWidth / 10, height: roadWidth / 10)
        let junctionMaterial = World3D.asphaltMaterial(albedo: "junction_albedo.jpg", normal: "junction_normal.jpg", rough: "junction_rough.jpg")
        roadMaterials.append(junctionMaterial)
        addAsphaltDetail(junctionMaterial)
        junction.materials = [junctionMaterial]
        let stripe = SCNPlane(width: 0.5, height: 3.2)
        // Worn white paint on asphalt
        let zebra = Mat.pbr(.white, metal: 0, rough: 0.7)
        zebra.diffuse.contents = UIImage(named: "zebra_albedo.jpg")
        stripe.materials = [zebra]
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
        for block in city.blocks {
            let plane = SCNPlane(width: block.width / 10, height: block.height / 10)
            // Interlocking herringbone pavers (Poly Haven scan), a tile every 1.4 m with full relief;
            // wet or snowy with the weather
            let sidewalk = Scenery.surface("sidewalk", tile: 1.4, size: CGSize(width: block.width / 10, height: block.height / 10), normal: 1.2)
            roadMaterials.append(sidewalk)
            plane.materials = [sidewalk]
            // Raised to the kerb's top: driving onto it is a real step up
            let node = flat(plane, y: Float(CityMap.kerbTop))
            let p = World3D.vec(CGPoint(x: block.midX, y: block.midY))
            node.position.x = p.x
            node.position.z = p.z
            ground.addChildNode(node)
        }
        // Low barriers around the map edge
        let edges: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: world.width / 2, y: -4), world.width + 16, 8),
            (CGPoint(x: world.width / 2, y: world.height + 4), world.width + 16, 8),
            (CGPoint(x: -4, y: world.height / 2), 8, world.height + 16),
            (CGPoint(x: world.width + 4, y: world.height / 2), 8, world.height + 16)
        ]
        for edge in edges {
            let box = SCNBox(width: edge.1 / 10, height: 0.9, length: edge.2 / 10, chamferRadius: 0.1)
            // Concrete repeated every 2 m along the barrier (one stretched texture looked flat)
            box.materials = [Scenery.surface("concrete", tile: 2, size: CGSize(width: max(edge.1, edge.2) / 10, height: 0.9))]
            let node = SCNNode(geometry: box)
            node.position = World3D.vec(edge.0, y: 0.45)
            ground.addChildNode(node)
        }
        // Added as they are: flattenedClone dropped the street planes (the map showed bare ground)
        levelRoot.addChildNode(ground)
        buildStreetFurniture(city, world: world)
    }

    // MARK: Street furniture and traffic lights

    private static let signalMaterials: [SCNMaterial] = {
        let colors = [UIColor(red: 1.0, green: 0.15, blue: 0.1, alpha: 1), UIColor(red: 1.0, green: 0.75, blue: 0.1, alpha: 1),
                      UIColor(red: 0.2, green: 1.0, blue: 0.45, alpha: 1)]
        return colors.map { color in
            let material = Mat.glow(color)
            material.diffuse.intensity = 1.8
            material.emission.intensity = 1.8
            return material
        }
    }()

    /// Traffic lights at every corner of every intersection, stop lines, street lamps and curbs.
    /// Static parts are written into one mesh; only the lit lamps are separate nodes.
    /// Street lamp spots on the sidewalks, with the way their arm reaches (scene x/z). Every spot
    /// is checked on its own: it must stand clear of every crossing street and intersection
    /// (the second lamp of a pair used to be shifted onto a cross street unchecked).
    static func streetLampPoints(city: CityMap, world: CGSize) -> [(position: CGPoint, toward: SIMD2<Float>)] {
        let sidewalk = CityMap.roadHalf + 8
        func clear(_ p: CGPoint) -> Bool {
            guard p.x > 40, p.y > 40, p.x < world.width - 40, p.y < world.height - 40 else { return false }
            // Off every road surface (its own street is `sidewalk` away) and away from corners
            let offX = city.xs.allSatisfy { abs($0 - p.x) >= sidewalk - 0.5 }
            let offY = city.ys.allSatisfy { abs($0 - p.y) >= sidewalk - 0.5 }
            let nearCornerX = city.xs.contains { abs($0 - p.x) < 170 }
            let nearCornerY = city.ys.contains { abs($0 - p.y) < 170 }
            return offX && offY && !(nearCornerX && nearCornerY)
        }
        var result: [(CGPoint, SIMD2<Float>)] = []
        for (j, y) in city.ys.enumerated() {
            var x: CGFloat = 260
            while x < world.width - 200 {
                let candidates: [(CGPoint, SIMD2<Float>, Bool)] = [
                    (CGPoint(x: x, y: y - sidewalk), SIMD2(0, -1), j > 0),
                    (CGPoint(x: x + 200, y: y + sidewalk), SIMD2(0, 1), j < city.rows - 1)
                ]
                for (point, toward, exists) in candidates where exists && clear(point) {
                    result.append((point, toward))
                }
                x += 400
            }
        }
        for (i, x) in city.xs.enumerated() {
            var y: CGFloat = 260
            while y < world.height - 200 {
                let candidates: [(CGPoint, SIMD2<Float>, Bool)] = [
                    (CGPoint(x: x - sidewalk, y: y), SIMD2(1, 0), i > 0),
                    (CGPoint(x: x + sidewalk, y: y + 200), SIMD2(-1, 0), i < city.cols - 1)
                ]
                for (point, toward, exists) in candidates where exists && clear(point) {
                    result.append((point, toward))
                }
                y += 400
            }
        }
        return result.map { (position: $0.0, toward: $0.1) }
    }

    /// The two traffic lights (Meshy from the reference sheet, tools/convert_meshy_street.py):
    /// a plain post and one with a pedestrian signal, lenses facing +x, post on the origin. Read
    /// once (in the background at launch, see CarModels.preload).
    static let signalTemplates: [SCNNode] = ["signal_pole", "signal_ped"].compactMap { Scenery.prop($0, lodDistance: 32) }
    static var signalTemplate: SCNNode? { signalTemplates.first }
    /// The mast's offset from the model's origin along the lenses' facing (the head sits on it).
    static let signalMastOffset: Float = 0

    /// A traffic light that can be knocked over: its pivot (at the mast's foot), where it stands
    /// (level units) and, once hit, how it falls.
    final class SignalPole {
        let pivot: SCNNode
        let position: CGPoint
        let lamp: SCNNode
        var fallen = false
        var angle: Float = 0
        var speed: Float = 0
        var axis = SIMD3<Float>(1, 0, 0)
        var bounces = 0
        init(pivot: SCNNode, position: CGPoint, lamp: SCNNode) {
            self.pivot = pivot
            self.position = position
            self.lamp = lamp
        }
    }
    private(set) var signalPoles: [SignalPole] = []
    private var fallingPoles: [SignalPole] = []

    /// A car hit the pole: it tips over the way the car was going, faster the harder the hit.
    func knockSignal(_ pole: SignalPole, direction: CGVector, speed: CGFloat) {
        guard !pole.fallen else { return }
        pole.fallen = true
        // Level direction to scene: x stays, level y is scene -z
        let d = simd_normalize(SIMD3<Float>(Float(direction.dx), 0, -Float(direction.dy)))
        pole.axis = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), d))
        pole.speed = 0.35 + min(1.6, Float(speed) / 260)
        pole.angle = 0.02
        pole.lamp.geometry?.materials = [World3D.signalOff]
        fallingPoles.append(pole)
    }

    /// Falling poles: a rod pivoting on its foot under gravity (angular acceleration grows with
    /// the tilt), a couple of small bounces when the head hits the street, then it lies there.
    func stepFallingSignals(_ dt: Float) {
        guard !fallingPoles.isEmpty else { return }
        let rest: Float = .pi / 2 - 0.035      // the head keeps the mast just off the ground
        for pole in fallingPoles {
            pole.speed += 3.3 * sin(pole.angle) * dt
            pole.angle += pole.speed * dt
            if pole.angle >= rest {
                pole.angle = rest
                if pole.bounces < 2 && pole.speed > 0.4 {
                    pole.speed = -pole.speed * 0.22
                    pole.bounces += 1
                } else {
                    pole.speed = 0
                }
            }
            pole.pivot.simdOrientation = simd_quatf(angle: pole.angle, axis: pole.axis)
        }
        fallingPoles.removeAll { $0.speed == 0 && $0.angle >= rest - 0.0001 }
    }

    private static let signalOff: SCNMaterial = Mat.pbr(UIColor(white: 0.05, alpha: 1), metal: 0, rough: 0.2)

    /// Lens centres of each traffic light (game axes, printed by tools/convert_meshy_street.py),
    /// just in front of the glass: red, amber, green.
    static let signalLensSets: [[SIMD3<Float>]] = [
        [SIMD3(0.209, 4.322, -0.002), SIMD3(0.212, 3.829, -0.001), SIMD3(0.222, 3.356, 0.005)],
        [SIMD3(0.308, 4.297, 0.053), SIMD3(0.319, 3.845, 0.057), SIMD3(0.319, 3.390, 0.060)]
    ]
    /// The lit lens: a thin glowing disc (turned to face along the light's x).
    static let signalLensDisc: SCNGeometry = {
        let disc = SCNCylinder(radius: 0.112, height: 0.02)
        disc.radialSegmentCount = 16
        return disc
    }()

    private func buildStreetFurniture(_ city: CityMap, world: CGSize) {
        cityMap = city
        signalHeads.removeAll()
        signalPoles.removeAll()
        fallingPoles.removeAll()
        let mesh = MeshBuilder()
        let poleMaterial = Mat.pbr(UIColor(white: 0.22, alpha: 1), metal: 0.6, rough: 0.45)
        let headMaterial = Mat.pbr(UIColor(white: 0.08, alpha: 1), metal: 0.2, rough: 0.6)
        // Kerbs: textured concrete (repeated along their length below), not flat white
        let curbMaterial = Scenery.shared("curb", tile: 1, size: CGSize(width: 1, height: 1))
        let lampGlow = Mat.glow(UIColor(red: 1.0, green: 0.92, blue: 0.75, alpha: 1))
        lampGlow.diffuse.intensity = 1.4
        // Worn road paint (the zebra stripe's texture), not a flat white that glowed at night
        let stopLine = Mat.pbr(UIColor(white: 0.8, alpha: 1), metal: 0, rough: 0.75)
        stopLine.diffuse.contents = UIImage(named: "zebra_albedo.jpg")
        func box(_ c: SCNVector3, _ w: Float, _ h: Float, _ l: Float, _ m: SCNMaterial) {
            mesh.addBox(center: SIMD3(c.x, c.y, c.z), width: w, height: h, length: l, angle: 0, wall: m, roof: m,
                        wallRepeats: { _ in SIMD2(1, 1) })
        }
        let signalModels = World3D.signalTemplates
        var lampHeads: [SCNVector3] = []

        for j in 0..<city.rows {
            for i in 0..<city.cols {
                let node = city.node(i, j)
                let center = CGPoint(x: city.xs[i], y: city.ys[j])
                // (corner offset, facing direction in scene space, controls east-west traffic?)
                let corners: [(CGPoint, SIMD2<Float>, Bool, Bool)] = [
                    (CGPoint(x: -112, y: -112), SIMD2(-1, 0), true, i > 0),          // faces west: eastbound
                    (CGPoint(x: 112, y: 112), SIMD2(1, 0), true, i < city.cols - 1),  // faces east: westbound
                    (CGPoint(x: 112, y: -112), SIMD2(0, 1), false, j > 0),            // faces south: northbound
                    (CGPoint(x: -112, y: 112), SIMD2(0, -1), false, j < city.rows - 1) // faces north: southbound
                ]
                for (offset, facing, horizontal, exists) in corners where exists {
                    let base = World3D.vec(CGPoint(x: center.x + offset.x, y: center.y + offset.y))
                    // The traffic light model faces +x; turned to face its traffic. Each light is its
                    // own node on a pivot at the mast's foot, so a car can knock it over
                    let yaw = atan2(-facing.y, facing.x)
                    let mast = World3D.signalMastOffset
                    let mastScene = SIMD3<Float>(base.x + mast * cos(yaw), 0, base.z - mast * sin(yaw))
                    let pivot = SCNNode()
                    pivot.simdPosition = mastScene + SIMD3(0, Float(CityMap.kerbTop), 0)
                    let holder = SCNNode()
                    holder.eulerAngles.y = yaw
                    holder.simdPosition = SIMD3(-mast * cos(yaw), 0, mast * sin(yaw))
                    pivot.addChildNode(holder)
                    // Every other corner gets the light with the pedestrian signal
                    let variant = signalModels.count > 1 ? (i + j + (horizontal ? 0 : 1)) % 2 : 0
                    if variant < signalModels.count {
                        let copy = signalModels[variant].clone()
                        copy.castsShadow = true
                        holder.addChildNode(copy)
                    } else {
                        let pole = SCNNode(geometry: SCNBox(width: 0.16, height: 4.3, length: 0.16, chamferRadius: 0.04))
                        pole.geometry?.materials = [poleMaterial]
                        pole.position = SCNVector3(0, 2.15, 0)
                        holder.addChildNode(pole)
                    }
                    // Lamp slots in the light's own space (it falls with it)
                    let slots = World3D.signalLensSets[signalModels.isEmpty ? 0 : variant].map { SCNVector3($0.x, $0.y, $0.z) }
                    let lamp = SCNNode(geometry: World3D.signalLensDisc.copy() as? SCNGeometry)
                    lamp.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                    lamp.castsShadow = false
                    holder.addChildNode(lamp)
                    levelRoot.addChildNode(pivot)
                    signalHeads.append((node, horizontal, lamp, slots, -1))
                    let level = CGPoint(x: CGFloat(mastScene.x + 50) * 10, y: CGFloat(25 - mastScene.z) * 10)
                    signalPoles.append(SignalPole(pivot: pivot, position: level, lamp: lamp))
                }
                // Stop lines across the approach lanes
                let approaches: [(CGPoint, Bool, Bool)] = [
                    (CGPoint(x: -118, y: -35), true, i > 0), (CGPoint(x: 118, y: 35), true, i < city.cols - 1),
                    (CGPoint(x: 35, y: -118), false, j > 0), (CGPoint(x: -35, y: 118), false, j < city.rows - 1)
                ]
                for (offset, horizontal, exists) in approaches where exists {
                    let p = World3D.vec(CGPoint(x: center.x + offset.x, y: center.y + offset.y))
                    box(SCNVector3(p.x, 0.025, p.z), horizontal ? 0.45 : 6.6, 0.012, horizontal ? 6.6 : 0.45, stopLine)
                }
            }
        }

        // Street lamps on the sidewalks, arms reaching over the road
        func lamp(at point: CGPoint, toward direction: SIMD2<Float>) {
            let base = World3D.vec(point)
            box(base, 0.14, 5.6, 0.14, poleMaterial)
            let arm = SCNVector3(base.x + direction.x * 0.7, 5.5, base.z + direction.y * 0.7)
            box(arm, direction.x != 0 ? 1.4 : 0.1, 0.1, direction.x != 0 ? 0.1 : 1.4, poleMaterial)
            let head = SCNVector3(base.x + direction.x * 1.35, 5.38, base.z + direction.y * 1.35)
            box(head, 0.5, 0.14, 0.5, lampGlow)
            lampHeads.append(head)
        }
        for point in World3D.streetLampPoints(city: city, world: world) {
            lamp(at: point.position, toward: point.toward)
        }
        // Light pools on the street under every lamp, for the night
        let pools = MeshBuilder()
        let poolMaterial = SCNMaterial()
        poolMaterial.lightingModel = .constant
        poolMaterial.diffuse.contents = CarArt.glowParticle()
        poolMaterial.multiply.contents = UIColor(red: 1.0, green: 0.78, blue: 0.48, alpha: 1)
        poolMaterial.blendMode = .add
        poolMaterial.writesToDepthBuffer = false
        for head in lampHeads {
            pools.addDecal(center: SIMD3(head.x, 0.07, head.z), direction: SIMD2(1, 0), length: 9, width: 9, material: poolMaterial)
        }
        if let geometry = pools.build() {
            let node = SCNNode(geometry: geometry)
            node.castsShadow = false
            node.opacity = 0.55
            node.isHidden = true
            levelRoot.addChildNode(node)
            lampPools = node
        }


        // Kerb stones around every block, flush with the raised pavement: 45 cm wide, a face to
        // the street that leans back a little, a smoothly rounded top edge (6 cm radius, ten
        // segments), a fine chamfer on the pavement side, and a shallow concrete gutter in front
        let top = Float(CityMap.kerbTop)
        let r: Float = 0.06
        var kerb: [(Float, Float, Float, Float)] = [(-0.55, 0.03, 0, 1), (-0.24, 0.024, 0, 1), (-0.235, 0.024, -0.995, 0.1),
                                                    (-0.225, top - r, -0.99, 0.12)]
        for k in 1...10 {
            let t = Float(k) / 10 * (.pi / 2)
            kerb.append((-0.225 + r - r * cos(t), top - r + r * sin(t), -cos(t), sin(t)))
        }
        kerb += [(0.205, top, 0, 1), (0.225, top - 0.012, 0.7, 0.7), (0.23, top - 0.02, 1, 0), (0.23, 0.0, 1, 0)]
        let paintedKerb = curbMaterial.copy() as! SCNMaterial
        paintedKerb.multiply.contents = UIColor(red: 1.0, green: 0.78, blue: 0.12, alpha: 1)
        paintedKerb.roughness.intensity = 0.8
        for block in city.blocks {
            // (start, end, towards the pavement) in level units
            let edges: [(CGPoint, CGPoint, CGVector)] = [
                (CGPoint(x: block.minX - 22, y: block.minY), CGPoint(x: block.maxX + 22, y: block.minY), CGVector(dx: 0, dy: 1)),
                (CGPoint(x: block.minX - 22, y: block.maxY), CGPoint(x: block.maxX + 22, y: block.maxY), CGVector(dx: 0, dy: -1)),
                (CGPoint(x: block.minX, y: block.minY), CGPoint(x: block.minX, y: block.maxY), CGVector(dx: 1, dy: 0)),
                (CGPoint(x: block.maxX, y: block.minY), CGPoint(x: block.maxX, y: block.maxY), CGVector(dx: -1, dy: 0))
            ]
            for (start, end, inward) in edges {
                let a = World3D.vec(start), b = World3D.vec(end)
                let side = SIMD3<Float>(Float(inward.dx), 0, -Float(inward.dy))
                // The last few metres before each crossing are painted yellow (no stopping)
                let from = SIMD3<Float>(a.x, 0, a.z), to = SIMD3<Float>(b.x, 0, b.z)
                let length = simd_length(to - from)
                let paint = min(6.5, length * 0.25)
                let dir = (to - from) / max(length, 0.001)
                let p0 = from + dir * paint, p1 = to - dir * paint
                mesh.addProfile(from: from, to: p0, side: side, profile: kerb, material: paintedKerb, uvRepeat: 1.0)
                mesh.addProfile(from: p0, to: p1, side: side, profile: kerb, material: curbMaterial, uvRepeat: 1.0)
                mesh.addProfile(from: p1, to: to, side: side, profile: kerb, material: paintedKerb, uvRepeat: 1.0)
            }
        }
        if let geometry = mesh.build() {
            levelRoot.addChildNode(SCNNode(geometry: geometry))
        }
        updateSignals(time: 0)
    }

    /// Moves each lit lamp to red/yellow/green for the given level time.
    func updateSignals(time: CGFloat) {
        guard let city = cityMap else { return }
        for index in signalHeads.indices {
            let head = signalHeads[index]
            let state: Int
            switch city.signal(at: head.node, horizontal: head.horizontal, time: time) {
            case .red: state = 0
            case .yellow: state = 1
            case .green: state = 2
            }
            guard state != head.state else { continue }
            if PerfSettings.benchmark && head.state >= 0 { FrameMonitor.shared.mark("signal") }
            head.lamp.position = head.slots[state]
            head.lamp.geometry?.materials = [World3D.signalMaterials[state]]
            signalHeads[index].state = state
        }
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

    /// Uploads all geometry (including far-distance car models that are not in the tree yet) and
    /// compiles their shaders before they first appear, so the first sighting does not stall a frame.
    /// `completion` runs on the main thread once everything is uploaded (or right away without a view).
    func warmUp(attempt: Int = 0, completion: (() -> Void)? = nil) {
        guard let renderer = renderer else {
            // The 3D view may not exist yet in the very first frame; try again shortly
            if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.warmUp(attempt: attempt + 1, completion: completion)
                }
            } else {
                completion?()
            }
            return
        }
        var objects: [Any] = [scene.rootNode] + World3D.signalMaterials
        if PerfSettings.optimized { objects += CarFactory.allGeometries + CarModels.allGeometries + TrafficVehicles.allGeometries }
        // Street trees and traffic lights, near and far meshes (their textures upload now too)
        for prop in Scenery.trees + World3D.signalTemplates {
            prop.enumerateHierarchy { node, _ in
                guard let geometry = node.geometry else { return }
                objects.append(geometry)
                objects += (geometry.levelsOfDetail ?? []).compactMap { $0.geometry }
            }
        }
        if cityMap != nil {
            objects += PedestrianModels.all + StreetProps.allGeometries
            World3D.policeTemplate?.enumerateHierarchy { node, _ in
                if let geometry = node.geometry { objects.append(geometry) }
            }
        }
        renderer.prepare(objects) { _ in
            DispatchQueue.main.async { completion?() }
        }
    }

    /// Builds the car models a race needs while the player is still in the menu, one per main-loop
    /// turn so the menu stays smooth. Anything not built yet is made on demand later.
    static func prewarmCars() {
        guard PerfSettings.optimized else { return }
        var jobs: [() -> Void] = []
        let saved = CarChoice.saved
        jobs.append { _ = CarModels.texturePaint(CarSpec.of(saved.model), saved.color) }

        jobs.append { _ = CarFactory.wheelTemplate }
        func next(_ index: Int) {
            guard index < jobs.count else { return }
            jobs[index]()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { next(index + 1) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { next(0) }
    }

    // MARK: Nitro pickups and speed cameras

    private static let pickupGeometry: (can: SCNGeometry, ring: SCNGeometry) = {
        let can = SCNCylinder(radius: 0.42, height: 1.1)
        can.radialSegmentCount = 14
        let label = Mat.pbr(.white, metal: 0.6, rough: 0.25)
        label.diffuse.contents = CityArt.nitroCan
        label.emission.contents = UIColor(red: 0.05, green: 0.25, blue: 0.55, alpha: 1)
        let cap = Mat.pbr(UIColor(white: 0.85, alpha: 1), metal: 0.9, rough: 0.2)
        can.materials = [label, cap, cap]
        let ring = SCNPlane(width: 3.2, height: 3.2)
        let glow = SCNMaterial()
        glow.lightingModel = .constant
        glow.diffuse.contents = CarArt.glowParticle()
        glow.multiply.contents = UIColor(red: 0.3, green: 0.75, blue: 1.0, alpha: 1)
        glow.blendMode = .add
        glow.writesToDepthBuffer = false
        ring.materials = [glow]
        return (can, ring)
    }()

    /// A person in the city (geometry set by the pedestrian system each frame).
    func addPedestrianNode() -> SCNNode {
        let node = SCNNode()
        levelRoot.addChildNode(node)
        return node
    }

    /// A spinning, bobbing nitro canister with a glow on the road.
    func addNitroPickup(at point: CGPoint) -> SCNNode {
        let holder = SCNNode()
        holder.position = World3D.vec(point)
        let can = SCNNode(geometry: World3D.pickupGeometry.can)
        can.position.y = 1.2
        can.eulerAngles.z = 0.35
        can.castsShadow = false
        let spin = SCNNode()
        spin.addChildNode(can)
        spin.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 1.8)))
        spin.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.35, z: 0, duration: 0.6), .moveBy(x: 0, y: -0.35, z: 0, duration: 0.6)])))
        holder.addChildNode(spin)
        let ring = SCNNode(geometry: World3D.pickupGeometry.ring)
        ring.eulerAngles.x = -Float.pi / 2
        ring.position.y = 0.05
        ring.castsShadow = false
        holder.addChildNode(ring)
        levelRoot.addChildNode(holder)
        return holder
    }

    /// Speed camera on a pole at the curb; returns the flash node (shown briefly when it fires).
    func addSpeedCamera(at point: CGPoint, lookingAlongX: Bool) -> SCNNode {
        let holder = SCNNode()
        holder.position = World3D.vec(point)
        if !lookingAlongX { holder.eulerAngles.y = Float.pi / 2 }
        let pole = SCNBox(width: 0.18, height: 4.2, length: 0.18, chamferRadius: 0.02)
        pole.materials = [Mat.pbr(UIColor(white: 0.3, alpha: 1), metal: 0.6, rough: 0.4)]
        let poleNode = SCNNode(geometry: pole)
        poleNode.position.y = 2.1
        holder.addChildNode(poleNode)
        let housing = SCNBox(width: 0.9, height: 0.55, length: 0.6, chamferRadius: 0.06)
        housing.materials = [Mat.pbr(UIColor(red: 0.95, green: 0.8, blue: 0.1, alpha: 1), metal: 0.2, rough: 0.5)]
        let housingNode = SCNNode(geometry: housing)
        housingNode.position.y = 4.3
        holder.addChildNode(housingNode)
        let sign = SCNBox(width: 0.06, height: 1.0, length: 1.0, chamferRadius: 0)
        let signMaterial = Mat.lambert(CityArt.radarSign)
        sign.materials = [signMaterial]
        for side: Float in [-1, 1] {
            let node = SCNNode(geometry: sign)
            node.position = SCNVector3(side * 0.12, 3.2, 0)
            holder.addChildNode(node)
        }
        let flash = SCNNode(geometry: SCNSphere(radius: 0.5))
        flash.geometry?.materials = [Mat.glow(UIColor.white)]
        flash.position.y = 4.3
        flash.scale = SCNVector3(0.001, 0.001, 0.001)
        flash.castsShadow = false
        holder.addChildNode(flash)
        levelRoot.addChildNode(holder)
        return flash
    }

    /// Benchmark helper: saves what the 3D view shows to Documents/<name>.png.
    func saveSnapshot(named name: String) {
        guard let image = renderer?.snapshot(), let data = image.pngData(),
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? data.write(to: folder.appendingPathComponent(name + ".png"))
    }

    /// Full detail only for parked cars near the player (world units).
    @discardableResult
    func updateDetail(around point: CGPoint) -> Int {
        guard !isSweeping else { return 0 }
        let range = PerfSettings.carDetailDistance * 10
        var changed = 0
        for entry in parkedCars3D {
            if entry.car.setDetail(abs(entry.position.x - point.x) < range && abs(entry.position.y - point.y) < range) { changed += 1 }
        }
        return changed
    }

    /// The floating marker hides while the car is in its bay, and the bay's glowing outline turns
    /// from the player's colour to green as the hold fills.
    func setTargetMarker(hidden: Bool, progress: CGFloat) {
        if let arrow = arrowNode, arrow.isHidden != hidden {
            arrow.isHidden = hidden
        }
        guard let neon = myNeon, let material = neon.geometry?.firstMaterial, let images = myNeonImages else { return }
        let p = max(0, min(1, progress))
        let holding = p > 0
        if holding != myNeonHolding {
            myNeonHolding = holding
            material.diffuse.contents = holding ? images.green : images.normal
        }
        neon.scale = SCNVector3(1 + 0.05 * Float(p), 1 + 0.05 * Float(p), 1)
    }
    private var myNeonImages: (normal: UIImage, green: UIImage)?
    private var myNeonHolding = false

    func markParked() {
        arrowNode?.isHidden = true
        myNeon?.removeAllActions()
        myNeon?.opacity = 1
        if let material = myNeon?.geometry?.firstMaterial {
            material.multiply.contents = UIColor(red: 0.5, green: 1.0, blue: 0.6, alpha: 1)
        }
    }

    /// Skid marks come from a fixed pool made with the level (no new nodes or shadow casters
    /// while racing; creating them stalled the first corner).
    private var skidPool: [SCNNode] = []
    private var skidNext = 0

    private func buildSkidPool() {
        skidPool.removeAll()
        skidNext = 0
        for _ in 0..<160 {
            let mark = SCNNode(geometry: skidGeometry)
            mark.eulerAngles.x = -Float.pi / 2
            mark.scale = SCNVector3(0.001, 0.001, 0.001)
            mark.castsShadow = false
            fxRoot.addChildNode(mark)
            skidPool.append(mark)
        }
    }

    func addSkid(at point: CGPoint) {
        if PerfSettings.benchmark { FrameMonitor.shared.mark("skid") }
        guard !skidPool.isEmpty else { return }
        let mark = skidPool[skidNext]
        skidNext = (skidNext + 1) % skidPool.count
        mark.removeAllActions()
        mark.position = World3D.vec(point, y: 0.015)
        mark.scale = SCNVector3(1, 1, 1)
        mark.opacity = 1
        mark.runAction(.sequence([.wait(duration: 3), .fadeOut(duration: 2), .scale(to: 0.001, duration: 0)]))
    }

    var isSweeping: Bool { sweepClock >= 0 }
    /// The tour has shown the map from above and both rings around the start once.
    var sweepComplete: Bool { sweepClock < 0 || sweepClock >= 3 * 1.2 + 0.1 }
}

/// 0 below `a`, 1 above `b`, smooth in between.
func easeStep(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = max(0, min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}

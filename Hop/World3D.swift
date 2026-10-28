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

    /// Rim colour: the wheels get their own rim material (one per car).
    private var rimMaterial: SCNMaterial?
    func setRim(_ color: UIColor) {
        if rimMaterial == nil {
            let material = CarModels.rim.copy() as! SCNMaterial
            rimMaterial = material
            for spinner in spinNodes {
                spinner.enumerateHierarchy { node, _ in
                    guard node.name == "rim", let geometry = node.geometry?.copy() as? SCNGeometry else { return }
                    geometry.materials = [material]
                    node.geometry = geometry
                }
            }
        }
        rimMaterial?.diffuse.contents = color
    }

    /// Swaps the paint material only (no new geometry, no new shader).
    func setPaint(_ color: UIColor) {
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

        // Traffic and parked cars: Kenney vehicles
        if style != .racer, PerfSettings.optimized,
           let vehicle = forcedVehicle.flatMap({ KenneyCatalog.all[$0] }) ?? TrafficVehicles.pick(variety &* 31 &+ style.rawValue),
           let template = TrafficVehicles.body(vehicle.id) {
            if parked {
                if let flat = TrafficVehicles.parked(vehicle) { body.addChildNode(flat.clone()) }
                return
            }
            body.addChildNode(template.clone())
            var lights: [SCNNode] = []
            let tailX = vehicle.rear - 0.01
            for z in [vehicle.width * 0.3, -vehicle.width * 0.3] {
                lights.append(CarFactory.box(0.05, 0.14, 0.3, 0.02, brakeMaterial, at: SCNVector3(tailX, 0.72, z), to: body))
            }
            lights.append(CarFactory.box(0.05, 0.08, 0.22, 0.02, reverseMaterial, at: SCNVector3(tailX, 0.55, 0), to: body))
            for light in lights { light.castsShadow = false }
            detailNodes += lights
            if let wheelModel = TrafficVehicles.wheel(vehicle.id) {
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

        scene.background.contents = CityArt.sky
        scene.fogColor = UIColor(red: 0.84, green: 0.90, blue: 0.97, alpha: 1)
        scene.fogStartDistance = 70
        scene.fogEndDistance = 200
        scene.lightingEnvironment.contents = CityArt.sky
        scene.lightingEnvironment.intensity = 1.1
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
    private var cinematicShotB = false
    private var shotAEye = SIMD3<Float>(0, 0, 0)
    private var celebrationPoint = SCNVector3Zero

    /// Shot A: a low camera past the finish line watches the car come in (slow motion is applied by
    /// the game), with a shallow depth of field.
    func startFinishCinematic(at position: CGPoint, heading: CGFloat, finishLine: CGPoint) {
        cinematicActive = true
        cinematicShotB = false
        cinematicTime = 0
        let p = World3D.vec(position)
        let forward = SIMD3<Float>(cos(Float(heading)), 0, -sin(Float(heading)))
        let side = SIMD3<Float>(sin(Float(heading)), 0, cos(Float(heading)))
        shotAEye = SIMD3<Float>(p.x, p.y, p.z) + forward * 16 + side * 3.4 + SIMD3<Float>(0, 0.75, 0)
        celebrationPoint = World3D.vec(finishLine, y: 6.4)
        // Only the lens changes: post-processing (depth of field, HDR, bloom) would make the GPU
        // rebuild its pipelines mid-frame and stall
        cameraNode.camera?.fieldOfView = 38
    }

    /// Shot B: hard cut to an orbit around the car, fireworks, confetti and a graded, glowing image.
    func celebrate() {
        cinematicShotB = true
        cinematicTime = 0
        let toCamera = shotAEye - cameraFocus
        cinematicAngle = atan2(-toCamera.z, toCamera.x) + 0.6
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
            cinematicAngle += Float(dt) * (0.9 - min(cinematicTime, 2.5) * 0.25)
            cameraFocus += (focus - cameraFocus) * min(1, Float(dt) * 8)
            let radius = 10 - min(cinematicTime, 2) * 1.6
            let height = 2.2 + sin(min(cinematicTime, 3) * 0.6) * 1.6
            let eye = cameraFocus + SIMD3<Float>(cos(cinematicAngle) * radius, height, -sin(cinematicAngle) * radius)
            cameraNode.simdPosition = eye
            cameraNode.simdLook(at: cameraFocus + SIMD3<Float>(0, 0.9, 0), up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
            cameraNode.camera?.focusDistance = CGFloat(radius)
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
        switch newWeather {
        case .day:
            scene.background.contents = CityArt.sky
            scene.lightingEnvironment.contents = CityArt.sky
            scene.lightingEnvironment.intensity = 1.1
            scene.fogColor = UIColor(red: 0.84, green: 0.90, blue: 0.97, alpha: 1)
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
            // Storm light: dark, cold, misty; the wet street catches every light
            scene.background.contents = CityArt.rainSky
            scene.lightingEnvironment.contents = CityArt.rainSky
            scene.lightingEnvironment.intensity = 1.15
            scene.fogColor = UIColor(red: 0.30, green: 0.34, blue: 0.40, alpha: 1)
            scene.fogStartDistance = 18
            scene.fogEndDistance = 120
            sunLight.intensity = 380
            sunLight.color = UIColor(red: 0.78, green: 0.84, blue: 0.95, alpha: 1)
            ambientLight.intensity = 300
            ambientLight.color = UIColor(red: 0.62, green: 0.69, blue: 0.82, alpha: 1)
        }
        lampPools?.isHidden = !night
        // Wet asphalt: darker and glossy, with puddles and rain rings (World3D.wetRoadShader)
        for material in roadMaterials {
            material.roughness.intensity = wet ? 0.45 : 1
            material.diffuse.intensity = wet ? 0.72 : 1
            material.shaderModifiers = wet ? [.surface: World3D.wetRoadShader] : nil
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

    /// Rain around the camera: a near layer of fast, thin streaks and a far, denser curtain.
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
            system.stretchFactor = 0.022
            system.particleColor = UIColor(red: 0.74, green: 0.80, blue: 0.90, alpha: alpha)
            system.particleColorVariation = SCNVector4(0, 0, 0.08, 0.25)
            system.particleImage = CarArt.rainStreak()
            system.blendMode = .additive
            system.isLightingEnabled = false
            system.isAffectedByGravity = false
            system.loops = true
            return system
        }
        let node = SCNNode()
        node.position = SCNVector3(0, 13, -9)
        node.addParticleSystem(layer(birthRate: 1500, box: 22, size: 0.05, alpha: 0.42, speed: 30))
        let far = SCNNode()
        far.position = SCNVector3(0, 4, -26)
        far.addParticleSystem(layer(birthRate: 1700, box: 60, size: 0.09, alpha: 0.2, speed: 24))
        node.addChildNode(far)
        return node
    }

    /// Small drops bouncing up where the rain lands, in front of the camera.
    private static func makeSplashes() -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.birthRate = 700
        system.emitterShape = SCNPlane(width: 26, height: 26)
        system.particleLifeSpan = 0.22
        system.particleLifeSpanVariation = 0.08
        system.particleVelocity = 1.8
        system.particleVelocityVariation = 0.8
        system.emittingDirection = SCNVector3(0, 1, 0)
        system.spreadingAngle = 35
        system.particleSize = 0.035
        system.particleSizeVariation = 0.015
        system.particleColor = UIColor(red: 0.85, green: 0.9, blue: 1.0, alpha: 0.5)
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

    /// Polyfork's police cruiser (front along +z in the file), turned to face +x like every car.
    static let policeTemplate: SCNNode? = {
        guard let url = Bundle.main.url(forResource: "pf_police", withExtension: "usdz"),
              let scene = try? SCNScene(url: url, options: nil) else { return nil }
        let model = SCNNode()
        for child in scene.rootNode.childNodes { model.addChildNode(child) }
        model.eulerAngles.y = Float.pi / 2
        model.enumerateHierarchy { node, _ in
            node.castsShadow = node.name?.hasPrefix("wheel") == false
            for material in node.geometry?.materials ?? [] {
                material.lightingModel = .physicallyBased
                // The light bar flashes through its emission: set one now so the shader compiled
                // ahead of time is the one the chase uses
                material.emission.contents = UIColor.black
            }
        }
        let holder = SCNNode()
        holder.addChildNode(model)
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
            node = Car3D(color: .white, style: .sedan, vehicle: "police").node
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
        lampPools = nil
        if let city = level.city {
            buildCity(city, world: level.world)
            levelRoot.addChildNode(CityDecor.build(level: level, city: city))
        }
        // City rounds have their weather; a parking lot can be wet (a harder level)
        setWeather(level.city != nil || level.weather == .rain ? level.weather : .day)

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
            let material = World3D.asphaltMaterial(albedo: "road_albedo.jpg", normal: "road_normal.png", rough: "road_rough.jpg")
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
        let junctionMaterial = World3D.asphaltMaterial(albedo: "junction_albedo.jpg", normal: "junction_normal.png", rough: "junction_rough.jpg")
        roadMaterials.append(junctionMaterial)
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
            // Pavers: one texture tile is 2 x 2 m
            let sidewalk = Mat.lambert(CityArt.pavers)
            sidewalk.diffuse.wrapS = .repeat
            sidewalk.diffuse.wrapT = .repeat
            sidewalk.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(block.width / 20), Float(block.height / 20), 1)
            plane.materials = [sidewalk]
            let node = flat(plane, y: 0.08)
            let p = World3D.vec(CGPoint(x: block.midX, y: block.midY))
            node.position.x = p.x
            node.position.z = p.z
            ground.addChildNode(node)
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

    /// The traffic light model, read once (in the background at launch, see CarModels.preload).
    static let signalTemplate: SCNNode? = CarModels.load("signal")

    /// Lens centers of the traffic light model (game axes, from tools/convert_meshy_props.py),
    /// just in front of the glass: red, amber, green.
    static let signalLenses: [SIMD3<Float>] = [SIMD3(0.075, 4.248, 0), SIMD3(0.075, 3.896, 0), SIMD3(0.075, 3.522, 0)]
    /// The lit lens: a thin glowing disc (turned to face along the light's x).
    static let signalLensDisc: SCNGeometry = {
        let disc = SCNCylinder(radius: 0.125, height: 0.02)
        disc.radialSegmentCount = 16
        return disc
    }()

    private func buildStreetFurniture(_ city: CityMap, world: CGSize) {
        cityMap = city
        signalHeads.removeAll()
        let mesh = MeshBuilder()
        let poleMaterial = Mat.pbr(UIColor(white: 0.22, alpha: 1), metal: 0.6, rough: 0.45)
        let headMaterial = Mat.pbr(UIColor(white: 0.08, alpha: 1), metal: 0.2, rough: 0.6)
        let curbMaterial = Mat.pbr(UIColor(white: 0.82, alpha: 1), rough: 0.85)
        let lampGlow = Mat.glow(UIColor(red: 1.0, green: 0.92, blue: 0.75, alpha: 1))
        lampGlow.diffuse.intensity = 1.4
        let stopLine = Mat.lambert(UIColor(white: 0.95, alpha: 1))
        func box(_ c: SCNVector3, _ w: Float, _ h: Float, _ l: Float, _ m: SCNMaterial) {
            mesh.addBox(center: SIMD3(c.x, c.y, c.z), width: w, height: h, length: l, angle: 0, wall: m, roof: m,
                        wallRepeats: { _ in SIMD2(1, 1) })
        }
        let signalModel = World3D.signalTemplate
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
                // The lights of one intersection are merged (one draw call, still culled when off screen)
                let signalHolder = SCNNode()
                defer {
                    if !signalHolder.childNodes.isEmpty {
                        let merged = signalHolder.flattenedClone()
                        merged.castsShadow = false
                        levelRoot.addChildNode(merged)
                    }
                }
                for (offset, facing, horizontal, exists) in corners where exists {
                    let base = World3D.vec(CGPoint(x: center.x + offset.x, y: center.y + offset.y))
                    // Realistic traffic light model (Meshy AI, lenses face +x), turned to face traffic
                    let yaw = atan2(-facing.y, facing.x)
                    func place(_ local: SIMD3<Float>) -> SCNVector3 {
                        let c = cos(yaw), sn = sin(yaw)
                        return SCNVector3(base.x + local.x * c + local.z * sn, local.y, base.z - local.x * sn + local.z * c)
                    }
                    if let model = signalModel {
                        let copy = model.clone()
                        copy.position = SCNVector3(base.x, 0, base.z)
                        copy.eulerAngles.y = yaw
                        signalHolder.addChildNode(copy)
                    } else {
                        box(base, 0.16, 4.3, 0.16, poleMaterial)
                        box(SCNVector3(base.x, 3.35, base.z), 0.42, 1.25, 0.42, headMaterial)
                    }
                    let slots = World3D.signalLenses.map { place($0) }
                    // Own geometry copy: each lamp gets its own color
                    let lamp = SCNNode(geometry: World3D.signalLensDisc.copy() as? SCNGeometry)
                    lamp.eulerAngles = SCNVector3(0, yaw, Float.pi / 2)
                    lamp.castsShadow = false
                    levelRoot.addChildNode(lamp)
                    signalHeads.append((node, horizontal, lamp, slots, -1))
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


        // Raised curbs around every block
        for block in city.blocks {
            let edges: [(CGPoint, Float, Float)] = [
                (CGPoint(x: block.midX, y: block.minY), Float(block.width / 10), 0.3),
                (CGPoint(x: block.midX, y: block.maxY), Float(block.width / 10), 0.3),
                (CGPoint(x: block.minX, y: block.midY), 0.3, Float(block.height / 10)),
                (CGPoint(x: block.maxX, y: block.midY), 0.3, Float(block.height / 10))
            ]
            for (point, w, l) in edges {
                box(World3D.vec(point), w, 0.16, l, curbMaterial)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { next(0) }
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

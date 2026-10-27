import SceneKit
import UIKit

// MARK: - Loose street props

/// Traffic cones, barrels and trash bins that fly, tumble and bounce when a car hits them.
/// A light hand-written simulation (gravity, bounce, friction) on plain nodes: no physics engine,
/// nothing is created during play.
final class StreetProps {
    private struct Prop {
        let kind: Int
        var position: CGPoint
        var height: CGFloat = 0           // world units above the ground
        var velocity = CGVector.zero
        var climb: CGFloat = 0            // vertical speed (units/s)
        var yaw: CGFloat
        var tumble: CGFloat = 0           // rotation around the axis across the motion
        var tumbleSpeed: CGFloat = 0
        var spinSpeed: CGFloat = 0
        var moving = false
        var lastHit: CGFloat = -10
        let node: SCNNode
    }

    private var props: [Prop] = []
    private var clock: CGFloat = 0
    static let radius: [CGFloat] = [4, 6, 6]   // world units

    init(defs: [PropDef], parent: SCNNode) {
        for (index, def) in defs.enumerated() {
            guard let template = StreetProps.templates[safe: def.kind] else { continue }
            let node = template.clone()
            let yaw = CGFloat((index * 37) % 360) * CGFloat.pi / 180
            node.position = World3D.vec(def.position)
            node.eulerAngles.y = Float(yaw)
            node.castsShadow = false
            parent.addChildNode(node)
            props.append(Prop(kind: def.kind, position: def.position, yaw: yaw, node: node))
        }
    }

    /// Steps the props; `hitters` are the cars (position, velocity, size along/across).
    /// Returns how many props the player (hitter 0) knocked this step.
    func step(_ dt: CGFloat, hitters: [(position: CGPoint, velocity: CGVector, heading: CGFloat)]) -> Int {
        clock += dt
        var knockedByPlayer = 0
        for index in props.indices {
            var p = props[index]
            // Hits: inside a car's footprint (rough box) while it moves
            for (h, hitter) in hitters.enumerated() {
                let dx = p.position.x - hitter.position.x, dy = p.position.y - hitter.position.y
                if abs(dx) > 40 || abs(dy) > 40 { continue }
                let along = dx * cos(hitter.heading) + dy * sin(hitter.heading)
                let across = -dx * sin(hitter.heading) + dy * cos(hitter.heading)
                let r = StreetProps.radius[p.kind]
                guard abs(along) < 22 + r, abs(across) < 11 + r else { continue }
                let speed = hypot(hitter.velocity.dx, hitter.velocity.dy)
                guard speed > 12, clock - p.lastHit > 0.25 else { continue }
                p.lastHit = clock
                // Thrown ahead of the car and away from its center line
                let side: CGFloat = across >= 0 ? 1 : -1
                let push = speed * (p.kind == 0 ? 1.15 : 0.9)
                let sideways = speed * 0.35 * side
                p.velocity = CGVector(dx: hitter.velocity.dx / max(speed, 1) * push - sin(hitter.heading) * sideways,
                                      dy: hitter.velocity.dy / max(speed, 1) * push + cos(hitter.heading) * sideways)
                p.climb = 18 + speed * (p.kind == 0 ? 0.32 : 0.22)
                p.tumbleSpeed = (p.kind == 0 ? 9 : 6) * (Bool.random() ? 1 : -1)
                p.spinSpeed = CGFloat.random(in: -6...6)
                p.moving = true
                if h == 0 { knockedByPlayer += 1 }
            }
            if p.moving {
                p.position.x += p.velocity.dx * dt
                p.position.y += p.velocity.dy * dt
                p.height += p.climb * dt
                p.climb -= 98 * dt                  // 9.8 m/s² in world units
                p.tumble += p.tumbleSpeed * dt
                p.yaw += p.spinSpeed * dt
                if p.height <= 0 {
                    p.height = 0
                    if abs(p.climb) > 12 {
                        p.climb = -p.climb * 0.35   // bounce
                        p.velocity = CGVector(dx: p.velocity.dx * 0.6, dy: p.velocity.dy * 0.6)
                        p.tumbleSpeed *= 0.6
                    } else {
                        p.climb = 0
                        let friction = exp(-dt * 4)
                        p.velocity = CGVector(dx: p.velocity.dx * friction, dy: p.velocity.dy * friction)
                        p.tumbleSpeed *= friction
                        p.spinSpeed *= friction
                        // Settle lying down or upright, whichever is closer
                        let quarter = CGFloat.pi / 2
                        let target = (p.tumble / quarter).rounded() * quarter
                        p.tumble += (target - p.tumble) * min(1, dt * 6)
                        if hypot(p.velocity.dx, p.velocity.dy) < 1.5 && abs(p.tumbleSpeed) < 0.3 { p.moving = false }
                    }
                }
                let lift = p.height / 10 + (abs(sin(p.tumble)) * (p.kind == 0 ? 0.18 : 0.3))
                p.node.position = World3D.vec(p.position, y: lift)
                p.node.eulerAngles = SCNVector3(Float(p.tumble), Float(p.yaw), 0)
            }
            props[index] = p
        }
        return knockedByPlayer
    }

    static var allGeometries: [SCNGeometry] {
        templates.compactMap { $0.geometry }
    }

    // MARK: Models (procedural for now, flattened to one node each)

    static let templates: [SCNNode] = [cone(), barrel(), bin()]

    private static func flat(_ build: (SCNNode) -> Void) -> SCNNode {
        let holder = SCNNode()
        build(holder)
        return holder.flattenedClone()
    }

    private static func cone() -> SCNNode {
        flat { holder in
            let orange = Mat.pbr(UIColor(red: 1.0, green: 0.38, blue: 0.05, alpha: 1), rough: 0.55)
            let white = Mat.pbr(UIColor(white: 0.95, alpha: 1), rough: 0.4)
            let black = Mat.pbr(UIColor(white: 0.08, alpha: 1), rough: 0.8)
            let base = SCNBox(width: 0.42, height: 0.04, length: 0.42, chamferRadius: 0.03)
            base.materials = [black]
            let baseNode = SCNNode(geometry: base)
            baseNode.position.y = 0.02
            holder.addChildNode(baseNode)
            let body = SCNCone(topRadius: 0.035, bottomRadius: 0.17, height: 0.68)
            body.radialSegmentCount = 14
            body.materials = [orange]
            let bodyNode = SCNNode(geometry: body)
            bodyNode.position.y = 0.38
            holder.addChildNode(bodyNode)
            let band = SCNCone(topRadius: 0.095, bottomRadius: 0.118, height: 0.12)
            band.radialSegmentCount = 14
            band.materials = [white]
            let bandNode = SCNNode(geometry: band)
            bandNode.position.y = 0.47
            holder.addChildNode(bandNode)
        }
    }

    private static func barrel() -> SCNNode {
        flat { holder in
            let orange = Mat.pbr(UIColor(red: 1.0, green: 0.42, blue: 0.06, alpha: 1), rough: 0.5)
            let white = Mat.glow(UIColor(white: 0.92, alpha: 1))
            for (k, y) in [0.12, 0.34, 0.56, 0.78].enumerated() {
                let ring = SCNCylinder(radius: 0.3, height: 0.22)
                ring.radialSegmentCount = 16
                ring.materials = [k % 2 == 0 ? orange : white]
                let node = SCNNode(geometry: ring)
                node.position.y = Float(y)
                holder.addChildNode(node)
            }
            let top = SCNCylinder(radius: 0.26, height: 0.04)
            top.materials = [orange]
            let topNode = SCNNode(geometry: top)
            topNode.position.y = 0.91
            holder.addChildNode(topNode)
        }
    }

    private static func bin() -> SCNNode {
        flat { holder in
            let green = Mat.pbr(UIColor(red: 0.12, green: 0.35, blue: 0.2, alpha: 1), metal: 0.3, rough: 0.5)
            let lid = Mat.pbr(UIColor(white: 0.15, alpha: 1), rough: 0.6)
            let body = SCNCylinder(radius: 0.27, height: 0.82)
            body.radialSegmentCount = 14
            body.materials = [green]
            let bodyNode = SCNNode(geometry: body)
            bodyNode.position.y = 0.41
            holder.addChildNode(bodyNode)
            let cap = SCNCylinder(radius: 0.3, height: 0.06)
            cap.materials = [lid]
            let capNode = SCNNode(geometry: cap)
            capNode.position.y = 0.85
            holder.addChildNode(capNode)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Police chase

/// A police car that follows the player's own path (so it never cuts through buildings), a bit
/// faster than the player can drive without nitro. It catches the player when close enough, and
/// gives up after a while or when far behind.
final class PoliceChase {
    enum Outcome { case none, caught, escaped }

    let car: Car3D
    private var trail: [CGPoint]
    private var position: CGPoint
    private var heading: CGFloat
    private var speed: CGFloat = 0
    private var clock: CGFloat = 0
    private let lights: [SCNNode]
    private let red: SCNMaterial
    private let blue: SCNMaterial
    private(set) var finished = false
    let duration: CGFloat = 20

    init(car: Car3D, trail: [CGPoint]) {
        self.car = car
        self.trail = trail
        position = trail.first ?? .zero
        heading = 0
        if trail.count > 1 { heading = atan2(trail[1].y - trail[0].y, trail[1].x - trail[0].x) }
        red = Mat.glow(UIColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 1))
        blue = Mat.glow(UIColor(red: 0.15, green: 0.35, blue: 1.0, alpha: 1))
        let height = Float(KenneyCatalog.all["police"]?.height ?? 1.7)
        var bar: [SCNNode] = []
        for side: Float in [-1, 1] {
            let lamp = SCNNode(geometry: SCNBox(width: 0.32, height: 0.14, length: 0.42, chamferRadius: 0.04))
            lamp.position = SCNVector3(0, height + 0.08, side * 0.26)
            lamp.castsShadow = false
            car.node.addChildNode(lamp)
            bar.append(lamp)
        }
        lights = bar
    }

    /// Adds the player's latest position to the path the police car follows.
    func extend(_ point: CGPoint) {
        if let last = trail.last, last.distance(to: point) < 8 { return }
        trail.append(point)
    }

    /// Distance left along the trail to the player.
    var gap: CGFloat {
        var total: CGFloat = 0
        var from = position
        for p in trail {
            total += from.distance(to: p)
            from = p
        }
        return total
    }

    func step(_ dt: CGFloat, playerSpeed: CGFloat, player: CGPoint) -> Outcome {
        guard !finished else { return .none }
        clock += dt
        // Flashing light bar
        let phase = Int(clock * 7) % 2 == 0
        lights[0].geometry?.materials = [phase ? red : blue]
        lights[1].geometry?.materials = [phase ? blue : red]
        let target = clock < 1.2 ? 120 : max(playerSpeed * 1.08, 175)
        speed += (target - speed) * min(1, dt * 1.5)
        var move = speed * dt
        while move > 0, let next = trail.first {
            let d = position.distance(to: next)
            if d <= move {
                position = next
                trail.removeFirst()
                move -= d
            } else {
                let desired = atan2(next.y - position.y, next.x - position.x)
                heading += CGFloat.angleDelta(heading, desired) * min(1, dt * 8)
                position = CGPoint(x: position.x + (next.x - position.x) / d * move, y: position.y + (next.y - position.y) / d * move)
                move = 0
            }
        }
        car.update(position: position, heading: heading, steer: 0, braking: false)
        if position.distance(to: player) < 34 && clock > 1.0 {
            finished = true
            return .caught
        }
        if clock > duration || gap > 900 {
            finished = true
            return .escaped
        }
        return .none
    }
}

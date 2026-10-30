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
    static let radius: [CGFloat] = [4, 6, 6, 10]   // world units

    init(defs: [PropDef], parent: SCNNode) {
        for (index, def) in defs.enumerated() {
            guard let template = StreetProps.templates[safe: def.kind] else { continue }
            let node = template.clone()
            let yaw = def.yaw ?? CGFloat((index * 37) % 360) * CGFloat.pi / 180
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
                p.climb = 18 + speed * (p.kind == 0 ? 0.32 : (p.kind == 3 ? 0.18 : 0.22))
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
                let lift = p.height / 10 + (abs(sin(p.tumble)) * [0.18, 0.3, 0.3, 0.35][p.kind])
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

    /// Polyfork models (free low poly set, commercial use, no attribution; see README), with the
    /// procedural shapes as a fallback: cone, drum, wire bin, police barricade.
    static let templates: [SCNNode] = [
        model("pf_cone") ?? cone(),
        model("pf_drum") ?? barrel(),
        model("pf_basket") ?? bin(),
        model("pf_barricade") ?? barrel()
    ]

    /// A bundled USDZ prop (meters, y up, standing on y = 0) merged into one node.
    static func model(_ name: String) -> SCNNode? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz"),
              let scene = try? SCNScene(url: url, options: nil) else { return nil }
        let holder = SCNNode()
        for child in scene.rootNode.childNodes { holder.addChildNode(child) }
        let flat = holder.flattenedClone()
        flat.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] { material.lightingModel = .physicallyBased }
        }
        return flat
    }

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

/// A police car sent after the player for a crime. It sets off from an intersection some way off
/// and drives the streets to the player with its siren on; once close it sticks to the player's
/// own path (so it does not cut through buildings), a bit faster than the player can drive without
/// nitro. It catches the player when close enough and gives up after a while or when far behind.
/// The model is the Meshy police car (TrafficVehicles); its light bar flashes and its wheels turn.
final class PoliceChase {
    enum Outcome { case none, caught, escaped }
    /// Chasing; pulling over across the front of a caught car; driving away after letting it go.
    enum Mode { case chasing, pullingOver, leaving }
    private(set) var mode = Mode.chasing
    private var stopPose: (position: CGPoint, heading: CGFloat) = (.zero, 0)
    /// Beside the caught car: passed on the way to the stop when the stop is on its far side
    /// (straight there would cut through it).
    private var pullOverVia: CGPoint?
    private var leaveClock: CGFloat = 0

    let node: SCNNode
    private let map: CityMap
    private var waypoints: [CGPoint] = []
    private(set) var position: CGPoint
    private(set) var heading: CGFloat = 0
    private var speed: CGFloat = 0
    private var clock: CGFloat = 0
    private var planClock: CGFloat = 0
    private var spin: CGFloat = 0
    /// Smoothed point the cruiser closes in on (where the player is heading).
    private var aim: CGPoint?
    private var wheels: [SCNNode] = []
    private var redLamps: [SCNMaterial] = []
    private var blueLamps: [SCNMaterial] = []
    private(set) var finished = false
    /// Close behind the player (following its path) rather than still on the way.
    private(set) var pursuing = false
    private(set) var distance: CGFloat = 999
    var duration: CGFloat = 30

    init(node: SCNNode, map: CityMap, start: CGPoint) {
        self.node = node
        self.map = map
        position = start
        node.enumerateHierarchy { child, _ in
            if let name = child.name, name.hasPrefix("wheel") { self.wheels.append(child) }
            guard let geometry = child.geometry else { return }
            // The light bar materials, found by their colors (shared by every police car)
            for material in geometry.materials {
                guard let color = material.diffuse.contents as? UIColor else { continue }
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.getRed(&r, green: &g, blue: &b, alpha: &a)
                if b > 0.55 && r < 0.2 && g < 0.4 { self.blueLamps.append(material) }
                if r > 0.7 && g < 0.15 && b < 0.15 { self.redLamps.append(material) }
            }
        }
        node.position = World3D.vec(position)
    }

    /// Another crime during the chase: the police keeps at it longer.
    func extend() {
        duration = max(duration, clock + 25)
    }

    /// Flashing light bar: red and blue take turns.
    private func flashLights() {
        let redOn = Int(clock * 7) % 2 == 0
        for lamp in redLamps { lamp.emission.contents = redOn ? UIColor(red: 1, green: 0.1, blue: 0.08, alpha: 1) : UIColor.black }
        for lamp in blueLamps { lamp.emission.contents = redOn ? UIColor.black : UIColor(red: 0.15, green: 0.35, blue: 1, alpha: 1) }
    }

    /// The friend's police car in an online game: its pose arrives over the network and the car
    /// eases to it, with the light bar flashing and the wheels turning.
    func mirror(_ dt: CGFloat, to target: CGPoint, heading targetHeading: CGFloat, viewer: CGPoint) {
        clock += dt
        flashLights()
        let k = min(1, dt * 10)
        let before = position
        if position.distance(to: target) > 300 {
            position = target
        } else {
            position = CGPoint(x: position.x + (target.x - position.x) * k, y: position.y + (target.y - position.y) * k)
        }
        heading += CGFloat.angleDelta(heading, targetHeading) * k
        distance = position.distance(to: viewer)
        node.position = World3D.vec(position)
        node.eulerAngles.y = Float(heading)
        spin += position.distance(to: before) / 10 / 0.32
        for wheel in wheels { wheel.eulerAngles.x = Float(spin) }
    }

    /// Caught: the cruiser swings in diagonally across the front of the car (on the side it
    /// came from), nose in, boxing it in.
    func pullOver(player: CGPoint, heading playerHeading: CGFloat) {
        mode = .pullingOver
        let side: CGFloat = (cos(playerHeading) * (position.y - player.y) - sin(playerHeading) * (position.x - player.x)) >= 0 ? 1 : -1
        let ahead = CGPoint(x: player.x + cos(playerHeading) * 50 - sin(playerHeading) * 16 * side,
                            y: player.y + sin(playerHeading) * 50 + cos(playerHeading) * 16 * side)
        stopPose = (ahead, playerHeading + CGFloat.pi + side * 0.85)
        waypoints = []
        // Coming from behind, it goes round the car (beside it, on its side) instead of through it
        let forward = cos(playerHeading) * (position.x - player.x) + sin(playerHeading) * (position.y - player.y)
        pullOverVia = forward < 30
            ? CGPoint(x: player.x + cos(playerHeading) * 10 - sin(playerHeading) * 46 * side,
                      y: player.y + sin(playerHeading) * 10 + cos(playerHeading) * 46 * side)
            : nil
    }

    /// Let go: the cruiser backs off and drives away down the streets, then is gone.
    func driveOff(from player: CGPoint) {
        mode = .leaving
        leaveClock = 0
        // The farthest intersection makes a believable "back on patrol" route
        var far = position
        for x in map.xs { for y in map.ys where CGPoint(x: x, y: y).distance(to: player) > far.distance(to: player) { far = CGPoint(x: x, y: y) } }
        waypoints = Array(map.route(from: position, to: far).dropFirst())
        speed = 40
    }

    /// The pull-over and drive-off moves (no catching or escaping in these).
    private func stepScripted(_ dt: CGFloat, player: CGPoint) {
        clock += dt
        distance = position.distance(to: player)
        flashLights()
        let before = position
        switch mode {
        case .pullingOver:
            if let via = pullOverVia {
                if position.distance(to: via) < 18 {
                    pullOverVia = nil
                } else {
                    let toward = atan2(via.y - position.y, via.x - position.x)
                    speed += (min(200, 80 + position.distance(to: via) * 2) - speed) * min(1, dt * 6)
                    let move = min(position.distance(to: via), speed * dt)
                    position = CGPoint(x: position.x + cos(toward) * move, y: position.y + sin(toward) * move)
                    heading += CGFloat.angleDelta(heading, toward) * min(1, dt * 7)
                    break
                }
            }
            let d = position.distance(to: stopPose.position)
            let wanted = min(220, d * 3)
            speed += (wanted - speed) * min(1, dt * 6)
            let move = min(d, speed * dt)
            if d > 0.5 {
                let toward = atan2(stopPose.position.y - position.y, stopPose.position.x - position.x)
                position = CGPoint(x: position.x + cos(toward) * move, y: position.y + sin(toward) * move)
                // Faces where it goes while far, then turns into its stopping angle
                let face = d > 25 ? toward : stopPose.heading
                heading += CGFloat.angleDelta(heading, face) * min(1, dt * 7)
            } else {
                heading += CGFloat.angleDelta(heading, stopPose.heading) * min(1, dt * 7)
            }
        case .leaving:
            leaveClock += dt
            speed += (min(190, 60 + leaveClock * 70) - speed) * min(1, dt * 2)
            var move = speed * dt
            while move > 0, let next = waypoints.first {
                let d = position.distance(to: next)
                if d <= move { position = next; waypoints.removeFirst(); move -= d; continue }
                let desired = atan2(next.y - position.y, next.x - position.x)
                heading += CGFloat.angleDelta(heading, desired) * min(1, dt * 6)
                position = CGPoint(x: position.x + (next.x - position.x) / d * move, y: position.y + (next.y - position.y) / d * move)
                move = 0
            }
            if leaveClock > 4 || waypoints.isEmpty { finished = true }
        case .chasing:
            break
        }
        node.position = World3D.vec(position)
        node.eulerAngles.y = Float(heading)
        spin += position.distance(to: before) / 10 / 0.32
        for wheel in wheels { wheel.eulerAngles.x = Float(spin) }
    }

    /// The point `length` along the waypoints from the car.
    private func point(along length: CGFloat) -> CGPoint? {
        var remaining = length
        var from = position
        for next in waypoints {
            let d = from.distance(to: next)
            if d >= remaining, d > 0 {
                return CGPoint(x: from.x + (next.x - from.x) / d * remaining, y: from.y + (next.y - from.y) / d * remaining)
            }
            remaining -= d
            from = next
        }
        return waypoints.last
    }

    /// Never inside the player's car: pushed out the shortest way, and slowed hard when it was
    /// driving into it.
    func keepClear(of player: CGPoint, heading playerHeading: CGFloat) {
        let size = CGSize(width: Levels.carSize.width + 4, height: Levels.carSize.height + 3)
        let theirs = OBB(center: player, size: size, angle: playerHeading)
        let mine = OBB(center: position, size: size, angle: heading)
        guard let push = Traffic.penetration(theirs, mine) else { return }
        position = CGPoint(x: position.x + push.dx, y: position.y + push.dy)
        if cos(heading) * push.dx + sin(heading) * push.dy < 0 { speed *= 0.3 }
        node.position = World3D.vec(position)
    }

    /// `trail`: the player's recent positions, oldest first; `playerVelocity` lets the cruiser
    /// aim where the car is going rather than where it is (it cuts corners and comes alongside
    /// instead of trailing straight behind).
    func step(_ dt: CGFloat, player: CGPoint, playerSpeed: CGFloat, playerVelocity: CGVector = .zero, trail: [CGPoint]) -> Outcome {
        guard !finished else { return .none }
        if mode != .chasing {
            stepScripted(dt, player: player)
            return .none
        }
        clock += dt
        distance = position.distance(to: player)
        flashLights()

        // Where the player will be by the time we get there (at most a second ahead), smoothed so
        // the aim does not jump with every twitch of the player's steering
        let lead = min(1.0, distance / max(speed, 120))
        let predicted = CGPoint(x: player.x + playerVelocity.dx * lead, y: player.y + playerVelocity.dy * lead)
        if aim == nil || aim!.distance(to: predicted) > 400 { aim = predicted }
        aim = CGPoint(x: aim!.x + (predicted.x - aim!.x) * min(1, dt * 4), y: aim!.y + (predicted.y - aim!.y) * min(1, dt * 4))

        // Plan: along the streets while far, along the player's own path when close (both stay on
        // the road), and only in the last stretch straight at the player
        planClock -= dt
        if planClock <= 0 || waypoints.isEmpty {
            planClock = 0.4
            if distance > 220 {
                pursuing = false
                waypoints = Array(map.route(from: position, to: player).dropFirst())
            } else {
                pursuing = true
                if distance < 95 {
                    waypoints = [aim!]
                    planClock = 0.12
                } else if let nearest = trail.indices.min(by: { trail[$0].distance(to: position) < trail[$1].distance(to: position) }) {
                    waypoints = Array(trail[nearest...]) + [aim!]
                } else {
                    waypoints = [aim!]
                }
            }
        }
        if distance < 95, !waypoints.isEmpty { waypoints[waypoints.count - 1] = aim! }
        // Points already passed are dropped, so it never turns back for one
        while waypoints.count > 1, position.distance(to: waypoints[0]) < 26 { waypoints.removeFirst() }
        // It sets off already facing down its route
        if clock <= dt * 1.5, let first = waypoints.first, first.distance(to: position) > 1 {
            heading = atan2(first.y - position.y, first.x - position.x)
        }

        // Driven like a car (it used to slide straight at each point, sideways or backwards, with
        // the body turning after it): it steers at a point a little way along its path, turns no
        // tighter than its wheels allow at that speed and slows for the bend ahead, braking harder
        // than it accelerates. A point behind it means a wide U-turn, not a reverse.
        let lookAhead = max(45, min(130, speed * 0.55))
        let steerAt = point(along: lookAhead) ?? aim!
        let desired = atan2(steerAt.y - position.y, steerAt.x - position.x)
        let error = CGFloat.angleDelta(heading, desired)
        let maxYaw = min(2.6, max(speed, 40) / 70)
        heading += max(-maxYaw, min(maxYaw, error * 4)) * dt
        var target: CGFloat = clock < 1.0 ? 120 : (pursuing ? max(playerSpeed * 1.08, 175) : 210)
        target *= max(0.32, 1 - abs(error) / .pi * 1.4)
        speed += (target - speed) * min(1, dt * (target < speed ? 3.5 : 1.6))
        let travelled = speed * dt
        position = CGPoint(x: position.x + cos(heading) * travelled, y: position.y + sin(heading) * travelled)
        node.position = World3D.vec(position)
        node.eulerAngles.y = Float(heading)
        spin += travelled / 10 / 0.32
        for wheel in wheels { wheel.eulerAngles.x = Float(spin) }
        // Caught as it comes up against the car (it used to need its centre within the car)
        if distance < 52 && clock > 1.5 {
            finished = true
            return .caught
        }
        if clock > duration || (pursuing == false && clock > 8 && distance > 1300) {
            finished = true
            return .escaped
        }
        return .none
    }
}

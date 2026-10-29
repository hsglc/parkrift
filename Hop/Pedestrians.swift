import SceneKit
import UIKit
import simd

// MARK: - Simulation

/// People walking around the city blocks. Each one walks its own lane of the sidewalk ring
/// (two lanes, one per direction, so they pass each other), stops to look at shop windows, and at
/// corners either turns or crosses at the zebra crossing — but only on a red light for the cars,
/// with enough red time left to make it across. While crossing they watch the cars: they hurry
/// when one comes, jump aside at the last moment, and get knocked over (then stand up again)
/// if a car still hits them. A horn makes the nearby ones jump and look.
final class PedestrianSystem {
    enum State {
        case walking
        case browsing      // looking at a shop window
        case waiting       // at the curb, waiting for red
        case crossing
        case startled      // jumped at a horn or a near miss
        case fallen
        case angry         // shouting at the car after a scare or a knock
    }

    struct Person {
        var position: CGPoint
        var heading: CGFloat
        var state: State = .walking
        var waypoints: [CGPoint] = []
        /// +1 walks the ring counter-clockwise, -1 clockwise.
        var direction: Int
        var block: Int
        /// Ring corner (0...3) it walks towards.
        var corner: Int
        var outfit: Int
        var baseSpeed: CGFloat
        var timer: CGFloat = 0
        var stride: CGFloat = 0
        var hurry: CGFloat = 1
        var dodge: CGVector = .zero
        var dodgeTime: CGFloat = 0
        /// The crossing in progress: intersection and whether it crosses the east-west street.
        var crossingNode = -1
        var crossesHorizontal = false
        var afterCrossing: (block: Int, corner: Int) = (0, 0)
        var lastHit: CGFloat = -10
        /// Stop at the next waypoint to look at a shop window.
        var browseNext = false
        var resumeState: State = .walking
        /// Got a fright (a horn, a car brushing past): gets angry once it has passed.
        var scared = false
    }

    /// A car the people react to: position, velocity (world units/s), heading, and whether hits count.
    struct Threat {
        let position: CGPoint
        let velocity: CGVector
        let heading: CGFloat
        let local: Bool
    }

    private(set) var people: [Person] = []
    private let map: CityMap
    private let blocks: [CGRect]
    private var rng: SplitMix64
    private(set) var clock: CGFloat = 0

    static let walkSpeed: CGFloat = 13     // 1.3 m/s
    static let crossSpeed: CGFloat = 24    // brisk, 2.4 m/s

    init(map: CityMap, count: Int, seed: UInt64) {
        self.map = map
        self.blocks = map.blocks
        rng = SplitMix64(seed: seed)
        guard !blocks.isEmpty else { return }
        for _ in 0..<count {
            let block = rng.int(blocks.count)
            let direction = rng.unit() < 0.5 ? 1 : -1
            let corner = rng.int(4)
            let previous = (corner - direction + 4) % 4
            let a = cornerPoint(block: block, corner: previous, direction: direction)
            let b = cornerPoint(block: block, corner: corner, direction: direction)
            let t = rng.range(0.1, 0.9)
            let start = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            var person = Person(position: start, heading: atan2(b.y - a.y, b.x - a.x), direction: direction, block: block,
                                corner: corner, outfit: rng.int(PedestrianModels.outfitCount),
                                baseSpeed: PedestrianSystem.walkSpeed * rng.range(0.8, 1.2))
            person.waypoints = [b]
            people.append(person)
        }
    }

    /// Sidewalk lane: counter-clockwise walkers keep 2.0 m from the curb, clockwise ones 3.0 m.
    private func inset(_ direction: Int) -> CGFloat { direction > 0 ? 20 : 30 }

    /// Corner k of a block's ring: 0 = (minX, minY), 1 = (maxX, minY), 2 = (maxX, maxY), 3 = (minX, maxY).
    private func cornerPoint(block: Int, corner: Int, direction: Int) -> CGPoint {
        let r = blocks[block].insetBy(dx: inset(direction), dy: inset(direction))
        switch corner {
        case 0: return CGPoint(x: r.minX, y: r.minY)
        case 1: return CGPoint(x: r.maxX, y: r.minY)
        case 2: return CGPoint(x: r.maxX, y: r.maxY)
        default: return CGPoint(x: r.minX, y: r.maxY)
        }
    }

    private func blockIndex(_ i: Int, _ j: Int) -> Int? {
        guard i >= 0, j >= 0, i < map.cols - 1, j < map.rows - 1 else { return nil }
        return i * (map.rows - 1) + j
    }

    /// Grid position (i, j) of a block index.
    private func blockCell(_ block: Int) -> (Int, Int) { (block / (map.rows - 1), block % (map.rows - 1)) }

    /// The intersection next to a block corner, and which quadrant of it the block is in.
    private func node(of block: Int, corner: Int) -> (i: Int, j: Int, sx: CGFloat, sy: CGFloat) {
        let (bi, bj) = blockCell(block)
        switch corner {
        case 0: return (bi, bj, 1, 1)
        case 1: return (bi + 1, bj, -1, 1)
        case 2: return (bi + 1, bj + 1, -1, -1)
        default: return (bi, bj + 1, 1, -1)
        }
    }

    /// Corner index of the block in quadrant (sx, sy) of an intersection.
    private func cornerFacing(sx: CGFloat, sy: CGFloat) -> Int {
        switch (sx > 0, sy > 0) {
        case (true, true): return 0
        case (false, true): return 1
        case (false, false): return 2
        default: return 3
        }
    }

    /// True when the cars crossing this street have red for at least `seconds` from now.
    private func redFor(node: Int, horizontal: Bool, seconds: CGFloat) -> Bool {
        var t: CGFloat = 0
        while t <= seconds {
            if map.signal(at: node, horizontal: horizontal, time: clock + t) != .red { return false }
            t += 0.5
        }
        return true
    }

    /// Plans what to do on reaching the ring corner: turn along the ring, or cross a street.
    private func arrive(_ p: inout Person) {
        let here = node(of: p.block, corner: p.corner)
        var options: [(horizontal: Bool, block: Int)] = []
        let (bi, bj) = blockCell(p.block)
        _ = (bi, bj)
        // Across the north-south street (cars on it run vertically)
        let ni = here.sx > 0 ? here.i - 1 : here.i
        let nj = here.sy > 0 ? here.j : here.j - 1
        if let other = blockIndex(ni, nj) { options.append((false, other)) }
        // Across the east-west street
        let mi = here.sx > 0 ? here.i : here.i - 1
        let mj = here.sy > 0 ? here.j - 1 : here.j
        if let other = blockIndex(mi, mj) { options.append((true, other)) }

        if !options.isEmpty && rng.unit() < 0.45 {
            let pick = options[rng.int(options.count)]
            let cx = map.xs[here.i], cy = map.ys[here.j]
            let d = inset(p.direction)
            if pick.horizontal {
                // Along the east/west arm at x = cx ± 11.4 m, from one curb to the other
                let x = cx + here.sx * 114
                p.waypoints = [CGPoint(x: x, y: cy + here.sy * 100), CGPoint(x: x, y: cy - here.sy * 100),
                               CGPoint(x: cx + here.sx * (100 + d), y: cy - here.sy * (100 + d))]
                p.afterCrossing = (pick.block, cornerFacing(sx: here.sx, sy: -here.sy))
            } else {
                let y = cy + here.sy * 114
                p.waypoints = [CGPoint(x: cx + here.sx * 100, y: y), CGPoint(x: cx - here.sx * 100, y: y),
                               CGPoint(x: cx - here.sx * (100 + d), y: cy + here.sy * (100 + d))]
                p.afterCrossing = (pick.block, cornerFacing(sx: -here.sx, sy: here.sy))
            }
            p.crossingNode = map.node(here.i, here.j)
            p.crossesHorizontal = pick.horizontal
            p.state = .walking   // walks to the curb first, then waits
            return
        }
        // Keep going around the block, sometimes stopping at a shop window on the way
        p.corner = (p.corner + p.direction + 4) % 4
        let target = cornerPoint(block: p.block, corner: p.corner, direction: p.direction)
        if rng.unit() < 0.3 {
            let t = rng.range(0.25, 0.75)
            p.waypoints = [CGPoint(x: p.position.x + (target.x - p.position.x) * t, y: p.position.y + (target.y - p.position.y) * t), target]
            p.browseNext = true
        } else {
            p.waypoints = [target]
        }
    }

    /// Walks on to the next corner of the current block.
    private func continueRing(_ p: inout Person) {
        p.corner = (p.corner + p.direction + 4) % 4
        p.waypoints = [cornerPoint(block: p.block, corner: p.corner, direction: p.direction)]
    }

    /// People standing on the road right now (cars should stop for them).
    var onRoad: [CGPoint] {
        people.compactMap { person in
            switch person.state {
            case .crossing: return person.position
            case .startled, .fallen, .angry: return isOnRoad(person.position) ? person.position : nil
            default: return nil
            }
        }
    }

    private func isOnRoad(_ p: CGPoint) -> Bool {
        map.xs.contains { abs($0 - p.x) < CityMap.roadHalf } || map.ys.contains { abs($0 - p.y) < CityMap.roadHalf }
    }

    /// Advances everyone. Returns how many people the local player's car knocked over this step.
    func step(_ dt: CGFloat, threats: [Threat], horn: CGPoint?) -> Int {
        clock += dt
        var knocked = 0
        for index in people.indices {
            var p = people[index]
            defer { people[index] = p }

            // A horn nearby: jump and look at the car
            if let horn = horn, p.state != .fallen, p.position.distance(to: horn) < 160 {
                if p.state == .crossing {
                    p.hurry = 1.5
                } else if p.state != .startled && p.state != .angry {
                    p.resumeState = p.state
                    p.state = .startled
                    p.timer = 0.9
                    p.scared = true
                    p.heading = atan2(horn.y - p.position.y, horn.x - p.position.x)
                }
            }

            // Cars: hits and near misses (only off the sidewalk: cars cannot get onto it)
            if p.state != .fallen && isOnRoad(p.position) {
                for threat in threats {
                    let speed = hypot(threat.velocity.dx, threat.velocity.dy)
                    let dx = p.position.x - threat.position.x, dy = p.position.y - threat.position.y
                    let along = dx * cos(threat.heading) + dy * sin(threat.heading)
                    let across = -dx * sin(threat.heading) + dy * cos(threat.heading)
                    // Inside the car's footprint (44 x 22 units) plus a little for the body
                    if abs(along) < 26 && abs(across) < 15 && speed > 12 && clock - p.lastHit > 2 {
                        p.lastHit = clock
                        p.resumeState = p.state == .startled ? p.resumeState : p.state
                        p.state = .fallen
                        p.timer = 2.9
                        p.heading = threat.heading + (across > 0 ? CGFloat.pi / 2 : -CGFloat.pi / 2)
                        p.dodge = CGVector(dx: cos(p.heading) * 60, dy: sin(p.heading) * 60)
                        p.dodgeTime = 0.35
                        if threat.local { knocked += 1 }
                        break
                    }
                    // Coming at me fast: jump aside at the last moment, hurry otherwise
                    let timeToReach = along < 0 && speed > 1 ? -along / speed : 99
                    if timeToReach < 0.7 && abs(across) < 22 && p.dodgeTime <= 0 {
                        let side: CGFloat = across >= 0 ? 1 : -1
                        let away = threat.heading + side * CGFloat.pi / 2
                        p.dodge = CGVector(dx: cos(away) * 75, dy: sin(away) * 75)
                        p.dodgeTime = 0.4
                        if p.state != .startled && p.state != .angry { p.resumeState = p.state }
                        p.state = .startled
                        p.timer = 1.0
                        p.scared = true
                    } else if timeToReach < 2.5 && abs(across) < 40 {
                        p.hurry = 1.6
                    }
                }
            }

            // Sideways jump in progress
            if p.dodgeTime > 0 {
                let step = min(dt, p.dodgeTime) / 0.4
                p.position.x += p.dodge.dx * step
                p.position.y += p.dodge.dy * step
                p.dodgeTime -= dt
            }

            switch p.state {
            case .fallen:
                p.timer -= dt
                if p.timer <= 0 {
                    // Back on their feet, and furious
                    p.state = .angry
                    p.timer = 2.6
                    p.scared = false
                }
                continue
            case .startled:
                p.timer -= dt
                if p.timer <= 0 {
                    if p.scared {
                        p.state = .angry
                        p.timer = 2.0
                        p.scared = false
                    } else {
                        p.state = p.resumeState == .startled ? .walking : p.resumeState
                    }
                }
                continue
            case .angry:
                p.timer -= dt
                if p.timer <= 0 {
                    let resume = p.resumeState
                    p.state = [.startled, .fallen, .angry].contains(resume) ? .walking : resume
                    p.hurry = 1.4
                }
                continue
            case .browsing:
                p.timer -= dt
                if p.timer <= 0 { p.state = .walking }
                continue
            case .waiting:
                // Wait for red for the cars on this street, with enough of it left to get across
                let needed = 200 / PedestrianSystem.crossSpeed * 0.85
                let nearbyFast = threats.contains { threat in
                    hypot(threat.velocity.dx, threat.velocity.dy) > 60 && threat.position.distance(to: p.position) < 140
                }
                if redFor(node: p.crossingNode, horizontal: p.crossesHorizontal, seconds: needed) && !nearbyFast {
                    p.state = .crossing
                }
                continue
            case .walking, .crossing:
                break
            }

            guard let target = p.waypoints.first else {
                if p.state == .crossing {
                    // Made it across: carry on around the new block
                    p.state = .walking
                    p.block = p.afterCrossing.block
                    p.corner = p.afterCrossing.corner
                    p.crossingNode = -1
                    p.hurry = 1
                    continueRing(&p)
                    continue
                }
                arrive(&p)
                continue
            }
            let dx = target.x - p.position.x, dy = target.y - p.position.y
            let distance = hypot(dx, dy)
            let speed = (p.state == .crossing ? PedestrianSystem.crossSpeed : p.baseSpeed) * p.hurry
            if distance < max(2, speed * dt) {
                p.position = target
                p.waypoints.removeFirst()
                if p.browseNext {
                    p.browseNext = false
                    // Shop window: turn to the building side and look a while
                    p.timer = rng.range(1.5, 4)
                    p.state = .browsing
                    p.heading += CGFloat(p.direction) * CGFloat.pi / 2
                } else if p.crossingNode >= 0 && p.state == .walking && p.waypoints.count == 2 {
                    // At the curb: face the street and wait for the light
                    p.state = .waiting
                    if let next = p.waypoints.first { p.heading = atan2(next.y - p.position.y, next.x - p.position.x) }
                }
                continue
            }
            p.heading = atan2(dy, dx)
            p.position.x += dx / distance * speed * dt
            p.position.y += dy / distance * speed * dt
            p.stride += speed * dt
            if p.state != .crossing { p.hurry = max(1, p.hurry - dt * 0.5) }
        }
        return knocked
    }
}

// MARK: - Models

/// People: two realistic characters made with Meshy (a woman and a man, 2K textures, about 14k
/// triangles), rigged by Meshy and animated with its clips: walk, run, idle, phone call, angry,
/// dodge and knock-down (tools/bake_meshy_people.py bakes every clip into frames of one shared
/// mesh). A person is one node whose geometry is swapped to animate: cheap for dozens of people,
/// no skinning on the device.
enum PedestrianModels {
    enum Clip: String, CaseIterable {
        case walk, run, idle, phone, angry, dodge, knockdown
    }

    static let characters = ["woman", "man"]
    static var outfitCount: Int { characters.count }
    /// World units walked per full cycle (two steps) of the walk and the run.
    static let walkCycle: CGFloat = 14
    static let runCycle: CGFloat = 30

    private struct Character {
        var frames: [Clip: [SCNGeometry]] = [:]
        var fps: [Clip: Float] = [:]
        var loops: [Clip: Bool] = [:]
    }

    private static let lock = NSLock()
    private static var loaded: [Int: Character] = [:]

    private static func character(_ index: Int) -> Character? {
        let k = abs(index) % characters.count
        lock.lock()
        defer { lock.unlock() }
        if let c = loaded[k] { return c }
        let c = load(characters[k])
        loaded[k] = c
        return c
    }

    /// The frame of `clip` at `time` seconds into it (looping clips wrap, the others hold their
    /// last frame).
    static func geometry(character index: Int, clip: Clip, time: CGFloat) -> SCNGeometry? {
        guard let c = character(index), let frames = c.frames[clip], !frames.isEmpty else { return nil }
        let raw = Int(floor(time * CGFloat(c.fps[clip] ?? 12)))
        let frame = (c.loops[clip] ?? true) ? ((raw % frames.count) + frames.count) % frames.count : max(0, min(frames.count - 1, raw))
        return frames[frame]
    }

    /// The frame at a point of a walking or running cycle (0...1), so the feet match the ground.
    static func geometry(character index: Int, clip: Clip, phase: CGFloat) -> SCNGeometry? {
        guard let c = character(index), let frames = c.frames[clip], !frames.isEmpty else { return nil }
        let p = phase - floor(phase)
        return frames[min(frames.count - 1, Int(p * CGFloat(frames.count)))]
    }

    /// Reads one character's baked clips: UVs and triangles shared by every frame, positions and
    /// normals (half floats) per frame.
    private static func load(_ name: String) -> Character {
        var result = Character()
        guard let url = Bundle.main.url(forResource: "ped_\(name)", withExtension: "bin"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count > 16,
              data.prefix(4) == Data("PED1".utf8) else { return result }
        func u32(_ o: Int) -> Int { Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }) }
        func f32(_ o: Int) -> Float { data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: Float.self) } }
        let vertexCount = u32(4), indexCount = u32(8), clipCount = u32(12)
        var o = 16
        let uvData = data.subdata(in: o..<(o + vertexCount * 8)); o += vertexCount * 8
        let indexData = data.subdata(in: o..<(o + indexCount * 4)); o += indexCount * 4
        let uvSource = SCNGeometrySource(data: uvData, semantic: .texcoord, vectorCount: vertexCount, usesFloatComponents: true,
                                         componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
        let element = SCNGeometryElement(data: indexData, primitiveType: .triangles, primitiveCount: indexCount / 3, bytesPerIndex: 4)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIImage(named: "ped_\(name)_diff.jpg")
        material.normal.contents = UIImage(named: "ped_\(name)_nor.jpg")
        material.roughness.contents = UIImage(named: "ped_\(name)_rough.jpg")
        material.metalness.contents = NSNumber(value: 0)
        for property in [material.diffuse, material.normal, material.roughness] {
            property.mipFilter = .linear
        }
        let frameBytes = vertexCount * 6
        for _ in 0..<clipCount {
            guard o < data.count else { break }
            let nameLength = Int(data[o]); o += 1
            let clipName = String(decoding: data.subdata(in: o..<(o + nameLength)), as: UTF8.self); o += nameLength
            let frameCount = u32(o); o += 4
            let fps = f32(o); o += 4
            let loop = data[o] != 0; o += 1
            var frames: [SCNGeometry] = []
            for _ in 0..<frameCount {
                guard o + frameBytes * 2 <= data.count else { break }
                // Half floats, converted once: positions and normals as float32 for SceneKit
                let positions = halfToFloat(data, offset: o, count: vertexCount * 3); o += frameBytes
                let normals = halfToFloat(data, offset: o, count: vertexCount * 3); o += frameBytes
                let vertexSource = SCNGeometrySource(data: positions, semantic: .vertex, vectorCount: vertexCount,
                                                     usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4,
                                                     dataOffset: 0, dataStride: 12)
                let normalSource = SCNGeometrySource(data: normals, semantic: .normal, vectorCount: vertexCount,
                                                     usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4,
                                                     dataOffset: 0, dataStride: 12)
                let geometry = SCNGeometry(sources: [vertexSource, normalSource, uvSource], elements: [element])
                geometry.materials = [material]
                frames.append(geometry)
            }
            if let clip = Clip(rawValue: clipName) {
                result.frames[clip] = frames
                result.fps[clip] = fps
                result.loops[clip] = loop
            }
        }
        return result
    }

    private static func halfToFloat(_ data: Data, offset: Int, count: Int) -> Data {
        var out = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: offset)
            for i in 0..<count {
                let h = UInt32(base.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self))
                // IEEE half to float (no Float16, so it builds for every architecture)
                let sign = (h & 0x8000) << 16
                var exponent = (h >> 10) & 0x1F
                var mantissa = h & 0x3FF
                let bits: UInt32
                if exponent == 0 {
                    if mantissa == 0 {
                        bits = sign
                    } else {
                        exponent = 1
                        while mantissa & 0x400 == 0 { mantissa <<= 1; exponent -= 1 }
                        mantissa &= 0x3FF
                        bits = sign | ((exponent &+ 112) << 23) | (mantissa << 13)
                    }
                } else if exponent == 31 {
                    bits = sign | 0x7F80_0000 | (mantissa << 13)
                } else {
                    bits = sign | ((exponent + 112) << 23) | (mantissa << 13)
                }
                out[i] = Float(bitPattern: bits)
            }
        }
        return out.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Loads both characters on a background thread (called at launch).
    static func preload() {
        DispatchQueue.global(qos: .utility).async {
            for index in characters.indices { _ = character(index) }
        }
    }

    static var all: [SCNGeometry] {
        characters.indices.flatMap { index -> [SCNGeometry] in
            guard let c = character(index) else { return [] }
            return Clip.allCases.flatMap { c.frames[$0] ?? [] }
        }
    }
}

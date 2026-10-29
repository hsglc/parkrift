import CoreGraphics
import Foundation

// MARK: - Deterministic random numbers (same map on both phones)

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE5_E4B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }
    mutating func range(_ low: CGFloat, _ high: CGFloat) -> CGFloat { low + (high - low) * unit() }
    mutating func int(_ upper: Int) -> Int { Int(next() % UInt64(max(upper, 1))) }
}

// MARK: - Street grid

/// A grid of two-lane streets. Roads run through `xs` (vertical streets) and `ys` (horizontal streets).
/// Cross-section of a street (distance from its center line): lanes 0…70, parking strip 70…100.
struct CityMap {
    let xs: [CGFloat]
    let ys: [CGFloat]

    static let roadHalf: CGFloat = 100
    static let laneOffset: CGFloat = 35
    static let stripOffset: CGFloat = 86
    static let slotLength: CGFloat = 64
    static let slotWidth: CGFloat = 30

    var cols: Int { xs.count }
    var rows: Int { ys.count }
    var nodeCount: Int { cols * rows }

    func node(_ i: Int, _ j: Int) -> Int { j * cols + i }
    func position(of node: Int) -> CGPoint { CGPoint(x: xs[node % cols], y: ys[node / cols]) }

    func neighbors(_ node: Int) -> [Int] {
        let i = node % cols
        let j = node / cols
        var result: [Int] = []
        if i > 0 { result.append(self.node(i - 1, j)) }
        if i < cols - 1 { result.append(self.node(i + 1, j)) }
        if j > 0 { result.append(self.node(i, j - 1)) }
        if j < rows - 1 { result.append(self.node(i, j + 1)) }
        return result
    }

    /// The street segment (between two intersections) closest to a point.
    func nearestSegment(to p: CGPoint) -> (a: Int, b: Int) {
        var bestRow = 0
        for j in 0..<rows where abs(p.y - ys[j]) < abs(p.y - ys[bestRow]) { bestRow = j }
        var bestCol = 0
        for i in 0..<cols where abs(p.x - xs[i]) < abs(p.x - xs[bestCol]) { bestCol = i }
        if abs(p.y - ys[bestRow]) <= abs(p.x - xs[bestCol]) {
            var i0 = 0
            for i in 0..<(cols - 1) where xs[i] <= p.x { i0 = i }
            return (node(i0, bestRow), node(i0 + 1, bestRow))
        } else {
            var j0 = 0
            for j in 0..<(rows - 1) where ys[j] <= p.y { j0 = j }
            return (node(bestCol, j0), node(bestCol, j0 + 1))
        }
    }

    /// Shortest drive along the streets: start point, intersections to pass, target.
    func route(from start: CGPoint, to target: CGPoint) -> [CGPoint] {
        let s = nearestSegment(to: start)
        let t = nearestSegment(to: target)
        if (s.a == t.a && s.b == t.b) || (s.a == t.b && s.b == t.a) {
            return [start, target]
        }
        var dist = [CGFloat](repeating: .greatestFiniteMagnitude, count: nodeCount)
        var previous = [Int](repeating: -1, count: nodeCount)
        var done = [Bool](repeating: false, count: nodeCount)
        dist[s.a] = start.distance(to: position(of: s.a))
        dist[s.b] = start.distance(to: position(of: s.b))
        for _ in 0..<nodeCount {
            var current = -1
            for n in 0..<nodeCount where !done[n] && (current < 0 || dist[n] < dist[current]) { current = n }
            guard current >= 0, dist[current] < .greatestFiniteMagnitude else { break }
            done[current] = true
            for next in neighbors(current) {
                let candidate = dist[current] + position(of: current).distance(to: position(of: next))
                if candidate < dist[next] {
                    dist[next] = candidate
                    previous[next] = current
                }
            }
        }
        let viaA = dist[t.a] + target.distance(to: position(of: t.a))
        let viaB = dist[t.b] + target.distance(to: position(of: t.b))
        var node = viaA <= viaB ? t.a : t.b
        var nodes: [CGPoint] = []
        while node >= 0 {
            nodes.append(position(of: node))
            node = previous[node]
        }
        return [start] + nodes.reversed() + [target]
    }

    /// Right-hand lane from intersection `a` to intersection `b`: entry and exit points.
    func lane(from a: Int, to b: Int) -> (start: CGPoint, end: CGPoint, heading: CGFloat) {
        let pa = position(of: a)
        let pb = position(of: b)
        let length = max(pa.distance(to: pb), 1)
        let d = CGPoint(x: (pb.x - pa.x) / length, y: (pb.y - pa.y) / length)
        let n = CGPoint(x: d.y, y: -d.x)
        let inset: CGFloat = 118
        let start = CGPoint(x: pa.x + d.x * inset + n.x * CityMap.laneOffset, y: pa.y + d.y * inset + n.y * CityMap.laneOffset)
        let end = CGPoint(x: pb.x - d.x * inset + n.x * CityMap.laneOffset, y: pb.y - d.y * inset + n.y * CityMap.laneOffset)
        return (start, end, atan2(d.y, d.x))
    }

    // MARK: Traffic lights

    enum Signal {
        case green
        case yellow
        case red
    }

    /// One 18 s cycle per intersection: east-west green 7 s, yellow 1.5 s, all red 0.5 s, then the
    /// same for north-south. Each intersection starts at its own offset so the city is not in sync.
    static let signalCycle: CGFloat = 18

    func signal(at node: Int, horizontal: Bool, time: CGFloat) -> Signal {
        let offset = CGFloat((node * 7919) % 180) / 10
        var t = (time + offset).truncatingRemainder(dividingBy: CityMap.signalCycle)
        if !horizontal { t = (t + CityMap.signalCycle / 2).truncatingRemainder(dividingBy: CityMap.signalCycle) }
        if t < 7 { return .green }
        if t < 8.5 { return .yellow }
        return .red
    }

    /// Building blocks between the streets (inner rectangles, without the street area).
    var blocks: [CGRect] {
        var result: [CGRect] = []
        for i in 0..<(cols - 1) {
            for j in 0..<(rows - 1) {
                result.append(CGRect(x: xs[i] + CityMap.roadHalf, y: ys[j] + CityMap.roadHalf,
                                     width: xs[i + 1] - xs[i] - CityMap.roadHalf * 2,
                                     height: ys[j + 1] - ys[j] - CityMap.roadHalf * 2))
            }
        }
        return result
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(other.x - x, other.y - y) }
}

struct BotStart {
    let from: Int
    let to: Int
    let progress: CGFloat
    let tint: Int
}

// MARK: - City rounds

extension Levels {
    static let cityBase = 100
    static let cityRounds = 5
    static let raceBase = 200
    static let raceRounds = 3
    /// Seconds added to the race time for every crash.
    static let crashPenalty: Double = 3

    /// City streets (park race and car race).
    static func isCity(_ index: Int) -> Bool { index >= cityBase }
    static func isRace(_ index: Int) -> Bool { index >= raceBase }

    static func level(_ index: Int) -> LevelDef {
        if isRace(index) { return city(round: index - raceBase, race: true) }
        if isCity(index) { return city(round: index - cityBase, race: false) }
        return all[max(0, min(index, all.count - 1))]
    }

    static func isLast(_ index: Int) -> Bool {
        if isRace(index) { return index >= raceBase + raceRounds - 1 }
        if isCity(index) { return index >= cityBase + cityRounds - 1 }
        return index >= all.count - 1
    }

    static func clamp(_ index: Int) -> Int {
        if isRace(index) { return min(index, raceBase + raceRounds - 1) }
        if isCity(index) { return min(index, cityBase + cityRounds - 1) }
        return max(0, min(index, all.count - 1))
    }

    static func title(_ index: Int) -> String {
        if isRace(index) { return Strings.raceRound(index - raceBase + 1, of: raceRounds) }
        if isCity(index) { return Strings.round(index - cityBase + 1, of: cityRounds) }
        return Strings.level(index + 1, of: all.count)
    }

    /// Race score: time plus a penalty per crash (lower is better).
    static func raceScore(time: Double, crashes: Int) -> Double {
        time + Double(crashes) * crashPenalty
    }

    /// A procedurally generated city with a street grid, parked cars, buildings and traffic.
    /// `race`: a finish line far away and dense traffic instead of a parking target.
    static func city(round: Int, race: Bool) -> LevelDef {
        var rng = SplitMix64(seed: (UInt64(round + 1) &* 0x2545_F491_4F6C_DD1D) ^ (race ? 0xA5A5_5A5A : 0))
        let map = CityMap(xs: [100, 900, 1700, 2500, 3300], ys: [100, 800, 1500, 2200])
        let worldSize = CGSize(width: 3400, height: 2300)

        // Parking slots along every curb that faces a block
        struct Slot { let center: CGPoint; let angle: CGFloat; let segment: Int; let side: Int; let index: Int }
        var slots: [Slot] = []
        var segments: [(a: Int, b: Int, horizontal: Bool, interior: Bool)] = []
        for j in 0..<map.rows {
            for i in 0..<(map.cols - 1) {
                segments.append((map.node(i, j), map.node(i + 1, j), true, j > 0 && j < map.rows - 1))
            }
        }
        for i in 0..<map.cols {
            for j in 0..<(map.rows - 1) {
                segments.append((map.node(i, j), map.node(i, j + 1), false, i > 0 && i < map.cols - 1))
            }
        }
        for (segmentIndex, segment) in segments.enumerated() {
            let pa = map.position(of: segment.a)
            let pb = map.position(of: segment.b)
            let length = pa.distance(to: pb)
            let count = Int((length - 2 * (CityMap.roadHalf + 30)) / CityMap.slotLength)
            for side in [-1, 1] {
                if segment.horizontal {
                    let j = segment.a / map.cols
                    if (side < 0 && j == 0) || (side > 0 && j == map.rows - 1) { continue }
                } else {
                    let i = segment.a % map.cols
                    if (side < 0 && i == 0) || (side > 0 && i == map.cols - 1) { continue }
                }
                for k in 0..<count {
                    let along = CityMap.roadHalf + 30 + CityMap.slotLength * (CGFloat(k) + 0.5)
                    let offset = CGFloat(side) * CityMap.stripOffset
                    let center = segment.horizontal
                        ? CGPoint(x: pa.x + along, y: pa.y + offset)
                        : CGPoint(x: pa.x + offset, y: pa.y + along)
                    slots.append(Slot(center: center, angle: segment.horizontal ? 0 : CGFloat.pi / 2,
                                      segment: segmentIndex, side: side, index: k))
                }
            }
        }

        func midpoint(_ index: Int) -> CGPoint {
            let s = segments[index]
            return CGPoint(x: (map.position(of: s.a).x + map.position(of: s.b).x) / 2,
                           y: (map.position(of: s.a).y + map.position(of: s.b).y) / 2)
        }
        func sideBySideStarts(on segmentIndex: Int, towards target: CGPoint?) -> [StartDef] {
            let seg = segments[segmentIndex]
            var fromNode = seg.a
            var toNode = seg.b
            if let target = target {
                if map.position(of: seg.a).distance(to: target) < map.position(of: seg.b).distance(to: target) {
                    fromNode = seg.b
                    toNode = seg.a
                }
            } else if rng.unit() < 0.5 {
                fromNode = seg.b
                toNode = seg.a
            }
            let lane = map.lane(from: fromNode, to: toNode)
            let mid = CGPoint(x: (lane.start.x + lane.end.x) / 2, y: (lane.start.y + lane.end.y) / 2)
            let normal = CGPoint(x: sin(lane.heading), y: -cos(lane.heading))
            return [StartDef(position: mid, heading: lane.heading),
                    StartDef(position: CGPoint(x: mid.x - normal.x * CityMap.laneOffset * 2, y: mid.y - normal.y * CityMap.laneOffset * 2),
                             heading: lane.heading)]
        }

        if race {
            // Start somewhere, finish line across a street far away
            let startSegment = rng.int(segments.count)
            var finishSegment = startSegment
            var bestDistance: CGFloat = 0
            for _ in 0..<30 {
                let candidate = rng.int(segments.count)
                let d = midpoint(candidate).distance(to: midpoint(startSegment))
                if d > bestDistance && (d < 2900 || bestDistance < 2000) {
                    bestDistance = d
                    finishSegment = candidate
                }
            }
            let finishSeg = segments[finishSegment]
            let finish = SpotDef(center: midpoint(finishSegment), size: CGSize(width: 50, height: 150),
                                 angle: finishSeg.horizontal ? 0 : CGFloat.pi / 2)
            let starts = sideBySideStarts(on: startSegment, towards: finish.center)

            var obstacles: [ObstacleDef] = []
            for slot in slots {
                guard slot.segment != finishSegment, rng.unit() < 0.12 else { continue }
                obstacles.append(ObstacleDef(kind: .car, center: slot.center, size: carSize,
                                             angle: slot.angle + (rng.unit() < 0.5 ? 0 : CGFloat.pi), tint: rng.int(6)))
            }
            var arcade = Levels.arcadeLayout(map: map, round: round, race: race)
            obstacles += buildings(map: map, rng: &rng, alleyBlocks: arcade.alleyBlocks, alleys: &arcade.alleys)

            var bots: [BotStart] = []
            var attempts = 0
            while bots.count < 56 && attempts < 900 {
                attempts += 1
                let index = rng.int(segments.count)
                let s = segments[index]
                let forward = rng.unit() < 0.5
                let start = BotStart(from: forward ? s.a : s.b, to: forward ? s.b : s.a, progress: rng.range(0.1, 0.9), tint: rng.int(6))
                let lane = map.lane(from: start.from, to: start.to)
                let p = CGPoint(x: lane.start.x + (lane.end.x - lane.start.x) * start.progress,
                                y: lane.start.y + (lane.end.y - lane.start.y) * start.progress)
                if starts.contains(where: { $0.position.distance(to: p) < 260 }) { continue }
                if bots.contains(where: { other in
                    let l = map.lane(from: other.from, to: other.to)
                    let q = CGPoint(x: l.start.x + (l.end.x - l.start.x) * other.progress, y: l.start.y + (l.end.y - l.start.y) * other.progress)
                    return q.distance(to: p) < 90
                }) { continue }
                bots.append(start)
            }
            var level = LevelDef(nameTR: "Yoğun Trafik", nameEN: "Rush Hour", starts: starts, spots: [finish, finish], obstacles: obstacles,
                                 world: worldSize, city: map, bots: bots, race: true)
            Levels.finishArcade(&level, arcade)
            return level
        }

        // Target: two facing slots on an interior street
        let interior = segments.indices.filter { segments[$0].interior }
        let targetSegment = interior[rng.int(interior.count)]
        let targetIndex = 2 + rng.int(4)
        guard let spotA = slots.first(where: { $0.segment == targetSegment && $0.side == -1 && $0.index == targetIndex }),
              let spotB = slots.first(where: { $0.segment == targetSegment && $0.side == 1 && $0.index == targetIndex }) else {
            return all[0]
        }
        let spotSize = CGSize(width: CityMap.slotLength, height: CityMap.slotWidth)
        let spots = [SpotDef(center: spotA.center, size: spotSize, angle: spotA.angle),
                     SpotDef(center: spotB.center, size: spotSize, angle: spotB.angle)]
        let targetCenter = CGPoint(x: (spotA.center.x + spotB.center.x) / 2, y: (spotA.center.y + spotB.center.y) / 2)

        // Start: a street far away from the target
        var startSegment = 0
        for _ in 0..<40 {
            let candidate = rng.int(segments.count)
            let s = segments[candidate]
            let mid = CGPoint(x: (map.position(of: s.a).x + map.position(of: s.b).x) / 2,
                              y: (map.position(of: s.a).y + map.position(of: s.b).y) / 2)
            startSegment = candidate
            if mid.distance(to: targetCenter) > 1500 { break }
        }
        let startSeg = segments[startSegment]
        let flip = rng.unit() < 0.5
        let fromNode = flip ? startSeg.b : startSeg.a
        let toNode = flip ? startSeg.a : startSeg.b
        let lane = map.lane(from: fromNode, to: toNode)
        let mid = CGPoint(x: (lane.start.x + lane.end.x) / 2, y: (lane.start.y + lane.end.y) / 2)
        let normal = CGPoint(x: sin(lane.heading), y: -cos(lane.heading))
        // Slot 0 in the right lane, slot 1 in the left lane, side by side
        let starts = [StartDef(position: mid, heading: lane.heading),
                      StartDef(position: CGPoint(x: mid.x - normal.x * CityMap.laneOffset * 2, y: mid.y - normal.y * CityMap.laneOffset * 2),
                               heading: lane.heading)]

        // Parked cars
        var obstacles: [ObstacleDef] = []
        for slot in slots {
            if slot.segment == targetSegment && slot.index == targetIndex { continue }
            let nearTarget = slot.segment == targetSegment && abs(slot.index - targetIndex) == 1
            let chance: CGFloat = nearTarget ? 0.75 : 0.2
            guard rng.unit() < chance else { continue }
            let jitter = rng.range(-6, 6)
            let center = slot.angle == 0 ? CGPoint(x: slot.center.x + jitter, y: slot.center.y)
                                         : CGPoint(x: slot.center.x, y: slot.center.y + jitter)
            obstacles.append(ObstacleDef(kind: .car, center: center, size: carSize,
                                         angle: slot.angle + (rng.unit() < 0.5 ? 0 : CGFloat.pi), tint: rng.int(6)))
        }

        var arcade = Levels.arcadeLayout(map: map, round: round, race: race)
        obstacles += buildings(map: map, rng: &rng, alleyBlocks: arcade.alleyBlocks, alleys: &arcade.alleys)

        // Traffic
        var bots: [BotStart] = []
        var attempts = 0
        while bots.count < 30 && attempts < 600 {
            attempts += 1
            let index = rng.int(segments.count)
            if index == startSegment { continue }
            let s = segments[index]
            let forward = rng.unit() < 0.5
            let candidate = BotStart(from: forward ? s.a : s.b, to: forward ? s.b : s.a, progress: rng.range(0.1, 0.9), tint: rng.int(6))
            let lane = map.lane(from: candidate.from, to: candidate.to)
            let p = CGPoint(x: lane.start.x + (lane.end.x - lane.start.x) * candidate.progress,
                            y: lane.start.y + (lane.end.y - lane.start.y) * candidate.progress)
            if bots.contains(where: { other in
                let l = map.lane(from: other.from, to: other.to)
                let q = CGPoint(x: l.start.x + (l.end.x - l.start.x) * other.progress, y: l.start.y + (l.end.y - l.start.y) * other.progress)
                return q.distance(to: p) < 90
            }) { continue }
            bots.append(candidate)
        }

        var level = LevelDef(nameTR: "Şehir", nameEN: "City", starts: starts, spots: spots, obstacles: obstacles,
                             world: worldSize, city: map, bots: bots)
        Levels.finishArcade(&level, arcade)
        return level
    }

    static let alleyWidth: CGFloat = 90

    /// Arcade extras, drawn from their own random stream so the rest of the map stays the same.
    struct ArcadeLayout {
        var alleyBlocks: Set<Int>
        var alleys: [CGRect] = []
        var rng: SplitMix64
        let weather: Weather
    }

    static func arcadeLayout(map: CityMap, round: Int, race: Bool) -> ArcadeLayout {
        var rng = SplitMix64(seed: (UInt64(round + 11) &* 0x9E37_79B9_7F4A_7C15) ^ (race ? 0x5151 : 0x7373))
        var blocks = Array(map.blocks.indices)
        blocks.shuffle(using: &rng)
        // Every round shows a different sky: races start at night, city rounds in the rain
        let weather = Weather(rawValue: (round + (race ? 1 : 2)) % 4) ?? .day
        return ArcadeLayout(alleyBlocks: Set(blocks.prefix(3)), rng: rng, weather: weather)
    }

    /// Ramps in the alleys, construction cones, barrels and bins, and the weather.
    static func finishArcade(_ level: inout LevelDef, _ layout: ArcadeLayout) {
        guard let map = level.city else { return }
        var rng = layout.rng
        level.alleys = layout.alleys
        level.weather = layout.weather
        level.ramps = layout.alleys.map { RampDef(center: CGPoint(x: $0.midX, y: $0.midY), alongX: true) }
        let keepClear = level.starts.map { $0.position } + level.spots.map { $0.center }
        let parked = level.obstacles.filter { $0.kind == .car }.map { $0.center }
        func free(_ p: CGPoint, _ radius: CGFloat) -> Bool {
            !keepClear.contains { $0.distance(to: p) < 220 } && !parked.contains { $0.distance(to: p) < radius }
                && !level.alleys.contains { $0.insetBy(dx: -30, dy: -30).contains(p) }
        }
        var props: [PropDef] = []
        // Road works: a taper of cones from the parking strip into the lane on a few streets
        for _ in 0..<5 {
            let horizontal = rng.unit() < 0.5
            let side: CGFloat = rng.unit() < 0.5 ? -1 : 1
            if horizontal {
                let j = rng.int(map.rows)
                let i = rng.int(map.cols - 1)
                let x0 = map.xs[i] + 220 + rng.range(0, 200)
                let barricade = CGPoint(x: x0 - 30, y: map.ys[j] + side * CityMap.stripOffset)
                if free(barricade, 50) { props.append(PropDef(kind: 3, position: barricade, yaw: CGFloat.pi / 2)) }
                for k in 0..<7 {
                    let p = CGPoint(x: x0 + CGFloat(k) * 34, y: map.ys[j] + side * (CityMap.stripOffset - CGFloat(k) * 7))
                    if free(p, 40) { props.append(PropDef(kind: 0, position: p)) }
                }
            } else {
                let i = rng.int(map.cols)
                let j = rng.int(map.rows - 1)
                let y0 = map.ys[j] + 220 + rng.range(0, 150)
                let barricade = CGPoint(x: map.xs[i] + side * CityMap.stripOffset, y: y0 - 30)
                if free(barricade, 50) { props.append(PropDef(kind: 3, position: barricade, yaw: 0)) }
                for k in 0..<7 {
                    let p = CGPoint(x: map.xs[i] + side * (CityMap.stripOffset - CGFloat(k) * 7), y: y0 + CGFloat(k) * 34)
                    if free(p, 40) { props.append(PropDef(kind: 0, position: p)) }
                }
            }
        }
        // Barrels at a few intersection corners
        for _ in 0..<6 {
            let node = rng.int(map.nodeCount)
            let c = map.position(of: node)
            let sx: CGFloat = rng.unit() < 0.5 ? -1 : 1
            let sy: CGFloat = rng.unit() < 0.5 ? -1 : 1
            for k in 0..<2 {
                let p = CGPoint(x: c.x + sx * (CityMap.roadHalf - 14), y: c.y + sy * (CityMap.roadHalf - 14 - CGFloat(k) * 18))
                if free(p, 30) && p.x > 20 && p.y > 20 && p.x < level.world.width - 20 && p.y < level.world.height - 20 {
                    props.append(PropDef(kind: 1, position: p))
                }
            }
        }
        // Bins at the curb along the blocks
        for block in map.blocks {
            for _ in 0..<2 {
                let alongX = rng.unit() < 0.5
                let p = alongX
                    ? CGPoint(x: rng.range(block.minX + 60, block.maxX - 60), y: rng.unit() < 0.5 ? block.minY + 10 : block.maxY - 10)
                    : CGPoint(x: rng.unit() < 0.5 ? block.minX + 10 : block.maxX - 10, y: rng.range(block.minY + 60, block.maxY - 60))
                if free(p, 30) { props.append(PropDef(kind: 2, position: p)) }
            }
        }
        level.props = props
    }

    /// Landmark kinds, stored in a building's `tint` (100+).
    static let gasStation = 100
    static let parkingGarage = 101
    static let park = 102

    /// Buildings: 2–3 columns x 2 rows per block, set back behind a sidewalk. One block is a park,
    /// and a few corner lots hold a gas station or a parking garage.
    private static func buildings(map: CityMap, rng: inout SplitMix64, alleyBlocks: Set<Int> = [],
                                  alleys: inout [CGRect]) -> [ObstacleDef] {
        var result: [ObstacleDef] = []
        let blocks = map.blocks
        var order = Array(blocks.indices)
        order.shuffle(using: &rng)
        let parkBlock = order.first ?? -1
        let gasBlocks = Set(order.dropFirst().prefix(2))
        let garageBlocks = Set(order.dropFirst(3).prefix(2))
        for (index, block) in blocks.enumerated() {
            let inner = block.insetBy(dx: 36, dy: 36)
            if index == parkBlock {
                result.append(ObstacleDef(kind: .building, center: CGPoint(x: inner.midX, y: inner.midY), size: inner.size,
                                          angle: 0, tint: park, height: 0))
                continue
            }
            let columns = 2 + rng.int(2)
            let gap: CGFloat = 22
            // An alley block keeps a wide drivable lane between its two rows of buildings
            let rowGap: CGFloat = alleyBlocks.contains(index) ? Levels.alleyWidth : gap
            if alleyBlocks.contains(index) {
                let y = inner.minY + (inner.height - rowGap) / 2
                alleys.append(CGRect(x: block.minX, y: y, width: block.width, height: rowGap))
            }
            let width = (inner.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let height = (inner.height - rowGap) / 2
            for c in 0..<columns {
                for r in 0..<2 {
                    let center = CGPoint(x: inner.minX + width * (CGFloat(c) + 0.5) + gap * CGFloat(c),
                                         y: inner.minY + height * (CGFloat(r) + 0.5) + rowGap * CGFloat(r))
                    var tint = rng.int(8)
                    let floors = rng.range(7, 26)
                    if c == 0 && r == 0 {
                        if gasBlocks.contains(index) { tint = gasStation }
                        if garageBlocks.contains(index) { tint = parkingGarage }
                    }
                    result.append(ObstacleDef(kind: .building, center: center, size: CGSize(width: width, height: height),
                                              angle: 0, tint: tint, height: tint >= 100 ? 12 : floors))
                }
            }
        }
        return result
    }
}

// MARK: - Traffic

struct Bot {
    var position: CGPoint
    var heading: CGFloat
    var speed: CGFloat
    var from: Int
    var to: Int
    var waypoints: [CGPoint]
    var waiting: CGFloat = 0
    var ignoreBots: CGFloat = 0
    var braking = false
    /// Knocked by a crash: slides and spins for a moment before driving on.
    var stunned: CGFloat = 0
    var shove = CGVector.zero
    var spin: CGFloat = 0
    let tint: Int

    var box: OBB { OBB(center: position, size: Levels.carSize, angle: heading) }
}

/// Simple lane-following traffic: drive the right-hand lane, pick a random street at each
/// intersection, stop for anything ahead.
final class Traffic {
    let map: CityMap
    private(set) var bots: [Bot] = []
    private var rng: SplitMix64

    private let cruise: CGFloat = 78
    /// Seconds since the level started; drives the traffic lights.
    private(set) var clock: CGFloat = 0
    private let cornerSpeed: CGFloat = 42

    init(map: CityMap, starts: [BotStart], seed: UInt64) {
        self.map = map
        rng = SplitMix64(seed: seed)
        for start in starts {
            let lane = map.lane(from: start.from, to: start.to)
            let p = CGPoint(x: lane.start.x + (lane.end.x - lane.start.x) * start.progress,
                            y: lane.start.y + (lane.end.y - lane.start.y) * start.progress)
            bots.append(Bot(position: p, heading: lane.heading, speed: cruise, from: start.from, to: start.to,
                            waypoints: [lane.end], tint: start.tint))
        }
    }

    /// A player crashed into bot `index`: it is shoved and spun, then drives on.
    func hit(_ index: Int, shove: CGVector, spin: CGFloat) {
        guard bots.indices.contains(index) else { return }
        bots[index].stunned = 1.1
        bots[index].shove = shove
        bots[index].spin = spin
        bots[index].speed = 0
    }

    /// `blockers`: player car centers the bots must not drive into.
    func step(_ dt: CGFloat, blockers: [CGPoint]) {
        clock += dt
        for index in bots.indices {
            var bot = bots[index]
            if bot.stunned > 0 {
                // Sliding and spinning after a hit, then back to its lane
                bot.stunned -= dt
                bot.position.x += bot.shove.dx * dt
                bot.position.y += bot.shove.dy * dt
                bot.heading += bot.spin * dt
                let fade = exp(-dt * 3.2)
                bot.shove = CGVector(dx: bot.shove.dx * fade, dy: bot.shove.dy * fade)
                bot.spin *= fade
                bot.speed = 0
                bot.braking = true
                bots[index] = bot
                continue
            }
            if bot.waypoints.isEmpty {
                var options = map.neighbors(bot.to).filter { $0 != bot.from }
                if options.isEmpty { options = map.neighbors(bot.to) }
                let next = options[rng.int(options.count)]
                bot.from = bot.to
                bot.to = next
                let lane = map.lane(from: bot.from, to: bot.to)
                bot.waypoints = [lane.start, lane.end]
            }
            let target = bot.waypoints[0]
            let dx = target.x - bot.position.x
            let dy = target.y - bot.position.y
            let distance = hypot(dx, dy)
            let ahead = dx * cos(bot.heading) + dy * sin(bot.heading)
            // Approaching the stop line (end of the lane) on a red or late yellow light?
            var mustStop = false
            if bot.waypoints.count == 1 && distance < 90 {
                let horizontal = bot.from / map.cols == bot.to / map.cols
                switch map.signal(at: bot.to, horizontal: horizontal, time: clock) {
                case .green: mustStop = false
                case .yellow: mustStop = distance > 40 || bot.speed < 20
                case .red: mustStop = true
                }
            }
            if !mustStop && (distance < 24 || (distance < 70 && ahead < 0)) {
                bot.waypoints.removeFirst()
                bots[index] = bot
                continue
            }
            let desired = atan2(dy, dx)
            let error = CGFloat.angleDelta(bot.heading, desired)
            let maxTurn = 2.4 * dt
            bot.heading += max(-maxTurn, min(maxTurn, error))

            var targetSpeed = abs(error) > 0.35 ? cornerSpeed : cruise
            if mustStop {
                // Ease to a stop just before the line
                targetSpeed = min(targetSpeed, max(0, (distance - 10) * 1.4))
                bot.braking = true
            }
            var blockedByBot = false
            var blocked = false
            func check(_ point: CGPoint) -> Bool {
                let vx = point.x - bot.position.x
                let vy = point.y - bot.position.y
                let forward = vx * cos(bot.heading) + vy * sin(bot.heading)
                let lateral = abs(-vx * sin(bot.heading) + vy * cos(bot.heading))
                return forward > 0 && forward < 82 && lateral < 26
            }
            for point in blockers where check(point) { blocked = true }
            if !blocked && bot.ignoreBots <= 0 {
                for other in bots.indices where other != index && check(bots[other].position) {
                    blocked = true
                    blockedByBot = true
                    break
                }
            }
            if blocked {
                targetSpeed = 0
                bot.waiting += dt
                if blockedByBot && bot.waiting > 2.5 {
                    bot.ignoreBots = 1.6
                    bot.waiting = 0
                }
            } else {
                bot.waiting = 0
            }
            bot.ignoreBots = max(0, bot.ignoreBots - dt)

            let accel: CGFloat = bot.speed < targetSpeed ? 90 : 280
            if bot.speed < targetSpeed {
                bot.speed = min(targetSpeed, bot.speed + accel * dt)
            } else {
                bot.speed = max(targetSpeed, bot.speed - accel * dt)
            }
            bot.braking = targetSpeed < bot.speed - 1 || (targetSpeed == 0)
            bot.position.x += cos(bot.heading) * bot.speed * dt
            bot.position.y += sin(bot.heading) * bot.speed * dt
            bots[index] = bot
        }
    }

    /// Compact state for the network: x, y, heading*100, from, to, speed per bot.
    func snapshot() -> [Int] {
        var result: [Int] = []
        for bot in bots {
            result += [Int(bot.position.x.rounded()), Int(bot.position.y.rounded()), Int((bot.heading * 100).rounded()),
                       bot.from, bot.to, Int(bot.speed.rounded())]
        }
        return result
    }

    /// Applies the host's state, easing toward it to hide small differences.
    func apply(_ data: [Int]) {
        guard data.count == bots.count * 6 else { return }
        for index in bots.indices {
            let base = index * 6
            let target = CGPoint(x: CGFloat(data[base]), y: CGFloat(data[base + 1]))
            let heading = CGFloat(data[base + 2]) / 100
            let from = data[base + 3]
            let to = data[base + 4]
            guard from >= 0, from < map.nodeCount, to >= 0, to < map.nodeCount else { continue }
            var bot = bots[index]
            if bot.position.distance(to: target) > 90 {
                bot.position = target
                bot.heading = heading
            } else {
                bot.position.x += (target.x - bot.position.x) * 0.6
                bot.position.y += (target.y - bot.position.y) * 0.6
                bot.heading += CGFloat.angleDelta(bot.heading, heading) * 0.6
            }
            bot.speed = CGFloat(data[base + 5])
            if from != bot.from || to != bot.to {
                bot.from = from
                bot.to = to
                let lane = map.lane(from: from, to: to)
                bot.waypoints = [lane.start, lane.end].filter {
                    ($0.x - bot.position.x) * cos(bot.heading) + ($0.y - bot.position.y) * sin(bot.heading) > 0
                }
            }
            bots[index] = bot
        }
    }
}

import CoreGraphics

/// The rules that make each parking level harder than the one before. Built from the level's
/// number (1-50) and its layout, the same on both phones:
///   - alignment: the car must sit straighter in the bay (17° at level 1, 4° at level 50),
///   - hold: it must stay still in the bay longer (0.8 s up to 2 s),
///   - time limit (from level 6): from the real driving distance to the bay, shrinking,
///   - crash limit (from level 10): 5, then 3, 2, 1, and none from level 45 ("zero margin"),
///   - back it in (straight bays, every other level from 15, all of them from 35): nose out,
///   - wet ground (every seventh level from 14): rain and much less grip,
///   - patrol cars (from level 18; two from level 36): a car drives up and down the lot and
///     stops for nobody but you, faster in every level.
struct ParkChallenge {
    let number: Int
    let tier: Int
    let alignTolerance: CGFloat
    let holdTime: CGFloat
    let timeLimit: CGFloat?
    let maxHits: Int?
    let reverseIn: Bool
    let wetGround: Bool
    let patrols: [PatrolLane]
    let patrolSpeed: CGFloat

    /// A straight lane a patrol car drives back and forth on.
    struct PatrolLane {
        let from: CGPoint
        let to: CGPoint
    }

    static let easy = ParkChallenge(number: 0, tier: 0, alignTolerance: 0.21, holdTime: 1, timeLimit: nil, maxHits: nil,
                                    reverseIn: false, wetGround: false, patrols: [], patrolSpeed: 0)

    static func make(index: Int, level: LevelDef, slot: Int) -> ParkChallenge {
        guard !Levels.isCity(index), index >= 0, index < 50 else { return .easy }
        let n = index + 1
        let t = CGFloat(n - 1) / 49
        let tier = min(4, (n - 1) / 10)
        let align = 0.30 - 0.23 * t
        let hold = 0.8 + 1.2 * t
        let maxHits: Int? = n < 10 ? nil : (n < 20 ? 5 : (n < 30 ? 3 : (n < 40 ? 2 : (n < 45 ? 1 : 0))))
        // Straight (90°) bays can be backed into: nose toward the lane
        let straight = level.spots.allSatisfy { abs(abs($0.angle) - CGFloat.pi / 2) < 0.05 }
        let reverse = straight && n >= 15 && (n % 2 == 0 || n >= 35)
        let wet = n >= 14 && n % 7 == 0
        var lanes: [PatrolLane] = []
        if n >= 18 {
            lanes = patrolLanes(level: level, count: n >= 36 ? 2 : 1)
        }
        var limit: CGFloat?
        if n >= 6 {
            // Driving distance to the bay (around everything), at an average speed that rises,
            // plus time to manoeuvre that shrinks
            let meters = (0..<min(level.starts.count, level.spots.count)).map {
                pathLength(level: level, from: level.starts[$0].position, to: level.spots[$0].center) / 10
            }.max() ?? 60
            let maneuver = 26 - 14 * t + (reverse ? 6 : 0) + (wet ? 4 : 0) + CGFloat(lanes.count) * 3
            let speed = 4 + 3 * t
            limit = (maneuver + meters / speed).rounded(.up)
        }
        return ParkChallenge(number: n, tier: tier, alignTolerance: align, holdTime: hold, timeLimit: limit, maxHits: maxHits,
                             reverseIn: reverse, wetGround: wet, patrols: lanes, patrolSpeed: 35 + 60 * t)
    }

    /// The rules shown before the start: (SF Symbol, text).
    var rules: [(icon: String, text: String)] {
        var list: [(String, String)] = []
        if let limit = timeLimit { list.append(("timer", Strings.ruleTime(Int(limit)))) }
        if let maxHits = maxHits {
            list.append(("exclamationmark.triangle.fill", maxHits == 0 ? Strings.ruleNoHits : Strings.ruleHits(maxHits)))
        }
        if reverseIn { list.append(("arrow.uturn.backward", Strings.ruleReverse)) }
        if wetGround { list.append(("cloud.rain.fill", Strings.ruleWet)) }
        if !patrols.isEmpty { list.append(("car.fill", Strings.rulePatrol(patrols.count))) }
        if number >= 25 { list.append(("scope", Strings.rulePrecise)) }
        return list
    }

    var tierName: String { Strings.tierNames[min(tier, Strings.tierNames.count - 1)] }

    // MARK: - Level analysis

    /// Free grid of the lot: cells of 10 units, blocked within a car's half width of anything.
    private static func freeGrid(_ level: LevelDef, radius: CGFloat) -> (cols: Int, rows: Int, free: [Bool]) {
        let cell: CGFloat = 10
        let cols = Int(level.world.width / cell), rows = Int(level.world.height / cell)
        var free = [Bool](repeating: true, count: cols * rows)
        for row in 0..<rows {
            for col in 0..<cols {
                let p = CGPoint(x: (CGFloat(col) + 0.5) * cell, y: (CGFloat(row) + 0.5) * cell)
                if p.x < radius || p.y < radius || p.x > level.world.width - radius || p.y > level.world.height - radius {
                    free[row * cols + col] = false
                    continue
                }
                for obstacle in level.obstacles {
                    let dx = p.x - obstacle.center.x, dy = p.y - obstacle.center.y
                    let c = cos(obstacle.angle), s = sin(obstacle.angle)
                    let lx = abs(dx * c + dy * s) - obstacle.size.width / 2
                    let ly = abs(-dx * s + dy * c) - obstacle.size.height / 2
                    if hypot(max(0, lx), max(0, ly)) < radius {
                        free[row * cols + col] = false
                        break
                    }
                }
            }
        }
        return (cols, rows, free)
    }

    /// Length of the shortest way (units) from a start to a bay, around obstacles (8-way grid).
    static func pathLength(level: LevelDef, from: CGPoint, to: CGPoint) -> CGFloat {
        let grid = freeGrid(level, radius: 12)
        let cell: CGFloat = 10
        func index(_ p: CGPoint) -> Int {
            let col = max(0, min(grid.cols - 1, Int(p.x / cell)))
            let row = max(0, min(grid.rows - 1, Int(p.y / cell)))
            return row * grid.cols + col
        }
        let start = index(from), goal = index(to)
        var distance = [CGFloat](repeating: .infinity, count: grid.free.count)
        distance[start] = 0
        // Dijkstra with a binary heap
        var heap = MinHeap()
        heap.push(start, 0)
        var free = grid.free
        free[start] = true
        free[goal] = true
        let steps: [(Int, Int, CGFloat)] = [(1, 0, 10), (-1, 0, 10), (0, 1, 10), (0, -1, 10),
                                           (1, 1, 14.1), (1, -1, 14.1), (-1, 1, 14.1), (-1, -1, 14.1)]
        while let (current, cost) = heap.pop() {
            if current == goal { return cost }
            if cost > distance[current] { continue }
            let col = current % grid.cols, row = current / grid.cols
            for (dc, dr, step) in steps {
                let c = col + dc, r = row + dr
                guard c >= 0, r >= 0, c < grid.cols, r < grid.rows else { continue }
                let next = r * grid.cols + c
                guard free[next] else { continue }
                let total = cost + step
                if total < distance[next] {
                    distance[next] = total
                    heap.push(next, total)
                }
            }
        }
        // No way found (should not happen: the generator checks every level)
        return hypot(to.x - from.x, to.y - from.y) * 1.5
    }

    /// Straight lanes across the lot that are clear of every obstacle, bay and start, ordered
    /// so the first one lies most in the way between the starts and the bays.
    private static func patrolLanes(level: LevelDef, count: Int) -> [PatrolLane] {
        let half = Levels.carSize.height / 2 + 8
        var keepOut = level.obstacles.map { $0.box }
        keepOut += level.spots.map { OBB(center: $0.center, size: CGSize(width: $0.size.width + 20, height: $0.size.height + 20), angle: $0.angle) }
        keepOut += level.starts.map { OBB(center: $0.position, size: CGSize(width: 90, height: 60), angle: $0.heading) }
        func clear(_ box: OBB) -> Bool { !keepOut.contains { $0.intersects(box) } }
        let world = level.world
        var candidates: [(lane: PatrolLane, score: CGFloat)] = []
        let startCenter = level.starts.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.position.x, y: $0.y + $1.position.y) }
        let spotCenter = level.spots.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.center.x, y: $0.y + $1.center.y) }
        let middle = CGPoint(x: (startCenter.x / CGFloat(max(1, level.starts.count)) + spotCenter.x / CGFloat(max(1, level.spots.count))) / 2,
                             y: (startCenter.y / CGFloat(max(1, level.starts.count)) + spotCenter.y / CGFloat(max(1, level.spots.count))) / 2)
        // Across the lot (north-south): the car crosses the player's way
        var x: CGFloat = 220
        while x <= world.width - 120 {
            let from = CGPoint(x: x, y: 40), to = CGPoint(x: x, y: world.height - 40)
            let box = OBB(center: CGPoint(x: x, y: world.height / 2), size: CGSize(width: world.height - 40, height: half * 2), angle: .pi / 2)
            if clear(box) { candidates.append((PatrolLane(from: from, to: to), abs(x - middle.x))) }
            x += 20
        }
        // Along the lot (east-west)
        var y: CGFloat = 60
        while y <= world.height - 60 {
            let from = CGPoint(x: 200, y: y), to = CGPoint(x: world.width - 60, y: y)
            let box = OBB(center: CGPoint(x: (from.x + to.x) / 2, y: y), size: CGSize(width: to.x - from.x + 44, height: half * 2), angle: 0)
            if clear(box) { candidates.append((PatrolLane(from: from, to: to), abs(y - middle.y) + 40)) }
            y += 20
        }
        candidates.sort { $0.score < $1.score }
        var lanes: [PatrolLane] = []
        for candidate in candidates where lanes.count < count {
            // Two patrols keep apart
            let far = lanes.allSatisfy {
                hypot(($0.from.x + $0.to.x) / 2 - (candidate.lane.from.x + candidate.lane.to.x) / 2,
                      ($0.from.y + $0.to.y) / 2 - (candidate.lane.from.y + candidate.lane.to.y) / 2) > 140
            }
            if far { lanes.append(candidate.lane) }
        }
        return lanes
    }
}

/// A small binary min-heap of (cell, cost) for the path search.
private struct MinHeap {
    private var items: [(Int, CGFloat)] = []
    mutating func push(_ item: Int, _ cost: CGFloat) {
        items.append((item, cost))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            if items[parent].1 <= items[i].1 { break }
            items.swapAt(parent, i)
            i = parent
        }
    }
    mutating func pop() -> (Int, CGFloat)? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var smallest = i
                if l < items.count && items[l].1 < items[smallest].1 { smallest = l }
                if r < items.count && items[r].1 < items[smallest].1 { smallest = r }
                if smallest == i { break }
                items.swapAt(i, smallest)
                i = smallest
            }
        }
        return top
    }
}

/// A car of the lot driving up and down its lane. It brakes for the player rather than hitting
/// them, so it blocks the way: the player has to time it.
final class PatrolCar {
    let lane: ParkChallenge.PatrolLane
    let car: Car3D
    private(set) var position: CGPoint
    private(set) var heading: CGFloat
    private var progress: CGFloat
    private var direction: CGFloat = 1
    private var speed: CGFloat = 0
    private var pause: CGFloat = 0
    let topSpeed: CGFloat
    var box: OBB { OBB(center: position, size: Levels.carSize, angle: heading) }

    init(lane: ParkChallenge.PatrolLane, car: Car3D, topSpeed: CGFloat, phase: CGFloat) {
        self.lane = lane
        self.car = car
        self.topSpeed = topSpeed
        progress = phase
        let dx = lane.to.x - lane.from.x, dy = lane.to.y - lane.from.y
        heading = atan2(dy, dx)
        position = CGPoint(x: lane.from.x + dx * phase, y: lane.from.y + dy * phase)
        car.update(position: position, heading: heading, steer: 0)
    }

    /// `blocked(box)`: would this box touch the player (or the friend)? Returns true when the
    /// car stopped for them this frame (for a horn).
    @discardableResult
    func step(_ dt: CGFloat, blocked: (OBB) -> Bool) -> Bool {
        let length = max(1, hypot(lane.to.x - lane.from.x, lane.to.y - lane.from.y))
        if pause > 0 {
            pause -= dt
            car.update(position: position, heading: heading, steer: 0, braking: true)
            return false
        }
        let ahead = OBB(center: CGPoint(x: position.x + cos(heading) * 18, y: position.y + sin(heading) * 18),
                        size: CGSize(width: Levels.carSize.width + 16, height: Levels.carSize.height + 6), angle: heading)
        var stopped = false
        if blocked(ahead) {
            speed = max(0, speed - 400 * dt)
            stopped = speed < 1
        } else {
            speed = min(topSpeed, speed + 60 * dt)
        }
        progress += direction * speed * dt / length
        if progress >= 1 || progress <= 0 {
            progress = max(0, min(1, progress))
            direction = -direction
            speed = 0
            pause = 0.8
        }
        let dx = lane.to.x - lane.from.x, dy = lane.to.y - lane.from.y
        position = CGPoint(x: lane.from.x + dx * progress, y: lane.from.y + dy * progress)
        heading = atan2(dy * direction, dx * direction)
        car.update(position: position, heading: heading, steer: 0, braking: speed < topSpeed * 0.3)
        return stopped
    }
}

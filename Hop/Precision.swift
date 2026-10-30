import Foundation
import CoreGraphics

/// How precisely a car stands in its bay, measured like a parking inspector would: how far it
/// sits off the bay's centre line (across and along) and how crooked it is, in centimetres and
/// degrees, and the gaps to the bay's lines on both sides. The world is 10 units to the metre.
struct ParkPrecision {
    /// Gap from the car's side to the bay line on its left and right (cm).
    let leftGap: Int
    let rightGap: Int
    /// Off the centre line across the bay and along it (cm, signed).
    let across: Int
    let along: Int
    /// Off straight (degrees).
    let angle: Double
    /// 0...100.
    let score: Int

    enum Grade: String {
        case s = "S", a = "A", b = "B", c = "C"
    }

    var grade: Grade {
        switch score {
        case 95...: return .s
        case 85..<95: return .a
        case 70..<85: return .b
        default: return .c
        }
    }

    /// Coins for the precision of the park.
    var coins: Int {
        switch grade {
        case .s: return 60
        case .a: return 30
        case .b: return 10
        case .c: return 0
        }
    }

    /// Measures `car` (centre, heading, size) in `spot`.
    init(spot: SpotDef, car: CGPoint, heading: CGFloat, carSize: CGSize) {
        let u = CGVector(dx: cos(spot.angle), dy: sin(spot.angle))          // along the bay
        let v = CGVector(dx: -sin(spot.angle), dy: cos(spot.angle))         // across it
        let dx = car.x - spot.center.x, dy = car.y - spot.center.y
        let alongUnits = dx * u.dx + dy * u.dy
        let acrossUnits = dx * v.dx + dy * v.dy
        // Crooked either way round (nose in or backed in)
        var off = (heading - spot.angle).truncatingRemainder(dividingBy: .pi)
        if off > .pi / 2 { off -= .pi }
        if off < -.pi / 2 { off += .pi }
        let angleDegrees = Double(abs(off)) * 180 / .pi
        // Half the car's footprint across the bay, tilted by the angle
        let halfAcross = (carSize.height / 2) * cos(abs(off)) + (carSize.width / 2) * sin(abs(off))
        let halfBay = spot.size.height / 2
        let left = halfBay - (acrossUnits + halfAcross)
        let right = halfBay + (acrossUnits - halfAcross)
        leftGap = Int((left * 10).rounded())
        rightGap = Int((right * 10).rounded())
        across = Int((acrossUnits * 10).rounded())
        along = Int((alongUnits * 10).rounded())
        angle = (angleDegrees * 10).rounded() / 10

        // Centred across the bay counts most, then straight, then centred along it. Each part is
        // full when spot on and empty at the edge of what the bay allows (8 degrees for the angle)
        let slackAcross = max(1, (spot.size.height - carSize.height) / 2)
        let slackAlong = max(1, (spot.size.width - carSize.width) / 2)
        // (a part falls off slowly near the middle and fast towards the edge: a few centimetres
        // off still earns an S, half way to the line does not)
        func part(_ off: Double, _ slack: Double) -> Double { max(0, 1 - pow(min(1, off / slack), 1.5)) }
        let acrossPart = part(Double(abs(acrossUnits)), Double(slackAcross))
        let anglePart = part(angleDegrees, 8)
        let alongPart = part(Double(abs(alongUnits)), Double(slackAlong))
        let raw = 0.5 * acrossPart + 0.35 * anglePart + 0.15 * alongPart
        score = max(0, min(100, Int((raw * 100).rounded())))
    }

    // MARK: Best per level

    private static let key = "pp.precision"

    static func best(level: Int) -> Int? {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Int])?[String(level)]
    }

    /// Keeps the best score of a level; true when this one beat it.
    @discardableResult
    static func record(level: Int, score: Int) -> Bool {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        let previous = all[String(level)]
        guard previous.map({ score > $0 }) ?? true else { return false }
        all[String(level)] = score
        UserDefaults.standard.set(all, forKey: key)
        return true
    }

    static func grade(for score: Int) -> Grade {
        switch score {
        case 95...: return .s
        case 85..<95: return .a
        case 70..<85: return .b
        default: return .c
        }
    }
}

import CoreGraphics
import Foundation

/// The player car's suspension: a rigid body (heave, pitch, roll) on four springs and dampers,
/// one at each wheel, with an anti-roll bar and bump stops. Each wheel sits on the ground under
/// it; the body is pushed by the springs and by its own inertia when the car brakes, accelerates
/// or corners. Units: metres, seconds, newtons. Corners: 0 front left, 1 front right, 2 rear
/// left, 3 rear right (left is +y).
struct Suspension {
    // The car
    private let mass: CGFloat = 1400
    private let pitchInertia: CGFloat = 2000
    private let rollInertia: CGFloat = 430
    private let cgHeight: CGFloat = 0.72            // above the roll and pitch axes
    private let halfBase: CGFloat = 1.35
    private let halfTrack: CGFloat = 0.82
    // Springs about 1.3 Hz, dampers at 40 % of critical, a stiff anti-roll bar
    private let spring: CGFloat = 23_400
    private let damper: CGFloat = 2_300
    private let antiRoll: CGFloat = 90_000
    private let antiRollDamping: CGFloat = 5_000
    private let bumpTravel: CGFloat = 0.09            // compression before the bump stop
    private let droopTravel: CGFloat = 0.11
    private let bumpStop: CGFloat = 220_000

    // Body state (heave relative to the car's node)
    private(set) var heave: CGFloat = 0
    private var heaveSpeed: CGFloat = 0
    private var pitchAngle: CGFloat = 0
    private var pitchSpeed: CGFloat = 0
    private var rollAngle: CGFloat = 0
    private var rollSpeed: CGFloat = 0
    private var lastNodeLift: CGFloat = 0
    private var lastGrounds: [CGFloat] = [0, 0, 0, 0]

    /// Where the wheels are (relative to the node): on the ground under each corner.
    private(set) var wheelLift: [CGFloat] = [0, 0, 0, 0]
    /// The car's node height (ramps and jumps), passed through.
    private(set) var nodeLift: CGFloat = 0
    /// Share of the car's weight on the front axle (0.5 at rest).
    private(set) var frontLoad: CGFloat = 0.5
    /// How much of the weight has moved to one side (0 level, 1 all on one side).
    private(set) var lateralTransfer: CGFloat = 0

    var pitch: CGFloat { pitchAngle }
    var roll: CGFloat { rollAngle }

    private var corners: [(x: CGFloat, y: CGFloat)] {
        [(halfBase, halfTrack), (halfBase, -halfTrack), (-halfBase, halfTrack), (-halfBase, -halfTrack)]
    }

    /// `grounds`: the ground's height under each wheel relative to the node; `ax` forward and
    /// `ay` leftward acceleration of the car.
    mutating func step(_ dt: CGFloat, nodeLift lift: CGFloat, grounds: [CGFloat], ax: CGFloat, ay: CGFloat) {
        // The node moving up or down (a ramp, a jump) must not move the body in the world
        heave -= lift - lastNodeLift
        lastNodeLift = lift
        nodeLift = lift
        let groundSpeed = zip(grounds, lastGrounds).map { ($0 - $1) / max(dt, 0.001) }
        lastGrounds = grounds
        wheelLift = grounds

        let steps = 4
        let h = min(dt, 0.05) / CGFloat(steps)
        var forces: [CGFloat] = [0, 0, 0, 0]
        for _ in 0..<steps {
            var force: CGFloat = 0, pitchMoment: CGFloat = 0, rollMoment: CGFloat = 0
            for (i, corner) in corners.enumerated() {
                let z = heave + corner.x * pitchAngle + corner.y * rollAngle
                let zSpeed = heaveSpeed + corner.x * pitchSpeed + corner.y * rollSpeed
                let travel = z - grounds[i]                     // < 0: compressed
                var f = -spring * travel - damper * (zSpeed - groundSpeed[i])
                if travel < -bumpTravel { f += bumpStop * (-bumpTravel - travel) }
                if travel > droopTravel { f -= bumpStop * (travel - droopTravel) }
                forces[i] = f
                force += f
                pitchMoment += f * corner.x
                rollMoment += f * corner.y
            }
            // Inertia: accelerating squats the rear, braking dives the nose, a turn leans the
            // body to the outside; the anti-roll bar resists the lean
            pitchMoment += mass * ax * cgHeight
            rollMoment += mass * ay * cgHeight - antiRoll * rollAngle - antiRollDamping * rollSpeed
            heaveSpeed += force / mass * h
            pitchSpeed += pitchMoment / pitchInertia * h
            rollSpeed += rollMoment / rollInertia * h
            heave += heaveSpeed * h
            pitchAngle += pitchSpeed * h
            rollAngle += rollSpeed * h
        }
        // Never further than the travel allows (keeps a bad frame from throwing the body)
        pitchAngle = max(-0.14, min(0.14, pitchAngle))
        rollAngle = max(-0.12, min(0.12, rollAngle))

        // Tyre loads: a quarter of the weight each plus what its spring adds
        let quarter = mass * 9.81 / 4
        let loads = forces.map { max(0, quarter + $0) }
        let total = max(1, loads.reduce(0, +))
        frontLoad = (loads[0] + loads[1]) / total
        lateralTransfer = abs((loads[0] + loads[2]) - (loads[1] + loads[3])) / total
    }
}

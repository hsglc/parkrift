import CoreGraphics

enum ObstacleKind {
    case wall
    case car
    case cone
    case building
}

struct ObstacleDef {
    let kind: ObstacleKind
    let center: CGPoint
    let size: CGSize   // width = length along `angle`
    let angle: CGFloat
    let tint: Int
    var height: CGFloat = 0   // meters, buildings only

    var box: OBB { OBB(center: center, size: size, angle: angle) }
}

/// A double-sided jump ramp (a hump): up, a short top, down. `alongX`: driven along world x.
struct RampDef {
    let center: CGPoint
    let alongX: Bool
    static let length: CGFloat = 120   // 12 m
    static let width: CGFloat = 70
    static let height: CGFloat = 0.9   // meters
}

/// A loose street object: 0 traffic cone, 1 drum, 2 trash bin, 3 police barricade.
struct PropDef {
    let kind: Int
    let position: CGPoint
    /// Scene yaw (radians); nil = any.
    var yaw: CGFloat? = nil
}

enum Weather: Int {
    case day, night, rain, snow
}

struct SpotDef {
    let center: CGPoint
    let size: CGSize   // width = length along `angle`
    let angle: CGFloat

    var box: OBB { OBB(center: center, size: size, angle: angle) }
}

struct StartDef {
    let position: CGPoint
    let heading: CGFloat
}

struct LevelDef {
    let nameTR: String
    let nameEN: String
    let starts: [StartDef]   // index = player slot
    var spots: [SpotDef]     // index = player slot (city rounds: the free bay each player is heading for)
    let obstacles: [ObstacleDef]
    var world: CGSize = CGSize(width: 1000, height: 500)
    var city: CityMap? = nil
    var bots: [BotStart] = []
    var race: Bool = false
    /// Shortcuts through city blocks (drivable, no buildings) and the jump ramps in them.
    var alleys: [CGRect] = []
    var ramps: [RampDef] = []
    /// Cones, barrels and bins that fly when hit.
    var props: [PropDef] = []
    var weather: Weather = .day
    /// City rounds (Spot Wars): the free bays on the target street, which drivers hunting for a
    /// spot try to take first, and those drivers.
    var freeSpots: [FreeSpot] = []
    var hunters: [HunterStart] = []
    /// Taxi rounds: the customer, the destination and the ride.
    var taxi: TaxiDef? = nil

    var name: String { Strings.pick(nameTR, nameEN, Levels.spanishNames[nameEN] ?? Levels.moreSpanishNames[nameEN] ?? nameEN) }
}

/// All levels share a 1000 x 500 world; y grows upwards, angles are in degrees in the builders.
enum Levels {
    /// Spanish level names (keyed by the English name).
    static let spanishNames: [String: String] = [
        "First Park": "Primer aparcamiento",
        "Turn In": "En batería",
        "Between Cars": "Entre coches",
        "Angled Bays": "Plazas en diagonal",
        "Go Around": "Rodea",
        "Parallel Park": "Aparcamiento en línea",
        "Maze": "Laberinto",
        "Tight Bays": "Plazas estrechas",
        "Tight Parallel": "Línea ajustada",
        "Garage": "Garaje",
    ]

    static let world = CGSize(width: 1000, height: 500)
    static let carSize = CGSize(width: 44, height: 22)

    static func rad(_ degrees: CGFloat) -> CGFloat { degrees * CGFloat.pi / 180 }

    static func start(_ x: CGFloat, _ y: CGFloat, _ degrees: CGFloat = 0) -> StartDef {
        StartDef(position: CGPoint(x: x, y: y), heading: rad(degrees))
    }

    static func spot(_ x: CGFloat, _ y: CGFloat, _ length: CGFloat, _ width: CGFloat, _ degrees: CGFloat = 0) -> SpotDef {
        SpotDef(center: CGPoint(x: x, y: y), size: CGSize(width: length, height: width), angle: rad(degrees))
    }

    static func car(_ x: CGFloat, _ y: CGFloat, _ degrees: CGFloat = 0, _ tint: Int = 0) -> ObstacleDef {
        ObstacleDef(kind: .car, center: CGPoint(x: x, y: y), size: carSize, angle: rad(degrees), tint: tint)
    }

    static func wall(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> ObstacleDef {
        ObstacleDef(kind: .wall, center: CGPoint(x: x, y: y), size: CGSize(width: w, height: h), angle: 0, tint: 0)
    }

    static func cone(_ x: CGFloat, _ y: CGFloat) -> ObstacleDef {
        ObstacleDef(kind: .cone, center: CGPoint(x: x, y: y), size: CGSize(width: 14, height: 14), angle: 0, tint: 0)
    }

    /// The 50 parking levels (Hop/LevelsMore.swift, made by tools/design_levels.py on a measured
    /// difficulty curve).
    static let all: [LevelDef] = more
}

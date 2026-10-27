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
    case day, night, rain
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
    let spots: [SpotDef]     // index = player slot
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

    static let all: [LevelDef] = base + more

    static let base: [LevelDef] = [
        // 1 — straight ahead
        LevelDef(nameTR: "İlk Park", nameEN: "First Park",
                 starts: [start(140, 150), start(140, 350)],
                 spots: [spot(820, 150, 84, 50), spot(820, 350, 84, 50)],
                 obstacles: [cone(480, 250), cone(520, 250), cone(560, 250)]),

        // 2 — turn 90° into the top row
        LevelDef(nameTR: "Dik Park", nameEN: "Turn In",
                 starts: [start(120, 120), start(120, 220)],
                 spots: [spot(420, 420, 84, 50, 90), spot(580, 420, 84, 50, 90)],
                 obstacles: [car(340, 425, 90, 1), car(500, 425, 90, 2), car(660, 425, 90, 3),
                             cone(800, 200), cone(820, 230)]),

        // 3 — slot between parked cars in the middle row
        LevelDef(nameTR: "Araba Arası", nameEN: "Between Cars",
                 starts: [start(100, 420), start(100, 80)],
                 spots: [spot(460, 250, 80, 44), spot(760, 250, 80, 44)],
                 obstacles: [car(260, 250, 0, 1), car(360, 250, 0, 4), car(560, 250, 0, 2),
                             car(660, 250, 0, 3), car(860, 250, 0, 5)]),

        // 4 — angled bays
        LevelDef(nameTR: "Açılı Park", nameEN: "Angled Bays",
                 starts: [start(100, 400), start(100, 310)],
                 spots: [spot(450, 115, 80, 44, 45), spot(600, 115, 80, 44, 45)],
                 obstacles: [car(300, 115, 45, 2), car(525, 115, 45, 1), car(750, 115, 45, 4),
                             cone(850, 300), cone(870, 330)]),

        // 5 — drive around the divider
        LevelDef(nameTR: "Etrafından Dolaş", nameEN: "Go Around",
                 starts: [start(120, 420), start(120, 340)],
                 spots: [spot(400, 75, 76, 46, 90), spot(600, 75, 76, 46, 90)],
                 obstacles: [wall(500, 250, 600, 20),
                             car(340, 78, 90, 3), car(460, 78, 90, 1), car(540, 78, 90, 5), car(660, 78, 90, 2)]),

        // 6 — parallel parking at the curb
        LevelDef(nameTR: "Paralel Park", nameEN: "Parallel Park",
                 starts: [start(80, 170), start(80, 260)],
                 spots: [spot(265, 52, 70, 34), spot(625, 52, 70, 34)],
                 obstacles: [wall(500, 15, 1000, 30),
                             car(200, 52, 0, 1), car(330, 52, 0, 2), car(440, 52, 0, 3),
                             car(560, 52, 0, 4), car(690, 52, 0, 5), car(900, 52, 0, 1),
                             car(150, 450, 0, 2), car(320, 450, 0, 3), car(490, 450, 0, 4),
                             car(660, 450, 0, 5), car(830, 450, 0, 1)]),

        // 7 — zig-zag maze
        LevelDef(nameTR: "Labirent", nameEN: "Maze",
                 starts: [start(100, 120), start(100, 400)],
                 spots: [spot(860, 120, 78, 44), spot(860, 380, 78, 44)],
                 obstacles: [wall(330, 170, 20, 340), wall(660, 330, 20, 340),
                             cone(760, 250), cone(950, 250), cone(480, 250)]),

        // 8 — tight perpendicular bays
        LevelDef(nameTR: "Dar Yerler", nameEN: "Tight Bays",
                 starts: [start(80, 330), start(80, 150)],
                 spots: [spot(430, 430, 70, 40, 90), spot(610, 430, 70, 40, 90)],
                 obstacles: [car(250, 432, 90, 1), car(310, 432, 90, 2), car(370, 432, 90, 3),
                             car(490, 432, 90, 4), car(550, 432, 90, 5), car(670, 432, 90, 1), car(730, 432, 90, 2),
                             car(240, 250, 90, 3), car(296, 250, 90, 4), car(352, 250, 90, 5), car(408, 250, 90, 1),
                             car(464, 250, 90, 2), car(520, 250, 90, 3), car(576, 250, 90, 4), car(632, 250, 90, 5),
                             car(688, 250, 90, 1), car(744, 250, 90, 2), car(800, 250, 90, 3)]),

        // 9 — tight parallel with cones in the lane
        LevelDef(nameTR: "Sıkı Paralel", nameEN: "Tight Parallel",
                 starts: [start(80, 180), start(80, 290)],
                 spots: [spot(260, 50, 62, 30), spot(660, 50, 62, 30)],
                 obstacles: [wall(500, 15, 1000, 30),
                             car(200, 50, 0, 2), car(320, 50, 0, 3), car(460, 50, 0, 4),
                             car(600, 50, 0, 5), car(720, 50, 0, 1), car(880, 50, 0, 2),
                             cone(420, 170), cone(520, 140), cone(800, 190), cone(300, 230),
                             car(150, 455, 0, 3), car(300, 455, 0, 4), car(450, 455, 0, 5),
                             car(600, 455, 0, 1), car(750, 455, 0, 2), car(900, 455, 0, 3)]),

        // 10 — the garage: low entrance, angled bays, pillars
        LevelDef(nameTR: "Garaj", nameEN: "Garage",
                 starts: [start(100, 420), start(100, 330)],
                 spots: [spot(720, 80, 66, 34, 60), spot(860, 80, 66, 34, 60)],
                 obstacles: [wall(540, 210, 20, 180), wall(760, 300, 440, 20),
                             car(650, 80, 60, 1), car(790, 80, 60, 3), car(930, 80, 60, 5),
                             cone(700, 210), cone(850, 215),
                             cone(300, 250), cone(330, 280), cone(270, 220)])
    ]
}

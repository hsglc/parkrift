import UIKit

/// Textures for the city: building facades by style, shop fronts, roofs, pavers, road details,
/// soft contact shadows, the distant skyline and a cloudy sky. All drawn once and cached.
enum CityArt {
    /// Deterministic noise so textures look the same every launch.
    private struct Noise {
        var state: UInt64
        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
        }
    }

    private static var cache: [String: UIImage] = [:]

    private static func cached(_ key: String, _ make: () -> UIImage) -> UIImage {
        if let image = cache[key] { return image }
        let image = make()
        cache[key] = image
        return image
    }

    private static func speckle(_ context: CGContext, _ size: CGSize, count: Int, alpha: CGFloat, seed: UInt64, light: Bool = false,
                                maxDot: CGFloat = 2) {
        var noise = Noise(state: seed)
        for _ in 0..<count {
            let x = noise.next() * size.width, y = noise.next() * size.height
            let d = 0.6 + noise.next() * maxDot
            let white = light ? 1.0 : 0.0
            context.setFillColor(UIColor(white: white, alpha: alpha * (0.4 + noise.next() * 0.6)).cgColor)
            context.fill(CGRect(x: x, y: y, width: d, height: d))
        }
    }

    // MARK: Building styles

    enum Style: Int, CaseIterable {
        case apartment
        case brick
        case office
        case concrete
    }

    static let wallColors: [Style: [UIColor]] = [
        .apartment: [UIColor(red: 0.93, green: 0.85, blue: 0.72, alpha: 1), UIColor(red: 0.95, green: 0.76, blue: 0.56, alpha: 1),
                     UIColor(red: 0.86, green: 0.70, blue: 0.72, alpha: 1), UIColor(red: 0.78, green: 0.84, blue: 0.72, alpha: 1)],
        .brick: [UIColor(red: 0.66, green: 0.34, blue: 0.26, alpha: 1), UIColor(red: 0.55, green: 0.30, blue: 0.24, alpha: 1)],
        .office: [UIColor(red: 0.30, green: 0.45, blue: 0.58, alpha: 1), UIColor(red: 0.28, green: 0.38, blue: 0.42, alpha: 1)],
        .concrete: [UIColor(red: 0.80, green: 0.80, blue: 0.78, alpha: 1), UIColor(red: 0.68, green: 0.69, blue: 0.70, alpha: 1)]
    ]

    static func wallColor(_ style: Style, variant: Int) -> UIColor {
        let list = wallColors[style] ?? [.gray]
        return list[variant % list.count]
    }

    /// One bay of an upper floor: 4 m wide, one floor (3.2 m) tall.
    static func facade(_ style: Style, variant: Int) -> UIImage {
        cached("facade-\(style.rawValue)-\(variant)") {
            let color = wallColor(style, variant: variant)
            return CarArt.image(CGSize(width: 128, height: 104), scale: 1) { context, s in
                context.setFillColor(color.cgColor)
                context.fill(CGRect(origin: .zero, size: s))
                switch style {
                case .apartment:
                    speckle(context, s, count: 220, alpha: 0.08, seed: 11)
                    // Slab line, window with frame and sill, small balcony rail
                    context.setFillColor(color.darker(by: 0.1).cgColor)
                    context.fill(CGRect(x: 0, y: s.height - 7, width: s.width, height: 7))
                    window(context, CGRect(x: 30, y: 18, width: 68, height: 54), frame: UIColor(white: 0.96, alpha: 1), seed: UInt64(variant))
                    context.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
                    context.fill(CGRect(x: 26, y: 72, width: 76, height: 5))
                    context.setFillColor(UIColor(white: 0.25, alpha: 0.55).cgColor)
                    for x in stride(from: CGFloat(30), through: 98, by: 6) { context.fill(CGRect(x: x, y: 78, width: 2, height: 15)) }
                    context.fill(CGRect(x: 28, y: 78, width: 72, height: 2))
                case .brick:
                    // Brick courses
                    var noise = Noise(state: 7)
                    for row in 0..<Int(s.height / 6) {
                        let y = CGFloat(row) * 6
                        let offset: CGFloat = row % 2 == 0 ? 0 : 7
                        for col in -1..<Int(s.width / 14) + 1 {
                            let shade = 0.85 + noise.next() * 0.25
                            context.setFillColor(color.darker(by: 1 - shade).cgColor)
                            context.fill(CGRect(x: CGFloat(col) * 14 + offset, y: y, width: 13, height: 5))
                        }
                    }
                    context.setFillColor(UIColor(white: 0.85, alpha: 1).cgColor)
                    context.fill(CGRect(x: 34, y: 14, width: 60, height: 6))   // stone lintel
                    window(context, CGRect(x: 38, y: 20, width: 52, height: 60), frame: UIColor(white: 0.92, alpha: 1), seed: UInt64(variant + 4))
                    context.setFillColor(UIColor(white: 0.82, alpha: 1).cgColor)
                    context.fill(CGRect(x: 34, y: 80, width: 60, height: 5))   // sill
                case .office:
                    // Curtain wall: tinted glass panels with thin mullions and a spandrel band
                    let glassTop = UIColor(red: 0.62, green: 0.78, blue: 0.92, alpha: 1)
                    let glassBottom = color
                    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                 colors: [glassTop.cgColor, glassBottom.cgColor] as CFArray, locations: [0, 1]) {
                        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: s.width * 0.4, y: s.height), options: [])
                    }
                    context.setFillColor(UIColor(white: 1, alpha: 0.18).cgColor)
                    context.fill(CGRect(x: 10, y: 0, width: 18, height: s.height))
                    context.setFillColor(color.darker(by: 0.35).cgColor)
                    context.fill(CGRect(x: 0, y: s.height - 16, width: s.width, height: 16))
                    context.setFillColor(UIColor(white: 0.85, alpha: 1).cgColor)
                    for x in [0, 64] as [CGFloat] { context.fill(CGRect(x: x, y: 0, width: 3, height: s.height)) }
                    context.fill(CGRect(x: 0, y: s.height - 17, width: s.width, height: 2))
                case .concrete:
                    speckle(context, s, count: 400, alpha: 0.10, seed: 23)
                    // Horizontal ribbon window
                    context.setFillColor(color.darker(by: 0.12).cgColor)
                    context.fill(CGRect(x: 0, y: 0, width: s.width, height: 4))
                    let ribbon = CGRect(x: 0, y: 26, width: s.width, height: 46)
                    context.setFillColor(UIColor(red: 0.18, green: 0.24, blue: 0.30, alpha: 1).cgColor)
                    context.fill(ribbon)
                    context.setFillColor(UIColor(red: 0.55, green: 0.70, blue: 0.85, alpha: 0.45).cgColor)
                    context.fill(CGRect(x: 6, y: 30, width: 40, height: 38))
                    context.setFillColor(UIColor(white: 0.30, alpha: 1).cgColor)
                    for x in [0, 42, 85] as [CGFloat] { context.fill(CGRect(x: x, y: 26, width: 3, height: 46)) }
                }
            }
        }
    }

    private static func window(_ context: CGContext, _ rect: CGRect, frame: UIColor, seed: UInt64) {
        var noise = Noise(state: seed &+ 99)
        context.setFillColor(frame.cgColor)
        context.fill(rect.insetBy(dx: -3, dy: -3))
        let lit = noise.next() < 0.25
        context.setFillColor((lit ? UIColor(red: 0.95, green: 0.86, blue: 0.62, alpha: 1)
                                   : UIColor(red: 0.20, green: 0.28, blue: 0.38, alpha: 1)).cgColor)
        context.fill(rect)
        // Sky reflection and a curtain
        context.setFillColor(UIColor(red: 0.70, green: 0.82, blue: 0.95, alpha: lit ? 0.15 : 0.45).cgColor)
        context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.35, height: rect.height))
        if noise.next() < 0.5 {
            context.setFillColor(UIColor(white: 0.92, alpha: 0.75).cgColor)
            context.fill(CGRect(x: rect.maxX - rect.width * 0.3, y: rect.minY, width: rect.width * 0.3, height: rect.height * 0.8))
        }
        context.setFillColor(frame.cgColor)
        context.fill(CGRect(x: rect.midX - 1.5, y: rect.minY, width: 3, height: rect.height))
    }

    /// Ground floor: shop windows, a door and a sign band (6 m wide, 4.2 m tall).
    static func storefront(_ variant: Int) -> UIImage {
        cached("shop-\(variant % 4)") {
            let signs = [UIColor(red: 0.85, green: 0.18, blue: 0.20, alpha: 1), UIColor(red: 0.12, green: 0.42, blue: 0.75, alpha: 1),
                         UIColor(red: 0.12, green: 0.55, blue: 0.35, alpha: 1), UIColor(red: 0.95, green: 0.62, blue: 0.10, alpha: 1)]
            let sign = signs[variant % signs.count]
            return CarArt.image(CGSize(width: 192, height: 134), scale: 1) { context, s in
                context.setFillColor(UIColor(white: 0.22, alpha: 1).cgColor)
                context.fill(CGRect(origin: .zero, size: s))
                // Sign band with "letters"
                context.setFillColor(sign.cgColor)
                context.fill(CGRect(x: 0, y: 8, width: s.width, height: 24))
                context.setFillColor(UIColor(white: 1, alpha: 0.92).cgColor)
                var noise = Noise(state: UInt64(variant) &+ 5)
                var x: CGFloat = 40
                while x < 150 {
                    let w = 6 + noise.next() * 8
                    context.fill(CGRect(x: x, y: 14, width: w, height: 12))
                    x += w + 3
                }
                // Windows with display shelves and warm light
                for rect in [CGRect(x: 8, y: 40, width: 76, height: 78), CGRect(x: 124, y: 40, width: 60, height: 78)] {
                    context.setFillColor(UIColor(red: 0.95, green: 0.88, blue: 0.70, alpha: 1).cgColor)
                    context.fill(rect)
                    context.setFillColor(UIColor(red: 0.55, green: 0.42, blue: 0.30, alpha: 0.8).cgColor)
                    context.fill(CGRect(x: rect.minX, y: rect.minY + 34, width: rect.width, height: 4))
                    context.fill(CGRect(x: rect.minX, y: rect.minY + 58, width: rect.width, height: 4))
                    for _ in 0..<7 {
                        context.setFillColor(signs[Int(noise.next() * 3.99)].withAlphaComponent(0.8).cgColor)
                        context.fill(CGRect(x: rect.minX + 4 + noise.next() * (rect.width - 14), y: rect.minY + (noise.next() < 0.5 ? 24 : 48),
                                            width: 8, height: 10))
                    }
                    context.setFillColor(UIColor(red: 0.75, green: 0.88, blue: 1.0, alpha: 0.35).cgColor)
                    context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.3, height: rect.height))
                    context.setStrokeColor(UIColor(white: 0.12, alpha: 1).cgColor)
                    context.setLineWidth(3)
                    context.stroke(rect)
                }
                // Door
                context.setFillColor(UIColor(red: 0.35, green: 0.45, blue: 0.52, alpha: 1).cgColor)
                context.fill(CGRect(x: 92, y: 46, width: 26, height: 82))
                context.setFillColor(UIColor(white: 0.85, alpha: 1).cgColor)
                context.fill(CGRect(x: 112, y: 84, width: 3, height: 10))
                // Grime at the base
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.45).cgColor] as CFArray,
                                             locations: [0, 1]) {
                    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s.height - 22), end: CGPoint(x: 0, y: s.height), options: [])
                }
            }
        }
    }

    /// Glass lobby for office towers.
    static let lobby: UIImage = CarArt.image(CGSize(width: 128, height: 90), scale: 1) { context, s in
        context.setFillColor(UIColor(red: 0.85, green: 0.90, blue: 0.92, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: s))
        context.setFillColor(UIColor(red: 0.30, green: 0.40, blue: 0.48, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 14, width: s.width, height: s.height - 14))
        context.setFillColor(UIColor(red: 0.95, green: 0.92, blue: 0.80, alpha: 0.5).cgColor)
        context.fill(CGRect(x: 10, y: 24, width: 108, height: 50))
        context.setFillColor(UIColor(white: 0.9, alpha: 1).cgColor)
        for x in stride(from: CGFloat(0), through: s.width, by: 32) { context.fill(CGRect(x: x, y: 14, width: 3, height: s.height)) }
    }

    /// Gravel roof.
    static let roof: UIImage = CarArt.image(CGSize(width: 64, height: 64), scale: 1) { context, s in
        context.setFillColor(UIColor(red: 0.44, green: 0.44, blue: 0.45, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: s))
        speckle(context, s, count: 500, alpha: 0.25, seed: 3)
        speckle(context, s, count: 250, alpha: 0.2, seed: 4, light: true)
    }

    /// Striped awning cloth.
    static func awning(_ variant: Int) -> UIImage {
        cached("awning-\(variant % 4)") {
            let colors = [UIColor(red: 0.80, green: 0.15, blue: 0.18, alpha: 1), UIColor(red: 0.10, green: 0.45, blue: 0.40, alpha: 1),
                          UIColor(red: 0.15, green: 0.30, blue: 0.62, alpha: 1), UIColor(red: 0.90, green: 0.55, blue: 0.10, alpha: 1)]
            return CarArt.image(CGSize(width: 64, height: 16), scale: 1) { context, s in
                context.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor)
                context.fill(CGRect(origin: .zero, size: s))
                context.setFillColor(colors[variant % colors.count].cgColor)
                for x in stride(from: CGFloat(0), to: s.width, by: 16) { context.fill(CGRect(x: x, y: 0, width: 8, height: s.height)) }
            }
        }
    }

    // MARK: Ground

    /// Square concrete pavers (2 x 2 tiles of 1 m).
    static let pavers: UIImage = CarArt.image(CGSize(width: 128, height: 128), scale: 1) { context, s in
        context.setFillColor(UIColor(red: 0.70, green: 0.69, blue: 0.66, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: s))
        var noise = Noise(state: 17)
        for row in 0..<4 {
            for col in 0..<4 {
                let shade = 0.94 + noise.next() * 0.1
                context.setFillColor(UIColor(red: 0.74 * shade, green: 0.73 * shade, blue: 0.70 * shade, alpha: 1).cgColor)
                context.fill(CGRect(x: CGFloat(col) * 32 + 1, y: CGFloat(row) * 32 + 1, width: 30, height: 30))
            }
        }
        speckle(context, s, count: 300, alpha: 0.12, seed: 18)
    }

    /// Asphalt for a 20 m stretch of street: noise, tyre wear in the lanes, patches, parking bay
    /// ticks in the parking strips, the lane lines. U runs along the street.
    static let road: UIImage = CarArt.image(CGSize(width: 256, height: 256), scale: 1) { context, s in
        let k = s.height / 200
        context.setFillColor(UIColor(red: 0.27, green: 0.28, blue: 0.31, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: s))
        // Parking strips slightly lighter
        context.setFillColor(UIColor(red: 0.32, green: 0.33, blue: 0.36, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: s.width, height: 30 * k))
        context.fill(CGRect(x: 0, y: s.height - 30 * k, width: s.width, height: 30 * k))
        speckle(context, s, count: 2600, alpha: 0.22, seed: 41)
        speckle(context, s, count: 1400, alpha: 0.10, seed: 42, light: true)
        // Darker tyre tracks in each lane
        context.setFillColor(UIColor(white: 0.0, alpha: 0.10).cgColor)
        for lane in [65.0, 135.0] as [CGFloat] {
            for offset in [-12.0, 12.0] as [CGFloat] {
                context.fill(CGRect(x: 0, y: (lane + offset) * k - 4, width: s.width, height: 8))
            }
        }
        // A patch and a crack
        context.setFillColor(UIColor(red: 0.23, green: 0.24, blue: 0.27, alpha: 1).cgColor)
        context.fill(CGRect(x: 150, y: 80 * k, width: 46, height: 22))
        context.setStrokeColor(UIColor(white: 0.1, alpha: 0.5).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: 30, y: 120 * k))
        context.addLine(to: CGPoint(x: 52, y: 126 * k))
        context.addLine(to: CGPoint(x: 70, y: 121 * k))
        context.addLine(to: CGPoint(x: 96, y: 128 * k))
        context.strokePath()
        // Edge lines between lanes and strips
        context.setFillColor(UIColor(white: 0.92, alpha: 0.9).cgColor)
        context.fill(CGRect(x: 0, y: 30 * k - 2, width: s.width, height: 4))
        context.fill(CGRect(x: 0, y: s.height - 30 * k - 2, width: s.width, height: 4))
        // Parking bay ticks every 5 m
        context.setFillColor(UIColor(white: 0.9, alpha: 0.75).cgColor)
        for x in stride(from: CGFloat(0), to: s.width, by: s.width / 4) {
            context.fill(CGRect(x: x, y: 4, width: 3, height: 30 * k - 6))
            context.fill(CGRect(x: x, y: s.height - 30 * k + 2, width: 3, height: 30 * k - 6))
        }
        // Dashed center line
        context.setFillColor(UIColor(red: 1.0, green: 0.84, blue: 0.30, alpha: 1).cgColor)
        context.fill(CGRect(x: 12, y: s.height / 2 - 3, width: s.width / 2 - 24, height: 6))
        context.fill(CGRect(x: s.width / 2 + 12, y: s.height / 2 - 3, width: s.width / 2 - 24, height: 6))
        // Gutter by the curb
        context.setFillColor(UIColor(white: 0.62, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: s.width, height: 3))
        context.fill(CGRect(x: 0, y: s.height - 3, width: s.width, height: 3))
    }

    /// The same street turned 90° (V runs along the street) for north-south roads.
    static let roadVertical: UIImage = {
        let source = road
        return CarArt.image(CGSize(width: source.size.height, height: source.size.width), scale: 1) { context, s in
            context.translateBy(x: s.width / 2, y: s.height / 2)
            context.rotate(by: .pi / 2)
            source.draw(in: CGRect(x: -source.size.width / 2, y: -source.size.height / 2, width: source.size.width, height: source.size.height))
        }
    }()

    /// Intersection asphalt with the same noise as the streets.
    static let junction: UIImage = CarArt.image(CGSize(width: 128, height: 128), scale: 1) { context, s in
        context.setFillColor(UIColor(red: 0.27, green: 0.28, blue: 0.31, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: s))
        speckle(context, s, count: 1300, alpha: 0.22, seed: 51)
        speckle(context, s, count: 700, alpha: 0.10, seed: 52, light: true)
    }

    /// Soft shadow strip: black at the top (v = 0) fading to clear at the bottom.
    static let contactShadow: UIImage = CarArt.image(CGSize(width: 8, height: 64), scale: 1) { context, s in
        let colors = [UIColor(white: 0, alpha: 0.5).cgColor, UIColor(white: 0, alpha: 0.18).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: s.height), options: [])
        }
    }

    /// Round soft shadow (under trees, props).
    static let blobShadow: UIImage = CarArt.image(CGSize(width: 64, height: 64), scale: 1) { context, s in
        let colors = [UIColor(white: 0, alpha: 0.42).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                       endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
    }

    /// Manhole cover.
    static let manhole: UIImage = CarArt.image(CGSize(width: 64, height: 64), scale: 1) { context, s in
        let rect = CGRect(x: 4, y: 4, width: 56, height: 56)
        context.setFillColor(UIColor(white: 0.16, alpha: 1).cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(UIColor(white: 0.32, alpha: 1).cgColor)
        context.setLineWidth(3)
        context.strokeEllipse(in: rect.insetBy(dx: 3, dy: 3))
        context.setLineWidth(2)
        for y in stride(from: CGFloat(18), through: 46, by: 7) {
            context.move(to: CGPoint(x: 14, y: y))
            context.addLine(to: CGPoint(x: 50, y: y))
        }
        context.strokePath()
    }

    /// White straight-ahead lane arrow, pointing to the top of the image.
    static let laneArrow: UIImage = CarArt.image(CGSize(width: 32, height: 128), scale: 1) { context, s in
        context.setFillColor(UIColor(white: 0.95, alpha: 0.9).cgColor)
        context.fill(CGRect(x: 12, y: 40, width: 8, height: 86))
        let head = CGMutablePath()
        head.move(to: CGPoint(x: 16, y: 2))
        head.addLine(to: CGPoint(x: 31, y: 44))
        head.addLine(to: CGPoint(x: 1, y: 44))
        head.closeSubpath()
        context.addPath(head)
        context.fillPath()
    }

    // MARK: Skyline and sky

    /// Far-away tower at dusk-blue with a few lit windows.
    static let skyline: UIImage = CarArt.image(CGSize(width: 64, height: 128), scale: 1) { context, s in
        context.setFillColor(UIColor(red: 0.50, green: 0.58, blue: 0.70, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: s))
        var noise = Noise(state: 61)
        for row in 0..<16 {
            for col in 0..<6 {
                let lit = noise.next()
                let color = lit > 0.85 ? UIColor(red: 0.95, green: 0.90, blue: 0.75, alpha: 1)
                    : UIColor(red: 0.40, green: 0.48, blue: 0.60, alpha: 1)
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: 4 + CGFloat(col) * 10, y: 4 + CGFloat(row) * 8, width: 6, height: 4))
            }
        }
    }

    /// Yellow and black diagonal hazard stripes (jump ramps).
    static let hazardStripes: UIImage = CarArt.image(CGSize(width: 128, height: 128), scale: 1) { context, s in
        context.setFillColor(UIColor(red: 0.98, green: 0.78, blue: 0.1, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: s))
        context.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
        // 45° stripes with a 64 px period: the 128 px tile repeats seamlessly
        for k in stride(from: -3, through: 3, by: 1) {
            let x = CGFloat(k) * 64
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x + 32, y: 0))
            context.addLine(to: CGPoint(x: x + 32 + s.height, y: s.height))
            context.addLine(to: CGPoint(x: x + s.height, y: s.height))
            context.closePath()
            context.fillPath()
        }
    }

    /// Night sky: deep blue-black, a warm city glow at the horizon, a scatter of stars.
    static let nightSky: UIImage = CarArt.image(CGSize(width: 1024, height: 512), scale: 1) { context, s in
        let colors = [UIColor(red: 0.01, green: 0.015, blue: 0.05, alpha: 1).cgColor,
                      UIColor(red: 0.04, green: 0.06, blue: 0.14, alpha: 1).cgColor,
                      UIColor(red: 0.20, green: 0.15, blue: 0.16, alpha: 1).cgColor,
                      UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.36, 0.5, 0.56]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: s.height), options: [.drawsAfterEndLocation])
        }
        var noise = Noise(state: 91)
        for _ in 0..<260 {
            let x = noise.next() * s.width
            let y = noise.next() * s.height * 0.42
            let size = 0.6 + noise.next() * 1.4
            context.setFillColor(UIColor(white: 1, alpha: 0.35 + noise.next() * 0.6).cgColor)
            context.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
        }
    }

    /// Overcast rain sky: flat grey with darker cloud bands.
    static let rainSky: UIImage = CarArt.image(CGSize(width: 1024, height: 512), scale: 1) { context, s in
        // Storm: heavy blue-grey clouds, a pale band of mist on the horizon
        let colors = [UIColor(red: 0.13, green: 0.15, blue: 0.19, alpha: 1).cgColor,
                      UIColor(red: 0.27, green: 0.30, blue: 0.36, alpha: 1).cgColor,
                      UIColor(red: 0.46, green: 0.50, blue: 0.56, alpha: 1).cgColor,
                      UIColor(red: 0.22, green: 0.24, blue: 0.27, alpha: 1).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.3, 0.5, 0.56]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: s.height), options: [.drawsAfterEndLocation])
        }
        var noise = Noise(state: 93)
        for _ in 0..<40 {
            let cx = noise.next() * s.width
            let cy = s.height * (0.08 + noise.next() * 0.36)
            let w = 120 + noise.next() * 220
            let puff = [UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 0.35).cgColor, UIColor(white: 0.1, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: puff, locations: [0, 1]) {
                context.saveGState()
                context.translateBy(x: cx, y: cy)
                context.scaleBy(x: 1, y: 0.3)
                context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: w / 2, options: [])
                context.restoreGState()
            }
        }
    }

    /// Equirectangular sky: deep blue at the top, hazy horizon, soft clouds, and a ground tone below.
    static let sky: UIImage = CarArt.image(CGSize(width: 1024, height: 512), scale: 1) { context, s in
        let colors = [UIColor(red: 0.32, green: 0.56, blue: 0.92, alpha: 1).cgColor,
                      UIColor(red: 0.58, green: 0.76, blue: 0.97, alpha: 1).cgColor,
                      UIColor(red: 0.90, green: 0.93, blue: 0.97, alpha: 1).cgColor,
                      UIColor(red: 0.62, green: 0.65, blue: 0.64, alpha: 1).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.32, 0.5, 0.56]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: s.height), options: [.drawsAfterEndLocation])
        }
        // Clouds: clusters of soft white puffs between 22% and 46% of the height
        var noise = Noise(state: 77)
        for _ in 0..<26 {
            let cx = noise.next() * s.width
            let cy = s.height * (0.22 + noise.next() * 0.22)
            let scale = 0.5 + noise.next() * 1.0
            let flatten = 0.35 + (cy / s.height - 0.22) * 0.6   // flatter near the horizon
            for _ in 0..<7 {
                let w = (40 + noise.next() * 60) * scale
                let h = w * flatten
                let x = cx + (noise.next() - 0.5) * 110 * scale
                let y = cy + (noise.next() - 0.5) * 16 * scale
                let puff = [UIColor(white: 1, alpha: 0.55).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: puff, locations: [0, 1]) {
                    context.saveGState()
                    context.translateBy(x: x, y: y)
                    context.scaleBy(x: 1, y: h / w)
                    context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: w / 2, options: [])
                    context.restoreGState()
                }
            }
        }
    }

    // MARK: Landmarks

    /// Big blue parking sign.
    static let parkingSign: UIImage = CarArt.image(CGSize(width: 64, height: 64), scale: 1) { context, s in
        context.setFillColor(UIColor(red: 0.08, green: 0.36, blue: 0.85, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: s))
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(3)
        context.stroke(CGRect(x: 4, y: 4, width: 56, height: 56))
        let font = UIFont.systemFont(ofSize: 44, weight: .black)
        ("P" as NSString).draw(at: CGPoint(x: 18, y: 4), withAttributes: [.font: font, .foregroundColor: UIColor.white])
    }

    /// Fuel station sign with a price board.
    static let fuelSign: UIImage = CarArt.image(CGSize(width: 64, height: 128), scale: 1) { context, s in
        context.setFillColor(UIColor(red: 0.10, green: 0.55, blue: 0.30, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: s))
        context.setFillColor(UIColor(red: 1.0, green: 0.82, blue: 0.1, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: 10, y: 8, width: 44, height: 44))
        context.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
        context.fill(CGRect(x: 8, y: 62, width: 48, height: 58))
        let font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        for (k, price) in ["44.9", "46.2", "47.8"].enumerated() {
            (price as NSString).draw(at: CGPoint(x: 18, y: 66 + CGFloat(k) * 17),
                                     withAttributes: [.font: font, .foregroundColor: UIColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 1)])
        }
    }

    /// Red band under the fuel canopy roof.
    static let canopyBand: UIImage = CarArt.image(CGSize(width: 64, height: 16), scale: 1) { context, s in
        context.setFillColor(UIColor(red: 0.10, green: 0.55, blue: 0.30, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: s))
        context.setFillColor(UIColor(red: 1.0, green: 0.82, blue: 0.1, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 11, width: s.width, height: 3))
    }

    /// Lawn with mowing stripes.
    static let lawn: UIImage = CarArt.image(CGSize(width: 64, height: 64), scale: 1) { context, s in
        context.setFillColor(UIColor(red: 0.40, green: 0.62, blue: 0.32, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: s))
        context.setFillColor(UIColor(red: 0.44, green: 0.67, blue: 0.35, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: s.width / 2, height: s.height))
        speckle(context, s, count: 300, alpha: 0.15, seed: 91)
    }

    /// Nitro pickup label band (blue with a white flame).
    static let nitroCan: UIImage = CarArt.image(CGSize(width: 64, height: 64), scale: 1) { context, s in
        context.setFillColor(UIColor(red: 0.08, green: 0.45, blue: 0.95, alpha: 1).cgColor)
        context.fill(CGRect(origin: .zero, size: s))
        context.setFillColor(UIColor(white: 1, alpha: 0.95).cgColor)
        context.fill(CGRect(x: 0, y: 6, width: s.width, height: 4))
        context.fill(CGRect(x: 0, y: s.height - 10, width: s.width, height: 4))
        let font = UIFont.systemFont(ofSize: 20, weight: .black)
        ("N2O" as NSString).draw(at: CGPoint(x: 10, y: 20), withAttributes: [.font: font, .foregroundColor: UIColor.white])
    }

    /// Speed camera sign (white with a red border and a camera).
    static let radarSign: UIImage = CarArt.image(CGSize(width: 64, height: 64), scale: 1) { context, s in
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: s))
        context.setStrokeColor(UIColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1).cgColor)
        context.setLineWidth(6)
        context.stroke(CGRect(x: 3, y: 3, width: 58, height: 58))
        context.setFillColor(UIColor(white: 0.1, alpha: 1).cgColor)
        context.fill(CGRect(x: 16, y: 24, width: 28, height: 18))
        context.fillEllipse(in: CGRect(x: 40, y: 27, width: 12, height: 12))
        context.fill(CGRect(x: 22, y: 19, width: 10, height: 5))
    }
}

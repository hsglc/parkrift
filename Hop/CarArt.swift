import SpriteKit
import UIKit

/// Procedurally drawn textures for the parking game (top-down 2D with soft depth).
enum CarArt {

    static let playerColors: [UIColor] = [
        UIColor(red: 0.95, green: 0.26, blue: 0.27, alpha: 1),   // slot 0: red
        UIColor(red: 0.18, green: 0.53, blue: 0.98, alpha: 1)    // slot 1: blue
    ]

    static let parkedColors: [UIColor] = [
        UIColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1),
        UIColor(red: 0.24, green: 0.26, blue: 0.30, alpha: 1),
        UIColor(red: 0.98, green: 0.78, blue: 0.22, alpha: 1),
        UIColor(red: 0.20, green: 0.66, blue: 0.48, alpha: 1),
        UIColor(red: 0.56, green: 0.40, blue: 0.86, alpha: 1),
        UIColor(red: 0.98, green: 0.55, blue: 0.26, alpha: 1)
    ]

    // MARK: Helpers

    static let buildingColors: [UIColor] = [
        UIColor(red: 0.93, green: 0.86, blue: 0.74, alpha: 1),
        UIColor(red: 0.80, green: 0.55, blue: 0.45, alpha: 1),
        UIColor(red: 0.62, green: 0.72, blue: 0.82, alpha: 1),
        UIColor(red: 0.90, green: 0.90, blue: 0.88, alpha: 1),
        UIColor(red: 0.72, green: 0.80, blue: 0.66, alpha: 1),
        UIColor(red: 0.95, green: 0.74, blue: 0.52, alpha: 1),
        UIColor(red: 0.56, green: 0.56, blue: 0.62, alpha: 1),
        UIColor(red: 0.85, green: 0.66, blue: 0.70, alpha: 1)
    ]

    private static var facadeCache: [Int: UIImage] = [:]

    /// One window bay (4 m wide, 3.2 m tall) of a building wall; repeat it across the facade.
    static func facadeImage(tint: Int) -> UIImage {
        let index = tint % buildingColors.count
        if let cached = facadeCache[index] { return cached }
        let color = buildingColors[index]
        let result = image(CGSize(width: 64, height: 52), scale: 1) { context, s in
            context.setFillColor(color.cgColor)
            context.fill(CGRect(origin: .zero, size: s))
            context.setFillColor(color.darker(by: 0.12).cgColor)
            context.fill(CGRect(x: 0, y: s.height - 5, width: s.width, height: 5))
            let window = CGRect(x: 14, y: 12, width: 36, height: 26)
            context.setFillColor(UIColor(red: 0.20, green: 0.30, blue: 0.42, alpha: 1).cgColor)
            context.fill(window)
            context.setFillColor(UIColor(red: 0.55, green: 0.72, blue: 0.88, alpha: 0.55).cgColor)
            context.fill(CGRect(x: window.minX + 3, y: window.minY + 3, width: 12, height: window.height - 6))
            context.setStrokeColor(color.lighter(by: 0.2).cgColor)
            context.setLineWidth(2)
            context.stroke(window)
        }
        facadeCache[index] = result
        return result
    }

    /// 200 x 200 street tile (20 m): lanes with a dashed center line, solid lines at the
    /// parking strips and curbs. U runs along the street.
    static func roadImage() -> UIImage {
        image(CGSize(width: 128, height: 128), scale: 1) { context, s in
            let k = s.height / 200
            context.setFillColor(UIColor(red: 0.27, green: 0.28, blue: 0.31, alpha: 1).cgColor)
            context.fill(CGRect(origin: .zero, size: s))
            // Parking strips slightly lighter
            context.setFillColor(UIColor(red: 0.33, green: 0.34, blue: 0.37, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: s.width, height: 30 * k))
            context.fill(CGRect(x: 0, y: s.height - 30 * k, width: s.width, height: 30 * k))
            // Solid edge lines between lanes and strips
            context.setFillColor(UIColor(white: 0.92, alpha: 0.9).cgColor)
            context.fill(CGRect(x: 0, y: 30 * k - 1.5, width: s.width, height: 3))
            context.fill(CGRect(x: 0, y: s.height - 30 * k - 1.5, width: s.width, height: 3))
            // Dashed center line
            context.setFillColor(UIColor(red: 1.0, green: 0.84, blue: 0.30, alpha: 1).cgColor)
            context.fill(CGRect(x: 8, y: s.height / 2 - 2, width: s.width / 2 - 16, height: 4))
            context.fill(CGRect(x: s.width / 2 + 8, y: s.height / 2 - 2, width: s.width / 2 - 16, height: 4))
            // Curb edge
            context.setFillColor(UIColor(white: 0.75, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: s.width, height: 2))
            context.fill(CGRect(x: 0, y: s.height - 2, width: s.width, height: 2))
        }
    }

    /// Black and white checkerboard (8 x 8) for the finish line.
    static func checkerImage() -> UIImage {
        image(CGSize(width: 64, height: 64), scale: 1) { context, s in
            let cell = s.width / 8
            for row in 0..<8 {
                for col in 0..<8 {
                    context.setFillColor(((row + col) % 2 == 0 ? UIColor(white: 0.97, alpha: 1) : UIColor(white: 0.08, alpha: 1)).cgColor)
                    context.fill(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                }
            }
        }
    }

    static func image(_ size: CGSize, scale: CGFloat? = nil, _ draw: (CGContext, CGSize) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        if let scale = scale { format.scale = scale }
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in draw(context.cgContext, size) }
    }

    private static func render(_ size: CGSize, scale: CGFloat? = nil, _ draw: (CGContext, CGSize) -> Void) -> SKTexture {
        SKTexture(image: image(size, scale: scale, draw))
    }

    private static func gradient(_ colors: [UIColor], _ locations: [CGFloat]? = nil) -> CGGradient? {
        let cgColors = colors.map { $0.cgColor } as CFArray
        if let locations = locations {
            return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations)
        }
        return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil)
    }

    private static func fill(_ context: CGContext, path: CGPath, colors: [UIColor], locations: [CGFloat]? = nil,
                             from start: CGPoint, to end: CGPoint) {
        guard let gradient = gradient(colors, locations) else { return }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    private static func polygonPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        if let first = points.first {
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }

    /// Fake gaussian blur: stacked, growing rounded rects with low alpha.
    private static func softRect(_ context: CGContext, rect: CGRect, corner: CGFloat, spread: CGFloat, alpha: CGFloat) {
        let steps = 8
        for step in 0..<steps {
            let t = CGFloat(step) / CGFloat(steps - 1)
            let inset = -spread * t
            let r = rect.insetBy(dx: inset, dy: inset)
            let path = CGPath(roundedRect: r, cornerWidth: min(corner + spread * t, r.height / 2),
                              cornerHeight: min(corner + spread * t, r.height / 2), transform: nil)
            context.addPath(path)
            context.setFillColor(UIColor.black.withAlphaComponent(alpha / CGFloat(steps)).cgColor)
            context.fillPath()
        }
    }

    // MARK: Cars (facing +x: front is on the right)

    static func carBody(color: UIColor, size: CGSize = Levels.carSize) -> SKTexture {
        SKTexture(image: carImage(color: color, size: size))
    }

    static func carImage(color: UIColor, size: CGSize = Levels.carSize) -> UIImage {
        image(size) { context, s in
            let w = s.width
            let h = s.height
            let bodyRect = CGRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1)
            let body = CGPath(roundedRect: bodyRect, cornerWidth: h * 0.40, cornerHeight: h * 0.40, transform: nil)

            // Rounded side shading: dark edges, bright spine
            fill(context, path: body,
                 colors: [color.darker(by: 0.26), color.lighter(by: 0.10), color.lighter(by: 0.18), color, color.darker(by: 0.30)],
                 locations: [0, 0.28, 0.45, 0.70, 1],
                 from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: h))

            // Bumpers: slightly darker ends
            context.saveGState()
            context.addPath(body)
            context.clip()
            if let ends = gradient([UIColor.black.withAlphaComponent(0.25), UIColor.clear, UIColor.clear,
                                    UIColor.black.withAlphaComponent(0.18)], [0, 0.12, 0.88, 1]) {
                context.drawLinearGradient(ends, start: .zero, end: CGPoint(x: w, y: 0), options: [])
            }
            context.restoreGState()

            // Hood creases
            context.setStrokeColor(color.darker(by: 0.18).withAlphaComponent(0.6).cgColor)
            context.setLineWidth(0.6)
            context.move(to: CGPoint(x: w * 0.76, y: h * 0.30))
            context.addLine(to: CGPoint(x: w * 0.95, y: h * 0.34))
            context.move(to: CGPoint(x: w * 0.76, y: h * 0.70))
            context.addLine(to: CGPoint(x: w * 0.95, y: h * 0.66))
            context.strokePath()

            // Windshield with reflection
            let windshield = polygonPath([CGPoint(x: w * 0.58, y: h * 0.21), CGPoint(x: w * 0.73, y: h * 0.13),
                                          CGPoint(x: w * 0.73, y: h * 0.87), CGPoint(x: w * 0.58, y: h * 0.79)])
            fill(context, path: windshield,
                 colors: [UIColor(red: 0.10, green: 0.15, blue: 0.24, alpha: 1), UIColor(red: 0.28, green: 0.40, blue: 0.56, alpha: 1)],
                 from: CGPoint(x: w * 0.58, y: 0), to: CGPoint(x: w * 0.73, y: 0))
            context.saveGState()
            context.addPath(windshield)
            context.clip()
            context.setFillColor(UIColor.white.withAlphaComponent(0.22).cgColor)
            context.addPath(polygonPath([CGPoint(x: w * 0.62, y: h * 0.10), CGPoint(x: w * 0.66, y: h * 0.10),
                                         CGPoint(x: w * 0.61, y: h * 0.90), CGPoint(x: w * 0.57, y: h * 0.90)]))
            context.fillPath()
            context.restoreGState()

            // Rear window
            let rear = polygonPath([CGPoint(x: w * 0.15, y: h * 0.17), CGPoint(x: w * 0.27, y: h * 0.23),
                                    CGPoint(x: w * 0.27, y: h * 0.77), CGPoint(x: w * 0.15, y: h * 0.83)])
            fill(context, path: rear,
                 colors: [UIColor(red: 0.26, green: 0.36, blue: 0.50, alpha: 1), UIColor(red: 0.10, green: 0.14, blue: 0.22, alpha: 1)],
                 from: CGPoint(x: w * 0.15, y: 0), to: CGPoint(x: w * 0.27, y: 0))

            // Side windows
            context.setStrokeColor(UIColor(red: 0.12, green: 0.17, blue: 0.26, alpha: 0.9).cgColor)
            context.setLineWidth(1.4)
            context.move(to: CGPoint(x: w * 0.29, y: h * 0.17))
            context.addLine(to: CGPoint(x: w * 0.56, y: h * 0.17))
            context.move(to: CGPoint(x: w * 0.29, y: h * 0.83))
            context.addLine(to: CGPoint(x: w * 0.56, y: h * 0.83))
            context.strokePath()

            // Roof with soft highlight
            let roofRect = CGRect(x: w * 0.28, y: h * 0.22, width: w * 0.29, height: h * 0.56)
            let roof = CGPath(roundedRect: roofRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
            fill(context, path: roof, colors: [color.lighter(by: 0.22), color.lighter(by: 0.06), color.darker(by: 0.08)],
                 from: CGPoint(x: 0, y: roofRect.minY), to: CGPoint(x: 0, y: roofRect.maxY))
            context.setFillColor(UIColor.white.withAlphaComponent(0.30).cgColor)
            let streak = CGPath(roundedRect: CGRect(x: w * 0.31, y: h * 0.27, width: w * 0.20, height: h * 0.07),
                                cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            context.addPath(streak)
            context.fillPath()

            // Lights
            context.setFillColor(UIColor(red: 1.0, green: 0.98, blue: 0.86, alpha: 1).cgColor)
            context.addPath(CGPath(roundedRect: CGRect(x: w - 4, y: h * 0.10, width: 3, height: 4.5), cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
            context.addPath(CGPath(roundedRect: CGRect(x: w - 4, y: h * 0.90 - 4.5, width: 3, height: 4.5), cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
            context.fillPath()
            context.setFillColor(UIColor(red: 0.92, green: 0.08, blue: 0.12, alpha: 1).cgColor)
            context.addPath(CGPath(roundedRect: CGRect(x: 1, y: h * 0.10, width: 2.4, height: 4.5), cornerWidth: 1, cornerHeight: 1, transform: nil))
            context.addPath(CGPath(roundedRect: CGRect(x: 1, y: h * 0.90 - 4.5, width: 2.4, height: 4.5), cornerWidth: 1, cornerHeight: 1, transform: nil))
            context.fillPath()

            // Outline
            context.addPath(body)
            context.setStrokeColor(color.darker(by: 0.40).cgColor)
            context.setLineWidth(0.9)
            context.strokePath()
        }
    }

    static func carShadow(size: CGSize = Levels.carSize) -> SKTexture {
        let pad: CGFloat = 8
        return render(CGSize(width: size.width + pad * 2, height: size.height + pad * 2)) { context, _ in
            softRect(context, rect: CGRect(x: pad, y: pad, width: size.width, height: size.height),
                     corner: size.height * 0.4, spread: 5, alpha: 0.55)
        }
    }

    static func wheel() -> SKTexture {
        render(CGSize(width: 10, height: 5)) { context, s in
            let path = CGPath(roundedRect: CGRect(origin: .zero, size: s), cornerWidth: 2, cornerHeight: 2, transform: nil)
            fill(context, path: path, colors: [UIColor(white: 0.25, alpha: 1), UIColor(white: 0.06, alpha: 1)],
                 from: .zero, to: CGPoint(x: 0, y: s.height))
            context.setStrokeColor(UIColor(white: 0.35, alpha: 1).cgColor)
            context.setLineWidth(0.6)
            for x in stride(from: 2.0, to: Double(s.width), by: 2.0) {
                context.move(to: CGPoint(x: x, y: 0.6))
                context.addLine(to: CGPoint(x: x, y: s.height - 0.6))
            }
            context.strokePath()
        }
    }

    static func headlightBeam() -> SKTexture {
        render(CGSize(width: 90, height: 60)) { context, s in
            let cone = polygonPath([CGPoint(x: 0, y: s.height * 0.38), CGPoint(x: s.width, y: 0),
                                    CGPoint(x: s.width, y: s.height), CGPoint(x: 0, y: s.height * 0.62)])
            fill(context, path: cone,
                 colors: [UIColor(red: 1, green: 0.95, blue: 0.75, alpha: 0.45), UIColor(red: 1, green: 0.95, blue: 0.75, alpha: 0)],
                 from: .zero, to: CGPoint(x: s.width, y: 0))
        }
    }

    // MARK: Ground and scenery

    static func asphalt(size: CGSize) -> SKTexture {
        SKTexture(image: asphaltImage(size: size))
    }

    static func asphaltImage(size: CGSize) -> UIImage {
        image(size, scale: 2) { context, s in
            let full = CGRect(origin: .zero, size: s)
            fill(context, path: CGPath(rect: full, transform: nil),
                 colors: [UIColor(red: 0.27, green: 0.29, blue: 0.33, alpha: 1), UIColor(red: 0.22, green: 0.24, blue: 0.28, alpha: 1)],
                 from: .zero, to: CGPoint(x: s.width, y: s.height))

            var generator = SystemRandomNumberGenerator()
            // Patches of older asphalt
            for _ in 0..<14 {
                let r = CGFloat.random(in: 40...110, using: &generator)
                let x = CGFloat.random(in: 0...s.width, using: &generator)
                let y = CGFloat.random(in: 0...s.height, using: &generator)
                context.setFillColor(UIColor(white: 1, alpha: 0.025).cgColor)
                context.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.6, width: r * 2, height: r * 1.2))
            }
            // Oil stains
            for _ in 0..<7 {
                let r = CGFloat.random(in: 8...18, using: &generator)
                let x = CGFloat.random(in: 40...(s.width - 40), using: &generator)
                let y = CGFloat.random(in: 40...(s.height - 40), using: &generator)
                context.setFillColor(UIColor(white: 0, alpha: 0.16).cgColor)
                context.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.7, width: r * 2, height: r * 1.4))
            }
            // Grain
            for _ in 0..<2200 {
                let x = CGFloat.random(in: 0...s.width, using: &generator)
                let y = CGFloat.random(in: 0...s.height, using: &generator)
                let light = Bool.random(using: &generator)
                context.setFillColor((light ? UIColor.white : UIColor.black).withAlphaComponent(0.06).cgColor)
                let r = CGFloat.random(in: 0.8...2.2, using: &generator)
                context.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
            // Old tire marks
            context.setStrokeColor(UIColor(white: 0, alpha: 0.10).cgColor)
            context.setLineWidth(3)
            for _ in 0..<5 {
                let cx = CGFloat.random(in: 150...(s.width - 150), using: &generator)
                let cy = CGFloat.random(in: 120...(s.height - 120), using: &generator)
                let r = CGFloat.random(in: 50...110, using: &generator)
                let a = CGFloat.random(in: 0...(2 * CGFloat.pi), using: &generator)
                context.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: a, endAngle: a + 1.2, clockwise: false)
                context.strokePath()
                context.addArc(center: CGPoint(x: cx, y: cy), radius: r + 9, startAngle: a, endAngle: a + 1.2, clockwise: false)
                context.strokePath()
            }
            // Dashed centre line and arrows
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.16).cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [20, 16])
            context.move(to: CGPoint(x: 40, y: s.height / 2))
            context.addLine(to: CGPoint(x: s.width - 40, y: s.height / 2))
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            context.setFillColor(UIColor.white.withAlphaComponent(0.14).cgColor)
            for x in [s.width * 0.25, s.width * 0.75] {
                context.addPath(polygonPath([CGPoint(x: x - 14, y: s.height / 2 - 26), CGPoint(x: x + 14, y: s.height / 2 - 34),
                                             CGPoint(x: x - 14, y: s.height / 2 - 42)]))
                context.fillPath()
            }

            // Curb around the lot: raised edge with light top and a shadow on the asphalt
            let curb: CGFloat = 10
            context.setFillColor(UIColor(red: 0.70, green: 0.71, blue: 0.73, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: s.width, height: curb))
            context.fill(CGRect(x: 0, y: s.height - curb, width: s.width, height: curb))
            context.fill(CGRect(x: 0, y: 0, width: curb, height: s.height))
            context.fill(CGRect(x: s.width - curb, y: 0, width: curb, height: s.height))
            context.setFillColor(UIColor.white.withAlphaComponent(0.35).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: s.width, height: 2))
            context.fill(CGRect(x: 0, y: 0, width: 2, height: s.height))
            context.setFillColor(UIColor.black.withAlphaComponent(0.28).cgColor)
            context.fill(CGRect(x: curb, y: curb, width: s.width - curb * 2, height: 3))
            context.fill(CGRect(x: curb, y: curb, width: 3, height: s.height - curb * 2))
            // Curb segment joints
            context.setStrokeColor(UIColor.black.withAlphaComponent(0.18).cgColor)
            context.setLineWidth(1)
            var x: CGFloat = 40
            while x < s.width {
                context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: curb))
                context.move(to: CGPoint(x: x, y: s.height - curb)); context.addLine(to: CGPoint(x: x, y: s.height))
                x += 40
            }
            context.strokePath()
        }
    }

    static func spot(size: CGSize, color: UIColor) -> SKTexture {
        SKTexture(image: spotImage(size: size, color: color))
    }

    static func spotImage(size: CGSize, color: UIColor) -> UIImage {
        image(size) { context, s in
            let rect = CGRect(origin: .zero, size: s)
            fill(context, path: CGPath(rect: rect, transform: nil),
                 colors: [color.withAlphaComponent(0.10), color.withAlphaComponent(0.30)],
                 from: .zero, to: CGPoint(x: s.width, y: 0))
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.92).cgColor)
            context.setLineWidth(2.5)
            context.stroke(rect.insetBy(dx: 1.25, dy: 1.25))
            let fontSize = min(s.width, s.height) * 0.58
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .black),
                .foregroundColor: UIColor.white.withAlphaComponent(0.42)
            ]
            let text = "P" as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (s.width - textSize.width) / 2, y: (s.height - textSize.height) / 2), withAttributes: attributes)
        }
    }

    /// Concrete block seen from above: light top face plus a darker visible side.
    static func wall(size: CGSize) -> SKTexture {
        SKTexture(image: wallImage(size: size))
    }

    static func wallImage(size: CGSize) -> UIImage {
        image(size) { context, s in
            let rect = CGRect(origin: .zero, size: s)
            let side: CGFloat = min(5, min(s.width, s.height) * 0.3)
            let sideRect = CGRect(x: 0, y: s.height - side, width: s.width, height: side)
            context.setFillColor(UIColor(red: 0.42, green: 0.43, blue: 0.47, alpha: 1).cgColor)
            context.fill(sideRect)
            let top = CGRect(x: 0, y: 0, width: s.width, height: s.height - side)
            let topPath = CGPath(roundedRect: top, cornerWidth: 2, cornerHeight: 2, transform: nil)
            fill(context, path: topPath,
                 colors: [UIColor(red: 0.86, green: 0.86, blue: 0.88, alpha: 1), UIColor(red: 0.68, green: 0.69, blue: 0.72, alpha: 1)],
                 from: .zero, to: CGPoint(x: s.width, y: s.height))
            // Hazard tape near the ends of long walls
            context.saveGState()
            context.addPath(topPath)
            context.clip()
            let long = max(s.width, s.height)
            let horizontal = s.width >= s.height
            let band: CGFloat = min(40, long * 0.25)
            let zones: [CGRect] = horizontal
                ? [CGRect(x: 0, y: 0, width: band, height: s.height), CGRect(x: s.width - band, y: 0, width: band, height: s.height)]
                : [CGRect(x: 0, y: 0, width: s.width, height: band), CGRect(x: 0, y: s.height - band, width: s.width, height: band)]
            for zone in zones {
                context.saveGState()
                context.clip(to: zone)
                context.setFillColor(UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1).cgColor)
                context.fill(zone)
                context.setFillColor(UIColor(red: 0.99, green: 0.80, blue: 0.18, alpha: 1).cgColor)
                var offset: CGFloat = -long
                while offset < long * 2 {
                    context.addPath(polygonPath([CGPoint(x: offset, y: 0), CGPoint(x: offset + 7, y: 0),
                                                 CGPoint(x: offset + 7 - long, y: long), CGPoint(x: offset - long, y: long)]))
                    offset += 14
                }
                context.fillPath()
                context.restoreGState()
            }
            context.restoreGState()
            context.setStrokeColor(UIColor(red: 0.36, green: 0.37, blue: 0.40, alpha: 1).cgColor)
            context.setLineWidth(1)
            context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        }
    }

    static func blockShadow(size: CGSize) -> SKTexture {
        let pad: CGFloat = 8
        return render(CGSize(width: size.width + pad * 2, height: size.height + pad * 2)) { context, _ in
            softRect(context, rect: CGRect(x: pad, y: pad, width: size.width, height: size.height), corner: 2, spread: 5, alpha: 0.5)
        }
    }

    static func cone(size: CGFloat) -> SKTexture {
        render(CGSize(width: size, height: size)) { context, s in
            let rect = CGRect(origin: .zero, size: s)
            let base = CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
            fill(context, path: base, colors: [UIColor(white: 0.30, alpha: 1), UIColor(white: 0.12, alpha: 1)],
                 from: .zero, to: CGPoint(x: s.width, y: s.height))
            let cone = CGPath(ellipseIn: rect.insetBy(dx: s.width * 0.14, dy: s.height * 0.14), transform: nil)
            fill(context, path: cone,
                 colors: [UIColor(red: 1.0, green: 0.66, blue: 0.30, alpha: 1), UIColor(red: 0.95, green: 0.36, blue: 0.06, alpha: 1)],
                 from: .zero, to: CGPoint(x: s.width, y: s.height))
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: rect.insetBy(dx: s.width * 0.31, dy: s.height * 0.31))
            context.setFillColor(UIColor(red: 1.0, green: 0.55, blue: 0.20, alpha: 1).cgColor)
            context.fillEllipse(in: rect.insetBy(dx: s.width * 0.40, dy: s.height * 0.40))
            context.setFillColor(UIColor.white.withAlphaComponent(0.6).cgColor)
            context.fillEllipse(in: CGRect(x: s.width * 0.30, y: s.height * 0.22, width: s.width * 0.14, height: s.height * 0.10))
        }
    }

    static func tree(radius: CGFloat) -> SKTexture {
        let side = radius * 2
        return render(CGSize(width: side, height: side)) { context, s in
            let blobs: [(CGFloat, CGFloat, CGFloat)] = [
                (0.50, 0.50, 0.46), (0.32, 0.38, 0.30), (0.66, 0.36, 0.28), (0.36, 0.66, 0.28), (0.66, 0.66, 0.30)
            ]
            for blob in blobs {
                let r = blob.2 * s.width
                let center = CGPoint(x: blob.0 * s.width, y: blob.1 * s.height)
                let circle = CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2), transform: nil)
                context.saveGState()
                context.addPath(circle)
                context.clip()
                if let shade = gradient([UIColor(red: 0.50, green: 0.78, blue: 0.40, alpha: 1),
                                         UIColor(red: 0.22, green: 0.52, blue: 0.26, alpha: 1),
                                         UIColor(red: 0.13, green: 0.36, blue: 0.18, alpha: 1)], [0, 0.6, 1]) {
                    context.drawRadialGradient(shade, startCenter: CGPoint(x: center.x - r * 0.35, y: center.y - r * 0.35),
                                               startRadius: 0, endCenter: center, endRadius: r, options: [])
                }
                context.restoreGState()
            }
        }
    }

    static func roundShadow(radius: CGFloat) -> SKTexture {
        let side = radius * 2 + 16
        return render(CGSize(width: side, height: side)) { context, s in
            let center = CGPoint(x: s.width / 2, y: s.height / 2)
            if let shade = gradient([UIColor.black.withAlphaComponent(0.40), UIColor.black.withAlphaComponent(0)], [0.55, 1]) {
                context.drawRadialGradient(shade, startCenter: center, startRadius: 0, endCenter: center, endRadius: s.width / 2, options: [])
            }
        }
    }

    static func grass(size: CGSize) -> SKTexture {
        SKTexture(image: grassImage(size: size))
    }

    static func grassImage(size: CGSize) -> UIImage {
        image(size, scale: 1) { context, s in
            fill(context, path: CGPath(rect: CGRect(origin: .zero, size: s), transform: nil),
                 colors: [UIColor(red: 0.33, green: 0.56, blue: 0.32, alpha: 1), UIColor(red: 0.24, green: 0.45, blue: 0.27, alpha: 1)],
                 from: .zero, to: CGPoint(x: s.width, y: s.height))
            var generator = SystemRandomNumberGenerator()
            let count = Int(s.width * s.height / 90)
            for _ in 0..<count {
                let x = CGFloat.random(in: 0...s.width, using: &generator)
                let y = CGFloat.random(in: 0...s.height, using: &generator)
                let light = Bool.random(using: &generator)
                context.setFillColor((light ? UIColor(red: 0.48, green: 0.72, blue: 0.40, alpha: 0.6)
                                            : UIColor(red: 0.16, green: 0.34, blue: 0.20, alpha: 0.5)).cgColor)
                context.fill(CGRect(x: x, y: y, width: 1.4, height: 3.2))
            }
        }
    }

    static func vignette(size: CGSize) -> SKTexture {
        render(size, scale: 1) { context, s in
            let center = CGPoint(x: s.width / 2, y: s.height / 2)
            let radius = hypot(s.width, s.height) / 2
            if let shade = gradient([UIColor.black.withAlphaComponent(0), UIColor.black.withAlphaComponent(0.42)], [0.55, 1]) {
                context.drawRadialGradient(shade, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                                           options: [.drawsAfterEndLocation])
            }
        }
    }

    static func dot() -> SKTexture {
        render(CGSize(width: 16, height: 16)) { context, s in
            let center = CGPoint(x: s.width / 2, y: s.height / 2)
            if let soft = gradient([UIColor.white, UIColor.white.withAlphaComponent(0)], [0.3, 1]) {
                context.drawRadialGradient(soft, startCenter: center, startRadius: 0, endCenter: center, endRadius: s.width / 2, options: [])
            }
        }
    }

    // MARK: UI

    static func symbol(_ name: String, pointSize: CGFloat, color: UIColor, weight: UIImage.SymbolWeight = .bold) -> SKTexture {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let base = UIImage(systemName: name, withConfiguration: configuration) else { return SKTexture() }
        let tinted = base.withTintColor(color, renderingMode: .alwaysOriginal)
        return render(base.size) { _, s in
            tinted.draw(in: CGRect(origin: .zero, size: s))
        }
    }

    static func glass(size: CGSize, corner: CGFloat) -> SKTexture {
        render(size) { context, s in
            let rect = CGRect(origin: .zero, size: s).insetBy(dx: 1, dy: 1)
            let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
            context.addPath(path)
            context.setFillColor(UIColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 0.55).cgColor)
            context.fillPath()
            context.saveGState()
            context.addPath(path)
            context.clip()
            if let sheen = gradient([UIColor.white.withAlphaComponent(0.10), UIColor.white.withAlphaComponent(0.0)]) {
                context.drawLinearGradient(sheen, start: .zero, end: CGPoint(x: 0, y: s.height * 0.6), options: [])
            }
            context.restoreGState()
            context.addPath(path)
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.18).cgColor)
            context.setLineWidth(1)
            context.strokePath()
        }
    }

    static func steeringWheel(diameter: CGFloat) -> SKTexture {
        render(CGSize(width: diameter, height: diameter)) { context, s in
            let center = CGPoint(x: s.width / 2, y: s.height / 2)
            let outer = s.width / 2 - 3
            let rimWidth = s.width * 0.13
            let inner = outer - rimWidth
            func ring(_ r1: CGFloat, _ r2: CGFloat) -> CGMutablePath {
                let path = CGMutablePath()
                path.addEllipse(in: CGRect(x: center.x - r1, y: center.y - r1, width: r1 * 2, height: r1 * 2))
                path.addEllipse(in: CGRect(x: center.x - r2, y: center.y - r2, width: r2 * 2, height: r2 * 2))
                return path
            }
            // Dark disc behind so the wheel reads on any background
            context.setFillColor(UIColor(white: 0, alpha: 0.28).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
            // Rim: bright, thick
            context.saveGState()
            context.addPath(ring(outer, inner))
            context.clip(using: .evenOdd)
            if let shade = gradient([UIColor(white: 0.98, alpha: 1), UIColor(white: 0.62, alpha: 1)]) {
                context.drawLinearGradient(shade, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: s.height), options: [])
            }
            context.restoreGState()
            // Rim outline
            context.setStrokeColor(UIColor(white: 0.1, alpha: 0.9).cgColor)
            context.setLineWidth(2)
            context.addPath(ring(outer, inner))
            context.strokePath()
            // Spokes (T shape: left, right, bottom)
            context.setLineCap(.round)
            for (width, color) in [(s.width * 0.12, UIColor(white: 0.1, alpha: 0.9)), (s.width * 0.08, UIColor(white: 0.88, alpha: 1))] {
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(width)
                for angle in [CGFloat.pi, 0, CGFloat.pi / 2] {
                    context.move(to: center)
                    context.addLine(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                }
                context.strokePath()
            }
            // Hub
            let hubR = s.width * 0.16
            let hub = CGPath(ellipseIn: CGRect(x: center.x - hubR, y: center.y - hubR, width: hubR * 2, height: hubR * 2), transform: nil)
            fill(context, path: hub, colors: [UIColor(white: 0.35, alpha: 1), UIColor(white: 0.10, alpha: 1)],
                 from: CGPoint(x: 0, y: center.y - hubR), to: CGPoint(x: 0, y: center.y + hubR))
            // Big top marker so the rotation is obvious
            let marker = CGMutablePath()
            marker.addArc(center: center, radius: outer + 1, startAngle: -CGFloat.pi / 2 - 0.30, endAngle: -CGFloat.pi / 2 + 0.30, clockwise: false)
            marker.addArc(center: center, radius: inner - 1, startAngle: -CGFloat.pi / 2 + 0.30, endAngle: -CGFloat.pi / 2 - 0.30, clockwise: true)
            marker.closeSubpath()
            context.setFillColor(UIColor(red: 1.0, green: 0.78, blue: 0.10, alpha: 1).cgColor)
            context.addPath(marker)
            context.fillPath()
            context.setStrokeColor(UIColor(white: 0.1, alpha: 0.9).cgColor)
            context.setLineWidth(2)
            context.addPath(marker)
            context.strokePath()
            // Arrow on the hub pointing up (the car's nose)
            let arrow = CGMutablePath()
            arrow.move(to: CGPoint(x: center.x, y: center.y - hubR * 0.65))
            arrow.addLine(to: CGPoint(x: center.x + hubR * 0.5, y: center.y + hubR * 0.35))
            arrow.addLine(to: CGPoint(x: center.x - hubR * 0.5, y: center.y + hubR * 0.35))
            arrow.closeSubpath()
            context.setFillColor(UIColor(red: 1.0, green: 0.78, blue: 0.10, alpha: 1).cgColor)
            context.addPath(arrow)
            context.fillPath()
        }
    }

    /// Chunky colored pedal with a darker raised edge (matches the menu buttons).
    static func pedal(size: CGSize, accent: UIColor) -> SKTexture {
        render(size) { context, s in
            let depth: CGFloat = 6
            let body = CGRect(x: 2, y: 2, width: s.width - 4, height: s.height - 4 - depth)
            let edge = body.offsetBy(dx: 0, dy: depth)
            let corner: CGFloat = 18
            context.addPath(CGPath(roundedRect: edge, cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.setFillColor(accent.darker(by: 0.45).withAlphaComponent(0.95).cgColor)
            context.fillPath()
            let face = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)
            fill(context, path: face, colors: [accent.lighter(by: 0.18).withAlphaComponent(0.95), accent.darker(by: 0.12).withAlphaComponent(0.95)],
                 from: CGPoint(x: 0, y: body.minY), to: CGPoint(x: 0, y: body.maxY))
            context.saveGState()
            context.addPath(face)
            context.clip()
            if let sheen = gradient([UIColor.white.withAlphaComponent(0.35), UIColor.white.withAlphaComponent(0.0)]) {
                context.drawLinearGradient(sheen, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.minY + 22), options: [])
            }
            context.restoreGState()
        }
    }

    // MARK: 3D surface helpers

    /// Glowing outline for a parking bay (drawn additively over the bay).
    static func spotOutlineImage(size: CGSize, color: UIColor) -> UIImage {
        image(size) { context, s in
            let rect = CGRect(origin: .zero, size: s)
            context.setStrokeColor(color.lighter(by: 0.25).withAlphaComponent(0.35).cgColor)
            context.setLineWidth(10)
            context.stroke(rect.insetBy(dx: 5, dy: 5))
            context.setStrokeColor(color.lighter(by: 0.35).cgColor)
            context.setLineWidth(3.5)
            context.stroke(rect.insetBy(dx: 4, dy: 4))
        }
    }

    /// Soft sky gradient used as the image-based lighting environment.
    static func skyImage() -> UIImage {
        image(CGSize(width: 128, height: 64), scale: 1) { context, s in
            fill(context, path: CGPath(rect: CGRect(origin: .zero, size: s), transform: nil),
                 colors: [UIColor(red: 0.52, green: 0.72, blue: 0.98, alpha: 1),
                          UIColor(red: 0.90, green: 0.94, blue: 1.00, alpha: 1),
                          UIColor(red: 0.62, green: 0.66, blue: 0.62, alpha: 1)],
                 locations: [0, 0.5, 1],
                 from: .zero, to: CGPoint(x: 0, y: s.height))
        }
    }
}

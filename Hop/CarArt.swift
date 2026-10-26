import SpriteKit
import UIKit

/// Procedurally drawn textures for the parking game (top-down view).
enum CarArt {

    static let playerColors: [UIColor] = [
        UIColor(red: 0.93, green: 0.28, blue: 0.24, alpha: 1),   // slot 0: red
        UIColor(red: 0.20, green: 0.52, blue: 0.95, alpha: 1)    // slot 1: blue
    ]

    static let parkedColors: [UIColor] = [
        UIColor(red: 0.85, green: 0.86, blue: 0.88, alpha: 1),
        UIColor(red: 0.30, green: 0.32, blue: 0.36, alpha: 1),
        UIColor(red: 0.96, green: 0.78, blue: 0.24, alpha: 1),
        UIColor(red: 0.26, green: 0.62, blue: 0.40, alpha: 1),
        UIColor(red: 0.58, green: 0.42, blue: 0.80, alpha: 1),
        UIColor(red: 0.95, green: 0.58, blue: 0.30, alpha: 1)
    ]

    // MARK: Helpers

    private static func render(_ size: CGSize, scale: CGFloat? = nil, _ draw: (CGContext, CGSize) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        if let scale = scale { format.scale = scale }
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in draw(context.cgContext, size) }
        return SKTexture(image: image)
    }

    private static func fill(_ context: CGContext, path: CGPath, colors: [UIColor], from start: CGPoint, to end: CGPoint) {
        let cgColors = colors.map { $0.cgColor } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) else { return }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    private static func polygon(_ context: CGContext, _ points: [CGPoint], color: UIColor) {
        guard let first = points.first else { return }
        let path = CGMutablePath()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath()
    }

    // MARK: Cars (facing +x: front is on the right)

    static func car(color: UIColor, size: CGSize = Levels.carSize) -> SKTexture {
        render(CGSize(width: size.width + 4, height: size.height + 4)) { context, canvas in
            let w = size.width
            let h = size.height
            context.translateBy(x: 2, y: 2)

            // Soft shadow
            context.setFillColor(UIColor.black.withAlphaComponent(0.28).cgColor)
            let shadow = CGPath(roundedRect: CGRect(x: 1, y: 2, width: w - 1, height: h - 1),
                                cornerWidth: h * 0.35, cornerHeight: h * 0.35, transform: nil)
            context.addPath(shadow)
            context.fillPath()

            // Mirrors
            context.setFillColor(color.darker(by: 0.25).cgColor)
            context.fill(CGRect(x: w * 0.60, y: -1.5, width: 3, height: 3))
            context.fill(CGRect(x: w * 0.60, y: h - 1.5, width: 3, height: 3))

            // Body
            let body = CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                              cornerWidth: h * 0.35, cornerHeight: h * 0.35, transform: nil)
            fill(context, path: body, colors: [color.lighter(by: 0.14), color, color.darker(by: 0.18)],
                 from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: h))
            context.addPath(body)
            context.setStrokeColor(color.darker(by: 0.35).cgColor)
            context.setLineWidth(1.2)
            context.strokePath()

            let glass = UIColor(red: 0.14, green: 0.20, blue: 0.30, alpha: 1)
            // Windshield (front)
            polygon(context, [CGPoint(x: w * 0.58, y: h * 0.20), CGPoint(x: w * 0.72, y: h * 0.12),
                              CGPoint(x: w * 0.72, y: h * 0.88), CGPoint(x: w * 0.58, y: h * 0.80)], color: glass)
            // Rear window
            polygon(context, [CGPoint(x: w * 0.17, y: h * 0.16), CGPoint(x: w * 0.27, y: h * 0.22),
                              CGPoint(x: w * 0.27, y: h * 0.78), CGPoint(x: w * 0.17, y: h * 0.84)], color: glass)
            // Roof
            let roof = CGPath(roundedRect: CGRect(x: w * 0.29, y: h * 0.18, width: w * 0.28, height: h * 0.64),
                              cornerWidth: 3, cornerHeight: 3, transform: nil)
            context.addPath(roof)
            context.setFillColor(color.lighter(by: 0.06).cgColor)
            context.fillPath()
            context.setFillColor(UIColor.white.withAlphaComponent(0.28).cgColor)
            context.fill(CGRect(x: w * 0.32, y: h * 0.24, width: w * 0.18, height: h * 0.10))

            // Headlights and taillights
            context.setFillColor(UIColor(red: 1.0, green: 0.97, blue: 0.80, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(x: w - 4.5, y: h * 0.10, width: 3.5, height: 4))
            context.fillEllipse(in: CGRect(x: w - 4.5, y: h * 0.90 - 4, width: 3.5, height: 4))
            context.setFillColor(UIColor(red: 0.85, green: 0.10, blue: 0.12, alpha: 1).cgColor)
            context.fill(CGRect(x: 0.8, y: h * 0.12, width: 2.2, height: 4))
            context.fill(CGRect(x: 0.8, y: h * 0.88 - 4, width: 2.2, height: 4))
            _ = canvas
        }
    }

    // MARK: Ground and props

    static func asphalt(size: CGSize) -> SKTexture {
        render(size, scale: 2) { context, s in
            context.setFillColor(UIColor(red: 0.29, green: 0.31, blue: 0.35, alpha: 1).cgColor)
            context.fill(CGRect(origin: .zero, size: s))
            // Grain
            var generator = SystemRandomNumberGenerator()
            for _ in 0..<1600 {
                let x = CGFloat.random(in: 0...s.width, using: &generator)
                let y = CGFloat.random(in: 0...s.height, using: &generator)
                let light = Bool.random(using: &generator)
                context.setFillColor((light ? UIColor.white : UIColor.black).withAlphaComponent(0.07).cgColor)
                let r = CGFloat.random(in: 1...2.5, using: &generator)
                context.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
            // Painted edge
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.55).cgColor)
            context.setLineWidth(3)
            context.stroke(CGRect(origin: .zero, size: s).insetBy(dx: 6, dy: 6))
            // Lane arrows painted faintly
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.12).cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [18, 14])
            context.move(to: CGPoint(x: 30, y: s.height / 2))
            context.addLine(to: CGPoint(x: s.width - 30, y: s.height / 2))
            context.strokePath()
        }
    }

    static func spot(size: CGSize, color: UIColor) -> SKTexture {
        render(size) { context, s in
            let rect = CGRect(origin: .zero, size: s)
            context.setFillColor(color.withAlphaComponent(0.22).cgColor)
            context.fill(rect)
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(3)
            context.stroke(rect.insetBy(dx: 1.5, dy: 1.5))
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.stroke(rect.insetBy(dx: 5, dy: 5))
            context.setLineDash(phase: 0, lengths: [])
            let fontSize = min(s.width, s.height) * 0.62
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.55)
            ]
            let text = "P" as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (s.width - textSize.width) / 2, y: (s.height - textSize.height) / 2),
                      withAttributes: attributes)
        }
    }

    static func wall(size: CGSize) -> SKTexture {
        render(size) { context, s in
            let rect = CGRect(origin: .zero, size: s)
            let path = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
            fill(context, path: path,
                 colors: [UIColor(red: 0.78, green: 0.78, blue: 0.80, alpha: 1),
                          UIColor(red: 0.58, green: 0.58, blue: 0.62, alpha: 1)],
                 from: .zero, to: CGPoint(x: s.width, y: s.height))
            context.addPath(path)
            context.setStrokeColor(UIColor(red: 0.42, green: 0.42, blue: 0.46, alpha: 1).cgColor)
            context.setLineWidth(2)
            context.strokePath()
            // Hazard stripes
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.setFillColor(UIColor(red: 0.98, green: 0.80, blue: 0.20, alpha: 0.85).cgColor)
            let long = max(s.width, s.height)
            var offset: CGFloat = -long
            while offset < long * 2 {
                let stripe = CGMutablePath()
                stripe.move(to: CGPoint(x: offset, y: 0))
                stripe.addLine(to: CGPoint(x: offset + 10, y: 0))
                stripe.addLine(to: CGPoint(x: offset + 10 - long, y: long))
                stripe.addLine(to: CGPoint(x: offset - long, y: long))
                stripe.closeSubpath()
                context.addPath(stripe)
                offset += 28
            }
            context.fillPath()
            context.restoreGState()
        }
    }

    static func cone(size: CGFloat) -> SKTexture {
        render(CGSize(width: size, height: size)) { context, s in
            let base = CGPath(roundedRect: CGRect(origin: .zero, size: s).insetBy(dx: 0.5, dy: 0.5),
                              cornerWidth: 2, cornerHeight: 2, transform: nil)
            context.addPath(base)
            context.setFillColor(UIColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1).cgColor)
            context.fillPath()
            context.setFillColor(UIColor(red: 1.0, green: 0.48, blue: 0.10, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(origin: .zero, size: s).insetBy(dx: s.width * 0.14, dy: s.height * 0.14))
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: CGRect(origin: .zero, size: s).insetBy(dx: s.width * 0.32, dy: s.height * 0.32))
            context.setFillColor(UIColor(red: 1.0, green: 0.60, blue: 0.25, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(origin: .zero, size: s).insetBy(dx: s.width * 0.42, dy: s.height * 0.42))
        }
    }

    static func grass(size: CGSize) -> SKTexture {
        render(CGSize(width: 64, height: 64), scale: 1) { context, s in
            context.setFillColor(UIColor(red: 0.30, green: 0.52, blue: 0.30, alpha: 1).cgColor)
            context.fill(CGRect(origin: .zero, size: s))
            var generator = SystemRandomNumberGenerator()
            for _ in 0..<60 {
                let x = CGFloat.random(in: 0...s.width, using: &generator)
                let y = CGFloat.random(in: 0...s.height, using: &generator)
                context.setFillColor(UIColor(red: 0.38, green: 0.62, blue: 0.36, alpha: 0.8).cgColor)
                context.fill(CGRect(x: x, y: y, width: 1.5, height: 3))
            }
            _ = size
        }
    }
}

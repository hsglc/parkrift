import SpriteKit
import UIKit

extension UIColor {
    func lighter(by amount: CGFloat = 0.15) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue,
                       saturation: max(saturation - amount * 0.6, 0),
                       brightness: min(brightness + amount, 1),
                       alpha: alpha)
    }
}

/// Procedurally drawn textures. Everything is rendered once per screen size,
/// at the device's native scale, so the game needs no image files.
enum Art {

    // MARK: Helpers

    private static func render(_ size: CGSize, _ draw: (CGContext, CGSize) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            draw(context.cgContext, size)
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    private static func gradient(_ colors: [UIColor], _ locations: [CGFloat]? = nil) -> CGGradient? {
        let cgColors = colors.map { $0.cgColor } as CFArray
        if let locations = locations {
            return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations)
        }
        return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil)
    }

    private static func fill(_ context: CGContext, path: CGPath, colors: [UIColor],
                             locations: [CGFloat]? = nil, from start: CGPoint, to end: CGPoint) {
        guard let gradient = gradient(colors, locations) else { return }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    // MARK: Sky

    static func sky(size: CGSize) -> SKTexture {
        render(CGSize(width: 8, height: max(size.height, 64))) { context, s in
            let path = CGPath(rect: CGRect(origin: .zero, size: s), transform: nil)
            fill(context, path: path,
                 colors: [UIColor(red: 0.22, green: 0.47, blue: 0.90, alpha: 1),
                          UIColor(red: 0.45, green: 0.71, blue: 0.98, alpha: 1),
                          UIColor(red: 0.78, green: 0.89, blue: 1.00, alpha: 1),
                          UIColor(red: 1.00, green: 0.90, blue: 0.76, alpha: 1)],
                 locations: [0, 0.45, 0.78, 1],
                 from: .zero, to: CGPoint(x: 0, y: s.height))
        }
    }

    static func sun(radius: CGFloat) -> SKTexture {
        let side = radius * 4
        return render(CGSize(width: side, height: side)) { context, s in
            let center = CGPoint(x: s.width / 2, y: s.height / 2)
            if let glow = gradient([UIColor(red: 1, green: 0.93, blue: 0.62, alpha: 0.55),
                                    UIColor(red: 1, green: 0.90, blue: 0.60, alpha: 0)]) {
                context.drawRadialGradient(glow, startCenter: center, startRadius: radius * 0.8,
                                           endCenter: center, endRadius: s.width / 2, options: [])
            }
            let disk = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                width: radius * 2, height: radius * 2), transform: nil)
            fill(context, path: disk,
                 colors: [UIColor(red: 1, green: 0.97, blue: 0.78, alpha: 1),
                          UIColor(red: 1, green: 0.82, blue: 0.36, alpha: 1)],
                 from: CGPoint(x: center.x - radius, y: center.y - radius),
                 to: CGPoint(x: center.x + radius, y: center.y + radius))
        }
    }

    static func cloud(width: CGFloat) -> SKTexture {
        let size = CGSize(width: width, height: width * 0.55)
        return render(size) { context, s in
            let puffs: [(CGFloat, CGFloat, CGFloat)] = [
                (0.22, 0.62, 0.17), (0.40, 0.45, 0.24), (0.62, 0.50, 0.21), (0.80, 0.64, 0.15), (0.50, 0.70, 0.18)
            ]
            context.setFillColor(UIColor(red: 0.80, green: 0.87, blue: 0.97, alpha: 1).cgColor)
            for puff in puffs {
                let r = puff.2 * s.width
                context.fillEllipse(in: CGRect(x: puff.0 * s.width - r, y: puff.1 * s.height - r + r * 0.18,
                                               width: r * 2, height: r * 2))
            }
            context.setFillColor(UIColor.white.cgColor)
            for puff in puffs {
                let r = puff.2 * s.width
                context.fillEllipse(in: CGRect(x: puff.0 * s.width - r, y: puff.1 * s.height - r,
                                               width: r * 2, height: r * 2 * 0.92))
            }
        }
    }

    // MARK: Landscape (all horizontally seamless)

    private static func ridge(_ x: CGFloat, width: CGFloat) -> CGFloat {
        let t: CGFloat = x / width * 2 * CGFloat.pi
        var peak: CGFloat = 0.55
        peak += 0.22 * sin(2 * t + 0.6)
        peak += 0.12 * sin(5 * t + 1.7)
        peak += 0.06 * sin(11 * t + 0.3)
        return peak
    }

    static func mountains(width: CGFloat, height: CGFloat) -> SKTexture {
        render(CGSize(width: width, height: height)) { context, s in
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: s.height))
            var x: CGFloat = 0
            while x <= s.width {
                path.addLine(to: CGPoint(x: x, y: s.height * (1 - ridge(x, width: s.width))))
                x += 3
            }
            path.addLine(to: CGPoint(x: s.width, y: s.height))
            path.closeSubpath()
            fill(context, path: path,
                 colors: [UIColor(red: 0.62, green: 0.72, blue: 0.92, alpha: 1),
                          UIColor(red: 0.78, green: 0.85, blue: 0.97, alpha: 1)],
                 from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: s.height))

            // Light band along the ridge
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(4)
            let line = CGMutablePath()
            x = 0
            while x <= s.width {
                let point = CGPoint(x: x, y: s.height * (1 - ridge(x, width: s.width)) + 2)
                if x == 0 { line.move(to: point) } else { line.addLine(to: point) }
                x += 3
            }
            context.addPath(line)
            context.strokePath()
            context.restoreGState()
        }
    }

    static func hills(width: CGFloat, height: CGFloat) -> SKTexture {
        render(CGSize(width: width, height: height)) { context, s in
            func hillY(_ x: CGFloat) -> CGFloat {
                let t: CGFloat = x / s.width * 2 * CGFloat.pi
                var h: CGFloat = 0.42
                h += 0.10 * sin(3 * t + 0.4)
                h += 0.05 * sin(7 * t + 2.1)
                return s.height * (1 - h)
            }
            // Trees behind the ridge (drawn three times so they wrap seamlessly)
            let treeCount = 9
            for index in 0..<treeCount {
                let base = (CGFloat(index) + 0.5) * s.width / CGFloat(treeCount)
                let slot: CGFloat = s.width / CGFloat(treeCount)
                let jitter: CGFloat = sin(CGFloat(index) * 12.9898) * slot * 0.3
                let scale: CGFloat = 0.75 + 0.35 * abs(sin(CGFloat(index) * 4.1))
                for offset: CGFloat in [-s.width, 0, s.width] {
                    let x = base + jitter + offset
                    drawTree(context, x: x, groundY: hillY(x - offset) + 6, scale: scale * s.height / 120)
                }
            }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: s.height))
            var x: CGFloat = 0
            while x <= s.width {
                path.addLine(to: CGPoint(x: x, y: hillY(x)))
                x += 3
            }
            path.addLine(to: CGPoint(x: s.width, y: s.height))
            path.closeSubpath()
            fill(context, path: path,
                 colors: [UIColor(red: 0.50, green: 0.80, blue: 0.44, alpha: 1),
                          UIColor(red: 0.33, green: 0.62, blue: 0.33, alpha: 1)],
                 from: CGPoint(x: 0, y: s.height * 0.4), to: CGPoint(x: 0, y: s.height))
        }
    }

    private static func drawTree(_ context: CGContext, x: CGFloat, groundY: CGFloat, scale: CGFloat) {
        let trunkW = 7 * scale
        let trunkH = 22 * scale
        context.setFillColor(UIColor(red: 0.47, green: 0.32, blue: 0.20, alpha: 1).cgColor)
        context.fill(CGRect(x: x - trunkW / 2, y: groundY - trunkH, width: trunkW, height: trunkH))
        let crowns: [(CGFloat, CGFloat, CGFloat)] = [(0, -34, 18), (-10, -24, 13), (10, -24, 13)]
        context.setFillColor(UIColor(red: 0.20, green: 0.50, blue: 0.27, alpha: 1).cgColor)
        for crown in crowns {
            let r = crown.2 * scale
            context.fillEllipse(in: CGRect(x: x + crown.0 * scale - r, y: groundY + crown.1 * scale - r,
                                           width: r * 2, height: r * 2))
        }
        context.setFillColor(UIColor(red: 0.33, green: 0.66, blue: 0.36, alpha: 1).cgColor)
        let r = 9 * scale
        context.fillEllipse(in: CGRect(x: x - 6 * scale - r, y: groundY - 40 * scale - r, width: r * 2, height: r * 2))
    }

    static func ground(width: CGFloat, height: CGFloat) -> SKTexture {
        render(CGSize(width: width, height: height)) { context, s in
            let grassDepth: CGFloat = 20
            let dirt = CGPath(rect: CGRect(x: 0, y: grassDepth - 4, width: s.width, height: s.height), transform: nil)
            fill(context, path: dirt,
                 colors: [UIColor(red: 0.86, green: 0.66, blue: 0.42, alpha: 1),
                          UIColor(red: 0.68, green: 0.48, blue: 0.29, alpha: 1)],
                 from: CGPoint(x: 0, y: grassDepth), to: CGPoint(x: 0, y: s.height))

            // Pebbles and stripes (period divides the width so the tile wraps)
            let columns = max(Int(s.width / 46), 1)
            let step = s.width / CGFloat(columns)
            for index in 0..<columns {
                let x = CGFloat(index) * step
                context.setFillColor(UIColor(red: 0.62, green: 0.43, blue: 0.26, alpha: 0.45).cgColor)
                let stripe = CGPath(roundedRect: CGRect(x: x + step * 0.2, y: grassDepth + 18, width: step * 0.45, height: 5),
                                    cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
                context.addPath(stripe)
                context.fillPath()
                context.setFillColor(UIColor(red: 0.94, green: 0.80, blue: 0.60, alpha: 0.55).cgColor)
                let pebbleY = grassDepth + 36 + CGFloat(index % 3) * 9
                context.fillEllipse(in: CGRect(x: x + step * 0.65, y: pebbleY, width: 6, height: 4))
            }

            // Grass with a wavy lower edge
            let waves = columns * 2
            let grass = CGMutablePath()
            grass.move(to: CGPoint(x: 0, y: 0))
            grass.addLine(to: CGPoint(x: s.width, y: 0))
            var x = s.width
            while x >= 0 {
                let phase: CGFloat = x / s.width * 2 * CGFloat.pi * CGFloat(waves)
                let y: CGFloat = grassDepth - 3 + 4 * sin(phase)
                grass.addLine(to: CGPoint(x: x, y: y))
                x -= 2
            }
            grass.closeSubpath()
            fill(context, path: grass,
                 colors: [UIColor(red: 0.56, green: 0.86, blue: 0.40, alpha: 1),
                          UIColor(red: 0.34, green: 0.66, blue: 0.28, alpha: 1)],
                 from: .zero, to: CGPoint(x: 0, y: grassDepth + 4))
            context.setFillColor(UIColor.white.withAlphaComponent(0.35).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: s.width, height: 2))
        }
    }

    // MARK: Pillars

    private static func pillarShading(_ color: UIColor) -> [UIColor] {
        [color.darker(by: 0.22), color, color.lighter(by: 0.22), color, color.darker(by: 0.28)]
    }

    static func pillarBody(width: CGFloat, color: UIColor) -> SKTexture {
        render(CGSize(width: width, height: 32)) { context, s in
            let rect = CGRect(origin: .zero, size: s)
            fill(context, path: CGPath(rect: rect, transform: nil), colors: pillarShading(color),
                 locations: [0, 0.22, 0.38, 0.7, 1],
                 from: .zero, to: CGPoint(x: s.width, y: 0))
            context.setFillColor(color.darker(by: 0.35).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 3, height: s.height))
            context.fill(CGRect(x: s.width - 3, y: 0, width: 3, height: s.height))
            context.setFillColor(UIColor.white.withAlphaComponent(0.22).cgColor)
            context.fill(CGRect(x: s.width * 0.3, y: 0, width: s.width * 0.08, height: s.height))
        }
    }

    static func pillarCap(width: CGFloat, height: CGFloat, color: UIColor) -> SKTexture {
        render(CGSize(width: width, height: height)) { context, s in
            let rect = CGRect(origin: .zero, size: s).insetBy(dx: 1.5, dy: 1.5)
            let path = CGPath(roundedRect: rect, cornerWidth: 9, cornerHeight: 9, transform: nil)
            fill(context, path: path, colors: pillarShading(color),
                 locations: [0, 0.22, 0.38, 0.7, 1],
                 from: .zero, to: CGPoint(x: s.width, y: 0))
            context.addPath(path)
            context.setStrokeColor(color.darker(by: 0.35).cgColor)
            context.setLineWidth(3)
            context.strokePath()
            // Gem in the middle of the cap
            let cx = s.width / 2
            let cy = s.height / 2
            let gem = CGMutablePath()
            gem.move(to: CGPoint(x: cx, y: cy - 6))
            gem.addLine(to: CGPoint(x: cx + 6, y: cy))
            gem.addLine(to: CGPoint(x: cx, y: cy + 6))
            gem.addLine(to: CGPoint(x: cx - 6, y: cy))
            gem.closeSubpath()
            context.addPath(gem)
            context.setFillColor(UIColor.white.withAlphaComponent(0.75).cgColor)
            context.fillPath()
            context.setFillColor(UIColor.white.withAlphaComponent(0.3).cgColor)
            context.fill(CGRect(x: 8, y: 4, width: s.width - 16, height: 3))
        }
    }

    // MARK: Player

    static func player(size side: CGFloat) -> SKTexture {
        render(CGSize(width: side, height: side)) { context, s in
            let bodyRect = CGRect(origin: .zero, size: s).insetBy(dx: 2, dy: 2)
            let body = CGPath(roundedRect: bodyRect, cornerWidth: s.width * 0.28, cornerHeight: s.width * 0.28, transform: nil)
            fill(context, path: body,
                 colors: [UIColor(red: 1.00, green: 0.72, blue: 0.34, alpha: 1),
                          UIColor(red: 0.98, green: 0.46, blue: 0.14, alpha: 1)],
                 from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: s.height))
            context.addPath(body)
            context.setStrokeColor(UIColor(red: 0.74, green: 0.30, blue: 0.07, alpha: 1).cgColor)
            context.setLineWidth(3)
            context.strokePath()

            // Gloss
            let gloss = CGPath(roundedRect: CGRect(x: s.width * 0.16, y: s.height * 0.12,
                                                   width: s.width * 0.42, height: s.height * 0.14),
                               cornerWidth: s.width * 0.07, cornerHeight: s.width * 0.07, transform: nil)
            context.addPath(gloss)
            context.setFillColor(UIColor.white.withAlphaComponent(0.38).cgColor)
            context.fillPath()

            // Cheeks
            context.setFillColor(UIColor(red: 1.0, green: 0.42, blue: 0.48, alpha: 0.45).cgColor)
            context.fillEllipse(in: CGRect(x: s.width * 0.26, y: s.height * 0.62, width: s.width * 0.16, height: s.height * 0.09))
            context.fillEllipse(in: CGRect(x: s.width * 0.74, y: s.height * 0.60, width: s.width * 0.16, height: s.height * 0.09))

            // Eyes (looking forward, to the right)
            let eyes: [CGPoint] = [CGPoint(x: s.width * 0.44, y: s.height * 0.44),
                                   CGPoint(x: s.width * 0.72, y: s.height * 0.42)]
            let eyeR = s.width * 0.14
            for eye in eyes {
                context.setFillColor(UIColor.white.cgColor)
                context.fillEllipse(in: CGRect(x: eye.x - eyeR, y: eye.y - eyeR, width: eyeR * 2, height: eyeR * 2.1))
                let pupilR = eyeR * 0.52
                context.setFillColor(UIColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 1).cgColor)
                context.fillEllipse(in: CGRect(x: eye.x - pupilR + eyeR * 0.35, y: eye.y - pupilR,
                                               width: pupilR * 2, height: pupilR * 2.1))
                context.setFillColor(UIColor.white.cgColor)
                let sparkle = pupilR * 0.45
                context.fillEllipse(in: CGRect(x: eye.x + eyeR * 0.35, y: eye.y - pupilR * 0.7,
                                               width: sparkle, height: sparkle))
            }

            // Smile
            context.setStrokeColor(UIColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 1).cgColor)
            context.setLineWidth(max(2, s.width * 0.05))
            context.setLineCap(.round)
            context.addArc(center: CGPoint(x: s.width * 0.6, y: s.height * 0.6), radius: s.width * 0.12,
                           startAngle: 0.35, endAngle: CGFloat.pi - 0.35, clockwise: false)
            context.strokePath()
        }
    }

    static func wing(width: CGFloat) -> SKTexture {
        render(CGSize(width: width, height: width * 0.62)) { context, s in
            let rect = CGRect(origin: .zero, size: s).insetBy(dx: 2, dy: 2)
            let path = CGPath(ellipseIn: rect, transform: nil)
            fill(context, path: path,
                 colors: [UIColor(red: 1.00, green: 0.93, blue: 0.70, alpha: 1),
                          UIColor(red: 1.00, green: 0.70, blue: 0.36, alpha: 1)],
                 from: .zero, to: CGPoint(x: 0, y: s.height))
            context.addPath(path)
            context.setStrokeColor(UIColor(red: 0.74, green: 0.30, blue: 0.07, alpha: 1).cgColor)
            context.setLineWidth(2.5)
            context.strokePath()
            context.setStrokeColor(UIColor(red: 0.85, green: 0.47, blue: 0.20, alpha: 0.8).cgColor)
            context.setLineWidth(1.5)
            for index in 1...2 {
                let y = s.height * CGFloat(index) / 3
                context.move(to: CGPoint(x: s.width * 0.22, y: y))
                context.addLine(to: CGPoint(x: s.width * 0.78, y: y))
            }
            context.strokePath()
        }
    }

    // MARK: Effects

    static func shadow() -> SKTexture {
        render(CGSize(width: 64, height: 18)) { context, s in
            context.setFillColor(UIColor.black.withAlphaComponent(0.22).cgColor)
            context.fillEllipse(in: CGRect(origin: .zero, size: s))
        }
    }

    static func dot() -> SKTexture {
        render(CGSize(width: 16, height: 16)) { context, s in
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: CGRect(origin: .zero, size: s))
        }
    }

    private static func starPath(center c: CGPoint, outer: CGFloat, inner: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<8 {
            let angle: CGFloat = CGFloat(index) * CGFloat.pi / 4 - CGFloat.pi / 2
            let r = index % 2 == 0 ? outer : inner
            let point = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    static func star() -> SKTexture {
        render(CGSize(width: 20, height: 20)) { context, s in
            context.addPath(starPath(center: CGPoint(x: s.width / 2, y: s.height / 2), outer: s.width / 2, inner: s.width / 6))
            context.setFillColor(UIColor(red: 1.0, green: 0.92, blue: 0.45, alpha: 1).cgColor)
            context.fillPath()
        }
    }

    // MARK: Pickups, enemies, projectiles

    static func coin(size side: CGFloat) -> SKTexture {
        render(CGSize(width: side, height: side)) { context, s in
            let rect = CGRect(origin: .zero, size: s).insetBy(dx: 1.5, dy: 1.5)
            let disk = CGPath(ellipseIn: rect, transform: nil)
            fill(context, path: disk,
                 colors: [UIColor(red: 1.00, green: 0.92, blue: 0.45, alpha: 1),
                          UIColor(red: 0.96, green: 0.66, blue: 0.12, alpha: 1)],
                 from: .zero, to: CGPoint(x: s.width, y: s.height))
            context.addPath(disk)
            context.setStrokeColor(UIColor(red: 0.74, green: 0.46, blue: 0.04, alpha: 1).cgColor)
            context.setLineWidth(2)
            context.strokePath()
            context.setStrokeColor(UIColor(red: 1.0, green: 0.95, blue: 0.70, alpha: 0.9).cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: rect.insetBy(dx: s.width * 0.14, dy: s.height * 0.14))
            context.addPath(starPath(center: CGPoint(x: s.width / 2, y: s.height / 2), outer: s.width * 0.22, inner: s.width * 0.08))
            context.setFillColor(UIColor(red: 1.0, green: 0.97, blue: 0.82, alpha: 1).cgColor)
            context.fillPath()
        }
    }

    static func monster(size side: CGFloat) -> SKTexture {
        render(CGSize(width: side, height: side)) { context, s in
            let w = s.width
            let h = s.height
            // Horns
            context.setFillColor(UIColor(red: 0.96, green: 0.86, blue: 0.62, alpha: 1).cgColor)
            for hornX: CGFloat in [0.30, 0.70] {
                let horn = CGMutablePath()
                horn.move(to: CGPoint(x: w * (hornX - 0.08), y: h * 0.24))
                horn.addLine(to: CGPoint(x: w * hornX, y: h * 0.04))
                horn.addLine(to: CGPoint(x: w * (hornX + 0.08), y: h * 0.24))
                horn.closeSubpath()
                context.addPath(horn)
            }
            context.fillPath()

            // Blob body with three little feet
            let body = CGMutablePath()
            body.addEllipse(in: CGRect(x: w * 0.08, y: h * 0.14, width: w * 0.84, height: h * 0.70))
            for footX: CGFloat in [0.26, 0.5, 0.74] {
                body.addEllipse(in: CGRect(x: w * (footX - 0.10), y: h * 0.70, width: w * 0.20, height: h * 0.24))
            }
            fill(context, path: body,
                 colors: [UIColor(red: 0.70, green: 0.44, blue: 0.96, alpha: 1),
                          UIColor(red: 0.42, green: 0.18, blue: 0.72, alpha: 1)],
                 from: CGPoint(x: 0, y: h * 0.14), to: CGPoint(x: 0, y: h * 0.94))

            // Belly highlight
            context.setFillColor(UIColor.white.withAlphaComponent(0.18).cgColor)
            context.fillEllipse(in: CGRect(x: w * 0.22, y: h * 0.22, width: w * 0.30, height: h * 0.14))

            // One big eye looking left (towards the player)
            let eyeCenter = CGPoint(x: w * 0.5, y: h * 0.44)
            let eyeR = w * 0.19
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: CGRect(x: eyeCenter.x - eyeR, y: eyeCenter.y - eyeR, width: eyeR * 2, height: eyeR * 2))
            context.setFillColor(UIColor(red: 0.85, green: 0.15, blue: 0.20, alpha: 1).cgColor)
            let irisR = eyeR * 0.55
            context.fillEllipse(in: CGRect(x: eyeCenter.x - irisR - eyeR * 0.35, y: eyeCenter.y - irisR,
                                           width: irisR * 2, height: irisR * 2))
            context.setFillColor(UIColor(red: 0.10, green: 0.08, blue: 0.14, alpha: 1).cgColor)
            let pupilR = irisR * 0.5
            context.fillEllipse(in: CGRect(x: eyeCenter.x - pupilR - eyeR * 0.40, y: eyeCenter.y - pupilR,
                                           width: pupilR * 2, height: pupilR * 2))

            // Angry brow
            context.setStrokeColor(UIColor(red: 0.20, green: 0.06, blue: 0.32, alpha: 1).cgColor)
            context.setLineWidth(max(2.5, w * 0.06))
            context.setLineCap(.round)
            context.move(to: CGPoint(x: w * 0.30, y: h * 0.22))
            context.addLine(to: CGPoint(x: w * 0.68, y: h * 0.30))
            context.strokePath()

            // Mouth with fangs
            let mouth = CGRect(x: w * 0.34, y: h * 0.66, width: w * 0.32, height: h * 0.08)
            context.setFillColor(UIColor(red: 0.20, green: 0.06, blue: 0.32, alpha: 1).cgColor)
            context.fill(mouth)
            context.setFillColor(UIColor.white.cgColor)
            for fangX: CGFloat in [0.40, 0.58] {
                let fang = CGMutablePath()
                fang.move(to: CGPoint(x: w * fangX, y: mouth.minY))
                fang.addLine(to: CGPoint(x: w * (fangX + 0.04), y: mouth.maxY))
                fang.addLine(to: CGPoint(x: w * (fangX + 0.08), y: mouth.minY))
                fang.closeSubpath()
                context.addPath(fang)
            }
            context.fillPath()
        }
    }

    static func bullet(size side: CGFloat) -> SKTexture {
        render(CGSize(width: side, height: side)) { context, s in
            let center = CGPoint(x: s.width / 2, y: s.height / 2)
            if let glow = gradient([UIColor.white,
                                    UIColor(red: 1.0, green: 0.86, blue: 0.30, alpha: 1),
                                    UIColor(red: 1.0, green: 0.55, blue: 0.10, alpha: 0)],
                                   [0, 0.4, 1]) {
                context.drawRadialGradient(glow, startCenter: center, startRadius: 0,
                                           endCenter: center, endRadius: s.width / 2, options: [])
            }
        }
    }

    static func fireButton(size side: CGFloat) -> SKTexture {
        render(CGSize(width: side, height: side)) { context, s in
            let rect = CGRect(origin: .zero, size: s).insetBy(dx: 3, dy: 3)
            let disk = CGPath(ellipseIn: rect, transform: nil)
            fill(context, path: disk,
                 colors: [UIColor(red: 1.0, green: 0.50, blue: 0.38, alpha: 0.92),
                          UIColor(red: 0.82, green: 0.18, blue: 0.20, alpha: 0.92)],
                 from: .zero, to: CGPoint(x: 0, y: s.height))
            context.addPath(disk)
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor)
            context.setLineWidth(3)
            context.strokePath()
            // Orb with speed lines
            let c = CGPoint(x: s.width * 0.58, y: s.height / 2)
            let r = s.width * 0.13
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(3)
            context.setLineCap(.round)
            for dy: CGFloat in [-0.5, 0, 0.5] {
                context.move(to: CGPoint(x: c.x - r * 1.5, y: c.y + dy * r * 1.4))
                context.addLine(to: CGPoint(x: c.x - r * 3.0, y: c.y + dy * r * 1.4))
            }
            context.strokePath()
        }
    }
}

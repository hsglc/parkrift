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

    private static let squareParticleImage: UIImage = makeSquareParticle()
    static func squareParticle() -> UIImage { squareParticleImage }
    private static func makeSquareParticle() -> UIImage {
        image(CGSize(width: 8, height: 8), scale: 1) { context, s in
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 1, width: s.width, height: s.height - 2))
        }
    }

    private static let glowParticleImage: UIImage = makeGlowParticle()
    static func glowParticle() -> UIImage { glowParticleImage }

    /// A rain streak: a thin vertical line, bright in the middle, fading at both ends and sides.
    private static let rainStreakImage: UIImage = image(CGSize(width: 32, height: 64), scale: 1) { context, s in
        let colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.cgColor,
                      UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        guard let along = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1]) else { return }
        for (width, alpha) in [(CGFloat(5), CGFloat(0.25)), (2.2, 0.6), (1.0, 1.0)] {
            context.saveGState()
            context.setAlpha(alpha)
            context.clip(to: CGRect(x: (s.width - width) / 2, y: 2, width: width, height: s.height - 4))
            context.drawLinearGradient(along, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: s.height), options: [])
            context.restoreGState()
        }
    }
    static func rainStreak() -> UIImage { rainStreakImage }
    private static func makeGlowParticle() -> UIImage {
        image(CGSize(width: 32, height: 32), scale: 1) { context, s in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                let c = CGPoint(x: s.width / 2, y: s.height / 2)
                context.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: s.width / 2, options: [])
            }
        }
    }

    /// Strip of 16 x 2 checker cells for the finish banners.
    static let checkerStripTexture: SKTexture = makeCheckerStrip()
    static func checkerStrip() -> SKTexture { checkerStripTexture }
    private static func makeCheckerStrip() -> SKTexture {
        SKTexture(image: image(CGSize(width: 512, height: 64), scale: 1) { context, s in
            let cell = s.height / 2
            for row in 0..<2 {
                for col in 0..<Int(s.width / cell) {
                    context.setFillColor(((row + col) % 2 == 0 ? UIColor(white: 0.97, alpha: 1) : UIColor(white: 0.08, alpha: 1)).cgColor)
                    context.fill(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                }
            }
        })
    }

    /// The street tile turned 90° so the lane lines run along V (for north-south streets).
    static func roadImageVertical() -> UIImage {
        let source = roadImage()
        return image(CGSize(width: source.size.height, height: source.size.width), scale: 1) { context, s in
            context.translateBy(x: s.width / 2, y: s.height / 2)
            context.rotate(by: CGFloat.pi / 2)
            source.draw(in: CGRect(x: -source.size.width / 2, y: -source.size.height / 2,
                                   width: source.size.width, height: source.size.height))
        }
    }

    private static var glowTitles: [String: SKTexture] = [:]

    /// Big title text with a soft colored glow, rendered once into a texture (a live blur filter
    /// would cost a frame stall the first time it is shown).
    static func glowTitle(_ text: String, fontSize: CGFloat, color: UIColor) -> SKTexture {
        let key = "\(text)-\(fontSize)"
        if let cached = glowTitles[key] { return cached }
        let font = UIFont(name: "AvenirNext-Heavy", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize, weight: .heavy)
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let textSize = (text as NSString).size(withAttributes: plain)
        let pad: CGFloat = 40
        let canvas = CGSize(width: ceil(textSize.width + pad * 2), height: ceil(textSize.height + pad * 2))
        let rendered = image(canvas, scale: 2) { context, _ in
            let origin = CGPoint(x: pad, y: pad)
            context.saveGState()
            context.setShadow(offset: .zero, blur: 22, color: color.withAlphaComponent(0.95).cgColor)
            for _ in 0..<3 { (text as NSString).draw(at: origin, withAttributes: plain) }
            context.restoreGState()
            context.setShadow(offset: CGSize(width: 0, height: 5), blur: 0, color: UIColor.black.withAlphaComponent(0.45).cgColor)
            (text as NSString).draw(at: origin, withAttributes: plain)
        }
        let texture = SKTexture(image: rendered)
        glowTitles[key] = texture
        return texture
    }

    /// Racing-game font: heavy, condensed and italic.
    static func raceFont(_ size: CGFloat, weight: UIFont.Weight = .black, italic: Bool = true) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight, width: .condensed)
        guard italic, let descriptor = base.fontDescriptor.withSymbolicTraits(.traitItalic) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Soft glowing ring for the nitro shockwave (a sprite: SKShapeNode glow compiles a shader
    /// on first use, which stalled the first nitro).
    static let nitroRingTexture: SKTexture = render(CGSize(width: 160, height: 160), scale: 1) { context, s in
        let center = CGPoint(x: s.width / 2, y: s.height / 2)
        for (width, alpha) in [(16.0, 0.12), (10.0, 0.25), (5.0, 0.6), (2.5, 1.0)] as [(CGFloat, CGFloat)] {
            context.setStrokeColor(UIColor(red: 0.55, green: 0.9, blue: 1.0, alpha: alpha).cgColor)
            context.setLineWidth(width)
            context.strokeEllipse(in: CGRect(x: center.x - 62, y: center.y - 62, width: 124, height: 124))
        }
    }

    /// Lower-third result plate for the finish moment, in the style of racing games: a slanted
    /// dark plate with an accent edge, a small kicker, a big white title, a stats line and a
    /// position block on the right. Plain text on a solid plate so it reads over any scene.
    static func finishPlate(kicker: String, title: String, stats: [(icon: String, text: String)],
                            badgeTop: String?, badgeBottom: String, accent: UIColor, badgeText: UIColor) -> SKTexture {
        let size = CGSize(width: 470, height: 132)
        let skew: CGFloat = 22
        func slanted(_ rect: CGRect) -> CGPath {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX + skew, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - skew, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
        return render(size, scale: 2) { context, s in
            let badgeWidth: CGFloat = 112
            let plate = CGRect(x: 0, y: 8, width: s.width - badgeWidth + skew - 6, height: s.height - 16)
            // Plate with a soft drop shadow
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 6), blur: 14, color: UIColor.black.withAlphaComponent(0.55).cgColor)
            context.addPath(slanted(plate))
            context.setFillColor(UIColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 0.92).cgColor)
            context.fillPath()
            context.restoreGState()
            // Faint top highlight
            context.saveGState()
            context.addPath(slanted(plate))
            context.clip()
            if let shine = gradient([UIColor.white.withAlphaComponent(0.10), UIColor.white.withAlphaComponent(0)]) {
                context.drawLinearGradient(shine, start: CGPoint(x: 0, y: plate.minY), end: CGPoint(x: 0, y: plate.midY), options: [])
            }
            // Accent edge
            context.setFillColor(accent.cgColor)
            context.fill(CGRect(x: 0, y: plate.minY, width: skew + 10, height: plate.height))
            context.restoreGState()

            let left: CGFloat = skew + 22
            let kickerFont = UIFont.systemFont(ofSize: 12, weight: .heavy, width: .expanded)
            (kicker as NSString).draw(at: CGPoint(x: left + 4, y: plate.minY + 12),
                                      withAttributes: [.font: kickerFont, .foregroundColor: accent, .kern: 2.2])
            (title as NSString).draw(at: CGPoint(x: left, y: plate.minY + 24),
                                     withAttributes: [.font: raceFont(48), .foregroundColor: UIColor.white, .kern: 0.5])
            // Stats: icon + text pairs
            var x = left - 4
            let statFont = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .bold)
            let statY = plate.maxY - 28
            for stat in stats {
                if let icon = UIImage(systemName: stat.icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))?
                    .withTintColor(accent, renderingMode: .alwaysOriginal) {
                    icon.draw(at: CGPoint(x: x, y: statY + (20 - icon.size.height) / 2))
                    x += icon.size.width + 6
                }
                let attributes: [NSAttributedString.Key: Any] = [.font: statFont, .foregroundColor: UIColor.white.withAlphaComponent(0.92)]
                (stat.text as NSString).draw(at: CGPoint(x: x, y: statY), withAttributes: attributes)
                x += (stat.text as NSString).size(withAttributes: attributes).width + 22
            }

            // Position block
            let badge = CGRect(x: s.width - badgeWidth, y: 0, width: badgeWidth, height: s.height)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 6), blur: 14, color: UIColor.black.withAlphaComponent(0.5).cgColor)
            context.addPath(slanted(badge))
            context.setFillColor(accent.cgColor)
            context.fillPath()
            context.restoreGState()
            let centered = NSMutableParagraphStyle()
            centered.alignment = .center
            let bigFont = raceFont(badgeTop == nil ? 40 : 54)
            let big = badgeTop ?? "✓"
            let bigSize = (big as NSString).size(withAttributes: [.font: bigFont])
            (big as NSString).draw(in: CGRect(x: badge.minX, y: badge.midY - bigSize.height / 2 - 10, width: badge.width, height: bigSize.height),
                                   withAttributes: [.font: bigFont, .foregroundColor: badgeText, .paragraphStyle: centered])
            (badgeBottom as NSString).draw(in: CGRect(x: badge.minX, y: badge.maxY - 30, width: badge.width, height: 16),
                                           withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .heavy, width: .expanded),
                                                            .foregroundColor: badgeText.withAlphaComponent(0.8), .kern: 1.6,
                                                            .paragraphStyle: centered])
        }
    }

    // MARK: Finish titles

    /// One texture per letter of a big finish title (race font, white, with a soft dark shadow so
    /// it reads over any scene), plus each letter's advance, for letter-by-letter animation.
    static func titleGlyphs(_ text: String, size: CGFloat) -> [(texture: SKTexture, advance: CGFloat)] {
        let font = raceFont(size)
        let pad: CGFloat = size * 0.3
        var result: [(SKTexture, CGFloat)] = []
        for character in text {
            let string = String(character) as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let measured = string.size(withAttributes: attributes)
            let canvas = CGSize(width: ceil(measured.width + pad * 2), height: ceil(measured.height + pad * 2))
            let texture = render(canvas, scale: 2) { context, _ in
                context.setShadow(offset: CGSize(width: 0, height: 3), blur: size * 0.18,
                                  color: UIColor.black.withAlphaComponent(0.55).cgColor)
                string.draw(at: CGPoint(x: pad, y: pad), withAttributes: attributes)
            }
            result.append((texture, character == " " ? size * 0.28 : measured.width * 0.94))
        }
        return result
    }

    /// Rounded glass chip with an SF Symbol and a value, for the finish stats.
    static func statChip(icon: String, text: String, accent: UIColor) -> SKTexture {
        let font = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let symbol = UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold))?
            .withTintColor(accent, renderingMode: .alwaysOriginal)
        let iconWidth = (symbol?.size.width ?? 0) + 8
        let size = CGSize(width: ceil(textSize.width + iconWidth + 32), height: 38)
        return render(size, scale: 2) { context, s in
            let rect = CGRect(origin: .zero, size: s).insetBy(dx: 1, dy: 1)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
            context.setFillColor(UIColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 0.72).cgColor)
            context.addPath(path.cgPath)
            context.fillPath()
            context.setStrokeColor(accent.withAlphaComponent(0.55).cgColor)
            context.setLineWidth(1.2)
            context.addPath(path.cgPath)
            context.strokePath()
            var x: CGFloat = 16
            if let symbol = symbol {
                symbol.draw(at: CGPoint(x: x, y: (s.height - symbol.size.height) / 2))
                x += iconWidth
            }
            (text as NSString).draw(at: CGPoint(x: x, y: (s.height - textSize.height) / 2), withAttributes: attributes)
        }
    }

    // MARK: Minimap

    /// The level drawn as a navigation map (y up, `scale` map points per world unit, at 3x):
    /// streets with dashed centre lines and zebra crossings, pavements, building footprints with a
    /// lit edge, parks with trees; or the parking lot with its painted bays, walls, parked cars
    /// and cones.
    static func minimapTexture(level: LevelDef, scale: CGFloat) -> SKTexture {
        let size = CGSize(width: max(4, level.world.width * scale), height: max(4, level.world.height * scale))
        return render(size, scale: 3) { context, s in
            context.translateBy(x: 0, y: s.height)
            context.scaleBy(x: 1, y: -1)
            func rect(_ r: CGRect) -> CGRect { CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale) }
            func box(_ o: ObstacleDef, inset: CGFloat = 0, corner: CGFloat) -> CGPath {
                let w = max(1.5, o.size.width * scale - inset * 2), h = max(1.5, o.size.height * scale - inset * 2)
                var t = CGAffineTransform(translationX: o.center.x * scale, y: o.center.y * scale).rotated(by: o.angle)
                return CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerWidth: min(corner, w / 2),
                              cornerHeight: min(corner, h / 2), transform: &t)
            }
            if let city = level.city {
                // Streets
                context.setFillColor(UIColor(red: 0.21, green: 0.24, blue: 0.31, alpha: 1).cgColor)
                context.fill(CGRect(origin: .zero, size: s))
                // Dashed centre lines
                context.setStrokeColor(UIColor(red: 1.0, green: 0.84, blue: 0.36, alpha: 0.5).cgColor)
                context.setLineWidth(0.5)
                context.setLineDash(phase: 0, lengths: [2.2, 1.8])
                for x in city.xs {
                    context.move(to: CGPoint(x: x * scale, y: 0))
                    context.addLine(to: CGPoint(x: x * scale, y: s.height))
                }
                for y in city.ys {
                    context.move(to: CGPoint(x: 0, y: y * scale))
                    context.addLine(to: CGPoint(x: s.width, y: y * scale))
                }
                context.strokePath()
                context.setLineDash(phase: 0, lengths: [])
                // Blocks: pavement around, darker lots inside
                for block in city.blocks {
                    let outer = rect(block)
                    context.setFillColor(UIColor(red: 0.40, green: 0.44, blue: 0.52, alpha: 1).cgColor)
                    context.addPath(CGPath(roundedRect: outer, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
                    context.fillPath()
                    let inner = outer.insetBy(dx: 2.2, dy: 2.2)
                    context.setFillColor(UIColor(red: 0.12, green: 0.14, blue: 0.20, alpha: 1).cgColor)
                    context.addPath(CGPath(roundedRect: inner, cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
                    context.fillPath()
                }
                // Zebra crossings on every approach to a junction
                context.setFillColor(UIColor.white.withAlphaComponent(0.42).cgColor)
                for x in city.xs {
                    for y in city.ys {
                        let edge = (CityMap.roadHalf + 6) * scale
                        let half = CityMap.roadHalf * scale * 0.82
                        for k in stride(from: -half, through: half, by: 1.6) {
                            context.fill(CGRect(x: x * scale + k - 0.4, y: y * scale + edge - 0.9, width: 0.8, height: 1.8))
                            context.fill(CGRect(x: x * scale + k - 0.4, y: y * scale - edge - 0.9, width: 0.8, height: 1.8))
                            context.fill(CGRect(x: x * scale + edge - 0.9, y: y * scale + k - 0.4, width: 1.8, height: 0.8))
                            context.fill(CGRect(x: x * scale - edge - 0.9, y: y * scale + k - 0.4, width: 1.8, height: 0.8))
                        }
                    }
                }
                // Buildings and parks
                for o in level.obstacles where o.kind == .building {
                    if o.tint == 102 {
                        context.setFillColor(UIColor(red: 0.15, green: 0.36, blue: 0.27, alpha: 1).cgColor)
                        context.addPath(box(o, corner: 2))
                        context.fillPath()
                        // Trees: soft dots
                        context.setFillColor(UIColor(red: 0.24, green: 0.52, blue: 0.34, alpha: 1).cgColor)
                        var seed = UInt64(abs(Int(o.center.x * 7 + o.center.y * 13)))
                        for _ in 0..<Int(max(4, o.size.width * o.size.height * scale * scale / 22)) {
                            seed = seed &* 6364136223846793005 &+ 1442695040888963407
                            let u = CGFloat(seed >> 40 & 0xFFFF) / 65535 - 0.5
                            let v = CGFloat(seed >> 20 & 0xFFFF) / 65535 - 0.5
                            let p = CGPoint(x: (o.center.x + u * o.size.width * 0.85) * scale, y: (o.center.y + v * o.size.height * 0.85) * scale)
                            context.fillEllipse(in: CGRect(x: p.x - 1.1, y: p.y - 1.1, width: 2.2, height: 2.2))
                        }
                    } else {
                        context.setFillColor(UIColor(red: 0.19, green: 0.22, blue: 0.31, alpha: 1).cgColor)
                        context.addPath(box(o, inset: 0.3, corner: 0.8))
                        context.fillPath()
                        context.setStrokeColor(UIColor.white.withAlphaComponent(0.10).cgColor)
                        context.setLineWidth(0.5)
                        context.addPath(box(o, inset: 0.3, corner: 0.8))
                        context.strokePath()
                    }
                }
            } else {
                // The lot
                context.setFillColor(UIColor(red: 0.17, green: 0.19, blue: 0.25, alpha: 1).cgColor)
                context.fill(CGRect(origin: .zero, size: s))
                for o in level.obstacles {
                    switch o.kind {
                    case .wall, .building:
                        context.setFillColor(UIColor(red: 0.58, green: 0.62, blue: 0.70, alpha: 1).cgColor)
                        context.addPath(box(o, corner: 0.6))
                        context.fillPath()
                    case .car:
                        context.setFillColor(UIColor(red: 0.40, green: 0.44, blue: 0.53, alpha: 1).cgColor)
                        context.addPath(box(o, inset: 0.2, corner: 1.4))
                        context.fillPath()
                        context.setFillColor(UIColor(red: 0.20, green: 0.23, blue: 0.30, alpha: 1).cgColor)
                        context.addPath(box(ObstacleDef(kind: .car, center: o.center, size: CGSize(width: o.size.width * 0.38, height: o.size.height * 0.7),
                                                        angle: o.angle, tint: 0), corner: 0.8))
                        context.fillPath()
                    case .cone:
                        context.setFillColor(UIColor(red: 1.0, green: 0.52, blue: 0.16, alpha: 1).cgColor)
                        let r = max(1, o.size.width * scale / 2)
                        context.fillEllipse(in: CGRect(x: o.center.x * scale - r, y: o.center.y * scale - r, width: r * 2, height: r * 2))
                    }
                }
            }
        }
    }

    /// Dark at the rim, clear inside: the map fades into the bezel.
    static let minimapVignette: SKTexture = render(CGSize(width: 128, height: 128), scale: 2) { context, s in
        let colors = [UIColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 0).cgColor,
                      UIColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 0.15).cgColor,
                      UIColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 0.85).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.72, 1]) {
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            context.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: s.width / 2, options: [])
        }
    }

    /// A soft wedge from the bottom centre upwards (tinted in the game): the view ahead.
    static let minimapCone: SKTexture = render(CGSize(width: 128, height: 96), scale: 2) { context, s in
        let origin = CGPoint(x: s.width / 2, y: s.height)
        let path = CGMutablePath()
        path.move(to: origin)
        path.addArc(center: origin, radius: s.height, startAngle: -CGFloat.pi / 2 - 0.6, endAngle: -CGFloat.pi / 2 + 0.6, clockwise: false)
        path.closeSubpath()
        context.addPath(path)
        context.clip()
        let colors = [UIColor.white.withAlphaComponent(0.55).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawRadialGradient(g, startCenter: origin, startRadius: 0, endCenter: origin, endRadius: s.height, options: [])
        }
    }

    /// One stat of the finish panel: icon, small label, big value and its unit.
    struct FinishStat {
        let icon: String
        let label: String
        let value: String
        let unit: String
    }

    /// The finish stats as one dark glass panel: per stat a small label with its icon over a big
    /// number (with its unit smaller beside it), hairline dividers between, an accent edge on the
    /// left.
    static func finishStats(_ stats: [FinishStat], accent: UIColor) -> SKTexture {
        let labelFont = UIFont.systemFont(ofSize: 10, weight: .heavy)
        let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 26, weight: .heavy)
        let unitFont = UIFont.systemFont(ofSize: 13, weight: .bold)
        let labelAttr: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: UIColor.white.withAlphaComponent(0.55), .kern: 1.4]
        let valueAttr: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: UIColor.white]
        let unitAttr: [NSAttributedString.Key: Any] = [.font: unitFont, .foregroundColor: UIColor.white.withAlphaComponent(0.6)]
        let columns: [CGFloat] = stats.map { stat in
            let label = (stat.label as NSString).size(withAttributes: labelAttr).width + 16
            let value = (stat.value as NSString).size(withAttributes: valueAttr).width + (stat.unit as NSString).size(withAttributes: unitAttr).width + 3
            return max(label, value) + 36
        }
        let height: CGFloat = 70
        let size = CGSize(width: ceil(columns.reduce(0, +) + 10), height: height)
        return render(size, scale: 2) { context, s in
            let rect = CGRect(origin: .zero, size: s).insetBy(dx: 1, dy: 1)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 14)
            context.setFillColor(UIColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 0.78).cgColor)
            context.addPath(path.cgPath)
            context.fillPath()
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.12).cgColor)
            context.setLineWidth(1)
            context.addPath(path.cgPath)
            context.strokePath()
            // Accent edge
            context.saveGState()
            context.addPath(path.cgPath)
            context.clip()
            context.setFillColor(accent.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 4, height: s.height))
            context.restoreGState()
            var x: CGFloat = 10
            for (index, stat) in stats.enumerated() {
                let left = x + 18
                if let symbol = UIImage(systemName: stat.icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold))?
                    .withTintColor(accent, renderingMode: .alwaysOriginal) {
                    symbol.draw(at: CGPoint(x: left, y: 14))
                }
                (stat.label as NSString).draw(at: CGPoint(x: left + 15, y: 12), withAttributes: labelAttr)
                let valueSize = (stat.value as NSString).size(withAttributes: valueAttr)
                (stat.value as NSString).draw(at: CGPoint(x: left, y: 28), withAttributes: valueAttr)
                (stat.unit as NSString).draw(at: CGPoint(x: left + valueSize.width + 3, y: 28 + valueSize.height - 22), withAttributes: unitAttr)
                x += columns[index]
                if index < stats.count - 1 {
                    context.setFillColor(UIColor.white.withAlphaComponent(0.1).cgColor)
                    context.fill(CGRect(x: x, y: 14, width: 1, height: s.height - 28))
                }
            }
        }
    }

    /// Dark on the left, clear to the right: the finish text sits on it, the car stays in view.
    static let finishScrim: SKTexture = render(CGSize(width: 256, height: 64), scale: 1) { context, s in
        let colors = [UIColor.black.withAlphaComponent(0.72).cgColor, UIColor.black.withAlphaComponent(0.45).cgColor,
                      UIColor.black.withAlphaComponent(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: s.width, y: 0), options: [])
        }
    }

    /// Dark edges, clear middle: focuses the finish title.
    static let finishVignette: SKTexture = render(CGSize(width: 256, height: 128), scale: 1) { context, s in
        let colors = [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.25).cgColor,
                      UIColor.black.withAlphaComponent(0.7).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
            context.saveGState()
            context.scaleBy(x: 1, y: s.height / s.width)
            let center = CGPoint(x: s.width / 2, y: s.width / 2)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: s.width * 0.62,
                                       options: [.drawsAfterEndLocation])
            context.restoreGState()
        }
    }

    /// Soft horizontal light band behind the title (additive).
    static let finishBand: SKTexture = render(CGSize(width: 256, height: 64), scale: 1) { context, s in
        let colors = [UIColor.white.withAlphaComponent(0.9).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.saveGState()
            context.scaleBy(x: 1, y: s.height / s.width)
            let center = CGPoint(x: s.width / 2, y: s.width / 2)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: s.width / 2, options: [])
            context.restoreGState()
        }
    }

    /// Slanted white bar with soft edges: the shine that sweeps over the title.
    static let sheenTexture: SKTexture = render(CGSize(width: 64, height: 128), scale: 1) { context, s in
        let colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.withAlphaComponent(0.85).cgColor,
                      UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: s.width, y: 0), options: [])
        }
    }

    /// Nitro flame strip: bright white-cyan at the nozzle (right) fading to deep blue and black at
    /// the tip (left), soft at the top and bottom edges, with a few streaks. Drawn opaque on black
    /// for additive blending.
    static let flameImage: UIImage = {
        let size = CGSize(width: 256, height: 64)
        return image(size, scale: 1) { context, s in
            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(origin: .zero, size: s))
            let colors = [UIColor(red: 0.0, green: 0.05, blue: 0.25, alpha: 1).cgColor,
                          UIColor(red: 0.1, green: 0.35, blue: 1.0, alpha: 1).cgColor,
                          UIColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 1).cgColor,
                          UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1).cgColor] as CFArray
            guard let along = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 0.8, 1]) else { return }
            // Flame body: a teardrop that is wide at the nozzle and thin at the tip
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: s.height / 2))
            path.addCurve(to: CGPoint(x: s.width, y: s.height * 0.1), control1: CGPoint(x: s.width * 0.45, y: s.height * 0.42),
                          control2: CGPoint(x: s.width * 0.8, y: s.height * 0.05))
            path.addLine(to: CGPoint(x: s.width, y: s.height * 0.9))
            path.addCurve(to: CGPoint(x: 0, y: s.height / 2), control1: CGPoint(x: s.width * 0.8, y: s.height * 0.95),
                          control2: CGPoint(x: s.width * 0.45, y: s.height * 0.58))
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.drawLinearGradient(along, start: .zero, end: CGPoint(x: s.width, y: 0), options: [])
            // Darken toward the edges for a soft, round look
            if let edge = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [UIColor(white: 0, alpha: 0.85).cgColor, UIColor(white: 0, alpha: 0).cgColor,
                                              UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.85).cgColor] as CFArray,
                                     locations: [0, 0.35, 0.65, 1]) {
                context.drawLinearGradient(edge, start: .zero, end: CGPoint(x: 0, y: s.height), options: [])
            }
            // Hot streaks
            var generator = SystemRandomNumberGenerator()
            context.setStrokeColor(UIColor(white: 1, alpha: 0.35).cgColor)
            context.setLineWidth(1.5)
            for _ in 0..<9 {
                let y = CGFloat.random(in: s.height * 0.38...s.height * 0.62, using: &generator)
                let start = CGFloat.random(in: s.width * 0.3...s.width * 0.6, using: &generator)
                context.move(to: CGPoint(x: start, y: y))
                context.addLine(to: CGPoint(x: s.width, y: y + CGFloat.random(in: -3...3, using: &generator)))
            }
            context.strokePath()
            context.restoreGState()
        }
    }()

    /// Speed line: bright head fading into a long transparent tail (for the 2D boost overlay).
    static let speedLineTexture: SKTexture = {
        SKTexture(image: image(CGSize(width: 6, height: 128), scale: 1) { context, s in
            let colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: 0.9).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: s), cornerWidth: 3, cornerHeight: 3, transform: nil))
                context.clip()
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: s.height), options: [])
            }
        })
    }()

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
    /// A driving control: dark see-through glass with an accent edge and a soft accent glow at
    /// the bottom (the game stays visible behind the buttons).
    static func pedal(size: CGSize, accent: UIColor) -> SKTexture {
        render(size) { context, s in
            let body = CGRect(x: 2, y: 2, width: s.width - 4, height: s.height - 4)
            let corner: CGFloat = min(20, min(body.width, body.height) * 0.3)
            let face = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)
            context.addPath(face)
            context.setFillColor(UIColor(red: 0.03, green: 0.04, blue: 0.07, alpha: 0.5).cgColor)
            context.fillPath()
            context.saveGState()
            context.addPath(face)
            context.clip()
            if let glow = gradient([accent.withAlphaComponent(0.0), accent.withAlphaComponent(0.32)]) {
                context.drawLinearGradient(glow, start: CGPoint(x: 0, y: body.minY + body.height * 0.35),
                                           end: CGPoint(x: 0, y: body.maxY), options: [])
            }
            if let sheen = gradient([UIColor.white.withAlphaComponent(0.14), UIColor.white.withAlphaComponent(0.0)]) {
                context.drawLinearGradient(sheen, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.minY + 18), options: [])
            }
            context.restoreGState()
            context.addPath(CGPath(roundedRect: body.insetBy(dx: 0.75, dy: 0.75), cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.setStrokeColor(accent.withAlphaComponent(0.85).cgColor)
            context.setLineWidth(1.5)
            context.strokePath()
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

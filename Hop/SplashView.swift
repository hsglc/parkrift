import SwiftUI
import UIKit

/// The 2.5 second brand loading screen at launch: the key art dimmed and slowly pushing in under
/// falling rain, the app icon and the PARKRIFT wordmark in the middle with a light sweeping over
/// it, and a loading bar that fills in proportion to the time. The car models, textures and garage
/// studio are made ready behind it.
///
/// Everything moves in Core Animation (layers, a particle emitter for the rain): once started it
/// runs in the render server, so the heavy work on the main thread during launch can no longer
/// make it stutter (the SwiftUI timeline froze whenever the main thread was busy).
struct SplashView: View {
    static let duration: TimeInterval = 2.5

    var body: some View {
        SplashLayers()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

private struct SplashLayers: UIViewRepresentable {
    func makeUIView(context: Context) -> SplashLayerView { SplashLayerView() }
    func updateUIView(_ view: SplashLayerView, context: Context) {}
}

final class SplashLayerView: UIView {
    private let art = CALayer()
    private let vignette = CAGradientLayer()
    private let rain = CAEmitterLayer()
    private let icon = CALayer()
    private let iconGlow = CALayer()
    private let wordmark = CALayer()
    private let sheen = CAGradientLayer()
    private let sheenMask = CALayer()
    private let tagline = CALayer()
    private let track = CALayer()
    private let fill = CAGradientLayer()
    private var started = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 1)
        // The art, blurred ahead of time (blurring live every frame was the expensive part)
        art.contents = UIImage(named: "splash_blur.jpg")?.cgImage
        art.contentsGravity = .resizeAspectFill
        art.opacity = 0.45
        layer.addSublayer(art)
        vignette.type = .radial
        vignette.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.85).cgColor]
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1.1, y: 1.1)
        layer.addSublayer(vignette)
        layer.addSublayer(rain)
        // Icon with its cyan glow
        iconGlow.backgroundColor = UIColor(red: 0.25, green: 0.95, blue: 1.0, alpha: 1).cgColor
        iconGlow.shadowColor = UIColor(red: 0.25, green: 0.95, blue: 1.0, alpha: 1).cgColor
        iconGlow.shadowRadius = 26
        iconGlow.shadowOpacity = 0.5
        iconGlow.shadowOffset = .zero
        layer.addSublayer(iconGlow)
        icon.contents = UIImage(named: "brand_icon.jpg")?.cgImage
        icon.contentsGravity = .resizeAspectFill
        icon.masksToBounds = true
        icon.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        icon.borderWidth = 1
        icon.cornerCurve = .continuous
        layer.addSublayer(icon)
        // Wordmark and tagline drawn once into images
        let mark = ImageRenderer(content: Wordmark(size: 52).padding(16))
        mark.scale = UIScreen.main.scale
        if let image = mark.uiImage {
            wordmark.contents = image.cgImage
            wordmark.bounds = CGRect(origin: .zero, size: image.size)
            sheenMask.contents = image.cgImage
            sheenMask.bounds = CGRect(origin: .zero, size: image.size)
        }
        layer.addSublayer(wordmark)
        sheen.colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.withAlphaComponent(0.9).cgColor,
                        UIColor.white.withAlphaComponent(0).cgColor]
        sheen.startPoint = CGPoint(x: 0, y: 0.5)
        sheen.endPoint = CGPoint(x: 1, y: 0.5)
        let sheenHolder = CALayer()
        sheenHolder.addSublayer(sheen)
        sheenHolder.mask = sheenMask
        sheenHolder.name = "sheen"
        layer.addSublayer(sheenHolder)
        let line = ImageRenderer(content: Text(Strings.splashTagline.localUpper).font(.kicker(11)).tracking(3)
            .foregroundStyle(.white.opacity(0.6)))
        line.scale = UIScreen.main.scale
        if let image = line.uiImage {
            tagline.contents = image.cgImage
            tagline.bounds = CGRect(origin: .zero, size: image.size)
        }
        layer.addSublayer(tagline)
        // Loading bar
        track.backgroundColor = UIColor.white.withAlphaComponent(0.12).cgColor
        layer.addSublayer(track)
        fill.colors = [UIColor(red: 0.25, green: 0.95, blue: 1.0, alpha: 1).cgColor, UIColor(red: 1.0, green: 0.3, blue: 0.75, alpha: 1).cgColor]
        fill.startPoint = CGPoint(x: 0, y: 0.5)
        fill.endPoint = CGPoint(x: 1, y: 0.5)
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.shadowColor = UIColor(red: 0.25, green: 0.95, blue: 1.0, alpha: 1).cgColor
        fill.shadowRadius = 6
        fill.shadowOpacity = 0.8
        fill.shadowOffset = .zero
        track.addSublayer(fill)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = bounds.width, h = bounds.height
        art.frame = bounds
        art.anchorPoint = CGPoint(x: 0.6, y: 0.55)
        art.frame = bounds
        vignette.frame = bounds
        // Rain: thin streaks falling at a slant over the whole screen
        rain.frame = bounds
        rain.emitterShape = .line
        rain.emitterPosition = CGPoint(x: w / 2, y: -40)
        rain.emitterSize = CGSize(width: w * 1.3, height: 1)
        if rain.emitterCells == nil {
            let cell = CAEmitterCell()
            cell.contents = SplashLayerView.streak.cgImage
            cell.birthRate = 70
            cell.lifetime = 1.6
            cell.velocity = h * 0.95
            cell.velocityRange = h * 0.3
            cell.emissionLongitude = .pi / 2 - 0.25
            cell.scale = 0.5
            cell.scaleRange = 0.25
            cell.alphaRange = 0.2
            cell.color = UIColor.white.withAlphaComponent(0.22).cgColor
            rain.emitterCells = [cell]
            rain.beginTime = CACurrentMediaTime() - 1.2   // already falling on the first frame
        }
        let iconSize = min(128, h * 0.3)
        let centerY = h / 2 - 14
        let stackHeight = iconSize + 14 + wordmark.bounds.height + 10 + tagline.bounds.height
        let top = centerY - stackHeight / 2
        icon.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        icon.cornerRadius = iconSize * 0.225
        icon.position = CGPoint(x: w / 2, y: top + iconSize / 2)
        iconGlow.bounds = icon.bounds.insetBy(dx: 6, dy: 6)
        iconGlow.cornerRadius = icon.cornerRadius
        iconGlow.position = icon.position
        iconGlow.shadowPath = UIBezierPath(roundedRect: iconGlow.bounds, cornerRadius: icon.cornerRadius).cgPath
        wordmark.position = CGPoint(x: w / 2, y: top + iconSize + 14 + wordmark.bounds.height / 2 - 16)
        if let holder = layer.sublayers?.first(where: { $0.name == "sheen" }) {
            holder.frame = wordmark.frame
            sheenMask.frame = holder.bounds
            sheen.frame = CGRect(x: -80, y: 0, width: 70, height: holder.bounds.height)
        }
        tagline.position = CGPoint(x: w / 2, y: wordmark.frame.maxY + tagline.bounds.height / 2 - 6)
        let lineWidth = min(300, w * 0.36)
        track.frame = CGRect(x: (w - lineWidth) / 2, y: h - 34, width: lineWidth, height: 3)
        track.cornerRadius = 1.5
        fill.bounds = CGRect(x: 0, y: 0, width: lineWidth, height: 3)
        fill.position = CGPoint(x: 0, y: 1.5)
        fill.cornerRadius = 1.5
        CATransaction.commit()
        if !started { start() }
    }

    /// All the motion, handed to Core Animation in one go.
    private func start() {
        started = true
        let now = CACurrentMediaTime()
        let d = SplashView.duration
        func add(_ layer: CALayer, _ keyPath: String, from: Any, to: Any, delay: Double, duration: Double,
                 timing: CAMediaTimingFunctionName = .easeOut) {
            let a = CABasicAnimation(keyPath: keyPath)
            a.fromValue = from
            a.toValue = to
            a.beginTime = now + delay
            a.duration = duration
            a.timingFunction = CAMediaTimingFunction(name: timing)
            a.fillMode = .both
            a.isRemovedOnCompletion = false
            layer.add(a, forKey: keyPath)
        }
        add(art, "transform.scale", from: 1.04, to: 1.10, delay: 0, duration: d, timing: .linear)
        add(icon, "transform.scale", from: 0.82, to: 1.0, delay: 0, duration: 0.75)
        add(icon, "opacity", from: 0, to: 1, delay: 0, duration: 0.6)
        add(iconGlow, "opacity", from: 0, to: 1, delay: 0, duration: 0.6)
        let pulse = CABasicAnimation(keyPath: "shadowOpacity")
        pulse.fromValue = 0.25
        pulse.toValue = 0.75
        pulse.duration = d / 2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        iconGlow.add(pulse, forKey: "pulse")
        add(wordmark, "opacity", from: 0, to: 1, delay: d * 0.12, duration: 0.55)
        add(wordmark, "transform.translation.y", from: 14, to: 0, delay: d * 0.12, duration: 0.55)
        if let holder = layer.sublayers?.first(where: { $0.name == "sheen" }) {
            add(holder, "transform.translation.y", from: 14, to: 0, delay: d * 0.12, duration: 0.55)
            add(sheen, "position.x", from: -40, to: holder.bounds.width + 40, delay: d * 0.4, duration: d * 0.45, timing: .easeInEaseOut)
        }
        add(tagline, "opacity", from: 0, to: 1, delay: d * 0.28, duration: 0.55)
        // The bar fills in proportion to the time, full just before the fade
        add(fill, "transform.scale.x", from: 0.001, to: 1, delay: 0, duration: d * 0.96, timing: .easeInEaseOut)
    }

    /// One rain streak (slanted like the drops' path).
    private static let streak: UIImage = {
        let size = CGSize(width: 14, height: 44)
        return UIGraphicsImageRenderer(size: size).image { context in
            let c = context.cgContext
            c.setStrokeColor(UIColor.white.cgColor)
            c.setLineWidth(1.2)
            c.setLineCap(.round)
            c.move(to: CGPoint(x: size.width - 2, y: size.height - 1))
            c.addLine(to: CGPoint(x: 2, y: 1))
            c.strokePath()
        }
    }()
}

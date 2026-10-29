import SwiftUI

/// The 2.5 second brand loading screen at launch: the key art dimmed and slowly pushing in under
/// falling rain, the app icon and the PARKRIFT wordmark in the middle, and a loading bar that fills
/// in proportion to the time. The car models, textures and garage studio are made ready behind
/// it, so the menu is smooth from its first frame.
struct SplashView: View {
    static let duration: TimeInterval = 2.5
    @State private var start = Date()
    private let art = UIImage(named: "splash.jpg")
    private let icon = UIImage(named: "brand_icon.jpg")

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            let t = min(1, elapsed / SplashView.duration)
            GeometryReader { proxy in
                ZStack {
                    Color(red: 0.02, green: 0.03, blue: 0.07)
                    if let art = art {
                        Image(uiImage: art)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(1.04 + 0.06 * t, anchor: UnitPoint(x: 0.6, y: 0.55))
                            .clipped()
                            .blur(radius: 6)
                            .opacity(0.45)
                    }
                    RadialGradient(colors: [.clear, .black.opacity(0.85)], center: .center,
                                   startRadius: proxy.size.height * 0.2, endRadius: proxy.size.width * 0.7)
                    RainOverlay(time: elapsed)
                    brand(t: t, height: proxy.size.height)
                    progress(t: t, width: proxy.size.width)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { start = Date() }
    }

    private func brand(t: Double, height: CGFloat) -> some View {
        func rise(_ delay: Double, _ length: Double = 0.22) -> Double { min(1, max(0, (t - delay) / length)) }
        let ease = { (x: Double) in 1 - pow(1 - x, 3) }
        let iconSize = min(128, height * 0.3)
        let glow = 0.35 + 0.25 * sin(t * .pi * 2)
        return VStack(spacing: 14) {
            if let icon = icon {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: Color(red: 0.25, green: 0.95, blue: 1.0).opacity(glow), radius: 26)
                    .scaleEffect(0.82 + 0.18 * ease(rise(0.0, 0.3)))
                    .opacity(ease(rise(0.0, 0.25)))
            }
            ZStack {
                Wordmark(size: 52)
                // A band of light running across the letters
                Wordmark(size: 52)
                    .mask(
                        GeometryReader { box in
                            LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 60)
                                .rotationEffect(.degrees(18))
                                .offset(x: -90 + (box.size.width + 180) * min(1, max(0, (t - 0.4) / 0.45)))
                        }
                    )
                    .blendMode(.plusLighter)
            }
            .opacity(ease(rise(0.12)))
            .offset(y: 14 * (1 - ease(rise(0.12))))
            Text(Strings.splashTagline.uppercased())
                .font(.kicker(11))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.6))
                .opacity(ease(rise(0.28)))
        }
        .offset(y: -14)
    }

    private func progress(t: Double, width: CGFloat) -> some View {
        // In proportion to the time (full just before the fade), only softened at both ends
        let x = min(1, t / 0.96)
        let fill = CGFloat(0.8 * x + 0.2 * x * x * (3 - 2 * x))
        let lineWidth = min(300, width * 0.36)
        return VStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.95, blue: 1.0), Color(red: 1.0, green: 0.3, blue: 0.75)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: lineWidth * fill)
                    .shadow(color: Color(red: 0.25, green: 0.95, blue: 1.0).opacity(0.8), radius: 6)
            }
            .frame(width: lineWidth, height: 3)
            Text("\(Int(fill * 100))%")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 26)
    }
}

/// Thin slanted rain streaks drawn over the art (one Canvas, cheap).
private struct RainOverlay: View {
    let time: TimeInterval
    private static let drops: [(x: Double, y: Double, speed: Double, length: Double, alpha: Double)] = {
        var generator = SystemRandomNumberGenerator()
        return (0..<90).map { _ in
            (Double.random(in: 0...1, using: &generator), Double.random(in: 0...1, using: &generator),
             Double.random(in: 0.9...1.6, using: &generator), Double.random(in: 18...42, using: &generator),
             Double.random(in: 0.08...0.3, using: &generator))
        }
    }()

    var body: some View {
        Canvas { context, size in
            for drop in RainOverlay.drops {
                let travel = CGFloat((drop.y + time * drop.speed).truncatingRemainder(dividingBy: 1.0))
                let length = CGFloat(drop.length)
                let y = travel * (size.height + 80) - 40
                let x = CGFloat(drop.x) * (size.width + 80) - 40 + travel * 60
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x - length * 0.28, y: y - length))
                context.stroke(path, with: .color(.white.opacity(drop.alpha)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

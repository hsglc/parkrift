import SwiftUI

/// The 2 second opening screen: the key art (Meshy text-to-image, Textures/splash.jpg) slowly
/// pushing in under falling rain, the title sliding in with a light sweep, and a neon line that
/// fills while the game gets ready.
struct SplashView: View {
    static let duration: TimeInterval = 2.0
    @State private var start = Date()
    @State private var appeared = false
    private let art = UIImage(named: "splash.jpg")

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = min(1, timeline.date.timeIntervalSince(start) / SplashView.duration)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Color(red: 0.02, green: 0.03, blue: 0.07)
                    if let art = art {
                        Image(uiImage: art)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            // Slow push in and a little drift to the left
                            .scaleEffect(1.04 + 0.07 * t, anchor: UnitPoint(x: 0.62, y: 0.55))
                            .offset(x: -14 * t)
                            .clipped()
                    }
                    // Darker on the left for the title, and a deep fade along the bottom
                    LinearGradient(colors: [.black.opacity(0.78), .black.opacity(0.35), .clear],
                                   startPoint: .leading, endPoint: UnitPoint(x: 0.72, y: 0.5))
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom)
                    RainOverlay(time: timeline.date.timeIntervalSince(start))
                    title(t: t)
                        .padding(.leading, max(36, proxy.size.width * 0.07))
                    progress(t: t, width: proxy.size.width)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { start = Date() }
    }

    private func title(t: Double) -> some View {
        // Each part arrives a moment after the previous one
        func rise(_ delay: Double) -> Double { min(1, max(0, (t - delay) / 0.28)) }
        let ease = { (x: Double) in 1 - pow(1 - x, 3) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Capsule().fill(Color(red: 0.25, green: 0.95, blue: 1.0)).frame(width: 22, height: 3)
                Text("PARK · DRIFT · ONLINE")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .opacity(ease(rise(0.05)))
            .offset(x: -24 * (1 - ease(rise(0.05))))
            ZStack(alignment: .leading) {
                Text("PARKRIFT")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .italic()
                    .tracking(2)
                    .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.78, green: 0.93, blue: 1.0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color(red: 0.2, green: 0.85, blue: 1.0).opacity(0.55), radius: 18)
                // A band of light running across the letters
                Text("PARKRIFT")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .italic()
                    .tracking(2)
                    .foregroundStyle(.white)
                    .mask(
                        GeometryReader { box in
                            LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 70)
                                .rotationEffect(.degrees(18))
                                .offset(x: -90 + (box.size.width + 180) * min(1, max(0, (t - 0.35) / 0.5)))
                        }
                    )
                    .blendMode(.plusLighter)
            }
            .opacity(ease(rise(0.12)))
            .offset(x: -40 * (1 - ease(rise(0.12))))
            .scaleEffect(0.94 + 0.06 * ease(rise(0.12)), anchor: .leading)
            Text(Strings.splashTagline)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .opacity(ease(rise(0.3)))
                .offset(y: 8 * (1 - ease(rise(0.3))))
        }
    }

    private func progress(t: Double, width: CGFloat) -> some View {
        let fill = CGFloat(1 - pow(1 - min(1, t / 0.92), 2))
        let lineWidth = min(320, width * 0.4)
        return VStack(alignment: .leading, spacing: 8) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.leading, max(36, width * 0.07))
        .padding(.bottom, 30)
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

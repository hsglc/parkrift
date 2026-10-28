import SwiftUI

/// Shared colors and building blocks for the SwiftUI screens.
enum Palette {
    static let red = Color(red: 0.95, green: 0.27, blue: 0.27)
    static let blue = Color(red: 0.20, green: 0.52, blue: 0.98)
    static let gold = Color(red: 1.0, green: 0.80, blue: 0.20)
    static let goldDeep = Color(red: 1.0, green: 0.58, blue: 0.10)
    static let ink = Color(red: 0.06, green: 0.07, blue: 0.12)
    static let card = Color(red: 0.10, green: 0.11, blue: 0.18)

    static func player(_ slot: Int) -> Color { slot == 0 ? red : blue }

    struct ButtonColors {
        let top: Color
        let bottom: Color
        let edge: Color
    }

    static let orange = ButtonColors(top: Color(red: 1.0, green: 0.64, blue: 0.30),
                                     bottom: Color(red: 0.96, green: 0.38, blue: 0.18),
                                     edge: Color(red: 0.62, green: 0.20, blue: 0.08))
    static let blueButton = ButtonColors(top: Color(red: 0.42, green: 0.72, blue: 1.0),
                                         bottom: Color(red: 0.16, green: 0.44, blue: 0.95),
                                         edge: Color(red: 0.07, green: 0.23, blue: 0.60))
    static let green = ButtonColors(top: Color(red: 0.42, green: 0.90, blue: 0.52),
                                    bottom: Color(red: 0.14, green: 0.66, blue: 0.38),
                                    edge: Color(red: 0.05, green: 0.38, blue: 0.20))
    static let slate = ButtonColors(top: Color(red: 0.36, green: 0.39, blue: 0.50),
                                    bottom: Color(red: 0.24, green: 0.26, blue: 0.36),
                                    edge: Color(red: 0.12, green: 0.13, blue: 0.20))
    static let disabled = ButtonColors(top: Color(white: 0.42), bottom: Color(white: 0.32), edge: Color(white: 0.18))
}

/// Chunky game button with a raised edge that presses down.
struct ChunkyButtonStyle: ButtonStyle {
    var colors: ButtonColors
    var height: CGFloat = 50
    var corner: CGFloat = 16
    var fontSize: CGFloat = 18

    typealias ButtonColors = Palette.ButtonColors

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let depth: CGFloat = 5
        configuration.label
            .font(.system(size: fontSize, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.28), radius: 0, x: 0, y: 1.5)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(LinearGradient(colors: [colors.top, colors.bottom], startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.0)],
                                                     startPoint: .top, endPoint: .center), lineWidth: 1.5)
                }
            )
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(colors.edge)
                    .offset(y: pressed ? 1 : depth)
            )
            .offset(y: pressed ? depth - 1 : 0)
            .padding(.bottom, depth)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: pressed)
    }
}

/// Dark rounded panel used for menu and lobby cards.
struct PanelModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.card.opacity(0.92), Palette.ink.opacity(0.92)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
    }
}

extension View {
    func panel(padding: CGFloat = 18) -> some View { modifier(PanelModifier(padding: padding)) }
}

/// Three stars; `filled` of them are gold.
struct StarsRow: View {
    let filled: Int
    var size: CGFloat = 12
    var spacing: CGFloat = 2

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "star.fill")
                    .font(.system(size: size, weight: .black))
                    .foregroundStyle(index < filled
                                     ? AnyShapeStyle(LinearGradient(colors: [Palette.gold, Palette.goldDeep], startPoint: .top, endPoint: .bottom))
                                     : AnyShapeStyle(Color.white.opacity(0.16)))
            }
        }
    }
}

/// "Parkrift" wordmark: "Park" in the racing red, "rift" in the neon cyan of the icon's drift trail.
struct Logo: View {
    var size: CGFloat = 50

    var body: some View {
        HStack(spacing: 0) {
            Text("Park")
                .foregroundStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.40), Color(red: 1.0, green: 0.24, blue: 0.35)],
                                                startPoint: .top, endPoint: .bottom))
            Text("rift")
                .foregroundStyle(LinearGradient(colors: [Color(red: 0.55, green: 0.95, blue: 1.0), Color(red: 0.24, green: 0.80, blue: 1.0)],
                                                startPoint: .top, endPoint: .bottom))
        }
        .font(.race(size * 1.08))
        .shadow(color: .black.opacity(0.55), radius: 0, x: 0, y: 3)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}

/// Round icon button (sound, close…).
struct RoundIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Palette.ink.opacity(0.75)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

/// Small round button that toggles music and sounds.
struct SoundToggle: View {
    @State private var muted = AudioManager.shared.isMuted

    var body: some View {
        NeoIconButton(systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
            muted.toggle()
            AudioManager.shared.isMuted = muted
        }
    }
}

// MARK: - Racing style (garage, menu)

extension Font {
    /// Heavy condensed italic, the racing-game display face.
    static func race(_ size: CGFloat, weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight).width(.condensed).italic()
    }

    /// Small wide caps for labels above titles.
    static func kicker(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .heavy).width(.expanded)
    }
}

extension Palette {
    static let neon = Color(red: 0.22, green: 0.84, blue: 1.0)
    static let carbon = Color(red: 0.035, green: 0.04, blue: 0.06)
}

/// Parallelogram leaning right by `skew` points, the shape of racing-game plates and buttons.
struct SlantedShape: Shape {
    var skew: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + skew, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - skew, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Big slanted call-to-action button with a light sweep.
struct RaceButtonStyle: ButtonStyle {
    var color: Color = Palette.gold
    var textColor: Color = Palette.ink
    var height: CGFloat = 54
    var fontSize: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.race(fontSize))
            .tracking(0.5)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                SlantedShape(skew: 16)
                    .fill(LinearGradient(colors: [color, color.opacity(0.82)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(SlantedShape(skew: 16).strokeBorderCompat(Color.white.opacity(0.45), lineWidth: 1))
            .shadow(color: color.opacity(0.45), radius: configuration.isPressed ? 4 : 14, y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension Shape {
    /// Stroke that stays inside the shape (Shape has no strokeBorder before InsettableShape).
    func strokeBorderCompat(_ color: Color, lineWidth: CGFloat) -> some View {
        stroke(color, lineWidth: lineWidth).padding(lineWidth / 2)
    }
}

/// Dark slanted glass plate for racing panels.
struct RacePlate: ViewModifier {
    var skew: CGFloat = 18
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(.vertical, padding)
            .padding(.leading, padding + skew * 0.6)
            .padding(.trailing, padding)
            .background(
                SlantedShape(skew: skew)
                    .fill(LinearGradient(colors: [Palette.carbon.opacity(0.88), Palette.carbon.opacity(0.94)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                SlantedShape(skew: skew)
                    .strokeBorderCompat(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }
}

extension View {
    func racePlate(skew: CGFloat = 18, padding: CGFloat = 18) -> some View {
        modifier(RacePlate(skew: skew, padding: padding))
    }
}

/// Coin balance in a dark capsule (menu and garage).
struct CoinPill: View {
    let coins: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "dollarsign.circle.fill")
                .foregroundStyle(Palette.gold)
            Text("\(coins)")
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.race(17))
        .foregroundStyle(.white)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: 34)
        .background(SlantedShape(skew: 7).fill(Neo.ink.opacity(0.75)))
        .overlay(SlantedShape(skew: 7).strokeBorderCompat(Palette.gold.opacity(0.45), lineWidth: 1))
        .animation(.easeOut(duration: 0.3), value: coins)
    }
}

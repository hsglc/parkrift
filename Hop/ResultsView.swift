import SwiftUI
import UIKit

struct ResultEntry: Identifiable {
    var id: Int { slot }
    let name: String
    let slot: Int
    let time: Double?
    let hits: Int
    let isMe: Bool
    var isWinner: Bool

    var stars: Int { time == nil ? 0 : AppModel.stars(forHits: hits) }
}

enum ResultFooter {
    case solo(hasNext: Bool)
    case autoNext(seconds: Double)
    case final
}

struct ResultsInfo: Identifiable {
    let id = UUID()
    let levelIndex: Int
    let levelName: String
    let entries: [ResultEntry]
    let footer: ResultFooter
    let newBest: Bool
    let bestTime: Double?

    var me: ResultEntry? { entries.first { $0.isMe } }
}

/// The "parked!" card shown over the game when a level is finished.
struct ResultsOverlay: View {
    @EnvironmentObject var model: AppModel
    let info: ResultsInfo

    @State private var appeared = false
    @State private var shownStars = 0
    @State private var progress: CGFloat = 0

    private var isFinal: Bool {
        if case .final = info.footer { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.5 : 0)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                hero
                    .frame(width: 214)
                    .frame(maxHeight: .infinity)
                    .background(heroBackground)
                details
                    .frame(width: 300)
                    .padding(16)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(
                LinearGradient(colors: [Palette.card, Palette.ink], startPoint: .top, endPoint: .bottom)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
            .scaleEffect(appeared ? 1 : 0.8)
            .opacity(appeared ? 1 : 0)
        }
        .task(id: info.id) { await animateIn() }
    }

    // MARK: Hero (left)

    private var heroBackground: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.62, blue: 0.40), Color(red: 0.06, green: 0.32, blue: 0.24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Soft light rays
            ForEach(0..<8, id: \.self) { index in
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 26, height: 360)
                    .rotationEffect(.degrees(Double(index) * 22.5))
            }
            .offset(y: -40)
        }
        .clipped()
    }

    private var hero: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 74, height: 74)
                Circle()
                    .fill(LinearGradient(colors: isFinal ? [Palette.gold, Palette.goldDeep]
                                                         : [Color(red: 0.55, green: 1.0, blue: 0.62), Color(red: 0.18, green: 0.78, blue: 0.42)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 60, height: 60)
                    .shadow(color: .black.opacity(0.25), radius: 0, y: 3)
                Image(systemName: isFinal ? "trophy.fill" : "checkmark")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 0, y: 2)
            }
            .scaleEffect(appeared ? 1 : 0.3)

            Text(isFinal ? Strings.allDone : Strings.parkedTitle)
                .font(.system(size: isFinal ? 20 : 26, weight: .black, design: .rounded))
                .italic()
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.3), radius: 0, y: 2)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(Strings.levelShort) \(info.levelIndex + 1) · \(info.levelName)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    let lit = index < shownStars
                    Image(systemName: "star.fill")
                        .font(.system(size: index == 1 ? 38 : 30, weight: .black))
                        .foregroundStyle(lit
                                         ? AnyShapeStyle(LinearGradient(colors: [Palette.gold, Palette.goldDeep], startPoint: .top, endPoint: .bottom))
                                         : AnyShapeStyle(Color.black.opacity(0.25)))
                        .shadow(color: lit ? Palette.gold.opacity(0.7) : .clear, radius: 8)
                        .scaleEffect(lit ? 1 : 0.85)
                        .offset(y: index == 1 ? -6 : 0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.45), value: lit)
                }
            }
            .padding(.top, 4)

            if info.newBest {
                Text(Strings.newBest.uppercased())
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Palette.gold))
                    .rotationEffect(.degrees(-3))
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
    }

    // MARK: Details (right)

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            if info.entries.count == 1, let me = info.me {
                HStack(spacing: 8) {
                    StatTile(icon: "stopwatch.fill", label: Strings.timeLabel, value: format(me.time), tint: Palette.gold)
                    StatTile(icon: "car.side.rear.and.collision.and.car.side.front", label: Strings.bumpsLabel, value: "\(me.hits)",
                             tint: me.hits == 0 ? Color(red: 0.45, green: 0.95, blue: 0.6) : Color(red: 1.0, green: 0.55, blue: 0.4))
                }
                HStack(spacing: 8) {
                    StatTile(icon: "crown.fill", label: Strings.bestLabel, value: format(info.bestTime), tint: Color(red: 0.75, green: 0.6, blue: 1.0))
                    hintTile
                }
            } else {
                ForEach(info.entries) { entry in
                    PlayerResultRow(entry: entry)
                }
            }
            footer
        }
    }

    private var hintTile: some View {
        HStack(spacing: 6) {
            StarsRow(filled: 3, size: 9, spacing: 1)
            Text(Strings.starHint)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    @ViewBuilder
    private var footer: some View {
        switch info.footer {
        case .solo(let hasNext):
            HStack(spacing: 8) {
                Button { model.leaveToMenu() } label: { Image(systemName: "house.fill") }
                    .buttonStyle(ChunkyButtonStyle(colors: Palette.slate, height: 46, fontSize: 17))
                    .frame(width: 56)
                Button { model.retryLevel() } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(ChunkyButtonStyle(colors: Palette.blueButton, height: 46, fontSize: 17))
                    .frame(width: 56)
                if hasNext {
                    Button { model.nextLevel() } label: {
                        HStack(spacing: 6) {
                            Text(Strings.next)
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(ChunkyButtonStyle(colors: Palette.green, height: 46))
                }
            }
        case .autoNext:
            VStack(alignment: .leading, spacing: 6) {
                Text(Strings.nextLevelSoon)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.90, blue: 0.52), Color(red: 0.14, green: 0.66, blue: 0.38)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 8)
            }
        case .final:
            HStack(spacing: 8) {
                Button { model.leaveToMenu() } label: {
                    Label(Strings.backToMenu, systemImage: "house.fill")
                }
                .buttonStyle(ChunkyButtonStyle(colors: Palette.green, height: 46, fontSize: 16))
            }
        }
    }

    private func format(_ time: Double?) -> String {
        guard let time = time else { return "–" }
        return String(format: "%.1f s", time)
    }

    // MARK: Animation

    private func animateIn() async {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { appeared = true }
        if case .autoNext(let seconds) = info.footer {
            withAnimation(.linear(duration: seconds)) { progress = 1 }
        }
        let stars = info.me?.stars ?? 0
        try? await Task.sleep(nanoseconds: 350_000_000)
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        for index in 0..<stars {
            if Task.isCancelled { return }
            shownStars = index + 1
            haptic.impactOccurred(intensity: 0.6 + 0.2 * CGFloat(index))
            AudioManager.shared.play("beep", volume: 0.35 + 0.15 * Float(index))
            try? await Task.sleep(nanoseconds: 260_000_000)
        }
    }
}

private struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .tracking(1)
                Text(value)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct PlayerResultRow: View {
    let entry: ResultEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isWinner ? "crown.fill" : "car.side.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(entry.isWinner ? Palette.gold : .white)
                .frame(width: 36, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.player(entry.slot)))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                StarsRow(filled: entry.stars, size: 9, spacing: 1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.time.map { String(format: "%.1f s", $0) } ?? Strings.notParked)
                    .font(.system(size: entry.time == nil ? 12 : 18, weight: .black, design: .rounded))
                    .foregroundStyle(entry.time == nil ? Color.white.opacity(0.5) : Palette.gold)
                    .monospacedDigit()
                Text(Strings.hits(entry.hits))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(entry.isMe ? 0.10 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(entry.isMe ? Palette.player(entry.slot).opacity(0.7) : Color.clear, lineWidth: 1.2))
    }
}

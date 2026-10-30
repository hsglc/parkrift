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
    var score: Double? = nil

    var stars: Int { time == nil ? 0 : AppModel.stars(forHits: hits) }
}

/// How the round (or the match, on the last card) went for the player; it sets the card's colour,
/// its icon and its main button.
enum ResultOutcome {
    case success    // parked / finished, alone
    case failed     // did not park or finish (too many hits, time up)
    case won        // beat the friend this round
    case lost       // the friend won
    case draw
    case champion   // won the match, or finished every level
}

enum ResultFooter {
    case solo(hasNext: Bool)
    case autoNext(seconds: Double)
    case final
}

struct ResultsInfo: Identifiable {
    var id = UUID()
    let levelIndex: Int
    let levelTitle: String
    let entries: [ResultEntry]
    let footer: ResultFooter
    let newBest: Bool
    let bestTime: Double?
    var headline: String? = nil
    var scoreLine: String? = nil
    var reward: RunReward? = nil
    var outcome: ResultOutcome = .success
    /// On the last card of a match: how the last round went (the card shows the match).
    var roundLine: String? = nil

    var me: ResultEntry? { entries.first { $0.isMe } }

    /// The same card with other buttons (same id: it does not animate in again).
    func with(footer: ResultFooter) -> ResultsInfo {
        var copy = ResultsInfo(levelIndex: levelIndex, levelTitle: levelTitle, entries: entries, footer: footer,
                               newBest: newBest, bestTime: bestTime, headline: headline, scoreLine: scoreLine,
                               reward: reward, outcome: outcome, roundLine: roundLine)
        copy.id = id
        return copy
    }
}

/// The card shown over the game when a level ends, coloured by how it went: green when parked
/// or a round won, gold for a match won (or every level done), red when the player did not park
/// or lost, blue for a draw. A failed solo level makes trying again the main button.
struct ResultsOverlay: View {
    @EnvironmentObject var model: AppModel
    let info: ResultsInfo

    @State private var appeared = false
    @State private var shownStars = 0
    @State private var progress: CGFloat = 0
    @State private var shownCoins = 0

    private var isFinal: Bool {
        if case .final = info.footer { return true }
        return false
    }

    /// The player did not park (or finish) alone: too many hits, time up, gave up.
    private var failed: Bool { info.outcome == .failed }

    private var headToHead: Bool { info.entries.count > 1 }

    private var heroColors: [Color] {
        switch info.outcome {
        case .failed, .lost: return [Color(red: 0.74, green: 0.20, blue: 0.24), Color(red: 0.34, green: 0.07, blue: 0.12)]
        case .draw: return [Color(red: 0.24, green: 0.38, blue: 0.66), Color(red: 0.10, green: 0.15, blue: 0.32)]
        case .champion: return [Color(red: 0.86, green: 0.58, blue: 0.12), Color(red: 0.42, green: 0.22, blue: 0.06)]
        case .success, .won: return [Color(red: 0.16, green: 0.62, blue: 0.40), Color(red: 0.06, green: 0.32, blue: 0.24)]
        }
    }

    private var badgeColors: [Color] {
        switch info.outcome {
        case .failed, .lost: return [Color(red: 1.0, green: 0.48, blue: 0.44), Color(red: 0.86, green: 0.16, blue: 0.20)]
        case .draw: return [Color(red: 0.55, green: 0.75, blue: 1.0), Color(red: 0.22, green: 0.45, blue: 0.92)]
        case .champion: return [Palette.gold, Palette.goldDeep]
        case .success, .won: return [Color(red: 0.55, green: 1.0, blue: 0.62), Color(red: 0.18, green: 0.78, blue: 0.42)]
        }
    }

    private var badgeIcon: String {
        switch info.outcome {
        case .failed, .lost: return "xmark"
        case .draw: return "equal"
        case .champion: return "trophy.fill"
        case .won: return "crown.fill"
        case .success: return "checkmark"
        }
    }

    /// Failed with the next level not open yet: no way forward but trying again.
    private var nextOpen: Bool { model.unlockedLevels > info.levelIndex + 1 }

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
            LinearGradient(colors: heroColors, startPoint: .topLeading, endPoint: .bottomTrailing)
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
                    .fill(LinearGradient(colors: badgeColors, startPoint: .top, endPoint: .bottom))
                    .frame(width: 60, height: 60)
                    .shadow(color: .black.opacity(0.25), radius: 0, y: 3)
                Image(systemName: badgeIcon)
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 0, y: 2)
            }
            .scaleEffect(appeared ? 1 : 0.3)

            Text(info.headline ?? (failed ? Strings.notParkedTitle : (isFinal ? Strings.allDone : Strings.parkedTitle)))
                .font(.system(size: isFinal && info.headline == nil && !failed ? 20 : 26, weight: .black, design: .rounded))
                .italic()
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.3), radius: 0, y: 2)
                .fixedSize(horizontal: false, vertical: true)
            Text(info.levelTitle)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let scoreLine = info.scoreLine {
                Text(scoreLine)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.25)))
            }
            if let roundLine = info.roundLine {
                Text(roundLine)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Stars are the solo score; head to head the rows carry each player's stars
            if !headToHead {
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
            }

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
                    if let score = me.score {
                        StatTile(icon: "flag.checkered", label: Strings.scoreLabel, value: score >= 0 ? String(format: "%.1f", score) : "–", tint: Palette.gold)
                    } else {
                        StatTile(icon: "crown.fill", label: Strings.bestLabel, value: format(info.bestTime), tint: Color(red: 0.75, green: 0.6, blue: 1.0))
                    }
                    hintTile
                }
            } else {
                ForEach(info.entries) { entry in
                    PlayerResultRow(entry: entry)
                }
            }
            if let reward = info.reward, reward.total > 0 {
                coinRow(reward)
            }
            footer
        }
    }

    /// Coins earned: the total counts up, the lines that made it sit beside it, and a completed
    /// daily task gets its own gold tag.
    private func coinRow(_ reward: RunReward) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.gold)
                Text("+\(shownCoins)")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(reward.lines.map { "\($0.label) \($0.coins)" }.joined(separator: " · "))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                ForEach(reward.tasksDone.indices, id: \.self) { index in
                    Text("\(Strings.taskReadyTag) +\(reward.tasksDone[index].coins)")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Palette.gold))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var hintTile: some View {
        HStack(spacing: 6) {
            StarsRow(filled: 3, size: 9, spacing: 1)
            Text(info.me?.score != nil ? Strings.penaltyHint : Strings.starHint)
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
        if failed, info.entries.count == 1, !isAutoNext {
            // Did not park: trying again is the way forward (the next level only if already open)
            HStack(spacing: 8) {
                Button { model.leaveToMenu() } label: { Image(systemName: "house.fill") }
                    .buttonStyle(ChunkyButtonStyle(colors: Palette.slate, height: 46, fontSize: 17))
                    .frame(width: 56)
                Button { model.retryLevel() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text(Strings.tryAgain)
                    }
                }
                .buttonStyle(ChunkyButtonStyle(colors: Palette.orange, height: 46))
                if !isFinal && nextOpen {
                    Button { model.nextLevel() } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(ChunkyButtonStyle(colors: Palette.slate, height: 46, fontSize: 17))
                        .frame(width: 56)
                }
            }
        } else {
            footerButtons
        }
    }

    private var isAutoNext: Bool {
        if case .autoNext = info.footer { return true }
        return false
    }

    @ViewBuilder
    private var footerButtons: some View {
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
        // Coins count up after the stars
        let total = info.reward?.total ?? 0
        guard total > 0 else { return }
        let steps = 14
        for step in 1...steps {
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.05)) { shownCoins = total * step / steps }
            if step % 3 == 0 { AudioManager.shared.play("click", volume: 0.25) }
            try? await Task.sleep(nanoseconds: 45_000_000)
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
            if let score = entry.score {
                VStack(alignment: .trailing, spacing: 2) {
                    // Not finished: said in words (a lone dash read like a missing number)
                    Text(score >= 0 ? String(format: "%.1f", score) : Strings.didNotFinish)
                        .font(.system(size: score >= 0 ? 18 : 12, weight: .black, design: .rounded))
                        .foregroundStyle(score >= 0 ? Palette.gold : Color.white.opacity(0.5))
                        .monospacedDigit()
                    Text((entry.time.map { String(format: "%.1f s", $0) + " · " } ?? "") + Strings.crashes(entry.hits))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            } else {
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
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(entry.isMe ? 0.10 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(entry.isMe ? Palette.player(entry.slot).opacity(0.7) : Color.clear, lineWidth: 1.2))
    }
}

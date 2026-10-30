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
    /// Parking levels: the Santim Ölçer score (0...100) of the park.
    var precision: Int? = nil

    var me: ResultEntry? { entries.first { $0.isMe } }

    /// The same card with other buttons (same id: it does not animate in again).
    func with(footer: ResultFooter) -> ResultsInfo {
        var copy = ResultsInfo(levelIndex: levelIndex, levelTitle: levelTitle, entries: entries, footer: footer,
                               newBest: newBest, bestTime: bestTime, headline: headline, scoreLine: scoreLine,
                               reward: reward, outcome: outcome, roundLine: roundLine)
        copy.id = id
        copy.precision = precision
        return copy
    }
}

/// The screen over the game when a level ends, kept to what matters: the level in small type,
/// the result big, the stars (or the match score), the time and the coins earned, and one big
/// button for the way forward with the menu and retry as round icons beside it. No card: the
/// frozen game stays in view behind a dark shade.
struct ResultsOverlay: View {
    @EnvironmentObject var model: AppModel
    let info: ResultsInfo

    @State private var appeared = false
    @State private var titleIn = false
    @State private var restIn = false
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

    /// Failed with the next level not open yet: no way forward but trying again.
    private var nextOpen: Bool { model.unlockedLevels > info.levelIndex + 1 }

    /// Failed alone: what happened is the headline the game sends (too many hits, time up); the
    /// big line says plainly that the level was not done, the reason goes under it.
    private var failedRace: Bool { info.me?.score != nil }

    private var headline: String {
        if failed { return failedRace ? Strings.raceFailedTitle : Strings.notParkedTitle }
        return info.headline ?? (isFinal ? Strings.allDone : Strings.parkedTitle)
    }

    private var failReason: String? {
        guard failed else { return nil }
        if let reason = info.headline, reason != Strings.notParkedTitle { return reason }
        return info.roundLine
    }

    private let gold = Color(red: 1.0, green: 0.8, blue: 0.2)

    var body: some View {
        ZStack {
            Color(red: 0.024, green: 0.03, blue: 0.047).opacity(0.72)
                .ignoresSafeArea()
                .opacity(appeared ? 1 : 0)
            VStack(spacing: 0) {
                Text(info.levelTitle)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .opacity(titleIn ? 1 : 0)
                Text(headline.uppercased())
                    .font(.race(58))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 30)
                    .scaleEffect(titleIn ? 1 : 1.25)
                    .opacity(titleIn ? 1 : 0)
                middle
                    .padding(.top, 6)
                buttons
                    .padding(.top, 20)
                    .opacity(restIn ? 1 : 0)
                    .offset(y: restIn ? 0 : 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: info.id) { await animateIn() }
    }

    // MARK: Middle

    /// Alone: the stars, then the time and the coins. Head to head: the match score (or the
    /// round's winner) and one line about the round. Failed: why.
    @ViewBuilder
    private var middle: some View {
        if headToHead {
            VStack(spacing: 2) {
                if let scoreLine = info.scoreLine {
                    Text(scoreLine.components(separatedBy: " ").suffix(3).joined(separator: " "))
                        .font(.race(46))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                Text(info.roundLine ?? roundSummary)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                coinsLine.padding(.top, 6)
            }
            .opacity(restIn ? 1 : 0)
        } else if failed {
            VStack(spacing: 6) {
                if let reason = failReason {
                    Text(reason)
                        .font(.ui(15, .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .opacity(restIn ? 1 : 0)
        } else if let me = info.me {
            VStack(spacing: 10) {
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(0..<3, id: \.self) { star($0) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 22) {
                    figure(me.time.map { String(format: "%.1f", $0) } ?? "–", unit: Strings.secondsShort, tint: .white)
                    if let precision = info.precision {
                        Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 28)
                        figure(Strings.percent(precision), unit: Strings.precision.lowercased(), tint: .white)
                    }
                    if info.reward.map({ $0.total > 0 }) == true {
                        Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 28)
                        figure("+\(shownCoins)", unit: Strings.coinsWord, tint: gold)
                            .contentTransition(.numericText())
                    }
                }
                .opacity(restIn ? 1 : 0)
                if info.newBest {
                    Text(Strings.newBest)
                        .font(.ui(12, .heavy))
                        .foregroundStyle(gold)
                        .opacity(restIn ? 1 : 0)
                }
            }
        }
    }

    /// "Friend 31.9 s · you 34.2 s" for a round head to head.
    private var roundSummary: String {
        info.entries
            .map { "\($0.name) " + ($0.time.map { String(format: "%.1f %@", $0, Strings.secondsShort) } ?? "–") }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var coinsLine: some View {
        if let reward = info.reward, reward.total > 0 {
            figure("+\(shownCoins)", unit: Strings.coinsWord, tint: gold)
                .contentTransition(.numericText())
        }
    }

    private func star(_ index: Int) -> some View {
        let lit = index < shownStars
        return Image(systemName: "star.fill")
            .font(.system(size: index == 1 ? 50 : 40, weight: .black))
            .foregroundStyle(lit ? gold : Color.white.opacity(0.16))
            .shadow(color: lit ? gold.opacity(0.5) : .clear, radius: 12)
            .scaleEffect(lit ? 1 : 0.85)
            .animation(.spring(response: 0.32, dampingFraction: 0.45), value: lit)
    }

    private func figure(_ value: String, unit: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.race(40))
                .monospacedDigit()
            Text(unit)
                .font(.ui(15, .bold))
                .opacity(0.6)
        }
        .foregroundStyle(tint)
    }

    // MARK: Buttons

    /// One big button for the way forward; menu and retry (or next, after a fail) as round icons.
    @ViewBuilder
    private var buttons: some View {
        switch info.footer {
        case .autoNext:
            VStack(spacing: 8) {
                Text(Strings.nextLevelSoon)
                    .font(.ui(13, .bold))
                    .foregroundStyle(.white.opacity(0.75))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(gold).frame(width: proxy.size.width * progress)
                    }
                }
                .frame(width: 240, height: 6)
            }
        case .final:
            Button { model.leaveToMenu() } label: { Text(Strings.backToMenu.uppercased()) }
                .buttonStyle(MainPillStyle(fill: gold))
        case .solo(let hasNext):
            HStack(spacing: 14) {
                Button { model.leaveToMenu() } label: { Image(systemName: "house.fill") }
                    .buttonStyle(RoundIconStyle())
                    .accessibilityLabel(Strings.menu)
                if failed {
                    Button { model.retryLevel() } label: { Text(Strings.tryAgain.uppercased()) }
                        .buttonStyle(MainPillStyle(fill: Color(red: 1, green: 0.56, blue: 0.22)))
                    if nextOpen {
                        Button { model.nextLevel() } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(RoundIconStyle())
                            .accessibilityLabel(Strings.next)
                    }
                } else if hasNext {
                    Button { model.nextLevel() } label: { Text(Strings.next.uppercased()) }
                        .buttonStyle(MainPillStyle(fill: gold))
                    Button { model.retryLevel() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(RoundIconStyle())
                        .accessibilityLabel(Strings.retry)
                } else {
                    Button { model.retryLevel() } label: { Text(Strings.retry.uppercased()) }
                        .buttonStyle(MainPillStyle(fill: gold))
                }
            }
        }
    }

    // MARK: Animation

    private func animateIn() async {
        // The shade, the result slamming in, then the rest; the stars one by one, the coins
        // counting up
        withAnimation(.easeOut(duration: 0.2)) { appeared = true }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.62).delay(0.05)) { titleIn = true }
        withAnimation(.easeOut(duration: 0.3).delay(0.3)) { restIn = true }
        if case .autoNext(let seconds) = info.footer {
            withAnimation(.linear(duration: seconds)) { progress = 1 }
        }
        try? await Task.sleep(nanoseconds: 380_000_000)
        let stars = failed || headToHead ? 0 : (info.me?.stars ?? 0)
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        for index in 0..<stars {
            if Task.isCancelled { return }
            shownStars = index + 1
            haptic.impactOccurred(intensity: 0.6 + 0.2 * CGFloat(index))
            AudioManager.shared.play("beep", volume: 0.3 + 0.15 * Float(index))
            try? await Task.sleep(nanoseconds: 230_000_000)
        }
        let total = info.reward?.total ?? 0
        guard total > 0 else { return }
        let steps = 14
        for step in 1...steps {
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.05)) { shownCoins = total * step / steps }
            if step % 3 == 0 { AudioManager.shared.play("click", volume: 0.22) }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
    }
}

/// The big pill for the way forward.
struct MainPillStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.race(24))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 24)
            .frame(width: 240, height: 52)
            .background(Capsule().fill(fill))
            .shadow(color: fill.opacity(0.35), radius: configuration.isPressed ? 4 : 14, y: 5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A round glass icon button (menu, retry, next) beside the big one.
struct RoundIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.2 : 0.1)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

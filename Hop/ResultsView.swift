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

/// The card shown over the game when a level ends: one centred column, read top to bottom.
/// The level and the result (lit by the outcome's colour), the stars or the match score, one
/// glass panel with the figures (a timing board head to head) and the coins, then labelled
/// buttons with the way forward as the big one. Green when parked or a round won, gold for a
/// match won (or every level done), red when the player did not park or lost, blue for a draw.
struct ResultsOverlay: View {
    @EnvironmentObject var model: AppModel
    let info: ResultsInfo

    @State private var appeared = false
    @State private var titleIn = false
    @State private var panelIn = false
    @State private var shownStars = 0
    @State private var progress: CGFloat = 0
    @State private var shownCoins = 0

    private var isFinal: Bool {
        if case .final = info.footer { return true }
        return false
    }

    private var isAutoNext: Bool {
        if case .autoNext = info.footer { return true }
        return false
    }

    /// The player did not park (or finish) alone: too many hits, time up, gave up.
    private var failed: Bool { info.outcome == .failed }

    private var headToHead: Bool { info.entries.count > 1 }

    /// Failed with the next level not open yet: no way forward but trying again.
    private var nextOpen: Bool { model.unlockedLevels > info.levelIndex + 1 }

    private var badgeIcon: String {
        switch info.outcome {
        case .failed, .lost: return "xmark"
        case .draw: return "equal"
        case .champion: return "trophy.fill"
        case .won: return "crown.fill"
        case .success: return "checkmark"
        }
    }

    /// The outcome's colour: the glow behind the result, its badge and the panel's top edge.
    private var accent: Color {
        switch info.outcome {
        case .failed, .lost: return Color(red: 0.96, green: 0.30, blue: 0.32)
        case .draw: return Color(red: 0.36, green: 0.62, blue: 1.0)
        case .champion: return Palette.gold
        case .success, .won: return Color(red: 0.27, green: 0.90, blue: 0.56)
        }
    }

    private var headline: String {
        info.headline ?? (failed ? Strings.notParkedTitle : (isFinal ? Strings.allDone : Strings.parkedTitle))
    }

    private var hasReward: Bool {
        guard let reward = info.reward else { return false }
        return reward.total > 0 || !reward.tasksDone.isEmpty
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // The frozen game stays in view, only dimmed: the card is the one thing to read
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .opacity(appeared ? 1 : 0)
                card
                    .frame(width: min(480, geo.size.width - 48))
                    .scaleEffect(panelIn ? 1 : 0.94)
                    .opacity(panelIn ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: info.id) { await animateIn() }
    }

    // MARK: Card

    /// One compact glass card: the level and the stars on a line, the result, the figures and
    /// the coins in one row, then the buttons.
    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: badgeIcon)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(accent))
                Text(info.levelTitle)
                    .font(.ui(12, .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 8)
                medal
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(headline.uppercased())
                    .font(.race(36))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if info.newBest {
                    Text(Strings.newBest)
                        .font(.ui(10, .heavy))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(Capsule().fill(Palette.gold))
                }
            }
            .padding(.top, 4)
            .scaleEffect(titleIn ? 1 : 1.06, anchor: .leading)
            .opacity(titleIn ? 1 : 0)
            if let roundLine = info.roundLine {
                Text(roundLine)
                    .font(.ui(12, .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            divider.padding(.top, 12)
            board.padding(.vertical, 12)
            divider
            footer.padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.05, green: 0.06, blue: 0.09).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        // The outcome's colour as a thin line along the top
        .overlay(alignment: .top) {
            Capsule()
                .fill(accent)
                .frame(width: 64, height: 3)
                .offset(y: -1.5)
        }
        .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }

    /// Next to the level: the stars (alone) or the match score (head to head).
    @ViewBuilder
    private var medal: some View {
        if let scoreLine = info.scoreLine {
            Text(scoreLine)
                .font(.race(17))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(accent.opacity(0.22)))
                .overlay(Capsule().strokeBorder(accent.opacity(0.7), lineWidth: 1))
        } else if !headToHead && !failed {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { starView($0) }
            }
        }
    }

    private func starView(_ index: Int) -> some View {
        let lit = index < shownStars
        return Image(systemName: "star.fill")
            .font(.system(size: 17, weight: .black))
            .foregroundStyle(lit ? Palette.gold : Color.white.opacity(0.14))
            .shadow(color: lit ? Palette.gold.opacity(0.6) : .clear, radius: 5)
            .scaleEffect(lit ? 1 : 0.8)
            .animation(.spring(response: 0.35, dampingFraction: 0.45), value: lit)
    }

    // MARK: Figures

    /// Head to head: the two players as timing rows. Alone: time, crashes, score or best, and the
    /// coins, side by side.
    @ViewBuilder
    private var board: some View {
        if headToHead {
            VStack(spacing: 6) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, entry in
                    timingRow(entry, position: index + 1, leader: ranked.first?.time)
                }
                if hasReward, let reward = info.reward {
                    coins(reward).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        } else if let me = info.me {
            HStack(alignment: .top, spacing: 0) {
                figure(Strings.timeLabel, value: me.time.map { String(format: "%.1f", $0) } ?? "–", unit: me.time == nil ? "" : "s")
                figure(Strings.bumpsLabel, value: "\(me.hits)", unit: "",
                       tint: me.hits == 0 ? Color(red: 0.45, green: 0.95, blue: 0.6) : .white)
                if let score = me.score {
                    figure(Strings.scoreLabel, value: score >= 0 ? String(format: "%.1f", score) : "–", unit: "")
                } else if let best = info.bestTime {
                    figure(Strings.bestLabel, value: String(format: "%.1f", best), unit: "s", tint: .white.opacity(0.7))
                }
                if hasReward, let reward = info.reward {
                    coins(reward)
                }
            }
        }
    }

    /// A figure: a small caption over a number.
    private func figure(_ label: String, value: String, unit: String, tint: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.ui(10, .bold))
                .foregroundStyle(.white.opacity(0.45))
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.race(28))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.race(14))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The coins: the total counting up, what made it in one small line under it.
    private func coins(_ reward: RunReward) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 5) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.gold)
                Text("+\(shownCoins)")
                    .font(.race(28))
                    .monospacedDigit()
                    .foregroundStyle(Palette.gold)
                    .contentTransition(.numericText())
            }
            if !reward.lines.isEmpty {
                Text(reward.lines.map { "\($0.label) +\($0.coins)" }.joined(separator: " · "))
                    .font(.ui(10, .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ForEach(reward.tasksDone.indices, id: \.self) { index in
                taskTag(reward.tasksDone[index].coins)
            }
        }
        .frame(maxWidth: 170, alignment: .trailing)
    }

    /// Players in finishing order (finished first, by time).
    private var ranked: [ResultEntry] {
        info.entries.sorted { a, b in
            switch (a.time, b.time) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.isMe
            }
        }
    }

    private func gapText(_ entry: ResultEntry, leader: Double?) -> String {
        guard let time = entry.time, let leader = leader, time - leader >= 0.05 else { return "" }
        return String(format: "+%.1f", time - leader)
    }

    private func timingRow(_ entry: ResultEntry, position: Int, leader: Double?) -> some View {
        let finished = entry.time != nil
        return HStack(spacing: 0) {
            Text("P\(position)")
                .font(.race(17))
                .foregroundStyle(entry.isWinner ? Palette.ink : Color.white)
                .frame(width: 36, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(entry.isWinner ? Palette.gold : Palette.player(entry.slot)))
            Text(entry.name)
                .font(.ui(15, .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.leading, 10)
            if entry.isWinner {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Palette.gold)
                    .padding(.leading, 6)
            }
            Spacer(minLength: 6)
            Text(finished ? String(format: "%.1f", entry.time ?? 0) : Strings.didNotFinish)
                .font(finished ? .race(21) : .ui(11, .bold))
                .monospacedDigit()
                .foregroundStyle(finished ? Color.white : Color.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 64, alignment: .trailing)
            Text(gapText(entry, leader: leader))
                .font(.ui(13, .bold))
                .monospacedDigit()
                .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.3))
                .frame(width: 52, alignment: .trailing)
            Text("\(entry.hits)")
                .font(.ui(15, .heavy))
                .monospacedDigit()
                .foregroundStyle(entry.hits == 0 ? Color(red: 0.45, green: 0.95, blue: 0.6) : Color.white.opacity(0.8))
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(entry.isMe ? 0.1 : 0.05)))
    }

    private func taskTag(_ coins: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "gift.fill").font(.system(size: 10, weight: .black))
            Text("\(Strings.taskReadyTag) +\(coins)")
                .font(.ui(10, .heavy))
                .lineLimit(1)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 9)
        .frame(height: 20)
        .background(Capsule().fill(Palette.gold))
    }

    // MARK: Buttons

    /// Labelled buttons; the way forward is the wide, coloured one.
    @ViewBuilder
    private var footer: some View {
        switch info.footer {
        case .autoNext:
            VStack(spacing: 7) {
                Text(Strings.nextLevelSoon)
                    .font(.ui(13, .bold))
                    .foregroundStyle(.white.opacity(0.75))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule().fill(accent).frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 60)
            }
        case .final:
            Button { model.leaveToMenu() } label: {
                Label(Strings.backToMenu, systemImage: "house.fill")
            }
            .buttonStyle(ResultButtonStyle(fill: Palette.gold))
        case .solo(let hasNext):
            HStack(spacing: 10) {
                Button { model.leaveToMenu() } label: { Label(Strings.menu, systemImage: "house.fill") }
                    .buttonStyle(ResultButtonStyle())
                if failed {
                    if nextOpen {
                        Button { model.nextLevel() } label: { Label(Strings.next, systemImage: "forward.end.fill") }
                            .buttonStyle(ResultButtonStyle())
                    }
                    Button { model.retryLevel() } label: { Label(Strings.tryAgain, systemImage: "arrow.counterclockwise") }
                        .buttonStyle(ResultButtonStyle(fill: Color(red: 1, green: 0.56, blue: 0.22)))
                } else {
                    Button { model.retryLevel() } label: { Label(Strings.retry, systemImage: "arrow.counterclockwise") }
                        .buttonStyle(ResultButtonStyle(fill: hasNext ? nil : Palette.gold))
                    if hasNext {
                        Button { model.nextLevel() } label: {
                            HStack(spacing: 8) {
                                Text(Strings.next)
                                Image(systemName: "chevron.right")
                            }
                        }
                        .buttonStyle(ResultButtonStyle(fill: Palette.gold))
                    }
                }
            }
        }
    }

    // MARK: Animation

    private func animateIn() async {
        // One sequence: the shade and the result, then the panel and the buttons, the stars one
        // by one, then the coins counting up
        withAnimation(.easeOut(duration: 0.25)) { appeared = true }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72).delay(0.05)) { titleIn = true }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86).delay(0.22)) { panelIn = true }
        if case .autoNext(let seconds) = info.footer {
            withAnimation(.linear(duration: seconds)) { progress = 1 }
        }
        let stars = failed || headToHead ? 0 : (info.me?.stars ?? 0)
        try? await Task.sleep(nanoseconds: 380_000_000)
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        for index in 0..<stars {
            if Task.isCancelled { return }
            shownStars = index + 1
            haptic.impactOccurred(intensity: 0.6 + 0.2 * CGFloat(index))
            AudioManager.shared.play("beep", volume: 0.35 + 0.15 * Float(index))
            try? await Task.sleep(nanoseconds: 240_000_000)
        }
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

/// Results buttons: a coloured one for the way forward (wide), dark glass for the rest; each has
/// its icon and its name.
struct ResultButtonStyle: ButtonStyle {
    var fill: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let primary = fill != nil
        return configuration.label
            .font(primary ? .race(18) : .ui(14, .bold))
            .labelStyle(ResultLabelStyle())
            .foregroundStyle(primary ? Palette.ink : Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 14)
            .frame(maxWidth: primary ? .infinity : nil)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(primary ? AnyShapeStyle(LinearGradient(colors: [fill!.opacity(1), fill!.opacity(0.86)], startPoint: .top, endPoint: .bottom))
                                  : AnyShapeStyle(Color.white.opacity(0.1)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.white.opacity(primary ? 0.35 : 0.14), lineWidth: 1)
            )
            .shadow(color: primary ? fill!.opacity(0.3) : .clear, radius: configuration.isPressed ? 2 : 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Icon and title side by side, a little apart.
struct ResultLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
            configuration.title
        }
    }
}

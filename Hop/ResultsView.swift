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

    /// The accent of the outcome (band, winner marks, primary button).
    private var accent: Color {
        switch info.outcome {
        case .failed, .lost: return Color(red: 0.94, green: 0.27, blue: 0.30)
        case .draw: return Color(red: 0.29, green: 0.55, blue: 1.0)
        case .champion: return Palette.gold
        case .success, .won: return Color(red: 0.23, green: 0.88, blue: 0.53)
        }
    }

    private var headline: String {
        info.headline ?? (failed ? Strings.notParkedTitle : (isFinal ? Strings.allDone : Strings.parkedTitle))
    }

    @State private var bandIn = false
    @State private var rowsIn = false
    @State private var sheen: CGFloat = -0.3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // The frozen frame shows through faintly (the HUD under it must not compete), a
                // little more on the right
                LinearGradient(colors: [Color.black.opacity(0.88), Color.black.opacity(0.74), Color.black.opacity(0.6)],
                               startPoint: .leading, endPoint: .trailing)
                    .ignoresSafeArea()
                    .opacity(appeared ? 1 : 0)

                VStack(alignment: .leading, spacing: 14) {
                    band(width: geo.size.width)
                    HStack(alignment: .top, spacing: 18) {
                        board
                            .frame(width: min(400, geo.size.width * 0.5), alignment: .leading)
                        VStack(alignment: .leading, spacing: 12) {
                            if let reward = info.reward, reward.total > 0 || !reward.tasksDone.isEmpty {
                                rewardBoard(reward)
                            }
                            footer
                        }
                        .frame(maxWidth: 320, alignment: .leading)
                        .opacity(rowsIn ? 1 : 0)
                        .offset(x: rowsIn ? 0 : 24)
                    }
                    .padding(.leading, 6)
                }
                .padding(.leading, max(24, geo.safeAreaInsets.leading + 8))
                .padding(.trailing, max(24, geo.safeAreaInsets.trailing + 8))
                // Sits a little above the middle of the screen
                .frame(maxHeight: .infinity, alignment: .center)
                .offset(y: -geo.size.height * 0.04)
            }
        }
        .task(id: info.id) { await animateIn() }
    }

    // MARK: The band

    /// The outcome on a livery band that sweeps in across the screen: a broad stripe in the
    /// outcome's colour with a thin echo stripe under it, the result in big italic type, the
    /// level above the band and, at its right end, the match score or the stars.
    private func band(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: badgeIcon)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(accent)
                Text(info.levelTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                if info.newBest {
                    Text(Strings.newBest)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 8).frame(height: 18)
                        .background(SlantedShape(skew: 5).fill(Palette.gold))
                }
            }
            .padding(.leading, 18)
            .opacity(bandIn ? 1 : 0)
            ZStack(alignment: .leading) {
                // Echo stripe
                SlantedShape(skew: 30)
                    .fill(accent.opacity(0.35))
                    .frame(height: 8)
                    .offset(x: 26, y: 50)
                // The band, with a light sweep across it as it lands
                SlantedShape(skew: 30)
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.78)], startPoint: .leading, endPoint: .trailing))
                    .overlay(
                        LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 120)
                            .offset(x: sheen * width)
                            .blendMode(.plusLighter)
                            .mask(SlantedShape(skew: 30))
                    )
                    .frame(height: 74)
                    .shadow(color: accent.opacity(0.45), radius: 18, y: 6)
                HStack(alignment: .center, spacing: 14) {
                    Text(headline.uppercased())
                        .font(.race(54))
                        .foregroundStyle(onAccent)
                        .shadow(color: .black.opacity(info.outcome == .champion ? 0 : 0.25), radius: 0, x: 2, y: 2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .offset(x: bandIn ? 0 : -40)
                    Spacer(minLength: 8)
                    bandTrailing
                }
                .padding(.leading, 30)
                .padding(.trailing, 40)
            }
            .frame(width: min(width * 0.86, 760), height: 74, alignment: .leading)
            .mask(Rectangle().scaleEffect(x: bandIn ? 1 : 0.001, anchor: .leading))
            if let roundLine = info.roundLine {
                Text(roundLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.leading, 22)
                    .padding(.top, 6)
                    .opacity(bandIn ? 1 : 0)
            }
        }
    }

    /// Text on the band: dark on gold, white on the other colours.
    private var onAccent: Color { info.outcome == .champion ? Palette.ink : .white }

    /// Right end of the band: the match score head to head, the stars alone.
    @ViewBuilder
    private var bandTrailing: some View {
        if let scoreLine = info.scoreLine {
            Text(scoreLine)
                .font(.race(40))
                .monospacedDigit()
                .foregroundStyle(onAccent)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(SlantedShape(skew: 10).fill(Color.black.opacity(0.28)))
        } else if !headToHead {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    starView(index)
                }
            }
        }
    }

    private func starView(_ index: Int) -> some View {
        let lit = index < shownStars
        return Image(systemName: "star.fill")
            .font(.system(size: index == 1 ? 34 : 28, weight: .black))
            .foregroundStyle(lit ? Color.white : Color.black.opacity(0.28))
            .shadow(color: lit ? Color.white.opacity(0.7) : Color.clear, radius: 6)
            .scaleEffect(lit ? 1 : 0.82)
            .offset(y: index == 1 ? -3 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.45), value: lit)
    }

    // MARK: The board under the band

    /// Head to head: a timing tower (position, player, time, gap, crashes), the winner on top.
    /// Alone: the round's numbers as large figures with the best time beside them.
    @ViewBuilder
    private var board: some View {
        if headToHead {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer()
                    Text(Strings.timeLabel).frame(width: 72, alignment: .trailing)
                    Text(Strings.gapLabel).frame(width: 58, alignment: .trailing)
                    Image(systemName: "car.side.rear.and.collision.and.car.side.front").frame(width: 40, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.trailing, 12)
                .padding(.bottom, 5)
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, entry in
                    timingRow(entry, position: index + 1, leader: ranked.first?.time)
                        .opacity(rowsIn ? 1 : 0)
                        .offset(x: rowsIn ? 0 : -30)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.08), value: rowsIn)
                }
            }
        } else if let me = info.me {
            soloFigures(me)
                .padding(.leading, 14)
                .opacity(rowsIn ? 1 : 0)
                .offset(y: rowsIn ? 0 : 12)
        }
    }

    private func soloFigures(_ me: ResultEntry) -> some View {
        HStack(alignment: .bottom, spacing: 22) {
            figure(Strings.timeLabel, value: me.time.map { String(format: "%.1f", $0) } ?? "–", unit: me.time == nil ? "" : "s", big: true)
            figure(Strings.bumpsLabel, value: "\(me.hits)", unit: "", big: false,
                   tint: me.hits == 0 ? Color(red: 0.45, green: 0.95, blue: 0.6) : .white)
            if let score = me.score {
                figure(Strings.scoreLabel, value: score >= 0 ? String(format: "%.1f", score) : "–", unit: "", big: false)
            } else if let best = info.bestTime {
                figure(Strings.bestLabel, value: String(format: "%.1f", best), unit: "s", big: false, tint: .white.opacity(0.75))
            }
        }
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
        let blockFill: Color = entry.isWinner ? Palette.gold : Palette.player(entry.slot)
        let rowFill: Color = Color.white.opacity(entry.isMe ? 0.12 : 0.06)
        return HStack(spacing: 0) {
            // Position block in the player's colour (gold for the winner)
            Text("P\(position)")
                .font(.race(20))
                .foregroundStyle(entry.isWinner ? Palette.ink : Color.white)
                .frame(width: 48, height: 44)
                .background(SlantedShape(skew: 8).fill(blockFill))
            Text(entry.name)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.leading, 12)
            if entry.isWinner {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Palette.gold)
                    .padding(.leading, 6)
            }
            Spacer(minLength: 6)
            Text(finished ? String(format: "%.1f", entry.time ?? 0) : Strings.didNotFinish)
                .font(finished ? .race(22) : .system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(finished ? Color.white : Color.white.opacity(0.5))
                .frame(width: 72, alignment: .trailing)
            Text(gapText(entry, leader: leader))
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.3))
                .frame(width: 58, alignment: .trailing)
            Text("\(entry.hits)")
                .font(.system(size: 15, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(entry.hits == 0 ? Color(red: 0.45, green: 0.95, blue: 0.6) : Color.white.opacity(0.8))
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.trailing, 12)
        .frame(height: 44)
        .background(SlantedShape(skew: 8).fill(rowFill))
        .padding(.bottom, 4)
    }

    /// A big number with a small caption: the round's figures alone.
    private func figure(_ label: String, value: String, unit: String, big: Bool, tint: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.race(big ? 60 : 36))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.race(big ? 24 : 18))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    // MARK: Reward board

    /// The coins: the total counts up big, what made it in small lines, waiting task rewards as
    /// gold tags.
    private func rewardBoard(_ reward: RunReward) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Palette.gold)
                Text("+\(shownCoins)")
                    .font(.race(34))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            if !reward.lines.isEmpty {
                Text(reward.lines.map { "\($0.label) +\($0.coins)" }.joined(separator: "   "))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(reward.tasksDone.indices, id: \.self) { index in
                taskTag(reward.tasksDone[index].coins)
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SlantedShape(skew: 10).fill(Color.white.opacity(0.07)))
        .overlay(alignment: .leading) {
            SlantedShape(skew: 3).fill(Palette.gold).frame(width: 6).padding(.vertical, 1)
        }
    }

    private func taskTag(_ coins: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "gift.fill").font(.system(size: 10, weight: .black))
            Text("\(Strings.taskReadyTag) +\(coins)")
                .font(.system(size: 10, weight: .heavy))
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 8).frame(height: 20)
        .background(SlantedShape(skew: 5).fill(Palette.gold))
    }

    @ViewBuilder
    private var footer: some View {
        if failed, info.entries.count == 1, !isAutoNext {
            // Did not park: trying again is the way forward (the next level only if already open)
            HStack(spacing: 8) {
                Button { model.leaveToMenu() } label: { Image(systemName: "house.fill") }
                    .buttonStyle(PlateButtonStyle(glass: true))
                Button { model.retryLevel() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text(Strings.tryAgain)
                    }
                }
                .buttonStyle(PlateButtonStyle(fill: Color(red: 1, green: 0.55, blue: 0.2)))
                if !isFinal && nextOpen {
                    Button { model.nextLevel() } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(PlateButtonStyle(glass: true))
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
                    .buttonStyle(PlateButtonStyle(glass: true))
                Button { model.retryLevel() } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(PlateButtonStyle(glass: true))
                if hasNext {
                    Button { model.nextLevel() } label: {
                        HStack(spacing: 6) {
                            Text(Strings.next)
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(PlateButtonStyle())
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
                            .fill(accent)
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
                .buttonStyle(PlateButtonStyle())
            }
        }
    }

    private func format(_ time: Double?) -> String {
        guard let time = time else { return "–" }
        return String(format: "%.1f s", time)
    }

    // MARK: Animation

    private func animateIn() async {
        // One sequence: the shade, the band wiping in with its sheen, then the board and rewards
        withAnimation(.easeOut(duration: 0.25)) { appeared = true }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { bandIn = true }
        withAnimation(.easeInOut(duration: 0.9).delay(0.3)) { sheen = 1.2 }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.2)) { rowsIn = true }
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

/// A slanted racing plate button: solid for the main action, dark glass for the others.
struct PlateButtonStyle: ButtonStyle {
    var fill: Color = Palette.gold
    var text: Color = Palette.ink
    var height: CGFloat = 46
    var glass = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.race(19))
            .foregroundStyle(glass ? Color.white : text)
            .padding(.horizontal, 16)
            .frame(maxWidth: glass ? nil : .infinity)
            .frame(minWidth: glass ? 52 : nil)
            .frame(height: height)
            .background(SlantedShape(skew: 10).fill(glass ? AnyShapeStyle(Color.white.opacity(0.1)) : AnyShapeStyle(fill)))
            .overlay(SlantedShape(skew: 10).strokeBorderCompat(Color.white.opacity(glass ? 0.18 : 0.4), lineWidth: 1))
            .shadow(color: glass ? .clear : fill.opacity(0.4), radius: configuration.isPressed ? 3 : 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

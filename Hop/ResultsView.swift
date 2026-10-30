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

    @State private var printed = false
    @State private var stamped = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .opacity(appeared ? 1 : 0)
                HStack(alignment: .bottom, spacing: 22) {
                    printer(maxHeight: geo.size.height - 8)
                    keys
                        .frame(width: 196)
                        .padding(.bottom, 14)
                        .opacity(panelIn ? 1 : 0)
                        .offset(x: panelIn ? 0 : 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .task(id: info.id) { await animateIn() }
    }

    // MARK: The receipt

    /// The result printed on a thermal receipt that comes out of a slot at the top of the screen,
    /// like the parking ticket: the level, the stars (or the match score), the figures with dotted
    /// leaders, the coins line by line and their total, a barcode, and the result stamped across it.
    private func printer(maxHeight: CGFloat) -> some View {
        ZStack(alignment: .top) {
            receipt
                .frame(width: 262)
                .mask(alignment: .top) {
                    Rectangle().frame(height: printed ? 1200 : 0)
                }
                .offset(y: printed ? 6 : -10)
                .overlay(alignment: .center) { stamp }
            // The slot it comes out of
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                .fill(Color(red: 0.05, green: 0.055, blue: 0.065))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.black).frame(height: 3).padding(.horizontal, 12)
                }
                .frame(width: 300, height: 14)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
        }
        .frame(maxHeight: maxHeight, alignment: .top)
    }

    private let ink = Color(red: 0.12, green: 0.12, blue: 0.13)
    private let paper = Color(red: 0.965, green: 0.958, blue: 0.935)

    private func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    private var receipt: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PARKRIFT · " + Strings.resultSlip)
                .font(mono(9, .medium))
                .tracking(1.6)
                .foregroundStyle(ink.opacity(0.55))
                .frame(maxWidth: .infinity)
            Text(Strings.upper(info.levelTitle))
                .font(mono(11, .bold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.top, 3)
            topMark
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            if let roundLine = info.roundLine {
                Text(roundLine)
                    .font(mono(10))
                    .foregroundStyle(ink.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 3)
            }
            dashes
            lines
            if hasReward, let reward = info.reward {
                dashes
                ForEach(Array(reward.lines.prefix(4).enumerated()), id: \.offset) { _, line in
                    leader(line.label, "+\(line.coins)", weight: .regular)
                }
                ForEach(reward.tasksDone.indices, id: \.self) { index in
                    leader(Strings.taskReadyTag, "+\(reward.tasksDone[index].coins)", weight: .bold)
                }
                dashes
                HStack(alignment: .firstTextBaseline) {
                    Text(Strings.totalLabel)
                        .font(mono(12, .bold))
                    Spacer()
                    Text("+\(shownCoins)")
                        .font(.custom("BarlowCondensed-Black", fixedSize: 30))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(red: 0.8, green: 0.6, blue: 0.08))
                }
                .foregroundStyle(ink)
            }
            barcode
                .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .background(paper)
        .mask(TornEdge())
        .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
    }

    /// Under the level: the stars (alone and parked) or the match score (head to head).
    @ViewBuilder
    private var topMark: some View {
        if let scoreLine = info.scoreLine {
            Text(Strings.upper(scoreLine))
                .font(.custom("BarlowCondensed-Black", fixedSize: 22))
                .foregroundStyle(ink)
        } else if !headToHead && !failed {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: index < shownStars ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ink.opacity(index < shownStars ? 1 : 0.3))
                        .scaleEffect(index < shownStars ? 1 : 0.85)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: shownStars)
                }
            }
        }
    }

    /// The figures: the players head to head, or time, crashes and score (or best) alone.
    @ViewBuilder
    private var lines: some View {
        if headToHead {
            ForEach(Array(ranked.enumerated()), id: \.element.id) { index, entry in
                let value = entry.time.map { String(format: "%.1f s", $0) } ?? Strings.didNotFinish
                leader("P\(index + 1) " + Strings.upper(entry.name) + (entry.isWinner ? " ♛" : ""),
                       value + " · \(entry.hits)", weight: entry.isMe ? .bold : .regular)
            }
        } else if let me = info.me {
            leader(Strings.upper(Strings.timeLabel), me.time.map { String(format: "%.1f s", $0) } ?? "–", weight: .bold)
            leader(Strings.upper(Strings.bumpsLabel), "\(me.hits)", weight: .bold)
            if let score = me.score {
                leader(Strings.upper(Strings.scoreLabel), score >= 0 ? String(format: "%.1f", score) : "–", weight: .bold)
            } else if let best = info.bestTime {
                leader(Strings.upper(Strings.bestLabel), String(format: "%.1f s", best), weight: .regular)
            }
            if info.newBest {
                Text("★ " + Strings.upper(Strings.newBest))
                    .font(mono(11, .heavy))
                    .foregroundStyle(Color(red: 0.78, green: 0.16, blue: 0.18))
                    .padding(.top, 3)
            }
        }
    }

    /// A printed line: the label, a dotted leader, the value.
    private func leader(_ label: String, _ value: String, weight: Font.Weight) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(label)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
            Line()
                .stroke(ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                .frame(height: 1)
                .offset(y: -3)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .layoutPriority(2)
        }
        .font(mono(12, weight))
        .foregroundStyle(ink)
        .frame(height: 21)
    }

    private var dashes: some View {
        Line()
            .stroke(ink.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(height: 1)
            .padding(.vertical, 7)
    }

    /// A barcode (bars of a few widths, the same for the same level).
    private var barcode: some View {
        Canvas { context, size in
            var rng = SplitMix64(seed: UInt64(info.levelIndex &+ 7))
            var x: CGFloat = 0
            while x < size.width {
                let w = CGFloat(rng.int(3) + 1)
                context.fill(Path(CGRect(x: x, y: 0, width: w, height: size.height)), with: .color(ink))
                x += w + CGFloat(rng.int(3) + 1)
            }
        }
        .frame(height: 24)
    }

    /// The result, stamped across the receipt in ink of the outcome's colour.
    private var stamp: some View {
        Text(Strings.upper(headline.replacingOccurrences(of: "!", with: "")))
            .font(.custom("BarlowCondensed-Black", fixedSize: 30))
            .tracking(0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(stampInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(stampInk, lineWidth: 3))
            .frame(maxWidth: 220)
            .opacity(stamped ? 0.88 : 0)
            .scaleEffect(stamped ? 1 : 1.8)
            .rotationEffect(.degrees(-13))
            .blendMode(.multiply)
            .offset(x: 6, y: -18)
    }

    private var stampInk: Color {
        switch info.outcome {
        case .failed, .lost: return Color(red: 0.8, green: 0.15, blue: 0.16)
        case .draw: return Color(red: 0.16, green: 0.38, blue: 0.82)
        case .champion: return Color(red: 0.78, green: 0.52, blue: 0.0)
        case .success, .won: return Color(red: 0.07, green: 0.58, blue: 0.3)
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

    // MARK: Keys

    /// Beside the receipt: the way forward on top, big; the menu and retry under it.
    @ViewBuilder
    private var keys: some View {
        switch info.footer {
        case .autoNext:
            VStack(alignment: .leading, spacing: 8) {
                Text(Strings.nextLevelSoon)
                    .font(.ui(13, .bold))
                    .foregroundStyle(.white.opacity(0.8))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Palette.gold).frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 6)
            }
        case .final:
            Button { model.leaveToMenu() } label: { Text(Strings.upper(Strings.backToMenu)) }
                .buttonStyle(KeyButtonStyle(primary: Palette.gold))
        case .solo(let hasNext):
            VStack(spacing: 9) {
                if failed {
                    Button { model.retryLevel() } label: { Text(Strings.upper(Strings.tryAgain)) }
                        .buttonStyle(KeyButtonStyle(primary: Color(red: 1, green: 0.56, blue: 0.22)))
                    HStack(spacing: 9) {
                        Button { model.leaveToMenu() } label: { Text(Strings.menu) }
                            .buttonStyle(KeyButtonStyle())
                        if nextOpen {
                            Button { model.nextLevel() } label: { Text(Strings.next) }
                                .buttonStyle(KeyButtonStyle())
                        }
                    }
                } else {
                    if hasNext {
                        Button { model.nextLevel() } label: { Text(Strings.upper(Strings.next) + "  ›") }
                            .buttonStyle(KeyButtonStyle(primary: Palette.gold))
                    }
                    HStack(spacing: 9) {
                        Button { model.leaveToMenu() } label: { Text(Strings.menu) }
                            .buttonStyle(KeyButtonStyle())
                        Button { model.retryLevel() } label: { Text(Strings.retry) }
                            .buttonStyle(KeyButtonStyle(primary: hasNext ? nil : Palette.gold))
                    }
                }
            }
        }
    }

    // MARK: Animation

    private func animateIn() async {
        // The shade, the receipt printing out of the slot, the stamp coming down on it, the stars
        // one by one, then the coins counting up to the total
        withAnimation(.easeOut(duration: 0.2)) { appeared = true }
        withAnimation(.easeOut(duration: 0.75)) { printed = true }
        withAnimation(.easeOut(duration: 0.3).delay(0.5)) { panelIn = true }
        if case .autoNext(let seconds) = info.footer {
            withAnimation(.linear(duration: seconds)) { progress = 1 }
        }
        for _ in 0..<5 {
            AudioManager.shared.play("click", volume: 0.18)
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        if Task.isCancelled { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { stamped = true }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        AudioManager.shared.play("bump", volume: 0.5)
        try? await Task.sleep(nanoseconds: 250_000_000)
        let stars = failed || headToHead ? 0 : (info.me?.stars ?? 0)
        let haptic = UIImpactFeedbackGenerator(style: .light)
        for index in 0..<stars {
            if Task.isCancelled { return }
            shownStars = index + 1
            haptic.impactOccurred()
            AudioManager.shared.play("beep", volume: 0.3 + 0.12 * Float(index))
            try? await Task.sleep(nanoseconds: 200_000_000)
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

/// A physical key beside the receipt: chunky, with a darker lip under it that it presses into.
struct KeyButtonStyle: ButtonStyle {
    var primary: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let fill = primary ?? Color(red: 0.09, green: 0.1, blue: 0.12)
        let lip = primary.map { $0.opacity(0.55) } ?? Color.black
        let pressed = configuration.isPressed
        return configuration.label
            .font(primary != nil ? .race(21) : .ui(15, .heavy))
            .foregroundStyle(primary != nil ? Palette.ink : Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(height: primary != nil ? 48 : 42)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(lip)
                    .offset(y: 4)
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(primary != nil ? 0.3 : 0.1), lineWidth: 1))
            )
            .offset(y: pressed ? 3 : 0)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// A straight line across (for the dotted leaders and the dashed rules).
struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}

/// The receipt's outline: straight top and sides, a torn zigzag along the bottom.
struct TornEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tooth: CGFloat = 7, depth: CGFloat = 5
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - depth))
        var x = rect.maxX
        var down = true
        while x > 0 {
            x = max(0, x - tooth / 2)
            path.addLine(to: CGPoint(x: x, y: down ? rect.maxY : rect.maxY - depth))
            down.toggle()
        }
        path.addLine(to: CGPoint(x: 0, y: rect.maxY - depth))
        path.closeSubpath()
        return path
    }
}

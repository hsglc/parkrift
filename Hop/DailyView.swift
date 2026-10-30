import SwiftUI

/// The daily screen: a gift card (today's reward up front, the seven-day streak as a timeline
/// and the collect button) beside today's tasks, one tab per game mode, each task with a
/// progress ring and its reward. Resets at midnight, shown as a countdown in the header.
struct DailyView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var justCollected: Int?
    @State private var shown = false
    @State private var mode: Progression.TaskMode?
    @State private var pulse = false
    /// Tasks whose coins were just collected (for the burst and the "collected" state).
    @State private var collecting: Set<Int> = []
    @State private var bursts: [CoinBurst] = []

    private let green = Color(red: 0.35, green: 0.95, blue: 0.55)

    private func accent(_ mode: Progression.TaskMode) -> Color {
        switch mode {
        case .park: return Neo.cyan
        case .city: return Palette.gold
        case .race: return Neo.magenta
        case .online: return green
        }
    }

    var body: some View {
        ZStack {
            Neo.ink.ignoresSafeArea()
            // The art as an overlay on a clear view: an image filling the screen on its own sizes
            // the ZStack to the image (taller than the screen in landscape), which pushed the
            // header off the top and the cards off the bottom. Pre-blurred, no live blur.
            Color.clear
                .overlay {
                    if let art = UIImage(named: "splash_blur.jpg") ?? UIImage(named: "splash.jpg") {
                        Image(uiImage: art)
                            .resizable()
                            .scaledToFill()
                            .opacity(0.3)
                    }
                }
                .clipped()
                .ignoresSafeArea()
                .allowsHitTesting(false)
            LinearGradient(colors: [Neo.ink.opacity(0.94), Neo.ink.opacity(0.72)], startPoint: .leading, endPoint: .trailing)
                .ignoresSafeArea()
            // A soft colour bloom behind the gift
            RadialGradient(colors: [Palette.gold.opacity(0.16), .clear], center: .init(x: 0.22, y: 0.55), startRadius: 10, endRadius: 360)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Laid out from the space actually there (inside the safe area): the cards get the
            // height left under the header, so nothing ever pushes the title off the top
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 8) {
                    header
                        .frame(height: 40)
                    HStack(alignment: .top, spacing: 14) {
                        giftCard
                            .frame(width: min(300, proxy.size.width * 0.38))
                            .rise(shown, delay: 0.02)
                        tasksColumn
                            .rise(shown, delay: 0.1)
                    }
                    .frame(height: max(200, proxy.size.height - 48))
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)
        }
        .onAppear {
            shown = true
            // Start the pulses once the sheet has settled (a repeating animation started during
            // the slide-in would keep replaying the slide)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { pulse = true }
            if mode == nil {
                // Opens on rewards waiting to be collected, else on the first mode with work left
                let tasks = Progression.tasks
                mode = Progression.TaskMode.allCases.first { m in tasks.contains { $0.kind.mode == m && $0.claimable } }
                    ?? Progression.TaskMode.allCases.first { m in tasks.contains { $0.kind.mode == m && !$0.done } } ?? .park
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(Strings.dailyTitle.localUpper).font(.race(26)).foregroundStyle(.white)
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 12, weight: .bold))
                    Text(Strings.resetsIn(Self.untilMidnight(from: context.date)))
                        .font(.ui(12, .bold)).monospacedDigit()
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 12).frame(height: 32)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            }
            let waiting = Progression.claimableTasks
            if waiting.count >= 2 {
                Button { collectAll(waiting) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 12, weight: .black))
                        Text(Strings.collectAll).font(.ui(13, .heavy))
                        Text("+\(waiting.reduce(0) { $0 + $1.kind.reward })").font(.race(14))
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(Capsule().fill(Palette.gold))
                    .shadow(color: Palette.gold.opacity(pulse ? 0.6 : 0.2), radius: pulse ? 12 : 4)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
            CoinPill(coins: model.coins)
            NeoIconButton(systemImage: "xmark") { dismiss() }
        }
    }

    private static func untilMidnight(from now: Date) -> String {
        let calendar = Calendar.current
        let next = calendar.startOfDay(for: now).addingTimeInterval(86_400)
        let left = max(0, Int(next.timeIntervalSince(now)))
        return String(format: "%02d:%02d:%02d", left / 3600, left / 60 % 60, left % 60)
    }

    // MARK: Gift

    private var giftCard: some View {
        let pending = Progression.pendingGiftDay
        let collected = Progression.streakCollected
        let shownDay = pending ?? min(7, collected + 1)
        let reward = Progression.streakRewards[max(0, min(6, shownDay - 1))]
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Strings.dailyGift.localUpper).font(.kicker(10)).tracking(1.6).foregroundStyle(Palette.gold)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").foregroundStyle(Palette.goldDeep)
                    Text(Strings.streakDays(pending.map { $0 - 1 } ?? collected))
                }
                .font(.ui(12, .heavy))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10).frame(height: 24)
                .background(Capsule().fill(Palette.goldDeep.opacity(0.16)))
            }
            // Today's reward, big
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Palette.gold.opacity(pending != nil ? 0.55 : 0.18), .clear],
                                             center: .center, startRadius: 2, endRadius: 46))
                        .frame(width: 66, height: 66)
                        .scaleEffect(pending != nil && pulse ? 1.08 : 0.96)
                        .animation(pending != nil ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: pulse)
                    Circle()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().strokeBorder(Palette.gold.opacity(0.5), lineWidth: 1.5))
                        .frame(width: 50, height: 50)
                    Image(systemName: pending == nil ? "checkmark" : (shownDay == 7 ? "gift.fill" : "dollarsign"))
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(pending == nil ? green : Palette.gold)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.dayN(shownDay).localUpper)
                        .font(.kicker(9)).tracking(1.4).foregroundStyle(.white.opacity(0.55))
                    Text("+\(justCollected ?? reward)")
                        .font(.race(32)).foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(Strings.dailyGiftHint)
                        .font(.ui(10, .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 8)

            streakTimeline(pending: pending, collected: collected)
                .padding(.top, 8)

            Spacer(minLength: 8)
            if let day = pending {
                Button {
                    let amount = model.collectGift()
                    AudioManager.shared.play("park", volume: 0.8)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { justCollected = amount }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gift.fill").font(.system(size: 15, weight: .black))
                        Text("\(Strings.collect.localUpper)  +\(Progression.streakRewards[day - 1])")
                    }
                }
                .buttonStyle(RaceButtonStyle(color: Palette.gold, textColor: Neo.ink, height: 44, fontSize: 18))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(green)
                    Text((justCollected.map { "\(Strings.collected) +\($0)" } ?? Strings.comeBackTomorrow).localUpper)
                        .contentTransition(.numericText())
                }
                .font(.race(15))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(green.opacity(0.35), lineWidth: 1))
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(glassCard(tint: Palette.gold))
    }

    /// Seven days as a track: done days filled, today ringed and glowing, the last one a gift.
    private func streakTimeline(pending: Int?, collected: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(1...7, id: \.self) { day in
                let done = pending == nil ? day <= collected : day < (pending ?? 1)
                let today = day == pending
                if day > 1 {
                    Rectangle()
                        .fill(done || today ? green.opacity(0.8) : Color.white.opacity(0.12))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 18)
                }
                VStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(done ? green : (today ? Palette.gold : Color.white.opacity(0.06)))
                            .frame(width: day == 7 ? 30 : 24, height: day == 7 ? 30 : 24)
                        if today {
                            Circle().strokeBorder(Palette.gold.opacity(0.5), lineWidth: 2)
                                .frame(width: 34, height: 34)
                                .scaleEffect(pulse ? 1.15 : 0.95)
                                .opacity(pulse ? 0.2 : 0.9)
                                .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: pulse)
                        }
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .black)).foregroundStyle(Neo.ink)
                        } else if day == 7 {
                            Image(systemName: "gift.fill").font(.system(size: 13, weight: .black))
                                .foregroundStyle(today ? Neo.ink : Palette.gold)
                        } else {
                            Text("\(day)").font(.race(11)).foregroundStyle(today ? Neo.ink : .white.opacity(0.6))
                        }
                    }
                    .frame(height: 34)
                    Text("\(Progression.streakRewards[day - 1])")
                        .font(.ui(9.5, .heavy)).monospacedDigit()
                        .foregroundStyle(today ? Palette.gold : .white.opacity(done ? 0.4 : 0.6))
                        .fixedSize()
                }
            }
        }
    }

    // MARK: Tasks

    private var tasksColumn: some View {
        let tasks = Progression.tasks
        let doneCount = tasks.filter(\.done).count
        let selected = mode ?? .park
        let group = tasks.filter { $0.kind.mode == selected }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Strings.dailyTasks.localUpper).font(.kicker(10)).tracking(1.6).foregroundStyle(Neo.cyan)
                    Text(Strings.dailyTasksHint)
                        .font(.ui(10, .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(doneCount) / CGFloat(max(1, tasks.count)))
                        .stroke(green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(doneCount)/\(tasks.count)").font(.ui(10, .heavy)).monospacedDigit()
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
            }
            HStack(alignment: .top, spacing: 10) {
                // Modes as a list: each with its full name, icon and how many of its tasks are done
                VStack(spacing: 6) {
                    ForEach(Progression.TaskMode.allCases, id: \.rawValue) { m in modeRow(m, tasks: tasks, selected: selected) }
                    Spacer(minLength: 0)
                }
                .frame(width: 124)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(group) { task in taskCard(task, accent: accent(selected)) }
                    }
                    .id(selected)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(glassCard(tint: Neo.cyan))
    }

    private func modeRow(_ m: Progression.TaskMode, tasks: [Progression.DailyTask], selected: Progression.TaskMode) -> some View {
        let modeTasks = tasks.filter { $0.kind.mode == m }
        let done = modeTasks.filter(\.done).count
        let isOn = m == selected
        let complete = done == modeTasks.count && !modeTasks.isEmpty
        let waiting = modeTasks.filter(\.claimable).count
        return Button {
            AudioManager.shared.play("click", volume: 0.4)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { mode = m }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: m.icon)
                    .font(.system(size: 12, weight: .black))
                    .frame(width: 18)
                Text(m.short)
                    .font(.ui(13, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                if waiting > 0 {
                    // Rewards to collect in this mode
                    // (a small gold disc: the mode's name keeps its room)
                    Image(systemName: "gift.fill")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Palette.gold))
                        .scaleEffect(pulse ? 1.08 : 0.94)
                } else if complete {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isOn ? Neo.ink : green)
                } else {
                    Text("\(done)/\(modeTasks.count)")
                        .font(.ui(11, .heavy)).monospacedDigit()
                        .opacity(0.75)
                }
            }
            .foregroundStyle(isOn ? Neo.ink : .white.opacity(0.85))
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 12).fill(isOn ? AnyShapeStyle(accent(m)) : AnyShapeStyle(Color.white.opacity(0.06))))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isOn ? Color.clear : Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// A task: its progress ring and icon, the full title, and below it the count and reward.
    private func taskCard(_ task: Progression.DailyTask, accent: Color) -> some View {
        let value = Double(min(task.progress, task.kind.target)) / Double(max(1, task.kind.target))
        let tint = task.done ? green : accent
        return HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: value)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: task.done ? "checkmark" : task.kind.icon)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(task.done ? green : .white)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 6) {
                Text(task.kind.title)
                    .font(.ui(13.5, .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(task.claimable ? Strings.rewardWaiting : (task.done ? Strings.taskDone : "\(min(task.progress, task.kind.target)) / \(task.kind.target)"))
                        .font(.ui(11, .heavy)).monospacedDigit()
                        .foregroundStyle(task.claimable ? Palette.gold : (task.done ? green : .white.opacity(0.55)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    rewardChip(task)
                        .fixedSize()
                        .layoutPriority(2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(cardFill(task)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(cardEdge(task, tint: tint), lineWidth: task.claimable ? 1.5 : 1))
        .overlay {
            // Coins flying off the card when collected
            ForEach(bursts.filter { $0.task == task.index }) { burst in CoinBurstView(amount: burst.amount) }
        }
    }

    private func cardFill(_ task: Progression.DailyTask) -> Color {
        task.claimable ? Palette.gold.opacity(0.08) : Color.white.opacity(task.done ? 0.03 : 0.05)
    }

    private func cardEdge(_ task: Progression.DailyTask, tint: Color) -> Color {
        task.claimable ? Palette.gold.opacity(pulse ? 0.8 : 0.4) : tint.opacity(task.done ? 0.35 : 0.18)
    }

    /// The task's reward: a COLLECT button once it is done and waiting, else the amount (or
    /// "collected").
    @ViewBuilder
    private func rewardChip(_ task: Progression.DailyTask) -> some View {
        if task.claimable && !collecting.contains(task.index) {
            // Done: the coins wait for a tap
            Button { collect(task) } label: {
                HStack(spacing: 4) {
                    Text(Strings.collectTag).font(.race(13))
                    Image(systemName: "dollarsign.circle.fill").font(.system(size: 11, weight: .bold))
                    Text("+\(task.kind.reward)").font(.race(13))
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(Palette.gold))
                .shadow(color: Palette.gold.opacity(pulse ? 0.7 : 0.25), radius: pulse ? 10 : 4)
                .scaleEffect(pulse ? 1.04 : 0.98)
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        } else {
            HStack(spacing: 3) {
                Image(systemName: task.done ? "checkmark" : "dollarsign.circle.fill").font(.system(size: 11, weight: .bold))
                Text(task.done ? Strings.claimed : "+\(task.kind.reward)").font(.race(13))
            }
            .foregroundStyle(task.done ? green.opacity(0.8) : Palette.gold)
            .padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(task.done ? green.opacity(0.08) : Palette.gold.opacity(0.12)))
        }
    }

    /// Collects one task's coins: a burst of coins and the amount rising off the card, a chime,
    /// a tap of haptics; the coin counter in the header counts up.
    private func collect(_ task: Progression.DailyTask) {
        guard !collecting.contains(task.index) else { return }
        let amount = model.claimTask(task.index)
        guard amount > 0 else { return }
        AudioManager.shared.play("park", volume: 0.7)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let burst = CoinBurst(task: task.index, amount: amount)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            _ = collecting.insert(task.index)
            bursts.append(burst)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { bursts.removeAll { $0.id == burst.id } }
    }

    private func collectAll(_ tasks: [Progression.DailyTask]) {
        for (order, task) in tasks.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(order) * 0.18) {
                // The mode of each task comes up as its coins fly
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { mode = task.kind.mode }
                collect(task)
            }
        }
    }

    /// Frosted dark card with a hairline edge and a faint tint along the top.
    private func glassCard(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(Neo.panel.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(colors: [tint.opacity(0.10), .clear], startPoint: .top, endPoint: .center))
            )
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
    }
}

/// One collect: which task, how many coins.
struct CoinBurst: Identifiable {
    let id = UUID()
    let task: Int
    let amount: Int
}

/// A handful of coins popping up and fading off a task card, with the amount rising above them.
struct CoinBurstView: View {
    let amount: Int
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { index in
                let angle = Double(index) / 9 * .pi * 2 + 0.3
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.gold)
                    .shadow(color: Palette.gold.opacity(0.8), radius: 4)
                    .offset(x: go ? cos(angle) * 70 : 0, y: go ? sin(angle) * 34 - 26 : 0)
                    .scaleEffect(go ? 0.6 : 1.2)
                    .opacity(go ? 0 : 1)
            }
            Text("+\(amount)")
                .font(.race(22))
                .foregroundStyle(Palette.gold)
                .shadow(color: .black.opacity(0.6), radius: 3)
                .offset(y: go ? -38 : -6)
                .opacity(go ? 0 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 40)
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 1.1)) { go = true } }
    }
}

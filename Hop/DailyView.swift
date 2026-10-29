import SwiftUI

/// The daily screen in the home screen's racing style: the seven-day gift strip as slanted
/// plates with today's gift to collect, and today's three tasks with slanted progress bars.
struct DailyView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var justCollected: Int?
    @State private var shown = false

    private let green = Color(red: 0.35, green: 0.95, blue: 0.55)

    var body: some View {
        ZStack {
            Neo.ink.ignoresSafeArea()
            // The splash art, dim and soft, behind everything
            if let art = UIImage(named: "splash.jpg") {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 18)
                    .opacity(0.35)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            LinearGradient(colors: [Neo.ink.opacity(0.9), Neo.ink.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Strings.dailyKicker).font(.kicker(9)).tracking(1.5).foregroundStyle(Neo.cyan)
                        Text(Strings.dailyTitle.uppercased()).font(.race(32)).foregroundStyle(.white)
                    }
                    Spacer()
                    CoinPill(coins: model.coins)
                    NeoIconButton(systemImage: "xmark") { dismiss() }
                }
                HStack(alignment: .top, spacing: 16) {
                    giftPanel
                        .rise(shown, delay: 0.02)
                    tasksPanel
                        .rise(shown, delay: 0.1)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .onAppear { shown = true }
    }

    // MARK: Gift

    private var giftPanel: some View {
        let pending = Progression.pendingGiftDay
        let collected = Progression.streakCollected
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Strings.dailyGift.uppercased()).font(.kicker(10)).tracking(1.5).foregroundStyle(Palette.gold)
                Spacer()
                Text(Strings.streakDays(pending.map { $0 - 1 } ?? collected))
                    .font(.race(13)).foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { day in
                    let done = pending == nil ? day <= collected : day < (pending ?? 1)
                    let today = day == pending
                    VStack(spacing: 4) {
                        Text("\(day)")
                            .font(.race(11, weight: .heavy))
                            .foregroundStyle(today ? Neo.ink.opacity(0.7) : .white.opacity(0.55))
                        Image(systemName: done ? "checkmark" : (day == 7 ? "gift.fill" : "dollarsign.circle.fill"))
                            .font(.system(size: day == 7 ? 20 : 16, weight: .black))
                            .foregroundStyle(done ? green : (today ? Neo.ink : Palette.gold))
                            .frame(height: 22)
                        Text("\(Progression.streakRewards[day - 1])")
                            .font(.race(14))
                            .monospacedDigit()
                            .foregroundStyle(today ? Neo.ink : .white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        SlantedShape(skew: 6)
                            .fill(today ? AnyShapeStyle(LinearGradient(colors: [Palette.gold, Palette.goldDeep], startPoint: .top, endPoint: .bottom))
                                        : AnyShapeStyle(Neo.ink.opacity(done ? 0.5 : 0.85)))
                    )
                    .overlay(SlantedShape(skew: 6).strokeBorderCompat(today ? Color.white.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1))
                    .shadow(color: today ? Palette.gold.opacity(0.6) : .clear, radius: 10)
                    .opacity(done ? 0.55 : 1)
                    .scaleEffect(today ? 1.06 : 1)
                    .zIndex(today ? 1 : 0)
                }
            }
            Text(Strings.dailyGiftHint)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let day = pending {
                Button {
                    let amount = model.collectGift()
                    AudioManager.shared.play("park", volume: 0.8)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { justCollected = amount }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gift.fill").font(.system(size: 15, weight: .black))
                        Text("\(Strings.collect.uppercased())  +\(Progression.streakRewards[day - 1])")
                    }
                }
                .buttonStyle(RaceButtonStyle(color: Palette.gold, textColor: Neo.ink, height: 50, fontSize: 21))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(green)
                    Text((justCollected.map { "\(Strings.collected) +\($0)" } ?? Strings.comeBackTomorrow).uppercased())
                        .contentTransition(.numericText())
                }
                .font(.race(18))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(SlantedShape(skew: 16).fill(Neo.ink.opacity(0.85)))
                .overlay(SlantedShape(skew: 16).strokeBorderCompat(green.opacity(0.5), lineWidth: 1))
                .scaleEffect(justCollected == nil ? 1 : 1.03)
            }
        }
        .padding(.vertical, 16)
        .padding(.leading, 26)
        .padding(.trailing, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NeoPanel())
        .overlay(alignment: .topLeading) { AccentStripe(color: Palette.gold).offset(x: 30, y: 0) }
    }

    // MARK: Tasks

    private var tasksPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(Strings.dailyTasks.uppercased()).font(.kicker(10)).tracking(1.5).foregroundStyle(Neo.cyan)
            ForEach(Progression.tasks) { task in
                HStack(spacing: 12) {
                    Image(systemName: task.kind.icon)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(task.done ? Neo.ink : .white)
                        .frame(width: 40, height: 34)
                        .background(SlantedShape(skew: 6).fill(task.done ? AnyShapeStyle(green) : AnyShapeStyle(Color.white.opacity(0.1))))
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(task.kind.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer(minLength: 4)
                            if task.done {
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .black)).foregroundStyle(green)
                            } else {
                                Text("+\(task.kind.reward)").font(.race(14)).foregroundStyle(Palette.gold)
                            }
                        }
                        SlantedBar(value: Double(min(task.progress, task.kind.target)) / Double(max(1, task.kind.target)),
                                   color: task.done ? green : Palette.gold)
                            .frame(height: 6)
                        Text("\(min(task.progress, task.kind.target)) / \(task.kind.target)")
                            .font(.race(11, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 18)
                .padding(.trailing, 14)
                .background(NeoPanel())
            }
            Text(Strings.dailyTasksHint)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

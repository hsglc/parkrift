import SwiftUI

/// The daily screen: the seven-day gift strip with today's gift to collect, and today's three
/// tasks with their progress.
struct DailyView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var justCollected: Int?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.card, Palette.ink], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(Strings.dailyTitle.uppercased())
                        .font(.race(30))
                        .foregroundStyle(.white)
                    Spacer()
                    CoinPill(coins: model.coins)
                    RoundIconButton(systemImage: "xmark") { dismiss() }
                }
                HStack(alignment: .top, spacing: 16) {
                    giftPanel
                    tasksPanel
                }
            }
            .padding(20)
        }
    }

    // MARK: Gift

    private var giftPanel: some View {
        let pending = Progression.pendingGiftDay
        let collected = Progression.streakCollected
        return VStack(alignment: .leading, spacing: 10) {
            Text(Strings.dailyGift.uppercased())
                .font(.kicker(11))
                .tracking(1.5)
                .foregroundStyle(Palette.neon)
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    let done = pending == nil ? day <= collected : day < (pending ?? 1)
                    let today = day == pending
                    VStack(spacing: 3) {
                        Text(Strings.dayLabel(day))
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Image(systemName: done ? "checkmark.circle.fill" : (day == 7 ? "gift.fill" : "dollarsign.circle.fill"))
                            .font(.system(size: day == 7 ? 22 : 18, weight: .bold))
                            .foregroundStyle(done ? Color(red: 0.45, green: 0.95, blue: 0.6) : Palette.gold)
                        Text("\(Progression.streakRewards[day - 1])")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(today ? Palette.gold.opacity(0.22) : Color.white.opacity(done ? 0.04 : 0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(today ? Palette.gold : Color.clear, lineWidth: 1.5))
                    .opacity(done ? 0.6 : 1)
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
                    Text("\(Strings.collect.uppercased()) · +\(Progression.streakRewards[day - 1])")
                }
                .buttonStyle(RaceButtonStyle(color: Palette.gold, height: 48, fontSize: 20))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color(red: 0.45, green: 0.95, blue: 0.6))
                    Text(justCollected.map { "\(Strings.collected) +\($0)" } ?? Strings.comeBackTomorrow)
                        .contentTransition(.numericText())
                }
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
                .scaleEffect(justCollected == nil ? 1 : 1.03)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    // MARK: Tasks

    private var tasksPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Strings.dailyTasks.uppercased())
                .font(.kicker(11))
                .tracking(1.5)
                .foregroundStyle(Palette.neon)
            ForEach(Progression.tasks) { task in
                HStack(spacing: 10) {
                    Image(systemName: task.kind.icon)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(task.done ? Palette.ink : .white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(task.done ? Color(red: 0.45, green: 0.95, blue: 0.6) : Color.white.opacity(0.1)))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(task.kind.title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer(minLength: 4)
                            Text(task.done ? "✓" : "+\(task.kind.reward)")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(task.done ? Color(red: 0.45, green: 0.95, blue: 0.6) : Palette.gold)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.1))
                                Capsule()
                                    .fill(LinearGradient(colors: [Palette.gold, Palette.goldDeep], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: proxy.size.width * min(1, CGFloat(task.progress) / CGFloat(task.kind.target)))
                            }
                        }
                        .frame(height: 6)
                        Text("\(min(task.progress, task.kind.target)) / \(task.kind.target)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
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

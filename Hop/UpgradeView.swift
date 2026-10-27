import SwiftUI

/// Upgrades for the car shown in the garage (engine, grip, nitro; three levels each, paid with
/// coins) and its rim colour.
struct UpgradeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var choice: CarChoice

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.card, Palette.ink], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Strings.upgrade.uppercased())
                            .font(.kicker(11))
                            .tracking(1.5)
                            .foregroundStyle(Palette.neon)
                        Text(choice.spec.name.uppercased())
                            .font(.race(28))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    CoinPill(coins: model.coins)
                    RoundIconButton(systemImage: "xmark") { dismiss() }
                }
                HStack(spacing: 10) {
                    upgradeCard(.engine, icon: "engine.combustion.fill", title: Strings.upgradeEngine, info: Strings.upgradeEngineInfo)
                    upgradeCard(.grip, icon: "road.lanes.curved.right", title: Strings.upgradeGrip, info: Strings.upgradeGripInfo)
                    upgradeCard(.nitro, icon: "flame.fill", title: Strings.upgradeNitro, info: Strings.upgradeNitroInfo)
                }
                HStack(spacing: 10) {
                    Text(Strings.rims.uppercased())
                        .font(.kicker(10))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.6))
                    ForEach(CarSpec.rims.indices, id: \.self) { index in
                        let selected = index == choice.rim
                        Button {
                            AudioManager.shared.play("click", volume: 0.5)
                            choice.rim = index
                        } label: {
                            Circle()
                                .fill(Color(CarSpec.rims[index]))
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(Color.white.opacity(selected ? 1 : 0.3), lineWidth: selected ? 2.5 : 1))
                                .scaleEffect(selected ? 1.12 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: choice.rim)
                Text(Strings.upgradeHint)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(20)
        }
    }

    private func level(_ kind: Progression.UpgradeKind) -> Int {
        let current = Progression.upgrades(for: choice.model)
        return [current.engine, current.grip, current.nitro][kind.rawValue]
    }

    private func upgradeCard(_ kind: Progression.UpgradeKind, icon: String, title: String, info: String) -> some View {
        let current = level(kind)
        let maxed = current >= Progression.maxUpgrade
        let price = Progression.upgradePrice(current)
        let affordable = model.coins >= price
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(Palette.gold)
                Text(title.uppercased())
                    .font(.race(18))
                    .foregroundStyle(.white)
            }
            Text(info)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                ForEach(0..<Progression.maxUpgrade, id: \.self) { index in
                    Capsule()
                        .fill(index < current ? Palette.gold : Color.white.opacity(0.12))
                        .frame(height: 7)
                }
            }
            Spacer(minLength: 0)
            Button {
                if Progression.buyUpgrade(kind, for: choice.model) {
                    model.objectWillChange.send()
                    AudioManager.shared.play("shift", volume: 0.6)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } label: {
                HStack(spacing: 4) {
                    if maxed {
                        Text(Strings.maxLevel)
                    } else {
                        Image(systemName: "dollarsign.circle.fill")
                        Text("\(price)").monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(RaceButtonStyle(color: maxed ? Color(white: 0.4) : (affordable ? Color(red: 0.35, green: 0.95, blue: 0.55) : Color(white: 0.45)),
                                         height: 40, fontSize: 17))
            .disabled(maxed || !affordable)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

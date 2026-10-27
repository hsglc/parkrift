import SwiftUI
import SceneKit

/// Live 3D lot behind the menu screens, darkened on the left so text stays readable.
struct MenuBackdrop: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            SceneKitView(world: model.menuWorld)
            LinearGradient(colors: [Palette.ink.opacity(0.80), Palette.ink.opacity(0.35), Palette.ink.opacity(0.70)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [Color.clear, Palette.ink.opacity(0.55)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Menu

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var showJoin = false

    var body: some View {
        ZStack {
            MenuBackdrop()
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Logo(size: 50)
                    Text(Strings.tagline)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 330, alignment: .leading)
                    LevelPicker()
                        .padding(.top, 4)
                }

                VStack(spacing: 10) {
                    if showJoin {
                        JoinPanel(showJoin: $showJoin)
                    } else {
                        Button { model.playSolo() } label: {
                            Label(Strings.playSolo, systemImage: "car.fill")
                        }
                        .buttonStyle(ChunkyButtonStyle(colors: Palette.orange, height: 46, fontSize: 18))
                        Button { model.playCity() } label: {
                            Label(Strings.cityDrive, systemImage: "building.2.fill")
                        }
                        .buttonStyle(ChunkyButtonStyle(colors: Palette.slate, height: 44, fontSize: 17))
                        Button { model.playRace() } label: {
                            Label(Strings.carRace, systemImage: "flag.checkered")
                        }
                        .buttonStyle(ChunkyButtonStyle(colors: Palette.slate, height: 44, fontSize: 17))
                        Button { model.createRoom() } label: {
                            Label(Strings.createRoom, systemImage: "person.2.fill")
                        }
                        .buttonStyle(ChunkyButtonStyle(colors: Palette.blueButton, height: 44, fontSize: 17))
                        Button { withAnimation(.spring(response: 0.3)) { showJoin = true } } label: {
                            Label(Strings.joinRoom, systemImage: "keyboard.fill")
                        }
                        .buttonStyle(ChunkyButtonStyle(colors: Palette.green, height: 44, fontSize: 17))
                    }
                    if model.connecting {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text(Strings.connecting)
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                    }
                    if let error = model.errorText {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 230)
                .panel()
            }
            .padding(.horizontal, 20)
        }
        .overlay(alignment: .topTrailing) {
            SoundToggle()
                .padding(.top, 12)
                .padding(.trailing, 16)
        }
    }
}

/// Four letter boxes over a hidden text field.
private struct JoinPanel: View {
    @EnvironmentObject var model: AppModel
    @Binding var showJoin: Bool
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text(Strings.joinRoom.uppercased())
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(1.5)
            ZStack {
                TextField("", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($focused)
                    .opacity(0.02)
                    .onChange(of: code) { _, newValue in
                        let filtered = String(newValue.uppercased().filter { $0.isLetter && $0.isASCII }.prefix(4))
                        if filtered != newValue { code = filtered }
                    }
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        let letters = Array(code)
                        let active = focused && index == min(letters.count, 3)
                        Text(index < letters.count ? String(letters[index]) : "")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 52)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.10)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(active ? Palette.gold : Color.white.opacity(0.18), lineWidth: active ? 2 : 1))
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            Button {
                focused = false
                model.joinRoom(code: code)
            } label: {
                Label(Strings.join, systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(ChunkyButtonStyle(colors: code.count == 4 ? Palette.green : Palette.disabled, height: 46))
            .disabled(code.count != 4 || model.connecting)

            Button(Strings.back) {
                focused = false
                withAnimation(.spring(response: 0.3)) { showJoin = false }
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.65))
        }
        .onAppear { focused = true }
    }
}

struct LevelPicker: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered")
                Text(Strings.levels.uppercased())
                    .tracking(1.2)
                Spacer()
                Image(systemName: "star.fill").foregroundStyle(Palette.gold)
                Text("\(totalStars)/\(Levels.all.count * 3)")
            }
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))

            let columns = Array(repeating: GridItem(.fixed(54), spacing: 8), count: 5)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(0..<Levels.all.count, id: \.self) { index in
                    LevelTile(index: index,
                              unlocked: index < model.unlockedLevels,
                              selected: model.selectedLevel == index,
                              stars: model.stars(for: index)) {
                        model.selectedLevel = index
                        AudioManager.shared.play("click", volume: 0.6)
                    }
                }
            }
        }
        .frame(width: 302)
        .panel(padding: 14)
    }

    private var totalStars: Int {
        (0..<Levels.all.count).reduce(0) { $0 + model.stars(for: $1) }
    }
}

private struct LevelTile: View {
    let index: Int
    let unlocked: Bool
    let selected: Bool
    let stars: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                if unlocked {
                    Text("\(index + 1)")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(selected ? Palette.ink : .white)
                    StarsRow(filled: stars, size: 7, spacing: 1)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .frame(width: 54, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: [Palette.gold, Palette.goldDeep], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(unlocked ? 0.10 : 0.04)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(selected ? Color.white.opacity(0.6) : Color.white.opacity(unlocked ? 0.16 : 0.06), lineWidth: 1)
            )
            .scaleEffect(selected ? 1.06 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: selected)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }
}

// MARK: - Lobby

struct LobbyView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            MenuBackdrop()
            HStack(spacing: 18) {
                // Room code
                VStack(spacing: 12) {
                    Text(Strings.roomCode.uppercased())
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(1.5)
                    HStack(spacing: 8) {
                        ForEach(Array(model.roomCode.enumerated()), id: \.offset) { _, letter in
                            Text(String(letter))
                                .font(.system(size: 40, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 58, height: 70)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.06)],
                                                             startPoint: .top, endPoint: .bottom))
                                )
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                        }
                    }
                    if model.isHost {
                        Text(Strings.shareCode)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                        ShareLink(item: "ParkPark – \(Strings.roomCode): \(model.roomCode)") {
                            Label(Strings.shareCode, systemImage: "square.and.arrow.up")
                                .labelStyle(.iconOnly)
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color.white.opacity(0.12)))
                        }
                    }
                }
                .frame(width: 270)
                .panel()

                // Players and start
                VStack(alignment: .leading, spacing: 12) {
                    Text(Strings.players.uppercased())
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(1.5)
                    PlayerChip(name: Strings.you, slot: model.mySlot, present: true)
                    PlayerChip(name: Strings.friend, slot: 1 - model.mySlot, present: model.friendHere)

                    HStack(spacing: 8) {
                        ModeChip(title: Strings.carRace, icon: "flag.checkered", selected: model.onlineMode == .race,
                                 enabled: model.isHost) { model.setOnlineMode(.race) }
                        ModeChip(title: Strings.parkRace, icon: "parkingsign", selected: model.onlineMode == .park,
                                 enabled: model.isHost) { model.setOnlineMode(.park) }
                    }
                    Text(model.onlineMode == .race ? Strings.carRaceInfo : Strings.cityRaceInfo)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    if model.isHost {
                        Button { model.startOnlineGame() } label: {
                            Label(Strings.start, systemImage: "flag.checkered")
                        }
                        .buttonStyle(ChunkyButtonStyle(colors: model.friendHere ? Palette.green : Palette.disabled, height: 50, fontSize: 19))
                        .disabled(!model.friendHere)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text(Strings.waitingHost)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .frame(width: 250)
                .panel()
            }
            .padding(.horizontal, 20)
        }
        .overlay(alignment: .topLeading) {
            RoundIconButton(systemImage: "xmark") { model.leaveToMenu() }
                .padding(.top, 12)
                .padding(.leading, 16)
        }
        .overlay(alignment: .topTrailing) {
            SoundToggle()
                .padding(.top, 12)
                .padding(.trailing, 16)
        }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
        }
        .buttonStyle(ChunkyButtonStyle(colors: Palette.slate, height: 40, corner: 12, fontSize: 16))
        .frame(width: 52)
    }
}

private struct PlayerChip: View {
    let name: String
    let slot: Int
    let present: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(present ? Palette.player(slot) : Color.white.opacity(0.08)))
            Text(name)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(present ? 1 : 0.5))
            Spacer()
            if present {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.55))
            } else {
                ProgressView().tint(.white.opacity(0.7))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(present ? Palette.player(slot).opacity(0.6) : Color.white.opacity(0.08),
                          style: StrokeStyle(lineWidth: 1, dash: present ? [] : [4, 3])))
    }
}

private struct ModeChip: View {
    let title: String
    let icon: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .black))
                Text(title)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? Palette.ink : .white.opacity(0.8))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: [Palette.gold, Palette.goldDeep], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.08)))
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(selected ? 0.5 : 0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Loading

/// Shown while a level is built (instead of a black screen) until the countdown can start.
struct LoadingView: View {
    let level: Int
    @State private var tip = Strings.tips.randomElement() ?? ""

    private var modeTitle: String {
        if Levels.isRace(level) { return Strings.carRace }
        if Levels.isCity(level) { return Strings.parkRace }
        return Levels.title(level)
    }

    private var modeIcon: String {
        if Levels.isRace(level) { return "flag.checkered" }
        if Levels.isCity(level) { return "building.2.fill" }
        return "parkingsign"
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.card, Palette.ink], startPoint: .top, endPoint: .bottom)
            // Road stripes along the bottom
            GeometryReader { proxy in
                Path { path in
                    var x: CGFloat = -20
                    while x < proxy.size.width {
                        path.addRect(CGRect(x: x, y: proxy.size.height - 46, width: 34, height: 6))
                        x += 70
                    }
                }
                .fill(Palette.gold.opacity(0.35))
            }
            VStack(spacing: 14) {
                Logo(size: 44)
                HStack(spacing: 8) {
                    Image(systemName: modeIcon)
                    Text(modeTitle.uppercased())
                        .tracking(1.5)
                }
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Palette.gold)
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .padding(.top, 4)
                Text(Strings.loadingText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                if !tip.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(Palette.gold)
                        Text(tip)
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                    .frame(maxWidth: 420)
                }
            }
            .padding(.horizontal, 20)
        }
        .ignoresSafeArea()
    }
}

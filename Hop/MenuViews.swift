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
    enum Page: Equatable {
        case home
        case levels
        case city
        case online
    }

    @EnvironmentObject var model: AppModel
    @State private var page: Page = .home
    @State private var showJoin = false

    private let pageAnimation = Animation.spring(response: 0.42, dampingFraction: 0.86)

    var body: some View {
        ZStack {
            MenuBackdrop()
            VStack(spacing: 10) {
                topBar
                ZStack {
                    if page == .home {
                        home
                            .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                    } else {
                        detail
                            .id(page)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .move(edge: .trailing).combined(with: .opacity)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                statusLine
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .onChange(of: model.errorText) { _, error in
            if error != nil { withAnimation(pageAnimation) { page = .online } }
        }
    }

    private func go(_ target: Page) {
        AudioManager.shared.play("click", volume: 0.6)
        withAnimation(pageAnimation) {
            page = target
            if target != .online { showJoin = false }
        }
    }

    // MARK: Top bar

    private var totalStars: Int {
        (0..<Levels.all.count).reduce(0) { $0 + model.stars(for: $1) }
    }

    private var pageTitle: String {
        switch page {
        case .home: return ""
        case .levels: return Strings.modeSoloTitle
        case .city: return Strings.modeCityTitle
        case .online: return Strings.modeOnlineTitle
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if page == .home {
                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        Logo(size: 34)
                        Text(Strings.tagline)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .transition(.opacity)
                } else {
                    HStack(spacing: 12) {
                        RoundIconButton(systemImage: "chevron.left") { go(.home) }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Strings.chooseMode.uppercased())
                                .font(.kicker(9))
                                .tracking(1.5)
                                .foregroundStyle(Palette.neon)
                            Text(pageTitle.uppercased())
                                .font(.race(28))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.4), radius: 0, y: 2)
                        }
                    }
                    .transition(.opacity)
                }
            }
            Spacer()
            Button {
                AudioManager.shared.play("click", volume: 0.6)
                model.openGarage(.menu)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "car.side.fill")
                        .foregroundStyle(Color(model.carChoice.color.lighter(by: 0.25)))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Strings.garage.uppercased())
                            .font(.kicker(8))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.6))
                        Text(model.carChoice.spec.name.uppercased())
                            .font(.race(15))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 12)
                .frame(height: 42)
                .background(SlantedShape(skew: 10).fill(Palette.ink.opacity(0.8)))
                .overlay(SlantedShape(skew: 10).stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(PressScaleStyle())
            HStack(spacing: 6) {
                Image(systemName: "star.fill").foregroundStyle(Palette.gold)
                Text("\(totalStars)")
                    .monospacedDigit()
            }
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Capsule().fill(Palette.ink.opacity(0.75)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            SoundToggle()
        }
        .frame(height: 46)
    }

    // MARK: Home: three mode cards

    private var home: some View {
        VStack(spacing: 6) {
            homeCards
            Text(Strings.credits)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var homeCards: some View {
        HStack(spacing: 12) {
            ModeTile(number: "01", title: Strings.modeSoloTitle, subtitle: Strings.modeSoloSub, icon: "parkingsign",
                     chips: [Strings.levelsCount(Levels.all.count), "★ \(totalStars)/\(Levels.all.count * 3)"],
                     accent: Color(red: 1.0, green: 0.55, blue: 0.18)) { go(.levels) }
            ModeTile(number: "02", title: Strings.modeCityTitle, subtitle: Strings.modeCitySub, icon: "flag.checkered",
                     chips: [Strings.carRace, Strings.parkRace],
                     accent: Color(red: 1.0, green: 0.25, blue: 0.45)) { go(.city) }
            ModeTile(number: "03", title: Strings.modeOnlineTitle, subtitle: Strings.modeOnlineSub, icon: "person.2.fill",
                     chips: [Strings.twoPlayersOnline],
                     accent: Palette.neon) { go(.online) }
        }
    }

    // MARK: Detail pages

    @ViewBuilder
    private var detail: some View {
        switch page {
        case .home:
            EmptyView()
        case .levels:
            levelsPage
        case .city:
            HStack(spacing: 12) {
                OptionTile(title: Strings.carRace, subtitle: Strings.carRaceInfo, icon: "flag.checkered",
                           accent: Color(red: 1.0, green: 0.25, blue: 0.45), buttonTitle: Strings.play) { model.playRace() }
                OptionTile(title: Strings.parkRace, subtitle: Strings.cityRaceInfo, icon: "parkingsign",
                           accent: Color(red: 0.55, green: 0.45, blue: 1.0), buttonTitle: Strings.play) { model.playCity() }
            }
        case .online:
            HStack(spacing: 12) {
                OptionTile(title: Strings.createRoom, subtitle: Strings.createRoomSub, icon: "plus.circle.fill",
                           accent: Palette.neon, buttonTitle: Strings.createRoom) { model.createRoom() }
                ZStack {
                    if showJoin {
                        JoinPanel(showJoin: $showJoin)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .racePlate(skew: 16, padding: 14)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    } else {
                        OptionTile(title: Strings.joinRoom, subtitle: Strings.joinRoomSub, icon: "keyboard.fill",
                                   accent: Color(red: 0.35, green: 0.95, blue: 0.55), buttonTitle: Strings.enterCode) {
                            withAnimation(pageAnimation) { showJoin = true }
                        }
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
            }
        }
    }

    private var levelsPage: some View {
        let index = model.selectedLevel
        let level = Levels.all[min(index, Levels.all.count - 1)]
        return HStack(spacing: 14) {
            LevelPicker()
            VStack(alignment: .leading, spacing: 10) {
                Text(Strings.level(index + 1, of: Levels.all.count).uppercased())
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .tracking(1.2)
                Text(level.name.uppercased())
                    .font(.race(28))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .id(index)
                    .transition(.opacity)
                StarsRow(filled: model.stars(for: index), size: 20, spacing: 4)
                HStack(spacing: 6) {
                    Image(systemName: "stopwatch.fill").foregroundStyle(Palette.gold)
                    Text(Strings.bestLabel + ": " + (model.bestTime(for: index).map { String(format: "%.1f s", $0) } ?? "–"))
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 0)
                Button { model.playSolo() } label: {
                    HStack(spacing: 8) {
                        Text(Strings.play.uppercased())
                        Image(systemName: "chevron.right.2").font(.system(size: 16, weight: .black))
                    }
                }
                .buttonStyle(RaceButtonStyle(color: Palette.gold, height: 50, fontSize: 22))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .racePlate(skew: 16, padding: 16)
            .animation(.easeOut(duration: 0.2), value: index)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if model.connecting {
            HStack(spacing: 8) {
                ProgressView().tint(.white)
                Text(Strings.connecting)
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.8))
        } else if let error = model.errorText {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.55))
        }
    }
}

/// Big mode tile on the home page, racing-game style: slanted carbon plate, accent art at the top
/// with speed stripes, a large number, condensed italic title and an accent bar at the bottom.
private struct ModeTile: View {
    let number: String
    let title: String
    let subtitle: String
    let icon: String
    let chips: [String]
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                TileArt(icon: icon, accent: accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text(number)
                        .font(.race(34))
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.35), radius: 0, x: 2, y: 2)
                    Spacer(minLength: 0)
                    Text(title.uppercased())
                        .font(.race(30))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip.uppercased())
                                .font(.race(11, weight: .heavy))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(SlantedShape(skew: 4).fill(Color.white.opacity(0.1)))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(accent)
                    }
                }
                .padding(.leading, 26)
                .padding(.trailing, 18)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SlantedShape(skew: 18).fill(Palette.carbon.opacity(0.88)))
            .clipShape(SlantedShape(skew: 18))
            .overlay(SlantedShape(skew: 18).stroke(Color.white.opacity(0.14), lineWidth: 1))
            .overlay(alignment: .bottom) {
                SlantedShape(skew: 2).fill(accent).frame(height: 4).padding(.leading, 4).padding(.trailing, 22)
            }
            .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
        }
        .buttonStyle(PressableCardStyle())
    }
}

/// Accent gradient, speed stripes and a big icon in the top part of a tile.
private struct TileArt: View {
    let icon: String
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [accent.opacity(0.85), accent.opacity(0.25), .clear],
                               startPoint: .topTrailing, endPoint: UnitPoint(x: 0.1, y: 0.75))
                // Speed stripes
                ForEach(0..<4, id: \.self) { index in
                    SlantedShape(skew: 30)
                        .fill(Color.white.opacity(0.10 - Double(index) * 0.02))
                        .frame(width: 70 - CGFloat(index) * 10, height: 7)
                        .offset(x: -CGFloat(index) * 26 - 8, y: 30 + CGFloat(index) * 13)
                }
                Image(systemName: icon)
                    .font(.system(size: min(96, proxy.size.height * 0.36), weight: .black))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: accent.opacity(0.8), radius: 16)
                    .rotationEffect(.degrees(-6))
                    .padding(.top, 22)
                    .padding(.trailing, 26)
            }
        }
    }
}

/// Option inside a mode page: tile art, title, description and a slanted play button.
private struct OptionTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            TileArt(icon: icon, accent: accent)
            VStack(alignment: .leading, spacing: 8) {
                Spacer(minLength: 0)
                Text(title.uppercased())
                    .font(.race(30))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: action) {
                    HStack(spacing: 8) {
                        Text(buttonTitle.uppercased())
                        Image(systemName: "chevron.right.2").font(.system(size: 15, weight: .black))
                    }
                }
                .buttonStyle(RaceButtonStyle(color: accent, textColor: Palette.ink, height: 46, fontSize: 20))
                .padding(.top, 2)
            }
            .padding(.leading, 26)
            .padding(.trailing, 20)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SlantedShape(skew: 18).fill(Palette.carbon.opacity(0.9)))
        .clipShape(SlantedShape(skew: 18))
        .overlay(SlantedShape(skew: 18).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }
}

/// Cards shrink slightly while pressed.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
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
        .racePlate(skew: 14, padding: 12)
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
                .racePlate(skew: 16, padding: 16)

                // Players and start
                VStack(alignment: .leading, spacing: 12) {
                    Text(Strings.players.uppercased())
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(1.5)
                    PlayerChip(name: Strings.you, slot: model.mySlot, present: true, car: model.carChoice.spec.name)
                    PlayerChip(name: Strings.friend, slot: 1 - model.mySlot, present: model.friendHere,
                               car: model.friendHere ? model.friendCar?.spec.name : nil)
                    Button {
                        AudioManager.shared.play("click", volume: 0.6)
                        model.openGarage(.lobby)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                            Text(Strings.changeCar.uppercased())
                        }
                        .font(.race(14, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(SlantedShape(skew: 8).fill(Color.white.opacity(0.1)))
                        .overlay(SlantedShape(skew: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle())

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
                .frame(width: 270)
                .racePlate(skew: 16, padding: 14)
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
    var car: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(present ? Palette.player(slot) : Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.race(17))
                    .foregroundStyle(.white.opacity(present ? 1 : 0.5))
                if let car = car {
                    Text(car.uppercased())
                        .font(.kicker(8))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
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
    @State private var progress: CGFloat = 0

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
                // Fills over the minimum loading time
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.gold, Palette.goldDeep], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 220 * progress)
                }
                .frame(width: 220, height: 6)
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
        .onAppear {
            withAnimation(.easeInOut(duration: AppModel.minimumLoading)) { progress = 1 }
        }
    }
}

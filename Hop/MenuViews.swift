import SwiftUI
import SceneKit

/// Live 3D lot behind the menu screens under a calm dusk wash: deep blue on the left where the
/// text sits, a soft teal and lavender glow, and two slow drifting lights.
struct MenuBackdrop: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            SceneKitView(world: model.menuWorld)
            // Carbon wash: dark on the left where the brand sits, the lot glowing through on the right
            LinearGradient(colors: [Neo.ink.opacity(0.94), Neo.ink.opacity(0.72), Neo.ink.opacity(0.55)],
                           startPoint: .leading, endPoint: .trailing)
            DriftingLights()
            LinearGradient(colors: [.clear, Neo.ink.opacity(0.75)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

/// Two large, very soft lights that wander slowly (one full drift takes about half a minute).
private struct DriftingLights: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                ZStack {
                    Circle()
                        .fill(Neo.cyan.opacity(0.14))
                        .frame(width: h * 0.9, height: h * 0.9)
                        .blur(radius: 70)
                        .position(x: w * (0.25 + 0.08 * sin(t / 17)), y: h * (0.35 + 0.1 * cos(t / 13)))
                    Circle()
                        .fill(Neo.magenta.opacity(0.12))
                        .frame(width: h * 0.8, height: h * 0.8)
                        .blur(radius: 80)
                        .position(x: w * (0.78 + 0.07 * cos(t / 19)), y: h * (0.65 + 0.1 * sin(t / 15)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The calm menu palette.
enum Calm {
    static let night = Color(red: 0.04, green: 0.07, blue: 0.13)
    static let teal = Color(red: 0.40, green: 0.85, blue: 0.80)
    static let lavender = Color(red: 0.66, green: 0.62, blue: 1.0)
    static let peach = Color(red: 1.0, green: 0.74, blue: 0.58)
    static let sky = Color(red: 0.50, green: 0.75, blue: 1.0)
    static let rose = Color(red: 1.0, green: 0.62, blue: 0.72)

    static func title(_ size: CGFloat) -> Font { .ui(size, .semibold) }
    static func body(_ size: CGFloat) -> Font { .ui(size, .medium) }
}

/// Frosted glass card used across the menu.
struct CalmCard: ViewModifier {
    var radius: CGFloat = 26
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Calm.night.opacity(0.35)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
    }
}

extension View {
    func calmCard(radius: CGFloat = 26, padding: CGFloat = 18) -> some View {
        modifier(CalmCard(radius: radius, padding: padding))
    }
}

/// Round frosted icon button for the menu's top bar.
private struct GlassIconButton: View {
    let systemImage: String
    var badge = false
    let action: () -> Void

    var body: some View {
        Button {
            AudioManager.shared.play("click", volume: 0.5)
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 40, height: 40)
                .background(Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(Calm.peach).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Calm.night, lineWidth: 2))
                    }
                }
        }
        .buttonStyle(PressScaleStyle())
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
    @State private var showAbout = false
    @State private var showDaily = false
    /// The daily gift opens by itself once per launch while it waits to be collected.
    private static var giftShownThisLaunch = false

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
                // Pages take what is left and never push the top bar off the screen
                .layoutPriority(-1)
                statusLine
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showAbout) { AboutView() }
        // Full screen, not a sheet: in landscape a sheet is taller than the screen, which cut
        // off the title and the bottom of the cards
        .fullScreenCover(isPresented: $showDaily) { DailyView().environmentObject(model) }
        .onAppear {
            if PerfSettings.benchmark && ProcessInfo.processInfo.arguments.contains("-staydaily") {
                // Store and design screenshots of the daily screen
                DispatchQueue.main.asyncAfter(deadline: .now() + SplashView.duration + 0.9) { showDaily = true }
            }
            if PerfSettings.benchmark, let at = ProcessInfo.processInfo.arguments.firstIndex(of: "-menupage"),
               at + 1 < ProcessInfo.processInfo.arguments.count {
                // Design screenshots of the menu pages, saved by the app itself
                let name = ProcessInfo.processInfo.arguments[at + 1]
                let target: Page = ["levels": .levels, "city": .city, "online": .online, "join": .online][name] ?? .home
                // Animations started at launch can stall on the test simulator, so the page (the
                // home too) is opened again once the app runs
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { page = target == .home ? .city : .home }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { page = target; showJoin = name == "join" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { saveWindowSnapshot(named: "menu-shot") }
            }
            if Progression.pendingGiftDay != nil && !MenuView.giftShownThisLaunch && !PerfSettings.benchmark {
                MenuView.giftShownThisLaunch = true
                DispatchQueue.main.asyncAfter(deadline: .now() + SplashView.duration + 0.9) { showDaily = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showLevelsPage)) { _ in
            go(.levels)
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

    private var pageSubtitle: String {
        switch page {
        case .home: return ""
        case .levels: return Strings.levelsCount(Levels.all.count)
        case .city: return Strings.chooseMode
        case .online: return Strings.chooseMode
        }
    }

    /// Done daily tasks whose coins wait to be collected (read again whenever the menu redraws).
    private var claimable: [Progression.DailyTask] { Progression.claimableTasks }

    /// Narrow screens drop the garage chip from page top bars (the title needs the room).
    @State private var compactTopBar = false

    private var topBar: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if page == .home {
                    // Coins from finished daily tasks wait here to be collected
                    if !claimable.isEmpty {
                        RewardsReadyPill(count: claimable.count, coins: claimable.reduce(0) { $0 + $1.kind.reward }) {
                            showDaily = true
                        }
                        .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                    }
                } else {
                    NeoPageTitle(subtitle: pageSubtitle, title: pageTitle) { go(.home) }
                    .transition(.opacity)
                }
            }
            Spacer()
            if page != .home && !compactTopBar {
                NeoGarageChip()
            }
            CoinPill(coins: model.coins)
            NeoIconButton(systemImage: "gift.fill", badge: Progression.pendingGiftDay != nil || !claimable.isEmpty) { showDaily = true }
            NeoIconButton(systemImage: "trophy.fill") { GameCenter.showLeaderboards() }
            NeoIconButton(systemImage: "info") { showAbout = true }
            SoundToggle()
        }
        .frame(height: 48)
        .background(GeometryReader { proxy in
            Color.clear.onAppear { compactTopBar = proxy.size.width < 700 }
                .onChange(of: proxy.size.width) { _, width in compactTopBar = width < 700 }
        })
    }

    // MARK: Home: three mode cards

    private var home: some View {
        HomeScreen(openLevels: { go(.levels) }, openCity: { go(.city) }, openOnline: { go(.online) })
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
            HStack(spacing: 14) {
                ArtActionTile(image: "menu_city.jpg", kicker: Strings.homeCityKicker, title: Strings.carRace,
                              detail: Strings.carRaceInfo, accent: Neo.magenta, icon: "flag.checkered",
                              buttonTitle: Strings.play) { model.playRace() }
                ArtActionTile(image: "menu_parkrace.jpg", kicker: Strings.homeTrafficKicker, title: Strings.parkRace,
                              detail: Strings.cityRaceInfo, accent: Palette.gold, icon: "parkingsign",
                              buttonTitle: Strings.play) { model.playCity() }
            }
        case .online:
            ZStack {
                if showJoin {
                    JoinRoomView(showJoin: $showJoin)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    HStack(spacing: 12) {
                        ArtActionTile(image: "menu_duo.jpg", kicker: Strings.homeOnlineKicker, title: Strings.quickMatch,
                                      detail: Strings.quickMatchSub, accent: Neo.magenta, icon: "bolt.fill",
                                      buttonTitle: Strings.playNow) { model.quickMatch() }
                        ArtActionTile(image: "menu_room.jpg", kicker: Strings.homePrivateKicker, title: Strings.createRoom,
                                      detail: Strings.createRoomSub, accent: Neo.cyan, icon: "plus",
                                      buttonTitle: Strings.createRoom) { model.createRoom() }
                        ArtActionTile(image: "menu_join.jpg", kicker: Strings.homePrivateKicker, title: Strings.joinRoom,
                                      detail: Strings.joinRoomSub, accent: Palette.gold, icon: "keyboard",
                                      buttonTitle: Strings.enterCode) {
                            withAnimation(pageAnimation) { showJoin = true }
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private var levelsPage: some View {
        HStack(spacing: 14) {
            LevelPicker()
            LevelDetailPanel()
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if model.connecting {
            HStack(spacing: 8) {
                ProgressView().tint(.white)
                Text(model.matchmaking ? Strings.searching : Strings.connecting)
            }
            .font(.ui(13, .bold))
            .foregroundStyle(.white.opacity(0.8))
        } else if let error = model.errorText {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.ui(13, .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.55))
        }
    }
}

/// Mode card on the home page: frosted glass, a soft accent glow, an icon in a tinted circle,
/// a calm rounded title, a short line and small chips. Cards rise in one after another.
private struct ModeTile: View {
    let index: Int
    let title: String
    let subtitle: String
    let icon: String
    let chips: [String]
    let accent: Color
    let action: () -> Void
    @State private var shown = false

    var body: some View {
        Button {
            AudioManager.shared.play("click", volume: 0.5)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconBadge(icon: icon, accent: accent, size: 50)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                Spacer(minLength: 0)
                Text(title)
                    .font(Calm.title(24))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(Calm.body(12))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(Calm.body(11))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(accent.opacity(0.14)))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(alignment: .topTrailing) {
                Circle().fill(accent.opacity(0.22)).frame(width: 170, height: 170).blur(radius: 50).offset(x: 40, y: -50)
            }
            .calmCard(radius: 28, padding: 18)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 18)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.9).delay(0.08 * Double(index))) { shown = true }
        }
    }
}

/// An icon in a softly tinted circle.
private struct IconBadge: View {
    let icon: String
    let accent: Color
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(accent)
            .frame(width: size, height: size)
            .background(Circle().fill(accent.opacity(0.16)))
            .overlay(Circle().strokeBorder(accent.opacity(0.35), lineWidth: 1))
    }
}

/// Option inside a mode page: icon, title, description and a soft pill button.
private struct OptionTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IconBadge(icon: icon, accent: accent, size: 46)
            Spacer(minLength: 0)
            Text(title)
                .font(Calm.title(22))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(Calm.body(12))
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                AudioManager.shared.play("click", volume: 0.5)
                action()
            } label: {
                HStack(spacing: 6) {
                    Text(buttonTitle)
                    Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
                }
                .font(Calm.title(16))
                .foregroundStyle(Calm.night)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(accent))
            }
            .buttonStyle(PressScaleStyle())
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .topTrailing) {
            Circle().fill(accent.opacity(0.2)).frame(width: 160, height: 160).blur(radius: 50).offset(x: 40, y: -50)
        }
        .calmCard(radius: 28, padding: 18)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
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
/// Joining a room: the code in four big tiles on the left with the join pill, and the game's own
/// letter pad on the right (no system keyboard, which covered half of the landscape screen). Room
/// codes use 24 letters (no I or O), so the pad is a neat 8 × 3 grid.
private struct JoinRoomView: View {
    @EnvironmentObject var model: AppModel
    @Binding var showJoin: Bool
    @State private var code = ""

    private static let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ").map(String.init)

    var body: some View {
        HStack(spacing: 14) {
            codeSide
            pad
        }
    }

    private var codeSide: some View {
        VStack(spacing: 0) {
            Text(Strings.joinRoom)
                .font(.race(28))
                .foregroundStyle(.white)
            Text(Strings.joinRoomSub)
                .font(.ui(12, .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 2)
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { index in
                    let letters = Array(code)
                    let active = index == min(letters.count, 3) && letters.count < 4
                    Text(index < letters.count ? String(letters[index]) : "")
                        .font(.race(38))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 62)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(active ? Palette.gold : Color.white.opacity(0.16), lineWidth: active ? 2 : 1))
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: code)
                }
            }
            .padding(.top, 14)
            Spacer(minLength: 10)
            Button {
                AudioManager.shared.play("click", volume: 0.7)
                model.joinRoom(code: code)
            } label: {
                Text(Strings.join.localUpper)
            }
            .buttonStyle(GaragePillStyle(fill: code.count == 4 ? Palette.gold : Color(white: 0.35), fontSize: 20))
            .disabled(code.count != 4 || model.connecting)
            Button {
                AudioManager.shared.play("click", volume: 0.5)
                withAnimation(.spring(response: 0.3)) { showJoin = false }
            } label: {
                Text(Strings.back)
                    .font(.ui(14, .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(height: 34)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(18)
        .frame(width: 290)
        .frame(maxHeight: .infinity)
        .background(NeoPanel(radius: 24))
    }

    private var pad: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<8, id: \.self) { column in
                        let letter = Self.letters[row * 8 + column]
                        Button { type(letter) } label: {
                            Text(letter)
                                .font(.race(24))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(PressScaleStyle())
                        .disabled(code.count >= 4)
                    }
                }
            }
            HStack(spacing: 8) {
                // Paste a code the friend sent (no permission prompt with the system paste button)
                PasteButton(payloadType: String.self) { strings in
                    let cleaned = String((strings.first ?? "").uppercased().filter { Self.letters.contains(String($0)) }.prefix(4))
                    Task { @MainActor in code = cleaned }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .tint(Color.white.opacity(0.18))
                Spacer(minLength: 0)
                Button {
                    AudioManager.shared.play("click", volume: 0.4)
                    if !code.isEmpty { code.removeLast() }
                } label: {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 96)
                        .frame(maxHeight: .infinity)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(code.isEmpty)
            }
            .frame(height: 44)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NeoPanel(radius: 24))
    }

    private func type(_ letter: String) {
        guard code.count < 4 else { return }
        AudioManager.shared.play("click", volume: 0.4)
        code += letter
    }
}

struct LevelPicker: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(Strings.levels)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.gold)
                Text("\(totalStars)")
                    .font(.race(16))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("/ \(Levels.all.count * 3)")
                    .font(.ui(12, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 2)

            let columns = Array(repeating: GridItem(.fixed(54), spacing: 8), count: 5)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(0..<Levels.all.count, id: \.self) { index in
                            LevelTile(index: index,
                                      unlocked: index < model.unlockedLevels,
                                      selected: model.selectedLevel == index,
                                      stars: model.stars(for: index),
                                      precision: ParkPrecision.best(level: index)) {
                                model.selectedLevel = index
                                AudioManager.shared.play("click", volume: 0.6)
                            }
                            .id(index)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear { proxy.scrollTo(model.selectedLevel, anchor: .center) }
            }
        }
        .frame(width: 302)
        .padding(12)
        .background(NeoPanel(radius: 24))
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
    /// Best parking precision (0...100), shown as its grade in the corner.
    var precision: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                if unlocked {
                    Text("\(index + 1)")
                        .font(.race(19))
                        .foregroundStyle(selected ? Neo.ink : .white)
                    StarsRow(filled: stars, size: 7, spacing: 1)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .frame(width: 54, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Palette.gold : Color.white.opacity(unlocked ? 0.08 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0 : (unlocked ? 0.12 : 0.05)), lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                // Difficulty tier as a short coloured line along the bottom
                Capsule().fill(TierColor.of(level: index).opacity(unlocked ? (selected ? 0 : 0.9) : 0.3))
                    .frame(width: 18, height: 3)
                    .offset(y: -4)
            }
            .overlay(alignment: .topTrailing) {
                if unlocked, let precision = precision {
                    let grade = ParkPrecision.grade(for: precision)
                    Text(grade.rawValue)
                        .font(.race(10))
                        .foregroundStyle(grade == .s ? Palette.ink : .white)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(grade == .s ? Palette.gold : Color.white.opacity(0.18)))
                        .offset(x: 3, y: -4)
                }
            }
            .shadow(color: selected ? Palette.gold.opacity(0.45) : .clear, radius: 10)
            .scaleEffect(selected ? 1.06 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: selected)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }
}

// MARK: - About

extension Notification.Name {
    /// The player picked another language: every screen redraws its texts.
    static let languageChanged = Notification.Name("languageChanged")
    /// Opens the level list (store screenshots).
    static let showLevelsPage = Notification.Name("showLevelsPage")
}

/// Privacy policy, support and the 3D model licenses (attribution required by CC BY).
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var language = Strings.languageChoice
    static let site = "https://parkrift.huseyinglc0-946.workers.dev"

    private struct Credit: Identifiable {
        let id = UUID()
        let what: String
        let author: String
        let license: String
        let link: String
    }

    private var credits: [Credit] { [
        Credit(what: Strings.pick("Garaj arabaları, trafik araçları, polis arabası ve menü görselleri",
                                  "Garage cars, traffic cars, police car and menu art",
                                  "Coches del garaje, coches del tráfico, coche de policía e imágenes del menú"),
               author: Strings.pick("Özgün, Meshy AI ile üretildi", "Original, made with Meshy AI", "Originales, hechos con Meshy AI"),
               license: Strings.pick("Özgün tasarım", "Original design", "Diseño original"), link: "https://www.meshy.ai"),
        Credit(what: Strings.pick("Yayalar ve animasyonları, koniler, variller, bariyer",
                                  "Pedestrians and their animations, cones, drums, barricade",
                                  "Peatones y sus animaciones, conos, bidones, valla"),
               author: "Polyfork", license: Strings.pick("Ticari kullanım", "Commercial use", "Uso comercial"), link: "https://polyfork.dev"),
        Credit(what: Strings.pick("Lastik, rüzgâr, çarpma ve bitiş sesleri", "Tyre, wind, crash and finish sounds", "Sonidos de neumáticos, viento, choques y meta"),
               author: "Stunt Rally / VDrift, Halleck, nathanshadow", license: "CC BY-SA 3.0", link: "https://opengameart.org/content/stunt-rally-sounds"),
        Credit(what: Strings.pick("Korna sesi", "Horn sound", "Sonido de claxon"), author: "BigSoundBank (Joseph Sardin)", license: "CC0",
               link: "https://bigsoundbank.com"),
        Credit(what: Strings.pick("Motor, siren sesleri ve müzik", "Engine and siren sounds, music", "Motor, sirena y música"),
               author: "OpenGameArt (banditracer.eu, omfgdude)", license: "CC0", link: "https://opengameart.org"),
        Credit(what: Strings.pick("Arayüz sesleri", "Interface sounds", "Sonidos de interfaz"), author: "Kenney", license: "CC0", link: "https://kenney.nl"),
        Credit(what: Strings.pick("Asfalt, kaldırım, beton dokuları ve gökyüzü", "Asphalt, paving and concrete textures, skies",
                                  "Texturas de asfalto, acera y hormigón, cielos"), author: "Poly Haven", license: "CC0",
               link: "https://polyhaven.com"),
        Credit(what: Strings.pick("Yağmur sesi", "Rain sound", "Sonido de lluvia"), author: "Ylmir (OpenGameArt)", license: "CC0",
               link: "https://opengameart.org/content/rain-loopable"),
        Credit(what: Strings.pick("Trafik ışığı", "Traffic light", "Semáforo"),
               author: Strings.pick("Özgün, Meshy AI ile üretildi", "Original, made with Meshy AI", "Originales, hechos con Meshy AI"), license: "CC BY 4.0", link: "https://www.meshy.ai")
    ] }

    var body: some View {
        NavigationStack {
            List {
                Section(Strings.languageTitle) {
                    Picker(Strings.languageTitle, selection: $language) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .onChange(of: language) { _, newValue in
                        Strings.languageChoice = newValue
                        NotificationCenter.default.post(name: .languageChanged, object: nil)
                    }
                }
                Section {
                    Text(Strings.aboutText)
                        .font(.ui(14, .regular))
                    Link(destination: URL(string: AboutView.site + "/privacy")!) {
                        Label(Strings.privacyPolicy, systemImage: "hand.raised.fill")
                    }
                    Link(destination: URL(string: AboutView.site + "/support")!) {
                        Label(Strings.support, systemImage: "envelope.fill")
                    }
                }
                Section(Strings.licenses) {
                    ForEach(credits) { credit in
                        Link(destination: URL(string: credit.link)!) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(credit.what).font(.ui(15, .semibold))
                                Text("\(credit.author) · \(credit.license)")
                                    .font(.ui(12, .regular))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(Strings.pick("Modeller oyun için değiştirildi (küçültüldü, logolar kaldırıldı). Lisans: creativecommons.org/licenses/by/4.0",
                                      "Models were modified for the game (simplified, logos removed). License: creativecommons.org/licenses/by/4.0",
                                      "Los modelos se adaptaron al juego (simplificados, sin logotipos). Licencia: creativecommons.org/licenses/by/4.0"))
                        .font(.ui(11, .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(Strings.about)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.close) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Lobby

struct LobbyView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            MenuBackdrop()
            VStack(spacing: 10) {
                topBar
                HStack(spacing: 14) {
                    codeCard
                    playersCard
                }
                // The cards take what is left and never push the title bar off the top
                .frame(maxHeight: .infinity)
                .layoutPriority(-1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: Top: close, title, sound

    private var topBar: some View {
        HStack(spacing: 12) {
            RoundIconButton(systemImage: "xmark") {
                AudioManager.shared.play("click", volume: 0.6)
                model.leaveToMenu()
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(Strings.modeOnlineTitle)
                    .font(.race(28))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(model.matchmaking ? Strings.quickMatch : (model.isHost ? Strings.createRoom : Strings.joinRoom))
                    .font(.ui(12, .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer()
            NeoGarageChip()
            SoundToggle()
        }
        .frame(height: 48)
    }

    // MARK: Left: the room code

    private var codeCard: some View {
        VStack(spacing: 0) {
            Text(Strings.roomCode)
                .font(.ui(13, .semibold))
                .foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 10) {
                ForEach(Array(model.roomCode.enumerated()), id: \.offset) { _, letter in
                    Text(String(letter))
                        .font(.race(42))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 66)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                }
            }
            .padding(.top, 10)
            Spacer(minLength: 8)
            if model.matchmaking {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text(Strings.searching)
                }
                .font(.ui(14, .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(height: 52)
            } else if model.isHost {
                Text(Strings.shareCode)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.bottom, 8)
                ShareLink(item: "Parkrift – \(Strings.roomCode): \(model.roomCode)") {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .bold))
                        Text(Strings.shareButton)
                            .font(.race(19))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: 240)
                    .frame(height: 48)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(PressScaleStyle())
            } else {
                Text(Strings.waitingHost)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NeoPanel(radius: 24))
    }

    // MARK: Right: players, the mode, start

    private var playersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlayerChip(name: Strings.playerYou, slot: model.mySlot, present: true, car: model.carChoice.spec.name)
            PlayerChip(name: Strings.playerFriend, slot: 1 - model.mySlot, present: model.friendHere,
                       car: model.friendHere ? model.friendCar?.spec.name : nil)
            // The mode, as one segmented capsule (the host picks)
            HStack(spacing: 4) {
                ModeChip(title: Strings.carRace, icon: "flag.checkered", selected: model.onlineMode == .race,
                         enabled: model.isHost) { model.setOnlineMode(.race) }
                ModeChip(title: Strings.parkRace, icon: "parkingsign", selected: model.onlineMode == .park,
                         enabled: model.isHost) { model.setOnlineMode(.park) }
            }
            .padding(4)
            .background(Capsule().fill(Color.black.opacity(0.35)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .padding(.top, 2)
            Text(model.onlineMode == .race ? Strings.onlineRaceInfo : Strings.onlineParkInfo)
                .font(.ui(12, .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 4)
            Spacer(minLength: 4)
            if model.isHost {
                Button {
                    AudioManager.shared.play("click", volume: 0.7)
                    model.startOnlineGame()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.checkered").font(.system(size: 15, weight: .bold))
                        Text(Strings.start.localUpper)
                    }
                }
                .buttonStyle(GaragePillStyle(fill: model.friendHere ? Palette.gold : Color(white: 0.4)))
                .disabled(!model.friendHere)
            } else {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text(Strings.waitingHost)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.ui(13, .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(minHeight: 48)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NeoPanel(radius: 24))
    }
}

/// A player in the room: their colour, name and car, a tick once they are in.
private struct PlayerChip: View {
    let name: String
    let slot: Int
    let present: Bool
    var car: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(present ? Palette.ink : .white.opacity(0.4))
                .frame(width: 36, height: 36)
                .background(Circle().fill(present ? Palette.player(slot) : Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.race(18))
                    .foregroundStyle(.white.opacity(present ? 1 : 0.5))
                Text(car ?? Strings.waitingShort)
                    .font(.ui(12, .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if present {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.55))
            } else {
                ProgressView().tint(.white.opacity(0.7))
            }
        }
        .padding(.vertical, 5)
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .background(Capsule().fill(Color.white.opacity(present ? 0.07 : 0.03)))
        .overlay(Capsule().strokeBorder(present ? Palette.player(slot).opacity(0.5) : Color.white.opacity(0.1),
                                        style: StrokeStyle(lineWidth: 1, dash: present ? [] : [4, 3])))
    }
}

/// One side of the mode switch: an icon and the mode's name, gold when chosen.
private struct ModeChip: View {
    let title: String
    let icon: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            AudioManager.shared.play("click", volume: 0.5)
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.ui(13, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? Palette.ink : .white.opacity(enabled ? 0.8 : 0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(Capsule().fill(selected ? Palette.gold : Color.clear))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selected)
    }
}

// MARK: - Loading

/// Shown while a level is built (instead of a black screen) until the countdown can start: the
/// mode's key art, the level and its difficulty in the racing style, a filling neon line and a tip.
struct LoadingView: View {
    let level: Int
    /// When the screen appeared and how long it should take; `endsAt` is the exact close time
    /// once the level is ready.
    var shownAt = Date()
    var expected: TimeInterval = 2.35
    var endsAt: Date? = nil
    @State private var tip = Strings.tips.randomElement() ?? ""
    @State private var shown = false
    private var modeTitle: String {
        if Levels.isRace(level) { return Strings.carRace }
        if Levels.isCity(level) { return Strings.parkRace }
        return Levels.title(level)
    }

    private var levelName: String {
        Levels.isCity(level) ? Strings.homeCityKicker : Levels.level(level).name
    }

    private var art: String {
        if Levels.isRace(level) { return "menu_city.jpg" }
        if Levels.isCity(level) { return "menu_parkrace.jpg" }
        return "menu_park.jpg"
    }

    private var accent: Color {
        Levels.isCity(level) ? (Levels.isRace(level) ? Neo.magenta : Palette.gold) : TierColor.of(level: level)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Neo.ink
                if let image = UIImage(named: art) {
                    // Zooms in Core Animation: it keeps moving while the level is built on the
                    // main thread
                    DriftingImage(image: image)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .allowsHitTesting(false)
                }
                LinearGradient(colors: [Neo.ink.opacity(0.92), Neo.ink.opacity(0.55), Neo.ink.opacity(0.2)],
                               startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, Neo.ink.opacity(0.8)], startPoint: .center, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 0) {
                    Wordmark(size: 22)
                    Spacer()
                    HStack(spacing: 8) {
                        Text(modeTitle)
                            .font(.ui(13, .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                        if !Levels.isCity(level) {
                            TierChip(index: level)
                        }
                    }
                    Text(levelName.localUpper)
                        .font(.race(44))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .shadow(color: .black.opacity(0.5), radius: 10)
                        .padding(.top, 2)
                    HStack(spacing: 10) {
                        LoadingBar(shownAt: shownAt, expected: expected, endsAt: endsAt, color: UIColor(accent))
                            .frame(width: 260, height: 6)
                        Text(Strings.loadingText)
                            .font(.ui(12, .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.top, 12)
                    if !tip.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(accent)
                            Text(tip)
                                .font(.ui(12, .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 10)
                        .padding(.leading, 18)
                        .padding(.trailing, 14)
                        .background(NeoPanel())
                        .frame(maxWidth: 460, alignment: .leading)
                        .padding(.top, 16)
                    }
                }
                .padding(.horizontal, max(32, proxy.size.width * 0.06))
                .padding(.vertical, 26)
                .opacity(shown ? 1 : 0)
                .offset(x: shown ? 0 : -20)
                .animation(.spring(response: 0.55, dampingFraction: 0.9), value: shown)
            }
        }
        .ignoresSafeArea()
        .onAppear { shown = true }
    }
}


/// The loading bar as a Core Animation layer: once committed, its animation runs in the render
/// server, so it fills smoothly even while the main thread is busy building the level (a
/// SwiftUI timeline froze and then jumped). Steady towards 92 % over the expected time, creeping
/// on if the level takes longer, then to 100 % exactly at the close time.
struct LoadingBar: UIViewRepresentable {
    let shownAt: Date
    let expected: TimeInterval
    let endsAt: Date?
    let color: UIColor

    func makeUIView(context: Context) -> LoadingBarView {
        let view = LoadingBarView()
        view.configure(color: color)
        return view
    }

    func updateUIView(_ view: LoadingBarView, context: Context) {
        view.run(shownAt: shownAt, expected: expected, endsAt: endsAt)
    }
}

final class LoadingBarView: UIView {
    private let track = CAShapeLayer()
    private let fill = CALayer()
    private let fillHolder = CALayer()
    private let shape = CAShapeLayer()
    private var started: Date?
    private var finishing: Date?

    func configure(color: UIColor) {
        backgroundColor = .clear
        track.fillColor = UIColor.white.withAlphaComponent(0.12).cgColor
        layer.addSublayer(track)
        let gradient = CAGradientLayer()
        gradient.colors = [color.cgColor, color.withAlphaComponent(0.7).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        fill.addSublayer(gradient)
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fillHolder.addSublayer(fill)
        fillHolder.mask = shape
        fillHolder.shadowColor = color.cgColor
        layer.addSublayer(fillHolder)
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = 0.6
        layer.shadowRadius = 4
        layer.shadowOffset = .zero
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = UIBezierPath()
        let r = bounds, skew: CGFloat = 4
        path.move(to: CGPoint(x: r.minX + skew, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - skew, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        path.close()
        track.path = path.cgPath
        shape.path = path.cgPath
        track.frame = bounds
        fillHolder.frame = bounds
        shape.frame = bounds
        fill.bounds = bounds
        fill.position = CGPoint(x: 0, y: bounds.midY)
        fill.sublayers?.first?.frame = bounds
        CATransaction.commit()
    }

    /// The bar's value for a moment, from the clock alone (as the old timeline did).
    private func value(at now: Date, shownAt: Date, expected: TimeInterval) -> CGFloat {
        let elapsed = now.timeIntervalSince(shownAt)
        if elapsed <= expected { return CGFloat(min(1, elapsed / max(0.5, expected)) * 0.92) }
        return CGFloat(0.92 + 0.06 * (1 - exp(-(elapsed - expected) / 2)))
    }

    private var current: CGFloat {
        CGFloat((fill.presentation()?.value(forKeyPath: "transform.scale.x") as? NSNumber)?.doubleValue ?? 0.02)
    }

    func run(shownAt: Date, expected: TimeInterval, endsAt: Date?) {
        let now = Date()
        if let end = endsAt {
            guard finishing != end else { return }
            finishing = end
            let from = max(0.02, current)
            fill.removeAllAnimations()
            let to = CABasicAnimation(keyPath: "transform.scale.x")
            to.fromValue = from
            to.toValue = 1
            to.duration = max(0.05, end.timeIntervalSince(now))
            to.fillMode = .forwards
            to.isRemovedOnCompletion = false
            fill.setValue(1, forKeyPath: "transform.scale.x")
            fill.add(to, forKey: "fill")
            return
        }
        guard started != shownAt else { return }
        started = shownAt
        finishing = nil
        // Up to 92 % at the expected time, then a slow creep: keyframes sampled from the curve
        let total = max(expected, 0) + 8
        let start = max(0, now.timeIntervalSince(shownAt))
        var times: [NSNumber] = []
        var values: [CGFloat] = []
        let steps = 24
        for k in 0...steps {
            let t = start + (total - start) * Double(k) / Double(steps)
            times.append(NSNumber(value: Double(k) / Double(steps)))
            values.append(max(0.02, value(at: shownAt.addingTimeInterval(t), shownAt: shownAt, expected: expected)))
        }
        let animation = CAKeyframeAnimation(keyPath: "transform.scale.x")
        animation.values = values
        animation.keyTimes = times
        animation.duration = max(0.1, total - start)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        fill.removeAllAnimations()
        fill.setValue(values.last ?? 0.98, forKeyPath: "transform.scale.x")
        fill.add(animation, forKey: "fill")
    }
}

/// The loading art, slowly zooming in (Core Animation, so a busy main thread does not stop it).
struct DriftingImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIView {
        let holder = UIView()
        holder.clipsToBounds = true
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFill
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        holder.addSubview(view)
        let zoom = CABasicAnimation(keyPath: "transform.scale")
        zoom.fromValue = 1.0
        zoom.toValue = 1.06
        zoom.duration = 3
        zoom.timingFunction = CAMediaTimingFunction(name: .easeOut)
        zoom.fillMode = .forwards
        zoom.isRemovedOnCompletion = false
        view.layer.add(zoom, forKey: "zoom")
        return holder
    }

    func updateUIView(_ view: UIView, context: Context) {
        view.subviews.first?.frame = view.bounds
    }
}


/// The loading page for page changes, connecting and searching: the art dimmed behind, the
/// wordmark, an icon and a big title, a light sweeping along a bar (Core Animation, so it keeps
/// moving while the app is busy), and a cancel button when the wait can be stopped.
struct CurtainView: View {
    let title: String
    let subtitle: String
    let icon: String
    let onCancel: (() -> Void)?
    @State private var shown = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Neo.ink
                if let image = UIImage(named: "menu_city.jpg") {
                    DriftingImage(image: image)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .opacity(0.55)
                        .allowsHitTesting(false)
                }
                LinearGradient(colors: [Neo.ink.opacity(0.95), Neo.ink.opacity(0.6), Neo.ink.opacity(0.3)],
                               startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, Neo.ink.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 0) {
                    Wordmark(size: 22)
                    Spacer()
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(Neo.cyan)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Neo.cyan.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title.localUpper)
                                .font(.race(38))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            if !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.ui(13, .semibold))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                    SweepBar(color: UIColor(Neo.cyan))
                        .frame(width: 260, height: 5)
                        .padding(.top, 16)
                    if let onCancel = onCancel {
                        Button {
                            AudioManager.shared.play("click", volume: 0.5)
                            onCancel()
                        } label: {
                            Label(Strings.cancelAction, systemImage: "xmark")
                                .font(.ui(14, .bold))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 16)
                                .frame(height: 38)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 18)
                    }
                }
                .padding(.horizontal, max(32, proxy.size.width * 0.06))
                .padding(.vertical, 26)
                .opacity(shown ? 1 : 0)
                .offset(x: shown ? 0 : -16)
                .animation(.easeOut(duration: 0.3), value: shown)
            }
        }
        .ignoresSafeArea()
        .onAppear { shown = true }
    }
}

/// An endless loading bar: a light runs along the track (Core Animation, render server).
struct SweepBar: UIViewRepresentable {
    let color: UIColor

    func makeUIView(context: Context) -> SweepBarView {
        let view = SweepBarView()
        view.configure(color: color)
        return view
    }

    func updateUIView(_ view: SweepBarView, context: Context) {}
}

final class SweepBarView: UIView {
    private let track = CALayer()
    private let light = CAGradientLayer()

    func configure(color: UIColor) {
        backgroundColor = .clear
        track.backgroundColor = UIColor.white.withAlphaComponent(0.12).cgColor
        layer.addSublayer(track)
        light.colors = [color.withAlphaComponent(0).cgColor, color.cgColor, color.withAlphaComponent(0).cgColor]
        light.startPoint = CGPoint(x: 0, y: 0.5)
        light.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(light)
        layer.masksToBounds = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        track.frame = bounds
        track.cornerRadius = bounds.height / 2
        layer.cornerRadius = bounds.height / 2
        let width = bounds.width * 0.4
        light.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        light.removeAllAnimations()
        let run = CABasicAnimation(keyPath: "position.x")
        run.fromValue = -width / 2
        run.toValue = bounds.width + width / 2
        run.duration = 1.1
        run.repeatCount = .infinity
        run.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        light.add(run, forKey: "run")
    }
}

/// On the home screen while daily tasks are done but not collected: a gold pill with the gift,
/// how many rewards wait and their coins, and a COLLECT tab; it springs in with a chime and
/// breathes a glow so it is noticed, and opens the daily screen.
struct RewardsReadyPill: View {
    let count: Int
    let coins: Int
    let open: () -> Void
    @State private var glow = false
    @State private var shown = false

    private var edgeColor: Color { Palette.gold.opacity(glow ? 0.95 : 0.45) }
    private var glowColor: Color { Palette.gold.opacity(glow ? 0.55 : 0.15) }

    var body: some View {
        Button {
            AudioManager.shared.play("click", volume: 0.6)
            open()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Palette.gold.opacity(0.22)).frame(width: 30, height: 30)
                    Image(systemName: "gift.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Palette.gold)
                        .rotationEffect(.degrees(glow ? -8 : 8))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(Strings.rewardsReady(count))
                        .font(.ui(12, .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Image(systemName: "dollarsign.circle.fill").font(.system(size: 10, weight: .bold))
                        Text("+\(coins)").font(.race(13))
                    }
                    .foregroundStyle(Palette.gold)
                }
                Text(Strings.collectTag)
                    .font(.race(13))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(Palette.gold))
            }
            .padding(.leading, 5)
            .padding(.trailing, 7)
            .frame(height: 42)
            .background(Capsule().fill(Color.black.opacity(0.5)))
            .overlay(Capsule().strokeBorder(edgeColor, lineWidth: 1.5))
            .shadow(color: glowColor, radius: glow ? 14 : 6)
            .scaleEffect(shown ? 1 : 0.7)
            .opacity(shown ? 1 : 0)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.25)) { shown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { glow = true }
            }
        }
    }
}

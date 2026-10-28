import SwiftUI
import SceneKit

/// Live 3D lot behind the menu screens under a calm dusk wash: deep blue on the left where the
/// text sits, a soft teal and lavender glow, and two slow drifting lights.
struct MenuBackdrop: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            SceneKitView(world: model.menuWorld)
            LinearGradient(colors: [Calm.night.opacity(0.88), Calm.night.opacity(0.45), Calm.night.opacity(0.62)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [Calm.teal.opacity(0.10), .clear, Calm.lavender.opacity(0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            DriftingLights()
            LinearGradient(colors: [.clear, Calm.night.opacity(0.6)], startPoint: .center, endPoint: .bottom)
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
                        .fill(Calm.teal.opacity(0.22))
                        .frame(width: h * 0.9, height: h * 0.9)
                        .blur(radius: 70)
                        .position(x: w * (0.25 + 0.08 * sin(t / 17)), y: h * (0.35 + 0.1 * cos(t / 13)))
                    Circle()
                        .fill(Calm.lavender.opacity(0.18))
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

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func body(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .rounded) }
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
                statusLine
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .sheet(isPresented: $showAbout) { AboutView() }
        .sheet(isPresented: $showDaily) { DailyView().environmentObject(model) }
        .onAppear {
            if Progression.pendingGiftDay != nil && !MenuView.giftShownThisLaunch && !PerfSettings.benchmark {
                MenuView.giftShownThisLaunch = true
                DispatchQueue.main.asyncAfter(deadline: .now() + SplashView.duration + 0.9) { showDaily = true }
            }
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
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Strings.greeting)
                            .font(Calm.body(12))
                            .foregroundStyle(Calm.teal.opacity(0.9))
                        Text("Parkrift")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: [Calm.peach, Calm.rose, Calm.lavender],
                                                            startPoint: .leading, endPoint: .trailing))
                    }
                    .transition(.opacity)
                } else {
                    HStack(spacing: 12) {
                        GlassIconButton(systemImage: "chevron.left") { go(.home) }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Strings.chooseMode)
                                .font(Calm.body(11))
                                .foregroundStyle(Calm.teal.opacity(0.9))
                            Text(pageTitle)
                                .font(Calm.title(26))
                                .foregroundStyle(.white)
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
                        Text(Strings.garage)
                            .font(Calm.body(10))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(model.carChoice.spec.name)
                            .font(Calm.title(14))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            }
            .buttonStyle(PressScaleStyle())
            CoinPill(coins: model.coins)
            GlassIconButton(systemImage: "gift", badge: Progression.pendingGiftDay != nil) { showDaily = true }
            GlassIconButton(systemImage: "trophy") { GameCenter.showLeaderboards() }
            GlassIconButton(systemImage: "info") { showAbout = true }
            SoundToggle()
        }
        .frame(height: 46)
    }

    // MARK: Home: three mode cards

    private var home: some View {
        VStack(spacing: 6) {
            if Progression.isWeekendEvent {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text(Strings.weekendEvent)
                }
                .font(Calm.title(11))
                .foregroundStyle(Calm.night)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(LinearGradient(colors: [Calm.peach, Calm.rose], startPoint: .leading, endPoint: .trailing)))
            }
            homeCards
            Text(Strings.credits)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var homeCards: some View {
        HStack(spacing: 12) {
            ModeTile(index: 0, title: Strings.modeSoloTitle, subtitle: Strings.modeSoloSub, icon: "parkingsign",
                     chips: [Strings.levelsCount(Levels.all.count), "★ \(totalStars)/\(Levels.all.count * 3)"],
                     accent: Calm.peach) { go(.levels) }
            ModeTile(index: 1, title: Strings.modeCityTitle, subtitle: Strings.modeCitySub, icon: "building.2",
                     chips: [Strings.carRace, Strings.parkRace],
                     accent: Calm.lavender) { go(.city) }
            ModeTile(index: 2, title: Strings.modeOnlineTitle, subtitle: Strings.modeOnlineSub, icon: "person.2",
                     chips: [Strings.twoPlayersOnline],
                     accent: Calm.teal) { go(.online) }
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
                           accent: Calm.rose, buttonTitle: Strings.play) { model.playRace() }
                OptionTile(title: Strings.parkRace, subtitle: Strings.cityRaceInfo, icon: "parkingsign",
                           accent: Calm.lavender, buttonTitle: Strings.play) { model.playCity() }
            }
        case .online:
            HStack(spacing: 12) {
                OptionTile(title: Strings.quickMatch, subtitle: Strings.quickMatchSub, icon: "bolt",
                           accent: Calm.peach, buttonTitle: Strings.playNow) { model.quickMatch() }
                OptionTile(title: Strings.createRoom, subtitle: Strings.createRoomSub, icon: "plus",
                           accent: Calm.teal, buttonTitle: Strings.createRoom) { model.createRoom() }
                ZStack {
                    if showJoin {
                        JoinPanel(showJoin: $showJoin)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .calmCard(radius: 28, padding: 14)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    } else {
                        OptionTile(title: Strings.joinRoom, subtitle: Strings.joinRoomSub, icon: "keyboard",
                                   accent: Calm.sky, buttonTitle: Strings.enterCode) {
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
                Text(Strings.level(index + 1, of: Levels.all.count))
                    .font(Calm.body(12))
                    .foregroundStyle(Calm.teal.opacity(0.9))
                Text(level.name)
                    .font(Calm.title(28))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .id(index)
                    .transition(.opacity)
                StarsRow(filled: model.stars(for: index), size: 20, spacing: 4)
                HStack(spacing: 6) {
                    Image(systemName: "stopwatch").foregroundStyle(Calm.peach)
                    Text(Strings.bestLabel + ": " + (model.bestTime(for: index).map { String(format: "%.1f s", $0) } ?? "–"))
                }
                .font(Calm.body(13))
                .foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 0)
                Button {
                    AudioManager.shared.play("click", volume: 0.5)
                    model.playSolo()
                } label: {
                    HStack(spacing: 8) {
                        Text(Strings.play)
                        Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold))
                    }
                    .font(Calm.title(18))
                    .foregroundStyle(Calm.night)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Capsule().fill(Calm.peach))
                }
                .buttonStyle(PressScaleStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .calmCard(radius: 28, padding: 18)
            .animation(.easeOut(duration: 0.2), value: index)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if model.connecting {
            HStack(spacing: 8) {
                ProgressView().tint(.white)
                Text(model.matchmaking ? Strings.searching : Strings.connecting)
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
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(0..<Levels.all.count, id: \.self) { index in
                            LevelTile(index: index,
                                      unlocked: index < model.unlockedLevels,
                                      selected: model.selectedLevel == index,
                                      stars: model.stars(for: index)) {
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
        .calmCard(radius: 24, padding: 12)
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
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? Calm.night : .white)
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
                          ? AnyShapeStyle(LinearGradient(colors: [Calm.peach, Calm.rose], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(unlocked ? 0.08 : 0.03)))
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

// MARK: - About

extension Notification.Name {
    /// The player picked another language: every screen redraws its texts.
    static let languageChanged = Notification.Name("languageChanged")
}

/// Privacy policy, support and the 3D model licenses (attribution required by CC BY).
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var language = Strings.languageChoice
    static let site = "https://parkpark.huseyinglc0-946.workers.dev"

    private struct Credit: Identifiable {
        let id = UUID()
        let what: String
        let author: String
        let license: String
        let link: String
    }

    private var credits: [Credit] { [
        Credit(what: Strings.pick("Garaj arabaları", "Garage cars", "Coches del garaje"),
               author: "Polyfork", license: Strings.pick("Ticari kullanım", "Commercial use", "Uso comercial"), link: "https://polyfork.dev"),
        Credit(what: Strings.pick("Trafik araçları", "Traffic vehicles", "Vehículos del tráfico"), author: "Kenney (Car Kit)", license: "CC0", link: "https://kenney.nl/assets/car-kit"),
        Credit(what: Strings.pick("Yayalar ve animasyonları, koniler, variller, bariyer, polis arabası",
                                  "Pedestrians and their animations, cones, drums, barricade, police car",
                                  "Peatones y sus animaciones, conos, bidones, valla, coche de policía"),
               author: "Polyfork", license: Strings.pick("Ticari kullanım", "Commercial use", "Uso comercial"), link: "https://polyfork.dev"),
        Credit(what: Strings.pick("Lastik, rüzgâr, çarpma ve bitiş sesleri", "Tyre, wind, crash and finish sounds", "Sonidos de neumáticos, viento, choques y meta"),
               author: "Stunt Rally / VDrift, Halleck, nathanshadow", license: "CC BY-SA 3.0", link: "https://opengameart.org/content/stunt-rally-sounds"),
        Credit(what: Strings.pick("Motor, korna, siren sesleri ve müzik", "Engine, horn and siren sounds, music", "Motor, claxon, sirena y música"),
               author: "OpenGameArt (banditracer.eu, omfgdude)", license: "CC0", link: "https://opengameart.org"),
        Credit(what: Strings.pick("Arayüz sesleri", "Interface sounds", "Sonidos de interfaz"), author: "Kenney", license: "CC0", link: "https://kenney.nl"),
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
                        .font(.system(size: 14))
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
                                Text(credit.what).font(.system(size: 15, weight: .semibold))
                                Text("\(credit.author) · \(credit.license)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(Strings.pick("Modeller oyun için değiştirildi (küçültüldü, logolar kaldırıldı). Lisans: creativecommons.org/licenses/by/4.0",
                                      "Models were modified for the game (simplified, logos removed). License: creativecommons.org/licenses/by/4.0",
                                      "Los modelos se adaptaron al juego (simplificados, sin logotipos). Licencia: creativecommons.org/licenses/by/4.0"))
                        .font(.system(size: 11))
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
                    if model.matchmaking {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text(Strings.searching)
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                    } else if model.isHost {
                        Text(Strings.shareCode)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                        ShareLink(item: "Parkrift – \(Strings.roomCode): \(model.roomCode)") {
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

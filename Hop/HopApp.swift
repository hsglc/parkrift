import SwiftUI
import SpriteKit

@main
struct ParkParkApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}

// MARK: - Model

@MainActor
final class AppModel: ObservableObject {
    enum Screen {
        case menu
        case lobby
        case game
    }

    @Published var screen: Screen = .menu
    @Published var roomCode = ""
    @Published var isHost = false
    @Published var friendHere = false
    @Published var connecting = false
    @Published var errorText: String?
    @Published var selectedLevel = 0

    private(set) var online = false
    private(set) var mySlot = 0
    private(set) var scene: ParkingScene?
    let net = NetClient()

    var unlockedLevels: Int {
        get { max(1, min(Levels.all.count, UserDefaults.standard.integer(forKey: "pp.unlocked"))) }
        set { UserDefaults.standard.set(min(Levels.all.count, newValue), forKey: "pp.unlocked") }
    }

    init() {
        net.onMessage = { [weak self] message in self?.handle(message) }
        net.onClose = { [weak self] _ in self?.connectionClosed() }
    }

    // MARK: Menu actions

    func playSolo() {
        online = false
        mySlot = 0
        friendHere = false
        beginGame(level: selectedLevel)
    }

    func createRoom() {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        roomCode = String((0..<4).map { _ in letters.randomElement()! })
        isHost = true
        connect()
    }

    func joinRoom(code: String) {
        let cleaned = code.uppercased().filter { $0.isLetter && $0.isASCII }
        guard cleaned.count == 4 else {
            errorText = Strings.noRoom
            return
        }
        roomCode = cleaned
        isHost = false
        connect()
    }

    private func connect() {
        errorText = nil
        connecting = true
        friendHere = false
        online = true
        net.connect(code: roomCode, asHost: isHost)
    }

    func startOnlineGame() {
        guard isHost, friendHere else { return }
        net.send(["t": "lvl", "n": selectedLevel])
        beginGame(level: selectedLevel)
    }

    func leaveToMenu() {
        net.disconnect()
        online = false
        connecting = false
        friendHere = false
        scene = nil
        screen = .menu
    }

    // MARK: Game

    private func beginGame(level: Int) {
        let newScene = ParkingScene(size: CGSize(width: 852, height: 393))
        newScene.scaleMode = .resizeFill
        newScene.configure(model: self, online: online, slot: mySlot, isHost: isHost || !online, level: level)
        scene = newScene
        screen = .game
    }

    func send(_ message: [String: Any]) {
        guard online else { return }
        net.send(message)
    }

    func levelCompleted(_ index: Int) {
        if index + 2 > unlockedLevels { unlockedLevels = index + 2 }
    }

    // MARK: Network events

    private func handle(_ message: [String: Any]) {
        guard let type = message["t"] as? String else { return }
        switch type {
        case "welcome":
            connecting = false
            mySlot = message["slot"] as? Int ?? 0
            let peers = message["peers"] as? [Int] ?? []
            friendHere = !peers.isEmpty
            screen = .lobby
        case "join":
            friendHere = true
            scene?.friendJoined()
        case "leave":
            friendHere = false
            scene?.friendLeft()
        case "noroom":
            net.disconnect()
            connecting = false
            online = false
            errorText = Strings.noRoom
            screen = .menu
        case "full":
            net.disconnect()
            connecting = false
            online = false
            errorText = Strings.roomFull
            screen = .menu
        case "lvl":
            let level = message["n"] as? Int ?? 0
            if screen == .game, let scene = scene {
                scene.load(level: level)
            } else {
                beginGame(level: level)
            }
        default:
            scene?.handleNetwork(message)
        }
    }

    private func connectionClosed() {
        guard online else { return }
        connecting = false
        friendHere = false
        if screen == .game {
            scene?.friendLeft()
            online = false
        } else {
            errorText = Strings.connectionLost
            online = false
            screen = .menu
        }
    }
}

// MARK: - Views

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            switch model.screen {
            case .menu:
                MenuView()
            case .lobby:
                LobbyView()
            case .game:
                if let scene = model.scene {
                    SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
                        .ignoresSafeArea()
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

private struct MenuBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.20), Color(red: 0.04, green: 0.05, blue: 0.09)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color(red: 0.95, green: 0.26, blue: 0.27).opacity(0.55))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: -260, y: -120)
            Circle()
                .fill(Color(red: 0.18, green: 0.53, blue: 0.98).opacity(0.55))
                .frame(width: 380, height: 380)
                .blur(radius: 100)
                .offset(x: 280, y: 130)
            Circle()
                .fill(Color(red: 0.98, green: 0.78, blue: 0.22).opacity(0.18))
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .offset(x: 60, y: -160)
            GeometryReader { proxy in
                Path { path in
                    let step: CGFloat = 46
                    var x: CGFloat = 0
                    while x < proxy.size.width {
                        path.move(to: CGPoint(x: x, y: proxy.size.height * 0.78))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                        x += step
                    }
                }
                .stroke(Color.white.opacity(0.06), lineWidth: 3)
            }
        }
        .ignoresSafeArea()
    }
}

private struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }
}

extension View {
    fileprivate func glassCard() -> some View { modifier(GlassCard()) }
}

private struct BigButton: View {
    let title: String
    let systemImage: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.18)))
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .opacity(0.7)
            }
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 1))
            .shadow(color: (colors.first ?? .black).opacity(0.45), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct CarPreview: View {
    var body: some View {
        ZStack {
            Image(uiImage: CarArt.carImage(color: CarArt.playerColors[0], size: CGSize(width: 72, height: 36)))
                .rotationEffect(.degrees(-90))
                .offset(x: -20, y: 4)
                .shadow(color: .black.opacity(0.5), radius: 8, x: 4, y: 8)
            Image(uiImage: CarArt.carImage(color: CarArt.playerColors[1], size: CGSize(width: 72, height: 36)))
                .rotationEffect(.degrees(-80))
                .offset(x: 22, y: -2)
                .shadow(color: .black.opacity(0.5), radius: 8, x: 4, y: 8)
        }
        .frame(width: 96, height: 80)
    }
}

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var code = ""
    @State private var showJoin = false

    var body: some View {
        ZStack {
            MenuBackground()
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 2) {
                        HStack(spacing: 2) {
                            Text("Park")
                                .foregroundStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.52, blue: 0.42), Color(red: 0.92, green: 0.22, blue: 0.24)],
                                                                startPoint: .top, endPoint: .bottom))
                            Text("Park")
                                .foregroundStyle(LinearGradient(colors: [Color(red: 0.50, green: 0.76, blue: 1.0), Color(red: 0.16, green: 0.48, blue: 0.96)],
                                                                startPoint: .top, endPoint: .bottom))
                        }
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                        CarPreview()
                    }
                    Text(Strings.tagline)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Image(systemName: "flag.checkered")
                        Text(Strings.levels)
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 6)
                    LevelPicker()
                }
                .frame(maxWidth: 320, alignment: .leading)
                .glassCard()

                VStack(spacing: 12) {
                    if showJoin {
                        Text(Strings.joinRoom)
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        HStack(spacing: 10) {
                            TextField(Strings.codePlaceholder, text: $code)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.system(size: 26, weight: .heavy, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.12)))
                                .foregroundStyle(.white)
                                .onChange(of: code) { _, newValue in
                                    let filtered = String(newValue.uppercased().filter { $0.isLetter && $0.isASCII }.prefix(4))
                                    if filtered != newValue { code = filtered }
                                }
                            Button {
                                model.joinRoom(code: code)
                            } label: {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 20, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 50)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(code.count == 4 ? Color.green.gradient : Color.gray.gradient))
                            }
                            .buttonStyle(.plain)
                            .disabled(code.count != 4 || model.connecting)
                        }
                        Button(Strings.back) { showJoin = false }
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        BigButton(title: Strings.playSolo, systemImage: "car.fill",
                                  colors: [Color(red: 1.0, green: 0.55, blue: 0.32), Color(red: 0.92, green: 0.28, blue: 0.24)]) { model.playSolo() }
                        BigButton(title: Strings.createRoom, systemImage: "person.2.fill",
                                  colors: [Color(red: 0.36, green: 0.66, blue: 1.0), Color(red: 0.16, green: 0.42, blue: 0.92)]) { model.createRoom() }
                        BigButton(title: Strings.joinRoom, systemImage: "number",
                                  colors: [Color(red: 0.36, green: 0.82, blue: 0.56), Color(red: 0.14, green: 0.58, blue: 0.40)]) { showJoin = true }
                    }
                    if model.connecting {
                        ProgressView(Strings.connecting)
                            .tint(.white)
                            .foregroundStyle(.white)
                    }
                    if let error = model.errorText {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.55))
                    }
                }
                .frame(width: 236)
                .glassCard()
            }
            .padding(.horizontal, 16)
        }
    }
}

struct LevelPicker: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(44), spacing: 8), count: 5)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(0..<Levels.all.count, id: \.self) { index in
                let unlocked = index < model.unlockedLevels
                Button {
                    model.selectedLevel = index
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(model.selectedLevel == index ? Color.white : Color.white.opacity(unlocked ? 0.14 : 0.05))
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(unlocked ? 0.22 : 0.08), lineWidth: 1)
                        if unlocked {
                            Text("\(index + 1)")
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(model.selectedLevel == index ? Color.black : Color.white)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    .frame(width: 44, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(!unlocked)
            }
        }
    }
}

struct LobbyView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            MenuBackground()
            VStack(spacing: 14) {
                Text(Strings.roomCode.uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                Text(model.roomCode)
                    .font(.system(size: 64, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .tracking(10)
                    .textSelection(.enabled)
                if model.isHost {
                    Text(Strings.shareCode)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.friendHere ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(model.friendHere ? Strings.friendJoined : Strings.waitingFriend)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                if model.isHost {
                    HStack(spacing: 10) {
                        Text("\(Strings.startLevel): \(model.selectedLevel + 1)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                        Stepper("", value: $model.selectedLevel, in: 0...(model.unlockedLevels - 1))
                            .labelsHidden()
                    }
                    Button(Strings.start) { model.startOnlineGame() }
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 16)
                            .fill(model.friendHere ? Color.green.gradient : Color.gray.gradient))
                        .foregroundStyle(.white)
                        .disabled(!model.friendHere)
                } else {
                    Text(Strings.waitingHost)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Button(Strings.leave) { model.leaveToMenu() }
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)
            }
            .frame(minWidth: 380)
            .glassCard()
        }
    }
}

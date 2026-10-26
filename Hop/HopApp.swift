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
        LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.30), Color(red: 0.08, green: 0.10, blue: 0.16)],
                       startPoint: .top, endPoint: .bottom)
            .overlay(
                GeometryReader { proxy in
                    Path { path in
                        let step: CGFloat = 70
                        var x: CGFloat = -proxy.size.height
                        while x < proxy.size.width {
                            path.move(to: CGPoint(x: x, y: proxy.size.height))
                            path.addLine(to: CGPoint(x: x + proxy.size.height * 0.5, y: 0))
                            x += step
                        }
                    }
                    .stroke(Color.white.opacity(0.05), lineWidth: 2)
                }
            )
            .ignoresSafeArea()
    }
}

private struct BigButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16).fill(color.gradient))
            .shadow(color: color.opacity(0.4), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @State private var code = ""
    @State private var showJoin = false

    var body: some View {
        ZStack {
            MenuBackground()
            HStack(spacing: 36) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Park")
                            .foregroundStyle(Color(red: 0.98, green: 0.36, blue: 0.30))
                        Text("Park")
                            .foregroundStyle(Color(red: 0.30, green: 0.62, blue: 1.0))
                    }
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    Text(Strings.tagline)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(Strings.levels)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 10)
                    LevelPicker()
                }
                .frame(maxWidth: 360, alignment: .leading)

                VStack(spacing: 12) {
                    if showJoin {
                        HStack(spacing: 10) {
                            TextField(Strings.codePlaceholder, text: $code)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.system(size: 26, weight: .heavy, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.12)))
                                .foregroundStyle(.white)
                                .onChange(of: code) { _, newValue in
                                    let filtered = String(newValue.uppercased().filter { $0.isLetter && $0.isASCII }.prefix(4))
                                    if filtered != newValue { code = filtered }
                                }
                            Button(Strings.join) { model.joinRoom(code: code) }
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.green.gradient))
                                .foregroundStyle(.white)
                                .disabled(code.count != 4 || model.connecting)
                        }
                        Button(Strings.back) { showJoin = false }
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        BigButton(title: Strings.playSolo, systemImage: "car.fill",
                                  color: Color(red: 0.98, green: 0.45, blue: 0.25)) { model.playSolo() }
                        BigButton(title: Strings.createRoom, systemImage: "person.2.fill",
                                  color: Color(red: 0.25, green: 0.55, blue: 0.98)) { model.createRoom() }
                        BigButton(title: Strings.joinRoom, systemImage: "number",
                                  color: Color(red: 0.30, green: 0.70, blue: 0.45)) { showJoin = true }
                    }
                    if model.connecting {
                        ProgressView(Strings.connecting)
                            .tint(.white)
                            .foregroundStyle(.white)
                    }
                    if let error = model.errorText {
                        Text(error)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.5))
                    }
                }
                .frame(width: 280)
            }
            .padding(.horizontal, 40)
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
                        RoundedRectangle(cornerRadius: 10)
                            .fill(model.selectedLevel == index ? Color.white : Color.white.opacity(unlocked ? 0.14 : 0.05))
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
        }
    }
}

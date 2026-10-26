import SwiftUI
import SpriteKit
import SceneKit

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
    @Published var results: ResultsInfo?

    enum OnlineMode: String {
        case park
        case race
    }
    /// What the room plays; chosen by the host in the lobby.
    @Published var onlineMode: OnlineMode = .race

    /// Slowly orbiting 3D lot shown behind the menu and lobby.
    let menuWorld: World3D = {
        let world = World3D()
        world.setupShowcase()
        return world
    }()

    private(set) var online = false
    private(set) var mySlot = 0
    private(set) var scene: ParkingScene?
    private(set) var world: World3D?
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

    func playCity() {
        online = false
        mySlot = 0
        friendHere = false
        beginGame(level: Levels.cityBase)
    }

    func playRace() {
        online = false
        mySlot = 0
        friendHere = false
        beginGame(level: Levels.raceBase)
    }

    func setOnlineMode(_ mode: OnlineMode) {
        onlineMode = mode
        if isHost { net.send(["t": "mode", "m": mode.rawValue]) }
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
        let start = onlineMode == .race ? Levels.raceBase : Levels.cityBase
        net.send(["t": "lvl", "n": start])
        beginGame(level: start)
    }

    func leaveToMenu() {
        results = nil
        net.disconnect()
        online = false
        connecting = false
        friendHere = false
        scene = nil
        world = nil
        screen = .menu
    }

    // MARK: Game

    private func beginGame(level: Int) {
        let newWorld = World3D()
        let newScene = ParkingScene(size: CGSize(width: 852, height: 393))
        newScene.scaleMode = .resizeFill
        newScene.configure(model: self, world: newWorld, online: online, slot: mySlot, isHost: isHost || !online, level: level)
        world = newWorld
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

    // MARK: Records

    nonisolated static func stars(forHits hits: Int) -> Int {
        hits == 0 ? 3 : (hits <= 2 ? 2 : 1)
    }

    func stars(for level: Int) -> Int {
        (UserDefaults.standard.dictionary(forKey: "pp.stars") as? [String: Int])?[String(level)] ?? 0
    }

    func bestTime(for level: Int) -> Double? {
        (UserDefaults.standard.dictionary(forKey: "pp.best") as? [String: Double])?[String(level)]
    }

    /// Saves stars and time for a level; returns true when the time is a new best.
    @discardableResult
    func record(level: Int, time: Double, hits: Int) -> Bool {
        let key = String(level)
        var stars = UserDefaults.standard.dictionary(forKey: "pp.stars") as? [String: Int] ?? [:]
        stars[key] = max(stars[key] ?? 0, AppModel.stars(forHits: hits))
        UserDefaults.standard.set(stars, forKey: "pp.stars")
        var best = UserDefaults.standard.dictionary(forKey: "pp.best") as? [String: Double] ?? [:]
        let isNewBest = best[key].map { time < $0 } ?? true
        if isNewBest { best[key] = time }
        UserDefaults.standard.set(best, forKey: "pp.best")
        objectWillChange.send()
        return isNewBest
    }

    func retryLevel() {
        results = nil
        scene?.retryLevel()
    }

    func nextLevel() {
        results = nil
        scene?.nextLevel()
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
            if isHost { net.send(["t": "mode", "m": onlineMode.rawValue]) }
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
        case "mode":
            if let raw = message["m"] as? String, let mode = OnlineMode(rawValue: raw) { onlineMode = mode }
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
                if let scene = model.scene, let world = model.world {
                    ZStack {
                        SceneKitView(world: world)
                            .ignoresSafeArea()
                        SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.allowsTransparency])
                            .ignoresSafeArea()
                        if let results = model.results {
                            ResultsOverlay(info: results)
                                .id(results.id)
                                .transition(.opacity)
                        }
                    }
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { AudioManager.shared.ensureRunning() }
    }
}

/// SceneKit view that renders the 3D lot under the SpriteKit HUD.
struct SceneKitView: UIViewRepresentable {
    let world: World3D

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = world.scene
        view.pointOfView = world.cameraNode
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isPlaying = true
        view.isUserInteractionEnabled = false
        view.backgroundColor = UIColor(red: 0.30, green: 0.50, blue: 0.30, alpha: 1)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if uiView.scene !== world.scene {
            uiView.scene = world.scene
            uiView.pointOfView = world.cameraNode
        }
    }
}


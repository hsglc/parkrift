import SwiftUI
import SpriteKit
import SceneKit
import StoreKit

@main
struct ParkriftApp: App {
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
        case garage
        case game
    }

    /// Where the garage leads: straight into a level, or back to the online lobby.
    enum GarageExit: Equatable {
        case play(level: Int)
        case lobby
        case menu
    }
    @Published var garageExit: GarageExit = .play(level: 0)

    /// The player's car from the garage (saved, and sent to the friend online).
    @Published var carChoice = CarChoice.saved {
        didSet {
            guard carChoice != oldValue else { return }
            CarChoice.saved = carChoice
            if online { net.send(carChoice.message) }
        }
    }
    /// The friend's car, once their choice arrives.
    private(set) var friendCar: CarChoice?

    @Published var screen: Screen = .menu
    @Published var roomCode = ""
    @Published var isHost = false
    @Published var friendHere = false
    @Published var connecting = false
    @Published var errorText: String?
    @Published var selectedLevel = 0
    @Published var results: ResultsInfo?
    /// Loading screen over the game until the world is built and the countdown can start.
    @Published var loading = false
    private(set) var loadingLevel = 0

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
        World3D.prewarmCars()
        CarModels.prewarmRetroTextures()
        PedestrianModels.preload()
        // Car models load in the background; then the garage studio is built while the menu is idle
        CarModels.preload { [weak self] in
            GarageStage.prewarm(using: self?.menuWorld.renderer)
        }
        NotificationCenter.default.addObserver(forName: .languageChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
        net.onMessage = { [weak self] message in self?.handle(message) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { GameCenter.authenticate() }
        net.onClose = { [weak self] _ in self?.connectionClosed() }
    }

    // MARK: Menu actions

    func playSolo() { openGarage(.play(level: selectedLevel)) }

    func playCity() { openGarage(.play(level: Levels.cityBase)) }

    func playRace() { openGarage(.play(level: Levels.raceBase)) }

    /// Mode chosen: pick the car first.
    func openGarage(_ exit: GarageExit) {
        garageExit = exit
        screen = .garage
    }

    /// Garage confirmed: start the chosen level, or go back to the lobby.
    func leaveGarage(confirmed: Bool) {
        switch garageExit {
        case .lobby:
            screen = online ? .lobby : .menu
        case .menu:
            screen = .menu
        case .play(let level):
            guard confirmed else {
                screen = .menu
                return
            }
            online = false
            mySlot = 0
            friendHere = false
            beginGame(level: level)
        }
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
        friendCar = nil
        online = true
        net.connect(code: roomCode, asHost: isHost)
    }

    // MARK: Quick match

    /// Looking for a random opponent (no server change needed: players meet in rooms whose codes
    /// come from the clock, so everyone searching in the same minute tries the same few rooms).
    @Published var matchmaking = false
    private var matchCandidates: [(code: String, host: Bool)] = []
    private var matchTimeout: DispatchWorkItem?

    private static func matchCode(window: Int, index: Int) -> String {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        var value = UInt64(window) &* 2_654_435_761 &+ UInt64(index) &* 40_503
        var code = "Q"
        for _ in 0..<3 {
            code.append(letters[Int(value % UInt64(letters.count))])
            value /= UInt64(letters.count)
        }
        return code
    }

    func quickMatch() {
        let window = Int(Date().timeIntervalSince1970 / 20)
        // First join anyone already waiting (the last minute), then wait in a room of our own
        var candidates: [(String, Bool)] = []
        for w in [window - 2, window - 1, window] {
            for i in 0..<3 { candidates.append((AppModel.matchCode(window: w, index: i), false)) }
        }
        for i in 0..<3 { candidates.append((AppModel.matchCode(window: window, index: i), true)) }
        matchCandidates = candidates.map { (code: $0.0, host: $0.1) }
        matchmaking = true
        errorText = nil
        tryNextMatch()
    }

    private func tryNextMatch() {
        guard matchmaking else { return }
        guard !matchCandidates.isEmpty else {
            stopMatchmaking(error: Strings.noOpponent)
            return
        }
        let next = matchCandidates.removeFirst()
        roomCode = next.code
        isHost = next.host
        connect()
    }

    private func stopMatchmaking(error: String?) {
        matchmaking = false
        matchTimeout?.cancel()
        matchTimeout = nil
        if let error = error {
            net.disconnect()
            connecting = false
            online = false
            errorText = error
            screen = .menu
            // Nobody to play with: a solo race against the traffic instead of an empty wait
            if error == Strings.noOpponent {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                    guard let self = self, self.screen == .menu, !self.connecting else { return }
                    self.errorText = nil
                    self.playRace()
                }
            }
        }
    }

    func startOnlineGame() {
        guard isHost, friendHere else { return }
        let start = onlineMode == .race ? Levels.raceBase : Levels.cityBase
        net.send(["t": "lvl", "n": start])
        beginGame(level: start)
    }

    func leaveToMenu() {
        matchmaking = false
        matchTimeout?.cancel()
        results = nil
        loading = false
        Task { @MainActor in AudioManager.shared.stopLoops() }
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
        // Show the loading screen first, then build the world on the next turn of the main loop
        // (building it blocks the main thread, which used to leave a black screen).
        loadingLevel = level
        loadingStartedAt = Date()
        loading = true
        scene = nil
        world = nil
        screen = .game
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self = self, self.screen == .game, self.scene == nil else { return }
            let newWorld = World3D()
            let newScene = ParkingScene(size: CGSize(width: 852, height: 393))
            newScene.scaleMode = .resizeFill
            newScene.configure(model: self, world: newWorld, online: self.online, slot: self.mySlot,
                               isHost: self.isHost || !self.online, level: level)
            // scene/world are not @Published: tell SwiftUI so the game views get created
            self.objectWillChange.send()
            self.world = newWorld
            self.scene = newScene
        }
    }

    /// Fades the loading screen in over the running game, then runs `build` under it (the scene
    /// hides it again through `sceneReady` once the new level is warmed up).
    func showCurtain(level: Int, then build: @escaping () -> Void) {
        loadingLevel = level
        // Between rounds the curtain needs less time than at the first start
        loadingStartedAt = Date().addingTimeInterval(-(AppModel.minimumLoading - 1.0))
        withAnimation(.easeIn(duration: 0.25)) {
            results = nil
            loading = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, self.screen == .game else { return }
            self.world?.setRenderingPaused(false)
            build()
        }
    }

    /// The loading screen always stays at least this long, whatever the mode.
    static let minimumLoading: TimeInterval = 2.0
    private var loadingStartedAt = Date()

    /// Called when the world is built; hides the loading screen once it has been up for
    /// `minimumLoading`, then `start` begins the countdown.
    func sceneReady(then start: @escaping () -> Void) {
        // At least a few frames with the chase camera in place before the loading screen fades
        let remaining = max(0.25, AppModel.minimumLoading - Date().timeIntervalSince(loadingStartedAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self = self, self.screen == .game else { return }
            withAnimation(.easeOut(duration: 0.35)) { self.loading = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { start() }
        }
    }

    func send(_ message: [String: Any]) {
        guard online else { return }
        net.send(message)
    }

    func levelCompleted(_ index: Int) {
        if index + 2 > unlockedLevels { unlockedLevels = index + 2 }
    }

    // MARK: Coins, cars, daily tasks

    var coins: Int { Progression.coins }

    /// Pays a finished round; asks for a rating after a good moment now and then.
    func finishRun(_ stats: RunStats) -> RunReward {
        let reward = Progression.reward(for: stats)
        objectWillChange.send()
        // Leaderboards
        let defaults = UserDefaults.standard
        if stats.won == true {
            defaults.set(defaults.integer(forKey: "pp.wins") + 1, forKey: "pp.wins")
            GameCenter.submit(defaults.integer(forKey: "pp.wins"), to: GameCenter.totalWins)
        }
        if stats.driftPoints > defaults.integer(forKey: "pp.bestDrift") {
            defaults.set(stats.driftPoints, forKey: "pp.bestDrift")
        }
        GameCenter.submit(defaults.integer(forKey: "pp.bestDrift"), to: GameCenter.bestDrift)
        GameCenter.submit((0..<Levels.all.count).reduce(0) { $0 + stars(for: $1) }, to: GameCenter.totalStars)
        let goodMoment = (stats.solo && stats.finished && stats.stars == 3) || stats.won == true
        if goodMoment { maybeAskForReview() }
        return reward
    }

    func buyCar(_ id: CarModelID) -> Bool {
        let bought = Progression.buy(id)
        objectWillChange.send()
        return bought
    }

    @discardableResult
    func collectGift() -> Int {
        let amount = Progression.collectGift()
        objectWillChange.send()
        return amount
    }

    /// Apple's rating prompt (it shows at most three times a year) after a win, once the player
    /// has finished a few levels, and at most once per app version.
    private func maybeAskForReview() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let key = "pp.reviewAsked"
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: key) != version + "-" + build else { return }
        let finished = (0..<Levels.all.count).filter { stars(for: $0) > 0 }.count
        guard finished >= 3 else { return }
        defaults.set(version + "-" + build, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { return }
            AppStore.requestReview(in: scene)
        }
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
        scene?.retryLevel()
    }

    func nextLevel() {
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
            if matchmaking {
                // Slot 0 waits for an opponent (and starts the game); slot 1 joined someone
                isHost = mySlot == 0
                if isHost {
                    let timeout = DispatchWorkItem { [weak self] in
                        guard let self = self, self.matchmaking, !self.friendHere else { return }
                        self.stopMatchmaking(error: Strings.noOpponent)
                    }
                    matchTimeout = timeout
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timeout)
                } else {
                    stopMatchmaking(error: nil)
                }
            }
            screen = .lobby
            net.send(carChoice.message)
        case "join":
            friendHere = true
            if isHost { net.send(["t": "mode", "m": onlineMode.rawValue]) }
            net.send(carChoice.message)
            scene?.friendJoined()
            if matchmaking && isHost {
                // Matched: start a city race shortly
                stopMatchmaking(error: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.startOnlineGame() }
            }
        case "leave":
            friendHere = false
            scene?.friendLeft()
        case "noroom" where matchmaking, "full" where matchmaking:
            net.disconnect()
            tryNextMatch()
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
        case "car":
            if let choice = CarChoice(message: message) {
                friendCar = choice
                objectWillChange.send()
                scene?.friendCarChanged()
            }
        case "mode":
            if let raw = message["m"] as? String, let mode = OnlineMode(rawValue: raw) { onlineMode = mode }
        case "lvl":
            let level = message["n"] as? Int ?? 0
            if screen == .game, let scene = scene {
                scene.loadBehindCurtain(level: level)
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
    @State private var splash = !PerfSettings.benchmark

    var body: some View {
        ZStack {
            switch model.screen {
            case .menu:
                MenuView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            case .lobby:
                LobbyView()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            case .garage:
                GarageView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .game:
                ZStack {
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
                    // The results card fades in and out instead of popping
                    .animation(.easeOut(duration: 0.3), value: model.results?.id)
                }
                if model.loading {
                    LoadingView(level: model.loadingLevel)
                        .transition(.opacity)
                }
                }
                .transition(.opacity)
            }
            if splash {
                SplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.screen)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            if splash {
                DispatchQueue.main.asyncAfter(deadline: .now() + SplashView.duration) {
                    withAnimation(.easeInOut(duration: 0.45)) { splash = false }
                }
            }
            AudioManager.shared.ensureRunning()
            // Store screenshots (simulator, taken from outside with simctl): stay on a screen
            let args = ProcessInfo.processInfo.arguments
            if PerfSettings.benchmark && args.contains("-staymenu") {
                AudioManager.shared.isMuted = true
                return
            }
            if PerfSettings.benchmark && args.contains("-staygarage") {
                AudioManager.shared.isMuted = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { model.openGarage(.menu) }
                return
            }
            if PerfSettings.benchmark && args.contains("-staylevels") {
                AudioManager.shared.isMuted = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    NotificationCenter.default.post(name: .showLevelsPage, object: nil)
                }
                return
            }
            if PerfSettings.benchmark && model.screen == .menu {
                AudioManager.shared.isMuted = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saveWindowSnapshot(named: "menu") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { model.playRace() }
                // Garage snapshot, then start the race from it
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    saveWindowSnapshot(named: "garage")
                    GarageStage.shared.saveSnapshot(named: "garage3d")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { model.leaveGarage(confirmed: true) }
            }
        }
    }
}

/// SceneKit view that renders the 3D lot under the SpriteKit HUD.
struct SceneKitView: UIViewRepresentable {
    let world: World3D

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = world.scene
        view.pointOfView = world.cameraNode
        world.renderer = view
        if PerfSettings.optimized {
            // Native 3x on Pro phones costs 2.25x the pixels of 2x; 2x MSAA instead of 4x
            view.antialiasingMode = .multisampling2X
            view.contentScaleFactor = min(UIScreen.main.scale, 2)
        } else {
            view.antialiasingMode = .multisampling4X
        }
        view.delegate = FrameMonitor.shared
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
            world.renderer = uiView
        }
    }
}


/// Benchmark helper: saves the key window (SwiftUI content) to Documents/<name>.png.
@MainActor
func saveWindowSnapshot(named name: String) {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
          let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    try? image.pngData()?.write(to: folder.appendingPathComponent(name + ".png"))
}

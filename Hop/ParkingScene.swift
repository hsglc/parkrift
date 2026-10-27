import SpriteKit
import SceneKit
import UIKit

/// Game loop, input, HUD and 2D effects. The world itself is drawn in 3D by `World3D`
/// (a SceneKit view underneath this transparent SpriteKit scene).
final class ParkingScene: SKScene {

    private enum Control: Hashable {
        case left
        case right
        case forward
        case reverse
        case handbrake
    }

    private enum Phase {
        case countdown
        case driving
        case finished
    }

    private enum Gear {
        case drive
        case reverse
    }

    /// Something the car can touch: the lot edge, a level obstacle, or the other player's car.
    private enum Contact: Hashable {
        case bounds
        case obstacle(Int)
        case remoteCar
        case bot(Int)
    }

    // MARK: Configuration

    private weak var model: AppModel?
    private var world: World3D?
    private var localCar: Car3D?
    private var remoteCar: Car3D?
    private var online = false
    private var slot = 0
    private var isHost = true
    private var friendPresent = false
    private var levelIndex = 0
    private var level: LevelDef = Levels.all[0]
    private var isCity: Bool { level.city != nil }
    private var otherSlot: Int { 1 - slot }

    // MARK: Layers

    private var builtSize: CGSize = .zero
    private let fxLayer = SKNode()
    private let hud = SKNode()
    private let controlsLayer = SKNode()
    private let overlay = SKNode()

    // MARK: Nodes

    private var localTag = SKLabelNode()
    private var remoteTag = SKLabelNode()
    private var remoteCheck = SKSpriteNode()
    private var holdRing = SKShapeNode()
    private var levelLabel = SKLabelNode()
    private var timerLabel = SKLabelNode()
    private var hitsLabel = SKLabelNode()
    private var statusLabel = SKLabelNode()
    private var codeLabel = SKLabelNode()
    private var gearLabel = SKLabelNode()
    private var countdownNode = SKNode()
    private var countdownLabel = SKLabelNode()
    private var countdownShadow = SKLabelNode()
    private var menuButton = SKSpriteNode()
    private var resetButton = SKSpriteNode()
    private var soundButton = SKSpriteNode()
    private var soundIcon = SKSpriteNode()
    private var finalButton: SKNode?
    private var leftButton = SKSpriteNode()
    private var rightButton = SKSpriteNode()
    private var steerArc = SKShapeNode()
    private var steerLabel = SKLabelNode()
    private let minimap = SKNode()
    private var mapScale: CGFloat = 0.168
    private let mapRadius: CGFloat = 56
    private var mapContent = SKNode()
    private var targetPointer = SKSpriteNode()

    // Speedometer
    private var speedDial = SKNode()
    private var speedArc = SKShapeNode()
    private var speedLabel = SKLabelNode()
    private var shownSpeed: CGFloat = 0
    private var myMarker = SKShapeNode()
    private var hudLeft: CGFloat = 10
    private var routeLine = SKShapeNode()
    private var botDots: [SKNode] = []

    // Benchmark autopilot
    private let benchmark = PerfSettings.benchmark
    private var autoControls: Set<Control> = []
    private var autoReverse: CGFloat = 0
    private var stuckTime: CGFloat = 0
    private var benchClock: CGFloat = 0
    private var benchRecording = false
    private var benchDone = false
    var levelLoadMilliseconds: Double = 0
    private var finishAnimating = false
    private var finishClock: CGFloat = 0
    private var nitroFiredAt: [Double] = []
    private var detailClock: CGFloat = 0
    private var finishTestPlaced = false
    private var nitroShock = SKSpriteNode()
    private var nitroBanner = SKLabelNode()
    private var finishTestAt: Double = -1
    private var finishCrossAt: Double = -1
    /// While the results card is up the 3D world is neither updated nor drawn.
    private var worldFrozen = false
    /// False until the first level is fully loaded; the countdown waits for it.
    private var ready = false
    private var readyRequested = false
    private var navNode = SKNode()
    private var navArrow = SKSpriteNode()
    private var navLabel = SKLabelNode()

    // City traffic and race
    private var traffic: Traffic?
    private var botCars: [Car3D] = []
    private var botSendClock: TimeInterval = 0
    private var routeClock: CGFloat = 0
    private var route: [CGPoint] = []
    private var giveUp: CGFloat = 20
    private var myWins = 0
    private var friendWins = 0
    private var friendMarker = SKShapeNode()
    private var policeMarker = SKShapeNode()
    private var gasPedal = SKSpriteNode()
    private var hornButton = SKSpriteNode()

    // Nitro
    private var nitro: CGFloat = 0.5          // tank 0...1
    private var boostTime: CGFloat = 0        // seconds of boost left
    private var boostVisual: CGFloat = 0      // eased 0...1 for effects
    private var remoteBoost = false
    private var boostDuration: CGFloat = 3.0
    private var nitroFillTime: CGFloat = 10
    /// Nitro push (units/s²) for the chosen car.
    private var nitroPush: CGFloat = 300
    private var nitroButton = SKSpriteNode()
    private var nitroIcon = SKSpriteNode()
    private var nitroRing = SKShapeNode()
    private var speedLines: [(sprite: SKSpriteNode, angle: CGFloat, radius: CGFloat)] = []
    private var boostTint = SKSpriteNode()
    private var isBoosting: Bool { boostTime > 0 }
    private var lastHorn: TimeInterval = -10
    private var newBest = false
    private let advanceDelay: TimeInterval = 4.5
    private var reversePedal = SKSpriteNode()
    private var activeTouches: [UITouch: Control] = [:]
    private var wheelStartX: [UITouch: CGFloat] = [:]
    private var dotTexture = SKTexture()

    // MARK: Driving model (1 world unit ≈ 10 cm)

    private let wheelBase: CGFloat = 26
    private var maxSteer: CGFloat = 0.64
    private var steerRate: CGFloat = 2.6
    private var engineAccel: CGFloat = 150
    private let reverseAccel: CGFloat = 95
    private let brakeDecel: CGFloat = 360
    private let rolling: CGFloat = 22
    private let airDrag: CGFloat = 0.22
    private var maxForward: CGFloat = 150
    private let maxReverse: CGFloat = 70
    private let creepSpeed: CGFloat = 12

    // What this round earned (paid as coins at the end)
    private var runDriftPoints = 0
    private var runNearMisses = 0
    private var runEscapes = 0
    private var runTopSpeed = 0

    // Gearbox: gives the engine its rising and falling note and the pull its steps
    private var gearIndex = 1
    private var rpm: CGFloat = 900
    private var shiftCut: CGFloat = 0
    private var lastThrottle = false
    private let idleRPM: CGFloat = 900
    private let redline: CGFloat = 7000
    /// Top speed of each gear as a share of the car's top speed (5th only with nitro).
    private let gearTops: [CGFloat] = [0.3, 0.52, 0.75, 1.08, 1.8]
    /// How far the tyres are past their grip in a corner (0...1).
    private var understeer: CGFloat = 0

    private var carPosition = CGPoint.zero
    private var heading: CGFloat = 0
    private var velocity: CGFloat = 0
    private var steer: CGFloat = 0
    private var wheelInput: CGFloat = 0
    private var gear: Gear = .drive
    private var engaged = false
    private var braking = false
    private var longitudinalAccel: CGFloat = 0
    private var lateralAccel: CGFloat = 0
    private var skidClock: CGFloat = 0
    private var smokeClock: CGFloat = 0
    private var obstacleBoxes: [OBB] = []

    // Remote car
    private var remotePosition = CGPoint.zero
    private var remoteHeading: CGFloat = 0
    private var remoteSteer: CGFloat = 0
    private var remoteBraking = false
    private var remoteReversing = false
    private var remoteTarget: (CGPoint, CGFloat)?

    /// Received states of the other car, timed by the sender's clock, played back slightly in
    /// the past so there are always two states to blend between (smooth despite network jitter).
    private struct RemoteSnapshot {
        let time: TimeInterval
        let position: CGPoint
        let heading: CGFloat
        let velocity: CGFloat
    }
    private var remoteSnapshots: [RemoteSnapshot] = []
    private var clockOffset: TimeInterval?
    private let interpolationDelay: TimeInterval = 0.14

    // MARK: Level state

    private var phase: Phase = .countdown
    private var countdown: CGFloat = 3
    private var elapsed: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0
    private var sendClock: TimeInterval = 0
    private var hits = 0
    private var lastHitAt: TimeInterval = -10
    // Drift: the car can point away from where it travels; points turn into nitro
    private var travelHeading: CGFloat = 0
    /// Turn rate of the body (rad/s); has inertia while drifting.
    private var yawSpeed: CGFloat = 0
    /// Which way the tail went out (+1: car turning left), and how long the slide has been small.
    private var driftSide: CGFloat = 1
    private var driftCalm: CGFloat = 0
    private var drifting = false
    private var driftScore: CGFloat = 0
    private var driftClock: CGFloat = 0
    private var lastDriftEnd: TimeInterval = -10
    private var lastDriftScore: CGFloat = 0
    private var driftSmokeClock: CGFloat = 0
    private var driftButton = SKSpriteNode()
    private var driftLabel = SKLabelNode()
    private var shownDriftPoints = -1
    // Jumps off the alley ramps
    private var airTime: CGFloat = 0
    private var airDuration: CGFloat = 0
    private var airPeak: CGFloat = 0
    private var rampCooldown: TimeInterval = -10
    // Near misses, loose props, police
    private var nearMissAt: [Int: TimeInterval] = [:]
    private var streetProps: StreetProps?
    private var police: PoliceChase?
    private var trail: [CGPoint] = []
    private var trailClock: CGFloat = 0
    /// Last drawn HUD values (shapes and labels only change when these do).
    private var shownNitroStep = -2
    private var shownSteerStep = -999
    private var shownSpeedStep = -2
    private var lastShownKmh = -1
    /// Pre-drawn letters of the finish titles.
    private var finishGlyphs: [String: [(texture: SKTexture, advance: CGFloat)]] = [:]
    /// Crash reaction (arcade racers): a shove away from what we hit and a spin that fade out.
    private var crashShove = CGVector.zero
    private var crashSpin: CGFloat = 0
    private var parkHold: CGFloat = 0
    private var localParked = false
    private var localTime: Double = 0
    private var remoteParked = false
    private var remoteTime: Double = 0
    private var remoteHits = 0
    private var resultsShown = false
    private var advanceScheduled = false

    // MARK: Haptics and sound

    private lazy var bumpHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private lazy var tickHaptic = UIImpactFeedbackGenerator(style: .light)
    private lazy var notifyHaptic = UINotificationFeedbackGenerator()
    private var audio: AudioManager { AudioManager.shared }

    // MARK: Setup

    func configure(model: AppModel, world: World3D, online: Bool, slot: Int, isHost: Bool, level: Int) {
        self.model = model
        self.world = world
        self.online = online
        self.slot = online ? slot : 0
        self.isHost = isHost
        self.friendPresent = online
        self.levelIndex = Levels.clamp(level)
        let mine = model.carChoice
        localCar = world.makeCar(color: mine.color, style: .racer, model: mine.model)
        let friend = model.friendCar ?? CarChoice.friendDefault
        remoteCar = world.makeCar(color: friend.color, style: .racer, model: friend.model)
        remoteChoice = friend
        // The chosen car's driving character (small differences so online races stay fair)
        let spec = mine.spec
        maxForward = 150 * spec.topSpeed
        engineAccel = 150 * spec.acceleration
        maxSteer = 0.64 * min(1.1, spec.steering)
        steerRate = 2.6 * spec.steering
        nitroPush = 300 * spec.nitroPower
        nitroFillTime = 10 * spec.nitroFill
    }

    private var remoteChoice = CarChoice.friendDefault

    /// The friend picked another car (their choice can arrive after the world is built).
    func friendCarChanged() {
        guard let world = world, let choice = model?.friendCar, choice != remoteChoice else { return }
        remoteChoice = choice
        let hidden = remoteCar?.isHidden ?? true
        remoteCar?.node.removeFromParentNode()
        remoteCar = world.makeCar(color: choice.color, style: .racer, model: choice.model)
        remoteCar?.isHidden = hidden
    }

    override func didMove(to view: SKView) {
        stage("scene attached \(Int(size.width))x\(Int(size.height))")
        view.isMultipleTouchEnabled = true
        view.allowsTransparency = true
        backgroundColor = .clear
        audio.ensureRunning()
        audio.setMusicVolume(0.32)
        buildIfNeeded()
    }

    override func willMove(from view: SKView) {
        audio.setMotor(active: false, rpm: 0, load: 0)
        audio.setMusicVolume(0.5)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        buildIfNeeded()
    }

    private func buildIfNeeded() {
        guard view != nil, size.width > 1, size.height > 1, size != builtSize else { return }
        builtSize = size
        build()
    }

    private var insets: UIEdgeInsets { view?.safeAreaInsets ?? .zero }

    private func build() {
        stage("build")
        removeAllChildren()
        for layer in [fxLayer, hud, controlsLayer, overlay] {
            layer.removeAllChildren()
            layer.removeAllActions()
        }
        activeTouches.removeAll()
        wheelStartX.removeAll()

        addChild(fxLayer)
        addChild(hud)
        addChild(controlsLayer)
        addChild(overlay)
        fxLayer.zPosition = 50
        hud.zPosition = 100
        controlsLayer.zPosition = 110
        overlay.zPosition = 200

        world?.fit(size: size, insets: insets, topReserved: 50)
        dotTexture = CarArt.dot()

        let vignette = SKSpriteNode(texture: CarArt.vignette(size: size))
        vignette.size = size
        vignette.position = CGPoint(x: size.width / 2, y: size.height / 2)
        vignette.alpha = 0.55
        vignette.zPosition = 40
        addChild(vignette)

        localTag = makeLabel(Strings.you, size: 12, color: .white)
        localTag.isHidden = true
        fxLayer.addChild(localTag)
        remoteTag = makeLabel(Strings.friend, size: 12, color: UIColor.white.withAlphaComponent(0.85))
        fxLayer.addChild(remoteTag)
        remoteCheck = SKSpriteNode(texture: CarArt.symbol("checkmark.circle.fill", pointSize: 28,
                                                          color: UIColor(red: 0.4, green: 1, blue: 0.6, alpha: 1)))
        remoteCheck.size = CGSize(width: 24, height: 24)
        fxLayer.addChild(remoteCheck)

        holdRing = SKShapeNode()
        holdRing.strokeColor = UIColor(red: 0.35, green: 0.95, blue: 0.55, alpha: 1)
        holdRing.lineWidth = 4
        holdRing.lineCap = .round
        holdRing.glowWidth = 2
        fxLayer.addChild(holdRing)

        buildHUD()
        buildControls()
        // Render the big banner fonts once so the first NITRO!/FINISH! does not stall a frame
        for (text, fontSize) in [(Strings.nitroGo, CGFloat(34)), (Strings.finishBig, CGFloat(76)), ("0123456789.s", CGFloat(22))] {
            let warm = makeLabel(text, size: fontSize, color: .white)
            warm.alpha = 0.01
            warm.position = CGPoint(x: size.width / 2, y: size.height / 2)
            hud.addChild(warm)
            warm.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
        }
        load(level: levelIndex)
    }

    private func makeLabel(_ text: String, size fontSize: CGFloat, color: UIColor, font: String = "AvenirNext-Heavy") -> SKLabelNode {
        let label = SKLabelNode(fontNamed: font)
        label.text = text
        label.fontSize = fontSize
        label.fontColor = color
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        return label
    }

    private func makeGlass(width: CGFloat, height: CGFloat, corner: CGFloat? = nil) -> SKSpriteNode {
        let glass = SKSpriteNode(texture: CarArt.glass(size: CGSize(width: width, height: height), corner: corner ?? height / 2))
        glass.size = CGSize(width: width, height: height)
        return glass
    }

    private func makeIcon(_ name: String, size: CGFloat, color: UIColor = .white) -> SKSpriteNode {
        let texture = CarArt.symbol(name, pointSize: size * 1.6, color: color)
        let icon = SKSpriteNode(texture: texture)
        let textureSize = texture.size()
        let aspect = textureSize.height > 0 ? textureSize.width / textureSize.height : 1
        icon.size = CGSize(width: size * aspect, height: size)
        return icon
    }

    private func buildHUD() {
        let top = size.height - 24
        let left = max(insets.left, 10)
        let right = max(insets.right, 10)

        menuButton = makeGlass(width: 40, height: 40)
        menuButton.position = CGPoint(x: left + 24, y: top)
        menuButton.addChild(makeIcon("xmark", size: 15))
        hud.addChild(menuButton)

        resetButton = makeGlass(width: 40, height: 40)
        resetButton.position = CGPoint(x: left + 70, y: top)
        resetButton.addChild(makeIcon("arrow.counterclockwise", size: 17))
        hud.addChild(resetButton)

        soundButton = makeGlass(width: 40, height: 40)
        soundButton.position = CGPoint(x: left + 116, y: top)
        hud.addChild(soundButton)
        refreshSoundIcon()

        let center = makeGlass(width: 330, height: 38)
        center.position = CGPoint(x: size.width / 2 + 40, y: top)
        hud.addChild(center)
        levelLabel = makeLabel("", size: 14, color: .white, font: "AvenirNext-Bold")
        levelLabel.horizontalAlignmentMode = .left
        levelLabel.position = CGPoint(x: -150, y: 0)
        center.addChild(levelLabel)
        let stopwatch = makeIcon("stopwatch.fill", size: 15, color: UIColor(red: 1, green: 0.82, blue: 0.36, alpha: 1))
        stopwatch.position = CGPoint(x: 92, y: 0)
        center.addChild(stopwatch)
        timerLabel = makeLabel("0.0", size: 16, color: UIColor(red: 1, green: 0.86, blue: 0.45, alpha: 1))
        timerLabel.horizontalAlignmentMode = .left
        timerLabel.position = CGPoint(x: 104, y: 0)
        center.addChild(timerLabel)

        let bumps = makeGlass(width: 84, height: 38)
        bumps.position = CGPoint(x: size.width - right - 46, y: top)
        hud.addChild(bumps)
        let warning = makeIcon("exclamationmark.triangle.fill", size: 15, color: UIColor(red: 1, green: 0.62, blue: 0.30, alpha: 1))
        warning.position = CGPoint(x: -18, y: 0)
        bumps.addChild(warning)
        hitsLabel = makeLabel("0", size: 17, color: .white)
        hitsLabel.position = CGPoint(x: 12, y: 0)
        bumps.addChild(hitsLabel)

        codeLabel = makeLabel("", size: 11, color: UIColor.white.withAlphaComponent(0.85), font: "AvenirNext-Bold")
        codeLabel.position = CGPoint(x: size.width - right - 46, y: top - 30)
        hud.addChild(codeLabel)

        statusLabel = makeLabel("", size: 16, color: .white)
        statusLabel.position = CGPoint(x: size.width / 2 + 40, y: top - 86)
        hud.addChild(statusLabel)

        minimap.removeAllChildren()
        hudLeft = left
        hud.addChild(minimap)
        buildSpeedometer(left: left, top: top)

        navNode = SKNode()
        navNode.position = CGPoint(x: size.width / 2 + 40, y: top - 46)
        let navGlass = makeGlass(width: 210, height: 40)
        navNode.addChild(navGlass)
        let arrowDisc = SKShapeNode(circleOfRadius: 15)
        arrowDisc.fillColor = UIColor(red: 1.0, green: 0.78, blue: 0.10, alpha: 1)
        arrowDisc.strokeColor = .clear
        arrowDisc.position = CGPoint(x: -84, y: 0)
        navNode.addChild(arrowDisc)
        navArrow = makeIcon("arrow.up", size: 18, color: UIColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1))
        navArrow.position = arrowDisc.position
        navNode.addChild(navArrow)
        navLabel = makeLabel("", size: 15, color: .white)
        navLabel.horizontalAlignmentMode = .left
        navLabel.position = CGPoint(x: -62, y: 0)
        navNode.addChild(navLabel)
        navNode.isHidden = true
        hud.addChild(navNode)

        // Start lights: a small glass capsule high on the screen with the number, three lamps that
        // light one by one and a bar that fills smoothly over the three seconds
        countdownNode = SKNode()
        countdownNode.position = countdownHome
        countdownNode.zPosition = 5
        let pill = SKShapeNode(rect: CGRect(x: -78, y: -33, width: 156, height: 66), cornerRadius: 22)
        pill.fillColor = UIColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 0.6)
        pill.strokeColor = UIColor.white.withAlphaComponent(0.14)
        pill.lineWidth = 1
        countdownNode.addChild(pill)
        countdownPill = pill
        // The outgoing number (slides up) and the incoming one (slides in from below)
        countdownShadow = makeLabel("", size: 30, color: .white, font: "AvenirNext-Bold")
        countdownShadow.position = CGPoint(x: 0, y: 7)
        countdownNode.addChild(countdownShadow)
        countdownLabel = makeLabel("3", size: 30, color: .white, font: "AvenirNext-Bold")
        countdownLabel.position = CGPoint(x: 0, y: 7)
        countdownNode.addChild(countdownLabel)
        countdownLamps = (0..<3).map { index in
            let lamp = SKShapeNode(circleOfRadius: 4.5)
            lamp.position = CGPoint(x: CGFloat(index - 1) * 18, y: -15)
            lamp.fillColor = UIColor.white.withAlphaComponent(0.16)
            lamp.strokeColor = .clear
            countdownNode.addChild(lamp)
            return lamp
        }
        let track = SKSpriteNode(color: UIColor.white.withAlphaComponent(0.1), size: CGSize(width: 124, height: 3))
        track.position = CGPoint(x: 0, y: -26)
        countdownNode.addChild(track)
        countdownBar = SKSpriteNode(color: .white, size: CGSize(width: 124, height: 3))
        countdownBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        countdownBar.position = CGPoint(x: -62, y: -26)
        countdownBar.xScale = 0.001
        countdownNode.addChild(countdownBar)
        hud.addChild(countdownNode)
    }

    private var countdownHome: CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.76) }
    private var countdownPill = SKShapeNode()
    private var countdownLamps: [SKShapeNode] = []
    private var countdownBar = SKSpriteNode()
    private var countdownColor = UIColor.white

    private func refreshSoundIcon() {
        soundIcon.removeFromParent()
        soundIcon = makeIcon(audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 15)
        soundButton.addChild(soundIcon)
    }

    private func buildControls() {
        let left = max(insets.left, 12)
        let right = max(insets.right, 12)

        let steerSize = CGSize(width: 82, height: 82)
        let steerAccent = UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1)
        leftButton = SKSpriteNode(texture: CarArt.pedal(size: steerSize, accent: steerAccent))
        leftButton.size = steerSize
        leftButton.position = CGPoint(x: left + steerSize.width / 2 + 8, y: steerSize.height / 2 + 14)
        controlsLayer.addChild(leftButton)
        let leftIcon = makeIcon("arrowtriangle.left.fill", size: 28)
        leftIcon.position = CGPoint(x: -2, y: 4)
        leftButton.addChild(leftIcon)
        rightButton = SKSpriteNode(texture: CarArt.pedal(size: steerSize, accent: steerAccent))
        rightButton.size = steerSize
        rightButton.position = CGPoint(x: leftButton.position.x + steerSize.width + 12, y: leftButton.position.y)
        controlsLayer.addChild(rightButton)
        let rightIcon = makeIcon("arrowtriangle.right.fill", size: 28)
        rightIcon.position = CGPoint(x: 2, y: 4)
        rightButton.addChild(rightIcon)

        // Bar above the buttons showing how far the front wheels are turned
        let barCenter = CGPoint(x: (leftButton.position.x + rightButton.position.x) / 2, y: leftButton.position.y + steerSize.height / 2 + 16)
        let track = SKShapeNode(rect: CGRect(x: -80, y: -3.5, width: 160, height: 7), cornerRadius: 3.5)
        track.fillColor = UIColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 0.55)
        track.strokeColor = UIColor.white.withAlphaComponent(0.2)
        track.position = barCenter
        controlsLayer.addChild(track)
        let tick = SKShapeNode(rect: CGRect(x: -1, y: -6, width: 2, height: 12))
        tick.fillColor = UIColor.white.withAlphaComponent(0.6)
        tick.strokeColor = .clear
        tick.position = barCenter
        controlsLayer.addChild(tick)
        steerArc = SKShapeNode()
        steerArc.fillColor = UIColor(red: 1.0, green: 0.78, blue: 0.10, alpha: 1)
        steerArc.strokeColor = .clear
        steerArc.position = barCenter
        controlsLayer.addChild(steerArc)
        steerLabel = makeLabel("", size: 12, color: UIColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1))
        steerLabel.position = CGPoint(x: barCenter.x, y: barCenter.y + 16)
        controlsLayer.addChild(steerLabel)

        let gasSize = CGSize(width: 68, height: 116)
        gasPedal = SKSpriteNode(texture: CarArt.pedal(size: gasSize, accent: UIColor(red: 0.30, green: 0.85, blue: 0.50, alpha: 1)))
        gasPedal.size = gasSize
        gasPedal.position = CGPoint(x: size.width - right - gasSize.width / 2 - 6, y: gasSize.height / 2 + 14)
        controlsLayer.addChild(gasPedal)
        let gasIcon = makeIcon("arrow.up", size: 18)
        gasIcon.position = CGPoint(x: 0, y: 6)
        gasPedal.addChild(gasIcon)
        let gasText = makeLabel(Strings.forward, size: 10, color: UIColor.white.withAlphaComponent(0.85))
        gasText.position = CGPoint(x: 0, y: -18)
        gasPedal.addChild(gasText)

        let reverseSize = CGSize(width: 68, height: 84)
        reversePedal = SKSpriteNode(texture: CarArt.pedal(size: reverseSize, accent: UIColor(red: 1.0, green: 0.38, blue: 0.32, alpha: 1)))
        reversePedal.size = reverseSize
        reversePedal.position = CGPoint(x: gasPedal.position.x - gasSize.width / 2 - reverseSize.width / 2 - 12,
                                        y: reverseSize.height / 2 + 14)
        controlsLayer.addChild(reversePedal)
        let reverseIcon = makeIcon("arrow.down", size: 16)
        reverseIcon.position = CGPoint(x: 0, y: 2)
        reversePedal.addChild(reverseIcon)
        let reverseText = makeLabel(Strings.reverse, size: 10, color: UIColor.white.withAlphaComponent(0.85))
        reverseText.position = CGPoint(x: 0, y: -20)
        reversePedal.addChild(reverseText)

        hornButton = makeGlass(width: 60, height: 60)
        hornButton.position = CGPoint(x: gasPedal.position.x, y: gasPedal.position.y + gasSize.height / 2 + 38)
        controlsLayer.addChild(hornButton)
        let hornIcon = makeIcon("horn.blast.fill", size: 20, color: UIColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1))
        hornIcon.position = CGPoint(x: 0, y: 6)
        hornButton.addChild(hornIcon)
        let hornText = makeLabel(Strings.horn, size: 9, color: UIColor.white.withAlphaComponent(0.85))
        hornText.position = CGPoint(x: 0, y: -15)
        hornButton.addChild(hornText)

        nitroButton = makeGlass(width: 70, height: 70)
        nitroButton.position = CGPoint(x: reversePedal.position.x - reverseSize.width / 2 - 52, y: 50)
        controlsLayer.addChild(nitroButton)
        let nitroTrack = SKShapeNode(circleOfRadius: 39)
        nitroTrack.strokeColor = UIColor.white.withAlphaComponent(0.18)
        nitroTrack.lineWidth = 5
        nitroTrack.fillColor = .clear
        nitroButton.addChild(nitroTrack)
        nitroRing = SKShapeNode()
        nitroRing.strokeColor = UIColor(red: 0.30, green: 0.85, blue: 1.0, alpha: 1)
        nitroRing.lineWidth = 5
        nitroRing.lineCap = .round
        nitroRing.glowWidth = 2
        nitroButton.addChild(nitroRing)
        nitroIcon = makeIcon("flame.fill", size: 24, color: UIColor(red: 0.35, green: 0.85, blue: 1.0, alpha: 1))
        nitroIcon.position = CGPoint(x: 0, y: 7)
        nitroButton.addChild(nitroIcon)
        let nitroText = makeLabel(Strings.nitro, size: 10, color: .white)
        nitroText.position = CGPoint(x: 0, y: -17)
        nitroButton.addChild(nitroText)

        // Handbrake for drifts, above the nitro button
        driftButton = makeGlass(width: 64, height: 64)
        driftButton.position = CGPoint(x: nitroButton.position.x, y: nitroButton.position.y + 84)
        controlsLayer.addChild(driftButton)
        let driftIcon = makeIcon("car.rear.and.tire.marks", size: 20, color: UIColor(red: 1.0, green: 0.55, blue: 0.25, alpha: 1))
        driftIcon.position = CGPoint(x: 0, y: 6)
        driftButton.addChild(driftIcon)
        let driftText = makeLabel(Strings.driftButton, size: 9, color: .white)
        driftText.position = CGPoint(x: 0, y: -16)
        driftButton.addChild(driftText)
        driftLabel = makeLabel("", size: 26, color: UIColor(red: 1.0, green: 0.62, blue: 0.2, alpha: 1))
        driftLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.8)
        driftLabel.alpha = 0.002
        driftLabel.zPosition = 20
        hud.addChild(driftLabel)

        // Screen effects for the boost
        speedLines.removeAll()
        for _ in 0..<30 {
            let line = SKSpriteNode(texture: CarArt.speedLineTexture)
            line.size = CGSize(width: 3, height: 110)
            line.color = UIColor(red: 0.75, green: 0.92, blue: 1.0, alpha: 1)
            line.colorBlendFactor = 0.6
            line.blendMode = .add
            line.alpha = 0.002
            line.zPosition = 45
            addChild(line)
            speedLines.append((line, CGFloat.random(in: 0...(2 * CGFloat.pi)), CGFloat.random(in: 0...size.width * 0.6)))
        }
        boostTint = SKSpriteNode(texture: CarArt.vignette(size: size))
        boostTint.size = size
        boostTint.position = CGPoint(x: size.width / 2, y: size.height / 2)
        boostTint.color = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        boostTint.colorBlendFactor = 1
        // Effects rest at a nearly invisible alpha instead of 0: SpriteKit skips fully transparent
        // nodes, so their blend pipelines would otherwise be set up on the first nitro
        boostTint.alpha = 0.002
        boostTint.zPosition = 44
        addChild(boostTint)
        nitroShock = SKSpriteNode(texture: CarArt.nitroRingTexture)
        nitroShock.size = CGSize(width: 90, height: 90)
        nitroShock.blendMode = .add
        nitroShock.alpha = 0.002
        nitroShock.position = CGPoint(x: size.width / 2, y: size.height * 0.35)
        nitroShock.zPosition = 46
        addChild(nitroShock)
        nitroBanner = makeLabel(Strings.nitroGo, size: 34, color: UIColor(red: 0.45, green: 0.9, blue: 1.0, alpha: 1))
        nitroBanner.position = CGPoint(x: size.width / 2, y: size.height * 0.62)
        nitroBanner.zPosition = 20
        nitroBanner.alpha = 0.002
        hud.addChild(nitroBanner)
        // Haptic engines start lazily; get them ready so the first bump or nitro does not wait
        bumpHaptic.prepare()
        tickHaptic.prepare()
        notifyHaptic.prepare()

        let gearDisc = makeGlass(width: 36, height: 36)
        gearDisc.position = CGPoint(x: reversePedal.position.x, y: reversePedal.position.y + reverseSize.height / 2 + 26)
        controlsLayer.addChild(gearDisc)
        gearLabel = makeLabel("D", size: 18, color: UIColor(red: 0.45, green: 0.95, blue: 0.6, alpha: 1))
        gearDisc.addChild(gearLabel)
    }

    // MARK: Level loading

    func load(level index: Int) {
        let loadStarted = CACurrentMediaTime()
        defer { levelLoadMilliseconds = (CACurrentMediaTime() - loadStarted) * 1000 }
        levelIndex = Levels.clamp(index)
        level = Levels.level(levelIndex)
        model?.results = nil
        worldFrozen = false
        guard builtSize != .zero, let world = world else { return }
        overlay.removeAllChildren()
        finalButton = nil
        obstacleBoxes = level.obstacles.map { $0.box }
        let spotSlots = friendPresent ? [slot, otherSlot] : [slot]
        world.load(level: level, spotSlots: spotSlots, mySlot: slot)
        setupBonuses()
        // Only under the loading screen (later rounds load in view)
        if level.city != nil && !ready { world.beginWarmupSweep() }
        if level.race {
            // Draws once with the plate's fonts so the finish moment does not lay out glyphs cold
            // Letters and chips of the finish title are drawn now, so the finish starts without a hitch
            for title in [Strings.youWon.uppercased(), Strings.finishBig, Strings.parkedBig] where finishGlyphs[title] == nil {
                finishGlyphs[title] = CarArt.titleGlyphs(title, size: 74)
            }
            _ = CarArt.statChip(icon: "stopwatch.fill", text: "0.0 s", accent: .white)
            _ = CarArt.finishVignette
            _ = CarArt.finishBand
            // The title's shine uses a crop node: draw one once so its mask pass is ready
            let warmCrop = SKCropNode()
            let warmMask = SKSpriteNode(texture: CarArt.sheenTexture)
            warmMask.size = CGSize(width: 8, height: 8)
            warmCrop.maskNode = warmMask
            let warmShine = SKSpriteNode(texture: CarArt.sheenTexture)
            warmShine.size = CGSize(width: 8, height: 8)
            warmShine.blendMode = .add
            warmCrop.addChild(warmShine)
            warmCrop.alpha = 0.01
            warmCrop.position = CGPoint(x: size.width / 2, y: size.height / 2)
            hud.addChild(warmCrop)
            warmCrop.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
        }
        defer {
            stage("level loaded")
            world.warmUp { [weak self] in
                self?.stage("warm-up done")
                self?.becomeReady()
            }
            // Never wait on the GPU warm-up forever
            if !ready {
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                    self?.stage("warm-up timeout")
                    self?.becomeReady()
                }
            }
        }

        botCars.forEach { $0.node.removeFromParentNode() }
        botCars.removeAll()
        traffic = nil
        if let city = level.city {
            let newTraffic = Traffic(map: city, starts: level.bots, seed: UInt64(levelIndex * 31 + 7))
            traffic = newTraffic
            for (index, bot) in newTraffic.bots.enumerated() {
                botCars.append(world.makeCar(color: CarArt.parkedColors[bot.tint % CarArt.parkedColors.count],
                                             style: CarStyle(rawValue: index % 3) ?? .sedan, variety: index &* 7 &+ bot.tint))
            }
        }
        // People on the sidewalks (each player simulates their own: they are scenery that reacts)
        pedestrians = nil
        pedestrianNodes.removeAll()
        pedestrianLooks.removeAll()
        if let city = level.city {
            let people = PedestrianSystem(map: city, count: 44, seed: UInt64(levelIndex * 131 + 5))
            pedestrians = people
            for _ in people.people {
                pedestrianNodes.append(world.addPedestrianNode())
                pedestrianLooks.append(-1)
            }
            updatePedestrianNodes()
        }
        // Arcade extras of the level
        streetProps = level.city != nil ? world.addProps(level.props) : nil
        police = nil
        remotePolice = nil
        remotePoliceTarget = nil
        policeCooldownUntil = 0
        if policeBanner.parent != nil {
            policeBanner.alpha = 0.002
            policeEdges.forEach { $0.alpha = 0.002 }
        }
        trail.removeAll()
        nearMissAt.removeAll()
        runDriftPoints = 0
        runNearMisses = 0
        runEscapes = 0
        runTopSpeed = 0
        drifting = false
        driftScore = 0
        lastDriftScore = 0
        airTime = 0
        shownDriftPoints = -1
        driftLabel.alpha = 0.002
        localCar?.setHeadlights(level.city != nil && level.weather == .night)
        audio.setLoop("rain", volume: level.city != nil && level.weather == .rain ? 0.35 : 0)
        audio.setLoop("siren", volume: 0)
        audio.setLoop("skid", volume: 0)
        route = []
        routeClock = 0
        giveUp = 20
        if levelIndex == Levels.cityBase || !Levels.isCity(levelIndex) {
            myWins = 0
            friendWins = 0
        }

        let start = level.starts[slot]
        carPosition = start.position
        heading = start.heading
        travelHeading = start.heading
        velocity = 0
        steer = 0
        wheelInput = 0
        gear = .drive
        engaged = false
        braking = false
        longitudinalAccel = 0
        lateralAccel = 0
        let remoteStart = level.starts[otherSlot]
        remotePosition = remoteStart.position
        remoteHeading = remoteStart.heading
        remoteSteer = 0
        remoteBraking = false
        remoteReversing = false
        remoteTarget = nil
        remoteSnapshots.removeAll()

        phase = .countdown
        countdown = 3
        elapsed = 0
        hits = 0
        lastHitAt = -10
        parkHold = 0
        localParked = false
        localTime = 0
        remoteParked = false
        remoteTime = 0
        remoteHits = 0
        resultsShown = false
        advanceScheduled = false
        newBest = false
        nitro = 0.5
        boostTime = 0
        remoteBoost = false
        statusLabel.text = ""
        countdownLabel.text = ""
        setCountdown("3")
        countdownNode.removeAllActions()
        countdownNode.alpha = 0
        countdownNode.setScale(1)
        countdownNode.position = countdownHome
        countdownBar.xScale = 0.001
        hitsLabel.text = "0"
        gearLabel.text = "1"
        gearIndex = 1
        rpm = idleRPM
        shiftCut = 0
        audio.setLoop("wind", volume: 0)
        refreshLevelLabel()
        codeLabel.text = online ? "\(Strings.roomCode): \(model?.roomCode ?? "")" : ""
        remoteCheck.isHidden = true
        holdRing.path = nil
        world.follow(position: carPosition, heading: heading, dt: 0, snap: true)
        buildMinimap()
        updateCarNodes()
        countdownNode.isHidden = !ready
        if ready {
            popCountdown(go: false)
            tickHaptic.impactOccurred()
            audio.play("beep", volume: 0.6)
        }
    }

    /// The world is built and its shaders are compiled: hide the loading screen, start the countdown.
    private func stage(_ text: String) {
        if PerfSettings.benchmark {
            FileHandle.standardError.write(("PPSTAGE " + text + "\n").data(using: .utf8)!)
        }
    }

    /// The capsule fades in once; each new number slides up into place while the old one leaves
    /// upward, and the lamp that just lit pops. GO! turns the capsule green and it floats away.
    private func popCountdown(go: Bool) {
        countdownNode.isHidden = false
        if countdownNode.alpha < 0.99 || countdownNode.action(forKey: "leave") != nil {
            countdownNode.removeAllActions()
            countdownNode.position = CGPoint(x: countdownHome.x, y: countdownHome.y - 10)
            countdownNode.alpha = 0
            countdownNode.setScale(0.92)
            let enter = SKAction.group([.fadeIn(withDuration: 0.25), .scale(to: 1, duration: 0.3), .move(to: countdownHome, duration: 0.3)])
            enter.timingMode = .easeOut
            countdownNode.run(enter)
        }
        countdownShadow.removeAllActions()
        countdownShadow.position = CGPoint(x: 0, y: 7)
        countdownShadow.alpha = countdownShadow.text?.isEmpty == false ? 1 : 0
        let out = SKAction.group([.moveBy(x: 0, y: 14, duration: 0.2), .fadeOut(withDuration: 0.2)])
        out.timingMode = .easeIn
        countdownShadow.run(out)
        countdownLabel.removeAllActions()
        countdownLabel.position = CGPoint(x: 0, y: -5)
        countdownLabel.alpha = 0
        let into = SKAction.group([.move(to: CGPoint(x: 0, y: 7), duration: 0.26), .fadeIn(withDuration: 0.22)])
        into.timingMode = .easeOut
        countdownLabel.run(into)
        let litIndex = go ? -1 : max(0, 3 - (Int(countdownLabel.text ?? "3") ?? 3))
        for (index, lamp) in countdownLamps.enumerated() where index == litIndex || go {
            lamp.removeAllActions()
            lamp.setScale(1.7)
            let settle = SKAction.scale(to: 1, duration: 0.25)
            settle.timingMode = .easeOut
            lamp.run(settle)
        }
        if go {
            countdownBar.xScale = 1
            let pulse = SKAction.sequence([.scale(to: 1.08, duration: 0.12), .scale(to: 1.0, duration: 0.14)])
            let leave = SKAction.group([.fadeOut(withDuration: 0.3), .moveBy(x: 0, y: 18, duration: 0.3)])
            leave.timingMode = .easeIn
            countdownNode.run(.sequence([pulse, .wait(forDuration: 0.35), leave, .hide()]), withKey: "leave")
        }
    }

    /// The bar fills smoothly over the whole countdown.
    private func updateCountdownRing() {
        countdownBar.xScale = max(0.001, min(1, 1 - countdown / 3))
    }

    private func becomeReady() {
        guard !ready, !readyRequested else { return }
        readyRequested = true
        stage("ready")
        revealWhenWarm()
    }

    /// The warm-up camera tour must finish (every material, mesh and lamp color of the level drawn
    /// once) before the loading screen goes; cutting it short left first-sight stalls in the race.
    /// It then ends under the curtain, so the first thing the player sees is the chase camera.
    private func revealWhenWarm(waited: TimeInterval = 0) {
        if let world = world, !world.sweepComplete, waited < 5 {
            run(.wait(forDuration: 0.1)) { [weak self] in self?.revealWhenWarm(waited: waited + 0.1) }
            return
        }
        world?.endWarmupSweep()
        if let model = model {
            model.sceneReady { [weak self] in self?.startCountdown() }
        } else {
            startCountdown()
        }
    }

    /// Runs once the loading screen has gone.
    private func startCountdown() {
        guard !ready else { return }
        ready = true
        world?.endWarmupSweep()
        countdownNode.isHidden = false
        countdown = 3
        setCountdown("3")
        popCountdown(go: false)
        tickHaptic.impactOccurred()
        audio.play("beep", volume: 0.6)
    }

    // MARK: Network

    func handleNetwork(_ message: [String: Any]) {
        guard let type = message["t"] as? String else { return }
        let messageLevel = message["l"] as? Int ?? -1
        switch type {
        case "s":
            guard messageLevel == levelIndex,
                  let x = message["x"] as? Double, let y = message["y"] as? Double, let h = message["h"] as? Double else { return }
            let target = CGPoint(x: x, y: y)
            if remoteTarget == nil {
                remotePosition = target
                remoteHeading = CGFloat(h)
            }
            remoteTarget = (target, CGFloat(h))
            let now = CACurrentMediaTime()
            let sentAt = message["ts"] as? Double ?? now
            let offset = now - sentAt
            if let current = clockOffset, offset >= current {
                clockOffset = current + (offset - current) * 0.02
            } else {
                clockOffset = offset
            }
            if let last = remoteSnapshots.last, sentAt <= last.time { return }
            remoteSnapshots.append(RemoteSnapshot(time: sentAt, position: target, heading: CGFloat(h),
                                                  velocity: CGFloat(message["v"] as? Double ?? 0)))
            if remoteSnapshots.count > 30 { remoteSnapshots.removeFirst(remoteSnapshots.count - 30) }
            remoteSteer = CGFloat(message["st"] as? Double ?? 0)
            remoteBoost = (message["n"] as? Int ?? 0) == 1
            remoteBraking = (message["b"] as? Int ?? 0) == 1
            remoteReversing = (message["r"] as? Int ?? 0) == 1
            if let pose = message["pp"] as? [Double], pose.count == 3 {
                remotePoliceTarget = (CGPoint(x: pose[0], y: pose[1]), CGFloat(pose[2]))
            } else {
                remotePoliceTarget = nil
            }
        case "p":
            guard messageLevel == levelIndex else { return }
            remoteParked = true
            remotePoliceTarget = nil
            remoteTime = message["time"] as? Double ?? -1
            remoteHits = message["hits"] as? Int ?? 0
            if let x = message["x"] as? Double, let y = message["y"] as? Double, let h = message["h"] as? Double {
                remoteTarget = (CGPoint(x: x, y: y), CGFloat(h))
                remoteSnapshots.removeAll()
            }
            remoteSteer = 0
            remoteBraking = false
            remoteReversing = false
            remoteCheck.isHidden = false
            notifyHaptic.notificationOccurred(.warning)
            checkLevelDone()
        case "hn":
            remoteHonk()
        case "b":
            guard messageLevel == levelIndex, !isHost, let data = message["d"] as? [Int] else { return }
            traffic?.apply(data)
        default:
            break
        }
    }

    private func setCountdown(_ text: String) {
        let colors: [String: UIColor] = ["3": UIColor(red: 1.0, green: 0.36, blue: 0.33, alpha: 1),
                                         "2": UIColor(red: 1.0, green: 0.70, blue: 0.22, alpha: 1),
                                         "1": UIColor(red: 1.0, green: 0.88, blue: 0.30, alpha: 1)]
        let go = colors[text] == nil
        countdownShadow.text = countdownLabel.text == text ? "" : countdownLabel.text
        countdownShadow.fontColor = countdownLabel.fontColor
        countdownLabel.text = text
        countdownColor = colors[text] ?? UIColor(red: 0.35, green: 1.0, blue: 0.55, alpha: 1)
        countdownLabel.fontColor = go ? .white : countdownColor
        let lit = go ? 3 : max(0, 4 - (Int(text) ?? 3))
        for (index, lamp) in countdownLamps.enumerated() {
            lamp.fillColor = index < lit ? countdownColor : UIColor.white.withAlphaComponent(0.16)
        }
        countdownBar.color = countdownColor
        countdownPill.fillColor = go ? UIColor(red: 0.1, green: 0.62, blue: 0.32, alpha: 0.85)
                                     : UIColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 0.6)
        countdownPill.strokeColor = go ? UIColor(red: 0.5, green: 1, blue: 0.65, alpha: 0.6) : UIColor.white.withAlphaComponent(0.14)
    }

    /// Plays the other car back `interpolationDelay` behind the newest state, blending between
    /// the two states around that moment; extrapolates briefly if packets are late.
    private func updateRemoteCar(_ dt: CGFloat) {
        guard let target = remoteTarget else { return }
        guard let offset = clockOffset, let newest = remoteSnapshots.last else {
            // No timed states (parked or old version): ease to the last known pose
            let k = min(1, dt * 10)
            remotePosition = CGPoint(x: remotePosition.x + (target.0.x - remotePosition.x) * k,
                                     y: remotePosition.y + (target.0.y - remotePosition.y) * k)
            remoteHeading += CGFloat.angleDelta(remoteHeading, target.1) * k
            return
        }
        let renderTime = CACurrentMediaTime() - offset - interpolationDelay
        var pose: (CGPoint, CGFloat)
        if renderTime >= newest.time {
            let ahead = CGFloat(min(renderTime - newest.time, 0.35))
            pose = (CGPoint(x: newest.position.x + cos(newest.heading) * newest.velocity * ahead,
                            y: newest.position.y + sin(newest.heading) * newest.velocity * ahead), newest.heading)
        } else if let first = remoteSnapshots.first, renderTime <= first.time {
            pose = (first.position, first.heading)
        } else {
            var index = remoteSnapshots.count - 1
            while index > 0 && remoteSnapshots[index - 1].time > renderTime { index -= 1 }
            let a = remoteSnapshots[max(0, index - 1)]
            let b = remoteSnapshots[index]
            let span = max(b.time - a.time, 0.001)
            let f = CGFloat(max(0, min(1, (renderTime - a.time) / span)))
            pose = (CGPoint(x: a.position.x + (b.position.x - a.position.x) * f,
                            y: a.position.y + (b.position.y - a.position.y) * f),
                    a.heading + CGFloat.angleDelta(a.heading, b.heading) * f)
            // Drop states that are no longer needed
            if index > 2 { remoteSnapshots.removeFirst(index - 2) }
        }
        // Small smoothing on top hides extrapolation corrections
        let k = min(1, dt * 20)
        if remotePosition.distance(to: pose.0) > 120 {
            remotePosition = pose.0
            remoteHeading = pose.1
        } else {
            remotePosition = CGPoint(x: remotePosition.x + (pose.0.x - remotePosition.x) * k,
                                     y: remotePosition.y + (pose.0.y - remotePosition.y) * k)
            remoteHeading += CGFloat.angleDelta(remoteHeading, pose.1) * k
        }
    }

    private func refreshLevelLabel() {
        if isCity && online && friendPresent {
            levelLabel.text = Levels.title(levelIndex) + " · " + Strings.score(myWins, friendWins)
        } else {
            levelLabel.text = Levels.title(levelIndex) + " · " + level.name
        }
    }

    func retryLevel() {
        loadBehindCurtain(level: levelIndex)
    }

    func nextLevel() {
        loadBehindCurtain(level: Levels.clamp(levelIndex + 1))
    }

    /// Later rounds load behind the loading screen too (building a level in view froze the game
    /// for a moment and cut straight to the new map): the curtain fades in, the level is built and
    /// warmed up under it, then it fades out and the countdown starts.
    func loadBehindCurtain(level index: Int) {
        guard let model = model else {
            load(level: index)
            return
        }
        model.showCurtain(level: index) { [weak self] in
            guard let self = self else { return }
            self.ready = false
            self.readyRequested = false
            self.load(level: index)
        }
    }

    // MARK: Benchmark

    /// Drives along the route at full throttle, uses nitro, backs out when stuck, and measures
    /// 20 seconds of frames once driving has settled.
    private func runAutopilot(_ dt: CGFloat) {
        autoControls = []
        guard phase != .countdown, !benchDone else { return }
        benchClock += finishAnimating ? CGFloat(1.0 / 60.0) : dt
        if !benchRecording && benchClock > 2 {
            benchRecording = true
            FrameMonitor.shared.start()
        }
        if benchClock > 1.0 && benchClock - dt <= 1.0 { world?.saveSnapshot(named: "shot-start") }
        // (not behind the results card: a snapshot of the paused 3D view stalls)
        if benchClock > 12 && benchClock - dt <= 12 && !worldFrozen {
            FrameMonitor.shared.mark("snapshot")
            world?.saveSnapshot(named: "shot-mid")
            saveFullSnapshot()
        }
        if benchRecording && benchClock > 22 {
            finishBenchmark()
            return
        }
        // Finish test: put the car just before the finish line at speed so it crosses it
        if PerfSettings.finishTest && level.race && !finishTestPlaced && benchClock > 6 {
            finishTestPlaced = true
            let finish = level.spots[slot]
            let dir = CGPoint(x: cos(finish.angle), y: sin(finish.angle))
            let normal = CGPoint(x: dir.y, y: -dir.x)
            carPosition = CGPoint(x: finish.center.x - dir.x * 140 + normal.x * CityMap.laneOffset,
                                  y: finish.center.y - dir.y * 140 + normal.y * CityMap.laneOffset)
            heading = finish.angle
            velocity = 120
            gear = .drive
            finishTestAt = Double(benchClock - 2)
        }
        if PerfSettings.finishTest && finishTestPlaced && level.race && phase == .driving && !localParked {
            checkParking(dt)
            autoControls = [.forward]
            return
        }
        guard phase == .driving else { return }
        if autoReverse > 0 {
            autoReverse -= dt
            autoControls = [.reverse, .left]
            return
        }
        autoControls.insert(.forward)
        var relative: CGFloat = 0
        if route.count >= 2 {
            let k = route.count > 2 && carPosition.distance(to: route[1]) < 95 ? 2 : 1
            relative = CGFloat.angleDelta(heading, atan2(route[k].y - carPosition.y, route[k].x - carPosition.x))
            if relative > 0.08 { autoControls.insert(.left) } else if relative < -0.08 { autoControls.insert(.right) }
        }
        stuckTime = abs(velocity) < 6 ? stuckTime + dt : 0
        if stuckTime > 1.2 {
            stuckTime = 0
            autoReverse = 1.0
        }
        if nitro >= 1 && abs(relative) < 0.25 { fireNitro() }
    }

    /// Benchmark helper: 3D view plus the HUD drawn on top, saved as Documents/shot-hud.png.
    private func saveFullSnapshot() {
        guard let world = world, let base = world.renderer?.snapshot(), let skView = view,
              let texture = skView.texture(from: self),
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let hudImage = UIImage(cgImage: texture.cgImage())
        let canvas = CGSize(width: size.width, height: size.height)
        let image = UIGraphicsImageRenderer(size: canvas).image { _ in
            base.draw(in: CGRect(origin: .zero, size: canvas))
            hudImage.draw(in: CGRect(origin: .zero, size: canvas))
        }
        try? image.pngData()?.write(to: folder.appendingPathComponent("shot-hud.png"))
    }

    private func finishBenchmark() {
        benchDone = true
        FrameMonitor.shared.stop()
        let summary = FrameMonitor.shared.summary()
        let stats = world.map { SceneStats.count($0.scene.rootNode) } ?? (0, 0, 0, 0)
        let effective = world.map { SceneStats.effective($0.scene.rootNode, camera: $0.cameraNode.simdWorldPosition) } ?? (0, 0)
        let report: [String: Any] = [
            "mode": PerfSettings.optimized ? "optimized" : "legacy",
            "device": UIDevice.current.model, "screenScale": Double(UIScreen.main.scale),
            "level": Levels.title(levelIndex), "bots": traffic?.bots.count ?? 0,
            "parkedCars": level.obstacles.filter { $0.kind == .car }.count,
            "frames": summary.frames, "seconds": (summary.seconds * 100).rounded() / 100,
            "avgFPS": (summary.averageFPS * 10).rounded() / 10,
            "onePercentLowFPS": (summary.onePercentLowFPS * 10).rounded() / 10,
            "frameMsP50": (summary.p50 * 100).rounded() / 100, "frameMsP95": (summary.p95 * 100).rounded() / 100,
            "frameMsP99": (summary.p99 * 100).rounded() / 100, "frameMsWorst": (summary.worst * 100).rounded() / 100,
            "jankFramesOver25ms": summary.jankFrames,
            "updateMsAvg": (summary.updateAverage * 1000).rounded() / 1000,
            "updateMsP95": (summary.updateP95 * 1000).rounded() / 1000,
            "renderCpuMsAvg": (summary.renderCpuAverage * 1000).rounded() / 1000,
            "renderCpuMsP95": (summary.renderCpuP95 * 1000).rounded() / 1000,
            "drawCallsAtCamera": effective.0, "trianglesAtCamera": effective.1,
            "sceneNodes": stats.0, "geometryNodes": stats.1, "drawCallsFullDetail": stats.2, "triangles": stats.3,
            "levelLoadMs": (levelLoadMilliseconds * 10).rounded() / 10,
            "hits": hits,
            "spikes": FrameMonitor.shared.spikes(over: 50),
            "spikeDetails": FrameMonitor.shared.spikeDetails(over: 45),
            "slowUpdates": FrameMonitor.shared.slowUpdates(over: 12),
            "nitroAt": nitroFiredAt,
            "finishTestAt": finishTestAt, "finishCrossAt": finishCrossAt
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            print("PPBENCH " + text)
            if let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? data.write(to: folder.appendingPathComponent("bench.json"))
            }
        }
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { exit(0) }
    }

    // MARK: Nitro

    private func fireNitro() {
        guard phase == .driving, !localParked, !isBoosting else { return }
        guard nitro >= 1 else {
            nitroButton.removeAction(forKey: "deny")
            nitroButton.run(.sequence([.moveBy(x: -5, y: 0, duration: 0.04), .moveBy(x: 10, y: 0, duration: 0.06),
                                       .moveBy(x: -5, y: 0, duration: 0.04)]), withKey: "deny")
            tickHaptic.impactOccurred(intensity: 0.3)
            return
        }
        nitro = 0
        boostTime = boostDuration
        if benchmark { FrameMonitor.shared.mark("nitro") }
        if benchRecording { nitroFiredAt.append((Double(benchClock - 2) * 10).rounded() / 10) }
        engaged = true
        if gear == .reverse && velocity <= 2 { gear = .drive }
        velocity = max(velocity, 0) + 45
        var t0 = CACurrentMediaTime()
        func lap(_ name: String) {
            guard benchmark else { return }
            let now = CACurrentMediaTime()
            let ms = (now - t0) * 1000
            if ms > 5 { stage(String(format: "nitro %@ %.0f ms", name, ms)) }
            t0 = now
        }
        audio.play("nitro", volume: 0.8)
        lap("audio")
        bumpHaptic.impactOccurred(intensity: 1.0)
        lap("haptic")
        world?.shake(strength: 3)
        boostVisual = 1.3   // lens punch, eases back to 1
        // Shockwave ring from behind the car and the banner: both made when the level is built
        // (an SKShapeNode glow compiled its shader on the first nitro and stalled a frame)
        nitroShock.removeAllActions()
        nitroShock.setScale(0.6)
        nitroShock.alpha = 1
        let expand = SKAction.group([.scale(to: 6, duration: 0.45), .fadeAlpha(to: 0.002, duration: 0.45)])
        expand.timingMode = .easeOut
        nitroShock.run(expand)
        nitroBanner.removeAllActions()
        nitroBanner.position = CGPoint(x: size.width / 2, y: size.height * 0.62)
        nitroBanner.setScale(0.5)
        nitroBanner.alpha = 1
        nitroBanner.run(.sequence([.scale(to: 1.15, duration: 0.12), .scale(to: 1.0, duration: 0.1), .wait(forDuration: 0.5),
                                   .group([.fadeAlpha(to: 0.002, duration: 0.3), .moveBy(x: 0, y: 20, duration: 0.3)])]))
        lap("effects")
    }

    private func updateNitro(_ dt: CGFloat) {
        if isBoosting {
            boostTime = max(0, boostTime - dt)
            if phase != .driving || localParked { boostTime = 0 }
        } else if phase == .driving && !localParked {
            let before = nitro
            nitro = min(1, nitro + dt / nitroFillTime)
            if before < 1 && nitro >= 1 {
                tickHaptic.impactOccurred(intensity: 0.7)
                nitroButton.run(.sequence([.scale(to: 1.15, duration: 0.1), .scale(to: 1.0, duration: 0.15)]))
            }
        }
        boostVisual = approach(boostVisual, isBoosting ? 1 : 0, (isBoosting ? 5 : 2) * dt)
        world?.setBoost(boostVisual)
        localCar?.setNitro(isBoosting)
        remoteCar?.setNitro(remoteBoost && friendPresent)

        // Ring: fill level, or remaining boost while burning
        let fraction = isBoosting ? boostTime / boostDuration : nitro
        // Rebuilding a shape path re-tessellates it: only when the ring visibly changes
        let nitroStep = fraction > 0.01 ? Int((fraction * 120).rounded()) : -1
        if nitroStep != shownNitroStep {
            shownNitroStep = nitroStep
            if nitroStep >= 0 {
                let path = CGMutablePath()
                path.addArc(center: .zero, radius: 39, startAngle: CGFloat.pi / 2,
                            endAngle: CGFloat.pi / 2 - CGFloat(nitroStep) / 120 * 2 * CGFloat.pi, clockwise: true)
                nitroRing.path = path
            } else {
                nitroRing.path = nil
            }
        }
        let ready = nitro >= 1 && !isBoosting
        nitroRing.strokeColor = isBoosting ? UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
                                           : (ready ? UIColor(red: 0.35, green: 1.0, blue: 0.9, alpha: 1) : UIColor(red: 0.30, green: 0.70, blue: 1.0, alpha: 1))
        nitroButton.alpha = ready || isBoosting ? 1 : 0.75
        if ready && nitroIcon.action(forKey: "pulse") == nil {
            nitroIcon.run(.repeatForever(.sequence([.scale(to: 1.2, duration: 0.35), .scale(to: 1.0, duration: 0.35)])), withKey: "pulse")
        } else if !ready {
            nitroIcon.removeAction(forKey: "pulse")
            nitroIcon.setScale(1)
        }

        // Speed lines and blue tint
        boostTint.alpha = max(0.002, boostVisual * 0.75)
        let center = CGPoint(x: size.width / 2, y: size.height * 0.45)
        let maxRadius = hypot(size.width, size.height) * 0.6
        for index in speedLines.indices {
            var line = speedLines[index]
            if boostVisual < 0.02 {
                line.sprite.alpha = 0.002
                continue
            }
            line.radius += (700 + 900 * boostVisual) * dt
            if line.radius > maxRadius {
                line.radius = size.height * 0.3 + CGFloat.random(in: 0...60)
                line.angle = CGFloat.random(in: 0...(2 * CGFloat.pi))
            }
            line.sprite.position = CGPoint(x: center.x + cos(line.angle) * line.radius, y: center.y + sin(line.angle) * line.radius)
            line.sprite.zRotation = line.angle - CGFloat.pi / 2
            line.sprite.alpha = 0.5 * boostVisual * min(1, (line.radius - size.height * 0.25) / 120)
            line.sprite.yScale = 0.6 + boostVisual
            speedLines[index] = line
        }
    }

    // MARK: Horn

    private func honk() {
        guard lastUpdate - lastHorn > 0.25 else { return }
        lastHorn = lastUpdate
        pendingHorn = carPosition
        audio.play("horn", volume: 0.5)
        tickHaptic.impactOccurred(intensity: 0.9)
        hornButton.removeAction(forKey: "pulse")
        hornButton.setScale(1)
        hornButton.run(.sequence([.scale(to: 0.86, duration: 0.05), .scale(to: 1.0, duration: 0.18)]), withKey: "pulse")
        if online && friendPresent {
            model?.send(["t": "hn"])
        }
    }

    private func remoteHonk() {
        guard friendPresent else { return }
        pendingHorn = remotePosition
        let distance = hypot(remotePosition.x - carPosition.x, remotePosition.y - carPosition.y)
        audio.play("horn", volume: Float(max(0.45, min(0.8, 0.85 - distance / 2500))))
        bumpHaptic.impactOccurred(intensity: 0.6)

        var point = world?.project(remotePosition, height: 3.2) ?? CGPoint(x: -10000, y: 0)
        point.x = max(70, min(size.width - 70, point.x))
        point.y = max(90, min(size.height - 70, point.y))
        let bubble = makeGlass(width: 46, height: 46)
        bubble.position = point
        bubble.addChild(makeIcon("horn.blast.fill", size: 20, color: CarArt.playerColors[otherSlot].lighter(by: 0.25)))
        bubble.setScale(0.4)
        fxLayer.addChild(bubble)
        bubble.run(.sequence([
            .scale(to: 1.15, duration: 0.12),
            .scale(to: 1.0, duration: 0.1),
            .wait(forDuration: 0.5),
            .group([.fadeOut(withDuration: 0.35), .moveBy(x: 0, y: 18, duration: 0.35)]),
            .removeFromParent()
        ]))
        friendMarker.run(.sequence([.scale(to: 2.0, duration: 0.12), .scale(to: 1.0, duration: 0.25)]))
    }

    func friendJoined() {
        friendPresent = true
        online = true
    }

    func friendLeft() {
        friendPresent = false
        online = false
        remoteTarget = nil
        showToast(Strings.friendLeft)
        if resultsShown && !advanceScheduled {
            resultsShown = false
        }
        if phase == .finished { checkLevelDone() }
    }

    private func sendState() {
        model?.send(["t": "s", "l": levelIndex, "ts": CACurrentMediaTime(),
                     "x": Double(carPosition.x), "y": Double(carPosition.y),
                     "h": Double(heading), "v": Double(velocity), "st": Double(steer),
                     "b": braking ? 1 : 0, "r": (gear == .reverse && velocity < -1) ? 1 : 0, "n": isBoosting ? 1 : 0,
                     "pp": police.map { [Double($0.position.x), Double($0.position.y), Double($0.heading)] } ?? []])
    }

    // MARK: Input

    private func hitControl(at point: CGPoint) -> Control? {
        if leftButton.frame.insetBy(dx: -8, dy: -14).contains(point) { return .left }
        if rightButton.frame.insetBy(dx: -8, dy: -14).contains(point) { return .right }
        if gasPedal.frame.insetBy(dx: -14, dy: -14).contains(point) { return .forward }
        if reversePedal.frame.insetBy(dx: -14, dy: -14).contains(point) { return .reverse }
        if driftButton.parent != nil && driftButton.frame.insetBy(dx: -10, dy: -10).contains(point) { return .handbrake }
        return nil
    }

    private func isPressed(_ control: Control) -> Bool {
        autoControls.contains(control) || activeTouches.values.contains(control)
    }

    private func refreshPedals() {
        let gasDown = isPressed(.forward)
        let reverseDown = isPressed(.reverse)
        gasPedal.setScale(gasDown ? 0.93 : 1)
        gasPedal.alpha = gasDown ? 1 : 0.88
        reversePedal.setScale(reverseDown ? 0.93 : 1)
        reversePedal.alpha = reverseDown ? 1 : 0.88
        let leftDown = isPressed(.left)
        let rightDown = isPressed(.right)
        leftButton.setScale(leftDown ? 0.92 : 1)
        leftButton.alpha = leftDown ? 1 : 0.88
        rightButton.setScale(rightDown ? 0.92 : 1)
        rightButton.alpha = rightDown ? 1 : 0.88
        let driftDown = isPressed(.handbrake)
        driftButton.setScale(driftDown ? 0.9 : 1)
        driftButton.alpha = driftDown ? 1 : 0.88
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            if let finalButton = finalButton, finalButton.contains(point) {
                audio.play("click")
                model?.leaveToMenu()
                return
            }
            if menuButton.contains(point) {
                audio.play("click")
                model?.leaveToMenu()
                return
            }
            if resetButton.contains(point) {
                audio.play("click")
                resetCar()
                continue
            }
            if hornButton.contains(point) {
                honk()
                continue
            }
            if nitroButton.contains(point) {
                fireNitro()
                continue
            }
            if soundButton.contains(point) {
                audio.isMuted.toggle()
                refreshSoundIcon()
                audio.play("click")
                continue
            }
            if let control = hitControl(at: point) {
                activeTouches[touch] = control
                tickHaptic.impactOccurred(intensity: 0.5)
            }
        }
        refreshPedals()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let control = activeTouches[touch] else { continue }
            let point = touch.location(in: self)
            // Sliding a finger between neighbouring buttons switches to the new one
            if let now = hitControl(at: point), now != control {
                let steering: Set<Control> = [.left, .right]
                if steering.contains(now) == steering.contains(control) {
                    activeTouches[touch] = now
                }
            }
        }
        refreshPedals()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseTouches(touches)
    }

    private func releaseTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            activeTouches[touch] = nil
            wheelStartX[touch] = nil
        }
        refreshPedals()
    }

    private func resetCar() {
        guard phase == .driving, !localParked else { return }
        let start = level.starts[slot]
        carPosition = start.position
        heading = start.heading
        velocity = 0
        steer = 0
        gear = .drive
        engaged = false
        parkHold = 0
        tickHaptic.impactOccurred()
        world?.follow(position: carPosition, heading: heading, dt: 0, snap: true)
        updateCarNodes()
    }

    // MARK: Update loop

    override func update(_ currentTime: TimeInterval) {
        let started = CACurrentMediaTime()
        gameUpdate(currentTime)
        FrameMonitor.shared.recordUpdate(milliseconds: (CACurrentMediaTime() - started) * 1000)
    }

    private var firstUpdateLogged = false

    private func gameUpdate(_ currentTime: TimeInterval) {
        if !firstUpdateLogged {
            firstUpdateLogged = true
            stage("first update, paused=\(isPaused) viewPaused=\(view?.isPaused ?? true)")
        }
        let rawDelta = lastUpdate == 0 ? 1.0 / 60.0 : currentTime - lastUpdate
        lastUpdate = currentTime
        guard builtSize != .zero else { return }
        var dt = CGFloat(min(max(rawDelta, 0), 1.0 / 30.0))
        // Slow motion while the finish camera watches the car arrive
        if finishAnimating {
            finishClock += dt
            dt *= finishClock < 1.0 ? 0.35 : min(1, 0.35 + (finishClock - 1.0) * 1.6)
        }
        if benchmark { runAutopilot(dt) }

        let leftDown = isPressed(.left)
        let rightDown = isPressed(.right)
        let steerTarget: CGFloat = leftDown == rightDown ? 0 : (leftDown ? 1 : -1)
        wheelInput = approach(wheelInput, steerTarget, (steerTarget == 0 ? 4.0 : 2.6) * dt)

        switch phase {
        case .countdown:
            guard ready else { break }
            let before = Int(ceil(countdown))
            countdown -= dt
            let after = Int(ceil(countdown))
            if countdown <= 0 {
                phase = .driving
                setCountdown(Strings.go)
                popCountdown(go: true)
                tickHaptic.impactOccurred(intensity: 1.0)
                audio.play("go", volume: 0.7)
            } else {
                if after != before {
                    setCountdown("\(after)")
                    popCountdown(go: false)
                    tickHaptic.impactOccurred()
                    audio.play("beep", volume: 0.6)
                }
                updateCountdownRing()
            }
        case .driving:
            if !localParked {
                elapsed += TimeInterval(dt)
                stepCar(dt)
                separateFromRemote(dt)
                if !benchmark { checkParking(dt) }
            }
        case .finished:
            braking = false
            // Roll on past the finish line and slow down
            if level.race && abs(velocity) > 0.5 {
                velocity = approach(velocity, 0, 55 * dt)
                let next = CGPoint(x: carPosition.x + cos(heading) * velocity * dt, y: carPosition.y + sin(heading) * velocity * dt)
                if contacts(OBB(center: next, size: Levels.carSize, angle: heading)).isEmpty {
                    carPosition = next
                } else {
                    velocity = 0
                }
                braking = true
            }
        }

        // Revving is allowed during the countdown too
        let pedal = (isPressed(.forward) || isPressed(.reverse)) && (phase == .driving || phase == .countdown) && !localParked
        updateGearbox(dt, throttle: pedal)
        audio.setMotor(active: true, rpm: Float(rpm), load: pedal ? 1 : (isBoosting ? 0.8 : 0.15))

        if online && friendPresent {
            sendClock += TimeInterval(dt)
            if sendClock >= 1.0 / 20.0 && !localParked {
                sendClock = 0
                sendState()
            }
        }

        if worldFrozen {
            setTimerText(String(format: "%.1f", localParked ? max(localTime, 0) : elapsed))
            return
        }
        if let traffic = traffic {
            var blockers = [carPosition]
            if friendPresent && remoteTarget != nil { blockers.append(remotePosition) }
            if let people = pedestrians {
                // Cars stop for people on the road
                blockers += people.onRoad
                var threats = [PedestrianSystem.Threat(position: carPosition,
                                                       velocity: CGVector(dx: cos(heading) * velocity, dy: sin(heading) * velocity),
                                                       heading: velocity >= 0 ? heading : heading + CGFloat.pi, local: true)]
                if friendPresent && remoteTarget != nil {
                    let v = remoteSnapshots.last?.velocity ?? 0
                    threats.append(PedestrianSystem.Threat(position: remotePosition,
                                                           velocity: CGVector(dx: cos(remoteHeading) * v, dy: sin(remoteHeading) * v),
                                                           heading: v >= 0 ? remoteHeading : remoteHeading + CGFloat.pi, local: false))
                }
                let knocked = people.step(dt, threats: phase == .driving && !localParked ? threats : Array(threats.dropFirst()), horn: pendingHorn)
                pendingHorn = nil
                if knocked > 0 && lastUpdate - lastHitAt > 0.3 {
                    lastHitAt = lastUpdate
                    hits += knocked
                    hitsLabel.text = "\(hits)"
                    velocity *= 0.6
                    bumpHaptic.impactOccurred(intensity: 0.8)
                    audio.play("bump", volume: 0.6)
                    flashBonus(Strings.pedestrianHit)
                    dispatchPolice(Strings.crimePedestrian)
                }
                updatePedestrianNodes()
            }
            traffic.step(dt, blockers: blockers)
            world?.updateSignals(time: traffic.clock)
            updateArcade(dt, traffic: traffic)
            let detailRange = PerfSettings.carDetailDistance * 10
            var botDetailChanges = 0
            for (index, bot) in traffic.bots.enumerated() where index < botCars.count {
                let near = (world?.isSweeping ?? false)
                    || (abs(bot.position.x - carPosition.x) < detailRange && abs(bot.position.y - carPosition.y) < detailRange)
                if botCars[index].setDetail(near) { botDetailChanges += 1 }
                botCars[index].update(position: bot.position, heading: bot.heading, steer: 0, braking: bot.braking)
            }
            if benchmark && botDetailChanges > 0 { FrameMonitor.shared.mark("botDetail\(botDetailChanges)") }
            if online && friendPresent && isHost {
                botSendClock += TimeInterval(dt)
                if botSendClock >= 0.125 {
                    botSendClock = 0
                    model?.send(["t": "b", "l": levelIndex, "d": traffic.snapshot()])
                }
            }
        }
        if isCity { updateNavigation(dt) }
        detailClock -= dt
        if detailClock <= 0 {
            detailClock = 0.2
            let parkedChanges = world?.updateDetail(around: carPosition) ?? 0
            if benchmark && parkedChanges > 0 { FrameMonitor.shared.mark("parkedDetail\(parkedChanges)") }
        }

        if online && friendPresent && remoteParked && !localParked && phase == .driving {
            giveUp -= dt
            statusLabel.text = Strings.friendParkedHurry(max(0, Int(ceil(giveUp))))
            if giveUp <= 0 { gaveUp() }
        }

        updateRemoteCar(dt)
        updateNitro(dt)
        updateBonuses()
        updateSpeedometer(dt)

        setTimerText(String(format: "%.1f", localParked ? localTime : elapsed))
        // While drifting the camera looks between where the car points and where it goes
        let cameraHeading = drifting ? travelHeading + CGFloat.angleDelta(travelHeading, heading) * 0.35 : heading
        world?.follow(position: carPosition, heading: cameraHeading, dt: dt)
        updateCarNodes()
        updateSteerGauge()
    }

    /// The timer label only redraws when its text changes (ten times a second, not every frame).
    private func setTimerText(_ text: String) {
        if timerLabel.text != text { timerLabel.text = text }
    }

    private func updateSteerGauge() {
        let amount = max(-1, min(1, steer / maxSteer))
        let step = abs(amount) < 0.03 ? 0 : Int((amount * 80).rounded())
        guard step != shownSteerStep else { return }
        shownSteerStep = step
        if step == 0 {
            steerArc.path = nil
            if steerLabel.text != "" { steerLabel.text = "" }
            return
        }
        // Left fills toward the left side of the bar
        let width = CGFloat(abs(step))
        let rect = step > 0 ? CGRect(x: -width, y: -3.5, width: width, height: 7) : CGRect(x: 0, y: -3.5, width: width, height: 7)
        steerArc.path = CGPath(roundedRect: rect, cornerWidth: min(3.5, width / 2), cornerHeight: 3.5, transform: nil)
        let text = abs(amount) < 0.12 ? "" : (amount > 0 ? "◀ " + Strings.left : Strings.right + " ▶")
        if steerLabel.text != text { steerLabel.text = text }
    }

    // MARK: City race

    private func gaveUp() {
        endPoliceChase()
        audio.setLoop("siren", volume: 0)
        audio.setLoop("wind", volume: 0)
        audio.setLoop("skid", volume: 0)
        localParked = true
        localTime = -1
        velocity = 0
        braking = false
        phase = .finished
        holdRing.path = nil
        statusLabel.text = ""
        notifyHaptic.notificationOccurred(.error)
        model?.send(["t": "p", "l": levelIndex, "time": -1.0, "hits": hits,
                     "x": Double(carPosition.x), "y": Double(carPosition.y), "h": Double(heading)])
        checkLevelDone()
    }

    private func updateNavigation(_ dt: CGFloat) {
        guard let city = level.city else { return }
        let target = level.spots[slot].center
        routeClock -= dt
        if routeClock <= 0 || route.isEmpty {
            routeClock = 0.25
            if benchmark { FrameMonitor.shared.mark("route") }
            route = city.route(from: carPosition, to: target)
            let path = CGMutablePath()
            for (index, point) in route.enumerated() {
                let p = CGPoint(x: point.x * mapScale, y: point.y * mapScale)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            routeLine.path = path
        }
        navNode.isHidden = localParked
        guard route.count >= 2 else { return }

        // Where to steer right now
        var k = 1
        if route.count > 2 && carPosition.distance(to: route[1]) < 95 { k = 2 }
        let aim = route[k]
        let relative = CGFloat.angleDelta(heading, atan2(aim.y - carPosition.y, aim.x - carPosition.x))
        navArrow.zRotation = relative

        let toTarget = carPosition.distance(to: target)
        if toTarget < 90 {
            navLabel.text = level.race ? Strings.finishLine : Strings.parkHere
            return
        }
        if abs(relative) > 2.0 {
            navLabel.text = Strings.uTurn
            return
        }
        // Next turn along the route
        var travelled = carPosition.distance(to: route[k])
        var m = k
        while m < route.count - 1 {
            let a = route[m - 1]
            let b = route[m]
            let c = route[m + 1]
            let turn = CGFloat.angleDelta(atan2(b.y - a.y, b.x - a.x), atan2(c.y - b.y, c.x - b.x))
            if m >= 1 && abs(turn) > 0.6 && m < route.count - 1 && !(m == route.count - 2 && b.distance(to: c) < 140) {
                let meters = Int((travelled / 10).rounded())
                navLabel.text = (turn > 0 ? Strings.turnLeft : Strings.turnRight) + " · \(meters) m"
                return
            }
            travelled += b.distance(to: c)
            m += 1
        }
        navLabel.text = (level.race ? Strings.finishLine : Strings.toTarget) + " · \(Int((toTarget / 10).rounded())) m"
    }

    // MARK: Speedometer

    private let speedRadius: CGFloat = 50
    private let dialStart: CGFloat = CGFloat.pi * 1.25   // lower left
    private let dialSweep: CGFloat = CGFloat.pi * 1.5    // 270 degrees, clockwise
    private let dialMaxKmh: CGFloat = 100

    private func buildSpeedometer(left: CGFloat, top: CGFloat) {
        speedDial = SKNode()
        speedDial.position = CGPoint(x: left + speedRadius + 14, y: top - 44 - speedRadius)
        hud.addChild(speedDial)

        let disc = SKShapeNode(circleOfRadius: speedRadius + 6)
        disc.fillColor = UIColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 0.7)
        disc.strokeColor = UIColor.white.withAlphaComponent(0.2)
        disc.lineWidth = 1
        speedDial.addChild(disc)

        let track = SKShapeNode()
        let trackPath = CGMutablePath()
        trackPath.addArc(center: .zero, radius: speedRadius - 4, startAngle: dialStart, endAngle: dialStart - dialSweep, clockwise: true)
        track.path = trackPath
        track.strokeColor = UIColor.white.withAlphaComponent(0.14)
        track.lineWidth = 7
        track.lineCap = .round
        speedDial.addChild(track)

        // Tick marks every 10 km/h, longer every 20
        let ticks = SKShapeNode()
        let tickPath = CGMutablePath()
        for step in 0...10 {
            let angle = dialStart - dialSweep * CGFloat(step) / 10
            let inner = speedRadius - (step % 2 == 0 ? 17 : 13)
            let outer = speedRadius - 10
            tickPath.move(to: CGPoint(x: cos(angle) * inner, y: sin(angle) * inner))
            tickPath.addLine(to: CGPoint(x: cos(angle) * outer, y: sin(angle) * outer))
        }
        ticks.path = tickPath
        ticks.strokeColor = UIColor.white.withAlphaComponent(0.45)
        ticks.lineWidth = 1.5
        speedDial.addChild(ticks)

        speedArc = SKShapeNode()
        speedArc.lineWidth = 7
        speedArc.lineCap = .round
        speedArc.glowWidth = 1.5
        speedDial.addChild(speedArc)

        speedLabel = makeLabel("0", size: 28, color: .white)
        speedLabel.position = CGPoint(x: 0, y: 2)
        speedDial.addChild(speedLabel)
        let unit = makeLabel("km/h", size: 10, color: UIColor.white.withAlphaComponent(0.6), font: "AvenirNext-Bold")
        unit.position = CGPoint(x: 0, y: -20)
        speedDial.addChild(unit)
    }

    /// 1 world unit = 10 cm, so units/s * 0.36 = km/h.
    private func updateSpeedometer(_ dt: CGFloat) {
        let kmh = abs(velocity) * 0.36
        shownSpeed += (kmh - shownSpeed) * min(1, dt * 10)
        let shownKmh = Int(shownSpeed.rounded())
        if shownKmh != lastShownKmh {
            // Label text is drawn into a texture on every change: only when the number changes
            lastShownKmh = shownKmh
            speedLabel.text = "\(shownKmh)"
        }
        let fraction = min(1, shownSpeed / dialMaxKmh)
        let speedStep = fraction > 0.005 ? Int((fraction * 150).rounded()) : -1
        if speedStep != shownSpeedStep {
            shownSpeedStep = speedStep
            if speedStep >= 0 {
                let path = CGMutablePath()
                path.addArc(center: .zero, radius: speedRadius - 4, startAngle: dialStart,
                            endAngle: dialStart - dialSweep * CGFloat(speedStep) / 150, clockwise: true)
                speedArc.path = path
            } else {
                speedArc.path = nil
            }
        }
        let color: UIColor
        if isBoosting {
            color = UIColor(red: 0.35, green: 0.9, blue: 1.0, alpha: 1)
        } else if fraction < 0.5 {
            color = UIColor(red: 0.4, green: 0.95, blue: 0.55, alpha: 1)
        } else if fraction < 0.8 {
            color = UIColor(red: 1.0, green: 0.82, blue: 0.25, alpha: 1)
        } else {
            color = UIColor(red: 1.0, green: 0.42, blue: 0.32, alpha: 1)
        }
        speedArc.strokeColor = color
        speedLabel.fontColor = isBoosting ? color : .white
    }

    // MARK: Minimap

    /// Heading-up minimap in the top-right corner: the player stays in the middle pointing up and
    /// the map turns and slides underneath.
    private func buildMinimap() {
        minimap.removeAllChildren()
        botDots.removeAll()
        let right = max(insets.right, 10)
        let radius = mapRadius
        minimap.position = CGPoint(x: size.width - right - radius - 8, y: size.height - 56 - radius)
        codeLabel.position = CGPoint(x: minimap.position.x, y: minimap.position.y - radius - 14)
        mapScale = isCity ? radius / 700 : radius / 420

        let backdrop = SKShapeNode(circleOfRadius: radius + 3)
        backdrop.fillColor = UIColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 0.75)
        backdrop.strokeColor = UIColor.white.withAlphaComponent(0.35)
        backdrop.lineWidth = 1.5
        minimap.addChild(backdrop)

        let crop = SKCropNode()
        let mask = SKShapeNode(circleOfRadius: radius)
        mask.fillColor = .white
        mask.strokeColor = .clear
        crop.maskNode = mask
        minimap.addChild(crop)
        mapContent = SKNode()
        crop.addChild(mapContent)

        let worldRect = CGRect(x: 0, y: 0, width: level.world.width * mapScale, height: level.world.height * mapScale)
        let ground = SKShapeNode(rect: worldRect)
        ground.fillColor = isCity ? UIColor(red: 0.33, green: 0.34, blue: 0.38, alpha: 1) : UIColor(red: 0.22, green: 0.24, blue: 0.29, alpha: 1)
        ground.strokeColor = UIColor.white.withAlphaComponent(0.25)
        mapContent.addChild(ground)

        func shape(center: CGPoint, size: CGSize, angle: CGFloat) -> SKShapeNode {
            let node = SKShapeNode(rectOf: CGSize(width: max(2, size.width * mapScale), height: max(2, size.height * mapScale)),
                                   cornerRadius: 1)
            node.position = CGPoint(x: center.x * mapScale, y: center.y * mapScale)
            node.zRotation = angle
            node.strokeColor = .clear
            return node
        }

        if let city = level.city {
            for block in city.blocks {
                let node = SKShapeNode(rect: CGRect(x: block.minX * mapScale, y: block.minY * mapScale,
                                                    width: block.width * mapScale, height: block.height * mapScale), cornerRadius: 2)
                node.fillColor = UIColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 1)
                node.strokeColor = .clear
                mapContent.addChild(node)
            }
            for obstacle in level.obstacles where obstacle.tint == Levels.park {
                let node = shape(center: obstacle.center, size: obstacle.size, angle: 0)
                node.fillColor = UIColor(red: 0.16, green: 0.36, blue: 0.20, alpha: 1)
                mapContent.addChild(node)
            }
            routeLine = SKShapeNode()
            routeLine.strokeColor = UIColor(red: 1.0, green: 0.82, blue: 0.20, alpha: 1)
            routeLine.lineWidth = 3.5
            routeLine.lineCap = .round
            routeLine.lineJoin = .round
            mapContent.addChild(routeLine)
            for _ in traffic?.bots ?? [] {
                let dot = SKSpriteNode(texture: dotTexture)
                dot.size = CGSize(width: 5, height: 5)
                dot.alpha = 0.85
                mapContent.addChild(dot)
                botDots.append(dot)
            }
        } else {
            for obstacle in level.obstacles {
                let node = shape(center: obstacle.center, size: obstacle.size, angle: obstacle.angle)
                switch obstacle.kind {
                case .wall, .building: node.fillColor = UIColor(white: 0.78, alpha: 0.9)
                case .car: node.fillColor = UIColor(white: 0.55, alpha: 0.9)
                case .cone: node.fillColor = UIColor(red: 1.0, green: 0.5, blue: 0.15, alpha: 1)
                }
                mapContent.addChild(node)
            }
        }

        let spotSlots = friendPresent ? [otherSlot, slot] : [slot]
        for spotSlot in spotSlots {
            let def = level.spots[spotSlot]
            let color = CarArt.playerColors[spotSlot]
            let node: SKShapeNode
            if isCity {
                node = SKShapeNode(circleOfRadius: spotSlot == slot ? 5 : 3.5)
                node.position = CGPoint(x: def.center.x * mapScale, y: def.center.y * mapScale)
                node.fillColor = level.race ? UIColor(red: 1, green: 0.82, blue: 0.2, alpha: 1) : color
                node.strokeColor = .white
                node.lineWidth = 1.5
            } else {
                node = shape(center: def.center, size: def.size, angle: def.angle)
                node.fillColor = color.withAlphaComponent(0.35)
                node.strokeColor = color.lighter(by: 0.3)
                node.lineWidth = 1.5
            }
            if spotSlot == slot {
                node.glowWidth = 2
                node.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)])))
            }
            mapContent.addChild(node)
        }

        func marker(_ color: UIColor) -> SKShapeNode {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 7, y: 0))
            path.addLine(to: CGPoint(x: -5, y: 4.5))
            path.addLine(to: CGPoint(x: -3, y: 0))
            path.addLine(to: CGPoint(x: -5, y: -4.5))
            path.closeSubpath()
            let node = SKShapeNode(path: path)
            node.fillColor = color
            node.strokeColor = .white
            node.lineWidth = 1.2
            return node
        }
        friendMarker = marker(CarArt.playerColors[otherSlot])
        mapContent.addChild(friendMarker)
        // The police car: a flashing dot
        policeMarker = SKShapeNode(circleOfRadius: 4.5)
        policeMarker.fillColor = UIColor(red: 1, green: 0.15, blue: 0.15, alpha: 1)
        policeMarker.strokeColor = .white
        policeMarker.lineWidth = 1.2
        policeMarker.zPosition = 3
        policeMarker.isHidden = true
        mapContent.addChild(policeMarker)
        // The player: fixed in the middle, always pointing up
        myMarker = marker(CarArt.playerColors[slot])
        myMarker.setScale(1.3)
        myMarker.zRotation = CGFloat.pi / 2
        minimap.addChild(myMarker)
        // Arrow on the rim pointing at the target when it is off the map
        targetPointer = makeIcon("arrowtriangle.up.fill", size: 11, color: level.race ? UIColor(red: 1, green: 0.82, blue: 0.2, alpha: 1)
                                                                                : CarArt.playerColors[slot].lighter(by: 0.3))
        minimap.addChild(targetPointer)
        navNode.isHidden = !isCity
        updateMinimap()
    }

    private func updateMinimap() {
        // Rotate the map so the car's heading points up, and keep the car in the middle
        let rotation = CGFloat.pi / 2 - heading
        mapContent.zRotation = rotation
        let car = CGPoint(x: carPosition.x * mapScale, y: carPosition.y * mapScale)
        mapContent.position = CGPoint(x: -(car.x * cos(rotation) - car.y * sin(rotation)),
                                      y: -(car.x * sin(rotation) + car.y * cos(rotation)))
        friendMarker.isHidden = !friendPresent
        friendMarker.position = CGPoint(x: remotePosition.x * mapScale, y: remotePosition.y * mapScale)
        friendMarker.zRotation = remoteHeading
        if let chase = police ?? remotePolice {
            policeMarker.isHidden = false
            policeMarker.position = CGPoint(x: chase.position.x * mapScale, y: chase.position.y * mapScale)
            let red = Int(lastUpdate * 6) % 2 == 0
            policeMarker.fillColor = red ? UIColor(red: 1, green: 0.15, blue: 0.15, alpha: 1) : UIColor(red: 0.2, green: 0.45, blue: 1, alpha: 1)
        } else {
            policeMarker.isHidden = true
        }
        if let bots = traffic?.bots {
            for (index, dot) in botDots.enumerated() where index < bots.count {
                dot.position = CGPoint(x: bots[index].position.x * mapScale, y: bots[index].position.y * mapScale)
            }
        }
        // Target pointer on the rim
        let target = level.spots[slot].center
        let dx = (target.x - carPosition.x) * mapScale
        let dy = (target.y - carPosition.y) * mapScale
        let rx = dx * cos(rotation) - dy * sin(rotation)
        let ry = dx * sin(rotation) + dy * cos(rotation)
        let distance = hypot(rx, ry)
        if distance > mapRadius - 6 && !localParked {
            targetPointer.isHidden = false
            targetPointer.position = CGPoint(x: rx / distance * (mapRadius - 7), y: ry / distance * (mapRadius - 7))
            targetPointer.zRotation = atan2(ry, rx) - CGFloat.pi / 2
        } else {
            targetPointer.isHidden = true
        }
    }

    private func updateCarNodes() {
        guard let world = world else { return }
        let pitch = max(-0.07, min(0.07, longitudinalAccel * 0.00028))
        let roll = max(-0.06, min(0.06, lateralAccel * 0.00035))
        let reversing = gear == .reverse && velocity < -1
        let (lift, airPitch) = carLift()
        localCar?.update(position: carPosition, heading: heading, steer: steer,
                         pitch: pitch + airPitch, roll: roll, braking: braking, reversing: reversing, lift: lift)
        localTag.position = world.project(carPosition, height: 2.6)

        let showRemote = friendPresent
        remoteCar?.isHidden = !showRemote
        remoteTag.isHidden = !showRemote
        remoteCar?.update(position: remotePosition, heading: remoteHeading, steer: remoteSteer,
                          braking: remoteBraking, reversing: remoteReversing)
        remoteTag.position = world.project(remotePosition, height: 2.6)
        remoteCheck.position = world.project(remotePosition, height: 4.0)
        if !showRemote { remoteCheck.isHidden = true }
        updateMinimap()
    }

    // MARK: Driving

    private func stepCar(_ dt: CGFloat) {
        let gasDown = isPressed(.forward)
        let reverseDown = isPressed(.reverse)
        let previousVelocity = velocity
        braking = false
        if gasDown || reverseDown { engaged = true }

        // Automatic gearbox: the opposite pedal brakes first, then selects the other gear
        if gasDown && reverseDown {
            braking = true
            velocity = approach(velocity, 0, brakeDecel * dt)
        } else if gasDown {
            if gear == .reverse && velocity < -2 {
                braking = true
                velocity = approach(velocity, 0, brakeDecel * dt)
            } else {
                gear = .drive
                let headroom = max(0, 1 - velocity / maxForward)
                // Engine pull follows the torque curve; it dips for a moment at each gear change
                let x = rpm / redline
                let torque = max(0.35, 1 - pow((x - 0.62) / 0.5, 2))
                let pull = (0.72 + 0.36 * torque) * (shiftCut > 0 ? 0.35 : 1)
                velocity += engineAccel * pow(headroom, 0.7) * pull * dt
            }
        } else if reverseDown {
            if gear == .drive && velocity > 2 {
                braking = true
                velocity = approach(velocity, 0, brakeDecel * dt)
            } else {
                gear = .reverse
                let headroom = max(0, 1 - (-velocity) / maxReverse)
                velocity -= reverseAccel * pow(headroom, 0.7) * dt
            }
        } else {
            let creep = engaged ? (gear == .drive ? creepSpeed : -creepSpeed) : 0
            if abs(velocity) < creepSpeed && engaged {
                velocity = approach(velocity, creep, 30 * dt)
            } else {
                // Rolling resistance, air drag and engine braking in gear
                let engineBrake = gear == .drive ? 16 * rpm / redline : 0
                let resistance = (rolling + engineBrake + airDrag * velocity * velocity * 0.01) * dt
                velocity = approach(velocity, creep, resistance)
            }
        }
        if isBoosting && gear == .drive {
            braking = false
            velocity += nitroPush * dt
        }
        let topSpeed = isBoosting ? maxForward * 1.7 : maxForward
        if velocity > topSpeed {
            velocity = isBoosting ? topSpeed : max(topSpeed, velocity - 110 * dt)
        }
        velocity = max(-maxReverse, velocity)
        runTopSpeed = max(runTopSpeed, Int(abs(velocity) * 0.36))

        let handbrake = isPressed(.handbrake)
        // Full lock while sliding, so the player can counter-steer
        let speedFactor = drifting ? 1 : 1 - 0.4 * min(1, abs(velocity) / maxForward)
        let targetSteer = wheelInput * maxSteer * speedFactor
        steer = approach(steer, targetSteer, steerRate * (drifting ? 1.6 : 1) * dt)

        // Drift: the body (heading) and the direction of travel (travelHeading) come apart.
        // Pulling the handbrake at speed locks the rear wheels and kicks the tail out toward the
        // steering; then the throttle keeps the rear wheels spinning (little rear grip, the angle
        // holds), counter-steer balances it, and lifting off gives the grip back. Steering into
        // the slide on throttle spins the car; the car's yaw has inertia, so the angle builds and
        // settles instead of jumping.
        if !drifting { travelHeading = heading }
        if handbrake && velocity > 40 && !drifting && airTime <= 0 { startDrift() }
        var steerYaw = velocity / wheelBase * tan(steer)
        // The tyres can only hold so much sideways force: past it the car runs wide (understeer)
        // and the tyres squeal
        let maxLateral: CGFloat = 420
        understeer = 0
        if !drifting && abs(velocity * steerYaw) > maxLateral {
            understeer = min(1, (abs(velocity * steerYaw) - maxLateral) / 300)
            steerYaw = (steerYaw > 0 ? 1 : -1) * maxLateral / max(abs(velocity), 1)
        }
        var newHeading = heading + steerYaw * dt
        if drifting && airTime <= 0 {
            var slip = CGFloat.angleDelta(travelHeading, heading)
            let speedShare = min(1, abs(velocity) / 90)
            let rearGrip: CGFloat = handbrake ? 0.25 : (gasDown ? 0.6 : 2.2)
            var target = 0.8 * steerYaw - slip * rearGrip * 3
            if gasDown && !handbrake {
                // Power oversteer: wheelspin pushes the tail further out
                target += (slip >= 0 ? 1 : -1) * 2.6 * speedShare * min(1, abs(slip) / 0.35)
            }
            if handbrake && abs(wheelInput) > 0.1 { target += (wheelInput > 0 ? 1 : -1) * speedShare }
            yawSpeed += (target - yawSpeed) * min(1, dt * 3)
            newHeading = heading + yawSpeed * dt
            // The tyres drag the direction of travel round toward where the car points
            let pull: CGFloat = handbrake ? 0.7 : (gasDown ? 1.4 : 2.4)
            travelHeading += CGFloat.angleDelta(travelHeading, newHeading) * min(1, pull * dt)
            slip = CGFloat.angleDelta(travelHeading, newHeading)
            // Sliding sideways scrubs speed; the locked rear wheels even more
            velocity -= velocity * (0.3 * abs(sin(slip)) + (handbrake ? 0.5 : 0)) * dt
            if handbrake { braking = true }
            let before = driftClock
            driftClock += dt
            driftScore += abs(velocity) * abs(slip) * dt * 0.9
            if before < 2.2 && driftClock >= 2.2 { dispatchPolice(Strings.crimeDrift) }
            // Grip back: small angle for a moment, or the tail swung past straight
            driftCalm = abs(slip) < (gasDown ? 0.06 : 0.16) ? driftCalm + dt : 0
            if abs(slip) > 1.55 {
                // Spun out: the slide stops the car and the points are lost
                failDrift()
                velocity *= 0.4
                yawSpeed *= 0.5
                newHeading = heading
                bumpHaptic.impactOccurred(intensity: 0.6)
            } else if !handbrake && (driftCalm > 0.25 || slip * driftSide < -0.05) {
                endDrift()
            } else if abs(velocity) < 20 {
                endDrift()
            }
        } else {
            yawSpeed = airTime > 0 ? 0 : steerYaw
        }
        if airTime > 0 { newHeading = heading }   // no steering in the air
        let yawRate = (newHeading - heading) / max(dt, 0.0001)
        let moveHeading = drifting ? travelHeading : newHeading
        let newPosition = CGPoint(x: carPosition.x + cos(moveHeading) * velocity * dt,
                                  y: carPosition.y + sin(moveHeading) * velocity * dt)

        let longitudinal = (velocity - previousVelocity) / max(dt, 0.001)
        longitudinalAccel += (longitudinal - longitudinalAccel) * min(1, dt * 8)
        lateralAccel += (velocity * yawRate - lateralAccel) * min(1, dt * 8)

        // Hitting another car is handled first, from the speed at which the two cars close in
        // (head-on, glancing or from behind alike), so every real car crash reacts the same way
        if let impact = carImpact(OBB(center: newPosition, size: Levels.carSize, angle: newHeading), to: newPosition) {
            // A real crash (not just leaning on a stopped car); the same rule for every car
            if impact.closing > 22 && lastUpdate - lastHitAt > 0.45 {
                lastHitAt = lastUpdate
                hits += 1
                if benchmark { FrameMonitor.shared.mark("hit") }
                hitsLabel.text = "\(hits)"
                crashCar(impact)
            }
            // Most of our momentum goes into the crash; we do not drive into the other car
            velocity *= 0.3
            applyCrashMotion(dt)
            gearLabel.text = gear == .drive ? "\(gearIndex)" : "R"
            tyreEffects(dt, accelerating: gasDown || reverseDown)
            return
        }

        // Scraping along a curb, wall or parked car: keep the free axis instead of stopping dead
        var slid = false
        var lostSpeed = abs(velocity)
        if blocked(moving: OBB(center: newPosition, size: Levels.carSize, angle: newHeading), to: newPosition) {
            let candidates = [(CGPoint(x: newPosition.x, y: carPosition.y), abs(sin(heading) * velocity)),
                              (CGPoint(x: carPosition.x, y: newPosition.y), abs(cos(heading) * velocity))]
            for (candidate, lost) in candidates.sorted(by: { $0.1 < $1.1 }) where candidate.distance(to: carPosition) > 0.05 {
                if !blocked(moving: OBB(center: candidate, size: Levels.carSize, angle: heading), to: candidate) {
                    carPosition = candidate
                    lostSpeed = lost
                    slid = true
                    break
                }
            }
        }
        if slid {
            velocity *= 0.94
            if lostSpeed > 45 && lastUpdate - lastHitAt > 0.6 {
                lastHitAt = lastUpdate
                hits += 1
                if benchmark { FrameMonitor.shared.mark("hit") }
                hitsLabel.text = "\(hits)"
                bumpHaptic.impactOccurred(intensity: 0.5)
                audio.play("bump", volume: 0.5)
            } else if lostSpeed > 8 {
                tickHaptic.impactOccurred(intensity: 0.25)
            }
        } else if blocked(moving: OBB(center: newPosition, size: Levels.carSize, angle: newHeading), to: newPosition) {
            let impact = abs(velocity)
            var crashed = false
            if lastUpdate - lastHitAt > 0.6 && impact > 18 {
                lastHitAt = lastUpdate
                hits += 1
                if benchmark { FrameMonitor.shared.mark("hit") }
                hitsLabel.text = "\(hits)"
                bumpHaptic.impactOccurred(intensity: min(1, impact / 120 + 0.4))
                let direction: CGFloat = velocity >= 0 ? 1 : -1
                dust(at: CGPoint(x: carPosition.x + cos(heading) * 22 * direction,
                                 y: carPosition.y + sin(heading) * 22 * direction))
                crashed = crash(into: OBB(center: newPosition, size: Levels.carSize, angle: newHeading), impact: impact)
                if impact > 40 { failDrift() }
                if !crashed {
                    audio.play("bump", volume: Float(min(1, impact / 100 + 0.3)))
                    world?.shake(strength: min(6, impact / 20))
                }
            }
            velocity = abs(velocity) < 6 ? 0 : -velocity * (crashed ? 0.12 : 0.22)
            longitudinalAccel = -longitudinalAccel
        } else {
            carPosition = newPosition
            heading = newHeading
        }

        applyCrashMotion(dt)
        updateJump(dt)
        updateDriftDisplay(dt)

        gearLabel.text = gear == .drive ? "\(gearIndex)" : "R"
        gearLabel.fontColor = gear == .drive ? UIColor(red: 0.45, green: 0.95, blue: 0.6, alpha: 1)
                                             : UIColor(red: 1.0, green: 0.55, blue: 0.45, alpha: 1)
        tyreEffects(dt, accelerating: gasDown || reverseDown)
    }

    /// Picks the gear from the speed (up near the top of each gear, down well below it) and
    /// eases the rpm toward that gear's revs: quick to rise, quicker to drop on a shift.
    private func updateGearbox(_ dt: CGFloat, throttle: Bool) {
        let speed = abs(velocity)
        shiftCut = max(0, shiftCut - dt)
        var target: CGFloat
        if gear == .reverse && velocity < -1 {
            target = idleRPM + (redline * 0.75 - idleRPM) * min(1, speed / maxReverse)
        } else {
            let ratio = speed / (gearTops[gearIndex - 1] * maxForward)
            if ratio > 0.95 && gearIndex < gearTops.count && (throttle || isBoosting) && phase == .driving {
                gearIndex += 1
                shiftCut = 0.16
                audio.play("shift", volume: 0.22)
                tickHaptic.impactOccurred(intensity: 0.3)
            } else if gearIndex > 1 && speed < gearTops[gearIndex - 2] * maxForward * 0.62 {
                gearIndex -= 1
            }
            target = idleRPM + (redline - idleRPM) * min(1.02, speed / (gearTops[gearIndex - 1] * maxForward))
        }
        // Revving on the spot, and wheelspin in a drift
        if throttle && speed < 15 { target = max(target, phase == .countdown ? 5400 : 2800) }
        if throttle && drifting { target = max(target, redline * 0.86) }
        let rate: CGFloat = target > rpm ? 9 : (shiftCut > 0 ? 22 : 5)
        rpm += (target - rpm) * min(1, rate * dt)
        // Lifting off at high revs: the exhaust pops
        if lastThrottle && !throttle && rpm > 5000 && speed > 60 && phase == .driving && CGFloat.random(in: 0...1) < 0.65 {
            audio.play("pop", volume: 0.32)
        }
        lastThrottle = throttle
        if gear == .drive, gearLabel.text != "\(gearIndex)", phase == .driving { gearLabel.text = "\(gearIndex)" }
    }

    private func approach(_ value: CGFloat, _ target: CGFloat, _ step: CGFloat) -> CGFloat {
        if value < target { return min(value + step, target) }
        return max(value - step, target)
    }

    // MARK: Drift, jumps, near misses, props and police

    private func startDrift() {
        drifting = true
        driftScore = 0
        driftClock = 0
        driftCalm = 0
        travelHeading = heading
        // The handbrake kicks the tail out toward the steering
        driftSide = wheelInput > 0.1 ? 1 : (wheelInput < -0.1 ? -1 : (steer >= 0 ? 1 : -1))
        yawSpeed = velocity / wheelBase * tan(steer) + driftSide * 1.6
        tickHaptic.impactOccurred(intensity: 0.7)
    }

    /// A finished drift: its points become nitro.
    private func endDrift() {
        guard drifting else { return }
        drifting = false
        lastDriftEnd = lastUpdate
        lastDriftScore = driftScore
        travelHeading = heading
        let points = Int(driftScore.rounded())
        if driftScore > 40 && driftClock > 0.4 {
            runDriftPoints += points
            nitro = min(1, nitro + min(0.6, driftScore / 1500))
            flashBonus(Strings.driftBonus(points))
            audio.play("whoosh", volume: 0.5)
            notifyHaptic.notificationOccurred(.success)
        }
        driftScore = 0
    }

    /// A crash during a drift loses its points.
    private func failDrift() {
        guard drifting else { return }
        drifting = false
        lastDriftEnd = -10
        lastDriftScore = 0
        travelHeading = heading
        if driftScore > 40 { flashBonus(Strings.driftLost) }
        driftScore = 0
    }

    private func updateDriftDisplay(_ dt: CGFloat) {
        if drifting && driftScore > 5 {
            let points = Int(driftScore.rounded())
            if points != shownDriftPoints {
                shownDriftPoints = points
                driftLabel.text = "\(Strings.driftLabel) \(points)"
            }
            if driftLabel.alpha < 1 {
                driftLabel.removeAllActions()
                driftLabel.alpha = 1
                driftLabel.setScale(0.7)
                driftLabel.run(.scale(to: 1, duration: 0.15))
            }
            // Thick tyre smoke from the rear wheels
            driftSmokeClock += dt
            if driftSmokeClock > 0.07 {
                driftSmokeClock = 0
                for side: CGFloat in [11, -11] {
                    let point = CGPoint(x: carPosition.x - 14 * cos(heading) - side * sin(heading),
                                        y: carPosition.y - 14 * sin(heading) + side * cos(heading))
                    tyreSmoke(at: point)
                }
            }
        } else if driftLabel.alpha > 0.01 && driftLabel.action(forKey: "out") == nil {
            shownDriftPoints = -1
            driftLabel.run(.sequence([.fadeAlpha(to: 0.002, duration: 0.25)]), withKey: "out")
        }
    }

    private func tyreSmoke(at point: CGPoint) {
        guard let screen = world?.project(point, height: 0.3) else { return }
        let puff = SKSpriteNode(texture: dotTexture)
        puff.size = CGSize(width: 16, height: 16)
        puff.color = UIColor(white: 0.92, alpha: 1)
        puff.colorBlendFactor = 1
        puff.position = screen
        puff.alpha = 0.42
        fxLayer.addChild(puff)
        puff.run(.sequence([
            .group([.scale(to: 4.0, duration: 0.9), .fadeOut(withDuration: 0.9),
                    .moveBy(x: CGFloat.random(in: -14...14), y: CGFloat.random(in: 4...20), duration: 0.9)]),
            .removeFromParent()
        ]))
    }

    /// Height of a ramp under a point (meters), and the distance along the ramp.
    private func rampHeight(at p: CGPoint) -> CGFloat {
        for ramp in level.ramps {
            let along = ramp.alongX ? p.x - ramp.center.x : p.y - ramp.center.y
            let across = ramp.alongX ? p.y - ramp.center.y : p.x - ramp.center.x
            let half = RampDef.length / 2
            let top = half * 0.25
            guard abs(across) < RampDef.width / 2, abs(along) < half else { continue }
            if abs(along) < top { return RampDef.height }
            return RampDef.height * (half - abs(along)) / (half - top)
        }
        return 0
    }

    /// Takes off from the top of a ramp at speed; lands with a thump and a nitro bonus.
    private func updateJump(_ dt: CGFloat) {
        if airTime > 0 {
            airTime -= dt
            if airTime <= 0 {
                airTime = 0
                bumpHaptic.impactOccurred(intensity: 1.0)
                audio.play("bump", volume: 0.8)
                world?.shake(strength: 4)
                dust(at: carPosition)
                nitro = min(1, nitro + 0.2)
                flashBonus(Strings.jump)
            }
            return
        }
        guard rampHeight(at: carPosition) >= RampDef.height - 0.01, abs(velocity) > 50, lastUpdate - rampCooldown > 1.2 else { return }
        rampCooldown = lastUpdate
        airDuration = 0.35 + abs(velocity) / 320
        airPeak = min(3.2, abs(velocity) * 0.014)
        airTime = airDuration
        if drifting { endDrift() }
        tickHaptic.impactOccurred(intensity: 1.0)
    }

    /// The car's height above the ground (on a ramp or in the air) and its pitch in the air.
    private func carLift() -> (Float, CGFloat) {
        if airTime > 0, airDuration > 0 {
            let t = 1 - airTime / airDuration
            let height = RampDef.height * (1 - t) + 4 * airPeak * t * (1 - t)
            return (Float(height), 0.12 * (1 - 2 * t))
        }
        return (Float(rampHeight(at: carPosition)), 0)
    }

    /// Near misses, flying props, the police chase and the trail it follows.
    private func updateArcade(_ dt: CGFloat, traffic: Traffic) {
        let driving = phase == .driving && !localParked
        let moveHeading = drifting ? travelHeading : heading
        // Near miss: passing a car side by side with less than about a meter between them
        if driving && abs(velocity) > 70 && airTime <= 0 {
            for (index, bot) in traffic.bots.enumerated() {
                let dx = bot.position.x - carPosition.x, dy = bot.position.y - carPosition.y
                if abs(dx) > 60 || abs(dy) > 60 { continue }
                let along = dx * cos(heading) + dy * sin(heading)
                let across = -dx * sin(heading) + dy * cos(heading)
                guard abs(along) < 20, abs(across) > 23, abs(across) < 34 else { continue }
                guard lastUpdate - (nearMissAt[index] ?? -10) > 3, lastUpdate - lastHitAt > 1 else { continue }
                nearMissAt[index] = lastUpdate
                nitro = min(1, nitro + 0.12)
                flashBonus(Strings.nearMiss)
                runNearMisses += 1
                audio.play("whoosh", volume: 0.8)
                tickHaptic.impactOccurred(intensity: 0.8)
            }
        }
        // Props: our car, the traffic and the police knock them over
        if let props = streetProps {
            var hitters: [(position: CGPoint, velocity: CGVector, heading: CGFloat)] = [
                (carPosition, airTime > 0 ? .zero : CGVector(dx: cos(moveHeading) * velocity, dy: sin(moveHeading) * velocity), heading)
            ]
            for bot in traffic.bots where abs(bot.position.x - carPosition.x) < 800 && abs(bot.position.y - carPosition.y) < 800 {
                hitters.append((bot.position, CGVector(dx: cos(bot.heading) * bot.speed, dy: sin(bot.heading) * bot.speed), bot.heading))
            }
            if props.step(dt, hitters: hitters) > 0 {
                velocity *= 0.92
                audio.play("bump", volume: 0.4)
                tickHaptic.impactOccurred(intensity: 0.6)
            }
        }
        // The trail the police follows
        trailClock += dt
        if trailClock > 0.1 && driving {
            trailClock = 0
            trail.append(carPosition)
            if trail.count > 140 { trail.removeFirst(trail.count - 140) }
        }
        // The friend's police car (online): shown where the friend's game says it is
        var siren: CGFloat = 0
        if let target = remotePoliceTarget, friendPresent, !remoteParked, let world = world, let city = level.city {
            if remotePolice == nil {
                remotePolice = PoliceChase(node: world.makePoliceNode(), map: city, start: target.position)
            }
            remotePolice?.mirror(dt, to: target.position, heading: target.heading, viewer: carPosition)
            if let other = remotePolice { siren = max(siren, 0.6 - other.distance / 1600) }
        } else if remotePolice != nil {
            removeRemotePolice()
        }
        if let chase = police, driving {
            let outcome = chase.step(dt, player: carPosition, playerSpeed: abs(velocity), trail: trail)
            // The siren gets louder as the police closes in
            siren = max(siren, max(0.12, min(0.8, 0.85 - chase.distance / 1600)))
            updatePoliceWarning(chase)
            switch outcome {
            case .caught:
                hits += 2
                hitsLabel.text = "\(hits)"
                velocity *= 0.3
                flashBonus(Strings.policeCaught)
                notifyHaptic.notificationOccurred(.error)
                endPoliceChase()
            case .escaped:
                runEscapes += 1
                nitro = 1
                flashBonus(Strings.policeEscaped)
                notifyHaptic.notificationOccurred(.success)
                endPoliceChase()
            case .none:
                break
            }
        } else if police != nil {
            endPoliceChase()
        }
        audio.setLoop("siren", volume: phase == .driving && !localParked ? Float(max(0, siren)) : 0)
    }

    private func removeRemotePolice() {
        guard let other = remotePolice else { return }
        remotePolice = nil
        other.node.runAction(.sequence([.fadeOut(duration: 0.5), .removeFromParentNode()]))
    }

    /// A crime (crash, hitting a pedestrian, a long drift, speeding past a radar) calls the police:
    /// a cruiser sets off from an intersection some way off and drives the streets to us with its
    /// siren on, then chases us. Another crime during a chase keeps it going longer.
    private func dispatchPolice(_ reason: String) {
        guard let city = level.city, let world = world, phase == .driving, !localParked else { return }
        if let chase = police {
            chase.extend()
            showPoliceWarning(reason)
            return
        }
        guard lastUpdate >= policeCooldownUntil else { return }
        // An intersection 45–90 m away, preferably behind us
        var best: CGPoint?
        var bestScore = CGFloat.greatestFiniteMagnitude
        for x in city.xs {
            for y in city.ys {
                let point = CGPoint(x: x, y: y)
                let d = point.distance(to: carPosition)
                let ahead = ((x - carPosition.x) * cos(heading) + (y - carPosition.y) * sin(heading)) / max(d, 1)
                let score = abs(d - 650) + (d < 380 ? 2000 : 0) + max(0, ahead) * 400
                if score < bestScore {
                    bestScore = score
                    best = point
                }
            }
        }
        guard let start = best else { return }
        police = PoliceChase(node: world.makePoliceNode(), map: city, start: start)
        showPoliceWarning(reason)
        notifyHaptic.notificationOccurred(.warning)
    }

    private func endPoliceChase() {
        guard let chase = police else { return }
        police = nil
        policeCooldownUntil = lastUpdate + 10
        audio.setLoop("siren", volume: 0)
        hidePoliceWarning()
        chase.node.runAction(.sequence([.wait(duration: 1.5), .fadeOut(duration: 0.6), .removeFromParentNode()]))
    }

    // MARK: Police warning

    private var policeCooldownUntil: TimeInterval = 0
    /// The friend's police car: the last pose they sent, and its node here.
    private var remotePoliceTarget: (position: CGPoint, heading: CGFloat)?
    private var remotePolice: PoliceChase?
    private var policeBanner = SKNode()
    private var policeTitle = SKLabelNode()
    private var policeDetail = SKLabelNode()
    private var policeBannerBack = SKShapeNode()
    private var policeEdges: [SKShapeNode] = []
    private var policeReason = ""

    /// Built with the HUD (hidden), so the first chase does not stall on new nodes.
    private func setupPoliceWarning() {
        policeBanner.removeFromParent()
        policeEdges.forEach { $0.removeFromParent() }
        policeEdges.removeAll()
        policeBanner = SKNode()
        policeBanner.position = CGPoint(x: size.width / 2, y: size.height * 0.80)
        policeBanner.zPosition = 22
        // Not 0: SpriteKit skips fully transparent nodes, so the label's text would be laid out
        // only on the first chase
        policeBanner.alpha = 0.002
        let width = min(size.width - 40, 330)
        policeBannerBack = SKShapeNode(rect: CGRect(x: -width / 2, y: -24, width: width, height: 48), cornerRadius: 14)
        policeBannerBack.fillColor = UIColor(red: 0.08, green: 0.02, blue: 0.04, alpha: 0.82)
        policeBannerBack.strokeColor = UIColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
        policeBannerBack.lineWidth = 2.5
        policeBanner.addChild(policeBannerBack)
        policeTitle = makeLabel(Strings.policeComing, size: 18, color: .white)
        policeTitle.position = CGPoint(x: 0, y: 2)
        policeBanner.addChild(policeTitle)
        policeDetail = makeLabel("", size: 11, color: UIColor(white: 1, alpha: 0.85))
        policeDetail.position = CGPoint(x: 0, y: -16)
        policeBanner.addChild(policeDetail)
        hud.addChild(policeBanner)
        // Red and blue glow on the screen edges
        for (index, color) in [UIColor(red: 1, green: 0.1, blue: 0.1, alpha: 1), UIColor(red: 0.15, green: 0.4, blue: 1, alpha: 1)].enumerated() {
            let edge = SKShapeNode(rect: CGRect(x: index == 0 ? 0 : size.width - 16, y: 0, width: 16, height: size.height))
            edge.fillColor = color
            edge.strokeColor = .clear
            edge.glowWidth = 0
            edge.alpha = 0.002
            edge.zPosition = 20
            edge.blendMode = .add
            hud.addChild(edge)
            policeEdges.append(edge)
        }
    }

    private func showPoliceWarning(_ reason: String) {
        if policeBanner.parent == nil { setupPoliceWarning() }
        policeReason = reason
        policeBanner.removeAllActions()
        policeBanner.alpha = 1
        policeBanner.setScale(0.7)
        policeBanner.run(.sequence([.scale(to: 1.08, duration: 0.14), .scale(to: 1.0, duration: 0.1)]))
        audio.play("beep", volume: 0.6)
    }

    private func hidePoliceWarning() {
        policeBanner.removeAllActions()
        policeBanner.run(.fadeAlpha(to: 0.002, duration: 0.3))
        policeEdges.forEach { $0.run(.fadeAlpha(to: 0.002, duration: 0.3)) }
    }

    private func updatePoliceWarning(_ chase: PoliceChase) {
        let meters = Int((chase.distance / 10).rounded())
        let title = chase.pursuing ? Strings.policeChase : Strings.policeComing
        if policeTitle.text != title { policeTitle.text = title }
        let detail = "\(policeReason) · \(meters) m"
        if policeDetail.text != detail { policeDetail.text = detail }
        let flash = Int(lastUpdate * 6) % 2 == 0
        policeBannerBack.strokeColor = flash ? UIColor(red: 1, green: 0.2, blue: 0.2, alpha: 1) : UIColor(red: 0.25, green: 0.5, blue: 1, alpha: 1)
        // The closer the police, the stronger the edge glow
        let strength = max(0.25, min(0.7, 0.8 - chase.distance / 1500))
        if policeEdges.count == 2 {
            policeEdges[0].alpha = flash ? strength : strength * 0.15
            policeEdges[1].alpha = flash ? strength * 0.15 : strength
        }
    }

    // MARK: Collisions

    private struct CarImpact {
        let contact: Contact
        let center: CGPoint
        let otherVelocity: CGVector
        /// Speed at which the two cars approach each other (world units/s).
        let closing: CGFloat
    }

    /// A moving car (traffic or friend) the move would run into, with the closing speed.
    private func carImpact(_ box: OBB, to newPosition: CGPoint) -> CarImpact? {
        let mine = CGVector(dx: cos(heading) * velocity, dy: sin(heading) * velocity)
        var best: CarImpact?
        for contact in contacts(box) {
            var other: CGVector
            switch contact {
            case .bot(let index):
                guard let bots = traffic?.bots, index < bots.count else { continue }
                let bot = bots[index]
                other = CGVector(dx: cos(bot.heading) * bot.speed, dy: sin(bot.heading) * bot.speed)
            case .remoteCar:
                let v = remoteSnapshots.last?.velocity ?? 0
                other = CGVector(dx: cos(remoteHeading) * v, dy: sin(remoteHeading) * v)
            default:
                continue
            }
            guard let c = center(of: contact) else { continue }
            let dx = c.x - carPosition.x, dy = c.y - carPosition.y
            let length = max(1, hypot(dx, dy))
            let closing = ((mine.dx - other.dx) * dx + (mine.dy - other.dy) * dy) / length
            // Only when we actually move into it (otherwise the cars just separate)
            let oldDistance = hypot(carPosition.x - c.x, carPosition.y - c.y)
            let newDistance = hypot(newPosition.x - c.x, newPosition.y - c.y)
            guard closing > 10 || newDistance < oldDistance - 0.01 else { continue }
            if best == nil || closing > best!.closing {
                best = CarImpact(contact: contact, center: c, otherVelocity: other, closing: closing)
            }
        }
        return best
    }

    /// Car-on-car crash: always a clear reaction, stronger with the closing speed. We are knocked
    /// away from the other car and spun by the side of the hit; a traffic car takes our momentum.
    private func crashCar(_ impact: CarImpact) {
        failDrift()
        let strength = max(0.3, min(1, impact.closing / (maxForward * 0.75)))
        let dx = impact.center.x - carPosition.x, dy = impact.center.y - carPosition.y
        let length = max(1, hypot(dx, dy))
        let nx = dx / length, ny = dy / length
        let side = cos(heading) * dy - sin(heading) * dx          // > 0: the hit is on our left
        let forwardness = cos(heading) * nx + sin(heading) * ny
        let spinSign: CGFloat = side >= 0 ? -1 : 1
        crashSpin = spinSign * (1.8 + 3.2 * strength) * (0.6 + 0.4 * (1 - abs(forwardness)))
        let push = 70 + 160 * strength
        crashShove = CGVector(dx: -nx * push + impact.otherVelocity.dx * 0.3, dy: -ny * push + impact.otherVelocity.dy * 0.3)
        if case .bot(let index) = impact.contact {
            let kick = 40 + impact.closing * 0.6
            traffic?.hit(index, shove: CGVector(dx: nx * kick, dy: ny * kick), spin: -spinSign * (1.4 + 2.4 * strength))
        }
        audio.play("crash", volume: Float(min(1, 0.45 + strength * 0.6)))
        bumpHaptic.impactOccurred(intensity: min(1, 0.6 + strength * 0.4))
        world?.shake(strength: 3 + 7 * strength)
        dispatchPolice(Strings.crimeCrash)
        sparks(at: CGPoint(x: (carPosition.x + impact.center.x) / 2, y: (carPosition.y + impact.center.y) / 2))
        dust(at: CGPoint(x: (carPosition.x + impact.center.x) / 2, y: (carPosition.y + impact.center.y) / 2))
    }

    /// A real crash (into a car, or a wall at speed): crunch sound, a shove away from the hit and a
    /// spin that depends on where the hit landed, like arcade racers. The traffic car we hit is
    /// shoved and spun too. Returns false for light bumps.
    private func crash(into box: OBB, impact: CGFloat) -> Bool {
        let before = contacts(OBB(center: carPosition, size: Levels.carSize, angle: heading))
        let new = contacts(box).subtracting(before)
        let hitCar = new.contains { if case .bot = $0 { return true }; if case .remoteCar = $0 { return true }; return false }
        guard impact > (hitCar ? 35 : 70) else { return false }
        let strength = min(1, impact / maxForward)
        // Where the other thing is: the side of the hit decides the spin direction
        var other = CGPoint(x: carPosition.x + cos(heading) * 30 * (velocity >= 0 ? 1 : -1),
                            y: carPosition.y + sin(heading) * 30 * (velocity >= 0 ? 1 : -1))
        for contact in new { if let c = center(of: contact) { other = c; break } }
        let dx = other.x - carPosition.x, dy = other.y - carPosition.y
        let length = max(1, hypot(dx, dy))
        let side = cos(heading) * dy - sin(heading) * dx          // > 0: the hit is on our left
        let forwardness = (cos(heading) * dx + sin(heading) * dy) / length
        let spinSign: CGFloat = side >= 0 ? -1 : 1
        crashSpin = spinSign * (1.6 + 3.4 * strength) * (0.55 + 0.45 * (1 - abs(forwardness)))
        let push = 55 + 150 * strength
        crashShove = CGVector(dx: -dx / length * push, dy: -dy / length * push)
        for contact in new {
            if case .bot(let index) = contact {
                // Our momentum goes into the other car
                let travel = velocity >= 0 ? heading : heading + CGFloat.pi
                traffic?.hit(index, shove: CGVector(dx: cos(travel) * impact * 0.55, dy: sin(travel) * impact * 0.55),
                             spin: -spinSign * (1.2 + 2.6 * strength))
            }
        }
        audio.play("crash", volume: Float(min(1, 0.5 + strength * 0.6)))
        bumpHaptic.impactOccurred(intensity: 1.0)
        world?.shake(strength: 3 + 7 * strength)
        sparks(at: CGPoint(x: (carPosition.x + other.x) / 2, y: (carPosition.y + other.y) / 2))
        dispatchPolice(hitCar ? Strings.crimeCrash : Strings.crimeReckless)
        return true
    }

    /// Slides and spins the car after a crash; both fade out within about a second.
    private func applyCrashMotion(_ dt: CGFloat) {
        guard abs(crashSpin) > 0.02 || hypot(crashShove.dx, crashShove.dy) > 2 else {
            crashSpin = 0
            crashShove = .zero
            return
        }
        let candidate = CGPoint(x: carPosition.x + crashShove.dx * dt, y: carPosition.y + crashShove.dy * dt)
        let turned = heading + crashSpin * dt
        let box = OBB(center: candidate, size: Levels.carSize, angle: turned)
        if !blocked(moving: box, to: candidate) {
            carPosition = candidate
            heading = turned
        } else if !blocked(moving: OBB(center: carPosition, size: Levels.carSize, angle: turned), to: carPosition) {
            heading = turned
            crashShove = .zero
        } else {
            crashShove = .zero
            crashSpin = 0
        }
        let fade = exp(-dt * 3.4)
        crashShove = CGVector(dx: crashShove.dx * fade, dy: crashShove.dy * fade)
        crashSpin *= fade
        // Tyres screech while the car spins
        if abs(crashSpin) > 1.0 {
            skidClock += dt
            if skidClock > 0.03 {
                skidClock = 0
                for side: CGFloat in [10, -10] {
                    world?.addSkid(at: CGPoint(x: carPosition.x - 13 * cos(heading) - side * sin(heading),
                                               y: carPosition.y - 13 * sin(heading) + side * cos(heading)))
                }
            }
        }
    }

    private var remoteBox: OBB { OBB(center: remotePosition, size: Levels.carSize, angle: remoteHeading) }

    private func contacts(_ box: OBB, includeRemote: Bool = true) -> Set<Contact> {
        var result = Set<Contact>()
        let world = level.world
        let curb: CGFloat = isCity ? 4 : 8
        for corner in box.corners {
            if corner.x < curb || corner.y < curb || corner.x > world.width - curb || corner.y > world.height - curb {
                result.insert(.bounds)
                break
            }
        }
        for (index, obstacle) in obstacleBoxes.enumerated() {
            let dx = obstacle.center.x - box.center.x
            let dy = obstacle.center.y - box.center.y
            let limit = 60 + max(obstacle.halfSize.width, obstacle.halfSize.height)
            if abs(dx) > limit || abs(dy) > limit { continue }
            if box.intersects(obstacle) { result.insert(.obstacle(index)) }
        }
        if includeRemote && friendPresent && remoteTarget != nil && box.intersects(remoteBox) {
            result.insert(.remoteCar)
        }
        if let traffic = traffic {
            for (index, bot) in traffic.bots.enumerated() {
                if abs(bot.position.x - box.center.x) > 60 || abs(bot.position.y - box.center.y) > 60 { continue }
                if box.intersects(bot.box) { result.insert(.bot(index)) }
            }
        }
        return result
    }

    private func center(of contact: Contact) -> CGPoint? {
        switch contact {
        case .bounds: return nil
        case .obstacle(let index): return obstacleBoxes[index].center
        case .remoteCar: return remotePosition
        case .bot(let index):
            guard let bots = traffic?.bots, index < bots.count else { return nil }
            return bots[index].position
        }
    }

    /// A move is blocked by any new contact. Contacts that already exist (for example when the
    /// other car drove into us) only block moves that go deeper, so the cars can always separate.
    private func blocked(moving box: OBB, to newPosition: CGPoint) -> Bool {
        let before = contacts(OBB(center: carPosition, size: Levels.carSize, angle: heading))
        let after = contacts(box)
        for contact in after {
            guard before.contains(contact) else { return true }
            if let c = center(of: contact) {
                let oldDistance = hypot(carPosition.x - c.x, carPosition.y - c.y)
                let newDistance = hypot(newPosition.x - c.x, newPosition.y - c.y)
                if newDistance < oldDistance - 0.01 { return true }
            }
        }
        return false
    }

    /// When the two cars overlap, nudge ours away from the other one.
    private func separateFromRemote(_ dt: CGFloat) {
        guard friendPresent, remoteTarget != nil else { return }
        let mine = OBB(center: carPosition, size: Levels.carSize, angle: heading)
        guard mine.intersects(remoteBox) else { return }
        var dx = carPosition.x - remotePosition.x
        var dy = carPosition.y - remotePosition.y
        var length = hypot(dx, dy)
        if length < 0.5 {
            dx = cos(heading + CGFloat.pi / 2)
            dy = sin(heading + CGFloat.pi / 2)
            length = 1
        }
        let push = 45 * dt
        let candidate = CGPoint(x: carPosition.x + dx / length * push, y: carPosition.y + dy / length * push)
        let candidateBox = OBB(center: candidate, size: Levels.carSize, angle: heading)
        if contacts(candidateBox, includeRemote: false).isEmpty {
            carPosition = candidate
        }
    }

    // MARK: Effects

    private func tyreEffects(_ dt: CGFloat, accelerating: Bool) {
        let cornering = (abs(lateralAccel) > 150 && abs(velocity) > 50) || understeer > 0.2
        let hardBrake = braking && abs(velocity) > 60
        let squeal: CGFloat = drifting ? 0.45 : max(understeer > 0 ? 0.14 + 0.2 * understeer : 0,
                                                    cornering ? 0.12 : 0, hardBrake ? 0.2 : 0)
        audio.setLoop("skid", volume: Float(squeal))
        // Wind noise grows with speed
        let speedShare = abs(velocity) / maxForward
        audio.setLoop("wind", volume: Float(max(0, min(0.4, (speedShare - 0.45) * 0.45))))
        skidClock += dt
        if (cornering || hardBrake || drifting) && airTime <= 0 && skidClock > 0.03 {
            skidClock = 0
            for side: CGFloat in [10, -10] {
                let point = CGPoint(x: carPosition.x - 13 * cos(heading) - side * sin(heading),
                                    y: carPosition.y - 13 * sin(heading) + side * cos(heading))
                world?.addSkid(at: point)
            }
        }

        smokeClock += dt
        if accelerating && abs(velocity) < 45 && abs(longitudinalAccel) > 90 && smokeClock > 0.06 {
            smokeClock = 0
            let back: CGFloat = velocity >= 0 ? -1 : 1
            let point = CGPoint(x: carPosition.x + cos(heading) * 22 * back, y: carPosition.y + sin(heading) * 22 * back)
            guard let screen = world?.project(point, height: 0.4) else { return }
            let puff = SKSpriteNode(texture: dotTexture)
            puff.size = CGSize(width: 12, height: 12)
            puff.position = screen
            puff.alpha = 0.35
            fxLayer.addChild(puff)
            puff.run(.sequence([
                .group([.scale(to: 3.2, duration: 0.7), .fadeOut(withDuration: 0.7),
                        .moveBy(x: CGFloat.random(in: -10...10), y: CGFloat.random(in: 2...14), duration: 0.7)]),
                .removeFromParent()
            ]))
        }
    }

    private func dust(at point: CGPoint) {
        guard let screen = world?.project(point, height: 0.6) else { return }
        for _ in 0..<8 {
            let puff = SKSpriteNode(texture: dotTexture)
            puff.size = CGSize(width: 10, height: 10)
            puff.color = UIColor(red: 0.85, green: 0.80, blue: 0.70, alpha: 1)
            puff.colorBlendFactor = 1
            puff.position = screen
            puff.alpha = 0.65
            fxLayer.addChild(puff)
            puff.run(.sequence([
                .group([.moveBy(x: CGFloat.random(in: -22...22), y: CGFloat.random(in: -10...24), duration: 0.45),
                        .scale(to: 2.2, duration: 0.45), .fadeOut(withDuration: 0.45)]),
                .removeFromParent()
            ]))
        }
    }

    /// Sparks and bits flying from a crash point.
    private func sparks(at point: CGPoint) {
        guard let screen = world?.project(point, height: 0.7) else { return }
        for index in 0..<16 {
            let spark = SKSpriteNode(texture: dotTexture)
            let hot = index % 3 != 0
            spark.size = hot ? CGSize(width: 5, height: 5) : CGSize(width: 7, height: 7)
            spark.color = hot ? UIColor(red: 1.0, green: 0.78, blue: 0.3, alpha: 1) : UIColor(white: 0.85, alpha: 1)
            spark.colorBlendFactor = 1
            spark.blendMode = hot ? .add : .alpha
            spark.position = screen
            fxLayer.addChild(spark)
            let angle = CGFloat.random(in: 0...(2 * CGFloat.pi))
            let distance = CGFloat.random(in: 30...85)
            let move = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance * 0.7 + 12, duration: 0.4)
            move.timingMode = .easeOut
            spark.run(.sequence([.group([move, .fadeOut(withDuration: 0.4), .scale(to: 0.3, duration: 0.4)]),
                                 .removeFromParent()]))
        }
        dust(at: point)
    }

    // MARK: Parking

    private func checkParking(_ dt: CGFloat) {
        if level.race {
            if level.spots[slot].box.contains(carPosition) { parked() }
            return
        }
        let spot = level.spots[slot]
        let spotBox = spot.box
        let carBox = OBB(center: carPosition, size: Levels.carSize, angle: heading)
        let inside = carBox.corners.allSatisfy { spotBox.contains($0) }
        let misalignment = abs((heading - spot.angle).remainder(dividingBy: CGFloat.pi))
        let aligned = misalignment < 0.21
        let slowEnough = abs(velocity) < 14 && !isPressed(.forward) && !isPressed(.reverse)

        if inside && aligned && slowEnough {
            parkHold += dt
            velocity = approach(velocity, 0, 60 * dt)
            statusLabel.text = Strings.hold
        } else {
            parkHold = max(0, parkHold - dt * 2)
            if statusLabel.text == Strings.hold { statusLabel.text = "" }
        }

        if parkHold > 0.01, let world = world {
            let progress = min(parkHold, 1)
            let radius: CGFloat = 58
            let path = CGMutablePath()
            path.addArc(center: world.project(carPosition, height: 0.1), radius: radius, startAngle: CGFloat.pi / 2,
                        endAngle: CGFloat.pi / 2 - progress * 2 * CGFloat.pi, clockwise: true)
            holdRing.path = path
        } else {
            holdRing.path = nil
        }

        if parkHold >= 1.0 {
            parked()
        }
    }

    private func parked() {
        localParked = true
        localTime = elapsed
        // Drifting into the spot (or the finish) takes 2 s off
        if (drifting || lastUpdate - lastDriftEnd < 2.5) && max(driftScore, lastDriftScore) > 40 {
            localTime = max(0, localTime - 2)
            flashBonus(Strings.driftPark)
        }
        if drifting { endDrift() }
        endPoliceChase()
        audio.setLoop("skid", volume: 0)
        audio.setLoop("wind", volume: 0)
        audio.setLoop("siren", volume: 0)
        if !level.race { velocity = 0 }
        braking = false
        longitudinalAccel = 0
        lateralAccel = 0
        phase = .finished
        holdRing.path = nil
        world?.markParked()
        notifyHaptic.notificationOccurred(.success)
        audio.play("park", volume: 0.9)
        statusLabel.text = level.race ? "" : Strings.parked

        model?.send(["t": "p", "l": levelIndex, "time": localTime, "hits": hits,
                     "x": Double(carPosition.x), "y": Double(carPosition.y), "h": Double(heading)])
        if !isCity {
            model?.levelCompleted(levelIndex)
            newBest = model?.record(level: levelIndex, time: localTime, hits: hits) ?? false
        }
        if level.race {
            playFinishSequence()
        } else {
            playParkedSequence()
        }
    }

    /// Finish line moment. Everything it shows is prepared while the level loads, so it starts on
    /// the very frame the car crosses the line:
    /// 0.0 s  the scene dims at the edges and the title builds letter by letter; slow motion, low camera
    /// 1.0 s  cut to an orbit around the car with fireworks and confetti
    /// 4.0 s  the title eases out, results card
    private func playFinishSequence() {
        if benchRecording { finishCrossAt = Double(benchClock - 2) }
        finishAnimating = true
        finishClock = 0
        world?.startFinishCinematic(at: carPosition, heading: heading, finishLine: level.spots[slot].center)
        audio.play("nitro", volume: 0.45)
        notifyHaptic.notificationOccurred(.success)

        let layer = SKNode()
        layer.zPosition = 300
        addChild(layer)
        for node in [hud, controlsLayer, fxLayer] {
            node.run(.sequence([.fadeOut(withDuration: 0.25), .wait(forDuration: 3.5), .fadeIn(withDuration: 0.3)]))
        }
        speedLines.forEach { $0.sprite.alpha = 0.002 }

        let place = online && friendPresent && remoteParked && remoteTime >= 0 ? 2 : 1
        let together = online && friendPresent
        let won = together && place == 1
        let accent: UIColor = won ? UIColor(red: 1.0, green: 0.78, blue: 0.12, alpha: 1)
            : (together ? UIColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1) : UIColor(red: 0.22, green: 0.84, blue: 1.0, alpha: 1))
        var stats: [(icon: String, text: String)] = [("stopwatch.fill", String(format: "%.1f s", localTime))]
        if level.race { stats.append(("exclamationmark.triangle.fill", Strings.crashes(hits))) }
        let round = levelIndex - Levels.raceBase + 1
        stats.append(("flag.checkered", together ? "P\(place)" : "\(max(1, round))/\(Levels.raceRounds)"))
        let title = won ? Strings.youWon.uppercased() : Strings.finishBig
        presentFinishTitle(in: layer, title: title, kicker: Strings.raceComplete, stats: stats, accent: accent, hold: 3.0)

        run(.wait(forDuration: 1.0)) { [weak self] in self?.finishShotB(layer: layer) }
        if benchmark {
            // After the critical first second, so the capture does not count as a finish hitch
            run(.wait(forDuration: 2.2)) { Task { @MainActor in saveWindowSnapshot(named: "shot-finish") } }
        }
        layer.run(.sequence([.wait(forDuration: 4.1), .removeFromParent()]))
        run(.wait(forDuration: 4.0)) { [weak self] in
            guard let self = self else { return }
            self.finishAnimating = false
            self.checkLevelDone()
        }
    }

    /// Modern finish title: the scene dims at the edges, a light band opens behind the title, the
    /// letters drop in one by one with a springy settle, a shine sweeps across them, the stats
    /// chips rise in turn and golden sparks drift up. Everything eases out together after `hold`.
    private func presentFinishTitle(in layer: SKNode, title: String, kicker: String,
                                    stats: [(icon: String, text: String)], accent: UIColor, hold: TimeInterval) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.58)
        let group = SKNode()
        group.position = center
        layer.addChild(group)

        let vignette = SKSpriteNode(texture: CarArt.finishVignette)
        vignette.size = CGSize(width: size.width * 1.1, height: size.height * 1.1)
        vignette.position = CGPoint(x: size.width / 2, y: size.height / 2)
        vignette.alpha = 0
        layer.addChild(vignette)
        vignette.zPosition = -2
        vignette.run(.fadeAlpha(to: 0.9, duration: 0.45))

        let band = SKSpriteNode(texture: CarArt.finishBand)
        band.size = CGSize(width: size.width * 0.9, height: 120)
        band.color = accent
        band.colorBlendFactor = 1
        band.blendMode = .add
        band.alpha = 0.55
        band.xScale = 0.05
        band.zPosition = -1
        group.addChild(band)
        let open = SKAction.scaleX(to: 1, duration: 0.5)
        open.timingMode = .easeOut
        band.run(.sequence([open, .fadeAlpha(to: 0.3, duration: 0.8)]))

        // Kicker with lines either side
        let kickerLabel = SKLabelNode(text: kicker)
        kickerLabel.fontName = "AvenirNext-Heavy"
        kickerLabel.fontSize = 13
        kickerLabel.fontColor = accent
        kickerLabel.verticalAlignmentMode = .center
        kickerLabel.position = CGPoint(x: 0, y: 52)
        kickerLabel.alpha = 0
        group.addChild(kickerLabel)
        kickerLabel.run(.sequence([.wait(forDuration: 0.1), .group([.fadeIn(withDuration: 0.3), .moveBy(x: 0, y: 6, duration: 0.3)])]))
        for side: CGFloat in [-1, 1] {
            let line = SKSpriteNode(color: accent, size: CGSize(width: 70, height: 2))
            line.anchorPoint = CGPoint(x: side < 0 ? 1 : 0, y: 0.5)
            line.position = CGPoint(x: side * (kickerLabel.frame.width / 2 + 12), y: 58)
            line.xScale = 0
            line.alpha = 0.8
            group.addChild(line)
            let grow = SKAction.scaleX(to: 1, duration: 0.4)
            grow.timingMode = .easeOut
            line.run(.sequence([.wait(forDuration: 0.2), grow]))
        }

        // Letters
        let glyphs = finishGlyphs[title] ?? CarArt.titleGlyphs(title, size: 74)
        let total = glyphs.reduce(0) { $0 + $1.advance }
        let lettersNode = SKNode()
        group.addChild(lettersNode)
        var x = -total / 2
        for (index, glyph) in glyphs.enumerated() {
            let letter = SKSpriteNode(texture: glyph.texture)
            letter.size = glyph.texture.size()
            let home = CGPoint(x: x + glyph.advance / 2, y: 0)
            x += glyph.advance
            letter.position = CGPoint(x: home.x, y: home.y + 26)
            letter.alpha = 0
            letter.setScale(1.7)
            lettersNode.addChild(letter)
            let delay = 0.12 + Double(index) * 0.045
            let drop = SKAction.move(to: CGPoint(x: home.x, y: home.y - 3), duration: 0.2)
            drop.timingMode = .easeOut
            let shrink = SKAction.scale(to: 0.94, duration: 0.2)
            shrink.timingMode = .easeOut
            let settleScale = SKAction.scale(to: 1, duration: 0.16)
            settleScale.timingMode = .easeInEaseOut
            let settleMove = SKAction.move(to: home, duration: 0.16)
            settleMove.timingMode = .easeInEaseOut
            letter.run(.sequence([.wait(forDuration: delay),
                                  .group([.fadeIn(withDuration: 0.12), drop, shrink]),
                                  .group([settleScale, settleMove])]))
        }

        // Shine across the title (cropped to the letters)
        let crop = SKCropNode()
        let mask = SKNode()
        x = -total / 2
        for glyph in glyphs {
            let piece = SKSpriteNode(texture: glyph.texture)
            piece.size = glyph.texture.size()
            piece.position = CGPoint(x: x + glyph.advance / 2, y: 0)
            x += glyph.advance
            mask.addChild(piece)
        }
        crop.maskNode = mask
        let sheen = SKSpriteNode(texture: CarArt.sheenTexture)
        sheen.size = CGSize(width: 60, height: 130)
        sheen.zRotation = -0.35
        sheen.blendMode = .add
        sheen.alpha = 0.9
        sheen.position = CGPoint(x: -total / 2 - 80, y: 0)
        crop.addChild(sheen)
        group.addChild(crop)
        let lettersDone = 0.12 + Double(glyphs.count) * 0.045 + 0.3
        let sweep = SKAction.moveTo(x: total / 2 + 80, duration: 0.55)
        sweep.timingMode = .easeInEaseOut
        sheen.run(.sequence([.wait(forDuration: lettersDone), sweep, .removeFromParent()]))

        // Stats chips
        let chips = stats.map { CarArt.statChip(icon: $0.icon, text: $0.text, accent: accent) }
        let gap: CGFloat = 12
        let chipsWidth = chips.reduce(0) { $0 + $1.size().width } + gap * CGFloat(max(0, chips.count - 1))
        x = -chipsWidth / 2
        for (index, texture) in chips.enumerated() {
            let chip = SKSpriteNode(texture: texture)
            chip.size = texture.size()
            let home = CGPoint(x: x + chip.size.width / 2, y: -70)
            x += chip.size.width + gap
            chip.position = CGPoint(x: home.x, y: home.y - 18)
            chip.alpha = 0
            group.addChild(chip)
            let rise = SKAction.move(to: home, duration: 0.35)
            rise.timingMode = .easeOut
            chip.run(.sequence([.wait(forDuration: lettersDone + 0.1 + Double(index) * 0.1),
                                .group([.fadeIn(withDuration: 0.3), rise])]))
        }

        // Golden sparks drifting up
        for index in 0..<26 {
            let spark = SKSpriteNode(texture: dotTexture)
            let s = CGFloat.random(in: 3...7)
            spark.size = CGSize(width: s, height: s)
            spark.color = index % 3 == 0 ? .white : accent
            spark.colorBlendFactor = 1
            spark.blendMode = .add
            spark.alpha = 0
            spark.position = CGPoint(x: CGFloat.random(in: -total * 0.7...total * 0.7), y: CGFloat.random(in: -90 ... -20))
            group.addChild(spark)
            let rise = SKAction.moveBy(x: CGFloat.random(in: -20...20), y: CGFloat.random(in: 70...150), duration: 1.6)
            rise.timingMode = .easeOut
            spark.run(.sequence([.wait(forDuration: 0.3 + Double.random(in: 0...1.2)),
                                 .group([.sequence([.fadeAlpha(to: 0.9, duration: 0.25), .wait(forDuration: 0.7), .fadeOut(withDuration: 0.65)]),
                                         rise]),
                                 .removeFromParent()]))
        }

        // Breathe a little while held, then ease out together
        group.run(.sequence([.wait(forDuration: 0.6), .scale(to: 1.03, duration: hold - 0.6)]))
        let out = SKAction.group([.fadeOut(withDuration: 0.4), .scale(to: 1.08, duration: 0.4)])
        out.timingMode = .easeIn
        group.run(.sequence([.wait(forDuration: hold + 0.2), out, .removeFromParent()]))
        vignette.run(.sequence([.wait(forDuration: hold + 0.3), .fadeOut(withDuration: 0.4), .removeFromParent()]))
    }

    /// Parking levels: the same modern title, shorter, then the results.
    private func playParkedSequence() {
        finishAnimating = true
        let layer = SKNode()
        layer.zPosition = 300
        addChild(layer)
        var stats: [(icon: String, text: String)] = [("stopwatch.fill", String(format: "%.1f s", localTime))]
        stats.append(("exclamationmark.triangle.fill", Strings.crashes(hits)))
        presentFinishTitle(in: layer, title: Strings.parkedBig, kicker: Strings.levelComplete,
                           stats: stats, accent: UIColor(red: 0.35, green: 0.95, blue: 0.6, alpha: 1), hold: 1.6)
        layer.run(.sequence([.wait(forDuration: 2.4), .removeFromParent()]))
        run(.wait(forDuration: 2.1)) { [weak self] in
            guard let self = self else { return }
            self.finishAnimating = false
            self.checkLevelDone()
        }
    }

    private func finishShotB(layer: SKNode) {
        world?.celebrate()
        audio.play("park", volume: 0.9)
        bumpHaptic.impactOccurred(intensity: 1.0)
    }

    private func confetti(at point: CGPoint) {
        guard let screen = world?.project(point, height: 1.5) else { return }
        let colors: [UIColor] = [CarArt.playerColors[0], CarArt.playerColors[1],
                                 UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1), UIColor(red: 0.4, green: 1, blue: 0.6, alpha: 1)]
        for index in 0..<28 {
            let piece = SKSpriteNode(color: colors[index % colors.count], size: CGSize(width: 7, height: 4))
            piece.position = screen
            piece.zRotation = CGFloat.random(in: 0...CGFloat.pi)
            fxLayer.addChild(piece)
            let angle = CGFloat(index) / 28 * 2 * CGFloat.pi + CGFloat.random(in: -0.2...0.2)
            let distance = CGFloat.random(in: 50...110)
            piece.run(.sequence([
                .group([.moveBy(x: cos(angle) * distance, y: sin(angle) * distance + 20, duration: 0.8),
                        .rotate(byAngle: CGFloat.random(in: -6...6), duration: 0.8),
                        .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.3)])]),
                .removeFromParent()
            ]))
        }
    }

    // MARK: Level flow

    private func checkLevelDone() {
        guard localParked, !resultsShown, !finishAnimating else { return }
        let together = online && friendPresent
        if together && !remoteParked {
            statusLabel.text = Strings.waitingFriendPark
            return
        }
        resultsShown = true
        statusLabel.text = ""

        let footer: ResultFooter
        if Levels.isLast(levelIndex) {
            footer = .final
        } else if together {
            footer = .autoNext(seconds: advanceDelay)
            if isHost { scheduleAdvance() }
        } else {
            footer = .solo(hasNext: true)
        }
        showResults(footer: footer)
    }

    private func scheduleAdvance() {
        guard !advanceScheduled else { return }
        advanceScheduled = true
        run(.wait(forDuration: advanceDelay)) { [weak self] in
            guard let self = self else { return }
            let next = self.levelIndex + 1
            if self.online && self.friendPresent {
                self.model?.send(["t": "lvl", "n": next])
            }
            self.loadBehindCurtain(level: next)
        }
    }

    private func showResults(footer: ResultFooter) {
        let myTime: Double? = localTime >= 0 ? localTime : nil
        var entries = [ResultEntry(name: Strings.you, slot: slot, time: myTime, hits: hits, isMe: true, isWinner: false)]
        var headline: String?
        var scoreLine: String?
        if (online && friendPresent) || remoteParked {
            let friendTime: Double? = remoteParked && remoteTime >= 0 ? remoteTime : nil
            entries.append(ResultEntry(name: Strings.friend, slot: otherSlot, time: friendTime,
                                       hits: remoteHits, isMe: false, isWinner: false))
            if level.race {
                for index in entries.indices {
                    let crashes = entries[index].hits
                    let score = entries[index].time.map { Levels.raceScore(time: $0, crashes: crashes) } ?? -1
                    entries[index].score = score
                }
                let scores = entries.compactMap { $0.score }.filter { $0 >= 0 }
                if let best = scores.min() {
                    for index in entries.indices where entries[index].score == best {
                        entries[index].isWinner = true
                    }
                }
            } else if let best = entries.compactMap({ $0.time }).min() {
                for index in entries.indices where entries[index].time == best {
                    entries[index].isWinner = true
                }
            }
            let iWon = entries[0].isWinner && !entries[1].isWinner
            let friendWon = entries[1].isWinner && !entries[0].isWinner
            if iWon { myWins += 1 }
            if friendWon { friendWins += 1 }
            headline = iWon ? Strings.youWon : (friendWon ? Strings.friendWon : Strings.draw)
            if isCity {
                scoreLine = Strings.score(myWins, friendWins)
                if case .final = footer {
                    headline = myWins > friendWins ? Strings.youWon : (friendWins > myWins ? Strings.friendWon : Strings.draw)
                }
            }
            refreshLevelLabel()
        } else if case .final = footer, isCity {
            headline = Strings.allRounds
        }
        if level.race && entries.count == 1 {
            entries[0].score = myTime.map { Levels.raceScore(time: $0, crashes: hits) } ?? -1
            if headline == nil { headline = Strings.finished }
        }
        // Coins for the round (and any daily task it completed)
        let me = entries[0]
        let headToHead = entries.count > 1
        let stats = RunStats(finished: me.time != nil, stars: me.stars,
                             won: headToHead ? (me.isWinner && !entries[1].isWinner) : nil,
                             race: level.race, solo: !isCity, hits: hits, driftPoints: runDriftPoints,
                             nearMisses: runNearMisses, escapes: runEscapes, topSpeed: runTopSpeed)
        let reward = model?.finishRun(stats)
        model?.results = ResultsInfo(levelIndex: levelIndex, levelTitle: Levels.title(levelIndex) + " · " + level.name,
                                     entries: entries, footer: footer, newBest: newBest,
                                     bestTime: isCity ? nil : model?.bestTime(for: levelIndex),
                                     headline: headline, scoreLine: scoreLine, reward: reward)
        // The card covers the world: stop drawing it (a frozen frame) until the next level loads
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self, self.model?.results != nil else { return }
            self.worldFrozen = true
            self.world?.setRenderingPaused(true)
        }
    }

    // MARK: Pedestrians

    private var pedestrians: PedestrianSystem?
    private var pedestrianNodes: [SCNNode] = []
    /// Geometry key last shown per person (pose * 100 + outfit), to swap only on change.
    private var pedestrianLooks: [Int] = []
    private var pendingHorn: CGPoint?

    private func updatePedestrianNodes() {
        guard let people = pedestrians else { return }
        // People are detailed meshes now: draw the ones within 45 m (tiny further away)
        let range: CGFloat = 450
        for (index, person) in people.people.enumerated() where index < pedestrianNodes.count {
            let node = pedestrianNodes[index]
            let far = abs(person.position.x - carPosition.x) > range || abs(person.position.y - carPosition.y) > range
            if node.isHidden != far { node.isHidden = far }
            if far { continue }
            let pose: PedestrianModels.Pose
            var lift: Float = 0
            var tilt: Float = 0
            switch person.state {
            case .walking, .crossing:
                let cycle = PedestrianModels.Pose.walkCycle
                let frame = Int(person.stride / PedestrianModels.cycleLength * CGFloat(cycle.count)) % cycle.count
                pose = cycle[max(0, frame)]
            case .waiting, .browsing:
                pose = .stand
            case .startled:
                pose = .startled
            case .fallen:
                pose = .stand
                tilt = Float.pi / 2
                lift = 0.15
            }
            let look = pose.rawValue * 100 + person.outfit
            if pedestrianLooks[index] != look {
                pedestrianLooks[index] = look
                node.geometry = PedestrianModels.geometry(pose: pose, outfit: person.outfit)
            }
            var p = World3D.vec(person.position)
            p.y = lift
            node.position = p
            node.eulerAngles = SCNVector3(0, Float(person.heading), tilt)
        }
    }

    // MARK: Nitro pickups and speed cameras

    private struct Pickup {
        let point: CGPoint
        let node: SCNNode
        var readyAt: TimeInterval
    }

    private struct SpeedCamera {
        let point: CGPoint
        let alongX: Bool
        let flash: SCNNode
        var readyAt: TimeInterval
    }

    private var pickups: [Pickup] = []
    private var speedCameras: [SpeedCamera] = []
    private var bonusLabel = SKLabelNode()
    private let cameraThreshold: CGFloat = 45   // km/h
    private let policeThreshold: CGFloat = 70   // km/h

    /// Canisters on the lanes of a dozen street segments and speed cameras on a few others
    /// (same layout for both players: seeded by the level).
    private func setupBonuses() {
        pickups.removeAll()
        speedCameras.removeAll()
        if bonusLabel.parent == nil {
            bonusLabel = makeLabel(Strings.nitroPickup, size: 20, color: UIColor(red: 0.45, green: 0.9, blue: 1.0, alpha: 1))
            bonusLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.7)
            bonusLabel.zPosition = 21
            bonusLabel.alpha = 0.002
            hud.addChild(bonusLabel)
        }
        if policeBanner.parent == nil { setupPoliceWarning() }
        guard let city = level.city, let world = world else { return }
        var segments: [(mid: CGPoint, alongX: Bool)] = []
        for y in city.ys {
            for i in 0..<(city.cols - 1) { segments.append((CGPoint(x: (city.xs[i] + city.xs[i + 1]) / 2, y: y), true)) }
        }
        for x in city.xs {
            for j in 0..<(city.rows - 1) { segments.append((CGPoint(x: x, y: (city.ys[j] + city.ys[j + 1]) / 2), false)) }
        }
        var rng = SplitMix64(seed: UInt64(levelIndex) &* 104_729 &+ 17)
        segments.shuffle(using: &rng)
        for segment in segments.prefix(12) {
            let lane: CGFloat = rng.unit() < 0.5 ? CityMap.laneOffset : -CityMap.laneOffset
            let shift = rng.range(-120, 120)
            let point = segment.alongX ? CGPoint(x: segment.mid.x + shift, y: segment.mid.y + lane)
                                       : CGPoint(x: segment.mid.x + lane, y: segment.mid.y + shift)
            pickups.append(Pickup(point: point, node: world.addNitroPickup(at: point), readyAt: 0))
        }
        for segment in segments.dropFirst(12).prefix(4) {
            let pole = segment.alongX ? CGPoint(x: segment.mid.x + 60, y: segment.mid.y + 106)
                                      : CGPoint(x: segment.mid.x + 106, y: segment.mid.y + 60)
            speedCameras.append(SpeedCamera(point: segment.mid, alongX: segment.alongX,
                                            flash: world.addSpeedCamera(at: pole, lookingAlongX: segment.alongX), readyAt: 0))
        }
    }

    private func updateBonuses() {
        guard phase == .driving, !localParked, !pickups.isEmpty || !speedCameras.isEmpty else { return }
        let now = lastUpdate
        for index in pickups.indices where now >= pickups[index].readyAt {
            let pickup = pickups[index]
            if !pickup.node.isHidden, pickup.point.distance(to: carPosition) < 26 {
                pickups[index].readyAt = now + 18
                pickup.node.runAction(.sequence([.group([.scale(to: 1.8, duration: 0.15), .fadeOut(duration: 0.15)]), .hide()]))
                nitro = min(1, nitro + 0.5)
                if benchmark { FrameMonitor.shared.mark("pickup") }
                audio.play("beep", volume: 0.7)
                tickHaptic.impactOccurred(intensity: 0.8)
                flashBonus(Strings.nitroPickup)
            } else if pickup.node.isHidden && pickups[index].readyAt > 0 {
                // Back after the cooldown
                pickup.node.scale = SCNVector3(1, 1, 1)
                pickup.node.isHidden = false
                pickup.node.runAction(.fadeIn(duration: 0.4))
                pickups[index].readyAt = 0
            }
        }
        let kmh = abs(velocity) * 0.36
        for index in speedCameras.indices where now >= speedCameras[index].readyAt {
            let camera = speedCameras[index]
            let along = camera.alongX ? abs(carPosition.x - camera.point.x) : abs(carPosition.y - camera.point.y)
            let across = camera.alongX ? abs(carPosition.y - camera.point.y) : abs(carPosition.x - camera.point.x)
            guard along < 40, across < CityMap.roadHalf, kmh > 12 else { continue }
            speedCameras[index].readyAt = now + 8
            if benchmark { FrameMonitor.shared.mark("radar") }
            camera.flash.removeAllActions()
            camera.flash.scale = SCNVector3(1, 1, 1)
            camera.flash.runAction(.sequence([.wait(duration: 0.12), .scale(to: 0.001, duration: 0.2)]))
            let speedText = "\(Int(kmh.rounded())) km/h"
            if kmh >= policeThreshold {
                dispatchPolice(Strings.crimeSpeeding(speedText))
            }
            if kmh >= cameraThreshold {
                nitro = min(1, nitro + 0.35)
                audio.play("beep", volume: 0.8)
                notifyHaptic.notificationOccurred(.success)
                flashBonus(Strings.radarBonus(speedText))
            } else {
                flashBonus(Strings.radarSlow(speedText, Int(cameraThreshold)))
            }
        }
    }

    /// Short text pop above the car (prebuilt label, so the first bonus does not stall).
    private func flashBonus(_ text: String) {
        bonusLabel.removeAllActions()
        bonusLabel.text = text
        bonusLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.7)
        bonusLabel.setScale(0.6)
        bonusLabel.alpha = 1
        bonusLabel.run(.sequence([.scale(to: 1.1, duration: 0.12), .scale(to: 1.0, duration: 0.08), .wait(forDuration: 0.9),
                                  .group([.fadeAlpha(to: 0.002, duration: 0.3), .moveBy(x: 0, y: 16, duration: 0.3)])]))
    }

    private func showToast(_ text: String) {
        let toast = makeLabel(text, size: 16, color: UIColor(red: 1, green: 0.7, blue: 0.6, alpha: 1))
        toast.position = CGPoint(x: size.width / 2, y: size.height / 2 + 70)
        toast.zPosition = 10
        hud.addChild(toast)
        toast.run(.sequence([.wait(forDuration: 2.0), .fadeOut(withDuration: 0.4), .removeFromParent()]))
    }
}

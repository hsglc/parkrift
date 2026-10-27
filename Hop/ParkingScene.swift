import SpriteKit
import UIKit

/// Game loop, input, HUD and 2D effects. The world itself is drawn in 3D by `World3D`
/// (a SceneKit view underneath this transparent SpriteKit scene).
final class ParkingScene: SKScene {

    private enum Control: Hashable {
        case left
        case right
        case forward
        case reverse
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
    private var countdownDial = SKNode()
    private var countdownRing = SKShapeNode()
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
        audio.setMotor(active: false, speed: 0, throttle: 0)
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

        countdownNode = SKNode()
        countdownNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        countdownNode.zPosition = 5
        countdownShadow = makeLabel("3", size: 110, color: UIColor.black.withAlphaComponent(0.35))
        countdownShadow.position = CGPoint(x: 0, y: -6)
        countdownNode.addChild(countdownShadow)
        countdownLabel = makeLabel("3", size: 110, color: .white)
        countdownNode.addChild(countdownLabel)

        // Dial behind the numbers: dark disc, faint track and a ring that sweeps each second
        countdownDial = SKNode()
        countdownDial.position = countdownNode.position
        countdownDial.zPosition = 4
        let disc = SKShapeNode(circleOfRadius: 70)
        disc.fillColor = UIColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 0.45)
        disc.strokeColor = .clear
        countdownDial.addChild(disc)
        let track = SKShapeNode(circleOfRadius: 78)
        track.strokeColor = UIColor.white.withAlphaComponent(0.15)
        track.lineWidth = 6
        track.fillColor = .clear
        countdownDial.addChild(track)
        countdownRing = SKShapeNode()
        countdownRing.lineWidth = 6
        countdownRing.lineCap = .round
        countdownRing.glowWidth = 2
        countdownDial.addChild(countdownRing)
        countdownDial.isHidden = true
        hud.addChild(countdownDial)
        hud.addChild(countdownNode)
    }

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
        if level.race {
            // Draws once with the plate's fonts so the finish moment does not lay out glyphs cold
            _ = CarArt.finishPlate(kicker: Strings.raceComplete, title: Strings.finishBig, stats: [("stopwatch.fill", "0.0 s")],
                                   badgeTop: "P1", badgeBottom: Strings.placeShort, accent: .white, badgeText: .black)
        }
        defer {
            stage("level loaded")
            world.warmUp { [weak self] in
                self?.stage("warm-up done")
                self?.becomeReady()
            }
            // Never wait on the GPU warm-up forever
            if !ready {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
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
                                             style: CarStyle(rawValue: index % 3) ?? .sedan))
            }
        }
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
        setCountdown("3")
        countdownNode.removeAllActions()
        countdownNode.alpha = 1
        countdownNode.setScale(1)
        hitsLabel.text = "0"
        gearLabel.text = "D"
        refreshLevelLabel()
        codeLabel.text = online ? "\(Strings.roomCode): \(model?.roomCode ?? "")" : ""
        remoteCheck.isHidden = true
        holdRing.path = nil
        world.follow(position: carPosition, heading: heading, dt: 0, snap: true)
        buildMinimap()
        updateCarNodes()
        countdownNode.isHidden = !ready
        if ready {
            countdownDial.alpha = 0
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

    /// Each number grows in softly and fades out before the next; GO! zooms away.
    private func popCountdown(go: Bool) {
        countdownNode.removeAllActions()
        countdownNode.isHidden = false
        countdownNode.alpha = 0
        countdownNode.setScale(go ? 0.6 : 0.45)
        let appear = SKAction.group([.fadeIn(withDuration: 0.18), .scale(to: 1.0, duration: 0.34)])
        appear.timingMode = .easeOut
        let settle = SKAction.scale(to: go ? 1.08 : 1.04, duration: go ? 0.35 : 0.42)
        let leave = SKAction.group([.fadeOut(withDuration: go ? 0.35 : 0.2), .scale(to: go ? 2.0 : 1.25, duration: go ? 0.35 : 0.2)])
        leave.timingMode = .easeIn
        countdownNode.run(.sequence([appear, settle, leave]))
        if go {
            countdownDial.run(.sequence([.group([.fadeOut(withDuration: 0.3), .scale(to: 1.4, duration: 0.3)]), .hide()]))
        } else {
            countdownDial.removeAllActions()
            countdownDial.isHidden = false
            if countdownDial.alpha < 1 {
                countdownDial.setScale(0.8)
                countdownDial.run(.group([.fadeIn(withDuration: 0.25), .scale(to: 1.0, duration: 0.25)]))
            }
        }
    }

    private func updateCountdownRing() {
        var fraction = countdown - floor(countdown)
        if fraction <= 0.001 { fraction = 1 }
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: 78, startAngle: CGFloat.pi / 2,
                    endAngle: CGFloat.pi / 2 - fraction * 2 * CGFloat.pi, clockwise: true)
        countdownRing.path = path
        countdownRing.strokeColor = countdownLabel.fontColor ?? .white
    }

    private func becomeReady() {
        guard !ready, !readyRequested else { return }
        readyRequested = true
        stage("ready")
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
        countdownNode.isHidden = false
        countdown = 3
        setCountdown("3")
        countdownDial.alpha = 0
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
        case "p":
            guard messageLevel == levelIndex else { return }
            remoteParked = true
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
        let colors: [String: UIColor] = ["3": UIColor(red: 1.0, green: 0.38, blue: 0.35, alpha: 1),
                                         "2": UIColor(red: 1.0, green: 0.72, blue: 0.22, alpha: 1),
                                         "1": UIColor(red: 1.0, green: 0.90, blue: 0.30, alpha: 1)]
        let isNumber = text.count == 1
        countdownLabel.text = text
        countdownShadow.text = text
        countdownLabel.fontColor = colors[text] ?? UIColor(red: 0.40, green: 1.0, blue: 0.55, alpha: 1)
        countdownLabel.fontSize = isNumber ? 110 : 72
        countdownShadow.fontSize = countdownLabel.fontSize
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
        load(level: levelIndex)
    }

    func nextLevel() {
        load(level: Levels.clamp(levelIndex + 1))
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
        if benchClock > 12 && benchClock - dt <= 12 { world?.saveSnapshot(named: "shot-mid"); saveFullSnapshot() }
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
        if benchRecording { nitroFiredAt.append((Double(benchClock - 2) * 10).rounded() / 10) }
        engaged = true
        if gear == .reverse && velocity <= 2 { gear = .drive }
        velocity = max(velocity, 0) + 45
        audio.play("nitro", volume: 0.8)
        bumpHaptic.impactOccurred(intensity: 1.0)
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
        if fraction > 0.01 {
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: 39, startAngle: CGFloat.pi / 2,
                        endAngle: CGFloat.pi / 2 - fraction * 2 * CGFloat.pi, clockwise: true)
            nitroRing.path = path
        } else {
            nitroRing.path = nil
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
                     "b": braking ? 1 : 0, "r": (gear == .reverse && velocity < -1) ? 1 : 0, "n": isBoosting ? 1 : 0])
    }

    // MARK: Input

    private func hitControl(at point: CGPoint) -> Control? {
        if leftButton.frame.insetBy(dx: -8, dy: -14).contains(point) { return .left }
        if rightButton.frame.insetBy(dx: -8, dy: -14).contains(point) { return .right }
        if gasPedal.frame.insetBy(dx: -14, dy: -14).contains(point) { return .forward }
        if reversePedal.frame.insetBy(dx: -14, dy: -14).contains(point) { return .reverse }
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

        let throttle: Float = (isPressed(.forward) || isPressed(.reverse)) && phase == .driving && !localParked ? 1 : 0
        audio.setMotor(active: true, speed: Float(abs(velocity) / maxForward), throttle: throttle)

        if online && friendPresent {
            sendClock += TimeInterval(dt)
            if sendClock >= 1.0 / 20.0 && !localParked {
                sendClock = 0
                sendState()
            }
        }

        if worldFrozen {
            timerLabel.text = String(format: "%.1f", localParked ? max(localTime, 0) : elapsed)
            return
        }
        if let traffic = traffic {
            var blockers = [carPosition]
            if friendPresent && remoteTarget != nil { blockers.append(remotePosition) }
            traffic.step(dt, blockers: blockers)
            world?.updateSignals(time: traffic.clock)
            let detailRange = PerfSettings.carDetailDistance * 10
            for (index, bot) in traffic.bots.enumerated() where index < botCars.count {
                let near = abs(bot.position.x - carPosition.x) < detailRange && abs(bot.position.y - carPosition.y) < detailRange
                botCars[index].setDetail(near)
                botCars[index].update(position: bot.position, heading: bot.heading, steer: 0, braking: bot.braking)
            }
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
            world?.updateDetail(around: carPosition)
        }

        if online && friendPresent && remoteParked && !localParked && phase == .driving {
            giveUp -= dt
            statusLabel.text = Strings.friendParkedHurry(max(0, Int(ceil(giveUp))))
            if giveUp <= 0 { gaveUp() }
        }

        updateRemoteCar(dt)
        updateNitro(dt)
        updateSpeedometer(dt)

        timerLabel.text = String(format: "%.1f", localParked ? localTime : elapsed)
        world?.follow(position: carPosition, heading: heading, dt: dt)
        updateCarNodes()
        updateSteerGauge()
    }

    private func updateSteerGauge() {
        let amount = max(-1, min(1, steer / maxSteer))
        if abs(amount) < 0.03 {
            steerArc.path = nil
            steerLabel.text = ""
            return
        }
        // Left fills toward the left side of the bar
        let width = abs(amount) * 80
        let rect = amount > 0 ? CGRect(x: -width, y: -3.5, width: width, height: 7) : CGRect(x: 0, y: -3.5, width: width, height: 7)
        steerArc.path = CGPath(roundedRect: rect, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
        steerLabel.text = abs(amount) < 0.12 ? "" : (amount > 0 ? "◀ " + Strings.left : Strings.right + " ▶")
    }

    // MARK: City race

    private func gaveUp() {
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
        speedLabel.text = "\(Int(shownSpeed.rounded()))"
        let fraction = min(1, shownSpeed / dialMaxKmh)
        if fraction > 0.005 {
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: speedRadius - 4, startAngle: dialStart,
                        endAngle: dialStart - dialSweep * fraction, clockwise: true)
            speedArc.path = path
        } else {
            speedArc.path = nil
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
        localCar?.update(position: carPosition, heading: heading, steer: steer,
                         pitch: pitch, roll: roll, braking: braking, reversing: reversing)
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
                velocity += engineAccel * pow(headroom, 0.7) * dt
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
                let resistance = (rolling + airDrag * velocity * velocity * 0.01) * dt
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

        let speedFactor = 1 - 0.4 * min(1, abs(velocity) / maxForward)
        let targetSteer = wheelInput * maxSteer * speedFactor
        steer = approach(steer, targetSteer, steerRate * dt)

        let yawRate = velocity / wheelBase * tan(steer)
        let newHeading = heading + yawRate * dt
        let newPosition = CGPoint(x: carPosition.x + cos(newHeading) * velocity * dt,
                                  y: carPosition.y + sin(newHeading) * velocity * dt)

        let longitudinal = (velocity - previousVelocity) / max(dt, 0.001)
        longitudinalAccel += (longitudinal - longitudinalAccel) * min(1, dt * 8)
        lateralAccel += (velocity * yawRate - lateralAccel) * min(1, dt * 8)

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
                hitsLabel.text = "\(hits)"
                bumpHaptic.impactOccurred(intensity: 0.5)
                audio.play("bump", volume: 0.5)
            } else if lostSpeed > 8 {
                tickHaptic.impactOccurred(intensity: 0.25)
            }
        } else if blocked(moving: OBB(center: newPosition, size: Levels.carSize, angle: newHeading), to: newPosition) {
            let impact = abs(velocity)
            if lastUpdate - lastHitAt > 0.6 && impact > 18 {
                lastHitAt = lastUpdate
                hits += 1
                hitsLabel.text = "\(hits)"
                bumpHaptic.impactOccurred(intensity: min(1, impact / 120 + 0.4))
                audio.play("bump", volume: Float(min(1, impact / 100 + 0.3)))
                world?.shake(strength: min(6, impact / 20))
                let direction: CGFloat = velocity >= 0 ? 1 : -1
                dust(at: CGPoint(x: carPosition.x + cos(heading) * 22 * direction,
                                 y: carPosition.y + sin(heading) * 22 * direction))
            }
            velocity = abs(velocity) < 6 ? 0 : -velocity * 0.22
            longitudinalAccel = -longitudinalAccel
        } else {
            carPosition = newPosition
            heading = newHeading
        }

        gearLabel.text = gear == .drive ? "D" : "R"
        gearLabel.fontColor = gear == .drive ? UIColor(red: 0.45, green: 0.95, blue: 0.6, alpha: 1)
                                             : UIColor(red: 1.0, green: 0.55, blue: 0.45, alpha: 1)
        tyreEffects(dt, accelerating: gasDown || reverseDown)
    }

    private func approach(_ value: CGFloat, _ target: CGFloat, _ step: CGFloat) -> CGFloat {
        if value < target { return min(value + step, target) }
        return max(value - step, target)
    }

    // MARK: Collisions

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
        let cornering = abs(lateralAccel) > 150 && abs(velocity) > 50
        let hardBrake = braking && abs(velocity) > 60
        skidClock += dt
        if (cornering || hardBrake) && skidClock > 0.03 {
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
        if !level.race { confetti(at: carPosition) }
        model?.send(["t": "p", "l": levelIndex, "time": localTime, "hits": hits,
                     "x": Double(carPosition.x), "y": Double(carPosition.y), "h": Double(heading)])
        if !isCity {
            model?.levelCompleted(levelIndex)
            newBest = model?.record(level: levelIndex, time: localTime, hits: hits) ?? false
        }
        if level.race {
            playFinishSequence()
        } else {
            checkLevelDone()
        }
    }

    /// Finish line moment. Everything it shows is prepared while the level loads, so it starts on
    /// the very frame the car crosses the line:
    /// 0.0 s  flash, letterbox, checkered bands and the glowing title; slow motion, low camera
    /// 1.0 s  cut to an orbit around the car with fireworks and confetti
    /// 4.0 s  bars leave, results card
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

        let flash = SKSpriteNode(color: .white, size: size)
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.alpha = 0.85
        layer.addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.35), .removeFromParent()]))

        // Letterbox bars
        let barHeight = size.height * 0.1
        for top in [true, false] {
            let bar = SKSpriteNode(color: .black, size: CGSize(width: size.width + 40, height: barHeight))
            bar.anchorPoint = CGPoint(x: 0.5, y: top ? 0 : 1)
            bar.position = CGPoint(x: size.width / 2, y: top ? size.height : 0)
            layer.addChild(bar)
            let slideIn = SKAction.moveBy(x: 0, y: top ? -barHeight : barHeight, duration: 0.3)
            slideIn.timingMode = .easeOut
            let slideOut = SKAction.moveBy(x: 0, y: top ? barHeight : -barHeight, duration: 0.3)
            slideOut.timingMode = .easeIn
            bar.run(.sequence([slideIn, .wait(forDuration: 3.4), slideOut]))
        }
        for node in [hud, controlsLayer, fxLayer] {
            node.run(.sequence([.fadeOut(withDuration: 0.25), .wait(forDuration: 3.5), .fadeIn(withDuration: 0.3)]))
        }
        speedLines.forEach { $0.sprite.alpha = 0.002 }

        // Light streak sweeping across the screen as the car crosses the line
        let streak = SKSpriteNode(texture: CarArt.speedLineTexture)
        streak.size = CGSize(width: 6, height: size.width * 0.9)
        streak.zRotation = CGFloat.pi / 2
        streak.blendMode = .add
        streak.color = .white
        streak.colorBlendFactor = 1
        streak.position = CGPoint(x: -size.width * 0.5, y: size.height * 0.36)
        layer.addChild(streak)
        let sweep = SKAction.moveTo(x: size.width * 1.5, duration: 0.45)
        sweep.timingMode = .easeIn
        streak.run(.sequence([sweep, .removeFromParent()]))

        // Lower-third result plate
        let place = online && friendPresent && remoteParked && remoteTime >= 0 ? 2 : 1
        let together = online && friendPresent
        let won = together && place == 1
        let accent: UIColor = won ? UIColor(red: 1.0, green: 0.78, blue: 0.12, alpha: 1)
            : (together ? UIColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1) : UIColor(red: 0.22, green: 0.84, blue: 1.0, alpha: 1))
        var stats: [(icon: String, text: String)] = [("stopwatch.fill", String(format: "%.1f s", localTime))]
        if level.race { stats.append(("exclamationmark.triangle.fill", Strings.crashes(hits))) }
        let round = levelIndex - Levels.raceBase + 1
        let plateTexture = CarArt.finishPlate(
            kicker: Strings.raceComplete,
            title: won ? Strings.youWon.uppercased() : Strings.finishBig,
            stats: stats,
            badgeTop: together ? "P\(place)" : "\(max(1, round))/\(Levels.raceRounds)",
            badgeBottom: together ? Strings.placeShort : Strings.roundShort,
            accent: accent, badgeText: UIColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1))
        let plate = SKSpriteNode(texture: plateTexture)
        plate.size = plateTexture.size()
        let plateX = 26 + plate.size.width / 2
        plate.position = CGPoint(x: -plate.size.width / 2, y: barHeight + plate.size.height / 2 + 14)
        layer.addChild(plate)
        let enter = SKAction.moveTo(x: plateX, duration: 0.42)
        enter.timingMode = .easeOut
        let leave = SKAction.group([.moveBy(x: -40, y: 0, duration: 0.3), .fadeOut(withDuration: 0.3)])
        leave.timingMode = .easeIn
        plate.run(.sequence([.wait(forDuration: 0.25), enter, .moveBy(x: 10, y: 0, duration: 2.8), leave]))

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
            self.load(level: next)
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
        model?.results = ResultsInfo(levelIndex: levelIndex, levelTitle: Levels.title(levelIndex) + " · " + level.name,
                                     entries: entries, footer: footer, newBest: newBest,
                                     bestTime: isCity ? nil : model?.bestTime(for: levelIndex),
                                     headline: headline, scoreLine: scoreLine)
        // The card covers the world: stop drawing it (a frozen frame) until the next level loads
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self, self.model?.results != nil else { return }
            self.worldFrozen = true
            self.world?.setRenderingPaused(true)
        }
    }

    private func showToast(_ text: String) {
        let toast = makeLabel(text, size: 16, color: UIColor(red: 1, green: 0.7, blue: 0.6, alpha: 1))
        toast.position = CGPoint(x: size.width / 2, y: size.height / 2 + 70)
        toast.zPosition = 10
        hud.addChild(toast)
        toast.run(.sequence([.wait(forDuration: 2.0), .fadeOut(withDuration: 0.4), .removeFromParent()]))
    }
}

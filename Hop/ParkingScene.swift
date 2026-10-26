import SpriteKit
import UIKit

/// Game loop, input, HUD and 2D effects. The world itself is drawn in 3D by `World3D`
/// (a SceneKit view underneath this transparent SpriteKit scene).
final class ParkingScene: SKScene {

    private enum Control: Hashable {
        case wheel
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
    private var level: LevelDef { Levels.all[levelIndex] }
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
    private var menuButton = SKSpriteNode()
    private var resetButton = SKSpriteNode()
    private var soundButton = SKSpriteNode()
    private var soundIcon = SKSpriteNode()
    private var finalButton: SKNode?
    private var wheelSprite = SKSpriteNode()
    private var steerArc = SKShapeNode()
    private var steerLabel = SKLabelNode()
    private let minimap = SKNode()
    private var mapScale: CGFloat = 0.168
    private var myMarker = SKShapeNode()
    private var friendMarker = SKShapeNode()
    private var gasPedal = SKSpriteNode()
    private var hornButton = SKSpriteNode()
    private var lastHorn: TimeInterval = -10
    private var newBest = false
    private let advanceDelay: TimeInterval = 4.5
    private var reversePedal = SKSpriteNode()
    private var activeTouches: [UITouch: Control] = [:]
    private var wheelStartX: [UITouch: CGFloat] = [:]
    private var dotTexture = SKTexture()

    // MARK: Driving model (1 world unit ≈ 10 cm)

    private let wheelBase: CGFloat = 26
    private let maxSteer: CGFloat = 0.64
    private let steerRate: CGFloat = 2.6
    private let engineAccel: CGFloat = 150
    private let reverseAccel: CGFloat = 95
    private let brakeDecel: CGFloat = 360
    private let rolling: CGFloat = 22
    private let airDrag: CGFloat = 0.22
    private let maxForward: CGFloat = 150
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
        self.levelIndex = max(0, min(level, Levels.all.count - 1))
        localCar = world.makeCar(color: CarArt.playerColors[self.slot])
        remoteCar = world.makeCar(color: CarArt.playerColors[1 - self.slot])
    }

    override func didMove(to view: SKView) {
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
        statusLabel.position = CGPoint(x: size.width / 2, y: top - 40)
        hud.addChild(statusLabel)

        minimap.removeAllChildren()
        minimap.position = CGPoint(x: left + 6, y: size.height - 80 - Levels.world.height * mapScale)
        hud.addChild(minimap)

        countdownNode = SKNode()
        countdownNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        countdownNode.zPosition = 5
        countdownNode.addChild(makeGlass(width: 120, height: 120))
        countdownLabel = makeLabel("3", size: 60, color: .white)
        countdownNode.addChild(countdownLabel)
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

        let wheelDiameter: CGFloat = 136
        wheelSprite = SKSpriteNode(texture: CarArt.steeringWheel(diameter: wheelDiameter))
        wheelSprite.size = CGSize(width: wheelDiameter, height: wheelDiameter)
        wheelSprite.position = CGPoint(x: left + wheelDiameter / 2 + 10, y: wheelDiameter / 2 + 14)
        controlsLayer.addChild(wheelSprite)

        // Track + live arc around the wheel showing how far the front wheels are turned
        let trackRadius = wheelDiameter / 2 + 9
        let track = SKShapeNode(circleOfRadius: trackRadius)
        track.strokeColor = UIColor.white.withAlphaComponent(0.22)
        track.lineWidth = 5
        track.fillColor = .clear
        track.position = wheelSprite.position
        controlsLayer.addChild(track)
        steerArc = SKShapeNode()
        steerArc.strokeColor = UIColor(red: 1.0, green: 0.78, blue: 0.10, alpha: 1)
        steerArc.lineWidth = 6
        steerArc.lineCap = .round
        steerArc.glowWidth = 1.5
        steerArc.position = wheelSprite.position
        controlsLayer.addChild(steerArc)
        steerLabel = makeLabel("", size: 14, color: UIColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1))
        steerLabel.position = CGPoint(x: wheelSprite.position.x, y: wheelSprite.position.y + trackRadius + 16)
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

        let gearDisc = makeGlass(width: 36, height: 36)
        gearDisc.position = CGPoint(x: reversePedal.position.x, y: reversePedal.position.y + reverseSize.height / 2 + 26)
        controlsLayer.addChild(gearDisc)
        gearLabel = makeLabel("D", size: 18, color: UIColor(red: 0.45, green: 0.95, blue: 0.6, alpha: 1))
        gearDisc.addChild(gearLabel)
    }

    // MARK: Level loading

    func load(level index: Int) {
        levelIndex = max(0, min(index, Levels.all.count - 1))
        model?.results = nil
        guard builtSize != .zero, let world = world else { return }
        overlay.removeAllChildren()
        finalButton = nil
        obstacleBoxes = level.obstacles.map { $0.box }
        let spotSlots = friendPresent ? [slot, otherSlot] : [slot]
        world.load(level: level, spotSlots: spotSlots, mySlot: slot)

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
        statusLabel.text = ""
        countdownLabel.text = "3"
        countdownLabel.fontSize = 60
        countdownNode.removeAllActions()
        countdownNode.alpha = 1
        countdownNode.setScale(1)
        hitsLabel.text = "0"
        gearLabel.text = "D"
        levelLabel.text = Strings.level(levelIndex + 1, of: Levels.all.count) + " · " + level.name
        codeLabel.text = online ? "\(Strings.roomCode): \(model?.roomCode ?? "")" : ""
        remoteCheck.isHidden = true
        holdRing.path = nil
        world.follow(position: carPosition, heading: heading, dt: 0, snap: true)
        buildMinimap()
        updateCarNodes()
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
            remoteSteer = CGFloat(message["st"] as? Double ?? 0)
            remoteBraking = (message["b"] as? Int ?? 0) == 1
            remoteReversing = (message["r"] as? Int ?? 0) == 1
        case "p":
            guard messageLevel == levelIndex else { return }
            remoteParked = true
            remoteTime = message["time"] as? Double ?? 0
            remoteHits = message["hits"] as? Int ?? 0
            if let x = message["x"] as? Double, let y = message["y"] as? Double, let h = message["h"] as? Double {
                remoteTarget = (CGPoint(x: x, y: y), CGFloat(h))
            }
            remoteSteer = 0
            remoteBraking = false
            remoteReversing = false
            remoteCheck.isHidden = false
            notifyHaptic.notificationOccurred(.warning)
            checkLevelDone()
        case "hn":
            remoteHonk()
        default:
            break
        }
    }

    func retryLevel() {
        load(level: levelIndex)
    }

    func nextLevel() {
        load(level: min(levelIndex + 1, Levels.all.count - 1))
    }

    // MARK: Horn

    private func honk() {
        guard lastUpdate - lastHorn > 0.25 else { return }
        lastHorn = lastUpdate
        audio.play("horn", volume: 0.9)
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
        audio.play("horn", volume: Float(max(0.4, min(1.0, 1.1 - distance / 900))))
        tickHaptic.impactOccurred(intensity: 0.5)

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
        model?.send(["t": "s", "l": levelIndex,
                     "x": Double(carPosition.x), "y": Double(carPosition.y),
                     "h": Double(heading), "v": Double(velocity), "st": Double(steer),
                     "b": braking ? 1 : 0, "r": (gear == .reverse && velocity < -1) ? 1 : 0])
    }

    // MARK: Input

    private func hitControl(at point: CGPoint) -> Control? {
        if hypot(point.x - wheelSprite.position.x, point.y - wheelSprite.position.y) < wheelSprite.size.width * 0.75 {
            return .wheel
        }
        if gasPedal.frame.insetBy(dx: -14, dy: -14).contains(point) { return .forward }
        if reversePedal.frame.insetBy(dx: -14, dy: -14).contains(point) { return .reverse }
        return nil
    }

    private func isPressed(_ control: Control) -> Bool {
        activeTouches.values.contains(control)
    }

    private func refreshPedals() {
        let gasDown = isPressed(.forward)
        let reverseDown = isPressed(.reverse)
        gasPedal.setScale(gasDown ? 0.93 : 1)
        gasPedal.alpha = gasDown ? 1 : 0.88
        reversePedal.setScale(reverseDown ? 0.93 : 1)
        reversePedal.alpha = reverseDown ? 1 : 0.88
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
            if soundButton.contains(point) {
                audio.isMuted.toggle()
                refreshSoundIcon()
                audio.play("click")
                continue
            }
            if let control = hitControl(at: point) {
                if control == .wheel && isPressed(.wheel) { continue }
                activeTouches[touch] = control
                if control == .wheel {
                    wheelStartX[touch] = point.x + wheelInput * 80
                } else {
                    tickHaptic.impactOccurred(intensity: 0.5)
                }
            }
        }
        refreshPedals()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let control = activeTouches[touch] else { continue }
            let point = touch.location(in: self)
            switch control {
            case .wheel:
                let startX = wheelStartX[touch] ?? point.x
                wheelInput = max(-1, min(1, -(point.x - startX) / 80))
            case .forward, .reverse:
                if let now = hitControl(at: point), now != .wheel {
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
        let rawDelta = lastUpdate == 0 ? 1.0 / 60.0 : currentTime - lastUpdate
        lastUpdate = currentTime
        guard builtSize != .zero else { return }
        let dt = CGFloat(min(max(rawDelta, 0), 1.0 / 30.0))

        if !isPressed(.wheel) {
            wheelInput = approach(wheelInput, 0, 4.0 * dt)
        }
        wheelSprite.zRotation = wheelInput * 2.4

        switch phase {
        case .countdown:
            let before = Int(ceil(countdown))
            countdown -= dt
            let after = Int(ceil(countdown))
            if countdown <= 0 {
                phase = .driving
                countdownLabel.text = Strings.go
                countdownLabel.fontSize = 34
                countdownNode.run(.sequence([.scale(to: 1.25, duration: 0.15), .wait(forDuration: 0.3),
                                             .group([.fadeOut(withDuration: 0.25), .scale(to: 1.6, duration: 0.25)])]))
                tickHaptic.impactOccurred(intensity: 1.0)
                audio.play("go", volume: 0.7)
            } else if after != before {
                countdownLabel.text = "\(after)"
                countdownLabel.fontSize = 60
                countdownNode.setScale(1.25)
                countdownNode.run(.scale(to: 1.0, duration: 0.2))
                tickHaptic.impactOccurred()
                audio.play("beep", volume: 0.6)
            }
        case .driving:
            if !localParked {
                elapsed += TimeInterval(dt)
                stepCar(dt)
                separateFromRemote(dt)
                checkParking(dt)
            }
        case .finished:
            braking = false
        }

        let throttle: Float = (isPressed(.forward) || isPressed(.reverse)) && phase == .driving && !localParked ? 1 : 0
        audio.setMotor(active: true, speed: Float(abs(velocity) / maxForward), throttle: throttle)

        if online && friendPresent {
            sendClock += TimeInterval(dt)
            if sendClock >= 1.0 / 15.0 && !localParked {
                sendClock = 0
                sendState()
            }
        }

        if let target = remoteTarget {
            let k = min(1, dt * 12)
            remotePosition = CGPoint(x: remotePosition.x + (target.0.x - remotePosition.x) * k,
                                     y: remotePosition.y + (target.0.y - remotePosition.y) * k)
            remoteHeading += CGFloat.angleDelta(remoteHeading, target.1) * k
        }

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
        let radius = wheelSprite.size.width / 2 + 9
        let start = CGFloat.pi / 2
        let end = start + amount * 2.2
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: radius, startAngle: start, endAngle: end, clockwise: amount < 0)
        steerArc.path = path
        steerLabel.text = abs(amount) < 0.12 ? "" : (amount > 0 ? "◀ " + Strings.left : Strings.right + " ▶")
    }

    // MARK: Minimap

    private func buildMinimap() {
        minimap.removeAllChildren()
        let mapSize = CGSize(width: Levels.world.width * mapScale, height: Levels.world.height * mapScale)
        let background = SKShapeNode(rect: CGRect(origin: .zero, size: mapSize).insetBy(dx: -3, dy: -3), cornerRadius: 8)
        background.fillColor = UIColor(white: 0.05, alpha: 0.55)
        background.strokeColor = UIColor.white.withAlphaComponent(0.3)
        background.lineWidth = 1
        minimap.addChild(background)

        func shape(center: CGPoint, size: CGSize, angle: CGFloat) -> SKShapeNode {
            let node = SKShapeNode(rectOf: CGSize(width: max(2, size.width * mapScale), height: max(2, size.height * mapScale)),
                                   cornerRadius: 1)
            node.position = CGPoint(x: center.x * mapScale, y: center.y * mapScale)
            node.zRotation = angle
            node.strokeColor = .clear
            return node
        }

        for obstacle in level.obstacles {
            let node = shape(center: obstacle.center, size: obstacle.size, angle: obstacle.angle)
            switch obstacle.kind {
            case .wall: node.fillColor = UIColor(white: 0.78, alpha: 0.9)
            case .car: node.fillColor = UIColor(white: 0.55, alpha: 0.9)
            case .cone: node.fillColor = UIColor(red: 1.0, green: 0.5, blue: 0.15, alpha: 1)
            }
            minimap.addChild(node)
        }

        let spotSlots = friendPresent ? [otherSlot, slot] : [slot]
        for spotSlot in spotSlots {
            let def = level.spots[spotSlot]
            let node = shape(center: def.center, size: def.size, angle: def.angle)
            let color = CarArt.playerColors[spotSlot]
            node.fillColor = color.withAlphaComponent(0.35)
            node.strokeColor = color.lighter(by: 0.3)
            node.lineWidth = 1.5
            if spotSlot == slot {
                node.glowWidth = 2
                node.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)])))
            }
            minimap.addChild(node)
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
        minimap.addChild(friendMarker)
        myMarker = marker(CarArt.playerColors[slot])
        myMarker.setScale(1.15)
        minimap.addChild(myMarker)
        updateMinimap()
    }

    private func updateMinimap() {
        myMarker.position = CGPoint(x: carPosition.x * mapScale, y: carPosition.y * mapScale)
        myMarker.zRotation = heading
        friendMarker.isHidden = !friendPresent
        friendMarker.position = CGPoint(x: remotePosition.x * mapScale, y: remotePosition.y * mapScale)
        friendMarker.zRotation = remoteHeading
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
        velocity = max(-maxReverse, min(maxForward, velocity))

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

        if blocked(moving: OBB(center: newPosition, size: Levels.carSize, angle: newHeading), to: newPosition) {
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
        let world = Levels.world
        let curb: CGFloat = 11
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
        return result
    }

    private func center(of contact: Contact) -> CGPoint? {
        switch contact {
        case .bounds: return nil
        case .obstacle(let index): return obstacleBoxes[index].center
        case .remoteCar: return remotePosition
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
        velocity = 0
        braking = false
        longitudinalAccel = 0
        lateralAccel = 0
        phase = .finished
        holdRing.path = nil
        world?.markParked()
        notifyHaptic.notificationOccurred(.success)
        audio.play("park", volume: 0.9)
        statusLabel.text = Strings.parked
        confetti(at: carPosition)
        model?.send(["t": "p", "l": levelIndex, "time": localTime, "hits": hits,
                     "x": Double(carPosition.x), "y": Double(carPosition.y), "h": Double(heading)])
        model?.levelCompleted(levelIndex)
        newBest = model?.record(level: levelIndex, time: localTime, hits: hits) ?? false
        checkLevelDone()
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
        guard localParked, !resultsShown else { return }
        let together = online && friendPresent
        if together && !remoteParked {
            statusLabel.text = Strings.waitingFriendPark
            return
        }
        resultsShown = true
        statusLabel.text = ""

        let footer: ResultFooter
        if levelIndex >= Levels.all.count - 1 {
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
        var entries = [ResultEntry(name: Strings.you, slot: slot, time: localTime, hits: hits, isMe: true, isWinner: false)]
        if (online && friendPresent) || remoteParked {
            entries.append(ResultEntry(name: Strings.friend, slot: otherSlot, time: remoteParked ? remoteTime : nil,
                                       hits: remoteHits, isMe: false, isWinner: false))
            if let best = entries.compactMap({ $0.time }).min() {
                for index in entries.indices where entries[index].time == best {
                    entries[index].isWinner = true
                }
            }
        }
        model?.results = ResultsInfo(levelIndex: levelIndex, levelName: level.name, entries: entries, footer: footer,
                                     newBest: newBest, bestTime: model?.bestTime(for: levelIndex))
    }

    private func showToast(_ text: String) {
        let toast = makeLabel(text, size: 16, color: UIColor(red: 1, green: 0.7, blue: 0.6, alpha: 1))
        toast.position = CGPoint(x: size.width / 2, y: size.height / 2 + 70)
        toast.zPosition = 10
        hud.addChild(toast)
        toast.run(.sequence([.wait(forDuration: 2.0), .fadeOut(withDuration: 0.4), .removeFromParent()]))
    }
}

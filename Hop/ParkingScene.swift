import SpriteKit
import UIKit

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

    // MARK: Configuration

    private weak var model: AppModel?
    private var online = false
    private var slot = 0
    private var isHost = true
    private var friendPresent = false
    private var levelIndex = 0
    private var level: LevelDef { Levels.all[levelIndex] }
    private var otherSlot: Int { 1 - slot }

    // MARK: Layers

    private var builtSize: CGSize = .zero
    private let mapNode = SKNode()
    private let levelLayer = SKNode()
    private let hud = SKNode()
    private let controlsLayer = SKNode()
    private let overlay = SKNode()
    private var mapScale: CGFloat = 1

    // MARK: Nodes

    private var localCar = SKSpriteNode()
    private var remoteCar = SKSpriteNode()
    private var localTag = SKLabelNode()
    private var remoteTag = SKLabelNode()
    private var localSpotGlow: SKSpriteNode?
    private var remoteCheck = SKLabelNode()
    private var levelLabel = SKLabelNode()
    private var timerLabel = SKLabelNode()
    private var hitsLabel = SKLabelNode()
    private var statusLabel = SKLabelNode()
    private var codeLabel = SKLabelNode()
    private var countdownLabel = SKLabelNode()
    private var menuButton = SKShapeNode()
    private var resetButton = SKShapeNode()
    private var finalButton: SKShapeNode?
    private var buttons: [Control: SKShapeNode] = [:]
    private var buttonRadius: [Control: CGFloat] = [:]
    private var activeTouches: [UITouch: Control] = [:]

    // MARK: Textures

    private var parkedCarTextures: [SKTexture] = []
    private var coneTexture = SKTexture()

    // MARK: Car state (world units)

    private let wheelBase: CGFloat = 28
    private let maxSteer: CGFloat = 0.62
    private let steerRate: CGFloat = 3.2
    private let acceleration: CGFloat = 230
    private let reverseAcceleration: CGFloat = 170
    private let brakeForce: CGFloat = 520
    private let coastDrag: CGFloat = 200
    private let maxForward: CGFloat = 210
    private let maxReverse: CGFloat = 110

    private var position0 = CGPoint.zero
    private var heading: CGFloat = 0
    private var speed0: CGFloat = 0
    private var steer: CGFloat = 0
    private var obstacleBoxes: [OBB] = []

    private var remotePosition = CGPoint.zero
    private var remoteHeading: CGFloat = 0
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

    // MARK: Haptics

    private lazy var bumpHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private lazy var tickHaptic = UIImpactFeedbackGenerator(style: .light)
    private lazy var notifyHaptic = UINotificationFeedbackGenerator()

    // MARK: Setup

    func configure(model: AppModel, online: Bool, slot: Int, isHost: Bool, level: Int) {
        self.model = model
        self.online = online
        self.slot = online ? slot : 0
        self.isHost = isHost
        self.friendPresent = online
        self.levelIndex = max(0, min(level, Levels.all.count - 1))
    }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        backgroundColor = UIColor(red: 0.27, green: 0.47, blue: 0.29, alpha: 1)
        buildIfNeeded()
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
        mapNode.removeAllChildren()
        levelLayer.removeAllChildren()
        hud.removeAllChildren()
        controlsLayer.removeAllChildren()
        overlay.removeAllChildren()
        buttons.removeAll()
        buttonRadius.removeAll()
        activeTouches.removeAll()

        addChild(mapNode)
        addChild(hud)
        addChild(controlsLayer)
        addChild(overlay)
        hud.zPosition = 100
        controlsLayer.zPosition = 110
        overlay.zPosition = 200

        // Fit the 1000 x 500 world between the safe-area insets
        let world = Levels.world
        let left = max(insets.left, 8)
        let right = max(insets.right, 8)
        let availableWidth = size.width - left - right
        let availableHeight = size.height - 8
        mapScale = min(availableWidth / world.width, availableHeight / world.height)
        let mapWidth = world.width * mapScale
        let mapHeight = world.height * mapScale
        mapNode.setScale(mapScale)
        mapNode.position = CGPoint(x: left + (availableWidth - mapWidth) / 2, y: (size.height - mapHeight) / 2)

        let asphalt = SKSpriteNode(texture: CarArt.asphalt(size: world))
        asphalt.anchorPoint = .zero
        asphalt.size = world
        asphalt.zPosition = 0
        mapNode.addChild(asphalt)
        levelLayer.zPosition = 1
        mapNode.addChild(levelLayer)

        parkedCarTextures = CarArt.parkedColors.map { CarArt.car(color: $0) }
        coneTexture = CarArt.cone(size: 14)

        let carTextureSize = CGSize(width: Levels.carSize.width + 4, height: Levels.carSize.height + 4)
        localCar = SKSpriteNode(texture: CarArt.car(color: CarArt.playerColors[slot]))
        localCar.size = carTextureSize
        localCar.zPosition = 12
        mapNode.addChild(localCar)

        remoteCar = SKSpriteNode(texture: CarArt.car(color: CarArt.playerColors[otherSlot]))
        remoteCar.size = carTextureSize
        remoteCar.zPosition = 11
        mapNode.addChild(remoteCar)

        localTag = makeLabel(Strings.you, size: 13, color: CarArt.playerColors[slot].lighter(by: 0.25))
        localTag.zPosition = 20
        mapNode.addChild(localTag)
        remoteTag = makeLabel(Strings.friend, size: 13, color: CarArt.playerColors[otherSlot].lighter(by: 0.25))
        remoteTag.zPosition = 20
        mapNode.addChild(remoteTag)
        remoteCheck = makeLabel("✓", size: 22, color: .white)
        remoteCheck.zPosition = 21
        mapNode.addChild(remoteCheck)

        buildHUD()
        buildControls()
        load(level: levelIndex)
    }

    private func makeLabel(_ text: String, size fontSize: CGFloat, color: UIColor) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = fontSize
        label.fontColor = color
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        return label
    }

    private func makePill(width: CGFloat, height: CGFloat) -> SKShapeNode {
        let pill = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: height / 2)
        pill.fillColor = UIColor.black.withAlphaComponent(0.45)
        pill.strokeColor = UIColor.white.withAlphaComponent(0.15)
        pill.lineWidth = 1
        return pill
    }

    private func buildHUD() {
        let top = size.height - 22
        let left = max(insets.left, 10)
        let right = max(insets.right, 10)

        menuButton = makePill(width: 40, height: 32)
        menuButton.position = CGPoint(x: left + 26, y: top)
        menuButton.addChild(makeLabel("✕", size: 16, color: .white))
        hud.addChild(menuButton)

        resetButton = makePill(width: 40, height: 32)
        resetButton.position = CGPoint(x: left + 72, y: top)
        resetButton.addChild(makeLabel("↻", size: 20, color: .white))
        hud.addChild(resetButton)

        let centerPill = makePill(width: 300, height: 32)
        centerPill.position = CGPoint(x: size.width / 2, y: top)
        hud.addChild(centerPill)
        levelLabel = makeLabel("", size: 14, color: .white)
        levelLabel.position = CGPoint(x: -40, y: 0)
        centerPill.addChild(levelLabel)
        timerLabel = makeLabel("0.0", size: 16, color: UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))
        timerLabel.position = CGPoint(x: 112, y: 0)
        centerPill.addChild(timerLabel)

        let hitsPill = makePill(width: 110, height: 32)
        hitsPill.position = CGPoint(x: size.width - right - 60, y: top)
        hud.addChild(hitsPill)
        hitsLabel = makeLabel(Strings.hits(0), size: 14, color: .white)
        hitsPill.addChild(hitsLabel)

        codeLabel = makeLabel("", size: 12, color: UIColor.white.withAlphaComponent(0.7))
        codeLabel.position = CGPoint(x: size.width - right - 60, y: top - 28)
        hud.addChild(codeLabel)

        statusLabel = makeLabel("", size: 16, color: .white)
        statusLabel.position = CGPoint(x: size.width / 2, y: top - 34)
        hud.addChild(statusLabel)

        countdownLabel = makeLabel("", size: 80, color: .white)
        countdownLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        countdownLabel.zPosition = 5
        hud.addChild(countdownLabel)
    }

    private func buildControls() {
        let left = max(insets.left, 12)
        let right = max(insets.right, 12)
        addControl(.left, symbol: "◀", caption: nil, radius: 38, at: CGPoint(x: left + 48, y: 60))
        addControl(.right, symbol: "▶", caption: nil, radius: 38, at: CGPoint(x: left + 136, y: 60))
        addControl(.reverse, symbol: "▼", caption: Strings.reverse, radius: 36, at: CGPoint(x: size.width - right - 140, y: 56))
        addControl(.forward, symbol: "▲", caption: Strings.forward, radius: 42, at: CGPoint(x: size.width - right - 52, y: 70))
    }

    private func addControl(_ control: Control, symbol: String, caption: String?, radius: CGFloat, at point: CGPoint) {
        let button = SKShapeNode(circleOfRadius: radius)
        button.fillColor = UIColor.black.withAlphaComponent(0.25)
        button.strokeColor = UIColor.white.withAlphaComponent(0.75)
        button.lineWidth = 3
        button.position = point
        let icon = makeLabel(symbol, size: 26, color: .white)
        icon.position = CGPoint(x: 0, y: caption == nil ? 0 : 6)
        button.addChild(icon)
        if let caption = caption {
            let text = makeLabel(caption, size: 10, color: UIColor.white.withAlphaComponent(0.85))
            text.position = CGPoint(x: 0, y: -16)
            button.addChild(text)
        }
        controlsLayer.addChild(button)
        buttons[control] = button
        buttonRadius[control] = radius
    }

    // MARK: Level loading

    func load(level index: Int) {
        guard builtSize != .zero else {
            levelIndex = max(0, min(index, Levels.all.count - 1))
            return
        }
        levelIndex = max(0, min(index, Levels.all.count - 1))
        levelLayer.removeAllChildren()
        overlay.removeAllChildren()
        finalButton = nil
        obstacleBoxes = level.obstacles.map { $0.box }

        // Spots
        localSpotGlow = nil
        let spotSlots = friendPresent ? [slot, otherSlot] : [slot]
        for spotSlot in spotSlots {
            let def = level.spots[spotSlot]
            let color = CarArt.playerColors[spotSlot]
            let spotNode = SKSpriteNode(texture: CarArt.spot(size: def.size, color: color))
            spotNode.size = def.size
            spotNode.position = def.center
            spotNode.zRotation = def.angle
            spotNode.zPosition = 1
            levelLayer.addChild(spotNode)
            if spotSlot == slot {
                let glow = SKSpriteNode(color: color, size: def.size)
                glow.alpha = 0
                glow.zPosition = 1
                spotNode.addChild(glow)
                localSpotGlow = glow
                spotNode.run(.repeatForever(.sequence([.fadeAlpha(to: 0.7, duration: 0.6), .fadeAlpha(to: 1.0, duration: 0.6)])))
            }
        }

        // Obstacles
        for obstacle in level.obstacles {
            let node: SKSpriteNode
            switch obstacle.kind {
            case .wall:
                node = SKSpriteNode(texture: CarArt.wall(size: obstacle.size))
                node.size = obstacle.size
            case .car:
                let texture = parkedCarTextures[obstacle.tint % parkedCarTextures.count]
                node = SKSpriteNode(texture: texture)
                node.size = CGSize(width: obstacle.size.width + 4, height: obstacle.size.height + 4)
            case .cone:
                node = SKSpriteNode(texture: coneTexture)
                node.size = obstacle.size
            }
            node.position = obstacle.center
            node.zRotation = obstacle.angle
            node.zPosition = 5
            levelLayer.addChild(node)
        }

        // Cars
        let start = level.starts[slot]
        position0 = start.position
        heading = start.heading
        speed0 = 0
        steer = 0
        let remoteStart = level.starts[otherSlot]
        remotePosition = remoteStart.position
        remoteHeading = remoteStart.heading
        remoteTarget = nil

        // State
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
        statusLabel.text = ""
        countdownLabel.text = "3"
        countdownLabel.alpha = 1
        hitsLabel.text = Strings.hits(0)
        levelLabel.text = Strings.level(levelIndex + 1, of: Levels.all.count) + " · " + level.name
        codeLabel.text = online ? "\(Strings.roomCode): \(model?.roomCode ?? "")" : ""
        localCar.alpha = 1
        remoteCheck.isHidden = true
        updateCarNodes()
        tickHaptic.impactOccurred()
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
        case "p":
            guard messageLevel == levelIndex else { return }
            remoteParked = true
            remoteTime = message["time"] as? Double ?? 0
            remoteHits = message["hits"] as? Int ?? 0
            if let x = message["x"] as? Double, let y = message["y"] as? Double, let h = message["h"] as? Double {
                remoteTarget = (CGPoint(x: x, y: y), CGFloat(h))
            }
            remoteCheck.isHidden = false
            notifyHaptic.notificationOccurred(.warning)
            checkLevelDone()
        default:
            break
        }
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
        if phase == .finished { checkLevelDone() }
    }

    private func sendState() {
        model?.send(["t": "s", "l": levelIndex,
                     "x": Double(position0.x), "y": Double(position0.y),
                     "h": Double(heading), "v": Double(speed0)])
    }

    // MARK: Input

    private func control(at point: CGPoint) -> Control? {
        var best: (Control, CGFloat)?
        for (control, button) in buttons {
            let radius = (buttonRadius[control] ?? 40) * 1.3
            let distance = hypot(point.x - button.position.x, point.y - button.position.y)
            if distance < radius, best == nil || distance < best!.1 {
                best = (control, distance)
            }
        }
        return best?.0
    }

    private func isPressed(_ control: Control) -> Bool {
        activeTouches.values.contains(control)
    }

    private func refreshButtons() {
        for (control, button) in buttons {
            button.fillColor = isPressed(control)
                ? UIColor.white.withAlphaComponent(0.4)
                : UIColor.black.withAlphaComponent(0.25)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            if let finalButton = finalButton, finalButton.contains(point) {
                model?.leaveToMenu()
                return
            }
            if menuButton.contains(point) {
                model?.leaveToMenu()
                return
            }
            if resetButton.contains(point) {
                resetCar()
                continue
            }
            if let control = control(at: point) {
                activeTouches[touch] = control
                tickHaptic.impactOccurred(intensity: 0.4)
            }
        }
        refreshButtons()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where activeTouches[touch] != nil {
            if let control = control(at: touch.location(in: self)) {
                activeTouches[touch] = control
            } else {
                activeTouches[touch] = nil
            }
        }
        refreshButtons()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { activeTouches[touch] = nil }
        refreshButtons()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { activeTouches[touch] = nil }
        refreshButtons()
    }

    private func resetCar() {
        guard phase == .driving, !localParked else { return }
        let start = level.starts[slot]
        position0 = start.position
        heading = start.heading
        speed0 = 0
        steer = 0
        parkHold = 0
        tickHaptic.impactOccurred()
        updateCarNodes()
    }

    // MARK: Update loop

    override func update(_ currentTime: TimeInterval) {
        let rawDelta = lastUpdate == 0 ? 1.0 / 60.0 : currentTime - lastUpdate
        lastUpdate = currentTime
        guard builtSize != .zero else { return }
        let dt = CGFloat(min(max(rawDelta, 0), 1.0 / 30.0))

        switch phase {
        case .countdown:
            let before = Int(ceil(countdown))
            countdown -= dt
            let after = Int(ceil(countdown))
            if countdown <= 0 {
                phase = .driving
                countdownLabel.text = Strings.go
                countdownLabel.run(.sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.3)]))
                tickHaptic.impactOccurred(intensity: 1.0)
            } else if after != before {
                countdownLabel.text = "\(after)"
                tickHaptic.impactOccurred()
            }
        case .driving:
            if !localParked {
                elapsed += TimeInterval(dt)
                stepCar(dt)
                checkParking(dt)
            }
        case .finished:
            break
        }

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
        updateCarNodes()
    }

    private func updateCarNodes() {
        localCar.position = position0
        localCar.zRotation = heading
        localTag.position = CGPoint(x: position0.x, y: position0.y + 30)

        let showRemote = friendPresent
        remoteCar.isHidden = !showRemote
        remoteTag.isHidden = !showRemote
        remoteCar.position = remotePosition
        remoteCar.zRotation = remoteHeading
        remoteTag.position = CGPoint(x: remotePosition.x, y: remotePosition.y + 30)
        remoteCheck.position = remotePosition
        if !showRemote { remoteCheck.isHidden = true }
    }

    // MARK: Driving

    private func stepCar(_ dt: CGFloat) {
        let forward = isPressed(.forward)
        let reverse = isPressed(.reverse)

        if forward && !reverse {
            speed0 += (speed0 < 0 ? brakeForce : acceleration) * dt
        } else if reverse && !forward {
            speed0 -= (speed0 > 0 ? brakeForce : reverseAcceleration) * dt
        } else {
            let drag = coastDrag * dt
            if abs(speed0) <= drag { speed0 = 0 } else { speed0 -= drag * (speed0 > 0 ? 1 : -1) }
        }
        speed0 = max(-maxReverse, min(maxForward, speed0))

        var steerInput: CGFloat = 0
        if isPressed(.left) { steerInput += 1 }
        if isPressed(.right) { steerInput -= 1 }
        let target = steerInput * maxSteer
        let delta = max(-steerRate * dt, min(steerRate * dt, target - steer))
        steer += delta

        let newHeading = heading + speed0 / wheelBase * tan(steer) * dt
        let newPosition = CGPoint(x: position0.x + cos(newHeading) * speed0 * dt,
                                  y: position0.y + sin(newHeading) * speed0 * dt)
        let box = OBB(center: newPosition, size: Levels.carSize, angle: newHeading)
        if collides(box) {
            if lastUpdate - lastHitAt > 0.6 && abs(speed0) > 15 {
                lastHitAt = lastUpdate
                hits += 1
                hitsLabel.text = Strings.hits(hits)
                bumpHaptic.impactOccurred()
                localCar.run(.sequence([.colorize(with: .white, colorBlendFactor: 0.6, duration: 0.05),
                                        .colorize(withColorBlendFactor: 0, duration: 0.2)]))
                mapNode.run(.sequence([.moveBy(x: 4, y: 0, duration: 0.03), .moveBy(x: -8, y: 0, duration: 0.03),
                                       .moveBy(x: 4, y: 0, duration: 0.03)]))
            }
            speed0 = -speed0 * 0.25
        } else {
            position0 = newPosition
            heading = newHeading
        }
    }

    private func collides(_ box: OBB) -> Bool {
        let world = Levels.world
        for corner in box.corners {
            if corner.x < 4 || corner.y < 4 || corner.x > world.width - 4 || corner.y > world.height - 4 {
                return true
            }
        }
        let reach: CGFloat = 60
        for obstacle in obstacleBoxes {
            let dx = obstacle.center.x - box.center.x
            let dy = obstacle.center.y - box.center.y
            let limit = reach + max(obstacle.halfSize.width, obstacle.halfSize.height)
            if abs(dx) > limit || abs(dy) > limit { continue }
            if box.intersects(obstacle) { return true }
        }
        if friendPresent && remoteTarget != nil {
            let other = OBB(center: remotePosition, size: Levels.carSize, angle: remoteHeading)
            if box.intersects(other) { return true }
        }
        return false
    }

    // MARK: Parking

    private func checkParking(_ dt: CGFloat) {
        let spot = level.spots[slot]
        let spotBox = spot.box
        let carBox = OBB(center: position0, size: Levels.carSize, angle: heading)
        let inside = carBox.corners.allSatisfy { spotBox.contains($0) }
        let misalignment = abs((heading - spot.angle).remainder(dividingBy: CGFloat.pi))
        let aligned = misalignment < 0.21
        let slowEnough = abs(speed0) < 8

        if inside && aligned && slowEnough {
            parkHold += dt
            statusLabel.text = Strings.hold
        } else {
            parkHold = max(0, parkHold - dt * 2)
            if statusLabel.text == Strings.hold { statusLabel.text = "" }
        }
        localSpotGlow?.alpha = min(parkHold, 1) * 0.6

        if parkHold >= 1.0 {
            parked()
        }
    }

    private func parked() {
        localParked = true
        localTime = elapsed
        speed0 = 0
        phase = .finished
        notifyHaptic.notificationOccurred(.success)
        statusLabel.text = Strings.parked
        burst(at: position0)
        model?.send(["t": "p", "l": levelIndex, "time": localTime, "hits": hits,
                     "x": Double(position0.x), "y": Double(position0.y), "h": Double(heading)])
        model?.levelCompleted(levelIndex)
        checkLevelDone()
    }

    private func burst(at point: CGPoint) {
        for index in 0..<12 {
            let star = makeLabel("★", size: CGFloat.random(in: 12...20),
                                 color: UIColor(red: 1, green: 0.88, blue: 0.35, alpha: 1))
            star.position = point
            star.zPosition = 30
            mapNode.addChild(star)
            let angle = CGFloat(index) / 12 * 2 * CGFloat.pi
            let distance = CGFloat.random(in: 40...70)
            star.run(.sequence([
                .group([.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.5),
                        .fadeOut(withDuration: 0.5)]),
                .removeFromParent()
            ]))
        }
    }

    // MARK: Level flow

    private func checkLevelDone() {
        guard localParked, !resultsShown else { return }
        if online && friendPresent && !remoteParked {
            statusLabel.text = Strings.waitingFriendPark
            return
        }
        resultsShown = true
        statusLabel.text = ""
        showResults()

        let isLast = levelIndex >= Levels.all.count - 1
        if isLast {
            run(.wait(forDuration: 2.5)) { [weak self] in self?.showFinal() }
            return
        }
        if !online || !friendPresent || isHost {
            scheduleAdvance()
        } else {
            statusLabel.text = Strings.nextLevelSoon
        }
    }

    private func scheduleAdvance() {
        guard !advanceScheduled else { return }
        advanceScheduled = true
        run(.wait(forDuration: 3.5)) { [weak self] in
            guard let self = self else { return }
            let next = self.levelIndex + 1
            if self.online && self.friendPresent {
                self.model?.send(["t": "lvl", "n": next])
            }
            self.load(level: next)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        String(format: "%.1f s", seconds)
    }

    private func showResults() {
        overlay.removeAllChildren()
        let panelWidth: CGFloat = 340
        let rows = (online && friendPresent) || remoteParked ? 2 : 1
        let panelHeight: CGFloat = 96 + CGFloat(rows) * 38
        let panel = SKShapeNode(rectOf: CGSize(width: panelWidth, height: panelHeight), cornerRadius: 22)
        panel.fillColor = UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 0.92)
        panel.strokeColor = UIColor.white.withAlphaComponent(0.25)
        panel.lineWidth = 2
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 20)
        overlay.addChild(panel)

        let title = makeLabel(Strings.parked, size: 26, color: .white)
        title.position = CGPoint(x: 0, y: panelHeight / 2 - 30)
        panel.addChild(title)
        let subtitle = makeLabel(level.name, size: 14, color: UIColor.white.withAlphaComponent(0.6))
        subtitle.position = CGPoint(x: 0, y: panelHeight / 2 - 56)
        panel.addChild(subtitle)

        var entries: [(String, UIColor, Double?, Int)] = [(Strings.you, CarArt.playerColors[slot], localTime, hits)]
        if rows == 2 {
            entries.append((Strings.friend, CarArt.playerColors[otherSlot], remoteParked ? remoteTime : nil, remoteHits))
        }
        let parkedTimes = entries.compactMap { $0.2 }
        let bestTime = parkedTimes.min()

        for (index, entry) in entries.enumerated() {
            let y = panelHeight / 2 - 92 - CGFloat(index) * 38
            let name = makeLabel(entry.0, size: 16, color: entry.1.lighter(by: 0.2))
            name.horizontalAlignmentMode = .left
            name.position = CGPoint(x: -panelWidth / 2 + 24, y: y)
            panel.addChild(name)
            let timeText = entry.2.map { formatTime($0) } ?? Strings.notParked
            let time = makeLabel(timeText, size: 16, color: .white)
            time.position = CGPoint(x: 10, y: y)
            panel.addChild(time)
            let bumps = makeLabel(Strings.hits(entry.3), size: 13, color: UIColor.white.withAlphaComponent(0.7))
            bumps.horizontalAlignmentMode = .right
            bumps.position = CGPoint(x: panelWidth / 2 - 44, y: y)
            panel.addChild(bumps)
            if rows == 2, let time = entry.2, let best = bestTime, time == best {
                let crown = makeLabel("👑", size: 20, color: .white)
                crown.position = CGPoint(x: panelWidth / 2 - 22, y: y)
                panel.addChild(crown)
            }
        }

        panel.setScale(0.7)
        panel.alpha = 0
        panel.run(.group([.fadeIn(withDuration: 0.2), .scale(to: 1, duration: 0.2)]))
    }

    private func showFinal() {
        overlay.removeAllChildren()
        let panel = SKShapeNode(rectOf: CGSize(width: 360, height: 180), cornerRadius: 24)
        panel.fillColor = UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 0.95)
        panel.strokeColor = UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 0.8)
        panel.lineWidth = 3
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.addChild(panel)

        let trophy = makeLabel("🏆", size: 40, color: .white)
        trophy.position = CGPoint(x: 0, y: 46)
        panel.addChild(trophy)
        let title = makeLabel(Strings.allDone, size: 22, color: .white)
        title.position = CGPoint(x: 0, y: 2)
        panel.addChild(title)

        let button = SKShapeNode(rectOf: CGSize(width: 200, height: 44), cornerRadius: 14)
        button.fillColor = UIColor(red: 0.25, green: 0.70, blue: 0.45, alpha: 1)
        button.strokeColor = .clear
        button.position = CGPoint(x: size.width / 2, y: size.height / 2 - 52)
        button.addChild(makeLabel(Strings.backToMenu, size: 16, color: .white))
        overlay.addChild(button)
        finalButton = button
        notifyHaptic.notificationOccurred(.success)
    }

    private func showToast(_ text: String) {
        let toast = makeLabel(text, size: 16, color: UIColor(red: 1, green: 0.7, blue: 0.6, alpha: 1))
        toast.position = CGPoint(x: size.width / 2, y: size.height / 2 + 70)
        toast.zPosition = 10
        hud.addChild(toast)
        toast.run(.sequence([.wait(forDuration: 2.0), .fadeOut(withDuration: 0.4), .removeFromParent()]))
    }
}

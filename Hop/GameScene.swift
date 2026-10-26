import SpriteKit
import UIKit

// MARK: - Colors

enum Palette {
    static let skyTop = UIColor(red: 0.36, green: 0.62, blue: 0.98, alpha: 1)
    static let skyBottom = UIColor(red: 0.76, green: 0.89, blue: 1.00, alpha: 1)
    static let sun = UIColor(red: 1.00, green: 0.86, blue: 0.42, alpha: 1)
    static let hillBack = UIColor(red: 0.53, green: 0.79, blue: 0.55, alpha: 1)
    static let hillFront = UIColor(red: 0.43, green: 0.73, blue: 0.45, alpha: 1)
    static let grass = UIColor(red: 0.35, green: 0.68, blue: 0.32, alpha: 1)
    static let ground = UIColor(red: 0.85, green: 0.66, blue: 0.43, alpha: 1)
    static let groundMark = UIColor(red: 0.75, green: 0.56, blue: 0.35, alpha: 1)
    static let player = UIColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1)
    static let playerDark = UIColor(red: 0.80, green: 0.36, blue: 0.10, alpha: 1)
    static let ink = UIColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 1)
    static let obstacles: [UIColor] = [
        UIColor(red: 0.91, green: 0.30, blue: 0.36, alpha: 1),
        UIColor(red: 0.42, green: 0.36, blue: 0.85, alpha: 1),
        UIColor(red: 0.16, green: 0.62, blue: 0.62, alpha: 1)
    ]
}

extension UIColor {
    func darker(by amount: CGFloat = 0.2) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: saturation, brightness: max(brightness - amount, 0), alpha: alpha)
    }
}

// MARK: - Scene

final class GameScene: SKScene {

    private enum GameState {
        case ready
        case playing
        case over
    }

    // State
    private var state: GameState = .ready
    private var builtSize: CGSize = .zero
    private var lastUpdate: TimeInterval = 0
    private var canRestartAt: TimeInterval = 0

    // Layers
    private let world = SKNode()
    private let hud = SKNode()
    private let overlay = SKNode()

    // Nodes
    private var player = SKNode()
    private var playerBody = SKShapeNode()
    private var scoreLabel = SKLabelNode()
    private var obstacles: [SKNode] = []
    private var clouds: [SKNode] = []
    private var groundMarks: [SKNode] = []

    // Metrics
    private let playerSize: CGFloat = 46
    private var groundTop: CGFloat = 0
    private var markSpacing: CGFloat = 70

    // Movement
    private var velocityY: CGFloat = 0
    private var gravity: CGFloat = -2500
    private var jumpVelocity: CGFloat = 1000
    private var jumpsLeft = 2
    private var onGround = true
    private var runSpeed: CGFloat = 260
    private var baseSpeed: CGFloat = 260
    private var maxSpeed: CGFloat = 520
    private var distanceToNextSpawn: CGFloat = 0

    // Score
    private var score = 0
    private var best: Int {
        get { UserDefaults.standard.integer(forKey: "hop.best") }
        set { UserDefaults.standard.set(newValue, forKey: "hop.best") }
    }

    // Haptics
    private lazy var impact = UIImpactFeedbackGenerator(style: .light)
    private lazy var notify = UINotificationFeedbackGenerator()

    // MARK: Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = Palette.skyBottom
        buildIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        buildIfNeeded()
    }

    private func buildIfNeeded() {
        guard size.width > 1, size.height > 1, size != builtSize else { return }
        builtSize = size
        build()
    }

    // MARK: Building the world

    private func build() {
        removeAllActions()
        world.removeAllChildren()
        hud.removeAllChildren()
        overlay.removeAllChildren()
        removeAllChildren()
        obstacles.removeAll()
        clouds.removeAll()
        groundMarks.removeAll()

        addChild(world)
        addChild(hud)
        addChild(overlay)
        world.zPosition = 0
        hud.zPosition = 100
        overlay.zPosition = 200

        let w = size.width
        let h = size.height
        groundTop = h * 0.24
        gravity = -h * 3.0
        jumpVelocity = h * 1.2
        baseSpeed = w * 0.68
        maxSpeed = w * 1.35

        // Sky
        let sky = SKSpriteNode(texture: Self.gradientTexture(top: Palette.skyTop, bottom: Palette.skyBottom))
        sky.size = size
        sky.position = CGPoint(x: w / 2, y: h / 2)
        sky.zPosition = -100
        world.addChild(sky)

        // Sun
        let sun = SKShapeNode(circleOfRadius: w * 0.11)
        sun.fillColor = Palette.sun
        sun.strokeColor = .clear
        sun.position = CGPoint(x: w * 0.78, y: h * 0.80)
        sun.zPosition = -90
        world.addChild(sun)

        // Clouds
        for index in 0..<4 {
            let cloud = makeCloud(scale: CGFloat.random(in: 0.7...1.2))
            cloud.position = CGPoint(x: CGFloat(index) * w * 0.33 + CGFloat.random(in: 0...40),
                                     y: CGFloat.random(in: h * 0.55...h * 0.86))
            cloud.zPosition = -80
            world.addChild(cloud)
            clouds.append(cloud)
        }

        // Hills
        let hills: [(CGFloat, CGFloat, UIColor)] = [
            (0.10, 0.42, Palette.hillBack),
            (0.70, 0.50, Palette.hillBack),
            (0.35, 0.34, Palette.hillFront),
            (1.00, 0.38, Palette.hillFront)
        ]
        for (index, hill) in hills.enumerated() {
            let radius = w * hill.1
            let node = SKShapeNode(circleOfRadius: radius)
            node.fillColor = hill.2
            node.strokeColor = .clear
            node.position = CGPoint(x: w * hill.0, y: groundTop - radius * 0.45)
            node.zPosition = -60 + CGFloat(index)
            world.addChild(node)
        }

        // Ground
        let ground = SKShapeNode(rect: CGRect(x: 0, y: 0, width: w, height: groundTop))
        ground.fillColor = Palette.ground
        ground.strokeColor = .clear
        ground.zPosition = -10
        world.addChild(ground)

        let grass = SKShapeNode(rect: CGRect(x: 0, y: groundTop - 14, width: w, height: 14))
        grass.fillColor = Palette.grass
        grass.strokeColor = .clear
        grass.zPosition = -9
        world.addChild(grass)

        markSpacing = 70
        let markCount = Int(ceil((w + 80) / markSpacing)) + 1
        for index in 0..<markCount {
            let mark = SKShapeNode(rectOf: CGSize(width: 26, height: 6), cornerRadius: 3)
            mark.fillColor = Palette.groundMark
            mark.strokeColor = .clear
            mark.position = CGPoint(x: CGFloat(index) * markSpacing, y: groundTop * 0.55)
            mark.zPosition = -8
            world.addChild(mark)
            groundMarks.append(mark)
        }

        // Player
        player = SKNode()
        player.zPosition = 10
        let body = SKShapeNode(rectOf: CGSize(width: playerSize, height: playerSize), cornerRadius: 12)
        body.fillColor = Palette.player
        body.strokeColor = Palette.playerDark
        body.lineWidth = 3
        player.addChild(body)
        playerBody = body
        for dx: CGFloat in [-8, 10] {
            let eye = SKShapeNode(circleOfRadius: 7)
            eye.fillColor = .white
            eye.strokeColor = .clear
            eye.position = CGPoint(x: dx, y: 6)
            body.addChild(eye)
            let pupil = SKShapeNode(circleOfRadius: 3.5)
            pupil.fillColor = Palette.ink
            pupil.strokeColor = .clear
            pupil.position = CGPoint(x: dx + 2.5, y: 6)
            body.addChild(pupil)
        }
        world.addChild(player)

        // HUD
        let topInset = max(view?.safeAreaInsets.top ?? 0, 44)
        scoreLabel = makeLabel("0", fontSize: 56, color: .white)
        scoreLabel.position = CGPoint(x: w / 2, y: h - topInset - 50)
        hud.addChild(scoreLabel)

        resetRun()
        state = .ready
        showReady()
    }

    private func makeCloud(scale: CGFloat) -> SKNode {
        let cloud = SKNode()
        let parts: [(CGFloat, CGFloat, CGFloat)] = [(-26, 0, 22), (0, 8, 28), (28, 0, 20)]
        for part in parts {
            let puff = SKShapeNode(circleOfRadius: part.2)
            puff.fillColor = UIColor.white.withAlphaComponent(0.9)
            puff.strokeColor = .clear
            puff.position = CGPoint(x: part.0, y: part.1)
            cloud.addChild(puff)
        }
        cloud.setScale(scale)
        return cloud
    }

    private func makeLabel(_ text: String, fontSize: CGFloat, color: UIColor) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = fontSize
        label.fontColor = color
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        return label
    }

    private static func gradientTexture(top: UIColor, bottom: UIColor) -> SKTexture {
        let textureSize = CGSize(width: 4, height: 256)
        let renderer = UIGraphicsImageRenderer(size: textureSize)
        let image = renderer.image { context in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient,
                                                     start: .zero,
                                                     end: CGPoint(x: 0, y: textureSize.height),
                                                     options: [])
            }
        }
        return SKTexture(image: image)
    }

    // MARK: Overlays

    private func showReady() {
        overlay.removeAllChildren()
        scoreLabel.isHidden = true
        let w = size.width
        let h = size.height

        let title = makeLabel(Strings.title, fontSize: 72, color: .white)
        title.position = CGPoint(x: w / 2, y: h * 0.66)
        overlay.addChild(title)

        let start = makeLabel(Strings.tapToStart, fontSize: 24, color: Palette.ink)
        start.position = CGPoint(x: w / 2, y: h * 0.56)
        start.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.6),
                                            .fadeAlpha(to: 1.0, duration: 0.6)])))
        overlay.addChild(start)

        let hint = makeLabel(Strings.hint, fontSize: 15, color: Palette.ink.withAlphaComponent(0.75))
        hint.numberOfLines = 0
        hint.preferredMaxLayoutWidth = w * 0.8
        hint.position = CGPoint(x: w / 2, y: h * 0.50)
        overlay.addChild(hint)

        if best > 0 {
            let bestLabel = makeLabel(Strings.best(best), fontSize: 18, color: Palette.ink)
            bestLabel.position = CGPoint(x: w / 2, y: h * 0.45)
            overlay.addChild(bestLabel)
        }

        playerBody.removeAction(forKey: "idle")
        playerBody.position = .zero
        playerBody.run(.repeatForever(.sequence([.moveBy(x: 0, y: 5, duration: 0.45),
                                                 .moveBy(x: 0, y: -5, duration: 0.45)])),
                       withKey: "idle")
    }

    private func showGameOver(isNewBest: Bool) {
        overlay.removeAllChildren()
        let w = size.width
        let h = size.height

        let panel = SKShapeNode(rectOf: CGSize(width: min(w * 0.8, 340), height: 230), cornerRadius: 24)
        panel.fillColor = UIColor.white.withAlphaComponent(0.92)
        panel.strokeColor = .clear
        panel.position = CGPoint(x: w / 2, y: h * 0.58)
        overlay.addChild(panel)

        let title = makeLabel(Strings.gameOver, fontSize: 30, color: Palette.ink)
        title.position = CGPoint(x: 0, y: 72)
        panel.addChild(title)

        let scoreText = makeLabel("\(score)", fontSize: 64, color: Palette.player)
        scoreText.position = CGPoint(x: 0, y: 12)
        panel.addChild(scoreText)

        let bestText = makeLabel(isNewBest ? Strings.newBest : Strings.best(best),
                                 fontSize: 18,
                                 color: isNewBest ? Palette.obstacles[0] : Palette.ink)
        bestText.position = CGPoint(x: 0, y: -38)
        panel.addChild(bestText)

        let retry = makeLabel(Strings.tapToRetry, fontSize: 18, color: Palette.ink.withAlphaComponent(0.7))
        retry.position = CGPoint(x: 0, y: -80)
        retry.alpha = 0
        retry.run(.sequence([.wait(forDuration: 0.6),
                             .repeatForever(.sequence([.fadeAlpha(to: 1.0, duration: 0.5),
                                                       .fadeAlpha(to: 0.35, duration: 0.5)]))]))
        panel.addChild(retry)

        panel.setScale(0.7)
        panel.alpha = 0
        panel.run(.group([.fadeIn(withDuration: 0.2), .scale(to: 1.0, duration: 0.2)]))
    }

    // MARK: Run control

    private func resetRun() {
        for obstacle in obstacles { obstacle.removeFromParent() }
        obstacles.removeAll()
        score = 0
        scoreLabel.text = "0"
        runSpeed = baseSpeed
        velocityY = 0
        jumpsLeft = 2
        onGround = true
        world.removeAllActions()
        world.position = .zero
        player.removeAllActions()
        player.zRotation = 0
        player.position = CGPoint(x: size.width * 0.28, y: groundTop + playerSize / 2)
        playerBody.fillColor = Palette.player
        distanceToNextSpawn = size.width * 0.5
    }

    private func startRun() {
        overlay.removeAllChildren()
        playerBody.removeAction(forKey: "idle")
        playerBody.position = .zero
        scoreLabel.isHidden = false
        state = .playing
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch state {
        case .ready:
            startRun()
            jump()
        case .playing:
            jump()
        case .over:
            guard lastUpdate >= canRestartAt else { return }
            resetRun()
            startRun()
        }
    }

    private func jump() {
        guard jumpsLeft > 0 else { return }
        let isDoubleJump = !onGround
        velocityY = isDoubleJump ? jumpVelocity * 0.85 : jumpVelocity
        jumpsLeft -= 1
        onGround = false
        impact.impactOccurred()
        puff(at: CGPoint(x: player.position.x, y: player.position.y - playerSize / 2), count: isDoubleJump ? 4 : 6)

        playerBody.removeAction(forKey: "squash")
        playerBody.run(.sequence([.scaleX(to: 0.8, y: 1.2, duration: 0.08),
                                  .scale(to: 1.0, duration: 0.15)]),
                       withKey: "squash")
        if isDoubleJump {
            player.removeAction(forKey: "spin")
            player.run(.rotate(byAngle: -CGFloat.pi * 2, duration: 0.45), withKey: "spin")
        }
    }

    private func land() {
        player.removeAction(forKey: "spin")
        player.zRotation = 0
        playerBody.removeAction(forKey: "squash")
        playerBody.run(.sequence([.scaleX(to: 1.2, y: 0.8, duration: 0.06),
                                  .scale(to: 1.0, duration: 0.12)]),
                       withKey: "squash")
        puff(at: CGPoint(x: player.position.x, y: groundTop), count: 3)
    }

    private func crash() {
        state = .over
        notify.notificationOccurred(.error)
        playerBody.fillColor = Palette.obstacles[0]
        player.removeAction(forKey: "spin")

        let isNewBest = score > best
        if isNewBest { best = score }
        canRestartAt = lastUpdate + 0.6

        world.run(.sequence([.moveBy(x: 10, y: 0, duration: 0.04),
                             .moveBy(x: -20, y: 0, duration: 0.04),
                             .moveBy(x: 14, y: 0, duration: 0.04),
                             .moveBy(x: -4, y: 0, duration: 0.04)]))
        showGameOver(isNewBest: isNewBest)
    }

    private func addPoint() {
        score += 1
        scoreLabel.text = "\(score)"
        scoreLabel.removeAction(forKey: "pulse")
        scoreLabel.setScale(1.0)
        scoreLabel.run(.sequence([.scale(to: 1.25, duration: 0.07), .scale(to: 1.0, duration: 0.12)]),
                       withKey: "pulse")
        runSpeed = min(maxSpeed, runSpeed + size.width * 0.018)
    }

    private func puff(at point: CGPoint, count: Int) {
        for _ in 0..<count {
            let particle = SKShapeNode(circleOfRadius: CGFloat.random(in: 3...6))
            particle.fillColor = UIColor.white.withAlphaComponent(0.85)
            particle.strokeColor = .clear
            particle.position = point
            particle.zPosition = 8
            world.addChild(particle)
            let dx = CGFloat.random(in: -30...30)
            let dy = CGFloat.random(in: -4...14)
            particle.run(.sequence([
                .group([.moveBy(x: dx, y: dy, duration: 0.35),
                        .fadeOut(withDuration: 0.35),
                        .scale(to: 0.3, duration: 0.35)]),
                .removeFromParent()
            ]))
        }
    }

    // MARK: Obstacles

    private func spawnObstacle() {
        let h = size.height
        let width = CGFloat.random(in: 30...44)
        let tallAllowed = score >= 8
        let height = CGFloat.random(in: h * 0.05...(tallAllowed ? h * 0.15 : h * 0.11))
        let color = Palette.obstacles.randomElement() ?? Palette.obstacles[0]

        let obstacle = SKNode()
        let block = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 8)
        block.fillColor = color
        block.strokeColor = color.darker(by: 0.2)
        block.lineWidth = 3
        obstacle.addChild(block)

        let band = SKShapeNode(rectOf: CGSize(width: width - 10, height: 7), cornerRadius: 3)
        band.fillColor = UIColor.white.withAlphaComponent(0.35)
        band.strokeColor = .clear
        band.position = CGPoint(x: 0, y: height / 2 - 11)
        block.addChild(band)

        obstacle.position = CGPoint(x: size.width + width, y: groundTop + height / 2)
        obstacle.zPosition = 5
        world.addChild(obstacle)
        obstacles.append(obstacle)
    }

    // MARK: Update loop

    override func update(_ currentTime: TimeInterval) {
        let rawDelta = lastUpdate == 0 ? 1.0 / 60.0 : currentTime - lastUpdate
        let dt = CGFloat(min(max(rawDelta, 0), 1.0 / 30.0))
        lastUpdate = currentTime
        guard builtSize != .zero else { return }

        moveClouds(dt)
        if state == .playing {
            stepPlaying(dt)
        }
    }

    private func moveClouds(_ dt: CGFloat) {
        let w = size.width
        let drift = (state == .playing ? runSpeed * 0.12 : 14) * dt
        for cloud in clouds {
            cloud.position.x -= drift
            if cloud.position.x < -80 {
                cloud.position.x = w + 80
                cloud.position.y = CGFloat.random(in: size.height * 0.55...size.height * 0.86)
            }
        }
    }

    private func stepPlaying(_ dt: CGFloat) {
        // Player vertical motion
        velocityY += gravity * dt
        player.position.y += velocityY * dt
        let floorY = groundTop + playerSize / 2
        if player.position.y <= floorY {
            player.position.y = floorY
            if !onGround { land() }
            velocityY = 0
            onGround = true
            jumpsLeft = 2
        }

        // Scroll ground marks
        let dx = runSpeed * dt
        let wrapWidth = markSpacing * CGFloat(groundMarks.count)
        for mark in groundMarks {
            mark.position.x -= dx
            if mark.position.x < -40 {
                mark.position.x += wrapWidth
            }
        }

        // Move obstacles, score and check collisions
        let playerRect = CGRect(x: player.position.x - playerSize / 2 + 5,
                                y: player.position.y - playerSize / 2 + 3,
                                width: playerSize - 10,
                                height: playerSize - 8)
        for obstacle in obstacles {
            obstacle.position.x -= dx
            let frame = obstacle.calculateAccumulatedFrame().insetBy(dx: 3, dy: 3)
            if obstacle.name != "scored" && frame.maxX < playerRect.minX {
                obstacle.name = "scored"
                addPoint()
            }
            if frame.intersects(playerRect) {
                crash()
                return
            }
        }

        // Remove off-screen obstacles
        obstacles.removeAll { obstacle in
            if obstacle.calculateAccumulatedFrame().maxX < -20 {
                obstacle.removeFromParent()
                return true
            }
            return false
        }

        // Spawn new obstacles
        distanceToNextSpawn -= dx
        if distanceToNextSpawn <= 0 {
            spawnObstacle()
            distanceToNextSpawn = runSpeed * CGFloat.random(in: 0.95...1.6)
        }
    }
}

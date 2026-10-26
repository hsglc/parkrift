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
    static let pillars: [UIColor] = [
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

/// A top + bottom pillar with a gap the player flies through.
private final class PillarPair {
    let node: SKNode
    let width: CGFloat
    let gapBottom: CGFloat
    let gapTop: CGFloat
    var scored = false

    init(node: SKNode, width: CGFloat, gapBottom: CGFloat, gapTop: CGFloat) {
        self.node = node
        self.width = width
        self.gapBottom = gapBottom
        self.gapTop = gapTop
    }

    var minX: CGFloat { node.position.x - width / 2 }
    var maxX: CGFloat { node.position.x + width / 2 }
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
    private var pillars: [PillarPair] = []
    private var clouds: [SKNode] = []
    private var groundMarks: [SKNode] = []

    // Metrics
    private let playerSize: CGFloat = 40
    private var groundTop: CGFloat = 0
    private var markSpacing: CGFloat = 70
    private var pillarWidth: CGFloat = 64
    private var pillarSpacing: CGFloat = 240

    // Movement
    private var velocityY: CGFloat = 0
    private var gravity: CGFloat = -1800
    private var flapVelocity: CGFloat = 520
    private var maxFallSpeed: CGFloat = 900
    private var scrollSpeed: CGFloat = 200
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
        pillars.removeAll()
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
        groundTop = h * 0.16
        gravity = -h * 2.2
        flapVelocity = h * 0.62
        maxFallSpeed = h * 1.1
        scrollSpeed = w * 0.52
        pillarWidth = max(56, w * 0.17)
        pillarSpacing = w * 0.62

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
        sun.position = CGPoint(x: w * 0.78, y: h * 0.82)
        sun.zPosition = -90
        world.addChild(sun)

        // Clouds
        for index in 0..<4 {
            let cloud = makeCloud(scale: CGFloat.random(in: 0.7...1.2))
            cloud.position = CGPoint(x: CGFloat(index) * w * 0.33 + CGFloat.random(in: 0...40),
                                     y: CGFloat.random(in: h * 0.45...h * 0.88))
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

        // Ground (drawn above pillars so pillars disappear into it)
        let ground = SKShapeNode(rect: CGRect(x: 0, y: 0, width: w, height: groundTop))
        ground.fillColor = Palette.ground
        ground.strokeColor = .clear
        ground.zPosition = 20
        world.addChild(ground)

        let grass = SKShapeNode(rect: CGRect(x: 0, y: groundTop - 14, width: w, height: 14))
        grass.fillColor = Palette.grass
        grass.strokeColor = .clear
        grass.zPosition = 21
        world.addChild(grass)

        markSpacing = 70
        let markCount = Int(ceil((w + 80) / markSpacing)) + 1
        for index in 0..<markCount {
            let mark = SKShapeNode(rectOf: CGSize(width: 26, height: 6), cornerRadius: 3)
            mark.fillColor = Palette.groundMark
            mark.strokeColor = .clear
            mark.position = CGPoint(x: CGFloat(index) * markSpacing, y: groundTop * 0.5)
            mark.zPosition = 22
            world.addChild(mark)
            groundMarks.append(mark)
        }

        // Player
        player = SKNode()
        player.zPosition = 30
        let body = SKShapeNode(rectOf: CGSize(width: playerSize, height: playerSize), cornerRadius: 11)
        body.fillColor = Palette.player
        body.strokeColor = Palette.playerDark
        body.lineWidth = 3
        player.addChild(body)
        playerBody = body
        for dx: CGFloat in [-6, 9] {
            let eye = SKShapeNode(circleOfRadius: 6)
            eye.fillColor = .white
            eye.strokeColor = .clear
            eye.position = CGPoint(x: dx, y: 5)
            body.addChild(eye)
            let pupil = SKShapeNode(circleOfRadius: 3)
            pupil.fillColor = Palette.ink
            pupil.strokeColor = .clear
            pupil.position = CGPoint(x: dx + 2, y: 5)
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
        title.position = CGPoint(x: w / 2, y: h * 0.72)
        overlay.addChild(title)

        let start = makeLabel(Strings.tapToStart, fontSize: 24, color: Palette.ink)
        start.position = CGPoint(x: w / 2, y: h * 0.36)
        start.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.6),
                                            .fadeAlpha(to: 1.0, duration: 0.6)])))
        overlay.addChild(start)

        let hint = makeLabel(Strings.hint, fontSize: 15, color: Palette.ink.withAlphaComponent(0.75))
        hint.numberOfLines = 0
        hint.preferredMaxLayoutWidth = w * 0.8
        hint.position = CGPoint(x: w / 2, y: h * 0.31)
        overlay.addChild(hint)

        if best > 0 {
            let bestLabel = makeLabel(Strings.best(best), fontSize: 18, color: Palette.ink)
            bestLabel.position = CGPoint(x: w / 2, y: h * 0.26)
            overlay.addChild(bestLabel)
        }

        playerBody.removeAction(forKey: "idle")
        playerBody.position = .zero
        playerBody.run(.repeatForever(.sequence([.moveBy(x: 0, y: 8, duration: 0.4),
                                                 .moveBy(x: 0, y: -8, duration: 0.4)])),
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
                                 color: isNewBest ? Palette.pillars[0] : Palette.ink)
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
        for pair in pillars { pair.node.removeFromParent() }
        pillars.removeAll()
        score = 0
        scoreLabel.text = "0"
        velocityY = 0
        world.removeAllActions()
        world.position = .zero
        player.removeAllActions()
        player.zRotation = 0
        player.position = CGPoint(x: size.width * 0.3, y: size.height * 0.55)
        playerBody.fillColor = Palette.player
        distanceToNextSpawn = size.width * 0.75
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
            flap()
        case .playing:
            flap()
        case .over:
            guard lastUpdate >= canRestartAt else { return }
            resetRun()
            state = .ready
            showReady()
        }
    }

    private func flap() {
        velocityY = flapVelocity
        impact.impactOccurred()
        puff(at: CGPoint(x: player.position.x - playerSize * 0.4, y: player.position.y - playerSize * 0.3), count: 3)
        playerBody.removeAction(forKey: "squash")
        playerBody.run(.sequence([.scaleX(to: 0.85, y: 1.15, duration: 0.06),
                                  .scale(to: 1.0, duration: 0.12)]),
                       withKey: "squash")
    }

    private func crash() {
        state = .over
        notify.notificationOccurred(.error)
        playerBody.fillColor = Palette.pillars[0]

        let isNewBest = score > best
        if isNewBest { best = score }
        canRestartAt = lastUpdate + 0.7

        world.run(.sequence([.moveBy(x: 10, y: 0, duration: 0.04),
                             .moveBy(x: -20, y: 0, duration: 0.04),
                             .moveBy(x: 14, y: 0, duration: 0.04),
                             .moveBy(x: -4, y: 0, duration: 0.04)]))

        // Drop the player to the ground
        let floorY = groundTop + playerSize / 2
        let fallDistance = max(player.position.y - floorY, 0)
        player.run(.group([
            .rotate(toAngle: -CGFloat.pi / 2, duration: 0.25, shortestUnitArc: true),
            .moveTo(y: floorY, duration: TimeInterval(min(0.6, 0.15 + fallDistance / 900)))
        ]))
        showGameOver(isNewBest: isNewBest)
    }

    private func addPoint() {
        score += 1
        scoreLabel.text = "\(score)"
        scoreLabel.removeAction(forKey: "pulse")
        scoreLabel.setScale(1.0)
        scoreLabel.run(.sequence([.scale(to: 1.25, duration: 0.07), .scale(to: 1.0, duration: 0.12)]),
                       withKey: "pulse")
    }

    private func puff(at point: CGPoint, count: Int) {
        for _ in 0..<count {
            let particle = SKShapeNode(circleOfRadius: CGFloat.random(in: 3...5))
            particle.fillColor = UIColor.white.withAlphaComponent(0.85)
            particle.strokeColor = .clear
            particle.position = point
            particle.zPosition = 29
            world.addChild(particle)
            let dx = CGFloat.random(in: -26...(-6))
            let dy = CGFloat.random(in: -14...4)
            particle.run(.sequence([
                .group([.moveBy(x: dx, y: dy, duration: 0.3),
                        .fadeOut(withDuration: 0.3),
                        .scale(to: 0.3, duration: 0.3)]),
                .removeFromParent()
            ]))
        }
    }

    // MARK: Pillars

    private func spawnPillars() {
        let h = size.height
        // The gap narrows slightly as the score grows.
        let gapHeight = max(h * 0.20, h * 0.26 - CGFloat(score) * h * 0.002)
        let ceilingMargin = h * 0.10
        let floorMargin = groundTop + h * 0.08
        let minCenter = floorMargin + gapHeight / 2
        let maxCenter = h - ceilingMargin - gapHeight / 2
        let center = CGFloat.random(in: minCenter...max(minCenter, maxCenter))
        let gapBottom = center - gapHeight / 2
        let gapTop = center + gapHeight / 2

        let color = Palette.pillars.randomElement() ?? Palette.pillars[0]
        let pair = SKNode()
        pair.position = CGPoint(x: size.width + pillarWidth, y: 0)
        pair.zPosition = 10

        // Bottom pillar: from below the ground up to the gap.
        let bottomHeight = gapBottom + 20
        pair.addChild(makePillar(height: bottomHeight, color: color, bandAtTop: true,
                                 centerY: (gapBottom - 20) / 2))
        // Top pillar: from the gap up past the top of the screen.
        let topHeight = h - gapTop + 20
        pair.addChild(makePillar(height: topHeight, color: color, bandAtTop: false,
                                 centerY: gapTop + topHeight / 2))

        world.addChild(pair)
        pillars.append(PillarPair(node: pair, width: pillarWidth, gapBottom: gapBottom, gapTop: gapTop))
    }

    private func makePillar(height: CGFloat, color: UIColor, bandAtTop: Bool, centerY: CGFloat) -> SKNode {
        let pillar = SKShapeNode(rectOf: CGSize(width: pillarWidth, height: height), cornerRadius: 12)
        pillar.fillColor = color
        pillar.strokeColor = color.darker(by: 0.2)
        pillar.lineWidth = 4
        pillar.position = CGPoint(x: 0, y: centerY)

        // Light stripes facing the gap
        for index in 0..<2 {
            let stripe = SKShapeNode(rectOf: CGSize(width: pillarWidth - 14, height: 7), cornerRadius: 3)
            stripe.fillColor = UIColor.white.withAlphaComponent(index == 0 ? 0.4 : 0.25)
            stripe.strokeColor = .clear
            let offset = height / 2 - 14 - CGFloat(index) * 14
            stripe.position = CGPoint(x: 0, y: bandAtTop ? offset : -offset)
            pillar.addChild(stripe)
        }
        // A soft vertical highlight
        let highlight = SKShapeNode(rectOf: CGSize(width: 8, height: max(height - 40, 8)), cornerRadius: 4)
        highlight.fillColor = UIColor.white.withAlphaComponent(0.18)
        highlight.strokeColor = .clear
        highlight.position = CGPoint(x: -pillarWidth / 2 + 12, y: 0)
        pillar.addChild(highlight)
        return pillar
    }

    // MARK: Update loop

    override func update(_ currentTime: TimeInterval) {
        let rawDelta = lastUpdate == 0 ? 1.0 / 60.0 : currentTime - lastUpdate
        let dt = CGFloat(min(max(rawDelta, 0), 1.0 / 30.0))
        lastUpdate = currentTime
        guard builtSize != .zero else { return }

        moveClouds(dt)
        if state != .over {
            scrollGround(dt)
        }
        if state == .playing {
            stepPlaying(dt)
        }
    }

    private func moveClouds(_ dt: CGFloat) {
        let w = size.width
        let drift = (state == .playing ? scrollSpeed * 0.12 : 14) * dt
        for cloud in clouds {
            cloud.position.x -= drift
            if cloud.position.x < -80 {
                cloud.position.x = w + 80
                cloud.position.y = CGFloat.random(in: size.height * 0.45...size.height * 0.88)
            }
        }
    }

    private func scrollGround(_ dt: CGFloat) {
        let dx = scrollSpeed * dt
        let wrapWidth = markSpacing * CGFloat(groundMarks.count)
        for mark in groundMarks {
            mark.position.x -= dx
            if mark.position.x < -40 {
                mark.position.x += wrapWidth
            }
        }
    }

    private func stepPlaying(_ dt: CGFloat) {
        let h = size.height

        // Vertical motion
        velocityY = max(velocityY + gravity * dt, -maxFallSpeed)
        player.position.y += velocityY * dt
        let ceilingY = h - playerSize / 2
        if player.position.y > ceilingY {
            player.position.y = ceilingY
            velocityY = min(velocityY, 0)
        }

        // Tilt: nose up while rising, down while falling
        let targetAngle = max(min(velocityY / flapVelocity * 0.45, 0.45), -1.2)
        player.zRotation += (targetAngle - player.zRotation) * min(1, dt * 10)

        // Ground hit
        if player.position.y - playerSize / 2 <= groundTop {
            player.position.y = groundTop + playerSize / 2
            crash()
            return
        }

        // Move pillars, score and check collisions
        let dx = scrollSpeed * dt
        let half = playerSize / 2 - 5
        let playerMinX = player.position.x - half
        let playerMaxX = player.position.x + half
        let playerMinY = player.position.y - half
        let playerMaxY = player.position.y + half

        for pair in pillars {
            pair.node.position.x -= dx
            if !pair.scored && pair.maxX < playerMinX {
                pair.scored = true
                addPoint()
            }
            let overlapsX = playerMaxX > pair.minX + 3 && playerMinX < pair.maxX - 3
            if overlapsX && (playerMinY < pair.gapBottom || playerMaxY > pair.gapTop) {
                crash()
                return
            }
        }

        // Remove off-screen pillars
        pillars.removeAll { pair in
            if pair.maxX < -20 {
                pair.node.removeFromParent()
                return true
            }
            return false
        }

        // Spawn new pillars
        distanceToNextSpawn -= dx
        if distanceToNextSpawn <= 0 {
            spawnPillars()
            distanceToNextSpawn = pillarSpacing
        }
    }
}

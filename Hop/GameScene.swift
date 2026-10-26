import SpriteKit
import UIKit

// MARK: - Colors

enum Palette {
    static let ink = UIColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 1)
    static let accent = UIColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1)
    static let danger = UIColor(red: 0.91, green: 0.30, blue: 0.36, alpha: 1)
    static let gold = UIColor(red: 0.96, green: 0.66, blue: 0.12, alpha: 1)
    static let pillars: [UIColor] = [
        UIColor(red: 0.91, green: 0.36, blue: 0.42, alpha: 1),
        UIColor(red: 0.46, green: 0.40, blue: 0.88, alpha: 1),
        UIColor(red: 0.18, green: 0.66, blue: 0.66, alpha: 1)
    ]
}

extension UIColor {
    func darker(by amount: CGFloat = 0.2) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: saturation, brightness: max(brightness - amount, 0), alpha: alpha)
    }
}

// MARK: - Entities

/// A top + bottom pillar with a gap the player flies through.
private final class PillarPair {
    let node: SKNode
    let halfWidth: CGFloat
    let gapBottom: CGFloat
    let gapTop: CGFloat
    var scored = false

    init(node: SKNode, halfWidth: CGFloat, gapBottom: CGFloat, gapTop: CGFloat) {
        self.node = node
        self.halfWidth = halfWidth
        self.gapBottom = gapBottom
        self.gapTop = gapTop
    }

    var minX: CGFloat { node.position.x - halfWidth }
    var maxX: CGFloat { node.position.x + halfWidth }

    func blocks(_ point: CGPoint, radius: CGFloat) -> Bool {
        guard point.x + radius > minX, point.x - radius < maxX else { return false }
        return point.y - radius < gapBottom || point.y + radius > gapTop
    }
}

private final class Monster {
    let node: SKSpriteNode
    let baseY: CGFloat
    let amplitude: CGFloat
    var phase: CGFloat
    var dead = false

    init(node: SKSpriteNode, baseY: CGFloat, amplitude: CGFloat, phase: CGFloat) {
        self.node = node
        self.baseY = baseY
        self.amplitude = amplitude
        self.phase = phase
    }
}

private struct ParallaxLayer {
    let sprites: [SKSpriteNode]
    let factor: CGFloat
    let width: CGFloat
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
    private var nextFireAt: TimeInterval = 0

    // Layers
    private let world = SKNode()
    private let hud = SKNode()
    private let overlay = SKNode()

    // Textures (rebuilt per screen size)
    private var pillarBodies: [SKTexture] = []
    private var pillarCaps: [SKTexture] = []
    private var coinTexture = SKTexture()
    private var monsterTexture = SKTexture()
    private var bulletTexture = SKTexture()
    private var dotTexture = SKTexture()
    private var starTexture = SKTexture()

    // Nodes
    private var player = SKNode()
    private var playerBody = SKSpriteNode()
    private var wing = SKSpriteNode()
    private var shadow = SKSpriteNode()
    private var scoreLabel = SKLabelNode()
    private var scoreShadow = SKLabelNode()
    private var coinLabel = SKLabelNode()
    private var coinIcon = SKSpriteNode()
    private var fireButton = SKSpriteNode()
    private var layers: [ParallaxLayer] = []
    private var clouds: [SKSpriteNode] = []
    private var pillars: [PillarPair] = []
    private var monsters: [Monster] = []
    private var coins: [SKSpriteNode] = []
    private var bullets: [SKSpriteNode] = []

    // Metrics
    private let playerSize: CGFloat = 44
    private let monsterSize: CGFloat = 52
    private let coinSize: CGFloat = 28
    private let bulletSize: CGFloat = 22
    private let capHeight: CGFloat = 24
    private var groundTop: CGFloat = 0
    private var pillarWidth: CGFloat = 64
    private var pillarSpacing: CGFloat = 240

    // Movement
    private var velocityY: CGFloat = 0
    private var gravity: CGFloat = -1800
    private var flapVelocity: CGFloat = 520
    private var maxFallSpeed: CGFloat = 900
    private var scrollSpeed: CGFloat = 200
    private var bulletSpeed: CGFloat = 600
    private var distanceToNextSpawn: CGFloat = 0

    // Score
    private var score = 0
    private var runCoins = 0
    private var best: Int {
        get { UserDefaults.standard.integer(forKey: "hop.best") }
        set { UserDefaults.standard.set(newValue, forKey: "hop.best") }
    }
    private var totalCoins: Int {
        get { UserDefaults.standard.integer(forKey: "hop.coins") }
        set { UserDefaults.standard.set(newValue, forKey: "hop.coins") }
    }

    // Haptics
    private lazy var lightImpact = UIImpactFeedbackGenerator(style: .light)
    private lazy var rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private lazy var notify = UINotificationFeedbackGenerator()

    // MARK: Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.78, green: 0.89, blue: 1.0, alpha: 1)
        view.isMultipleTouchEnabled = true
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
        layers.removeAll()
        clouds.removeAll()
        pillars.removeAll()
        monsters.removeAll()
        coins.removeAll()
        bullets.removeAll()

        addChild(world)
        addChild(hud)
        addChild(overlay)
        hud.zPosition = 100
        overlay.zPosition = 200

        let w = size.width
        let h = size.height
        groundTop = h * 0.15
        gravity = -h * 2.2
        flapVelocity = h * 0.62
        maxFallSpeed = h * 1.1
        scrollSpeed = w * 0.52
        bulletSpeed = w * 1.6
        pillarWidth = max(58, w * 0.17)
        pillarSpacing = w * 0.66

        // Textures
        pillarBodies = Palette.pillars.map { Art.pillarBody(width: pillarWidth, color: $0) }
        pillarCaps = Palette.pillars.map { Art.pillarCap(width: pillarWidth + 14, height: capHeight, color: $0) }
        coinTexture = Art.coin(size: coinSize)
        monsterTexture = Art.monster(size: monsterSize)
        bulletTexture = Art.bullet(size: bulletSize)
        dotTexture = Art.dot()
        starTexture = Art.star()

        // Sky and sun
        let sky = SKSpriteNode(texture: Art.sky(size: size))
        sky.size = size
        sky.position = CGPoint(x: w / 2, y: h / 2)
        sky.zPosition = -100
        world.addChild(sky)

        let sunRadius = w * 0.10
        let sun = SKSpriteNode(texture: Art.sun(radius: sunRadius))
        sun.size = CGSize(width: sunRadius * 4, height: sunRadius * 4)
        sun.position = CGPoint(x: w * 0.76, y: h * 0.80)
        sun.zPosition = -95
        sun.run(.repeatForever(.sequence([.scale(to: 1.06, duration: 2.0), .scale(to: 1.0, duration: 2.0)])))
        world.addChild(sun)

        // Clouds
        let cloudTexture = Art.cloud(width: 140)
        for index in 0..<4 {
            let cloud = SKSpriteNode(texture: cloudTexture)
            let scale = CGFloat.random(in: 0.6...1.15)
            cloud.size = CGSize(width: 140 * scale, height: 77 * scale)
            cloud.alpha = CGFloat.random(in: 0.75...0.95)
            cloud.position = CGPoint(x: CGFloat(index) * w * 0.33 + CGFloat.random(in: 0...40),
                                     y: CGFloat.random(in: h * 0.50...h * 0.90))
            cloud.zPosition = -90
            world.addChild(cloud)
            clouds.append(cloud)
        }

        // Parallax landscape
        let mountainHeight = h * 0.30
        addParallax(texture: Art.mountains(width: w, height: mountainHeight),
                    height: mountainHeight, y: groundTop - 8, factor: 0.12, z: -80)
        let hillHeight = h * 0.20
        addParallax(texture: Art.hills(width: w, height: hillHeight),
                    height: hillHeight, y: groundTop - 8, factor: 0.32, z: -70)
        addParallax(texture: Art.ground(width: w, height: groundTop),
                    height: groundTop, y: 0, factor: 1.0, z: 20)

        // Player shadow
        shadow = SKSpriteNode(texture: Art.shadow())
        shadow.size = CGSize(width: playerSize * 1.1, height: 12)
        shadow.zPosition = 21
        world.addChild(shadow)

        // Player
        player = SKNode()
        player.zPosition = 30
        playerBody = SKSpriteNode(texture: Art.player(size: playerSize))
        playerBody.size = CGSize(width: playerSize, height: playerSize)
        player.addChild(playerBody)
        let wingWidth: CGFloat = 26
        wing = SKSpriteNode(texture: Art.wing(width: wingWidth))
        wing.size = CGSize(width: wingWidth, height: wingWidth * 0.62)
        wing.anchorPoint = CGPoint(x: 0.85, y: 0.5)
        wing.position = CGPoint(x: -playerSize * 0.12, y: -playerSize * 0.05)
        wing.zPosition = 1
        player.addChild(wing)
        world.addChild(player)

        // HUD
        let topInset = max(view?.safeAreaInsets.top ?? 0, 44)
        scoreShadow = makeLabel("0", fontSize: 60, color: Palette.ink.withAlphaComponent(0.30))
        scoreShadow.position = CGPoint(x: w / 2, y: h - topInset - 54)
        hud.addChild(scoreShadow)
        scoreLabel = makeLabel("0", fontSize: 60, color: .white)
        scoreLabel.position = CGPoint(x: w / 2, y: h - topInset - 50)
        hud.addChild(scoreLabel)

        coinIcon = SKSpriteNode(texture: coinTexture)
        coinIcon.size = CGSize(width: 26, height: 26)
        coinIcon.position = CGPoint(x: 30, y: h - topInset - 14)
        hud.addChild(coinIcon)
        coinLabel = makeLabel("0", fontSize: 22, color: .white)
        coinLabel.horizontalAlignmentMode = .left
        coinLabel.position = CGPoint(x: 50, y: h - topInset - 14)
        hud.addChild(coinLabel)

        let buttonSize: CGFloat = 76
        fireButton = SKSpriteNode(texture: Art.fireButton(size: buttonSize))
        fireButton.size = CGSize(width: buttonSize, height: buttonSize)
        fireButton.position = CGPoint(x: w - buttonSize / 2 - 22, y: max(groundTop * 0.5, buttonSize / 2 + 30))
        fireButton.alpha = 0.9
        hud.addChild(fireButton)

        resetRun()
        state = .ready
        showReady()
    }

    private func addParallax(texture: SKTexture, height: CGFloat, y: CGFloat, factor: CGFloat, z: CGFloat) {
        let w = size.width
        var sprites: [SKSpriteNode] = []
        for index in 0..<2 {
            let sprite = SKSpriteNode(texture: texture)
            sprite.size = CGSize(width: w + 1, height: height)
            sprite.anchorPoint = .zero
            sprite.position = CGPoint(x: CGFloat(index) * w, y: y)
            sprite.zPosition = z
            world.addChild(sprite)
            sprites.append(sprite)
        }
        layers.append(ParallaxLayer(sprites: sprites, factor: factor, width: w))
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

    // MARK: Overlays

    private func showReady() {
        overlay.removeAllChildren()
        scoreLabel.isHidden = true
        scoreShadow.isHidden = true
        updateCoinLabel()
        let w = size.width
        let h = size.height

        let titleShadow = makeLabel(Strings.title, fontSize: 76, color: Palette.ink.withAlphaComponent(0.25))
        titleShadow.position = CGPoint(x: w / 2, y: h * 0.72 - 5)
        overlay.addChild(titleShadow)
        let title = makeLabel(Strings.title, fontSize: 76, color: .white)
        title.position = CGPoint(x: w / 2, y: h * 0.72)
        overlay.addChild(title)

        let start = makeLabel(Strings.tapToStart, fontSize: 24, color: Palette.ink)
        start.position = CGPoint(x: w / 2, y: h * 0.40)
        start.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.6),
                                            .fadeAlpha(to: 1.0, duration: 0.6)])))
        overlay.addChild(start)

        let hint = makeLabel(Strings.hint, fontSize: 16, color: Palette.ink.withAlphaComponent(0.8))
        hint.numberOfLines = 0
        hint.preferredMaxLayoutWidth = w * 0.82
        hint.position = CGPoint(x: w / 2, y: h * 0.33)
        overlay.addChild(hint)

        if best > 0 {
            let bestLabel = makeLabel(Strings.best(best), fontSize: 18, color: Palette.ink)
            bestLabel.position = CGPoint(x: w / 2, y: h * 0.27)
            overlay.addChild(bestLabel)
        }

        playerBody.removeAction(forKey: "idle")
        playerBody.position = .zero
        playerBody.run(.repeatForever(.sequence([.moveBy(x: 0, y: 8, duration: 0.4),
                                                 .moveBy(x: 0, y: -8, duration: 0.4)])),
                       withKey: "idle")
        startIdleFlap()
    }

    private func showGameOver(isNewBest: Bool) {
        overlay.removeAllChildren()
        let w = size.width
        let h = size.height

        let panel = SKShapeNode(rectOf: CGSize(width: min(w * 0.82, 340), height: 260), cornerRadius: 26)
        panel.fillColor = UIColor.white.withAlphaComponent(0.94)
        panel.strokeColor = UIColor.white
        panel.lineWidth = 3
        panel.position = CGPoint(x: w / 2, y: h * 0.58)
        overlay.addChild(panel)

        let title = makeLabel(Strings.gameOver, fontSize: 30, color: Palette.ink)
        title.position = CGPoint(x: 0, y: 92)
        panel.addChild(title)

        let scoreText = makeLabel("\(score)", fontSize: 64, color: Palette.accent)
        scoreText.position = CGPoint(x: 0, y: 32)
        panel.addChild(scoreText)

        let coinRow = SKNode()
        coinRow.position = CGPoint(x: 0, y: -22)
        let icon = SKSpriteNode(texture: coinTexture)
        icon.size = CGSize(width: 24, height: 24)
        icon.position = CGPoint(x: -34, y: 0)
        coinRow.addChild(icon)
        let coinText = makeLabel("+\(runCoins)", fontSize: 22, color: Palette.gold.darker(by: 0.1))
        coinText.horizontalAlignmentMode = .left
        coinText.position = CGPoint(x: -16, y: 0)
        coinRow.addChild(coinText)
        panel.addChild(coinRow)

        let bestText = makeLabel(isNewBest ? Strings.newBest : Strings.best(best),
                                 fontSize: 18,
                                 color: isNewBest ? Palette.danger : Palette.ink)
        bestText.position = CGPoint(x: 0, y: -60)
        panel.addChild(bestText)

        let retry = makeLabel(Strings.tapToRetry, fontSize: 18, color: Palette.ink.withAlphaComponent(0.7))
        retry.position = CGPoint(x: 0, y: -100)
        retry.alpha = 0
        retry.run(.sequence([.wait(forDuration: 0.7),
                             .repeatForever(.sequence([.fadeAlpha(to: 1.0, duration: 0.5),
                                                       .fadeAlpha(to: 0.35, duration: 0.5)]))]))
        panel.addChild(retry)

        panel.setScale(0.7)
        panel.alpha = 0
        panel.run(.sequence([.wait(forDuration: 0.25),
                             .group([.fadeIn(withDuration: 0.2), .scale(to: 1.0, duration: 0.2)])]))
    }

    // MARK: Run control

    private func resetRun() {
        for pair in pillars { pair.node.removeFromParent() }
        for monster in monsters { monster.node.removeFromParent() }
        for coin in coins { coin.removeFromParent() }
        for bullet in bullets { bullet.removeFromParent() }
        pillars.removeAll()
        monsters.removeAll()
        coins.removeAll()
        bullets.removeAll()
        score = 0
        runCoins = 0
        setScore(0)
        velocityY = 0
        world.removeAllActions()
        world.position = .zero
        player.removeAllActions()
        player.zRotation = 0
        player.position = CGPoint(x: size.width * 0.3, y: size.height * 0.55)
        playerBody.colorBlendFactor = 0
        distanceToNextSpawn = size.width * 0.7
        updateShadow()
    }

    private func startRun() {
        overlay.removeAllChildren()
        playerBody.removeAction(forKey: "idle")
        playerBody.position = .zero
        scoreLabel.isHidden = false
        scoreShadow.isHidden = false
        state = .playing
    }

    private func setScore(_ value: Int) {
        scoreLabel.text = "\(value)"
        scoreShadow.text = "\(value)"
    }

    private func updateCoinLabel() {
        coinLabel.text = state == .ready ? "\(totalCoins)" : "\(runCoins)"
    }

    // MARK: Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self)
            let isFireSide = location.x > size.width * 0.55
            switch state {
            case .ready:
                startRun()
                updateCoinLabel()
                flap()
            case .playing:
                if isFireSide { fire() } else { flap() }
            case .over:
                guard lastUpdate >= canRestartAt else { return }
                resetRun()
                state = .ready
                showReady()
                return
            }
        }
    }

    private func flap() {
        velocityY = flapVelocity
        lightImpact.impactOccurred()
        puff(at: CGPoint(x: player.position.x - playerSize * 0.45, y: player.position.y - playerSize * 0.2), count: 3)
        playerBody.removeAction(forKey: "squash")
        playerBody.run(.sequence([.scaleX(to: 0.88, y: 1.12, duration: 0.06),
                                  .scale(to: 1.0, duration: 0.12)]),
                       withKey: "squash")
        wing.removeAction(forKey: "flap")
        wing.run(.sequence([.rotate(toAngle: 1.0, duration: 0.05, shortestUnitArc: true),
                            .rotate(toAngle: -0.5, duration: 0.10, shortestUnitArc: true),
                            .rotate(toAngle: 0, duration: 0.10, shortestUnitArc: true),
                            .run { [weak self] in self?.startIdleFlap() }]),
                 withKey: "flap")
    }

    private func startIdleFlap() {
        wing.removeAction(forKey: "flap")
        wing.run(.repeatForever(.sequence([.rotate(toAngle: 0.45, duration: 0.14, shortestUnitArc: true),
                                           .rotate(toAngle: -0.25, duration: 0.14, shortestUnitArc: true)])),
                 withKey: "flap")
    }

    private func fire() {
        guard lastUpdate >= nextFireAt else { return }
        nextFireAt = lastUpdate + 0.22
        rigidImpact.impactOccurred(intensity: 0.6)

        let bullet = SKSpriteNode(texture: bulletTexture)
        bullet.size = CGSize(width: bulletSize, height: bulletSize)
        bullet.position = CGPoint(x: player.position.x + playerSize * 0.5, y: player.position.y)
        bullet.zPosition = 28
        bullet.blendMode = .add
        bullet.run(.repeatForever(.sequence([.scale(to: 1.2, duration: 0.08), .scale(to: 0.9, duration: 0.08)])))
        world.addChild(bullet)
        bullets.append(bullet)

        fireButton.removeAction(forKey: "press")
        fireButton.run(.sequence([.scale(to: 0.88, duration: 0.05), .scale(to: 1.0, duration: 0.1)]), withKey: "press")
        player.run(.sequence([.moveBy(x: -3, y: 0, duration: 0.04), .moveBy(x: 3, y: 0, duration: 0.08)]))
    }

    // MARK: Events

    private func crash() {
        state = .over
        notify.notificationOccurred(.error)
        playerBody.color = Palette.danger
        playerBody.colorBlendFactor = 0.45
        wing.removeAction(forKey: "flap")

        let isNewBest = score > best
        if isNewBest { best = score }
        canRestartAt = lastUpdate + 0.8

        let flash = SKSpriteNode(color: .white, size: size)
        flash.position = CGPoint(x: size.width / 2, y: size.height / 2)
        flash.alpha = 0.75
        overlay.addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))

        world.run(.sequence([.moveBy(x: 10, y: -6, duration: 0.04),
                             .moveBy(x: -20, y: 10, duration: 0.04),
                             .moveBy(x: 14, y: -6, duration: 0.04),
                             .moveBy(x: -4, y: 2, duration: 0.04)]))

        let floorY = groundTop + playerSize / 2 - 4
        let fallDistance = max(player.position.y - floorY, 0)
        player.run(.group([
            .rotate(toAngle: -CGFloat.pi / 2, duration: 0.25, shortestUnitArc: true),
            .moveTo(y: floorY, duration: TimeInterval(min(0.6, 0.15 + fallDistance / 900)))
        ]))
        showGameOver(isNewBest: isNewBest)
    }

    private func addPoints(_ amount: Int) {
        score += amount
        setScore(score)
        for label in [scoreLabel, scoreShadow] {
            label.removeAction(forKey: "pulse")
            label.setScale(1.0)
            label.run(.sequence([.scale(to: 1.25, duration: 0.07), .scale(to: 1.0, duration: 0.12)]), withKey: "pulse")
        }
    }

    private func collect(_ coin: SKSpriteNode) {
        runCoins += 1
        totalCoins += 1
        updateCoinLabel()
        lightImpact.impactOccurred(intensity: 0.5)
        let target = convert(coinIcon.position, from: hud)
        let local = world.convert(target, from: self)
        coin.removeAllActions()
        coin.run(.sequence([
            .group([.move(to: local, duration: 0.35), .scale(to: 0.6, duration: 0.35)]),
            .removeFromParent()
        ]))
        coinIcon.removeAction(forKey: "pulse")
        coinIcon.setScale(1.0)
        coinIcon.run(.sequence([.wait(forDuration: 0.3), .scale(to: 1.3, duration: 0.07), .scale(to: 1.0, duration: 0.12)]),
                     withKey: "pulse")
    }

    private func kill(_ monster: Monster) {
        monster.dead = true
        rigidImpact.impactOccurred()
        addPoints(1)
        burst(at: monster.node.position, count: 10)
        monster.node.removeAllActions()
        monster.node.run(.sequence([
            .group([.scale(to: 1.5, duration: 0.15), .fadeOut(withDuration: 0.15)]),
            .removeFromParent()
        ]))
        // Drop a coin where the monster was
        spawnCoin(at: monster.node.position)
    }

    private func puff(at point: CGPoint, count: Int) {
        for _ in 0..<count {
            let particle = SKSpriteNode(texture: dotTexture)
            let side = CGFloat.random(in: 6...11)
            particle.size = CGSize(width: side, height: side)
            particle.alpha = 0.85
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

    private func burst(at point: CGPoint, count: Int) {
        for index in 0..<count {
            let star = SKSpriteNode(texture: starTexture)
            let side = CGFloat.random(in: 12...20)
            star.size = CGSize(width: side, height: side)
            star.position = point
            star.zPosition = 31
            world.addChild(star)
            let angle = CGFloat(index) / CGFloat(count) * 2 * CGFloat.pi + CGFloat.random(in: -0.2...0.2)
            let distance = CGFloat.random(in: 30...60)
            star.run(.sequence([
                .group([.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.4),
                        .rotate(byAngle: CGFloat.pi, duration: 0.4),
                        .fadeOut(withDuration: 0.4)]),
                .removeFromParent()
            ]))
        }
    }

    // MARK: Spawning

    private func spawnPillars() {
        let h = size.height
        let gapHeight = max(h * 0.21, h * 0.27 - CGFloat(score) * h * 0.002)
        let ceilingMargin = h * 0.10
        let floorMargin = groundTop + h * 0.08
        let minCenter = floorMargin + gapHeight / 2
        let maxCenter = h - ceilingMargin - gapHeight / 2
        let center = CGFloat.random(in: minCenter...max(minCenter, maxCenter))
        let gapBottom = center - gapHeight / 2
        let gapTop = center + gapHeight / 2

        let style = Int.random(in: 0..<Palette.pillars.count)
        let pair = SKNode()
        let x = size.width + pillarWidth
        pair.position = CGPoint(x: x, y: 0)
        pair.zPosition = 10

        // Bottom pillar body + cap
        let bottomBody = SKSpriteNode(texture: pillarBodies[style])
        bottomBody.size = CGSize(width: pillarWidth, height: gapBottom + 20)
        bottomBody.position = CGPoint(x: 0, y: (gapBottom - 20) / 2)
        pair.addChild(bottomBody)
        let bottomCap = SKSpriteNode(texture: pillarCaps[style])
        bottomCap.size = CGSize(width: pillarWidth + 14, height: capHeight)
        bottomCap.position = CGPoint(x: 0, y: gapBottom - capHeight / 2)
        pair.addChild(bottomCap)

        // Top pillar body + cap
        let topHeight = h - gapTop + 20
        let topBody = SKSpriteNode(texture: pillarBodies[style])
        topBody.size = CGSize(width: pillarWidth, height: topHeight)
        topBody.position = CGPoint(x: 0, y: gapTop + topHeight / 2)
        pair.addChild(topBody)
        let topCap = SKSpriteNode(texture: pillarCaps[style])
        topCap.size = CGSize(width: pillarWidth + 14, height: capHeight)
        topCap.position = CGPoint(x: 0, y: gapTop + capHeight / 2)
        topCap.yScale = -1
        pair.addChild(topCap)

        world.addChild(pair)
        pillars.append(PillarPair(node: pair, halfWidth: (pillarWidth + 14) / 2, gapBottom: gapBottom, gapTop: gapTop))

        // A coin in every gap
        spawnCoin(at: CGPoint(x: x, y: center))

        // Between this pillar and the next: a monster or a small coin arc
        let midX = x + pillarSpacing / 2
        let monsterChance = min(0.30 + CGFloat(score) * 0.03, 0.75)
        if score >= 1 && CGFloat.random(in: 0...1) < monsterChance {
            spawnMonster(atX: midX)
        } else if CGFloat.random(in: 0...1) < 0.5 {
            let arcCenter = CGFloat.random(in: floorMargin + 60...(h - ceilingMargin - 60))
            for index in -1...1 {
                spawnCoin(at: CGPoint(x: midX + CGFloat(index) * 38, y: arcCenter + (index == 0 ? 22 : 0)))
            }
        }
    }

    private func spawnCoin(at point: CGPoint) {
        let coin = SKSpriteNode(texture: coinTexture)
        coin.size = CGSize(width: coinSize, height: coinSize)
        coin.position = point
        coin.zPosition = 25
        coin.run(.repeatForever(.sequence([.scaleX(to: 0.25, duration: 0.35), .scaleX(to: 1.0, duration: 0.35)])))
        world.addChild(coin)
        coins.append(coin)
    }

    private func spawnMonster(atX x: CGFloat) {
        let h = size.height
        let low = groundTop + h * 0.12
        let high = h * 0.86
        let baseY = CGFloat.random(in: low...max(low, high))
        let node = SKSpriteNode(texture: monsterTexture)
        node.size = CGSize(width: monsterSize, height: monsterSize)
        node.position = CGPoint(x: x, y: baseY)
        node.zPosition = 26
        node.run(.repeatForever(.sequence([.scaleX(to: 1.08, y: 0.94, duration: 0.25),
                                           .scaleX(to: 0.95, y: 1.06, duration: 0.25)])))
        world.addChild(node)
        let amplitude = CGFloat.random(in: h * 0.04...h * 0.10)
        monsters.append(Monster(node: node, baseY: baseY, amplitude: amplitude,
                                phase: CGFloat.random(in: 0...(2 * CGFloat.pi))))
    }

    // MARK: Update loop

    override func update(_ currentTime: TimeInterval) {
        let rawDelta = lastUpdate == 0 ? 1.0 / 60.0 : currentTime - lastUpdate
        let dt = CGFloat(min(max(rawDelta, 0), 1.0 / 30.0))
        lastUpdate = currentTime
        guard builtSize != .zero else { return }

        moveClouds(dt)
        if state != .over {
            scrollLayers(dt)
        }
        if state == .playing {
            stepPlaying(dt)
        }
        updateShadow()
    }

    private func moveClouds(_ dt: CGFloat) {
        let w = size.width
        let drift = (state == .playing ? scrollSpeed * 0.06 : 10) * dt
        for cloud in clouds {
            cloud.position.x -= drift
            if cloud.position.x < -cloud.size.width {
                cloud.position.x = w + cloud.size.width
                cloud.position.y = CGFloat.random(in: size.height * 0.50...size.height * 0.90)
            }
        }
    }

    private func scrollLayers(_ dt: CGFloat) {
        for layer in layers {
            let dx = scrollSpeed * layer.factor * dt
            for sprite in layer.sprites {
                sprite.position.x -= dx
                if sprite.position.x <= -layer.width {
                    sprite.position.x += layer.width * 2
                }
            }
        }
    }

    private func updateShadow() {
        let height = max(player.position.y - groundTop, 0)
        let t = min(height / (size.height * 0.7), 1)
        shadow.position = CGPoint(x: player.position.x, y: groundTop + 2)
        shadow.setScale(1.0 - 0.6 * t)
        shadow.alpha = 1.0 - 0.7 * t
    }

    private func stepPlaying(_ dt: CGFloat) {
        let h = size.height
        let w = size.width

        // Player vertical motion
        velocityY = max(velocityY + gravity * dt, -maxFallSpeed)
        player.position.y += velocityY * dt
        let ceilingY = h - playerSize / 2
        if player.position.y > ceilingY {
            player.position.y = ceilingY
            velocityY = min(velocityY, 0)
        }
        let targetAngle = max(min(velocityY / flapVelocity * 0.45, 0.45), -1.1)
        player.zRotation += (targetAngle - player.zRotation) * min(1, dt * 10)

        if player.position.y - playerSize / 2 <= groundTop {
            player.position.y = groundTop + playerSize / 2
            crash()
            return
        }

        let dx = scrollSpeed * dt
        let playerPoint = player.position
        let playerRadius = playerSize / 2 - 5

        // Pillars
        for pair in pillars {
            pair.node.position.x -= dx
            if !pair.scored && pair.maxX < playerPoint.x - playerRadius {
                pair.scored = true
                addPoints(1)
            }
            if pair.blocks(playerPoint, radius: playerRadius) {
                crash()
                return
            }
        }

        // Coins
        for coin in coins {
            coin.position.x -= dx
        }
        var collected: [SKSpriteNode] = []
        for coin in coins where hypot(coin.position.x - playerPoint.x, coin.position.y - playerPoint.y) < playerRadius + coinSize * 0.45 {
            collected.append(coin)
        }
        for coin in collected {
            coins.removeAll { $0 === coin }
            collect(coin)
        }

        // Monsters
        for monster in monsters where !monster.dead {
            monster.phase += dt * 2.6
            monster.node.position.x -= dx
            monster.node.position.y = monster.baseY + sin(monster.phase) * monster.amplitude
            let distance = hypot(monster.node.position.x - playerPoint.x, monster.node.position.y - playerPoint.y)
            if distance < playerRadius + monsterSize * 0.38 {
                crash()
                return
            }
        }

        // Bullets
        var spentBullets: [SKSpriteNode] = []
        for bullet in bullets {
            bullet.position.x += bulletSpeed * dt
            if bullet.position.x > w + 30 {
                spentBullets.append(bullet)
                continue
            }
            if pillars.contains(where: { $0.blocks(bullet.position, radius: 5) }) {
                puff(at: bullet.position, count: 3)
                spentBullets.append(bullet)
                continue
            }
            if let target = monsters.first(where: { !$0.dead &&
                hypot($0.node.position.x - bullet.position.x, $0.node.position.y - bullet.position.y) < monsterSize * 0.45 }) {
                kill(target)
                spentBullets.append(bullet)
            }
        }
        for bullet in spentBullets {
            bullet.removeFromParent()
            bullets.removeAll { $0 === bullet }
        }

        // Clean up off-screen things
        pillars.removeAll { pair in
            guard pair.maxX < -20 else { return false }
            pair.node.removeFromParent()
            return true
        }
        monsters.removeAll { monster in
            guard monster.dead || monster.node.position.x < -monsterSize else { return false }
            if !monster.dead { monster.node.removeFromParent() }
            return true
        }
        coins.removeAll { coin in
            guard coin.position.x < -coinSize else { return false }
            coin.removeFromParent()
            return true
        }

        // Spawn new pillars
        distanceToNextSpawn -= dx
        if distanceToNextSpawn <= 0 {
            spawnPillars()
            distanceToNextSpawn = pillarSpacing
        }
    }
}

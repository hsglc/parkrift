import SwiftUI
import SceneKit

// MARK: - 3D showroom

/// Studio scene for the garage: the chosen car turning on a lit platform with a neon ring,
/// glossy floor reflections and studio lights, like the car select screens of racing games.
final class GarageStage {
    static let shared = GarageStage()

    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let turntable = SCNNode()
    private let ringMaterial = SCNMaterial()
    private let floorGlow = SCNMaterial()
    /// All three cars stay in the scene (inactive ones shrunk to nothing), so switching never
    /// builds geometry or compiles shaders.
    private var cars: [CarModelID: Car3D] = [:]
    private var shown: CarChoice?
    /// Studio lights with their normal intensities (dimmed for the unlock reveal).
    private var studioLights: [(SCNLight, CGFloat)] = []
    private static let cameraHome = SCNVector3(-0.6, 1.9, 9.6)
    private static let cameraHomeTarget = SCNVector3(1.9, 0.45, 0)
    private var revealNodes: [SCNNode] = []
    private var revealing = false
    /// Extra yaw from dragging, added to the slow automatic turn.
    private var dragYaw: Float = 0
    weak var view: SCNView?

    private init() {
        scene.background.contents = GarageStage.backdrop()
        scene.lightingEnvironment.contents = GarageStage.studioEnvironment()
        scene.lightingEnvironment.intensity = 0.9

        // Dark satin floor (a reflective SCNFloor drew the whole scene twice)
        let floor = SCNFloor()
        floor.reflectivity = 0
        let floorMaterial = Mat.pbr(UIColor(red: 0.05, green: 0.055, blue: 0.07, alpha: 1), metal: 0, rough: 0.9)
        floor.materials = [floorMaterial]
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        // Platform with a glowing ring
        let platform = SCNCylinder(radius: 3.3, height: 0.1)
        platform.radialSegmentCount = 96
        platform.materials = [Mat.pbr(UIColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1), metal: 0.7, rough: 0.3)]
        let platformNode = SCNNode(geometry: platform)
        platformNode.position.y = 0.05
        turntable.addChildNode(platformNode)
        let ring = SCNTube(innerRadius: 3.31, outerRadius: 3.34, height: 0.06)
        ring.radialSegmentCount = 96
        ringMaterial.lightingModel = .constant
        ringMaterial.diffuse.contents = UIColor.black
        ringMaterial.emission.contents = UIColor.cyan
        ring.materials = [ringMaterial]
        let ringNode = SCNNode(geometry: ring)
        ringNode.position.y = 0.055
        scene.rootNode.addChildNode(ringNode)
        // Soft colored light pool on the floor around the platform
        let pool = SCNPlane(width: 9.5, height: 9.5)
        floorGlow.lightingModel = .constant
        floorGlow.diffuse.contents = CarArt.glowParticle()
        floorGlow.multiply.contents = UIColor.cyan
        floorGlow.blendMode = .add
        floorGlow.writesToDepthBuffer = false
        pool.materials = [floorGlow]
        let poolNode = SCNNode(geometry: pool)
        poolNode.eulerAngles.x = -Float.pi / 2
        poolNode.position.y = 0.012
        poolNode.opacity = 0.35
        scene.rootNode.addChildNode(poolNode)
        turntable.position.y = 0
        scene.rootNode.addChildNode(turntable)
        // Soft shadow under the car instead of a shadow-casting light
        let shadow = SCNPlane(width: 5.6, height: 2.8)
        let shadowMaterial = SCNMaterial()
        shadowMaterial.lightingModel = .constant
        shadowMaterial.diffuse.contents = CityArt.blobShadow
        shadowMaterial.writesToDepthBuffer = false
        shadow.materials = [shadowMaterial]
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.eulerAngles.x = -Float.pi / 2
        shadowNode.position.y = 0.105
        turntable.addChildNode(shadowNode)
        let saved = CarChoice.saved
        for id in CarModelID.allCases {
            let car = Car3D(color: saved.color, style: .racer, model: id, textures: id == saved.model)
            car.update(position: .zero, heading: 0, steer: 0)
            car.node.position = SCNVector3(0, 0.1, 0)
            car.node.eulerAngles.y = 0
            car.node.scale = SCNVector3(0.001, 0.001, 0.001)
            turntable.addChildNode(car.node)
            cars[id] = car
            // Only the car on the platform holds its 4K textures
            car.setTexturesLoaded(id == saved.model)
        }

        // Lights: soft key from the front left with shadows, cool and warm rims behind, fill
        let key = SCNLight()
        key.type = .spot
        key.intensity = 1100
        key.spotInnerAngle = 30
        key.spotOuterAngle = 70
        key.castsShadow = false
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-4, 9, 7)
        keyNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(keyNode)
        studioLights.append((key, key.intensity))
        for (position, color, intensity) in [(SCNVector3(-6, 3, -6), UIColor(red: 0.35, green: 0.6, blue: 1.0, alpha: 1), CGFloat(600)),
                                             (SCNVector3(6, 2.5, -5), UIColor(red: 1.0, green: 0.55, blue: 0.3, alpha: 1), CGFloat(450)),
                                             (SCNVector3(5, 4, 6), UIColor.white, CGFloat(250))] {
            let light = SCNLight()
            light.type = .omni
            light.color = color
            light.intensity = intensity
            light.attenuationStartDistance = 4
            light.attenuationEndDistance = 18
            let node = SCNNode()
            node.light = light
            node.position = position
            scene.rootNode.addChildNode(node)
            studioLights.append((light, intensity))
        }
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 120
        studioLights.append((ambient, 120))
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Telephoto camera, aimed right of the car so it sits left of the info panel
        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.5
        camera.zFar = 80
        camera.wantsHDR = true
        camera.bloomIntensity = 0.25
        camera.bloomThreshold = 1.0
        camera.bloomBlurRadius = 8
        camera.exposureOffset = -0.15
        camera.saturation = 1.08
        camera.contrast = 0.1
        camera.vignettingIntensity = 0.6
        camera.vignettingPower = 0.8
        cameraNode.camera = camera
        cameraNode.position = GarageStage.cameraHome
        cameraNode.look(at: GarageStage.cameraHomeTarget)
        scene.rootNode.addChildNode(cameraNode)

        turntable.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 26)), forKey: "spin")
    }

    /// Shows `choice`: a new model swaps in with a short scale/fade, a new paint just repaints.
    func show(_ choice: CarChoice, animated: Bool = true) {
        guard choice != shown, let car = cars[choice.model] else { return }
        let previous = shown
        shown = choice
        let accent = choice.color.lighter(by: 0.15)
        ringMaterial.emission.contents = accent.darker(by: 0.35)
        floorGlow.multiply.contents = accent
        if previous?.model == choice.model {
            car.setPaint(choice.color)
            car.setRim(choice.rimColor)
            return
        }
        let tiny = SCNVector3(0.001, 0.001, 0.001)
        if let previous = previous, let old = cars[previous.model], animated {
            old.node.removeAllActions()
            old.node.runAction(.sequence([.group([.fadeOut(duration: 0.16), .scale(to: 0.9, duration: 0.16)]),
                                          .run { $0.scale = tiny; $0.opacity = 1 }])) {
                DispatchQueue.main.async { [weak self] in
                    // Unless it was picked again meanwhile, it lets its textures go
                    if self?.shown?.model != previous.model { old.setTexturesLoaded(false) }
                }
            }
        } else {
            for (id, other) in cars where id != choice.model {
                other.node.removeAllActions()
                other.node.scale = tiny
                other.setTexturesLoaded(false)
            }
        }
        car.node.removeAllActions()
        guard animated, previous != nil else {
            car.node.opacity = 1
            car.node.scale = SCNVector3(1, 1, 1)
            car.node.position.y = 0.1
            loadTextures(of: choice, on: car)
            return
        }
        // The new car waits out of sight until its textures are decoded, then drops in finished
        car.node.opacity = 0
        car.node.scale = SCNVector3(0.88, 0.88, 0.88)
        car.node.position.y = 0.6
        let started = CACurrentMediaTime()
        loadTextures(of: choice, on: car) {
            let drop = SCNAction.move(to: SCNVector3(0, 0.1, 0), duration: 0.35)
            drop.timingMode = .easeOut
            let grow = SCNAction.scale(to: 1, duration: 0.35)
            grow.timingMode = .easeOut
            let wait = max(0, 0.12 - (CACurrentMediaTime() - started))
            car.node.runAction(.sequence([.wait(duration: wait), .group([.fadeIn(duration: 0.25), drop, grow])]))
        }
    }

    /// The garage screen is open or not: closed, even the shown car lets its textures go, so the
    /// menu and the game never carry the garage's 4K car as well.
    func setActive(_ active: Bool) {
        guard let id = shown?.model, let car = cars[id] else { return }
        if active, let choice = shown {
            loadTextures(of: choice, on: car)
        } else {
            car.setTexturesLoaded(false)
        }
    }

    /// The car's 4K maps are decoded in the background and put on it when ready (until then it
    /// shows for a moment in its plain material), so the garage never freezes to decode them.
    private func loadTextures(of choice: CarChoice, on car: Car3D, ready: (() -> Void)? = nil) {
        car.setPaint(choice.color)
        car.setRim(choice.rimColor)
        CarModels.whenDecoded(CarSpec.of(choice.model)) { [weak self] in
            guard let self = self, self.shown?.model == choice.model, let current = self.shown else { return }
            car.setTexturesLoaded(true)
            car.setPaint(current.color)
            car.setRim(current.rimColor)
            ready?()
        }
    }

    /// Unlock reveal on the stage, staged like a car launch: the studio goes dark and the car
    /// turns to a three-quarter front view as a silhouette with an accent rim light behind it; a
    /// bright light sweeps along its body, picking out the paint; then the lights slam on with a
    /// bloom burst, a shockwave runs out over the floor and embers drift up from the ring, while
    /// the camera, low and close, glides slowly round the car. `finishUnlock` takes it all back.
    func celebrateUnlock(_ choice: CarChoice) {
        guard let car = cars[choice.model], let camera = cameraNode.camera else { return }
        clearReveal()
        revealing = true
        let accent = choice.color.lighter(by: 0.25)
        car.node.removeAllActions()
        car.node.position = SCNVector3(0, 0.1, 0)
        car.node.scale = SCNVector3(1, 1, 1)
        car.node.opacity = 1

        // The turntable stops with the nose towards the camera's right
        turntable.removeAction(forKey: "spin")
        let turn = SCNAction.rotateTo(x: 0, y: -1.0, z: 0, duration: 0.7, usesShortestUnitArc: true)
        turn.timingMode = .easeInEaseOut
        turntable.runAction(turn, forKey: "reveal")

        // Blackout: the car becomes a silhouette
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.25
        for (light, _) in studioLights { light.intensity = light.type == .ambient ? 8 : 20 }
        scene.lightingEnvironment.intensity = 0.06
        ringMaterial.emission.contents = UIColor(white: 0.08, alpha: 1)
        floorGlow.multiply.contents = UIColor.black
        camera.exposureOffset = -0.4
        SCNTransaction.commit()

        // Rim light behind the car, in its colour: an outline against the dark
        let rim = SCNLight()
        rim.type = .omni
        rim.color = accent
        rim.intensity = 0
        rim.attenuationStartDistance = 2
        rim.attenuationEndDistance = 9
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(0.6, 1.6, -3.4)
        scene.rootNode.addChildNode(rimNode)
        revealNodes.append(rimNode)
        rimNode.runAction(.customAction(duration: 0.6) { _, t in rim.intensity = 2200 * t / 0.6 })

        // The light sweep along the body (its reflection runs over the paint)
        let sweep = SCNLight()
        sweep.type = .omni
        sweep.color = UIColor.white
        sweep.intensity = 0
        sweep.attenuationStartDistance = 0.4
        sweep.attenuationEndDistance = 3.4
        let sweepNode = SCNNode()
        sweepNode.light = sweep
        sweepNode.position = SCNVector3(-3.4, 1.3, 2.4)
        scene.rootNode.addChildNode(sweepNode)
        revealNodes.append(sweepNode)
        let across = SCNAction.move(to: SCNVector3(3.4, 1.0, 1.6), duration: 0.95)
        across.timingMode = .easeInEaseOut
        sweepNode.runAction(.sequence([
            .wait(duration: 0.3),
            .group([across, .customAction(duration: 0.95) { _, t in
                sweep.intensity = 3800 * sin(.pi * min(1, t / 0.95))
            }]),
        ]))

        // Camera: low and close at the front three-quarter, then a slow glide round the car
        let target = SCNVector3(-1.9, 0.5, 0)
        let from = SCNVector3(2.4, 0.85, 8.6)
        let to = SCNVector3(-3.0, 1.3, 9.0)
        let startPosition = cameraNode.position
        cameraNode.removeAction(forKey: "unlock")
        let moveIn = SCNAction.customAction(duration: 0.55) { node, t in
            let k = Float(GarageStage.ease(Double(t / 0.55)))
            node.position = GarageStage.mix(startPosition, from, k)
            node.look(at: GarageStage.mix(GarageStage.cameraHomeTarget, target, k))
        }
        let glide = SCNAction.customAction(duration: 5.5) { node, t in
            let k = Float(GarageStage.easeOut(Double(t / 5.5)))
            node.position = GarageStage.mix(from, to, k)
            node.look(at: target)
        }
        cameraNode.runAction(.sequence([moveIn, glide]), forKey: "unlock")
        camera.fieldOfView = 30

        // Ignition: the lights slam on
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self] in
            guard let self = self, self.revealing else { return }
            self.ignite(accent: accent, car: car)
        }
    }

    private func ignite(accent: UIColor, car: Car3D) {
        guard let camera = cameraNode.camera else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.18
        for (light, intensity) in studioLights { light.intensity = intensity * 1.25 }
        scene.lightingEnvironment.intensity = 1.1
        ringMaterial.emission.contents = UIColor.white
        floorGlow.multiply.contents = accent
        camera.exposureOffset = 0.25
        camera.bloomIntensity = 1.4
        SCNTransaction.completionBlock = { [weak self] in
            guard let self = self else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 1.2
            for (light, intensity) in self.studioLights { light.intensity = intensity }
            self.scene.lightingEnvironment.intensity = 0.9
            self.ringMaterial.emission.contents = accent.darker(by: 0.35)
            camera.exposureOffset = -0.15
            camera.bloomIntensity = 0.45
            SCNTransaction.commit()
        }
        SCNTransaction.commit()

        // Shockwave over the floor
        let wave = SCNPlane(width: 2, height: 2)
        let waveMaterial = SCNMaterial()
        waveMaterial.lightingModel = .constant
        waveMaterial.diffuse.contents = GarageStage.shockRing
        waveMaterial.multiply.contents = accent.lighter(by: 0.3)
        waveMaterial.blendMode = .add
        waveMaterial.writesToDepthBuffer = false
        wave.materials = [waveMaterial]
        let waveNode = SCNNode(geometry: wave)
        waveNode.eulerAngles.x = -Float.pi / 2
        waveNode.position.y = 0.13
        waveNode.scale = SCNVector3(3.0, 3.0, 3.0)
        scene.rootNode.addChildNode(waveNode)
        let grow = SCNAction.scale(to: 9, duration: 0.9)
        grow.timingMode = .easeOut
        waveNode.runAction(.sequence([.group([grow, .fadeOut(duration: 0.9)]), .removeFromParentNode()]))

        // Embers rising slowly from the ring
        let embers = SCNParticleSystem()
        embers.particleImage = CarArt.glowParticle()
        embers.birthRate = 260
        embers.emissionDuration = 1.8
        embers.loops = false
        embers.particleLifeSpan = 2.2
        embers.particleLifeSpanVariation = 0.8
        embers.particleSize = 0.05
        embers.particleSizeVariation = 0.03
        embers.particleVelocity = 0.9
        embers.particleVelocityVariation = 0.6
        embers.emittingDirection = SCNVector3(0, 1, 0)
        embers.spreadingAngle = 12
        embers.acceleration = SCNVector3(0, 0.25, 0)
        embers.particleColor = accent.lighter(by: 0.35)
        embers.particleColorVariation = SCNVector4(0.03, 0.1, 0.25, 0)
        embers.blendMode = .additive
        embers.emitterShape = SCNTube(innerRadius: 3.2, outerRadius: 3.4, height: 0.05)
        embers.birthLocation = .surface
        let fade = CAKeyframeAnimation()
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.15, 0.6, 1]
        let controller = SCNParticlePropertyController(animation: fade)
        embers.propertyControllers = [.opacity: controller]
        let emitter = SCNNode()
        emitter.position = SCNVector3(0, 0.12, 0)
        emitter.addParticleSystem(embers)
        scene.rootNode.addChildNode(emitter)
        revealNodes.append(emitter)

        // The car settles on its springs as the lights hit
        let dip = SCNAction.move(to: SCNVector3(0, 0.06, 0), duration: 0.1)
        dip.timingMode = .easeOut
        let rise = SCNAction.move(to: SCNVector3(0, 0.1, 0), duration: 0.45)
        rise.timingMode = .easeInEaseOut
        car.node.runAction(.sequence([dip, rise]))

        // The sweep and rim fade away; the studio light carries on
        for node in revealNodes where node.light != nil {
            let light = node.light!
            let startIntensity = light.intensity
            node.runAction(.customAction(duration: 0.8) { _, t in light.intensity = startIntensity * (1 - t / 0.8) })
        }
    }

    /// Back to the normal showroom after the reveal: camera home, the turntable turning again.
    func finishUnlock() {
        guard revealing else { return }
        revealing = false
        let start = cameraNode.position
        let startTarget = SCNVector3(-1.9, 0.5, 0)
        cameraNode.removeAction(forKey: "unlock")
        cameraNode.runAction(.customAction(duration: 0.8) { node, t in
            let k = Float(GarageStage.ease(Double(t / 0.8)))
            node.position = GarageStage.mix(start, GarageStage.cameraHome, k)
            node.look(at: GarageStage.mix(startTarget, GarageStage.cameraHomeTarget, k))
        }, forKey: "unlock")
        turntable.removeAction(forKey: "reveal")
        turntable.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 26)), forKey: "spin")
        let nodes = revealNodes
        revealNodes = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { nodes.forEach { $0.removeFromParentNode() } }
        if let shown = shown {
            let accent = shown.color.lighter(by: 0.15)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            for (light, intensity) in studioLights { light.intensity = intensity }
            scene.lightingEnvironment.intensity = 0.9
            ringMaterial.emission.contents = accent.darker(by: 0.35)
            floorGlow.multiply.contents = accent
            cameraNode.camera?.exposureOffset = -0.15
            cameraNode.camera?.bloomIntensity = 0.25
            SCNTransaction.commit()
        }
    }

    private func clearReveal() {
        revealNodes.forEach { $0.removeFromParentNode() }
        revealNodes = []
    }

    private static func mix(_ a: SCNVector3, _ b: SCNVector3, _ k: Float) -> SCNVector3 {
        SCNVector3(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k, a.z + (b.z - a.z) * k)
    }

    private static func ease(_ t: Double) -> Double {
        let x = max(0, min(1, t))
        return x * x * (3 - 2 * x)
    }

    private static func easeOut(_ t: Double) -> Double {
        let x = max(0, min(1, t))
        return 1 - pow(1 - x, 3)
    }

    /// A soft bright ring (the floor shockwave).
    private static let shockRing: UIImage = {
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let center = CGPoint(x: 128, y: 128)
            let colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor(white: 1, alpha: 0.9).cgColor,
                          UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.72, 0.9, 1.0]) {
                cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 127, options: [])
            }
        }
    }()

    private var warmed = false

    /// Draws every car once at full size while the garage view is still hidden, so each car's
    /// meshes and textures are on the GPU before it is first shown (a car scaled to nothing is not
    /// really drawn, so the first look at each one used to stall). Runs once per app launch.
    func warmCars(then done: @escaping () -> Void) {
        guard !warmed else { done(); return }
        warmed = true
        let ids = CarModelID.allCases
        let tiny = SCNVector3(0.001, 0.001, 0.001)
        var index = 0
        func step() {
            guard index < ids.count else {
                let current = shown?.model
                for (id, car) in cars {
                    car.node.scale = id == current ? SCNVector3(1, 1, 1) : tiny
                    car.node.opacity = 1
                }
                done()
                return
            }
            let id = ids[index]
            for (other, car) in cars { car.node.scale = other == id ? SCNVector3(1, 1, 1) : tiny }
            index += 1
            // A few frames each (the view renders continuously)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { step() }
        }
        step()
    }

    /// Builds the stage and compiles its shaders ahead of time (called from the menu), so the
    /// first visit to the garage does not freeze.
    static func prewarm(using renderer: SCNSceneRenderer?, done: (() -> Void)? = nil) {
        let stage = shared
        guard let renderer = renderer else { done?(); return }
        renderer.prepare([stage.scene]) { _ in DispatchQueue.main.async { done?() } }
    }

    /// Turns the platform by a drag (radians).
    func drag(by yaw: Float) {
        turntable.eulerAngles.y += yaw
    }

    func pauseSpin(_ paused: Bool) {
        turntable.action(forKey: "spin")?.speed = paused ? 0 : 1
    }

    /// Benchmark helper.
    func saveSnapshot(named name: String) {
        guard let image = view?.snapshot(), let data = image.pngData(),
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? data.write(to: folder.appendingPathComponent(name + ".png"))
    }

    /// Dark studio wall with a soft light falloff behind the car.
    private static func backdrop() -> UIImage {
        CarArt.image(CGSize(width: 64, height: 256), scale: 1) { context, size in
            let colors = [UIColor(red: 0.10, green: 0.12, blue: 0.17, alpha: 1).cgColor,
                          UIColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1).cgColor,
                          UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height * 0.45), end: CGPoint(x: 0, y: 0), options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
            }
        }
    }

    /// Equirectangular studio for reflections: dark room with long softbox strips.
    private static func studioEnvironment() -> UIImage {
        CarArt.image(CGSize(width: 512, height: 256), scale: 1) { context, size in
            context.setFillColor(UIColor(red: 0.04, green: 0.045, blue: 0.06, alpha: 1).cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            // Overhead softboxes
            for (x, width) in [(40.0, 120.0), (220.0, 90.0), (360.0, 120.0)] as [(CGFloat, CGFloat)] {
                context.setFillColor(UIColor(white: 1, alpha: 0.95).cgColor)
                context.fill(CGRect(x: x, y: 26, width: width, height: 16))
                context.setFillColor(UIColor(white: 1, alpha: 0.35).cgColor)
                context.fill(CGRect(x: x - 6, y: 20, width: width + 12, height: 28))
            }
            // Horizon light strips (cool and warm)
            context.setFillColor(UIColor(red: 0.5, green: 0.75, blue: 1.0, alpha: 0.6).cgColor)
            context.fill(CGRect(x: 0, y: 112, width: size.width * 0.45, height: 8))
            context.setFillColor(UIColor(red: 1.0, green: 0.7, blue: 0.45, alpha: 0.5).cgColor)
            context.fill(CGRect(x: size.width * 0.55, y: 114, width: size.width * 0.45, height: 6))
            // Floor bounce
            context.setFillColor(UIColor(white: 0.12, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: size.height * 0.62, width: size.width, height: size.height * 0.38))
        }
    }
}

struct GarageSceneView: UIViewRepresentable {
    let stage: GarageStage

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = stage.scene
        view.pointOfView = stage.cameraNode
        view.antialiasingMode = .multisampling2X
        view.contentScaleFactor = min(UIScreen.main.scale, 2)
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isPlaying = true
        view.backgroundColor = .black
        stage.view = view
        // Hidden until its shaders are compiled, then faded in (no frozen first frames)
        view.alpha = 0
        view.prepare([stage.scene]) { [stage] _ in
            DispatchQueue.main.async {
                stage.warmCars {
                    UIView.animate(withDuration: 0.3) { view.alpha = 1 }
                }
            }
        }
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(stage: stage) }

    final class Coordinator: NSObject {
        let stage: GarageStage
        private var last: CGFloat = 0

        init(stage: GarageStage) { self.stage = stage }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            let x = gesture.translation(in: gesture.view).x
            switch gesture.state {
            case .began:
                last = 0
                stage.pauseSpin(true)
            case .changed:
                stage.drag(by: Float(x - last) * 0.012)
                last = x
            default:
                stage.pauseSpin(false)
            }
        }
    }
}

// MARK: - Garage screen

struct GarageView: View {
    @EnvironmentObject var model: AppModel
    @State private var choice = CarChoice.saved
    @State private var statsShown = false
    @State private var showUpgrades = false
    /// The car just bought, while its reveal is on screen.
    @State private var unlocked: CarSpec?
    private let stage = GarageStage.shared

    private var spec: CarSpec { choice.spec }
    /// The bars with this car's upgrades in (the driving model uses the same numbers).
    private var ratings: CarStats { CarPerformance.ratings(spec, upgrades: Progression.upgrades(for: choice.model)) }
    private var isPlay: Bool {
        if case .play = model.garageExit { return true }
        return false
    }
    private var accent: Color { Color(choice.color.lighter(by: 0.2)) }

    private var modeLabel: String {
        switch model.garageExit {
        case .lobby: return Strings.modeOnlineTitle
        case .menu: return Strings.yourCar
        case .play(let level):
            if Levels.isRace(level) { return Strings.carRace }
            if Levels.isCity(level) { return Strings.parkRace }
            return Levels.title(level)
        }
    }

    var body: some View {
        ZStack {
            GarageSceneView(stage: stage)
                .ignoresSafeArea()
            // A soft shade on the right, where the details sit, and along the bottom
            LinearGradient(colors: [.clear, .clear, Palette.carbon.opacity(0.82)], startPoint: .leading, endPoint: .trailing)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            LinearGradient(colors: [.clear, Palette.carbon.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            HStack(alignment: .top, spacing: 0) {
                leftColumn
                Spacer(minLength: 16)
                infoPanel
                    .frame(width: 290)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .opacity(unlocked == nil ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: unlocked == nil)

            if let spec = unlocked {
                UnlockReveal(spec: spec, accent: accent) {
                    stage.finishUnlock()
                    withAnimation(.easeOut(duration: 0.3)) { unlocked = nil }
                }
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .sheet(isPresented: $showUpgrades) { UpgradeView(choice: $choice).environmentObject(model) }
        .onAppear {
            choice = model.carChoice
            stage.setActive(true)
            stage.show(choice, animated: false)
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) { statsShown = true }
            #if BENCHMARK
            // Test hook: the unlock reveal on the shown car
            if ProcessInfo.processInfo.arguments.contains("-unlocktest") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    stage.celebrateUnlock(choice)
                    withAnimation(.easeOut(duration: 0.25)) { unlocked = choice.spec }
                    // Frames of the reveal, saved by the app itself
                    for at in [0.6, 1.0, 1.5, 2.2, 3.2, 4.5, 6.0] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                            saveWindowSnapshot(named: "unlock-\(Int(at * 10))")
                        }
                    }
                }
            }
            #endif
        }
        .onDisappear { stage.setActive(false) }
        .onChange(of: choice) { old, new in
            stage.show(new)
            if old.model != new.model {
                statsShown = false
                withAnimation(.easeOut(duration: 0.5).delay(0.05)) { statsShown = true }
            }
        }
    }

    // MARK: Left: title, the car's arrows, the car strip

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                RoundIconButton(systemImage: "chevron.left") {
                    AudioManager.shared.play("click", volume: 0.6)
                    model.leaveGarage(confirmed: false)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(Strings.garage)
                        .font(.race(30))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(.white)
                    Text(modeLabel)
                        .font(.ui(13, .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                coins
            }
            Spacer(minLength: 0)
            // Round arrows either side of the count, under the car
            HStack(spacing: 14) {
                arrow("chevron.left") { step(-1) }
                Text("\(spec.id.order + 1) / \(CarSpec.all.count)")
                    .font(.ui(14, .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 52)
                arrow("chevron.right") { step(1) }
            }
            .padding(.bottom, 12)
            carStrip
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The coins, in a round glass capsule.
    private var coins: some View {
        HStack(spacing: 6) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Palette.gold)
            Text("\(model.coins)")
                .font(.race(18))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(height: 36)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .animation(.easeOut(duration: 0.3), value: model.coins)
    }

    private func arrow(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
    }

    private var carStrip: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
            ForEach(CarSpec.all, id: \.id) { car in
                let selected = car.id == choice.model
                let owned = Progression.owns(car.id)
                Button {
                    select(car.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(car.className)
                                .font(.ui(11, .heavy))
                                .foregroundStyle(selected ? Palette.ink : .white)
                                .frame(minWidth: 20)
                                .padding(.horizontal, 4)
                                .frame(height: 18)
                                .background(Capsule().fill(selected ? Palette.gold : Color.white.opacity(0.16)))
                            Spacer(minLength: 0)
                            if !owned {
                                HStack(spacing: 3) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("\(Progression.price(car.id))")
                                        .monospacedDigit()
                                }
                                .font(.ui(11, .bold))
                                .foregroundStyle(Palette.gold)
                            }
                        }
                        Text(car.name)
                            .font(.race(17))
                            .foregroundStyle(.white.opacity(owned || selected ? 1 : 0.7))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(width: 124, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selected ? Color.white.opacity(0.16) : Color.black.opacity(0.45))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected ? Color.white.opacity(0.85) : Color.white.opacity(0.1), lineWidth: selected ? 1.5 : 1)
                    )
                }
                .buttonStyle(PressScaleStyle())
                .id(car.id)
            }
        }
        .padding(.vertical, 3)
        .padding(.trailing, 12)
        }
        .frame(maxWidth: 420)
        .onAppear { proxy.scrollTo(choice.model, anchor: .center) }
        .onChange(of: choice.model) { _, id in
            withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
        }
        }
    }

    // MARK: Right: name, stats, paint, go

    /// The details on the shade, no panel: maker and class, the name big, four bars, the paint,
    /// then the buttons.
    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(spec.maker)
                    .font(.ui(13, .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer()
                Text(Strings.carClass + " " + spec.className)
                    .font(.ui(12, .heavy))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Capsule().fill(Palette.gold))
            }
            Text(spec.name.uppercased())
                .font(.race(44))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 2)
                .id(spec.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

            VStack(spacing: 10) {
                StatBar(label: Strings.statSpeed, value: ratings.speed, shown: statsShown, color: accent)
                StatBar(label: Strings.statAccel, value: ratings.acceleration, shown: statsShown, color: accent)
                StatBar(label: Strings.statHandling, value: ratings.handling, shown: statsShown, color: accent)
                StatBar(label: Strings.statNitro, value: ratings.nitro, shown: statsShown, color: accent)
            }
            .padding(.top, 10)

            if CarSpec.paintChoice {
                HStack(spacing: 6) {
                    ForEach(CarSpec.paints.indices, id: \.self) { index in
                        let selected = index == choice.paint
                        Button {
                            AudioManager.shared.play("click", volume: 0.5)
                            choice.paint = index
                        } label: {
                            Circle()
                                .fill(Color(CarSpec.paints[index].color))
                                .frame(width: 22, height: 22)
                                .padding(3)
                                .overlay(Circle().strokeBorder(selected ? Color.white : Color.clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 4)
                    Text(spec.fixedLivery ? Strings.factoryLivery : CarSpec.paints[choice.paint].name)
                        .font(.ui(12, .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .padding(.top, 14)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: choice.paint)
                .opacity(spec.fixedLivery ? 0.35 : 1)
                .allowsHitTesting(!spec.fixedLivery)
            }

            Spacer(minLength: 10)
            HStack(spacing: 10) {
                if Progression.owns(choice.model) {
                    Button {
                        AudioManager.shared.play("click", volume: 0.6)
                        showUpgrades = true
                    } label: {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(Strings.upgrade)
                    Button {
                        AudioManager.shared.play("click", volume: 0.7)
                        model.carChoice = choice
                        model.leaveGarage(confirmed: true)
                    } label: {
                        Text(isPlay ? Strings.raceStart.uppercased() : Strings.selectCar.uppercased())
                    }
                    .buttonStyle(GaragePillStyle(fill: Palette.gold))
                } else {
                    buyButton
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: spec.id)
    }

    /// Unlocks the shown car with coins (or says how many are missing).
    private var buyButton: some View {
        let price = Progression.price(choice.model)
        let affordable = model.coins >= price
        return Button {
            if model.buyCar(choice.model) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                stage.celebrateUnlock(choice)
                withAnimation(.easeOut(duration: 0.25)) { unlocked = choice.spec }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: affordable ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 16, weight: .black))
                Text(affordable ? Strings.unlockFor(price) : Strings.needMoreCoins(price - model.coins))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .buttonStyle(GaragePillStyle(fill: affordable ? Color(red: 0.35, green: 0.95, blue: 0.55) : Color(white: 0.45),
                                     fontSize: affordable ? 21 : 16))
        .disabled(!affordable)
    }

    private func step(_ delta: Int) {
        let ids = CarModelID.allCases
        let next = (choice.model.order + delta + ids.count) % ids.count
        select(ids[next])
    }

    private func select(_ id: CarModelID) {
        guard id != choice.model else { return }
        AudioManager.shared.play("click", volume: 0.6)
        choice.model = id
    }
}

/// Label, a thin bar and the number, the bar filling when `shown` turns on.
private struct StatBar: View {
    let label: String
    let value: Double
    let shown: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(label)
                    .font(.ui(12, .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Spacer()
                Text("\(Int((value * 100).rounded()))")
                    .font(.race(16))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * CGFloat(shown ? value : 0))
                        .animation(.easeOut(duration: 0.6), value: shown)
                        .animation(.easeOut(duration: 0.4), value: value)
                }
            }
            .frame(height: 5)
        }
    }
}

/// The garage's main button: a gold pill (green to unlock), full width.
struct GaragePillStyle: ButtonStyle {
    let fill: Color
    var fontSize: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.race(fontSize))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(fill))
            .shadow(color: fill.opacity(0.35), radius: configuration.isPressed ? 4 : 14, y: 5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Small press feedback for plain buttons.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Full-screen reveal after buying a car, over the stage's own reveal (`celebrateUnlock`):
/// cinema bars close in while the studio is dark, an anamorphic flare streaks across when the
/// lights come on, then the car's card builds in the lower left so the car itself stays clear: a
/// kicker with a drawn accent line, the maker, the name rising letter by letter under a light
/// sweep, its class, and the performance bars filling up. A tap (or a few seconds) ends it.
struct UnlockReveal: View {
    let spec: CarSpec
    let accent: Color
    let done: () -> Void

    @State private var bars = false
    @State private var flare: CGFloat = 0
    @State private var kicker = false
    @State private var line: CGFloat = 0
    @State private var letters = 0
    @State private var shine: CGFloat = -1
    @State private var details = false
    @State private var fill: CGFloat = 0
    @State private var hint = false
    @State private var closing = false
    @State private var finished = false

    private var name: [Character] { Array(spec.name.uppercased()) }

    var body: some View {
        GeometryReader { geo in
            let barHeight = geo.size.height * 0.11
            ZStack(alignment: .bottomLeading) {
                // Shade on the left for the card; the car on the right stays clear
                LinearGradient(colors: [Color.black.opacity(0.8), Color.black.opacity(0.35), .clear],
                               startPoint: .leading, endPoint: .init(x: 0.62, y: 0.5))
                    .ignoresSafeArea()
                    .opacity(kicker ? 1 : 0)

                // Anamorphic flare as the lights come on
                Capsule()
                    .fill(LinearGradient(colors: [.clear, accent.opacity(0.9), .white, accent.opacity(0.9), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * 1.4 * flare, height: 3 + 5 * flare)
                    .blur(radius: 1.5)
                    .shadow(color: accent, radius: 18)
                    .opacity(flare > 0 ? Double(1 - flare) : 0)
                    .position(x: geo.size.width * 0.62, y: geo.size.height * 0.5)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)

                // The car's card
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Rectangle()
                            .fill(accent)
                            .frame(width: 36 * line, height: 3)
                            .shadow(color: accent, radius: 6)
                        Text(Strings.carUnlocked.uppercased())
                            .font(.kicker(12))
                            .tracking(4)
                            .foregroundStyle(accent)
                            .opacity(kicker ? 1 : 0)
                            .offset(x: kicker ? 0 : -12)
                    }
                    Text(spec.maker.uppercased())
                        .font(.kicker(12))
                        .tracking(5)
                        .foregroundStyle(.white.opacity(0.7))
                        .opacity(kicker ? 1 : 0)
                        .padding(.top, 6)

                    // The name, letter by letter, with a light sweep once it is complete
                    HStack(spacing: 0) {
                        ForEach(Array(name.enumerated()), id: \.offset) { index, letter in
                            Text(String(letter))
                                .font(.race(64, weight: .black))
                                .italic()
                                .foregroundStyle(.white)
                                .opacity(index < letters ? 1 : 0)
                                .offset(y: index < letters ? 0 : 26)
                                .blur(radius: index < letters ? 0 : 6)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .shadow(color: accent.opacity(0.55), radius: 16)
                    .overlay(
                        LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 70)
                            .rotationEffect(.degrees(18))
                            .offset(x: shine * 300)
                            .blendMode(.plusLighter)
                            .mask(Text(spec.name.uppercased()).font(.race(64, weight: .black)).italic()
                                    .frame(maxWidth: .infinity, alignment: .leading))
                            .allowsHitTesting(false)
                    )

                    HStack(spacing: 10) {
                        Text(Strings.carClass + " " + spec.className)
                            .font(.race(13, weight: .heavy))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(SlantedShape(skew: 6).fill(accent))
                        Text(Strings.addedToGarage.uppercased())
                            .font(.kicker(11))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .opacity(details ? 1 : 0)
                    .offset(y: details ? 0 : 8)

                    // Performance
                    VStack(alignment: .leading, spacing: 7) {
                        statRow(Strings.statSpeed, spec.stats.speed, delay: 0)
                        statRow(Strings.statAccel, spec.stats.acceleration, delay: 0.08)
                        statRow(Strings.statHandling, spec.stats.handling, delay: 0.16)
                    }
                    .padding(.top, 12)
                    .opacity(details ? 1 : 0)
                }
                .padding(.leading, max(28, geo.safeAreaInsets.leading + 12))
                .padding(.bottom, barHeight + 18)

                // Tap hint, lower right
                Text(Strings.tapToContinue)
                    .font(.ui(12, .semibold))
                    .foregroundStyle(.white.opacity(hint ? 0.65 : 0))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, max(28, geo.safeAreaInsets.trailing + 12))
                    .padding(.bottom, barHeight + 18)

                // Cinema bars
                VStack {
                    Color.black.frame(height: barHeight).offset(y: bars ? 0 : -barHeight - 40)
                    Spacer()
                    Color.black.frame(height: barHeight).offset(y: bars ? 0 : barHeight + 40)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            .opacity(closing ? 0 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { close() }
        .onAppear(perform: play)
    }

    private func statRow(_ label: String, _ value: Double, delay: Double) -> some View {
        HStack(spacing: 10) {
            Text(label.uppercased())
                .font(.kicker(10))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 96, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.7), accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 180 * CGFloat(value) * fill)
                    .shadow(color: accent.opacity(0.8), radius: 5)
                    .animation(.easeOut(duration: 0.9).delay(delay), value: fill)
            }
            .frame(width: 180, height: 5)
            Text("\(Int((value * 100 * Double(fill)).rounded()))")
                .font(.race(13, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 34, alignment: .trailing)
                .animation(.easeOut(duration: 0.9).delay(delay), value: fill)
        }
    }

    private func play() {
        // 0.0  dark studio, cinema bars close in
        withAnimation(.easeOut(duration: 0.5)) { bars = true }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        // 0.3  the light sweep on the car
        after(0.3) { AudioManager.shared.play("whoosh", volume: 0.7) }
        // 1.25 the lights slam on: flare, thump, the card starts
        after(1.25) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            AudioManager.shared.play("nitro", volume: 0.8)
            withAnimation(.easeOut(duration: 0.7)) { flare = 1 }
        }
        after(1.45) {
            withAnimation(.easeOut(duration: 0.35)) { kicker = true }
            withAnimation(.easeOut(duration: 0.45).delay(0.05)) { line = 1 }
        }
        for index in 0..<name.count {
            after(1.65 + Double(index) * 0.045) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { letters = index + 1 }
                if index % 2 == 0 { UISelectionFeedbackGenerator().selectionChanged() }
            }
        }
        let named = 1.65 + Double(name.count) * 0.045 + 0.15
        after(named) {
            withAnimation(.easeInOut(duration: 0.75)) { shine = 1 }
            withAnimation(.easeOut(duration: 0.35)) { details = true }
            fill = 1
            AudioManager.shared.play("park", volume: 0.6)
        }
        after(named + 1.0) { withAnimation(.easeIn(duration: 0.4)) { hint = true } }
        after(7.5) { close() }
    }

    private func close() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeIn(duration: 0.3)) { bars = false; closing = true }
        after(0.3) { done() }
    }

    private func after(_ delay: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

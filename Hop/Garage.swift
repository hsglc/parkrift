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
        let ring = SCNTube(innerRadius: 3.28, outerRadius: 3.36, height: 0.11)
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
            let car = Car3D(color: saved.color, style: .racer, model: id)
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
        }
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 120
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
        cameraNode.position = SCNVector3(-0.6, 1.9, 9.6)
        cameraNode.look(at: SCNVector3(1.9, 0.45, 0))
        scene.rootNode.addChildNode(cameraNode)

        turntable.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 26)), forKey: "spin")
    }

    /// Shows `choice`: a new model swaps in with a short scale/fade, a new paint just repaints.
    func show(_ choice: CarChoice, animated: Bool = true) {
        guard choice != shown, let car = cars[choice.model] else { return }
        let previous = shown
        shown = choice
        let accent = choice.color.lighter(by: 0.15)
        ringMaterial.emission.contents = accent
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

    /// Unlock reveal on the stage: the platform ring flashes white, a light column sweeps up
    /// through the car, sparks burst from the ring in the car's accent colour, the car hops and
    /// spins once and the camera pushes in and settles back.
    func celebrateUnlock(_ choice: CarChoice) {
        guard let car = cars[choice.model] else { return }
        let accent = choice.color.lighter(by: 0.25)

        // Ring flash: white, then back to the accent
        ringMaterial.emission.contents = UIColor.white
        floorGlow.multiply.contents = UIColor.white
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.ringMaterial.emission.contents = accent
            self?.floorGlow.multiply.contents = accent
        }

        // Light column rising through the car
        let beam = SCNCylinder(radius: 3.0, height: 0.02)
        beam.radialSegmentCount = 64
        let beamMaterial = SCNMaterial()
        beamMaterial.lightingModel = .constant
        beamMaterial.diffuse.contents = UIColor.black
        beamMaterial.emission.contents = accent
        beamMaterial.blendMode = .add
        beamMaterial.writesToDepthBuffer = false
        beamMaterial.isDoubleSided = true
        beam.materials = [beamMaterial]
        let beamNode = SCNNode(geometry: beam)
        beamNode.position = SCNVector3(0, 0.12, 0)
        beamNode.opacity = 0.9
        scene.rootNode.addChildNode(beamNode)
        let rise = SCNAction.move(to: SCNVector3(0, 2.6, 0), duration: 0.7)
        rise.timingMode = .easeOut
        beamNode.runAction(.sequence([.group([rise, .fadeOut(duration: 0.7),
                                               .customAction(duration: 0.7) { node, t in
                                                   (node.geometry as? SCNCylinder)?.radius = 3.0 - 1.4 * t / 0.7
                                               }]),
                                       .removeFromParentNode()]))

        // Sparks from the ring
        let sparks = SCNParticleSystem()
        sparks.particleImage = CarArt.glowParticle()
        sparks.birthRate = 2600
        sparks.emissionDuration = 0.12
        sparks.loops = false
        sparks.particleLifeSpan = 1.1
        sparks.particleLifeSpanVariation = 0.4
        sparks.particleSize = 0.09
        sparks.particleSizeVariation = 0.05
        sparks.particleVelocity = 4.2
        sparks.particleVelocityVariation = 2.0
        sparks.emittingDirection = SCNVector3(0, 1, 0)
        sparks.spreadingAngle = 35
        sparks.acceleration = SCNVector3(0, -6.5, 0)
        sparks.particleColor = accent
        sparks.particleColorVariation = SCNVector4(0.05, 0.1, 0.2, 0)
        sparks.blendMode = .additive
        sparks.emitterShape = SCNTube(innerRadius: 3.2, outerRadius: 3.35, height: 0.05)
        sparks.birthLocation = .surface
        let emitter = SCNNode()
        emitter.position = SCNVector3(0, 0.12, 0)
        emitter.addParticleSystem(sparks)
        scene.rootNode.addChildNode(emitter)
        emitter.runAction(.sequence([.wait(duration: 2.2), .removeFromParentNode()]))

        // The car hops and turns once
        car.node.removeAllActions()
        car.node.position = SCNVector3(0, 0.1, 0)
        car.node.scale = SCNVector3(1, 1, 1)
        car.node.opacity = 1
        let up = SCNAction.move(to: SCNVector3(0, 0.55, 0), duration: 0.32)
        up.timingMode = .easeOut
        let down = SCNAction.move(to: SCNVector3(0, 0.1, 0), duration: 0.38)
        down.timingMode = .easeIn
        let spin = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 0.95)
        spin.timingMode = .easeInEaseOut
        let squash = SCNAction.sequence([.scale(to: 1.04, duration: 0.08), .scale(to: 1, duration: 0.2)])
        car.node.runAction(.sequence([.wait(duration: 0.1), .group([.sequence([up, down, squash]), spin])]))

        // Camera push-in and back
        let home = cameraNode.position
        let closer = SCNVector3(home.x + 0.5, home.y - 0.3, home.z - 2.4)
        let push = SCNAction.move(to: closer, duration: 0.5)
        push.timingMode = .easeOut
        let back = SCNAction.move(to: home, duration: 1.1)
        back.timingMode = .easeInEaseOut
        cameraNode.removeAction(forKey: "unlock")
        cameraNode.runAction(.sequence([push, .wait(duration: 0.6), back]), forKey: "unlock")
        if let camera = cameraNode.camera {
            let bloom = camera.bloomIntensity
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.2
            camera.bloomIntensity = 1.2
            SCNTransaction.completionBlock = {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 1.0
                camera.bloomIntensity = bloom
                SCNTransaction.commit()
            }
            SCNTransaction.commit()
        }
    }

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
            // Readability shade under the panel and the title
            LinearGradient(colors: [.clear, .clear, Palette.carbon.opacity(0.75)], startPoint: .leading, endPoint: .trailing)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            LinearGradient(colors: [Palette.carbon.opacity(0.6), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            HStack(alignment: .top, spacing: 0) {
                leftColumn
                Spacer(minLength: 12)
                infoPanel
                    .frame(width: 300)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .opacity(unlocked == nil ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: unlocked == nil)

            if let spec = unlocked {
                UnlockReveal(spec: spec, accent: accent) {
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

    // MARK: Left: title, arrows, car strip

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                RoundIconButton(systemImage: "chevron.left") {
                    AudioManager.shared.play("click", volume: 0.6)
                    model.leaveGarage(confirmed: false)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(Strings.garage.uppercased())
                        .font(.race(30))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(.white)
                    Text(modeLabel.uppercased())
                        .font(.kicker(10))
                        .tracking(1.5)
                        .foregroundStyle(Palette.neon)
                }
                CoinPill(coins: model.coins)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                arrow("chevron.left") { step(-1) }
                Text(String(format: "%02d / %02d", spec.id.order + 1, CarSpec.all.count))
                    .font(.race(18, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 84)
                arrow("chevron.right") { step(1) }
            }
            .padding(.bottom, 10)
            carStrip
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func arrow(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 46, height: 40)
                .background(SlantedShape(skew: 8).fill(Color.white.opacity(0.12)))
                .overlay(SlantedShape(skew: 8).stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
    }

    private var carStrip: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
            ForEach(CarSpec.all, id: \.id) { car in
                let selected = car.id == choice.model
                Button {
                    select(car.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(car.className)
                                .font(.race(11, weight: .heavy))
                                .foregroundStyle(selected ? Palette.ink : .white)
                                .padding(.horizontal, 5)
                                .background(SlantedShape(skew: 3).fill(selected ? Palette.gold : Color.white.opacity(0.2)))
                            if Progression.owns(car.id) {
                                Text(car.maker)
                                    .font(.kicker(8))
                                    .tracking(1)
                                    .foregroundStyle(.white.opacity(0.6))
                            } else {
                                HStack(spacing: 3) {
                                    Image(systemName: "lock.fill")
                                    Text("\(Progression.price(car.id))")
                                        .monospacedDigit()
                                }
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(Palette.gold)
                            }
                        }
                        Text(car.name.uppercased())
                            .font(.race(16))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 8)
                    .padding(.leading, 16)
                    .padding(.trailing, 10)
                    .frame(width: 128, alignment: .leading)
                    .background(SlantedShape(skew: 10).fill(selected ? Color.white.opacity(0.18) : Palette.carbon.opacity(0.7)))
                    .overlay(SlantedShape(skew: 10).stroke(selected ? accent : Color.white.opacity(0.12), lineWidth: selected ? 2 : 1))
                    .overlay(alignment: .bottom) {
                        if selected {
                            Rectangle().fill(accent).frame(height: 3).padding(.horizontal, 14).offset(y: 1)
                        }
                    }
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

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(spec.maker)
                    .font(.kicker(11))
                    .tracking(2)
                    .foregroundStyle(accent)
                Spacer()
                Text(Strings.carClass + " " + spec.className)
                    .font(.race(14, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(SlantedShape(skew: 5).fill(Palette.gold))
            }
            Text(spec.name.uppercased())
                .font(.race(40))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .id(spec.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

            VStack(spacing: 7) {
                StatBar(label: Strings.statSpeed, value: ratings.speed, shown: statsShown, color: accent)
                StatBar(label: Strings.statAccel, value: ratings.acceleration, shown: statsShown, color: accent)
                StatBar(label: Strings.statHandling, value: ratings.handling, shown: statsShown, color: accent)
                StatBar(label: Strings.statNitro, value: ratings.nitro, shown: statsShown, color: accent)
            }
            .padding(.top, 2)

            HStack {
                if CarSpec.paintChoice {
                    Text(Strings.paint.uppercased())
                        .font(.kicker(10))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                if CarSpec.paintChoice {
                    Text(spec.fixedLivery ? Strings.factoryLivery.uppercased() : CarSpec.paints[choice.paint].name.uppercased())
                        .font(.race(13, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.85))
                }
                if Progression.owns(choice.model) {
                    Button {
                        AudioManager.shared.play("click", volume: 0.6)
                        showUpgrades = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                            Text(Strings.upgrade.uppercased())
                        }
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Palette.gold))
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
            .padding(.top, 4)
            if CarSpec.paintChoice {
            HStack(spacing: 4) {
                ForEach(CarSpec.paints.indices, id: \.self) { index in
                    let selected = index == choice.paint
                    Button {
                        AudioManager.shared.play("click", volume: 0.5)
                        choice.paint = index
                    } label: {
                        Circle()
                            .fill(LinearGradient(colors: [Color(CarSpec.paints[index].color.lighter(by: 0.25)), Color(CarSpec.paints[index].color)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.white.opacity(selected ? 1 : 0.25), lineWidth: selected ? 2.5 : 1))
                            .padding(3)
                            .overlay(Circle().stroke(selected ? accent : .clear, lineWidth: 1.5))
                            .scaleEffect(selected ? 1.08 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: choice.paint)
            .opacity(spec.fixedLivery ? 0.3 : 1)
            .allowsHitTesting(!spec.fixedLivery)
            }

            Spacer(minLength: 6)
            if Progression.owns(choice.model) {
                Button {
                    AudioManager.shared.play("click", volume: 0.7)
                    model.carChoice = choice
                    model.leaveGarage(confirmed: true)
                } label: {
                    HStack(spacing: 8) {
                        Text(isPlay ? Strings.raceStart.uppercased() : Strings.selectCar.uppercased())
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 16, weight: .black))
                    }
                }
                .buttonStyle(RaceButtonStyle(color: Palette.gold, height: 50, fontSize: 22))
            } else {
                buyButton
            }
        }
        .racePlate(skew: 20, padding: 16)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: spec.id)
    }

    /// Unlocks the shown car with coins (or says how many are missing).
    private var buyButton: some View {
        let price = Progression.price(choice.model)
        let affordable = model.coins >= price
        return Button {
            if model.buyCar(choice.model) {
                AudioManager.shared.play("park", volume: 0.8)
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
        .buttonStyle(RaceButtonStyle(color: affordable ? Color(red: 0.35, green: 0.95, blue: 0.55) : Color(white: 0.45),
                                     height: 50, fontSize: affordable ? 20 : 15))
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

/// Label, segmented bar and number, filling up when `shown` turns on.
private struct StatBar: View {
    let label: String
    let value: Double
    let shown: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(label.uppercased())
                .font(.kicker(9))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 82, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GeometryReader { proxy in
                let segments = 12
                let gap: CGFloat = 2
                let width = (proxy.size.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
                let lit = shown ? Int((value * Double(segments)).rounded()) : 0
                HStack(spacing: gap) {
                    ForEach(0..<segments, id: \.self) { index in
                        SlantedShape(skew: 3)
                            .fill(index < lit ? AnyShapeStyle(color) : AnyShapeStyle(Color.white.opacity(0.1)))
                            .frame(width: width)
                            .animation(.easeOut(duration: 0.25).delay(Double(index) * 0.025), value: lit)
                    }
                }
            }
            .frame(height: 9)
            Text("\(Int((value * 100).rounded()))")
                .font(.race(15, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 28, alignment: .trailing)
        }
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

/// Full-screen reveal after buying a car: a flash, a lock that springs open, the car's name
/// wiped in on a slanted neon band, its maker and class, then it fades by itself (or on a tap).
struct UnlockReveal: View {
    let spec: CarSpec
    let accent: Color
    let done: () -> Void

    @State private var flash = 1.0
    @State private var lockOpen = false
    @State private var bandWidth: CGFloat = 0
    @State private var nameShown = false
    @State private var detailsShown = false
    @State private var shine: CGFloat = -1
    @State private var ringScale: CGFloat = 0.4
    @State private var ringOpacity = 0.9

    var body: some View {
        ZStack {
            // Edge darkening so the text reads over the stage, with the car visible in the middle
            RadialGradient(colors: [.clear, Color.black.opacity(0.75)], center: .center, startRadius: 120, endRadius: 520)
                .ignoresSafeArea()
            Color.white.opacity(flash).ignoresSafeArea().blendMode(.plusLighter)

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(accent, lineWidth: 3)
                        .frame(width: 92, height: 92)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 64, height: 64)
                        .overlay(Circle().stroke(accent.opacity(0.9), lineWidth: 1.5))
                    Image(systemName: lockOpen ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(lockOpen ? accent : .white)
                        .rotationEffect(.degrees(lockOpen ? -12 : 0))
                        .scaleEffect(lockOpen ? 1.12 : 1)
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(Strings.carUnlocked.uppercased())
                    .font(.kicker(12))
                    .tracking(4)
                    .foregroundStyle(accent)
                    .opacity(detailsShown || nameShown ? 1 : 0)

                ZStack {
                    // Slanted neon band the name sits on
                    SlantedShape(skew: 26)
                        .fill(LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: bandWidth, height: 70)
                        .shadow(color: accent.opacity(0.8), radius: 18)
                    Text(spec.name.uppercased())
                        .font(.race(54, weight: .black))
                        .italic()
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 40)
                        .opacity(nameShown ? 1 : 0)
                        .offset(x: nameShown ? 0 : -40)
                        .overlay(
                            // Light sweep over the name
                            LinearGradient(colors: [.clear, .white.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 90)
                                .rotationEffect(.degrees(18))
                                .offset(x: shine * 320)
                                .blendMode(.plusLighter)
                                .mask(Text(spec.name.uppercased()).font(.race(54, weight: .black)).italic())
                        )
                }
                .frame(height: 80)

                HStack(spacing: 10) {
                    Text(spec.maker.uppercased())
                        .font(.kicker(11))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(Strings.carClass + " " + spec.className)
                        .font(.race(12, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SlantedShape(skew: 6).fill(accent))
                    Text(Strings.addedToGarage.uppercased())
                        .font(.kicker(11))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .opacity(detailsShown ? 1 : 0)
                .offset(y: detailsShown ? 0 : 10)

                Text(Strings.tapToContinue)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 14)
                    .opacity(detailsShown ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { done() }
        .onAppear(perform: play)
    }

    private func play() {
        withAnimation(.easeOut(duration: 0.45)) { flash = 0 }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5).delay(0.2)) { lockOpen = true }
        withAnimation(.easeOut(duration: 0.7).delay(0.2)) { ringScale = 2.2; ringOpacity = 0 }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.35)) { bandWidth = 520 }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.5)) { nameShown = true }
        withAnimation(.easeInOut(duration: 0.8).delay(0.75)) { shine = 1 }
        withAnimation(.easeOut(duration: 0.4).delay(0.9)) { detailsShown = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) { done() }
    }
}

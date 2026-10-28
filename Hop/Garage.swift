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
        car.setPaint(choice.color)
        car.setRim(choice.rimColor)
        guard previous?.model != choice.model else { return }

        let tiny = SCNVector3(0.001, 0.001, 0.001)
        if let previous = previous, let old = cars[previous.model], animated {
            old.node.removeAllActions()
            old.node.runAction(.sequence([.group([.fadeOut(duration: 0.16), .scale(to: 0.9, duration: 0.16)]),
                                          .run { $0.scale = tiny; $0.opacity = 1 }]))
        } else {
            for (id, other) in cars where id != choice.model {
                other.node.removeAllActions()
                other.node.scale = tiny
            }
        }
        car.node.removeAllActions()
        guard animated, previous != nil else {
            car.node.opacity = 1
            car.node.scale = SCNVector3(1, 1, 1)
            car.node.position.y = 0.1
            return
        }
        car.node.opacity = 0
        car.node.scale = SCNVector3(0.88, 0.88, 0.88)
        car.node.position.y = 0.6
        let drop = SCNAction.move(to: SCNVector3(0, 0.1, 0), duration: 0.35)
        drop.timingMode = .easeOut
        let grow = SCNAction.scale(to: 1, duration: 0.35)
        grow.timingMode = .easeOut
        car.node.runAction(.sequence([.wait(duration: 0.12), .group([.fadeIn(duration: 0.25), drop, grow])]))
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
    static func prewarm(using renderer: SCNSceneRenderer?) {
        let stage = shared
        renderer?.prepare([stage.scene], completionHandler: nil)
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
    private let stage = GarageStage.shared

    private var spec: CarSpec { choice.spec }
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
        }
        .sheet(isPresented: $showUpgrades) { UpgradeView(choice: $choice).environmentObject(model) }
        .onAppear {
            choice = model.carChoice
            stage.show(choice, animated: false)
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) { statsShown = true }
        }
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
                StatBar(label: Strings.statSpeed, value: spec.stats.speed, shown: statsShown, color: accent)
                StatBar(label: Strings.statAccel, value: spec.stats.acceleration, shown: statsShown, color: accent)
                StatBar(label: Strings.statHandling, value: spec.stats.handling, shown: statsShown, color: accent)
                StatBar(label: Strings.statNitro, value: spec.stats.nitro, shown: statsShown, color: accent)
            }
            .padding(.top, 2)

            HStack {
                Text(Strings.paint.uppercased())
                    .font(.kicker(10))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(spec.fixedLivery ? Strings.factoryLivery.uppercased() : CarSpec.paints[choice.paint].name.uppercased())
                    .font(.race(13, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.85))
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

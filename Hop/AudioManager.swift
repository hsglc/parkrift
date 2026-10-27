import AVFoundation

/// Music loop, engine hum and one-shot effects on a single AVAudioEngine.
@MainActor
final class AudioManager {
    static let shared = AudioManager()

    private let engine = AVAudioEngine()
    private let musicNode = AVAudioPlayerNode()
    private let motorNode = AVAudioPlayerNode()
    private let motorPitch = AVAudioUnitVarispeed()
    private var effectNodes: [AVAudioPlayerNode] = []
    private var nextEffect = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var prepared = false
    private var musicStarted = false
    private var motorStarted = false
    /// Looping layers whose volume follows the game: tyre screech, police siren, rain.
    private var loopNodes: [String: AVAudioPlayerNode] = [:]
    private var loopStarted = Set<String>()
    private static let loopNames = ["skid", "siren", "rain"]

    var isMuted: Bool {
        get { UserDefaults.standard.bool(forKey: "pp.muted") }
        set {
            UserDefaults.standard.set(newValue, forKey: "pp.muted")
            engine.mainMixerNode.outputVolume = newValue ? 0 : 1
        }
    }

    private init() {}

    private func load(_ name: String, ext: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }
        return buffer
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        let session = AVAudioSession.sharedInstance()
        // Ambient: game sounds follow the Silent switch and mix with other apps' audio
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        buffers["music"] = load("music", ext: "m4a")
        for name in ["engine", "bump", "beep", "go", "park", "click", "horn", "nitro", "crash", "whoosh", "skid", "siren", "rain"] {
            buffers[name] = load(name, ext: "wav")
        }

        engine.attach(musicNode)
        engine.attach(motorNode)
        engine.attach(motorPitch)
        if let music = buffers["music"] {
            engine.connect(musicNode, to: engine.mainMixerNode, format: music.format)
        }
        if let motor = buffers["engine"] {
            engine.connect(motorNode, to: motorPitch, format: motor.format)
            engine.connect(motorPitch, to: engine.mainMixerNode, format: motor.format)
        }
        for name in AudioManager.loopNames {
            guard let buffer = buffers[name] else { continue }
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
            node.volume = 0
            loopNodes[name] = node
        }
        let effectFormat = buffers["bump"]?.format
        for _ in 0..<4 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: effectFormat)
            effectNodes.append(node)
        }
        engine.mainMixerNode.outputVolume = isMuted ? 0 : 1
        engine.prepare()

        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AudioManager.shared.ensureRunning() }
        }
    }

    /// Starts (or restarts after an interruption) the engine and the music loop.
    func ensureRunning() {
        prepare()
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                return
            }
            musicStarted = false
            motorStarted = false
            loopStarted.removeAll()
        }
        if !musicStarted, let music = buffers["music"] {
            musicNode.stop()
            musicNode.scheduleBuffer(music, at: nil, options: [.loops], completionHandler: nil)
            musicNode.volume = 0.5
            musicNode.play()
            musicStarted = true
        }
    }

    func setMusicVolume(_ volume: Float) {
        musicNode.volume = volume
    }

    func play(_ name: String, volume: Float = 1) {
        ensureRunning()
        guard engine.isRunning, let buffer = buffers[name], !effectNodes.isEmpty else { return }
        let node = effectNodes[nextEffect]
        nextEffect = (nextEffect + 1) % effectNodes.count
        node.stop()
        node.volume = volume
        node.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        node.play()
    }

    /// Sets a looping layer's volume (0 silences it); `rate` is not used for now.
    func setLoop(_ name: String, volume: Float) {
        guard engine.isRunning, let node = loopNodes[name], let buffer = buffers[name] else { return }
        if volume > 0.001 && !loopStarted.contains(name) {
            node.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
            node.play()
            loopStarted.insert(name)
        }
        node.volume = max(0, min(1, volume))
    }

    /// Silences every looping layer (leaving a level).
    func stopLoops() {
        for node in loopNodes.values { node.volume = 0 }
    }

    /// speed: 0...1 of top speed, throttle: 0 or 1.
    func setMotor(active: Bool, speed: Float, throttle: Float) {
        guard engine.isRunning, let motor = buffers["engine"] else { return }
        if active && !motorStarted {
            motorNode.scheduleBuffer(motor, at: nil, options: [.loops], completionHandler: nil)
            motorNode.play()
            motorStarted = true
        }
        let clampedSpeed = max(0, min(1, speed))
        motorPitch.rate = 0.7 + clampedSpeed * 1.1 + throttle * 0.12
        motorNode.volume = active ? (0.10 + 0.14 * throttle + 0.10 * clampedSpeed) : 0
    }
}

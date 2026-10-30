import AVFoundation

/// Music loop, engine hum and one-shot effects on a single AVAudioEngine.
@MainActor
final class AudioManager {
    static let shared = AudioManager()

    private let engine = AVAudioEngine()
    private let musicNode = AVAudioPlayerNode()
    /// Engine: a low-rev and a high-rev loop, each pitched by the rpm and crossfaded.
    private let motorNode = AVAudioPlayerNode()
    private let motorPitch = AVAudioUnitVarispeed()
    private let motorHighNode = AVAudioPlayerNode()
    private let motorHighPitch = AVAudioUnitVarispeed()
    /// Tyre squeal pitch: a sliding tyre sings higher the faster and harder it slides.
    private let skidPitch = AVAudioUnitVarispeed()
    private var effectNodes: [AVAudioPlayerNode] = []
    private var nextEffect = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var prepared = false
    private var musicStarted = false
    private var motorStarted = false
    /// Looping layers whose volume follows the game: tyre screech, police siren, rain.
    private var loopNodes: [String: AVAudioPlayerNode] = [:]
    private var loopStarted = Set<String>()
    private static let loopNames = ["skid", "siren", "rain", "wind", "snow"]

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
        for name in ["engine_low", "engine_high", "bump", "beep", "go", "park", "click", "horn", "nitro", "crash", "whoosh",
                     "skid", "siren", "rain", "wind", "snow", "shift"] {
            buffers[name] = load(name, ext: "wav")
        }

        engine.attach(musicNode)
        engine.attach(motorNode)
        engine.attach(motorPitch)
        engine.attach(motorHighNode)
        engine.attach(motorHighPitch)
        if let music = buffers["music"] {
            engine.connect(musicNode, to: engine.mainMixerNode, format: music.format)
        }
        if let motor = buffers["engine_low"] {
            engine.connect(motorNode, to: motorPitch, format: motor.format)
            engine.connect(motorPitch, to: engine.mainMixerNode, format: motor.format)
        }
        if let motor = buffers["engine_high"] {
            engine.connect(motorHighNode, to: motorHighPitch, format: motor.format)
            engine.connect(motorHighPitch, to: engine.mainMixerNode, format: motor.format)
        }
        for name in AudioManager.loopNames {
            guard let buffer = buffers[name] else { continue }
            let node = AVAudioPlayerNode()
            engine.attach(node)
            if name == "skid" {
                engine.attach(skidPitch)
                engine.connect(node, to: skidPitch, format: buffer.format)
                engine.connect(skidPitch, to: engine.mainMixerNode, format: buffer.format)
            } else {
                engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
            }
            node.volume = 0
            loopNodes[name] = node
        }
        let effectFormat = buffers["bump"]?.format
        for _ in 0..<6 {
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
        // No stop(): it waits for the audio thread (8-10 ms on the main thread in the benchmark,
        // on every crash). The node keeps playing and the new sound interrupts what it had queued.
        node.volume = volume
        node.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        if !node.isPlaying { node.play() }
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

    /// Tyre squeal: `volume` follows how far the tyres slide, `rate` its pitch (1 = as recorded).
    func setSkid(volume: Float, rate: Float) {
        skidPitch.rate = max(0.7, min(1.4, rate))
        setLoop("skid", volume: volume)
    }

    /// Silences every looping layer (leaving a level).
    func stopLoops() {
        for node in loopNodes.values { node.volume = 0 }
    }

    /// The engine at `rpm` (revolutions per minute) under `load` (0 coasting ... 1 full
    /// throttle). Two recorded loops, a low-rev and a high-rev one, are each pitched with the rpm
    /// and crossfade between 2000 and 4500 rpm.
    func setMotor(active: Bool, rpm: Float, load: Float) {
        guard engine.isRunning, let low = buffers["engine_low"], let high = buffers["engine_high"] else { return }
        if active && !motorStarted {
            motorNode.scheduleBuffer(low, at: nil, options: [.loops], completionHandler: nil)
            motorHighNode.scheduleBuffer(high, at: nil, options: [.loops], completionHandler: nil)
            motorNode.play()
            motorHighNode.play()
            motorStarted = true
        }
        let r = max(700, min(7600, rpm))
        motorPitch.rate = 0.75 + (r - 700) / 3300 * 0.85            // 0.75 at idle, 1.6 at 4000
        motorHighPitch.rate = max(0.7, 0.9 + (r - 2500) / 4500 * 1.0)   // 0.9 at 2500, 1.9 at 7000
        let x = max(0, min(1, (r - 2000) / 2500))
        let blend = x * x * (3 - 2 * x)
        // Louder and harder under load; quieter (but not silent) on the overrun
        let level: Float = active ? (0.09 + 0.12 * load + 0.06 * min(1, r / 7000)) : 0
        motorNode.volume = level * (1 - blend * 0.85)
        motorHighNode.volume = level * blend * (0.55 + 0.45 * load)
    }
}

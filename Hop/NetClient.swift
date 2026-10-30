import Foundation

/// WebSocket connection to the Parkrift room server (Cloudflare Durable Objects).
@MainActor
final class NetClient {
    static let baseURL = "wss://parkrift.huseyinglc0-946.workers.dev/room/"

    var onMessage: (@MainActor ([String: Any]) -> Void)?
    var onClose: (@MainActor (String?) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var pingTask: Task<Void, Never>?
    private var generation = 0
    private let session = URLSession(configuration: .default)

    var isConnected: Bool { task != nil }

    // MARK: Fast path

    /// Car states and pings go over Cloudflare Realtime DataChannels (unordered, no retransmits)
    /// once the friend says it is receiving them; everything else, and everything until then,
    /// goes over the WebSocket.
    private var fast: FastLink?
    private var friendReceiving = false
    private var fastAttempts = 0
    /// True while states reach the friend over the fast path (shown beside the room code).
    private(set) var fastActive = false
    var onFastChange: (@MainActor (Bool) -> Void)?

    func sendFast(_ message: [String: Any]) {
        if friendReceiving, let fast = fast, fast.canSend,
           let data = try? JSONSerialization.data(withJSONObject: message) {
            fast.send(data)
            if !fastActive { setFast(true) }
            return
        }
        if fastActive { setFast(false) }
        send(message)
    }

    private func fastLog(_ text: String) {
        #if BENCHMARK
        FileHandle.standardError.write("PPNET rtc \(text)\n".data(using: .utf8)!)
        #endif
    }

    private func setFast(_ on: Bool) {
        fastActive = on
        onFastChange?(on)
        #if BENCHMARK
        FileHandle.standardError.write("PPNET fast \(on ? "on" : "off")\n".data(using: .utf8)!)
        #endif
    }

    private func startFast() {
        guard fastAttempts < 3 else { return }
        fastAttempts += 1
        makeLink()
        send(["t": "rtc"])
    }

    private func makeLink() {
        let link = FastLink()
        fast?.close()
        fast = link
        link.onAnswer = { [weak self] sdp in
            Task { @MainActor in
                self?.fastLog("answer \(sdp.count) bytes")
                self?.send(["t": "rtcanswer", "sdp": sdp])
            }
        }
        link.onConnected = { [weak self] in
            Task { @MainActor in
                self?.fastLog("connected")
                self?.send(["t": "rtcup"])
            }
        }
        link.onReceiving = { [weak self] on in
            // Tell the friend whether its states reach this phone over the fast path
            Task { @MainActor in
                self?.fastLog("receiving \(on)")
                self?.send(["t": "rtcrx", "on": on ? 1 : 0])
            }
        }
        link.onMessage = { [weak self] data in
            Task { @MainActor in
                guard let self = self,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                self.onMessage?(object)
            }
        }
        link.onFailed = { [weak self, weak link] in
            Task { @MainActor in
                guard let self = self, let link = link, self.fast === link else { return }
                self.fastLog("failed")
                link.close()
                self.fast = nil
                self.send(["t": "rtcrx", "on": 0])
                // Another try a little later (the WebSocket carries everything meanwhile)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self = self, self.task != nil, self.fast == nil else { return }
                    self.startFast()
                }
            }
        }
    }

    /// Fast-path signalling from the room server; true when the message was one of them.
    private func handleFast(_ object: [String: Any]) -> Bool {
        guard let type = object["t"] as? String else { return false }
        switch type {
        case "welcome":
            fastAttempts = 0
            friendReceiving = false
            startFast()
            return false
        case "join", "leave":
            // A different friend (or none): wait until it says it receives
            friendReceiving = false
            return false
        case "rtcoffer":
            fastLog("offer")
            if let sdp = object["sdp"] as? String {
                if fast == nil { makeLink() }
                fast?.start(offer: sdp)
            }
            return true
        case "rtcpub":
            fastLog("pub \(object["id"] ?? "")")
            if let id = object["id"] as? Int { fast?.publish(id: id) }
            return true
        case "rtcsub":
            fastLog("sub \(object["id"] ?? "")")
            if let id = object["id"] as? Int { fast?.subscribe(id: id) }
            return true
        case "rtcrx":
            friendReceiving = (object["on"] as? Int ?? 0) == 1
            fastLog("friend receiving \(friendReceiving)")
            return true
        case "rtcok":
            return true
        default:
            return false
        }
    }

    func connect(code: String, asHost: Bool) {
        disconnect()
        guard let url = URL(string: NetClient.baseURL + code + "?role=" + (asHost ? "host" : "guest")) else { return }
        generation += 1
        let current = generation
        let socket = session.webSocketTask(with: url)
        task = socket
        socket.resume()
        receive(on: socket, generation: current)
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { break }
                self?.send(["t": "ping"])
            }
        }
    }

    func disconnect() {
        fast?.close()
        fast = nil
        friendReceiving = false
        if fastActive { setFast(false) }
        generation += 1
        pingTask?.cancel()
        pingTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func send(_ message: [String: Any]) {
        guard let task = task,
              let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }

    private func receive(on socket: URLSessionWebSocketTask, generation current: Int) {
        socket.receive { [weak self] result in
            switch result {
            case .success(let message):
                var text: String?
                switch message {
                case .string(let value): text = value
                case .data(let data): text = String(data: data, encoding: .utf8)
                @unknown default: text = nil
                }
                Task { @MainActor in
                    guard let self = self, self.generation == current else { return }
                    if let text = text { self.deliver(text) }
                    self.receive(on: socket, generation: current)
                }
            case .failure(let error):
                let description = error.localizedDescription
                Task { @MainActor in
                    guard let self = self, self.generation == current else { return }
                    self.task = nil
                    self.fast?.close()
                    self.fast = nil
                    self.friendReceiving = false
                    self.pingTask?.cancel()
                    self.onClose?(description)
                }
            }
        }
    }

    private func deliver(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if handleFast(object) { return }
        onMessage?(object)
    }
}

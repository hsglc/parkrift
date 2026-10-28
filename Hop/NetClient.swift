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
                    self.pingTask?.cancel()
                    self.onClose?(description)
                }
            }
        }
    }

    private func deliver(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        onMessage?(object)
    }
}

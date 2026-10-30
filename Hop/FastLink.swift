import Foundation
import WebRTC

/// The fast (UDP-like) path to the friend: a WebRTC connection to Cloudflare Realtime whose
/// DataChannels are unordered and never retransmit, so a lost car state is simply replaced by the
/// next one instead of holding the others up (as TCP under the WebSocket does).
///
/// The room socket carries the signalling: the Room on the server creates the SFU session and
/// hands this phone the SFU's offer, the channel it publishes on (`out`) and the friend's channel
/// it receives on (`in`). Callbacks arrive on the main queue.
final class FastLink: NSObject {
    private static let factory: RTCPeerConnectionFactory = {
        // Data only: WebRTC must leave the game's audio session alone
        let audio = RTCAudioSession.sharedInstance()
        audio.useManualAudio = true
        audio.isAudioEnabled = false
        RTCInitializeSSL()
        return RTCPeerConnectionFactory()
    }()

    var onAnswer: ((String) -> Void)?
    var onConnected: (() -> Void)?
    var onFailed: (() -> Void)?
    var onReceiving: ((Bool) -> Void)?
    var onMessage: ((Data) -> Void)?

    private var peer: RTCPeerConnection?
    private var out: RTCDataChannel?
    private var incoming: RTCDataChannel?
    private var transport: RTCDataChannel?
    private var answerSent = false
    private var connected = false

    var canSend: Bool { out?.readyState == .open }

    /// Answers the SFU's offer; `onAnswer` gets the local description once its candidates are in.
    func start(offer sdp: String) {
        close()
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.cloudflare.com:3478"])]
        config.sdpSemantics = .unifiedPlan
        config.bundlePolicy = .maxBundle
        config.continualGatheringPolicy = .gatherOnce
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peer = FastLink.factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            onFailed?()
            return
        }
        self.peer = peer
        answerSent = false
        connected = false
        peer.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp)) { [weak self] error in
            guard let self = self, error == nil else { DispatchQueue.main.async { self?.onFailed?() }; return }
            peer.answer(for: constraints) { answer, error in
                guard let answer = answer, error == nil else { DispatchQueue.main.async { self.onFailed?() }; return }
                peer.setLocalDescription(answer) { error in
                    guard error == nil else { DispatchQueue.main.async { self.onFailed?() }; return }
                    // Candidates are gathered in well under a second; send what there is by then
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.sendAnswer() }
                }
            }
        }
    }

    private func sendAnswer() {
        guard !answerSent, let sdp = peer?.localDescription?.sdp else { return }
        answerSent = true
        onAnswer?(sdp)
    }

    private static func channelConfig(_ id: Int) -> RTCDataChannelConfiguration {
        let config = RTCDataChannelConfiguration()
        config.isNegotiated = true
        config.channelId = Int32(id)
        config.isOrdered = false
        config.maxRetransmits = 0
        return config
    }

    /// The channel this phone publishes its states on.
    func publish(id: Int) {
        guard let peer = peer else { return }
        out?.close()
        out = peer.dataChannel(forLabel: "s", configuration: FastLink.channelConfig(id))
        out?.delegate = self
    }

    /// The friend's published channel, as forwarded to this phone.
    func subscribe(id: Int) {
        guard let peer = peer else { return }
        incoming?.delegate = nil
        incoming?.close()
        incoming = peer.dataChannel(forLabel: "s-in", configuration: FastLink.channelConfig(id))
        incoming?.delegate = self
    }

    func send(_ data: Data) {
        guard let out = out, out.readyState == .open else { return }
        out.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    func close() {
        out?.delegate = nil
        incoming?.delegate = nil
        out?.close()
        incoming?.close()
        out = nil
        incoming = nil
        transport = nil
        peer?.delegate = nil
        peer?.close()
        peer = nil
        connected = false
    }
}

extension FastLink: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        guard newState == .complete else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.peer === peerConnection else { return }
            self.sendAnswer()
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.peer === peerConnection else { return }
            switch newState {
            case .connected:
                if !self.connected {
                    self.connected = true
                    self.onConnected?()
                }
            case .failed, .closed:
                self.onFailed?()
            default:
                break
            }
        }
    }

    /// The SFU's own transport channel ("server-events"): kept so it is not dropped.
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        DispatchQueue.main.async { [weak self] in self?.transport = dataChannel }
    }
}

extension FastLink: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        let state = dataChannel.readyState
        DispatchQueue.main.async { [weak self] in
            guard let self = self, dataChannel === self.incoming else { return }
            if state == .open { self.onReceiving?(true) }
            if state == .closed { self.onReceiving?(false) }
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let data = buffer.data
        DispatchQueue.main.async { [weak self] in
            guard let self = self, dataChannel === self.incoming else { return }
            self.onMessage?(data)
        }
    }
}

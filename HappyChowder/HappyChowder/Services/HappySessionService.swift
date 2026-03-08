import Foundation
import SocketIO

// MARK: - Delegate Protocol

protocol HappySessionServiceDelegate: AnyObject {
    func serviceDidConnect()
    func serviceDidDisconnect()
    func serviceDidReceiveTextDelta(_ text: String)
    func serviceDidReceiveThinkingDelta(_ text: String)
    func serviceDidReceiveToolCallStart(callId: String, name: String, title: String, description: String, args: [String: Any])
    func serviceDidReceiveToolCallEnd(callId: String)
    func serviceDidReceiveTurnEnd(status: String)
    func serviceDidReceiveServiceMessage(_ text: String)
    func serviceDidFinishMessage()
    func serviceDidReceiveError(_ error: Error)
    func serviceDidLog(_ message: String)
}

// MARK: - Service

final class HappySessionService {

    weak var delegate: HappySessionServiceDelegate?

    private let serverURL: String
    private let authToken: String
    private let encryption: EncryptionService

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var isConnected = false

    /// The currently active session ID.
    private(set) var activeSessionId: String?

    /// Last known update sequence number for resuming after reconnect.
    private var lastUpdateSeq: Int = 0

    /// Tracks processed message IDs to prevent duplicate handling.
    private var processedMessageIds: Set<String> = []

    init(serverURL: String, authToken: String, encryption: EncryptionService) {
        self.serverURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.authToken = authToken
        self.encryption = encryption
    }

    // MARK: - Connection

    func connect() {
        guard manager == nil else { return }

        guard let url = URL(string: serverURL) else {
            delegate?.serviceDidReceiveError(HappySessionError.invalidURL)
            return
        }

        log("Connecting to \(serverURL)")

        manager = SocketManager(socketURL: url, config: [
            .path("/v1/updates"),
            .connectParams(["token": authToken, "clientType": "user-scoped"]),
            .forceWebsockets(true),
            .reconnects(true),
            .reconnectWait(1),
            .reconnectWaitMax(5),
            .log(false)
        ])

        socket = manager?.defaultSocket
        setupEventHandlers()
        socket?.connect()
    }

    func disconnect() {
        log("Disconnecting")
        socket?.disconnect()
        socket = nil
        manager?.disconnect()
        manager = nil
        isConnected = false
    }

    // MARK: - Session Management

    /// Set the active session and initialize its encryption key.
    func setActiveSession(_ session: HappySession) throws {
        activeSessionId = session.id

        if let encKey = session.dataEncryptionKey, !encKey.isEmpty {
            if !encryption.hasSessionKey(forSession: session.id) {
                let aesKey = try encryption.decryptSessionKey(encryptedBase64: encKey)
                encryption.setSessionKey(aesKey, forSession: session.id)
            }
        }

        // Fetch recent messages for this session
        fetchRecentMessages()
    }

    // MARK: - Send Message

    func sendMessage(_ text: String) {
        guard let sessionId = activeSessionId else {
            log("No active session")
            return
        }

        let envelope = createUserEnvelope(text: text)

        do {
            let data = try JSONEncoder().encode(DecryptedMessageContent(role: "session", content: envelope))
            let encrypted = try encryption.encryptMessage(data, sessionId: sessionId)
            let localId = UUID().uuidString

            let body: [String: Any] = [
                "content": ["c": encrypted.c, "t": encrypted.t],
                "localId": localId
            ]

            postJSON(path: "/v3/sessions/\(sessionId)/messages", body: body) { [weak self] result in
                switch result {
                case .success:
                    self?.log("Message sent")
                case .failure(let error):
                    self?.log("Failed to send: \(error.localizedDescription)")
                    self?.delegate?.serviceDidReceiveError(error)
                }
            }
        } catch {
            log("Encryption error: \(error.localizedDescription)")
            delegate?.serviceDidReceiveError(error)
        }
    }

    // MARK: - Fetch Messages

    func fetchRecentMessages(limit: Int = 50) {
        guard let sessionId = activeSessionId else { return }

        let path = "/v3/sessions/\(sessionId)/messages?limit=\(limit)&after_seq=\(lastUpdateSeq)"
        getJSON(path: path) { [weak self] (result: Result<[SessionMessageResponse], Error>) in
            switch result {
            case .success(let messages):
                self?.processMessages(messages, sessionId: sessionId)
            case .failure(let error):
                self?.log("Fetch failed: \(error.localizedDescription)")
            }
        }
    }

    /// Fetch the list of sessions from the server.
    func fetchSessions(completion: @escaping (Result<[HappySession], Error>) -> Void) {
        getJSON(path: "/v3/sessions") { completion($0) }
    }

    // MARK: - Socket Event Handlers

    private func setupEventHandlers() {
        guard let socket else { return }

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            self?.log("Socket connected")
            self?.isConnected = true
            DispatchQueue.main.async {
                self?.delegate?.serviceDidConnect()
            }
        }

        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            self?.log("Socket disconnected")
            self?.isConnected = false
            DispatchQueue.main.async {
                self?.delegate?.serviceDidDisconnect()
            }
        }

        socket.on(clientEvent: .error) { [weak self] data, _ in
            let msg = (data.first as? String) ?? "Unknown socket error"
            self?.log("Socket error: \(msg)")
        }

        // Handle update events (sequenced, persistent)
        socket.on("update") { [weak self] data, _ in
            guard let self, let dict = data.first as? [String: Any] else { return }
            self.handleUpdateEvent(dict)
        }

        // Handle ephemeral events (transient, e.g. typing indicators)
        socket.on("ephemeral") { [weak self] data, _ in
            guard let self, let dict = data.first as? [String: Any] else { return }
            self.handleEphemeralEvent(dict)
        }
    }

    private func handleUpdateEvent(_ dict: [String: Any]) {
        guard let bodyDict = dict["body"] as? [String: Any],
              let type = bodyDict["t"] as? String else { return }

        if let seq = dict["seq"] as? Int {
            lastUpdateSeq = max(lastUpdateSeq, seq)
        }

        switch type {
        case "new-message":
            guard let sid = bodyDict["sid"] as? String,
                  sid == activeSessionId,
                  let messageDict = bodyDict["message"] as? [String: Any] else { return }

            do {
                let messageData = try JSONSerialization.data(withJSONObject: messageDict)
                let message = try JSONDecoder().decode(SessionMessageResponse.self, from: messageData)

                guard !processedMessageIds.contains(message.id) else { return }
                processedMessageIds.insert(message.id)

                processMessages([message], sessionId: sid)
            } catch {
                log("Failed to parse update message: \(error.localizedDescription)")
            }

        default:
            break
        }
    }

    private func handleEphemeralEvent(_ dict: [String: Any]) {
        // Ephemeral events can carry real-time activity hints
        // For now we rely on the persistent message stream
    }

    // MARK: - Message Processing

    private func processMessages(_ messages: [SessionMessageResponse], sessionId: String) {
        for message in messages.sorted(by: { $0.seq < $1.seq }) {
            do {
                let envelope = try encryption.decryptEnvelope(from: message, sessionId: sessionId)
                processEnvelope(envelope)
            } catch {
                log("Decrypt failed for message \(message.id): \(error.localizedDescription)")
            }
        }
    }

    private func processEnvelope(_ envelope: SessionEnvelope) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            switch envelope.ev {
            case .text(let textEvent):
                if textEvent.thinking == true {
                    self.delegate?.serviceDidReceiveThinkingDelta(textEvent.text)
                } else if envelope.role == "agent" {
                    self.delegate?.serviceDidReceiveTextDelta(textEvent.text)
                }

            case .toolCallStart(let toolEvent):
                let args = toolEvent.args.mapValues { $0.value }
                self.delegate?.serviceDidReceiveToolCallStart(
                    callId: toolEvent.call,
                    name: toolEvent.name,
                    title: toolEvent.title,
                    description: toolEvent.description,
                    args: args
                )

            case .toolCallEnd(let endEvent):
                self.delegate?.serviceDidReceiveToolCallEnd(callId: endEvent.call)

            case .turnEnd(let turnEnd):
                self.delegate?.serviceDidReceiveTurnEnd(status: turnEnd.status)
                self.delegate?.serviceDidFinishMessage()

            case .service(let serviceEvent):
                self.delegate?.serviceDidReceiveServiceMessage(serviceEvent.text)

            case .start, .turnStart, .stop, .file:
                break
            }
        }
    }

    // MARK: - Envelope Creation

    private func createUserEnvelope(text: String) -> SessionEnvelope {
        SessionEnvelope(
            id: UUID().uuidString,
            time: Date().timeIntervalSince1970 * 1000,
            role: "user",
            turn: nil,
            subagent: nil,
            ev: .text(SessionTextEvent(t: "text", text: text, thinking: nil))
        )
    }

    // MARK: - HTTP Helpers

    private func postJSON(path: String, body: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: "\(serverURL)\(path)") else {
            completion(.failure(HappySessionError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                completion(.failure(HappySessionError.serverError))
                return
            }
            completion(.success(()))
        }.resume()
    }

    private func getJSON<T: Decodable>(path: String, completion: @escaping (Result<T, Error>) -> Void) {
        guard let url = URL(string: "\(serverURL)\(path)") else {
            completion(.failure(HappySessionError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let data else {
                completion(.failure(HappySessionError.noData))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func log(_ msg: String) {
        print("[HappySession] \(msg)")
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.serviceDidLog(msg)
        }
    }
}

enum HappySessionError: LocalizedError {
    case invalidURL
    case serverError
    case noData
    case noActiveSession

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .serverError: return "Server returned an error"
        case .noData: return "No data received"
        case .noActiveSession: return "No active session"
        }
    }
}

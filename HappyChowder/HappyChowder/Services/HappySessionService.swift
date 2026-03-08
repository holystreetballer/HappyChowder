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
    // New delegate methods
    func serviceDidReceivePermissionRequests(_ requests: [String: PermissionRequest])
    func serviceDidReceiveUsageUpdate(sessionId: String, tokens: [String: Double], cost: [String: Double])
    func serviceDidReceiveMachineUpdate(machineId: String, active: Bool, activeAt: Double)
    func serviceDidReceiveSessionMetadata(_ metadata: SessionMetadata, forSession sessionId: String)
    func serviceDidReceiveSessionsList(_ sessions: [HappySession])
    func serviceDidReceiveMachinesList(_ machines: [HappyMachine])
}

// Default implementations for optional delegate methods
extension HappySessionServiceDelegate {
    func serviceDidReceivePermissionRequests(_ requests: [String: PermissionRequest]) {}
    func serviceDidReceiveUsageUpdate(sessionId: String, tokens: [String: Double], cost: [String: Double]) {}
    func serviceDidReceiveMachineUpdate(machineId: String, active: Bool, activeAt: Double) {}
    func serviceDidReceiveSessionMetadata(_ metadata: SessionMetadata, forSession sessionId: String) {}
    func serviceDidReceiveSessionsList(_ sessions: [HappySession]) {}
    func serviceDidReceiveMachinesList(_ machines: [HappyMachine]) {}
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

    /// Cached sessions list.
    private(set) var sessions: [HappySession] = []

    /// Cached machines.
    private(set) var machines: [String: HappyMachine] = [:]

    /// Current agent state version per session.
    private var agentStateVersions: [String: Int] = [:]

    /// Current metadata version per session.
    private var metadataVersions: [String: Int] = [:]

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

        // Store metadata version
        if let v = session.metadataVersion {
            metadataVersions[session.id] = v
        }
        if let v = session.agentStateVersion {
            agentStateVersions[session.id] = v
        }

        // Try to decrypt metadata if available
        if let metadataStr = session.metadata, !metadataStr.isEmpty {
            decryptAndDeliverMetadata(metadataStr, sessionId: session.id)
        }

        // Try to decrypt agent state if available
        if let stateStr = session.agentState, !stateStr.isEmpty {
            decryptAndDeliverAgentState(stateStr, sessionId: session.id)
        }

        // Fetch recent messages for this session
        fetchRecentMessages()
    }

    /// Switch to a different session.
    func switchToSession(id: String) throws {
        guard let session = sessions.first(where: { $0.id == id }) else {
            throw HappySessionError.noActiveSession
        }
        processedMessageIds.removeAll()
        lastUpdateSeq = 0
        try setActiveSession(session)
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

    /// Send a stop/cancel message to interrupt the current turn.
    func sendStopMessage() {
        sendMessage("STOP - Please stop what you're doing immediately.")
    }

    // MARK: - Permission Response

    /// Respond to a permission request by updating the agent state.
    func respondToPermission(requestId: String, decision: String) {
        guard let sessionId = activeSessionId else { return }
        let version = agentStateVersions[sessionId] ?? 0

        // Build the updated state with the completed request
        // We need to move the request from `requests` to `completedRequests`
        let completedRequest: [String: Any] = [
            "status": decision,
            "completedAt": Date().timeIntervalSince1970 * 1000,
            "decision": decision == "approved" ? "approved" : "denied"
        ]

        let stateUpdate: [String: Any] = [
            "completedRequests": [requestId: completedRequest]
        ]

        do {
            let stateData = try JSONSerialization.data(withJSONObject: stateUpdate)
            let encrypted = try encryption.encryptMessage(stateData, sessionId: sessionId)

            socket?.emitWithAck("update-state", [
                "sid": sessionId,
                "expectedVersion": version,
                "agentState": encrypted.c
            ]).timingOut(after: 10) { [weak self] data in
                guard let response = data.first as? [String: Any] else { return }
                let result = response["result"] as? String
                if result == "success", let newVersion = response["version"] as? Int {
                    self?.agentStateVersions[sessionId] = newVersion
                    self?.log("Permission \(decision) for \(requestId)")
                } else {
                    self?.log("Permission response failed: \(result ?? "unknown")")
                }
            }
        } catch {
            log("Failed to encrypt permission response: \(error.localizedDescription)")
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
        getJSON(path: "/v3/sessions") { [weak self] (result: Result<[HappySession], Error>) in
            if case .success(let sessions) = result {
                self?.sessions = sessions
                // Initialize encryption keys for all sessions
                for session in sessions {
                    if let encKey = session.dataEncryptionKey, !encKey.isEmpty,
                       !(self?.encryption.hasSessionKey(forSession: session.id) ?? true) {
                        do {
                            let aesKey = try self?.encryption.decryptSessionKey(encryptedBase64: encKey)
                            if let aesKey {
                                self?.encryption.setSessionKey(aesKey, forSession: session.id)
                            }
                        } catch {
                            self?.log("Failed to decrypt session key for \(session.id): \(error.localizedDescription)")
                        }
                    }
                }
                DispatchQueue.main.async {
                    self?.delegate?.serviceDidReceiveSessionsList(sessions)
                }
            }
            completion(result)
        }
    }

    /// Fetch machines from the server.
    func fetchMachines() {
        getJSON(path: "/v3/machines") { [weak self] (result: Result<[HappyMachineResponse], Error>) in
            switch result {
            case .success(let machineResponses):
                var resolvedMachines: [HappyMachine] = []
                for resp in machineResponses {
                    var machine = HappyMachine(
                        id: resp.id,
                        metadata: nil,
                        daemonState: nil,
                        active: resp.active ?? false,
                        activeAt: resp.activeAt ?? 0,
                        metadataVersion: resp.metadataVersion ?? 0,
                        daemonStateVersion: resp.daemonStateVersion ?? 0
                    )

                    // Try to decrypt metadata
                    if let metaStr = resp.metadata, !metaStr.isEmpty,
                       let encKey = resp.dataEncryptionKey, !encKey.isEmpty {
                        do {
                            if !(self?.encryption.hasSessionKey(forSession: resp.id) ?? true) {
                                let aesKey = try self?.encryption.decryptSessionKey(encryptedBase64: encKey)
                                if let aesKey {
                                    self?.encryption.setSessionKey(aesKey, forSession: resp.id)
                                }
                            }
                            let content = EncryptedContent(c: metaStr, t: "encrypted")
                            if let plaintext = try? self?.encryption.decryptMessage(encryptedContent: content, sessionId: resp.id) {
                                machine.metadata = try? JSONDecoder().decode(MachineMetadata.self, from: plaintext)
                            }
                        } catch {
                            self?.log("Failed to decrypt machine metadata: \(error.localizedDescription)")
                        }
                    }

                    self?.machines[resp.id] = machine
                    resolvedMachines.append(machine)
                }
                DispatchQueue.main.async {
                    self?.delegate?.serviceDidReceiveMachinesList(resolvedMachines)
                }
            case .failure(let error):
                self?.log("Failed to fetch machines: \(error.localizedDescription)")
            }
        }
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

        // Handle ephemeral events (transient)
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

        case "update-session":
            guard let sid = bodyDict["id"] as? String else { return }

            // Handle metadata update
            if let metaDict = bodyDict["metadata"] as? [String: Any],
               let metaValue = metaDict["value"] as? String,
               let metaVersion = metaDict["version"] as? Int {
                let currentVersion = metadataVersions[sid] ?? 0
                if metaVersion > currentVersion {
                    metadataVersions[sid] = metaVersion
                    decryptAndDeliverMetadata(metaValue, sessionId: sid)
                }
            }

            // Handle agent state update (permissions)
            if let stateDict = bodyDict["agentState"] as? [String: Any],
               let stateVersion = stateDict["version"] as? Int {
                let currentVersion = agentStateVersions[sid] ?? 0
                if stateVersion > currentVersion {
                    agentStateVersions[sid] = stateVersion
                    if let stateValue = stateDict["value"] as? String {
                        decryptAndDeliverAgentState(stateValue, sessionId: sid)
                    }
                }
            }

        case "update-machine":
            guard let machineId = bodyDict["machineId"] as? String else { return }
            let active = bodyDict["active"] as? Bool
            let activeAt = bodyDict["activeAt"] as? Double

            if let active, let activeAt {
                machines[machineId]?.active = active
                machines[machineId]?.activeAt = activeAt
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.serviceDidReceiveMachineUpdate(machineId: machineId, active: active, activeAt: activeAt)
                }
            }

        default:
            break
        }
    }

    private func handleEphemeralEvent(_ dict: [String: Any]) {
        guard let type = dict["type"] as? String else { return }

        switch type {
        case "activity":
            // Session activity indicator (thinking state)
            break

        case "machine-activity":
            guard let machineId = dict["id"] as? String,
                  let active = dict["active"] as? Bool,
                  let activeAt = dict["activeAt"] as? Double else { return }
            machines[machineId]?.active = active
            machines[machineId]?.activeAt = activeAt
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.serviceDidReceiveMachineUpdate(machineId: machineId, active: active, activeAt: activeAt)
            }

        case "usage":
            guard let sessionId = dict["id"] as? String,
                  let tokens = dict["tokens"] as? [String: Double],
                  let cost = dict["cost"] as? [String: Double] else { return }
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.serviceDidReceiveUsageUpdate(sessionId: sessionId, tokens: tokens, cost: cost)
            }

        default:
            break
        }
    }

    // MARK: - Metadata & State Decryption

    private func decryptAndDeliverMetadata(_ encryptedValue: String, sessionId: String) {
        guard encryption.hasSessionKey(forSession: sessionId) else { return }
        do {
            let content = EncryptedContent(c: encryptedValue, t: "encrypted")
            let plaintext = try encryption.decryptMessage(encryptedContent: content, sessionId: sessionId)
            let metadata = try JSONDecoder().decode(SessionMetadata.self, from: plaintext)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.serviceDidReceiveSessionMetadata(metadata, forSession: sessionId)
            }
        } catch {
            log("Failed to decrypt metadata for \(sessionId): \(error.localizedDescription)")
        }
    }

    private func decryptAndDeliverAgentState(_ encryptedValue: String, sessionId: String) {
        guard sessionId == activeSessionId, encryption.hasSessionKey(forSession: sessionId) else { return }
        do {
            let content = EncryptedContent(c: encryptedValue, t: "encrypted")
            let plaintext = try encryption.decryptMessage(encryptedContent: content, sessionId: sessionId)
            let state = try JSONDecoder().decode(AgentState.self, from: plaintext)
            if let requests = state.requests, !requests.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.serviceDidReceivePermissionRequests(requests)
                }
            }
        } catch {
            log("Failed to decrypt agent state for \(sessionId): \(error.localizedDescription)")
        }
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

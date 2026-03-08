import Foundation

// MARK: - Session Envelope (matches happy-wire/sessionProtocol.ts)

/// A single event in a session, wrapped with metadata.
struct SessionEnvelope: Codable {
    let id: String
    let time: Double
    let role: String        // "user" or "agent"
    let turn: String?
    let subagent: String?
    let ev: SessionEvent
}

/// The discriminated union of session event types.
enum SessionEvent: Codable {
    case text(SessionTextEvent)
    case service(SessionServiceEvent)
    case toolCallStart(SessionToolCallStartEvent)
    case toolCallEnd(SessionToolCallEndEvent)
    case file(SessionFileEvent)
    case turnStart
    case start(SessionStartEvent)
    case turnEnd(SessionTurnEndEvent)
    case stop

    private enum CodingKeys: String, CodingKey {
        case t
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .t)

        switch type {
        case "text":
            self = .text(try SessionTextEvent(from: decoder))
        case "service":
            self = .service(try SessionServiceEvent(from: decoder))
        case "tool-call-start":
            self = .toolCallStart(try SessionToolCallStartEvent(from: decoder))
        case "tool-call-end":
            self = .toolCallEnd(try SessionToolCallEndEvent(from: decoder))
        case "file":
            self = .file(try SessionFileEvent(from: decoder))
        case "turn-start":
            self = .turnStart
        case "start":
            self = .start(try SessionStartEvent(from: decoder))
        case "turn-end":
            self = .turnEnd(try SessionTurnEndEvent(from: decoder))
        case "stop":
            self = .stop
        default:
            throw DecodingError.dataCorruptedError(forKey: .t, in: container, debugDescription: "Unknown event type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let e):
            try container.encode("text", forKey: .t)
            try e.encode(to: encoder)
        case .service(let e):
            try container.encode("service", forKey: .t)
            try e.encode(to: encoder)
        case .toolCallStart(let e):
            try container.encode("tool-call-start", forKey: .t)
            try e.encode(to: encoder)
        case .toolCallEnd(let e):
            try container.encode("tool-call-end", forKey: .t)
            try e.encode(to: encoder)
        case .file(let e):
            try container.encode("file", forKey: .t)
            try e.encode(to: encoder)
        case .turnStart:
            try container.encode("turn-start", forKey: .t)
        case .start(let e):
            try container.encode("start", forKey: .t)
            try e.encode(to: encoder)
        case .turnEnd(let e):
            try container.encode("turn-end", forKey: .t)
            try e.encode(to: encoder)
        case .stop:
            try container.encode("stop", forKey: .t)
        }
    }
}

struct SessionTextEvent: Codable {
    let t: String
    let text: String
    let thinking: Bool?
}

struct SessionServiceEvent: Codable {
    let t: String
    let text: String
}

struct SessionToolCallStartEvent: Codable {
    let t: String
    let call: String        // call ID
    let name: String        // tool name
    let title: String
    let description: String
    let args: [String: AnyCodable]
}

struct SessionToolCallEndEvent: Codable {
    let t: String
    let call: String        // call ID
}

struct SessionFileEvent: Codable {
    let t: String
    let ref: String
    let name: String
    let size: Int
}

struct SessionStartEvent: Codable {
    let t: String
    let title: String?
}

struct SessionTurnEndEvent: Codable {
    let t: String
    let status: String      // "completed", "failed", "cancelled"
}

// MARK: - Wire Messages (matches happy-wire/messages.ts)

/// Encrypted content wrapper from the server.
struct EncryptedContent: Codable {
    let c: String           // base64-encoded ciphertext
    let t: String           // always "encrypted"
}

/// A session message as stored on the server.
struct SessionMessageResponse: Codable {
    let id: String
    let seq: Int
    let localId: String?
    let content: EncryptedContent
    let createdAt: Double
    let updatedAt: Double
}

/// The decrypted message content, wrapping a SessionEnvelope.
struct DecryptedMessageContent: Codable {
    let role: String
    let content: SessionEnvelope
}

// MARK: - Update Events (from Socket.IO)

struct CoreUpdateContainer: Codable {
    let id: String
    let seq: Int
    let body: CoreUpdateBody
    let createdAt: Double
}

enum CoreUpdateBody: Codable {
    case newMessage(UpdateNewMessage)
    case updateSession(UpdateSession)
    case updateMachine(UpdateMachine)

    private enum CodingKeys: String, CodingKey {
        case t
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .t)
        switch type {
        case "new-message":
            self = .newMessage(try UpdateNewMessage(from: decoder))
        case "update-session":
            self = .updateSession(try UpdateSession(from: decoder))
        case "update-machine":
            self = .updateMachine(try UpdateMachine(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .t, in: container, debugDescription: "Unknown update type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .newMessage(let m): try m.encode(to: encoder)
        case .updateSession(let s): try s.encode(to: encoder)
        case .updateMachine(let m): try m.encode(to: encoder)
        }
    }
}

struct UpdateNewMessage: Codable {
    let t: String
    let sid: String
    let message: SessionMessageResponse
}

struct UpdateSession: Codable {
    let t: String
    let id: String
    let metadata: VersionedEncryptedValue?
    let agentState: VersionedNullableEncryptedValue?
}

struct VersionedEncryptedValue: Codable {
    let version: Int
    let value: String
}

struct VersionedNullableEncryptedValue: Codable {
    let version: Int
    let value: String?
}

struct UpdateMachine: Codable {
    let t: String
    let machineId: String
    let metadata: VersionedEncryptedValue?
    let daemonState: VersionedEncryptedValue?
    let active: Bool?
    let activeAt: Double?
}

// MARK: - Session List Response

struct HappySession: Codable, Identifiable {
    let id: String
    let title: String?
    let machineId: String?
    let createdAt: Double
    let updatedAt: Double
    let dataEncryptionKey: String?   // base64-encoded encrypted AES key
    let metadata: String?            // encrypted metadata
    let metadataVersion: Int?
    let agentState: String?          // encrypted agent state
    let agentStateVersion: Int?
    let seq: Int?
    let active: Bool?
    let activeAt: Double?
}

// MARK: - Session Metadata (decrypted)

struct SessionMetadata: Codable {
    var path: String?
    var host: String?
    var version: String?
    var name: String?
    var os: String?
    var summary: SessionSummaryInfo?
    var machineId: String?
    var tools: [String]?
    var homeDir: String?
    var flavor: String?

    struct SessionSummaryInfo: Codable {
        let text: String
        let updatedAt: Double
    }
}

// MARK: - Agent State (for permission requests)

struct AgentState: Codable {
    var controlledByUser: Bool?
    var requests: [String: PermissionRequest]?
    var completedRequests: [String: CompletedPermissionRequest]?
}

struct PermissionRequest: Codable, Identifiable {
    var id: String { _id ?? UUID().uuidString }
    private var _id: String?
    let tool: String
    let arguments: AnyCodable?
    let createdAt: Double

    private enum CodingKeys: String, CodingKey {
        case tool, arguments, createdAt
    }

    init(id: String, tool: String, arguments: AnyCodable?, createdAt: Double) {
        self._id = id
        self.tool = tool
        self.arguments = arguments
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self._id = nil
        self.tool = try container.decode(String.self, forKey: .tool)
        self.arguments = try container.decodeIfPresent(AnyCodable.self, forKey: .arguments)
        self.createdAt = try container.decode(Double.self, forKey: .createdAt)
    }
}

struct CompletedPermissionRequest: Codable {
    let tool: String
    let arguments: AnyCodable?
    let createdAt: Double
    let completedAt: Double
    let status: String   // "canceled", "denied", "approved"
}

// MARK: - Machine Types

struct HappyMachine: Identifiable {
    let id: String
    var metadata: MachineMetadata?
    var daemonState: MachineDaemonState?
    var active: Bool
    var activeAt: Double
    var metadataVersion: Int
    var daemonStateVersion: Int
}

struct MachineMetadata: Codable {
    let host: String
    let platform: String
    let happyCliVersion: String
    let homeDir: String
    let happyHomeDir: String?
    let happyLibDir: String?
}

struct MachineDaemonState: Codable {
    let status: String    // "running", "shutting-down"
    let pid: Int?
    let httpPort: Int?
    let startedAt: Double?
}

// MARK: - Machine List Response

struct HappyMachineResponse: Codable, Identifiable {
    let id: String
    let metadata: String?            // encrypted
    let metadataVersion: Int?
    let daemonState: String?         // encrypted
    let daemonStateVersion: Int?
    let dataEncryptionKey: String?
    let active: Bool?
    let activeAt: Double?
}

// MARK: - Usage Tracking

struct UsageEvent {
    let sessionId: String
    let key: String
    let tokens: [String: Double]
    let cost: [String: Double]
    let timestamp: Double
}

// MARK: - AnyCodable helper

/// Lightweight Codable wrapper for heterogeneous JSON values.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { value = s }
        else if let i = try? container.decode(Int.self) { value = i }
        else if let d = try? container.decode(Double.self) { value = d }
        else if let b = try? container.decode(Bool.self) { value = b }
        else if let arr = try? container.decode([AnyCodable].self) { value = arr.map { $0.value } }
        else if let dict = try? container.decode([String: AnyCodable].self) { value = dict.mapValues { $0.value } }
        else if container.decodeNil() { value = NSNull() }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let s as String: try container.encode(s)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let b as Bool: try container.encode(b)
        default: try container.encodeNil()
        }
    }

    var stringValue: String? { value as? String }
    var dictValue: [String: Any]? { value as? [String: Any] }
}

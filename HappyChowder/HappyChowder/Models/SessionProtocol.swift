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
}

struct UpdateMachine: Codable {
    let t: String
    let machineId: String
}

// MARK: - Session List Response

struct HappySession: Codable, Identifiable {
    let id: String
    let title: String?
    let machineId: String?
    let createdAt: Double
    let updatedAt: Double
    let dataEncryptionKey: String?   // base64-encoded encrypted AES key
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

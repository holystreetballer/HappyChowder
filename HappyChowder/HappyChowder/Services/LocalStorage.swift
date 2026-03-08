import UIKit

enum LocalStorage {
    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Chat History

    private static var chatHistoryURL: URL {
        documentsURL.appendingPathComponent("chat_history.json")
    }

    static func saveMessages(_ messages: [Message]) {
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: chatHistoryURL, options: .atomic)
        } catch {
            print("[LocalStorage] Failed to save messages: \(error)")
        }
    }

    static func loadMessages() -> [Message] {
        guard FileManager.default.fileExists(atPath: chatHistoryURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: chatHistoryURL)
            return try JSONDecoder().decode([Message].self, from: data)
        } catch {
            print("[LocalStorage] Failed to load messages: \(error)")
            return []
        }
    }

    static func deleteMessages() {
        try? FileManager.default.removeItem(at: chatHistoryURL)
    }

    // MARK: - Agent Avatar

    private static var avatarURL: URL {
        documentsURL.appendingPathComponent("agent_avatar.jpg")
    }

    static func saveAvatar(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        do {
            try data.write(to: avatarURL, options: .atomic)
        } catch {
            print("[LocalStorage] Failed to save avatar: \(error)")
        }
        SharedStorage.saveAvatar(image)
    }

    static func loadAvatar() -> UIImage? {
        guard FileManager.default.fileExists(atPath: avatarURL.path) else { return nil }
        return UIImage(contentsOfFile: avatarURL.path)
    }

    static func deleteAvatar() {
        try? FileManager.default.removeItem(at: avatarURL)
        SharedStorage.deleteAvatar()
    }

    // MARK: - Session Encryption Keys Cache

    private static var sessionKeysURL: URL {
        documentsURL.appendingPathComponent("session_keys.json")
    }

    static func saveSessionKeys(_ keys: [String: Data]) {
        do {
            let encoded = keys.mapValues { $0.base64EncodedString() }
            let data = try JSONEncoder().encode(encoded)
            try data.write(to: sessionKeysURL, options: .atomic)
        } catch {
            print("[LocalStorage] Failed to save session keys: \(error)")
        }
    }

    static func loadSessionKeys() -> [String: Data] {
        guard FileManager.default.fileExists(atPath: sessionKeysURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: sessionKeysURL)
            let encoded = try JSONDecoder().decode([String: String].self, from: data)
            return encoded.compactMapValues { Data(base64Encoded: $0) }
        } catch {
            print("[LocalStorage] Failed to load session keys: \(error)")
            return [:]
        }
    }
}

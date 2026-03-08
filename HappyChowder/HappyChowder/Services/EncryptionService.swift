import Foundation
import CryptoKit
import Sodium

/// Handles Happy's E2E encryption: HKDF key derivation, NaCl box keypair,
/// AES-256-GCM message encryption/decryption.
final class EncryptionService {

    private let masterSecret: Data
    private let contentKeyPair: Box.KeyPair
    private let sodium = Sodium()

    /// Decrypted AES keys per session, keyed by session ID.
    private var sessionKeys: [String: SymmetricKey] = [:]

    init(masterSecret: Data) throws {
        guard masterSecret.count == 32 else {
            throw EncryptionError.invalidMasterSecret
        }
        self.masterSecret = masterSecret

        // Derive content data key via HKDF
        let contentDataKey = EncryptionService.deriveKey(
            from: masterSecret,
            salt: "Happy EnCoder",
            info: "content"
        )

        // Derive X25519 keypair from seed
        guard let keyPair = Sodium().box.keyPair(seed: Bytes(contentDataKey)) else {
            throw EncryptionError.keypairDerivationFailed
        }
        self.contentKeyPair = keyPair
    }

    /// The public key used for identity on the Happy server.
    var publicKey: Data {
        Data(contentKeyPair.publicKey)
    }

    // MARK: - Key Derivation

    static func deriveKey(from secret: Data, salt: String, info: String) -> Data {
        let saltData = salt.data(using: .utf8)!
        let infoData = info.data(using: .utf8)!
        let symmetricKey = SymmetricKey(data: secret)
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: symmetricKey,
            salt: saltData,
            info: infoData,
            outputByteCount: 32
        )
        return derived.withUnsafeBytes { Data($0) }
    }

    // MARK: - Session Key Management

    /// Decrypt a per-session AES key that was encrypted with our public key (NaCl sealed box).
    func decryptSessionKey(encryptedBase64: String) throws -> Data {
        guard let encryptedData = Data(base64Encoded: encryptedBase64) else {
            throw EncryptionError.invalidBase64
        }

        // First byte is version (0)
        guard encryptedData.count > 1, encryptedData[0] == 0 else {
            throw EncryptionError.unsupportedVersion
        }

        let ciphertext = Bytes(encryptedData.dropFirst())

        // Decrypt using NaCl anonymous box (sealed box)
        guard let decrypted = sodium.box.open(
            anonymousCipherText: ciphertext,
            recipientPublicKey: contentKeyPair.publicKey,
            recipientSecretKey: contentKeyPair.secretKey
        ) else {
            throw EncryptionError.decryptionFailed
        }

        return Data(decrypted)
    }

    /// Initialize a session with its decrypted AES key.
    func setSessionKey(_ key: Data, forSession sessionId: String) {
        sessionKeys[sessionId] = SymmetricKey(data: key)
    }

    /// Check if a session key is loaded.
    func hasSessionKey(forSession sessionId: String) -> Bool {
        sessionKeys[sessionId] != nil
    }

    // MARK: - Message Encryption/Decryption (AES-256-GCM)

    /// Decrypt message content for a specific session.
    func decryptMessage(encryptedContent: EncryptedContent, sessionId: String) throws -> Data {
        guard let sessionKey = sessionKeys[sessionId] else {
            throw EncryptionError.noSessionKey
        }

        guard let cipherData = Data(base64Encoded: encryptedContent.c) else {
            throw EncryptionError.invalidBase64
        }

        // AES-256-GCM: nonce (12 bytes) + ciphertext + tag (16 bytes)
        guard cipherData.count > 28 else {
            throw EncryptionError.invalidCiphertext
        }

        let nonce = cipherData.prefix(12)
        let ciphertextAndTag = cipherData.dropFirst(12)

        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: ciphertextAndTag.dropLast(16),
            tag: ciphertextAndTag.suffix(16)
        )

        let plaintext = try AES.GCM.open(sealedBox, using: sessionKey)
        return plaintext
    }

    /// Encrypt a message for a specific session.
    func encryptMessage(_ data: Data, sessionId: String) throws -> EncryptedContent {
        guard let sessionKey = sessionKeys[sessionId] else {
            throw EncryptionError.noSessionKey
        }

        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: sessionKey, nonce: nonce)

        var combined = Data()
        combined.append(contentsOf: nonce)
        combined.append(sealedBox.ciphertext)
        combined.append(sealedBox.tag)

        return EncryptedContent(c: combined.base64EncodedString(), t: "encrypted")
    }

    /// Decrypt a session envelope from an encrypted message.
    func decryptEnvelope(from message: SessionMessageResponse, sessionId: String) throws -> SessionEnvelope {
        let plaintext = try decryptMessage(encryptedContent: message.content, sessionId: sessionId)

        // The plaintext is a JSON-encoded DecryptedMessageContent
        let decoder = JSONDecoder()
        let content = try decoder.decode(DecryptedMessageContent.self, from: plaintext)
        return content.content
    }
}

enum EncryptionError: LocalizedError {
    case invalidMasterSecret
    case keypairDerivationFailed
    case invalidBase64
    case unsupportedVersion
    case decryptionFailed
    case noSessionKey
    case invalidCiphertext

    var errorDescription: String? {
        switch self {
        case .invalidMasterSecret: return "Invalid master secret (must be 32 bytes)"
        case .keypairDerivationFailed: return "Failed to derive encryption keypair"
        case .invalidBase64: return "Invalid base64 encoding"
        case .unsupportedVersion: return "Unsupported encryption version"
        case .decryptionFailed: return "Decryption failed"
        case .noSessionKey: return "No encryption key for this session"
        case .invalidCiphertext: return "Invalid ciphertext format"
        }
    }
}

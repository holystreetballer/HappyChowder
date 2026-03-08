import Foundation

struct ConnectionConfig {
    private static let serverURLKey = "happyServerURL"
    private static let tokenKeychainKey = "happyAuthToken"
    private static let masterSecretKey = "happyMasterSecret"

    var serverURL: String {
        get { UserDefaults.standard.string(forKey: Self.serverURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.serverURLKey) }
    }

    var token: String {
        get { KeychainService.load(key: Self.tokenKeychainKey) ?? "" }
        set { KeychainService.save(key: Self.tokenKeychainKey, value: newValue) }
    }

    /// Base64-encoded 32-byte master secret from QR pairing.
    var masterSecret: String {
        get { KeychainService.load(key: Self.masterSecretKey) ?? "" }
        set { KeychainService.save(key: Self.masterSecretKey, value: newValue) }
    }

    var isConfigured: Bool {
        !serverURL.isEmpty && !token.isEmpty && !masterSecret.isEmpty
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: serverURLKey)
        KeychainService.delete(key: tokenKeychainKey)
        KeychainService.delete(key: masterSecretKey)
    }
}

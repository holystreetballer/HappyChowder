import Foundation
import SwiftUI

@Observable
final class AuthManager {
    static let shared = AuthManager()

    var isAuthenticated: Bool = false
    var serverURL: String = ""
    var errorMessage: String?

    private init() {
        let config = ConnectionConfig()
        isAuthenticated = config.isConfigured
        serverURL = config.serverURL
    }

    /// Complete the pairing process with data from a QR code.
    /// QR payload format: `happy://<serverURL>?secret=<base64>&token=<jwt>`
    func pair(from qrPayload: String) {
        guard let url = URLComponents(string: qrPayload) else {
            errorMessage = "Invalid QR code format"
            return
        }

        let secret = url.queryItems?.first(where: { $0.name == "secret" })?.value
        let token = url.queryItems?.first(where: { $0.name == "token" })?.value

        // Extract server URL from the host/scheme
        var serverAddr = ""
        if let scheme = url.scheme, scheme != "happy" {
            serverAddr = qrPayload.components(separatedBy: "?").first ?? ""
        } else if let host = url.host {
            // happy://host:port -> https://host:port
            let port = url.port.map { ":\($0)" } ?? ""
            serverAddr = "https://\(host)\(port)"
        }

        guard let secret, !secret.isEmpty,
              let token, !token.isEmpty,
              !serverAddr.isEmpty else {
            errorMessage = "QR code missing required fields (server, secret, token)"
            return
        }

        var config = ConnectionConfig()
        config.serverURL = serverAddr
        config.token = token
        config.masterSecret = secret
        self.serverURL = serverAddr

        isAuthenticated = true
        errorMessage = nil
    }

    /// Manual configuration for development/testing.
    func configure(serverURL: String, token: String, masterSecret: String) {
        var config = ConnectionConfig()
        config.serverURL = serverURL
        config.token = token
        config.masterSecret = masterSecret
        self.serverURL = serverURL
        isAuthenticated = true
        errorMessage = nil
    }

    func logout() {
        ConnectionConfig.clear()
        isAuthenticated = false
        serverURL = ""
    }
}

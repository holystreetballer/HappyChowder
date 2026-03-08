import SwiftUI

@main
struct HappyChowderApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var authManager = AuthManager.shared

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                SessionsRootView()
            } else {
                AuthView()
            }
        }
        .animation(.easeInOut, value: authManager.isAuthenticated)
    }
}

/// Shows the active session chat.
struct SessionsRootView: View {
    var body: some View {
        NavigationStack {
            ChatView()
        }
    }
}

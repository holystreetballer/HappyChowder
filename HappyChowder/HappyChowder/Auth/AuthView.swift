import SwiftUI

struct AuthView: View {
    @State private var authManager = AuthManager.shared
    @State private var showScanner = false
    @State private var showManualEntry = false

    // Manual entry fields
    @State private var manualServerURL = ""
    @State private var manualToken = ""
    @State private var manualSecret = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Logo area
                VStack(spacing: 12) {
                    Image(systemName: "bolt.horizontal.icloud.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue)

                    Text("HappyChowder")
                        .font(.system(size: 28, weight: .bold))

                    Text("Control Claude Code from your iPhone")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 16) {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundStyle(.white)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Button {
                        showManualEntry = true
                    } label: {
                        Text("Enter Manually")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.blue)
                    }

                    if let error = authManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                Text("Run `happy pair` on your Mac to get started")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 24)
            }
            .sheet(isPresented: $showScanner) {
                NavigationStack {
                    QRScannerView { code in
                        authManager.pair(from: code)
                        showScanner = false
                    }
                    .navigationTitle("Scan QR Code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showScanner = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showManualEntry) {
                NavigationStack {
                    Form {
                        Section("Server") {
                            TextField("Server URL", text: $manualServerURL)
                                .textContentType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        Section("Authentication") {
                            SecureField("Auth Token", text: $manualToken)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            SecureField("Master Secret (base64)", text: $manualSecret)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                    .navigationTitle("Manual Setup")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showManualEntry = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Connect") {
                                authManager.configure(
                                    serverURL: manualServerURL,
                                    token: manualToken,
                                    masterSecret: manualSecret
                                )
                                showManualEntry = false
                            }
                            .disabled(manualServerURL.isEmpty || manualToken.isEmpty || manualSecret.isEmpty)
                        }
                    }
                }
            }
        }
    }
}

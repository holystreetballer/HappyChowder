import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var isConnected: Bool = false
    var machineCount: Int = 0
    var onSaveConnection: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onLogout: (() -> Void)?
    var onShowMachines: (() -> Void)?
    var onShowCosts: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Connection card
                    NavigationLink {
                        ConnectionDetailView(onSave: { onSaveConnection?() })
                    } label: {
                        GlassCard {
                            HStack(spacing: 12) {
                                GlassIcon(systemName: "server.rack")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Happy Server")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(isConnected ? Color.green : Color.gray.opacity(0.5))
                                            .frame(width: 6, height: 6)
                                        Text(isConnected ? "Connected" : "Disconnected")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // Machines card
                    GlassCard {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onShowMachines?()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                GlassIcon(systemName: "desktopcomputer", size: 32, iconSize: 14)
                                Text("Machines")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if machineCount > 0 {
                                    Text("\(machineCount)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    // Costs card
                    GlassCard {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onShowCosts?()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                GlassIcon(systemName: "dollarsign.circle", size: 32, iconSize: 14)
                                Text("Cost Dashboard")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    // Developer section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Developer")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)
                            .padding(.top, 8)

                        GlassCard {
                            Button {
                                LiveActivityManager.shared.startDemo()
                            } label: {
                                HStack(spacing: 12) {
                                    GlassIcon(systemName: "platter.filled.bottom.and.arrow.down.iphone", size: 32, iconSize: 14)
                                    Text("Live Activity Demo")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                        }
                    }

                    // Data section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Data")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)
                            .padding(.top, 8)

                        GlassCard {
                            Button(role: .destructive) {
                                onClearHistory?()
                            } label: {
                                HStack {
                                    Text("Clear Chat History")
                                        .font(.system(size: 16))
                                    Spacer()
                                }
                            }
                        }

                        GlassCard {
                            Button(role: .destructive) {
                                onLogout?()
                            } label: {
                                HStack {
                                    Text("Disconnect & Logout")
                                        .font(.system(size: 16))
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Connection Detail

struct ConnectionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (() -> Void)?

    @State private var serverURL: String = ""
    @State private var token: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Server")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    GlassCard(padding: 0) {
                        GlassTextField(label: "URL", placeholder: "https://your-happy-server.com", text: $serverURL)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Authentication")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    GlassCard(padding: 0) {
                        HStack {
                            Text("Token")
                                .font(.system(size: 16))
                                .frame(width: 80, alignment: .leading)
                            SecureField("Token", text: $token)
                                .font(.system(size: 16))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                }

                GlassSaveButton(
                    disabled: serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    var config = ConnectionConfig()
                    config.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !token.isEmpty {
                        config.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    onSave?()
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Happy Server")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let config = ConnectionConfig()
            serverURL = config.serverURL
            token = config.token
        }
    }
}

// MARK: - Shared Glass Components

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}

struct GlassIcon: View {
    let systemName: String
    var size: CGFloat = 40
    var iconSize: CGFloat = 18

    var body: some View {
        Circle()
            .fill(Color(.systemGray5))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: iconSize))
                    .foregroundStyle(.secondary)
            )
    }
}

struct GlassTextField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .leading)
            TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                .font(.system(size: 16))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

struct GlassSaveButton: View {
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Save")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(disabled ? Color.blue.opacity(0.4) : .blue)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
        }
        .disabled(disabled)
    }
}

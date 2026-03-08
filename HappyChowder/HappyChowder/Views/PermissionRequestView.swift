import SwiftUI

struct PermissionRequestView: View {
    let requests: [PermissionDisplayItem]
    let onApprove: (String) -> Void
    let onDeny: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if requests.isEmpty {
                        ContentUnavailableView("No Pending Requests", systemImage: "checkmark.shield", description: Text("All permissions have been handled"))
                            .padding(.top, 60)
                    } else {
                        ForEach(requests) { request in
                            PermissionCard(request: request, onApprove: onApprove, onDeny: onDeny)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Permissions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct PermissionDisplayItem: Identifiable {
    let id: String
    let tool: String
    let description: String
    let args: [String: Any]?
    let createdAt: Date
}

struct PermissionCard: View {
    let request: PermissionDisplayItem
    let onApprove: (String) -> Void
    let onDeny: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: iconForTool(request.tool))
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)
                    .frame(width: 36, height: 36)
                    .background(Color.orange.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(request.tool)
                        .font(.system(size: 15, weight: .semibold))
                    Text(request.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if let args = request.args, !args.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(args.keys.prefix(3).sorted()), id: \.self) { key in
                        HStack(spacing: 4) {
                            Text(key + ":")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(String(describing: args[key] ?? ""))
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                Button {
                    onDeny(request.id)
                } label: {
                    Text("Deny")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    onApprove(request.id)
                } label: {
                    Text("Approve")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func iconForTool(_ tool: String) -> String {
        switch tool.lowercased() {
        case "bash", "exec": return "terminal"
        case "write", "edit", "apply_patch": return "doc.badge.plus"
        case "read": return "doc.text"
        case "webfetch", "web_fetch": return "globe"
        case "websearch", "web_search": return "magnifyingglass"
        default: return "gearshape"
        }
    }
}

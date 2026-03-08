import SwiftUI

struct SessionsListView: View {
    let sessions: [SessionListItem]
    let activeSessionId: String?
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if sessions.isEmpty {
                ContentUnavailableView("No Sessions", systemImage: "bubble.left.and.bubble.right", description: Text("No active Claude Code sessions found"))
            } else {
                ForEach(groupedByMachine, id: \.machine) { group in
                    Section {
                        ForEach(group.sessions) { session in
                            SessionRow(session: session, isActive: session.id == activeSessionId)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelect(session.id)
                                    dismiss()
                                }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 11))
                            Text(group.machine)
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    private var groupedByMachine: [(machine: String, sessions: [SessionListItem])] {
        let grouped = Dictionary(grouping: sessions) { $0.machineName ?? "Unknown" }
        return grouped.map { (machine: $0.key, sessions: $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
            .sorted { $0.sessions.first?.updatedAt ?? 0 > $1.sessions.first?.updatedAt ?? 0 }
    }
}

struct SessionListItem: Identifiable {
    let id: String
    let summary: String?
    let path: String?
    let machineName: String?
    let isActive: Bool
    let updatedAt: Double
    let costTotal: Double?
}

struct SessionRow: View {
    let session: SessionListItem
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(session.isActive ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.summary ?? "Session")
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                if let path = session.path {
                    Text(path)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 16))
            }

            Text(timeAgo(session.updatedAt))
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func timeAgo(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp / 1000)
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

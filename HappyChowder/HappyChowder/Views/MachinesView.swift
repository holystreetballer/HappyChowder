import SwiftUI

struct MachinesView: View {
    let machines: [MachineDisplayItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if machines.isEmpty {
                        ContentUnavailableView("No Machines", systemImage: "desktopcomputer.trianglebadge.exclamationmark", description: Text("No machines connected to your Happy server"))
                            .padding(.top, 60)
                    } else {
                        ForEach(machines) { machine in
                            MachineCard(machine: machine)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Machines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct MachineDisplayItem: Identifiable {
    let id: String
    let host: String
    let platform: String
    let isOnline: Bool
    let daemonStatus: String?
    let cliVersion: String?
    let sessionCount: Int
    let lastActiveAt: Date?
}

struct MachineCard: View {
    let machine: MachineDisplayItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: platformIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(machine.isOnline ? .blue : .secondary)
                    .frame(width: 40, height: 40)
                    .background(
                        (machine.isOnline ? Color.blue : Color.gray).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(machine.host)
                            .font(.system(size: 15, weight: .semibold))
                        Circle()
                            .fill(machine.isOnline ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 7, height: 7)
                    }
                    Text(machine.isOnline ? (machine.daemonStatus ?? "Online") : "Offline")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if machine.sessionCount > 0 {
                    VStack(spacing: 2) {
                        Text("\(machine.sessionCount)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("sessions")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 16) {
                if let version = machine.cliVersion {
                    Label(version, systemImage: "tag")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Label(machine.platform, systemImage: "cpu")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if let lastActive = machine.lastActiveAt {
                    Label(lastActive.formatted(.relative(presentation: .named)), systemImage: "clock")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var platformIcon: String {
        switch machine.platform.lowercased() {
        case let p where p.contains("darwin") || p.contains("mac"): return "laptopcomputer"
        case let p where p.contains("linux"): return "server.rack"
        case let p where p.contains("win"): return "pc"
        default: return "desktopcomputer"
        }
    }
}

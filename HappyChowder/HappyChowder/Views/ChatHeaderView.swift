import SwiftUI

struct ChatHeaderView: View {
    let botName: String
    let isOnline: Bool
    var taskSummary: String?
    var pendingPermissionCount: Int = 0
    var totalCost: Double = 0
    var onSettingsTapped: (() -> Void)?
    var onDebugTapped: (() -> Void)?
    var onSessionsTapped: (() -> Void)?
    var onCostTapped: (() -> Void)?
    var onMetadataTapped: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    onMetadataTapped?()
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(botName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(isOnline ? Color.green : Color.gray.opacity(0.5))
                                    .frame(width: 6, height: 6)
                                Text(isOnline ? "Online" : "Offline")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.gray)
                                if let summary = taskSummary {
                                    Text("·").font(.system(size: 13)).foregroundStyle(.gray)
                                    Text(summary)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Cost badge
                if totalCost > 0 {
                    Button { onCostTapped?() } label: {
                        Text(String(format: "$%.2f", totalCost))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(.systemGray6)))
                    }
                }

                // Sessions button
                Button { onSessionsTapped?() } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16))
                        .foregroundStyle(.gray)
                }

                // Permission badge
                if pendingPermissionCount > 0 {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                        .symbolEffect(.pulse)
                }

                Button { onSettingsTapped?() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .foregroundStyle(.gray)
                }

                Button { onDebugTapped?() } label: {
                    Image(systemName: "ant")
                        .font(.system(size: 16))
                        .foregroundStyle(.gray)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Color(.systemGray5))
                .frame(height: 0.5)
        }
        .background {
            Color.white.opacity(0.75)
                .background(.thinMaterial)
                .ignoresSafeArea(edges: .top)
        }
    }
}

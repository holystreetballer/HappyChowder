import SwiftUI

struct ChatHeaderView: View {
    let botName: String
    let isOnline: Bool
    var taskSummary: String?
    var onSettingsTapped: (() -> Void)?
    var onDebugTapped: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    onSettingsTapped?()
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

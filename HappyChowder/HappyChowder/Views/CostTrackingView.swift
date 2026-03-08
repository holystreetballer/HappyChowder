import SwiftUI

struct CostTrackingView: View {
    let totalCost: Double
    let sessionCosts: [SessionCostItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Total cost card
                    VStack(spacing: 8) {
                        Text("Total Spend")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        Text(formatCost(totalCost))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                    // Token breakdown
                    if !sessionCosts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("By Session")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 4)

                            VStack(spacing: 0) {
                                ForEach(sessionCosts) { item in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .font(.system(size: 15, weight: .medium))
                                                .lineLimit(1)
                                            Text("\(item.inputTokens + item.outputTokens) tokens")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(formatCost(item.cost))
                                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)

                                    if item.id != sessionCosts.last?.id {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Costs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.01 { return "$0.00" }
        return String(format: "$%.2f", cost)
    }
}

struct SessionCostItem: Identifiable {
    let id: String
    let name: String
    let cost: Double
    let inputTokens: Int
    let outputTokens: Int
}

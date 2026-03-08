import SwiftUI

struct SessionMetadataView: View {
    let metadata: SessionMetadataDisplay?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let meta = metadata {
                    VStack(spacing: 12) {
                        // Session info
                        MetadataSection(title: "Session") {
                            if let name = meta.name {
                                MetadataRow(label: "Name", value: name)
                            }
                            if let summary = meta.summary {
                                MetadataRow(label: "Summary", value: summary)
                            }
                            if let path = meta.workingDirectory {
                                MetadataRow(label: "Directory", value: path, monospaced: true)
                            }
                        }

                        // Environment
                        MetadataSection(title: "Environment") {
                            if let host = meta.host {
                                MetadataRow(label: "Host", value: host)
                            }
                            if let os = meta.os {
                                MetadataRow(label: "OS", value: os)
                            }
                            if let version = meta.version {
                                MetadataRow(label: "Version", value: version)
                            }
                            if let flavor = meta.flavor {
                                MetadataRow(label: "Flavor", value: flavor)
                            }
                        }

                        // Tools
                        if let tools = meta.tools, !tools.isEmpty {
                            MetadataSection(title: "Available Tools (\(tools.count))") {
                                FlowLayout(spacing: 6) {
                                    ForEach(tools, id: \.self) { tool in
                                        Text(tool)
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color(.systemGray6), in: Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                } else {
                    ContentUnavailableView("No Metadata", systemImage: "info.circle", description: Text("Session metadata is not available yet"))
                        .padding(.top, 60)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Session Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct SessionMetadataDisplay {
    let name: String?
    let summary: String?
    let workingDirectory: String?
    let host: String?
    let os: String?
    let version: String?
    let flavor: String?
    let tools: [String]?
    let machineId: String?
}

struct MetadataSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 14, design: monospaced ? .monospaced : .default))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

import SwiftUI

struct QuickReplyBar: View {
    let onSend: (String) -> Void
    let isLoading: Bool

    private let quickReplies: [(label: String, message: String, icon: String)] = [
        ("Continue", "Continue", "arrow.right"),
        ("Yes", "Yes", "checkmark"),
        ("No", "No", "xmark"),
        ("Explain", "Can you explain what you just did?", "questionmark.circle"),
        ("Undo", "Please undo the last change", "arrow.uturn.backward"),
        ("Status", "What's the current status?", "info.circle"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickReplies, id: \.label) { reply in
                    Button {
                        onSend(reply.message)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: reply.icon)
                                .font(.system(size: 12))
                            Text(reply.label)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(isLoading ? Color(.systemGray3) : .blue)
                        .background(
                            Capsule()
                                .fill(isLoading ? Color(.systemGray6) : Color.blue.opacity(0.1))
                        )
                    }
                    .disabled(isLoading)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 36)
    }
}

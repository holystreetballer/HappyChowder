import Foundation

enum ToolCategory: String {
    case thinking
    case terminal
    case browser
    case network
    case fileSystem
    case search
    case generic

    var iconName: String {
        switch self {
        case .thinking:   return "arrow.turn.down.right"
        case .terminal:   return "terminal"
        case .browser:    return "globe"
        case .network:    return "arrow.down.circle"
        case .fileSystem: return "doc"
        case .search:     return "magnifyingglass"
        case .generic:    return "gearshape"
        }
    }
}

struct ActivityStep: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let type: StepType
    let label: String
    var detail: String
    var status: Status = .inProgress
    var completedAt: Date?
    var toolCategory: ToolCategory = .generic

    enum StepType {
        case thinking
        case toolCall
    }

    enum Status {
        case inProgress
        case completed
        case failed
    }

    var elapsed: TimeInterval {
        if let completedAt {
            return completedAt.timeIntervalSince(timestamp)
        }
        return Date().timeIntervalSince(timestamp)
    }
}

struct AgentActivity {
    var currentLabel: String = ""
    var thinkingText: String = ""
    var steps: [ActivityStep] = []

    var completedSteps: [ActivityStep] {
        steps.filter { $0.status == .completed }
    }

    mutating func finishCurrentSteps() {
        let now = Date()
        for i in steps.indices where steps[i].status == .inProgress {
            steps[i].status = .completed
            steps[i].completedAt = now
        }
    }
}

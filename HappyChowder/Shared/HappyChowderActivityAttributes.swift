import ActivityKit
import Foundation

struct HappyChowderActivityAttributes: ActivityAttributes {
    var agentName: String
    var userTask: String

    struct ContentState: Codable, Hashable {
        var subject: String?
        var currentIntent: String
        var currentIntentIcon: String?
        var previousIntent: String?
        var secondPreviousIntent: String?
        var intentStartDate: Date
        var intentEndDate: Date?
        var stepNumber: Int
        var costTotal: String?

        var isFinished: Bool { intentEndDate != nil }
    }
}

extension HappyChowderActivityAttributes {
    static var preview: HappyChowderActivityAttributes {
        HappyChowderActivityAttributes(agentName: "Claude", userTask: "Fix the login bug in auth.ts")
    }
}

extension HappyChowderActivityAttributes.ContentState {
    static var startDate: Date = .now

    static var step1: HappyChowderActivityAttributes.ContentState {
        .init(subject: nil, currentIntent: "Thinking...", previousIntent: nil, secondPreviousIntent: nil, intentStartDate: startDate, stepNumber: 1, costTotal: nil)
    }

    static var step2: HappyChowderActivityAttributes.ContentState {
        .init(subject: "Fix Login Bug", currentIntent: "Reading auth.ts...", previousIntent: "Analyzed the login flow", secondPreviousIntent: nil, intentStartDate: startDate, stepNumber: 2, costTotal: "$0.08")
    }

    static var step3: HappyChowderActivityAttributes.ContentState {
        .init(subject: "Fix Login Bug", currentIntent: "Editing auth.ts...", currentIntentIcon: "doc", previousIntent: "Read auth.ts", secondPreviousIntent: "Analyzed the login flow", intentStartDate: startDate, stepNumber: 3, costTotal: "$0.15")
    }

    static var step4: HappyChowderActivityAttributes.ContentState {
        .init(subject: "Fix Login Bug", currentIntent: "Running tests...", currentIntentIcon: "terminal", previousIntent: "Fixed token validation", secondPreviousIntent: "Read auth.ts", intentStartDate: startDate, stepNumber: 4, costTotal: "$0.22")
    }

    static var step5: HappyChowderActivityAttributes.ContentState {
        .init(subject: "Fix Login Bug", currentIntent: "Verifying fix...", currentIntentIcon: "checkmark.circle", previousIntent: "Tests passed", secondPreviousIntent: "Fixed token validation", intentStartDate: startDate, stepNumber: 5, costTotal: "$0.31")
    }

    static var finished: HappyChowderActivityAttributes.ContentState {
        .init(subject: "Login bug fixed — all tests passing", currentIntent: "Complete", previousIntent: nil, secondPreviousIntent: nil, intentStartDate: startDate, intentEndDate: startDate.addingTimeInterval(24), stepNumber: 5, costTotal: "$0.31")
    }
}

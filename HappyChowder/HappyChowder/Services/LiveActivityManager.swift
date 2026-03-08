import ActivityKit
import Foundation

final class LiveActivityManager: @unchecked Sendable {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<HappyChowderActivityAttributes>?
    private var activityStartDate: Date = Date()
    private var pendingContent: ActivityContent<HappyChowderActivityAttributes.ContentState>?
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 1.0
    private var lastStepNumber: Int = 0
    private var lastCostTotal: String?
    private var demoTask: Task<Void, Never>?

    private init() {}

    func startActivity(agentName: String, userTask: String, subject: String? = nil) {
        if currentActivity != nil { endActivity() }

        activityStartDate = Date()
        lastStepNumber = 0
        lastCostTotal = nil

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = HappyChowderActivityAttributes(agentName: agentName, userTask: userTask)
        let initialState = HappyChowderActivityAttributes.ContentState(
            subject: subject,
            currentIntent: "Thinking...",
            previousIntent: nil,
            secondPreviousIntent: nil,
            intentStartDate: activityStartDate,
            stepNumber: 1,
            costTotal: nil
        )
        let content = ActivityContent(state: initialState, staleDate: nil)

        do {
            currentActivity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            print("[LiveActivity] Failed to start: \(error.localizedDescription)")
        }
    }

    func update(
        subject: String?,
        currentIntent: String,
        currentIntentIcon: String? = nil,
        previousIntent: String?,
        secondPreviousIntent: String?,
        stepNumber: Int,
        costTotal: String?,
        isAISubject: Bool = false
    ) {
        guard currentActivity != nil else { return }
        lastStepNumber = stepNumber
        lastCostTotal = costTotal

        let state = HappyChowderActivityAttributes.ContentState(
            subject: subject,
            currentIntent: currentIntent,
            currentIntentIcon: currentIntentIcon,
            previousIntent: previousIntent,
            secondPreviousIntent: secondPreviousIntent,
            intentStartDate: activityStartDate,
            stepNumber: stepNumber,
            costTotal: costTotal
        )
        pendingContent = ActivityContent(state: state, staleDate: nil)

        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            self?.flushPendingUpdate()
        }
    }

    private func flushPendingUpdate() {
        guard let activity = currentActivity, let content = pendingContent else { return }
        pendingContent = nil
        Task { await activity.update(content) }
    }

    func updateIntent(_ intent: String) {
        guard currentActivity != nil else { return }
        update(subject: nil, currentIntent: intent, previousIntent: nil, secondPreviousIntent: nil, stepNumber: 1, costTotal: nil)
    }

    func endActivity(completionSummary: String? = nil) {
        demoTask?.cancel()
        demoTask = nil
        guard let activity = currentActivity else { return }
        debounceTimer?.invalidate()
        debounceTimer = nil
        pendingContent = nil
        currentActivity = nil

        let finalState = HappyChowderActivityAttributes.ContentState(
            subject: completionSummary,
            currentIntent: "Complete",
            previousIntent: nil,
            secondPreviousIntent: nil,
            intentStartDate: activityStartDate,
            intentEndDate: .now,
            stepNumber: lastStepNumber,
            costTotal: lastCostTotal
        )
        let content = ActivityContent(state: finalState, staleDate: nil)
        Task { await activity.end(content, dismissalPolicy: .after(.now + 8)) }
    }

    func startDemo() {
        demoTask?.cancel()
        if currentActivity != nil { endActivity() }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = HappyChowderActivityAttributes.preview
        let initialContent = ActivityContent(state: HappyChowderActivityAttributes.ContentState.step1, staleDate: nil)

        do {
            currentActivity = try Activity.request(attributes: attributes, content: initialContent, pushType: nil)
        } catch { return }

        demoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            let steps: [HappyChowderActivityAttributes.ContentState] = [.step2, .step3, .step4, .step5]
            for step in steps {
                guard let activity = self?.currentActivity, !Task.isCancelled else { return }
                await activity.update(ActivityContent(state: step, staleDate: nil))
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
            }
            guard let activity = self?.currentActivity, !Task.isCancelled else { return }
            self?.currentActivity = nil
            await activity.end(
                ActivityContent(state: HappyChowderActivityAttributes.ContentState.finished, staleDate: nil),
                dismissalPolicy: .after(.now + 8)
            )
        }
    }
}

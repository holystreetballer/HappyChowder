import SwiftUI
import UIKit

@Observable
final class ChatViewModel: HappySessionServiceDelegate {

    var messages: [Message] = []
    var inputText: String = ""

    // MARK: - Pagination

    var displayLimit: Int = 50
    private let pageSize: Int = 50

    var displayedMessages: [Message] {
        if messages.count <= displayLimit { return messages }
        return Array(messages.suffix(displayLimit))
    }

    var hasEarlierMessages: Bool { messages.count > displayLimit }

    func loadEarlierMessages() { displayLimit += pageSize }

    var isLoading: Bool = false
    var isConnected: Bool = false
    var showSettings: Bool = false
    var debugLog: [String] = []
    var showDebugLog: Bool = false

    var botName: String { "Claude Code" }

    /// Tracks the agent's current turn activity for the shimmer display.
    var currentActivity: AgentActivity?
    var lastCompletedActivity: AgentActivity?
    var showActivityCard: Bool = false

    var currentTaskSummary: String? { liveActivitySubject }

    private var shimmerStartTime: Date?

    @ObservationIgnored private let responseHaptic = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored private var hasPlayedResponseHaptic = false
    @ObservationIgnored private var hasReceivedAnyDelta = false

    private var sessionService: HappySessionService?
    private var encryption: EncryptionService?

    var activeSessionId: String? { sessionService?.activeSessionId }
    var isConfigured: Bool { ConnectionConfig().isConfigured }

    // MARK: - Run Generation

    private var currentRunGeneration: Int = 0
    private var currentRunStartTime: Date?

    // MARK: - Tool Call Tracking

    private var toolCallStartTimes: [String: Date] = [:]

    // MARK: - Live Activity Tracking State

    private var liveActivityBottomText: String = "Thinking..."
    private var liveActivityYellowIntent: String?
    private var liveActivityGreyIntent: String?
    private var liveActivityCostAccumulator: Double = 0
    private var liveActivityCost: String?
    private var liveActivityStepNumber: Int = 1
    private var liveActivitySubject: String?
    private var liveActivityCurrentIcon: String?
    private var pastTenseCache: [String: String] = [:]

    // MARK: - Feature: Multi-Session

    var sessions: [HappySession] = []
    var showSessionsList: Bool = false
    var sessionMetadataMap: [String: SessionMetadata] = [:]

    var sessionListItems: [SessionListItem] {
        sessions.map { session in
            let meta = sessionMetadataMap[session.id]
            let machineName = meta?.host ?? machines.first(where: { $0.id == session.machineId })?.metadata?.host
            return SessionListItem(
                id: session.id,
                summary: meta?.summary?.text ?? meta?.name ?? session.title,
                path: meta?.path,
                machineName: machineName,
                isActive: session.active ?? false,
                updatedAt: session.updatedAt,
                costTotal: sessionCosts[session.id]
            )
        }
    }

    // MARK: - Feature: Permission Requests

    var pendingPermissions: [String: PermissionRequest] = [:]
    var showPermissionSheet: Bool = false

    var permissionDisplayItems: [PermissionDisplayItem] {
        pendingPermissions.map { (id, req) in
            let args = req.arguments?.value as? [String: Any]
            let desc: String
            if let path = args?["path"] as? String {
                desc = path
            } else if let cmd = args?["command"] as? String {
                desc = String(cmd.prefix(80))
            } else {
                desc = "Requesting permission"
            }
            return PermissionDisplayItem(
                id: id,
                tool: req.tool,
                description: desc,
                args: args,
                createdAt: Date(timeIntervalSince1970: req.createdAt / 1000)
            )
        }
    }

    // MARK: - Feature: Cost Tracking

    var sessionCosts: [String: Double] = [:]
    var sessionTokens: [String: (input: Int, output: Int)] = [:]
    var showCostDashboard: Bool = false

    var totalCost: Double {
        sessionCosts.values.reduce(0, +)
    }

    var costDisplayItems: [SessionCostItem] {
        sessionCosts.compactMap { (sessionId, cost) in
            let meta = sessionMetadataMap[sessionId]
            let tokens = sessionTokens[sessionId] ?? (0, 0)
            return SessionCostItem(
                id: sessionId,
                name: meta?.summary?.text ?? meta?.name ?? String(sessionId.prefix(8)),
                cost: cost,
                inputTokens: tokens.input,
                outputTokens: tokens.output
            )
        }
        .sorted { $0.cost > $1.cost }
    }

    // MARK: - Feature: Machine Status

    var machines: [HappyMachine] = []
    var showMachinesView: Bool = false

    var machineDisplayItems: [MachineDisplayItem] {
        machines.map { machine in
            let sessionCount = sessions.filter { $0.machineId == machine.id }.count
            return MachineDisplayItem(
                id: machine.id,
                host: machine.metadata?.host ?? "Unknown",
                platform: machine.metadata?.platform ?? "unknown",
                isOnline: machine.active,
                daemonStatus: machine.daemonState?.status,
                cliVersion: machine.metadata?.happyCliVersion,
                sessionCount: sessionCount,
                lastActiveAt: machine.activeAt > 0 ? Date(timeIntervalSince1970: machine.activeAt / 1000) : nil
            )
        }
    }

    // MARK: - Feature: Session Metadata

    var showSessionMetadata: Bool = false

    var currentSessionMetadata: SessionMetadataDisplay? {
        guard let sessionId = sessionService?.activeSessionId,
              let meta = sessionMetadataMap[sessionId] else { return nil }
        return SessionMetadataDisplay(
            name: meta.name,
            summary: meta.summary?.text,
            workingDirectory: meta.path,
            host: meta.host,
            os: meta.os,
            version: meta.version,
            flavor: meta.flavor,
            tools: meta.tools,
            machineId: meta.machineId
        )
    }

    private func shiftThinkingIntent(_ newIntent: String) {
        guard newIntent != liveActivityYellowIntent else { return }
        liveActivityGreyIntent = liveActivityYellowIntent
        if let cached = pastTenseCache[newIntent] {
            liveActivityYellowIntent = cached
        } else {
            liveActivityYellowIntent = newIntent
            let intentToConvert = newIntent
            Task {
                let pastTense = await TaskSummaryService.shared.convertToPastTense(intentToConvert)
                await MainActor.run {
                    if let pastTense {
                        self.pastTenseCache[intentToConvert] = pastTense
                        if self.liveActivityYellowIntent == intentToConvert {
                            self.liveActivityYellowIntent = pastTense
                            self.pushLiveActivityUpdate()
                        }
                        if self.liveActivityGreyIntent == intentToConvert {
                            self.liveActivityGreyIntent = pastTense
                            self.pushLiveActivityUpdate()
                        }
                    }
                }
            }
        }
        if liveActivitySubject == nil {
            liveActivitySubject = newIntent
        }
    }

    private func pushLiveActivityUpdate(isAISubject: Bool = false) {
        LiveActivityManager.shared.update(
            subject: liveActivitySubject,
            currentIntent: liveActivityBottomText,
            currentIntentIcon: liveActivityCurrentIcon,
            previousIntent: liveActivityYellowIntent,
            secondPreviousIntent: liveActivityGreyIntent,
            stepNumber: liveActivityStepNumber,
            costTotal: liveActivityCost,
            isAISubject: isAISubject
        )
    }

    private func resetLiveActivityState() {
        liveActivityBottomText = "Thinking..."
        liveActivityYellowIntent = nil
        liveActivityGreyIntent = nil
        liveActivityCostAccumulator = 0
        liveActivityCost = nil
        liveActivityStepNumber = 1
        liveActivitySubject = nil
        liveActivityCurrentIcon = nil
        pastTenseCache.removeAll()
    }

    private func generateCompletionSummary() async -> String? {
        guard let finalText = latestAssistantResponseText(), !finalText.isEmpty else { return nil }
        return await TaskSummaryService.shared.generateCompletionMessage(fromAssistantResponse: finalText)
    }

    private func latestAssistantResponseText() -> String? {
        guard let last = messages.last(where: { $0.role == .assistant })?.content else { return nil }
        let cleaned = last.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    // MARK: - Buffered Debug Logging

    @ObservationIgnored private var logBuffer: [String] = []
    @ObservationIgnored private var logFlushScheduled = false
    @ObservationIgnored private let logFlushInterval: TimeInterval = 0.5

    private func log(_ msg: String) {
        let entry = "[\(Date().formatted(.dateTime.hour().minute().second()))] \(msg)"
        print(entry)
        logBuffer.append(entry)
        scheduleLogFlush()
    }

    private func scheduleLogFlush() {
        guard !logFlushScheduled else { return }
        logFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + logFlushInterval) { [weak self] in
            self?.flushLogBuffer()
        }
    }

    func flushLogBuffer() {
        logFlushScheduled = false
        guard !logBuffer.isEmpty else { return }
        debugLog.append(contentsOf: logBuffer)
        logBuffer.removeAll()
    }

    init() {
        NotificationManager.shared.requestPermission()
    }

    // MARK: - Actions

    func connect() {
        log("connect() called")

        if messages.isEmpty {
            messages = LocalStorage.loadMessages()
            if !messages.isEmpty { log("Restored \(messages.count) messages from disk") }
        }

        let config = ConnectionConfig()
        log("config — url=\(config.serverURL) tokenLen=\(config.token.count) configured=\(config.isConfigured)")
        guard config.isConfigured else {
            log("Not configured — showing settings")
            showSettings = true
            return
        }

        sessionService?.disconnect()

        // Initialize encryption from master secret
        guard let secretData = Data(base64Encoded: config.masterSecret), secretData.count == 32 else {
            log("Invalid master secret")
            showSettings = true
            return
        }

        do {
            let enc = try EncryptionService(masterSecret: secretData)
            self.encryption = enc

            let service = HappySessionService(
                serverURL: config.serverURL,
                authToken: config.token,
                encryption: enc
            )
            service.delegate = self
            self.sessionService = service
            service.connect()
            log("HappySessionService.connect() called")

            // Fetch sessions and activate the most recent one
            service.fetchSessions { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let sessions):
                        self?.log("Fetched \(sessions.count) sessions")
                        self?.sessions = sessions
                        if let latest = sessions.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                            do {
                                try service.setActiveSession(latest)
                                self?.log("Active session: \(latest.id)")
                            } catch {
                                self?.log("Failed to set session: \(error.localizedDescription)")
                            }
                        }
                    case .failure(let error):
                        self?.log("Failed to fetch sessions: \(error.localizedDescription)")
                    }
                }
            }

            // Fetch machines
            service.fetchMachines()
        } catch {
            log("Encryption init failed: \(error.localizedDescription)")
            showSettings = true
        }
    }

    func reconnect() {
        log("reconnect()")
        sessionService?.disconnect()
        sessionService = nil
        isConnected = false
        connect()
    }

    func send() {
        log("send() — isConnected=\(isConnected) isLoading=\(isLoading)")
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        sendText(text)
        inputText = ""
    }

    /// Send a message directly (used by quick replies and the input bar).
    func sendText(_ text: String) {
        guard !isLoading || text == "STOP - Please stop what you're doing immediately." else { return }

        hasPlayedResponseHaptic = false
        hasReceivedAnyDelta = false
        responseHaptic.prepare()

        messages.append(Message(role: .user, content: text))
        isLoading = true

        currentActivity = AgentActivity()
        currentActivity?.currentLabel = "Thinking..."
        shimmerStartTime = Date()

        currentRunGeneration += 1
        currentRunStartTime = Date()
        toolCallStartTimes.removeAll()
        resetLiveActivityState()

        messages.append(Message(role: .assistant, content: ""))
        LocalStorage.saveMessages(messages)

        LiveActivityManager.shared.startActivity(agentName: botName, userTask: text, subject: nil)

        let runGeneration = currentRunGeneration
        let latestUserMessage = text
        Task {
            let summary = await TaskSummaryService.shared.generateTitle(from: latestUserMessage)
            await MainActor.run {
                guard self.currentRunGeneration == runGeneration else { return }
                if let summary, !summary.isEmpty {
                    self.liveActivitySubject = summary
                    self.pushLiveActivityUpdate(isAISubject: true)
                }
            }
        }

        sessionService?.sendMessage(text)
        log("sessionService.sendMessage() called")
    }

    /// Send a quick reply.
    func sendQuickReply(_ message: String) {
        guard !isLoading else { return }
        sendText(message)
    }

    /// Cancel the current turn.
    func cancelTurn() {
        log("cancelTurn()")
        sessionService?.sendStopMessage()
    }

    /// Switch to a different session.
    func switchSession(to sessionId: String) {
        guard sessionId != sessionService?.activeSessionId else { return }
        do {
            messages.removeAll()
            try sessionService?.switchToSession(id: sessionId)
            log("Switched to session \(sessionId)")
        } catch {
            log("Failed to switch session: \(error.localizedDescription)")
        }
    }

    /// Approve a permission request.
    func approvePermission(id: String) {
        sessionService?.respondToPermission(requestId: id, decision: "approved")
        pendingPermissions.removeValue(forKey: id)
        if pendingPermissions.isEmpty { showPermissionSheet = false }
    }

    /// Deny a permission request.
    func denyPermission(id: String) {
        sessionService?.respondToPermission(requestId: id, decision: "denied")
        pendingPermissions.removeValue(forKey: id)
        if pendingPermissions.isEmpty { showPermissionSheet = false }
    }

    func clearMessages() {
        messages.removeAll()
        LocalStorage.deleteMessages()
        log("Chat history cleared")
    }

    func logout() {
        sessionService?.disconnect()
        sessionService = nil
        encryption = nil
        isConnected = false
        messages.removeAll()
        sessions.removeAll()
        machines.removeAll()
        sessionCosts.removeAll()
        sessionTokens.removeAll()
        pendingPermissions.removeAll()
        sessionMetadataMap.removeAll()
        LocalStorage.deleteMessages()
        AuthManager.shared.logout()
    }

    // MARK: - HappySessionServiceDelegate

    func serviceDidConnect() {
        log("CONNECTED")
        isConnected = true
    }

    func serviceDidDisconnect() {
        log("DISCONNECTED")
        isConnected = false
    }

    func serviceDidReceiveTextDelta(_ text: String) {
        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant else { return }
        messages[lastIndex].content += text
        hasReceivedAnyDelta = true

        if !hasPlayedResponseHaptic {
            hasPlayedResponseHaptic = true
            responseHaptic.impactOccurred()
            log("Assistant responding")

            if currentActivity != nil {
                currentActivity?.finishCurrentSteps()
                lastCompletedActivity = currentActivity
                currentActivity = nil
                shimmerStartTime = nil
            }
        }
    }

    func serviceDidReceiveThinkingDelta(_ text: String) {
        log("Thinking delta: \(text.count) chars")

        if currentActivity == nil {
            currentActivity = AgentActivity()
        }
        currentActivity?.thinkingText += text
        currentActivity?.currentLabel = "Thinking..."

        if let lastStep = currentActivity?.steps.last, lastStep.type == .thinking, lastStep.status == .inProgress {
            currentActivity?.steps[currentActivity!.steps.count - 1].detail += text
        } else {
            currentActivity?.finishCurrentSteps()
            currentActivity?.steps.append(
                ActivityStep(type: .thinking, label: "Thinking", detail: text, toolCategory: .thinking)
            )
        }

        // Shift thinking into Live Activity intent stack
        let summary = extractThinkingSummary(text)
        if let summary {
            liveActivityBottomText = "Thinking..."
            liveActivityCurrentIcon = nil
            liveActivityStepNumber = (currentActivity?.steps.count ?? 1)
            shiftThinkingIntent(summary)
            pushLiveActivityUpdate()
        }

        LiveActivityManager.shared.updateIntent("Thinking...")
    }

    func serviceDidReceiveToolCallStart(callId: String, name: String, title: String, description: String, args: [String: Any]) {
        log("Tool start: \(name) (\(callId))")

        if currentActivity == nil {
            currentActivity = AgentActivity()
        }

        currentActivity?.finishCurrentSteps()
        toolCallStartTimes[callId] = Date()

        let label = Self.friendlyLabel(for: name, title: title, args: args)
        let detail = Self.detailString(for: name, title: title, description: description, args: args)
        let category = Self.toolCategory(for: name, args: args)

        currentActivity?.currentLabel = label
        currentActivity?.steps.append(
            ActivityStep(type: .toolCall, label: label, detail: detail, toolCategory: category)
        )

        // Update Live Activity
        liveActivityBottomText = label
        liveActivityCurrentIcon = category.iconName
        liveActivityStepNumber = (currentActivity?.steps.count ?? 1)
        pushLiveActivityUpdate()
    }

    func serviceDidReceiveToolCallEnd(callId: String) {
        log("Tool end: \(callId)")

        if let activity = currentActivity {
            for i in activity.steps.indices.reversed() {
                if activity.steps[i].status == .inProgress && activity.steps[i].type == .toolCall {
                    currentActivity?.steps[i].status = .completed
                    currentActivity?.steps[i].completedAt = Date()
                    break
                }
            }
        }
        toolCallStartTimes.removeValue(forKey: callId)
    }

    func serviceDidReceiveTurnEnd(status: String) {
        log("Turn end: \(status)")
    }

    func serviceDidReceiveServiceMessage(_ text: String) {
        log("Service message: \(text)")
    }

    func serviceDidFinishMessage() {
        log("message.done - isLoading was \(isLoading)")
        isLoading = false
        hasPlayedResponseHaptic = false

        currentActivity?.finishCurrentSteps()

        if let activity = currentActivity {
            lastCompletedActivity = activity
        }

        let runGeneration = currentRunGeneration
        let sessionName = liveActivitySubject
        Task {
            let completionSummary = await generateCompletionSummary()
            await MainActor.run {
                guard self.currentRunGeneration == runGeneration else { return }
                LiveActivityManager.shared.endActivity(completionSummary: completionSummary)
                NotificationManager.shared.notifyTaskComplete(sessionName: sessionName, summary: completionSummary)
            }
        }

        currentActivity = nil
        shimmerStartTime = nil

        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == .assistant,
           messages[lastIndex].content.isEmpty {
            if hasReceivedAnyDelta {
                messages.remove(at: lastIndex)
            }
        }

        LocalStorage.saveMessages(messages)
    }

    func serviceDidReceiveError(_ error: Error) {
        log("ERROR: \(error.localizedDescription)")

        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == .assistant,
           messages[lastIndex].content.isEmpty {
            messages[lastIndex].content = "Something went wrong. Please try again."
        }
        isLoading = false
        currentActivity = nil
        LiveActivityManager.shared.endActivity()
        NotificationManager.shared.notifyError(sessionName: liveActivitySubject, error: error.localizedDescription)
        LocalStorage.saveMessages(messages)
    }

    func serviceDidLog(_ message: String) {
        log("SVC: \(message)")
    }

    // MARK: - New Delegate Methods

    func serviceDidReceivePermissionRequests(_ requests: [String: PermissionRequest]) {
        log("Permission requests: \(requests.count)")
        pendingPermissions = requests
        if !requests.isEmpty {
            showPermissionSheet = true
            // Notify if in background
            if let first = requests.values.first {
                NotificationManager.shared.notifyPermissionNeeded(tool: first.tool, sessionName: liveActivitySubject)
            }
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
        }
    }

    func serviceDidReceiveUsageUpdate(sessionId: String, tokens: [String: Double], cost: [String: Double]) {
        let totalCost = cost["total"] ?? 0
        sessionCosts[sessionId] = (sessionCosts[sessionId] ?? 0) + totalCost

        let inputTokens = Int(tokens["input"] ?? 0)
        let outputTokens = Int(tokens["output"] ?? 0)
        let existing = sessionTokens[sessionId] ?? (0, 0)
        sessionTokens[sessionId] = (existing.input + inputTokens, existing.output + outputTokens)

        // Update Live Activity cost
        if sessionId == sessionService?.activeSessionId {
            liveActivityCostAccumulator += totalCost
            liveActivityCost = String(format: "$%.2f", liveActivityCostAccumulator)
            pushLiveActivityUpdate()
        }
    }

    func serviceDidReceiveMachineUpdate(machineId: String, active: Bool, activeAt: Double) {
        if let idx = machines.firstIndex(where: { $0.id == machineId }) {
            machines[idx].active = active
            machines[idx].activeAt = activeAt
        }
    }

    func serviceDidReceiveSessionMetadata(_ metadata: SessionMetadata, forSession sessionId: String) {
        log("Received metadata for session \(sessionId): host=\(metadata.host ?? "?") path=\(metadata.path ?? "?")")
        sessionMetadataMap[sessionId] = metadata
    }

    func serviceDidReceiveSessionsList(_ sessions: [HappySession]) {
        self.sessions = sessions
    }

    func serviceDidReceiveMachinesList(_ machinesList: [HappyMachine]) {
        self.machines = machinesList
    }

    // MARK: - Thinking Summary Extraction

    private func extractThinkingSummary(_ text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if let dotIndex = cleaned.firstIndex(of: ".") {
            let sentence = String(cleaned[cleaned.startIndex...dotIndex])
            if sentence.count > 10 && sentence.count < 80 { return sentence }
        }

        let truncated = String(cleaned.prefix(60))
        return truncated.count > 10 ? truncated : nil
    }

    // MARK: - Friendly Tool Labels

    private static func friendlyLabel(for name: String, title: String, args: [String: Any]) -> String {
        if !title.isEmpty { return title }

        let fileName = (args["path"] as? String).map { ($0 as NSString).lastPathComponent }

        switch name {
        case "write", "apply_patch", "Write":
            return "Writing \(fileName ?? "file")..."
        case "read", "Read":
            return "Reading \(fileName ?? "file")..."
        case "edit", "Edit":
            return "Editing \(fileName ?? "file")..."
        case "Grep", "search":
            if let query = args["query"] as? String ?? args["pattern"] as? String, !query.isEmpty {
                let short = query.count > 30 ? String(query.prefix(30)) + "..." : query
                return "Searching for \"\(short)\"..."
            }
            return "Searching files..."
        case "Glob":
            return "Finding files..."
        case "Bash", "bash", "exec":
            if let cmd = args["command"] as? String, !cmd.isEmpty {
                let short = cmd.count > 30 ? String(cmd.prefix(30)) + "..." : cmd
                return "Running: \(short)"
            }
            return "Running a command..."
        case "Agent":
            return "Running a sub-task..."
        case "WebFetch", "web_fetch":
            return "Fetching from the web..."
        case "WebSearch", "web_search":
            return "Searching the web..."
        default:
            if let fileName { return "\(name) \(fileName)..." }
            return "Using \(name)..."
        }
    }

    private static func detailString(for name: String, title: String, description: String, args: [String: Any]) -> String {
        if !description.isEmpty { return description }
        if let path = args["path"] as? String, !path.isEmpty { return path }
        if let url = args["url"] as? String, !url.isEmpty { return url }
        if let cmd = args["command"] as? String, !cmd.isEmpty { return cmd }
        return ""
    }

    private static func toolCategory(for name: String, args: [String: Any]) -> ToolCategory {
        switch name {
        case "Bash", "bash", "exec":
            if let cmd = args["command"] as? String {
                if cmd.contains("agent-browser") || cmd.contains("playwright") { return .browser }
                if cmd.contains("curl") || cmd.contains("wget") { return .network }
            }
            return .terminal
        case "read", "Read", "write", "Write", "edit", "Edit", "Glob", "apply_patch":
            return .fileSystem
        case "Grep", "search":
            return .search
        case "WebFetch", "web_fetch", "WebSearch", "web_search":
            return .network
        case "Agent":
            return .generic
        default:
            return .generic
        }
    }
}

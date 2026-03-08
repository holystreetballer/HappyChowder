#if canImport(FoundationModels)
import FoundationModels

actor TaskSummaryService {
    static let shared = TaskSummaryService()
    private init() {}

    func generateTitle(from latestUserMessage: String) async -> String? {
        let message = latestUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return nil }

        let availability = SystemLanguageModel.default.availability
        guard availability == .available else { return nil }

        let session = LanguageModelSession(model: .init(useCase: .general, guardrails: .permissiveContentTransformations))
        let prompt = """
        You are generating a very short UI task title.

        Use ONLY this latest user message:
        "\(message)"

        Rules:
        - Infer the task the assistant should do from this message alone
        - Return a concise 2-4 word imperative-style title
        - Prefer specific nouns and proper nouns from the message
        - Avoid generic words
        - Do not add punctuation at the end

        It is crucial that the title is succinct because it will be used in UI. Only output the title, nothing else.
        """

        do {
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    func convertToPastTense(_ intent: String) async -> String? {
        let cleaned = intent.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let availability = SystemLanguageModel.default.availability
        guard availability == .available else { return nil }

        let session = LanguageModelSession(model: .init(useCase: .general, guardrails: .permissiveContentTransformations))
        let prompt = """
        Convert this action description to past tense. Keep the same level of detail and specificity.

        Input: "\(cleaned)"

        Rules:
        - Convert progressive/present tense to simple past tense
        - Keep proper nouns, filenames, and quoted strings unchanged
        - Keep it the same length or shorter
        - Do not add punctuation at the end

        Only output the converted text, nothing else.
        """

        do {
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    func generateCompletionMessage(fromAssistantResponse assistantResponse: String) async -> String? {
        let finalResponse = assistantResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalResponse.isEmpty else { return nil }

        let availability = SystemLanguageModel.default.availability
        guard availability == .available else { return nil }

        let session = LanguageModelSession(model: .init(useCase: .general, guardrails: .permissiveContentTransformations))
        let prompt = """
        You are generating a completion summary for a finished task.

        Use ONLY this final assistant response:
        "\(finalResponse)"

        Rules:
        - Summarize the actual outcome or result achieved
        - Use past-tense, notification style
        - Keep it concise (under 8 words)
        - Be specific to what was actually completed
        - Do not use exclamation marks

        Only output the completion message, nothing else.
        """

        do {
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

#else

// Stub for SDKs that don't include FoundationModels
actor TaskSummaryService {
    static let shared = TaskSummaryService()
    private init() {}

    func generateTitle(from latestUserMessage: String) async -> String? { nil }
    func convertToPastTense(_ intent: String) async -> String? { nil }
    func generateCompletionMessage(fromAssistantResponse assistantResponse: String) async -> String? { nil }
}

#endif

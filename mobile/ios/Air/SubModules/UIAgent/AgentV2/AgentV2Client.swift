import Foundation
import WalletCore

@MainActor
protocol AgentV2Client: AnyObject, Sendable {
    func consent() async throws -> Bool
    /// The user's consent as the app last read or gave it, known at once: false until then
    var isConsentKnownGiven: Bool { get }
    /// Forgets the known consent, which a reset of the accounts deletes
    func forgetKnownConsent()
    func acceptConsent() async throws
    func updateHostContext(_ context: ApiAgentV2HostContext?) async throws
    func hints() async throws -> ApiAgentV2HintsResponse
    func loadAvailability() async
    func loadUserQuota() async
    func problemReportAvailability() async -> Bool
    func setChatActive(_ isActive: Bool) async
    func defaultThread() async throws -> ApiAgentV2DefaultThreadResponse
    func listThreads(cursor: String?, limit: Int?, query: String?) async throws -> ApiAgentV2ThreadListResponse
    func createThread() async throws -> ApiAgentV2ThreadCreateResponse
    func createThread(news: ApiAgentV2ThreadNewsRequest) async throws -> ApiAgentV2ThreadCreateResponse
    func createThread(digest: ApiAgentV2ThreadDigestRequest) async throws -> ApiAgentV2ThreadCreateResponse
    func updateThread(id: String, update: ApiAgentV2ThreadUpdate) async throws -> ApiAgentV2ThreadUpdateResponse
    func deleteThread(id: String) async throws -> ApiAgentV2ThreadDeleteResponse
    func messages(threadId: String, cursor: String?, limit: Int) async throws -> ApiAgentV2ThreadHydration
    /// The SDK's copy of the thread's latest messages; `nil` when it has none or cannot read it
    func cachedMessages(threadId: String) async -> ApiAgentV2CachedMessages?
    /// The id of a new run, chosen before it starts
    func makeClientRunId() -> String
    func startRun(_ command: ApiAgentV2RunCommand) async throws -> ApiAgentV2RunResult
    func retryRun(clientRunId: String) async throws -> ApiAgentV2RunResult?
    /// Stops every run of the thread
    func stopRun(threadId: String) async
    func clearThread(id: String, revision: Int) async throws -> ApiAgentV2MutationResult<ApiAgentV2ThreadClearResponse>
    func reportProblem(threadId: String, report: ApiAgentV2ProblemReport) async throws
    func transcribeAgentV2Audio(_ request: ApiAgentV2TranscriptionRequest) async throws -> ApiAgentV2TranscriptionResponse
    /// Returns the rating the server keeps for the answer
    func setMessageFeedback(
        threadId: String,
        messageId: String,
        feedback: ApiAgentV2AnswerFeedback?
    ) async throws -> ApiAgentV2AnswerFeedback?
    func actionPresentation(messageId: String, actionId: String) async throws -> ApiAgentV2ActionPresentation
    func resolveAction(messageId: String, actionId: String) async throws -> ApiAgentV2ResolvedAction
}

extension AgentV2Client {
    var isConsentKnownGiven: Bool { false }
    func forgetKnownConsent() {}
}

@MainActor
final class LiveAgentV2Client: AgentV2Client {
    /// The consent as the app last read or gave it, shared by every chat and list
    private static var isConsentKnownGiven = false

    var isConsentKnownGiven: Bool {
        Self.isConsentKnownGiven
    }

    func consent() async throws -> Bool {
        let isGiven = try await Api.getAgentV2Consent()
        Self.isConsentKnownGiven = isGiven
        return isGiven
    }

    func forgetKnownConsent() {
        Self.isConsentKnownGiven = false
    }

    func acceptConsent() async throws {
        _ = try await Api.acceptAgentV2Consent()
        Self.isConsentKnownGiven = true
    }

    func updateHostContext(_ context: ApiAgentV2HostContext?) async throws {
        _ = try await Api.updateAgentV2HostContext(context)
    }

    func hints() async throws -> ApiAgentV2HintsResponse {
        try await Api.getAgentV2Hints(langCode: nil)
    }

    func loadAvailability() async {
        try? await Api.getAgentV2Availability()
    }

    func loadUserQuota() async {
        try? await Api.getAgentV2UserQuota()
    }

    func problemReportAvailability() async -> Bool {
        (try? await Api.getAgentV2ProblemReportAvailability()) == true
    }

    func setChatActive(_ isActive: Bool) async {
        try? await Api.setAgentV2ChatActive(isActive)
    }

    func defaultThread() async throws -> ApiAgentV2DefaultThreadResponse {
        try await Api.getAgentV2DefaultThread()
    }

    func listThreads(cursor: String?, limit: Int?, query: String?) async throws -> ApiAgentV2ThreadListResponse {
        try await Api.listAgentV2Threads(cursor: cursor, limit: limit, query: query)
    }

    func createThread() async throws -> ApiAgentV2ThreadCreateResponse {
        try await Api.createAgentV2Thread()
    }

    func createThread(news: ApiAgentV2ThreadNewsRequest) async throws -> ApiAgentV2ThreadCreateResponse {
        try await Api.createAgentV2Thread(news: news)
    }

    func createThread(digest: ApiAgentV2ThreadDigestRequest) async throws -> ApiAgentV2ThreadCreateResponse {
        try await Api.createAgentV2Thread(digest: digest)
    }

    func updateThread(id: String, update: ApiAgentV2ThreadUpdate) async throws -> ApiAgentV2ThreadUpdateResponse {
        try await Api.updateAgentV2Thread(threadId: id, update: update)
    }

    func deleteThread(id: String) async throws -> ApiAgentV2ThreadDeleteResponse {
        try await Api.deleteAgentV2Thread(threadId: id)
    }

    func messages(threadId: String, cursor: String?, limit: Int) async throws -> ApiAgentV2ThreadHydration {
        try await Api.getAgentV2Messages(threadId: threadId, cursor: cursor, limit: limit)
    }

    func cachedMessages(threadId: String) async -> ApiAgentV2CachedMessages? {
        await Api.getAgentV2CachedMessages(threadId: threadId)
    }

    func makeClientRunId() -> String {
        UUID().uuidString.lowercased()
    }

    func startRun(_ command: ApiAgentV2RunCommand) async throws -> ApiAgentV2RunResult {
        try await Api.startAgentV2Run(command)
    }

    func retryRun(clientRunId: String) async throws -> ApiAgentV2RunResult? {
        try await Api.retryAgentV2Run(clientRunId: clientRunId)
    }

    func stopRun(threadId: String) async {
        try? await Api.stopAgentV2Run(threadId: threadId)
    }

    func clearThread(id: String, revision: Int) async throws -> ApiAgentV2MutationResult<ApiAgentV2ThreadClearResponse> {
        try await Api.clearAgentV2Thread(threadId: id, expectedRevision: revision)
    }

    func reportProblem(threadId: String, report: ApiAgentV2ProblemReport) async throws {
        _ = try await Api.reportAgentV2Problem(threadId: threadId, report: report)
    }

    func transcribeAgentV2Audio(_ request: ApiAgentV2TranscriptionRequest) async throws -> ApiAgentV2TranscriptionResponse {
        try await Api.transcribeAgentV2Audio(request)
    }

    func setMessageFeedback(
        threadId: String,
        messageId: String,
        feedback: ApiAgentV2AnswerFeedback?
    ) async throws -> ApiAgentV2AnswerFeedback? {
        try await Api.setAgentV2MessageFeedback(threadId: threadId, messageId: messageId, feedback: feedback).feedback
    }

    func actionPresentation(messageId: String, actionId: String) async throws -> ApiAgentV2ActionPresentation {
        try await Api.getAgentV2ActionPresentation(messageId: messageId, actionId: actionId)
    }

    func resolveAction(messageId: String, actionId: String) async throws -> ApiAgentV2ResolvedAction {
        try await Api.resolveAgentV2Action(messageId: messageId, actionId: actionId)
    }
}

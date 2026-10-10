import Foundation
import WalletCore

@MainActor
protocol AgentV2Client: AnyObject, Sendable {
    func consent() async throws -> Bool
    func acceptConsent() async throws
    func updateHostContext(_ context: ApiAgentV2HostContext?) async throws
    func hints() async throws -> ApiAgentV2HintsResponse
    func loadAvailability() async
    func loadUserQuota() async
    func problemReportAvailability() async -> Bool
    func setChatActive(_ isActive: Bool) async
    func defaultThread() async throws -> ApiAgentV2DefaultThreadResponse
    func messages(threadId: String, cursor: String?, limit: Int) async throws -> ApiAgentV2ThreadHydration
    func startRun(_ command: ApiAgentV2RunCommand) async throws -> ApiAgentV2RunResult
    func retryRun(clientRunId: String) async throws -> ApiAgentV2RunResult?
    func cancelRun(_ runId: String) async
    func clearThread(id: String, revision: Int) async throws -> ApiAgentV2MutationResult<ApiAgentV2ThreadClearResponse>
    func reportProblem(threadId: String, report: ApiAgentV2ProblemReport) async throws
    func actionPresentation(messageId: String, actionId: String) async throws -> ApiAgentV2ActionPresentation
    func resolveAction(messageId: String, actionId: String) async throws -> ApiAgentV2ResolvedAction
}

@MainActor
final class LiveAgentV2Client: AgentV2Client {
    func consent() async throws -> Bool {
        try await Api.getAgentV2Consent()
    }

    func acceptConsent() async throws {
        _ = try await Api.acceptAgentV2Consent()
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

    func messages(threadId: String, cursor: String?, limit: Int) async throws -> ApiAgentV2ThreadHydration {
        try await Api.getAgentV2Messages(threadId: threadId, cursor: cursor, limit: limit)
    }

    func startRun(_ command: ApiAgentV2RunCommand) async throws -> ApiAgentV2RunResult {
        try await Api.startAgentV2Run(command)
    }

    func retryRun(clientRunId: String) async throws -> ApiAgentV2RunResult? {
        try await Api.retryAgentV2Run(clientRunId: clientRunId)
    }

    func cancelRun(_ runId: String) async {
        _ = try? await Api.cancelAgentV2Run(runId: runId)
    }

    func clearThread(id: String, revision: Int) async throws -> ApiAgentV2MutationResult<ApiAgentV2ThreadClearResponse> {
        try await Api.clearAgentV2Thread(threadId: id, expectedRevision: revision)
    }

    func reportProblem(threadId: String, report: ApiAgentV2ProblemReport) async throws {
        _ = try await Api.reportAgentV2Problem(threadId: threadId, report: report)
    }

    func actionPresentation(messageId: String, actionId: String) async throws -> ApiAgentV2ActionPresentation {
        try await Api.getAgentV2ActionPresentation(messageId: messageId, actionId: actionId)
    }

    func resolveAction(messageId: String, actionId: String) async throws -> ApiAgentV2ResolvedAction {
        try await Api.resolveAgentV2Action(messageId: messageId, actionId: actionId)
    }
}

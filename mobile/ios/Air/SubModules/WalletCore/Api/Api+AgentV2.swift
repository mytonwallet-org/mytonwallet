import Foundation

extension Api {
    @concurrent public static func getAgentV2Consent() async throws -> Bool {
        try await bridge.callApi("getAgentV2Consent", decoding: Bool.self)
    }

    @concurrent public static func acceptAgentV2Consent() async throws -> Bool {
        try await bridge.callApi("acceptAgentV2Consent", decoding: Bool.self)
    }

    @concurrent public static func updateAgentV2HostContext(
        _ context: ApiAgentV2HostContext?
    ) async throws -> ApiAgentV2HostContextUpdate {
        let result = try await bridge.callApi(
            "updateAgentV2HostContext",
            context,
            decoding: ApiAgentV2MutationResult<ApiAgentV2HostContextUpdate>.self
        )
        return try requireAgentV2OperationValue(result, methodName: "updateAgentV2HostContext")
    }

    @concurrent public static func getAgentV2Hints(langCode: String?) async throws -> ApiAgentV2HintsResponse {
        try await bridge.callApi("getAgentV2Hints", langCode, decoding: ApiAgentV2HintsResponse.self)
    }

    @concurrent public static func getAgentV2Availability() async throws {
        try await bridge.callApiVoid("getAgentV2Availability")
    }

    @concurrent public static func getAgentV2UserQuota() async throws {
        try await bridge.callApiVoid("getAgentV2UserQuota")
    }

    @concurrent public static func getAgentV2ProblemReportAvailability() async throws -> Bool {
        try await bridge.callApi("getAgentV2ProblemReportAvailability", decoding: Bool.self)
    }

    @concurrent public static func setAgentV2ChatActive(_ isActive: Bool) async throws {
        try await bridge.callApiVoid("setAgentV2ChatActive", isActive)
    }

    @concurrent public static func getAgentV2DefaultThread() async throws -> ApiAgentV2DefaultThreadResponse {
        let result = try await bridge.callApi(
            "getAgentV2DefaultThread",
            decoding: ApiAgentV2MutationResult<ApiAgentV2DefaultThreadResponse>.self
        )
        return try requireAgentV2OperationValue(result, methodName: "getAgentV2DefaultThread")
    }

    @concurrent public static func getAgentV2Messages(
        threadId: String,
        cursor: String?,
        limit: Int?
    ) async throws -> ApiAgentV2ThreadHydration {
        let result = try await bridge.callApi(
            "getAgentV2Messages",
            threadId,
            cursor,
            limit,
            decoding: ApiAgentV2MutationResult<ApiAgentV2ThreadHydration>.self
        )
        return try requireAgentV2OperationValue(result, methodName: "getAgentV2Messages")
    }

    @concurrent public static func startAgentV2Run(_ command: ApiAgentV2RunCommand) async throws -> ApiAgentV2RunResult {
        let result = try await bridge.callApi("startAgentV2Run", command, decoding: ApiAgentV2RunResult.self)
        try await bridge.waitForPendingUpdates()
        return result
    }

    @concurrent public static func retryAgentV2Run(clientRunId: String) async throws -> ApiAgentV2RunResult? {
        let result = try await bridge.callApiOptional(
            "retryAgentV2Run",
            clientRunId,
            decodingOptional: ApiAgentV2RunResult.self
        )
        try await bridge.waitForPendingUpdates()
        return result
    }

    @concurrent public static func cancelAgentV2Run(runId: String) async throws -> ApiAgentV2RunCancelResponse {
        try await bridge.callApi("cancelAgentV2Run", runId, decoding: ApiAgentV2RunCancelResponse.self)
    }

    @concurrent public static func clearAgentV2Thread(
        threadId: String,
        expectedRevision: Int
    ) async throws -> ApiAgentV2MutationResult<ApiAgentV2ThreadClearResponse> {
        try await bridge.callApi(
            "clearAgentV2Thread",
            threadId,
            expectedRevision,
            decoding: ApiAgentV2MutationResult<ApiAgentV2ThreadClearResponse>.self
        )
    }

    @concurrent public static func reportAgentV2Problem(
        threadId: String,
        report: ApiAgentV2ProblemReport
    ) async throws -> ApiAgentV2ProblemReportResponse {
        let result = try await bridge.callApi(
            "reportAgentV2Problem",
            threadId,
            report,
            decoding: ApiAgentV2MutationResult<ApiAgentV2ProblemReportResponse>.self
        )
        return try requireAgentV2OperationValue(result, methodName: "reportAgentV2Problem")
    }

    @concurrent public static func getAgentV2ActionPresentation(
        messageId: String,
        actionId: String
    ) async throws -> ApiAgentV2ActionPresentation {
        try await bridge.callApi(
            "getAgentV2ActionPresentation",
            messageId,
            actionId,
            decoding: ApiAgentV2ActionPresentation.self
        )
    }

    @concurrent public static func resolveAgentV2Action(
        messageId: String,
        actionId: String
    ) async throws -> ApiAgentV2ResolvedAction {
        try await bridge.callApi(
            "resolveAgentV2Action",
            messageId,
            actionId,
            decoding: ApiAgentV2ResolvedAction.self
        )
    }

    private static func requireAgentV2OperationValue<Value: Codable & Equatable & Sendable>(
        _ result: ApiAgentV2MutationResult<Value>,
        methodName: String
    ) throws -> Value {
        if let error = result.error {
            throw error
        }
        guard result.ok, let value = result.value else {
            throw SdkError.invalidResponse(
                methodName: methodName,
                reason: "SDK returned an invalid Agent V2 operation result",
                data: nil
            )
        }
        return value
    }
}

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
        try await bridge.waitForPendingUpdates()
    }

    @concurrent public static func getAgentV2UserQuota() async throws {
        try await bridge.callApiVoid("getAgentV2UserQuota")
        try await bridge.waitForPendingUpdates()
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

    /// The SDK's cached latest messages of the thread; `nil` when none are cached or they cannot be read
    @concurrent public static func getAgentV2CachedMessages(threadId: String) async -> ApiAgentV2CachedMessages? {
        try? await bridge.callApiOptional(
            "getAgentV2CachedMessages",
            threadId,
            decodingOptional: ApiAgentV2CachedMessages.self
        )
    }

    @concurrent public static func listAgentV2Threads(
        cursor: String? = nil,
        limit: Int? = nil,
        query: String? = nil
    ) async throws -> ApiAgentV2ThreadListResponse {
        let result = try await bridge.callApi(
            "listAgentV2Threads",
            ApiAgentV2ThreadListRequest(cursor: cursor, limit: limit, query: query),
            decoding: ApiAgentV2MutationResult<ApiAgentV2ThreadListResponse>.self
        )
        return try requireAgentV2OperationValue(result, methodName: "listAgentV2Threads")
    }

    /// The SDK's cached first page of the thread list; `nil` when none is cached or it cannot be read
    @concurrent public static func getAgentV2CachedThreads() async -> [ApiAgentV2ThreadListItem]? {
        try? await bridge.callApiOptional(
            "getAgentV2CachedThreads",
            decodingOptional: [ApiAgentV2ThreadListItem].self
        )
    }

    @concurrent public static func getAgentV2NewsFeed(
        lang: String,
        cursor: String? = nil,
        digestHour: Int,
        digestMinute: Int,
        timeZone: String,
        view: ApiAgentV2NewsFeedView = .all
    ) async throws -> ApiAgentV2NewsFeedPage {
        let result = try await bridge.callApi(
            "getAgentV2NewsFeed",
            ApiAgentV2NewsFeedRequest(
                lang: lang, cursor: cursor, digestHour: digestHour, digestMinute: digestMinute, timeZone: timeZone, view: view
            ),
            decoding: ApiAgentV2MutationResult<ApiAgentV2NewsFeedPage>.self
        )
        return try requireAgentV2OperationValue(result, methodName: "getAgentV2NewsFeed")
    }

    @concurrent public static func createAgentV2Thread(
        news: ApiAgentV2ThreadNewsRequest? = nil,
        digest: ApiAgentV2ThreadDigestRequest? = nil
    ) async throws -> ApiAgentV2ThreadCreateResponse {
        let result: ApiAgentV2MutationResult<ApiAgentV2ThreadCreateResponse>
        if news != nil || digest != nil {
            result = try await bridge.callApi(
                "createAgentV2Thread",
                ApiAgentV2ThreadCreateRequest(news: news, digest: digest),
                decoding: ApiAgentV2MutationResult<ApiAgentV2ThreadCreateResponse>.self
            )
        } else {
            result = try await bridge.callApi(
                "createAgentV2Thread",
                decoding: ApiAgentV2MutationResult<ApiAgentV2ThreadCreateResponse>.self
            )
        }
        return try requireAgentV2OperationValue(result, methodName: "createAgentV2Thread")
    }

    @concurrent public static func updateAgentV2Thread(
        threadId: String,
        update: ApiAgentV2ThreadUpdate
    ) async throws -> ApiAgentV2ThreadUpdateResponse {
        let result = try await bridge.callApi(
            "updateAgentV2Thread",
            threadId,
            update,
            decoding: ApiAgentV2MutationResult<ApiAgentV2ThreadUpdateResponse>.self
        )
        return try requireAgentV2OperationValue(result, methodName: "updateAgentV2Thread")
    }

    @concurrent public static func deleteAgentV2Thread(threadId: String) async throws -> ApiAgentV2ThreadDeleteResponse {
        let result = try await bridge.callApi(
            "deleteAgentV2Thread",
            threadId,
            decoding: ApiAgentV2MutationResult<ApiAgentV2ThreadDeleteResponse>.self
        )
        return try requireAgentV2OperationValue(result, methodName: "deleteAgentV2Thread")
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

    /// Stops every run of the thread; the runtime cancels them on the server itself
    @concurrent public static func stopAgentV2Run(threadId: String) async throws {
        try await bridge.callApiVoid("stopAgentV2Run", threadId)
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

    @concurrent public static func transcribeAgentV2Audio(
        _ request: ApiAgentV2TranscriptionRequest
    ) async throws -> ApiAgentV2TranscriptionResponse {
        let result = try await bridge.callApi(
            "transcribeAgentV2Audio",
            request,
            decoding: ApiAgentV2MutationResult<ApiAgentV2TranscriptionResponse>.self
        )
        return try requireAgentV2OperationValue(result, methodName: "transcribeAgentV2Audio")
    }

    /// Sets the user's rating of the complete answer `messageId`, or withdraws it without `feedback`
    @concurrent public static func setAgentV2MessageFeedback(
        threadId: String,
        messageId: String,
        feedback: ApiAgentV2AnswerFeedback?
    ) async throws -> ApiAgentV2AnswerFeedbackResponse {
        let result = try await bridge.callApi(
            "setAgentV2MessageFeedback",
            threadId,
            messageId,
            feedback,
            decoding: ApiAgentV2MutationResult<ApiAgentV2AnswerFeedbackResponse>.self
        )
        return try requireAgentV2OperationValue(result, methodName: "setAgentV2MessageFeedback")
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

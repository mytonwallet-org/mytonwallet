import Foundation

public enum ApiAgentV2UpdateType: String, Codable, CaseIterable, Sendable {
    case client = "agentV2"
    case portfolioHistory = "agentV2PortfolioHistory"
}

public struct ApiAgentV2HostContextUpdate: Codable, Equatable, Sendable {
    public let authorityChanged: Bool
    public let generation: Int
}

public struct ApiAgentV2ThreadSummary: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let revision: Int
    public let createdAt: String
    public let updatedAt: String
    public let lastActivityAt: String
    public let clearedAt: String?
    public let messageCount: Int
}

public struct ApiAgentV2DefaultThreadResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let thread: ApiAgentV2ThreadSummary
    public let created: Bool
}

public struct ApiAgentV2ThreadResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let thread: ApiAgentV2ThreadSummary
    public let duplicate: Bool?
}

public struct ApiAgentV2ThreadClearResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let thread: ApiAgentV2ThreadSummary
    public let duplicate: Bool
}

/// A problem report on the conversation, or on the stored message `messageId` names
public struct ApiAgentV2ProblemReport: Encodable, Equatable, Sendable {
    public let messageId: String?
    public let comment: String?

    public init(messageId: String?, comment: String?) {
        self.messageId = messageId
        self.comment = comment
    }
}

public struct ApiAgentV2ProblemReportResponse: Codable, Equatable, Sendable {
    public let reportId: String
    public let duplicate: Bool
}

public enum ApiAgentV2ErrorCode: String, Codable, Equatable, Hashable, Sendable {
    case invalidRequest = "invalid_request"
    case invalidEvent = "invalid_event"
    case clientUpdateRequired = "client_update_required"
    case networkError = "network_error"
    case deviceIdInvalid = "device_id_invalid"
    case deviceTokenMissing = "device_token_missing"
    case deviceTokenInvalid = "device_token_invalid"
    case deviceTokenExpired = "device_token_expired"
    case deviceTokenRateLimited = "device_token_rate_limited"
    case profileIdInvalid = "profile_id_invalid"
    case idempotencyMismatch = "idempotency_mismatch"
    case threadRevisionConflict = "thread_revision_conflict"
    case threadNotFound = "thread_not_found"
    case threadRunInProgress = "thread_run_in_progress"
    case runNotFound = "run_not_found"
    case runInterrupted = "run_interrupted"
    case runReplayExpired = "run_replay_expired"
    case runBudgetExceeded = "run_budget_exceeded"
    case outputLimitReached = "output_limit_reached"
    case rateLimited = "rate_limited"
    case userQuotaExhausted = "user_quota_exhausted"
    case agentCapacityExhausted = "agent_capacity_exhausted"
    case contextTooLargeRetryable = "context_too_large_retryable"
    case toolUnsupported = "tool_unsupported"
    case toolScopeMismatch = "tool_scope_mismatch"
    case toolResultAlreadySubmitted = "tool_result_already_submitted"
    case toolRejected = "tool_rejected"
    case walletContextChanged = "wallet_context_changed"
    case toolTimeout = "tool_timeout"
    case toolFailed = "tool_failed"
    case toolResultTooLarge = "tool_result_too_large"
    case marketDataUnavailable = "market_data_unavailable"
    case actionUnsupported = "action_unsupported"
    case messageNotFound = "message_not_found"
    case messageNotEditable = "message_not_editable"
    case regenerateTargetInvalid = "regenerate_target_invalid"
    case followupReferenceInvalid = "followup_reference_invalid"
    case feedbackTargetInvalid = "feedback_target_invalid"
    case feedbackRevisionConflict = "feedback_revision_conflict"
    case providerTimeout = "provider_timeout"
    case providerUnavailable = "provider_unavailable"
    case providerCapabilityUnavailable = "provider_capability_unavailable"
    case providerError = "provider_error"
    case emptyResponse = "empty_response"
    case internalError = "internal_error"
    case profileDeleted = "profile_deleted"
}

public struct ApiAgentV2MutationError: Codable, Equatable, Error, Sendable {
    public let code: ApiAgentV2ErrorCode
    public let retryable: Bool
}

public struct ApiAgentV2MutationResult<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public let ok: Bool
    public let value: Value?
    public let error: ApiAgentV2MutationError?
}

public struct ApiAgentV2MessageError: Codable, Equatable, Hashable, Sendable {
    public let code: ApiAgentV2ErrorCode
    public let retryable: Bool
    public let retryAfterMs: Int?
    public let resetAt: String?

    public init(code: ApiAgentV2ErrorCode, retryable: Bool, retryAfterMs: Int? = nil, resetAt: String? = nil) {
        self.code = code
        self.retryable = retryable
        self.retryAfterMs = retryAfterMs
        self.resetAt = resetAt
    }
}

public enum ApiAgentV2ContentKind: String, Codable, Equatable, Hashable, Sendable {
    case markdown, semantic
}

public enum ApiAgentV2ActionLabelCode: String, Codable, Equatable, Hashable, Sendable {
    case openReceive = "open_receive"
    case openSend = "open_send"
    case openExternalLink = "open_external_link"
    case openStaking = "open_staking"
    case openSwap = "open_swap"
}

public struct ApiAgentV2FollowUp: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let text: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, kind, text
    }

    public init(from decoder: Decoder) throws {
        let dynamicContainer = try decoder.container(keyedBy: ApiAgentV2DynamicCodingKey.self)
        let expectedKeys = Set(CodingKeys.allCases.map(\.rawValue))
        guard Set(dynamicContainer.allKeys.map(\.stringValue)) == expectedKeys else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid Agent V2 follow-up fields")
            )
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        text = try container.decode(String.self, forKey: .text)
        guard kind == "suggested_prompt",
              id.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression) != nil,
              Self.isValidText(text, maximumLength: 80) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid Agent V2 follow-up")
            )
        }
    }

    private static func isValidText(_ value: String, maximumLength: Int) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines) == value
            && !value.isEmpty
            && value.unicodeScalars.count <= maximumLength
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && value.range(
                of: #"(?:[*_~`]|\[[^\]]*\]\(|</?[A-Za-z]|^\s{0,3}(?:#{1,6}|>|[-+*]|\d+[.)])\s)"#,
                options: .regularExpression
            ) == nil
    }
}

private struct ApiAgentV2DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private struct ApiAgentV2LossyFollowUp: Decodable {
    let value: ApiAgentV2FollowUp?

    init(from decoder: Decoder) throws {
        value = try? ApiAgentV2FollowUp(from: decoder)
    }
}

private extension KeyedDecodingContainer {
    func decodeAgentV2FollowUps(forKey key: Key) -> [ApiAgentV2FollowUp] {
        guard let values = try? decode([ApiAgentV2LossyFollowUp].self, forKey: key) else {
            return []
        }
        var ids = Set<String>()
        var followUps = [ApiAgentV2FollowUp]()
        for value in values {
            guard let followUp = value.value, ids.insert(followUp.id).inserted else {
                continue
            }
            followUps.append(followUp)
            if followUps.count == 3 {
                break
            }
        }
        return followUps
    }
}

public enum ApiAgentV2ActionKind: String, Codable, Equatable, Hashable, Sendable {
    case receive, send, stake, swap, openDapp
}

public struct ApiAgentV2PersistedAction: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let kind: ApiAgentV2ActionKind
    public let labelCode: ApiAgentV2ActionLabelCode
    public let title: String
    public let sourceToolCallId: String?
    public let effect: String?
    public let localDraftRequired: Bool?
    public let requiresConfirmation: Bool
}

public struct ApiAgentV2AssetIdentity: Codable, Equatable, Hashable, Sendable {
    public let slug: String
    public let chain: String
    public let symbol: String
    public let name: String?
    public let tokenAddress: String?
    public let decimals: Int?

    public init(
        slug: String,
        chain: String,
        symbol: String,
        name: String?,
        tokenAddress: String?,
        decimals: Int?
    ) {
        self.slug = slug
        self.chain = chain
        self.symbol = symbol
        self.name = name
        self.tokenAddress = tokenAddress
        self.decimals = decimals
    }
}

public indirect enum ApiAgentV2JSONValue: Codable, Equatable, Hashable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([Self]), object([String: Self])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([Self].self) { self = .array(value) }
        else { self = try .object(container.decode([String: Self].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

public struct ApiAgentV2NoticeContent: Codable, Equatable, Hashable, Sendable {
    public enum Code: String, Codable, Equatable, Hashable, Sendable {
        case agentUnavailable = "agent_unavailable"
        case contentOverBudget = "content_over_budget"
        case webSearchNoResults = "web_search_no_results"
    }
    public let kind: String
    public let schemaVersion: Int
    public let code: Code
}

public enum ApiAgentV2SemanticContent: Codable, Equatable, Hashable, Sendable {
    case notice(ApiAgentV2NoticeContent)
    case clientUnsupported

    private enum CodingKeys: String, CodingKey { case kind, schemaVersion, code }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == 1 else {
            self = .clientUnsupported
            return
        }
        switch try container.decode(String.self, forKey: .kind) {
        case "notice":
            let code = try container.decode(String.self, forKey: .code)
            guard ApiAgentV2NoticeContent.Code(rawValue: code) != nil else {
                self = .clientUnsupported
                return
            }
            self = try .notice(ApiAgentV2NoticeContent(from: decoder))
        case "clientUnsupported": self = .clientUnsupported
        default: self = .clientUnsupported
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .notice(let value): try value.encode(to: encoder)
        case .clientUnsupported:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("clientUnsupported", forKey: .kind)
            try container.encode(1, forKey: .schemaVersion)
        }
    }
}

public struct ApiAgentV2AnswerTable: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let content: ApiAgentV2DisplayTable
}

public struct ApiAgentV2DisplayTable: Codable, Equatable, Hashable, Sendable {
    public let kind: String
    public let headers: [String]
    public let rows: [[String]]
    public let notes: [String]
}

public struct ApiAgentV2AnswerTableReference: Codable, Equatable, Hashable, Sendable {
    public let tableId: String
    public let textOffset: Int
}

/// A link over a label of answer text; offsets are UTF-16 and share the space of table references
public struct ApiAgentV2AnswerLink: Codable, Equatable, Hashable, Sendable {
    public let textOffset: Int
    public let textLength: Int
    public let url: String

    public init(textOffset: Int, textLength: Int, url: String) {
        self.textOffset = textOffset
        self.textLength = textLength
        self.url = url
    }
}

public struct ApiAgentV2ComposedMarkdown: Codable, Equatable, Hashable, Sendable {
    public let text: String
    public let tables: [ApiAgentV2AnswerTable]
    public let tableReferences: [ApiAgentV2AnswerTableReference]
    public let links: [ApiAgentV2AnswerLink]

    private enum CodingKeys: String, CodingKey { case text, tables, tableReferences, links }

    public init(
        text: String,
        tables: [ApiAgentV2AnswerTable],
        tableReferences: [ApiAgentV2AnswerTableReference],
        links: [ApiAgentV2AnswerLink] = []
    ) {
        self.text = text
        self.tables = tables
        self.tableReferences = tableReferences
        self.links = links
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        tables = try container.decode([ApiAgentV2AnswerTable].self, forKey: .tables)
        tableReferences = try container.decode([ApiAgentV2AnswerTableReference].self, forKey: .tableReferences)
        links = try container.decodeIfPresent([ApiAgentV2AnswerLink].self, forKey: .links) ?? []
    }
}

public enum ApiAgentV2MessageContent: Codable, Equatable, Hashable, Sendable {
    case markdown(String)
    case composedMarkdown(ApiAgentV2ComposedMarkdown)
    case semantic(ApiAgentV2SemanticContent)

    private enum CodingKeys: String, CodingKey { case kind, text, content, tables, tableReferences, links }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "markdown":
            let text = try container.decode(String.self, forKey: .text)
            let tables = try container.decodeIfPresent([ApiAgentV2AnswerTable].self, forKey: .tables) ?? []
            let references = try container.decodeIfPresent([ApiAgentV2AnswerTableReference].self, forKey: .tableReferences) ?? []
            let links = try container.decodeIfPresent([ApiAgentV2AnswerLink].self, forKey: .links) ?? []
            self = tables.isEmpty && links.isEmpty
                ? .markdown(text)
                : .composedMarkdown(.init(text: text, tables: tables, tableReferences: references, links: links))
        case "semantic": self = try .semantic(container.decode(ApiAgentV2SemanticContent.self, forKey: .content))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unsupported Agent V2 message content")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .markdown(let text):
            try container.encode("markdown", forKey: .kind)
            try container.encode(text, forKey: .text)
        case .composedMarkdown(let content):
            try container.encode("markdown", forKey: .kind)
            try container.encode(content.text, forKey: .text)
            try container.encode(content.tables, forKey: .tables)
            try container.encode(content.tableReferences, forKey: .tableReferences)
            if !content.links.isEmpty {
                try container.encode(content.links, forKey: .links)
            }
        case .semantic(let content):
            try container.encode("semantic", forKey: .kind)
            try container.encode(content, forKey: .content)
        }
    }
}

public enum ApiAgentV2MessageRole: String, Codable, Equatable, Hashable, Sendable {
    case user, assistant
}

public enum ApiAgentV2PersistedMessageStatus: String, Codable, Equatable, Hashable, Sendable {
    case complete, error, cancelled
}

public struct ApiAgentV2PersistedMessage: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let threadId: String
    public let role: ApiAgentV2MessageRole
    public let status: ApiAgentV2PersistedMessageStatus
    public let content: ApiAgentV2MessageContent?
    public let createdAt: String
    public let runId: String?
    public let responseLanguage: String?
    public let error: ApiAgentV2MessageError?
    public let actions: [ApiAgentV2PersistedAction]?
    public let followups: [ApiAgentV2FollowUp]?

    private enum CodingKeys: String, CodingKey {
        case id, threadId, role, status, content, createdAt, runId, responseLanguage, error, actions, followups
        case text, textFormat, widget
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in [CodingKeys.text, .textFormat, .widget] where container.contains(key) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Removed Agent V2 message content field"
            )
        }
        id = try container.decode(String.self, forKey: .id)
        threadId = try container.decode(String.self, forKey: .threadId)
        role = try container.decode(ApiAgentV2MessageRole.self, forKey: .role)
        status = try container.decode(ApiAgentV2PersistedMessageStatus.self, forKey: .status)
        content = try container.decodeIfPresent(ApiAgentV2MessageContent.self, forKey: .content)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        runId = try container.decodeIfPresent(String.self, forKey: .runId)
        responseLanguage = try container.decodeIfPresent(String.self, forKey: .responseLanguage)
        error = try container.decodeIfPresent(ApiAgentV2MessageError.self, forKey: .error)
        actions = try container.decodeIfPresent([ApiAgentV2PersistedAction].self, forKey: .actions)
        if container.contains(.followups), try container.decodeNil(forKey: .followups) == false {
            followups = container.decodeAgentV2FollowUps(forKey: .followups)
        } else {
            followups = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(threadId, forKey: .threadId)
        try container.encode(role, forKey: .role)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(runId, forKey: .runId)
        try container.encodeIfPresent(responseLanguage, forKey: .responseLanguage)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(actions, forKey: .actions)
        try container.encodeIfPresent(followups, forKey: .followups)
    }
}

public struct ApiAgentV2ThreadHydration: Codable, Equatable, Sendable {
    public let thread: ApiAgentV2ThreadSummary
    public let messages: [ApiAgentV2PersistedMessage]
    public let nextCursor: String?
}

public struct ApiAgentV2StarterHint: Codable, Equatable, Hashable, Sendable {
    public enum ID: String, Codable, Equatable, Hashable, Sendable {
        case agentCapabilities = "agent.capabilities"
        case portfolioPerformance = "portfolio.performance"
        case learnSwap = "learn.swap"
        case learnStaking = "learn.staking"
        case learnSecurity = "learn.security"
        case receiveTokens = "receive.tokens"
    }
    public let id: ID
    public let requiredCapabilities: [String]?
}

public struct ApiAgentV2HintsResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let catalogVersion: String
    public let items: [ApiAgentV2StarterHint]
}

public struct ApiAgentV2HostAsset: Codable, Equatable, Sendable {
    public let slug: String
    public let chain: String
    public let symbol: String
    public let name: String?
    public let tokenAddress: String?
    public let decimals: Int
    public let priceUsd: String?
    public let percentChange24h: String?

    public init(
        slug: String,
        chain: String,
        symbol: String,
        name: String?,
        tokenAddress: String?,
        decimals: Int,
        priceUsd: String? = nil,
        percentChange24h: String? = nil
    ) {
        self.slug = slug
        self.chain = chain
        self.symbol = symbol
        self.name = name
        self.tokenAddress = tokenAddress
        self.decimals = decimals
        self.priceUsd = priceUsd
        self.percentChange24h = percentChange24h
    }
}

public struct ApiAgentV2HostHolding: Codable, Equatable, Sendable {
    public let asset: ApiAgentV2HostAsset
    public let balance: String
    public let availableBalance: String?
    public let fiatValue: String?
    public let fiatPrice: String?
    public let valuationStatus: String?
    public let visibility: String?
    public let riskVerdict: String?

    public init(
        asset: ApiAgentV2HostAsset,
        balance: String,
        availableBalance: String?,
        fiatValue: String?,
        fiatPrice: String? = nil,
        valuationStatus: String? = nil,
        visibility: String? = nil,
        riskVerdict: String? = nil
    ) {
        self.asset = asset
        self.balance = balance
        self.availableBalance = availableBalance
        self.fiatValue = fiatValue
        self.fiatPrice = fiatPrice
        self.valuationStatus = valuationStatus
        self.visibility = visibility
        self.riskVerdict = riskVerdict
    }
}



public struct ApiAgentV2HostDomainState: Codable, Equatable, Sendable {
    public let state: String
    public let updatedAt: String?

    public init(state: String, updatedAt: String? = nil) {
        self.state = state
        self.updatedAt = updatedAt
    }
}

public struct ApiAgentV2HostPosition: Codable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let chain: String
    public let label: String
    public let asset: ApiAgentV2HostAsset?
    public let quantity: String?
    public let valuationStatus: String
    public let fiatValue: String?
    public let status: String?
    public let apy: String?
    public let rewards: String?
    public let collection: String?
    public let isOnSale: Bool?
    public let visibility: String?
    public let riskVerdict: String?

    public init(
        id: String,
        kind: String,
        chain: String,
        label: String,
        asset: ApiAgentV2HostAsset? = nil,
        quantity: String? = nil,
        valuationStatus: String,
        fiatValue: String? = nil,
        status: String? = nil,
        apy: String? = nil,
        rewards: String? = nil,
        collection: String? = nil,
        isOnSale: Bool? = nil,
        visibility: String? = nil,
        riskVerdict: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.chain = chain
        self.label = label
        self.asset = asset
        self.quantity = quantity
        self.valuationStatus = valuationStatus
        self.fiatValue = fiatValue
        self.status = status
        self.apy = apy
        self.rewards = rewards
        self.collection = collection
        self.isOnSale = isOnSale
        self.visibility = visibility
        self.riskVerdict = riskVerdict
    }
}

public struct ApiAgentV2HostAccount: Codable, Equatable, Sendable {
    public let accountId: String
    public let label: String?
    public let state: String
    public let accountType: String
    public let isViewOnly: Bool
    public let chains: [String]
    public let addresses: [String: String]
    public let portfolioWalletKeys: [String]?
    public let holdings: [ApiAgentV2HostHolding]
    public let positions: [ApiAgentV2HostPosition]?
    public let savedAddresses: [ApiAgentV2HostSavedAddress]?
    /// The networks whose NFTs the app has read in full
    public let nftLoadedChains: [String]?
    public let domainStates: [String: ApiAgentV2HostDomainState]?

    public init(
        accountId: String,
        label: String?,
        state: String,
        accountType: String,
        isViewOnly: Bool,
        chains: [String],
        addresses: [String: String],
        portfolioWalletKeys: [String]? = nil,
        holdings: [ApiAgentV2HostHolding],
        positions: [ApiAgentV2HostPosition]? = nil,
        savedAddresses: [ApiAgentV2HostSavedAddress]? = nil,
        nftLoadedChains: [String]? = nil,
        domainStates: [String: ApiAgentV2HostDomainState]? = nil
    ) {
        self.accountId = accountId
        self.label = label
        self.state = state
        self.accountType = accountType
        self.isViewOnly = isViewOnly
        self.chains = chains
        self.addresses = addresses
        self.portfolioWalletKeys = portfolioWalletKeys
        self.holdings = holdings
        self.positions = positions
        self.savedAddresses = savedAddresses
        self.nftLoadedChains = nftLoadedChains
        self.domainStates = domainStates
    }
}

public struct ApiAgentV2HostSavedAddress: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let chain: String
    public let address: String

    public init(id: String, name: String, chain: String, address: String) {
        self.id = id
        self.name = name
        self.chain = chain
        self.address = address
    }
}

public struct ApiAgentV2HostUiCapabilities: Codable, Equatable, Sendable {
    public let supportedActions: [String]
    public let supportsFollowups: Bool
    public let supportsRunActivity: Bool
    public let supportsWalletDirectory: Bool
    public let supportsMessageEdit: Bool
    public let supportsRegenerate: Bool
    public let supportsSendRecipientWithoutAsset: Bool?

    public init(
        supportedActions: [String],
        supportsFollowups: Bool,
        supportsRunActivity: Bool,
        supportsWalletDirectory: Bool,
        supportsMessageEdit: Bool,
        supportsRegenerate: Bool,
        supportsSendRecipientWithoutAsset: Bool? = nil
    ) {
        self.supportedActions = supportedActions
        self.supportsFollowups = supportsFollowups
        self.supportsRunActivity = supportsRunActivity
        self.supportsWalletDirectory = supportsWalletDirectory
        self.supportsMessageEdit = supportsMessageEdit
        self.supportsRegenerate = supportsRegenerate
        self.supportsSendRecipientWithoutAsset = supportsSendRecipientWithoutAsset
    }
}

public struct ApiAgentV2HostContext: Codable, Equatable, Sendable {
    public let uiCapabilities: ApiAgentV2HostUiCapabilities
    public let platform: String
    public let client: String
    public let lang: String
    public let baseCurrency: String
    public let currencyRate: String?
    public let timeZone: String?
    public let appVersion: String?
    public let theme: String?
    public let activeAccountId: String?
    public let activeNetwork: String?
    public let isTestnet: Bool?
    public let isStakingDisabled: Bool?
    public let accounts: [ApiAgentV2HostAccount]
    public let assetCatalog: [ApiAgentV2HostAsset]?
    public let swapAssetCatalog: [ApiAgentV2HostAsset]?
    public let savedAddresses: [ApiAgentV2HostSavedAddress]

    public init(
        platform: String = "ios",
        client: String = "native",
        uiCapabilities: ApiAgentV2HostUiCapabilities,
        lang: String,
        baseCurrency: String,
        currencyRate: String? = nil,
        timeZone: String? = nil,
        appVersion: String?,
        theme: String?,
        activeAccountId: String?,
        activeNetwork: String?,
        isTestnet: Bool? = nil,
        isStakingDisabled: Bool? = nil,
        accounts: [ApiAgentV2HostAccount],
        assetCatalog: [ApiAgentV2HostAsset]? = nil,
        swapAssetCatalog: [ApiAgentV2HostAsset]? = nil,
        savedAddresses: [ApiAgentV2HostSavedAddress]
    ) {
        self.uiCapabilities = uiCapabilities
        self.platform = platform
        self.client = client
        self.lang = lang
        self.baseCurrency = baseCurrency
        self.currencyRate = currencyRate
        self.timeZone = timeZone
        self.appVersion = appVersion
        self.theme = theme
        self.activeAccountId = activeAccountId
        self.activeNetwork = activeNetwork
        self.isTestnet = isTestnet
        self.isStakingDisabled = isStakingDisabled
        self.accounts = accounts
        self.assetCatalog = assetCatalog
        self.swapAssetCatalog = swapAssetCatalog
        self.savedAddresses = savedAddresses
    }
}

public enum ApiAgentV2RunInput: Encodable, Equatable, Sendable {
    case append(text: String)
    case edit(targetUserMessageId: String, text: String)
    case regenerate(targetAssistantMessageId: String)

    private enum CodingKeys: String, CodingKey {
        case kind, text, targetUserMessageId, targetAssistantMessageId
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .append(let text):
            try container.encode("append", forKey: .kind)
            try container.encode(text, forKey: .text)
        case .edit(let messageId, let text):
            try container.encode("edit", forKey: .kind)
            try container.encode(messageId, forKey: .targetUserMessageId)
            try container.encode(text, forKey: .text)
        case .regenerate(let messageId):
            try container.encode("regenerate", forKey: .kind)
            try container.encode(messageId, forKey: .targetAssistantMessageId)
        }
    }
}

public enum ApiAgentV2EntryPoint: Codable, Equatable, Sendable {
    public struct TokenAsset: Codable, Equatable, Sendable {
        public let slug: String
        public let chain: String
        public let tokenAddress: String?

        public init(slug: String, chain: String, tokenAddress: String?) {
            self.slug = slug
            self.chain = chain
            self.tokenAddress = tokenAddress
        }
    }

    case agentTab
    case portfolioChart(chartId: String, range: String, source: String?)
    case tokenScreen(asset: TokenAsset)
    case globalSearch(query: String)
    case emptyState(hintId: String?, catalogVersion: String?)

    private enum CodingKeys: String, CodingKey {
        case kind, chartId, range, accountScope, source, asset, query, surface, hintId, catalogVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "agentTab":
            self = .agentTab
        case "portfolioChart":
            self = try .portfolioChart(
                chartId: container.decode(String.self, forKey: .chartId),
                range: container.decode(String.self, forKey: .range),
                source: container.decodeIfPresent(String.self, forKey: .source)
            )
        case "tokenScreen":
            self = try .tokenScreen(asset: container.decode(TokenAsset.self, forKey: .asset))
        case "globalSearch":
            self = try .globalSearch(query: container.decode(String.self, forKey: .query))
        case "emptyState":
            guard try container.decode(String.self, forKey: .surface) == "agentTab" else {
                throw DecodingError.dataCorruptedError(
                    forKey: .surface,
                    in: container,
                    debugDescription: "Unsupported Agent V2 empty-state surface"
                )
            }
            self = try .emptyState(
                hintId: container.decodeIfPresent(String.self, forKey: .hintId),
                catalogVersion: container.decodeIfPresent(String.self, forKey: .catalogVersion)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported Agent V2 entry point"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .agentTab:
            try container.encode("agentTab", forKey: .kind)
        case .portfolioChart(let chartId, let range, let source):
            try container.encode("portfolioChart", forKey: .kind)
            try container.encode(chartId, forKey: .chartId)
            try container.encode(range, forKey: .range)
            try container.encode("current", forKey: .accountScope)
            try container.encodeIfPresent(source, forKey: .source)
        case .tokenScreen(let asset):
            try container.encode("tokenScreen", forKey: .kind)
            try container.encode(asset, forKey: .asset)
        case .globalSearch(let query):
            try container.encode("globalSearch", forKey: .kind)
            try container.encode(query, forKey: .query)
        case .emptyState(let hintId, let catalogVersion):
            try container.encode("emptyState", forKey: .kind)
            try container.encode("agentTab", forKey: .surface)
            try container.encodeIfPresent(hintId, forKey: .hintId)
            try container.encodeIfPresent(catalogVersion, forKey: .catalogVersion)
        }
    }
}

public struct ApiAgentV2RunCommand: Encodable, Equatable, Sendable {
    public struct FollowUpReference: Encodable, Equatable, Sendable {
        public let messageId: String
        public let followupId: String

        public init(messageId: String, followupId: String) {
            self.messageId = messageId
            self.followupId = followupId
        }
    }

    public let threadId: String?
    public let expectedThreadRevision: Int
    public let input: ApiAgentV2RunInput
    public let entryPoint: ApiAgentV2EntryPoint?
    public let followupOf: FollowUpReference?

    public init(
        threadId: String?,
        expectedThreadRevision: Int,
        input: ApiAgentV2RunInput,
        entryPoint: ApiAgentV2EntryPoint?,
        followupOf: FollowUpReference? = nil
    ) {
        self.threadId = threadId
        self.expectedThreadRevision = expectedThreadRevision
        self.input = input
        self.entryPoint = entryPoint
        self.followupOf = followupOf
    }
}

public enum ApiAgentV2RunResultState: String, Codable, Equatable, Sendable {
    case completed, failed, cancelled, interrupted
}

public enum ApiAgentV2RunCancelState: String, Codable, Equatable, Sendable {
    case completed
    case completedWithToolError = "completed_with_tool_error"
    case failed, cancelled
    case runInterrupted = "run_interrupted"
}

public struct ApiAgentV2RunResult: Codable, Equatable, Sendable {
    public let clientRunId: String
    public let runId: String?
    public let inputMessageId: String?
    public let state: ApiAgentV2RunResultState
}

public struct ApiAgentV2RunCancelResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let runId: String
    public let state: ApiAgentV2RunCancelState
    public let lastSequence: Int
    public let duplicate: Bool?
}

public struct ApiAgentV2ActionProposal: Codable, Equatable, Hashable, Sendable {
    public struct ContextBinding: Codable, Equatable, Hashable, Sendable {
        public let sessionId: String
        public let revision: Int
        public let activeAccountRef: String
        public let activeNetwork: String?
    }

    public let id: String
    public let kind: ApiAgentV2ActionKind
    public let labelCode: ApiAgentV2ActionLabelCode
    public let title: String
    public let sourceToolCallId: String?
    public let assetRefs: [String]?
    public let contextBinding: ContextBinding?
    public let effect: String?
    public let localMutationRequired: Bool?
    public let requiresConfirmation: Bool
}

public enum ApiAgentV2ActionPresentation: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case send, inactive
    }

    public enum Status: String, Codable, Sendable {
        case active
    }

    public enum FeeStatus: String, Codable, Sendable {
        case estimated
        case calculatedInWallet = "calculated_in_wallet"
    }

    public struct Amount: Codable, Equatable, Sendable {
        public let value: String
        public let symbol: String
    }

    public struct Recipient: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case savedAddress, external, domain
        }

        public let kind: Kind
        public let label: String?
    }

    public struct Send: Codable, Equatable, Sendable {
        public let kind: Kind
        public let status: Status
        public let amount: Amount?
        public let network: String
        public let accountLabel: String
        public let recipient: Recipient?
        public let feeStatus: FeeStatus
        public let warningCodes: [String]
        public let expiresAt: String?
    }

    case send(Send)
    case inactive

    public var kind: Kind {
        switch self {
        case .send: .send
        case .inactive: .inactive
        }
    }

    public var status: Status? {
        guard case .send(let value) = self else { return nil }
        return value.status
    }

    public var expiresAt: String? {
        guard case .send(let value) = self else { return nil }
        return value.expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .send:
            self = try .send(Send(from: decoder))
        case .inactive:
            self = .inactive
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .send(let value):
            try value.encode(to: encoder)
        case .inactive:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Kind.inactive, forKey: .kind)
        }
    }
}

public struct ApiAgentV2ResolvedAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case openReceive, openStaking, openSwap, openPortfolio, inactive
        case openDapp
        case openSend = "sendForm"
    }

    public struct StakeAmount: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case exact, all
        }

        public let kind: Kind
        public let value: String?
    }

    public enum AmountSide: String, Codable, Sendable {
        case source, destination
    }

    public let kind: Kind
    public let chain: String?
    public let tokenSlug: String?
    public let toAddress: String?
    public let range: String?
    public let productId: String?
    public let stakeAmount: StakeAmount?
    public let tokenInSlug: String?
    public let tokenOutSlug: String?
    public let swapAmount: String?
    public let amountSide: AmountSide?
    public let url: String?
    /// Send opens with the most the wallet can send of the asset, as its Max button does
    public let isMaxAmount: Bool

    private enum CodingKeys: String, CodingKey {
        case kind, chain, tokenSlug, toAddress, range
        case productId, tokenInSlug, tokenOutSlug, amount, amountSide, url, isMaxAmount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        chain = try container.decodeIfPresent(String.self, forKey: .chain)
        tokenSlug = try container.decodeIfPresent(String.self, forKey: .tokenSlug)
        toAddress = try container.decodeIfPresent(String.self, forKey: .toAddress)
        range = try container.decodeIfPresent(String.self, forKey: .range)
        productId = try container.decodeIfPresent(String.self, forKey: .productId)
        tokenInSlug = try container.decodeIfPresent(String.self, forKey: .tokenInSlug)
        tokenOutSlug = try container.decodeIfPresent(String.self, forKey: .tokenOutSlug)
        amountSide = try container.decodeIfPresent(AmountSide.self, forKey: .amountSide)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        isMaxAmount = try container.decodeIfPresent(Bool.self, forKey: .isMaxAmount) ?? false
        if kind == .openStaking {
            stakeAmount = try container.decodeIfPresent(StakeAmount.self, forKey: .amount)
            swapAmount = nil
        } else if kind == .openSwap {
            stakeAmount = nil
            swapAmount = try container.decodeIfPresent(String.self, forKey: .amount)
        } else {
            stakeAmount = nil
            swapAmount = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(chain, forKey: .chain)
        try container.encodeIfPresent(tokenSlug, forKey: .tokenSlug)
        try container.encodeIfPresent(toAddress, forKey: .toAddress)
        try container.encodeIfPresent(range, forKey: .range)
        try container.encodeIfPresent(productId, forKey: .productId)
        try container.encodeIfPresent(tokenInSlug, forKey: .tokenInSlug)
        try container.encodeIfPresent(tokenOutSlug, forKey: .tokenOutSlug)
        try container.encodeIfPresent(amountSide, forKey: .amountSide)
        try container.encodeIfPresent(url, forKey: .url)
        if isMaxAmount {
            try container.encode(isMaxAmount, forKey: .isMaxAmount)
        }
        if kind == .openStaking {
            try container.encodeIfPresent(stakeAmount, forKey: .amount)
        } else if kind == .openSwap {
            try container.encodeIfPresent(swapAmount, forKey: .amount)
        }
    }
}

public struct ApiAgentV2ClientUpdateEnvelope: Decodable, Sendable {
    public let type: ApiAgentV2UpdateType
    public let update: ApiAgentV2ClientUpdate
}

public struct ApiAgentV2PortfolioHistoryUpdate: Decodable, Sendable {
    public let type: ApiAgentV2UpdateType
    public let accountId: String
    public let baseCurrency: String
    public let range: ApiPriceHistoryPeriod
    public let fetchedAtSlot: Int
    public let netWorth: ApiPortfolioHistoryResponse
}

public struct ApiAgentV2AvailabilityState: Decodable, Equatable, Sendable {
    public enum State: String, Decodable, Equatable, Sendable {
        case available
        case capacityExhausted = "capacity_exhausted"
    }

    public let state: State
    public let resetAt: Double?

    public init(state: State, resetAt: Double? = nil) {
        self.state = state
        self.resetAt = resetAt
    }
}

public struct ApiAgentV2UserQuota: Decodable, Equatable, Sendable {
    public let limit: Int
    public let used: Int
    public let remaining: Int
    public let resetAt: String
}

public struct ApiAgentV2RunActivityEvent: Decodable, Equatable, Sendable {
    public enum Code: String, Decodable, Equatable, Sendable {
        case planning = "request.planning"
        case webSearching = "web.searching"
        case webReadingSources = "web.reading_sources"
        case helpSearching = "help.searching"
        case marketData = "data.reading_market"
        case checkingFreshness = "analysis.checking_freshness"
        case computing = "analysis.computing"
        case writing = "answer.writing"
    }

    public enum Status: String, Decodable, Equatable, Sendable {
        case active, completed
    }

    public struct Detail: Decodable, Equatable, Sendable {
        public enum Kind: String, Decodable, Equatable, Sendable {
            case sourceCount = "source_count"
        }

        public let kind: Kind
        public let count: Int
    }

    public let protocolVersion: Int
    public let runId: String
    public let sequence: Int
    public let code: Code
    public let status: Status
    public let detail: Detail?
    public let createdAt: String?
}

public enum ApiAgentV2ClientUpdate: Decodable, Sendable {
    case runtimeReady(generation: Int)
    case runStarted(Bound, threadRevision: Int, inputMessageId: String?)
    case messageStarted(
        Bound,
        messageId: String,
        contentKind: ApiAgentV2ContentKind,
        responseLanguage: String?
    )
    case textDelta(Bound, messageId: String, delta: String)
    case answerTablesChanged(Bound, messageId: String, tables: [ApiAgentV2AnswerTable], tableReferences: [ApiAgentV2AnswerTableReference])
    case answerLinkAdded(Bound, messageId: String, link: ApiAgentV2AnswerLink)
    case messageContentEnded(Bound, messageId: String)
    case messageCompleted(Bound, messageId: String, finishReason: String)
    case actionAvailable(Bound, messageId: String, action: ApiAgentV2ActionProposal)
    case followupsAvailable(Bound, messageId: String, items: [ApiAgentV2FollowUp])
    case semanticContentAvailable(Bound, messageId: String, content: ApiAgentV2SemanticContent)
    case toolActivityChanged(
        Bound,
        toolCallId: String,
        toolName: String,
        operation: String?,
        status: String
    )
    case runActivityChanged(Bound, event: ApiAgentV2RunActivityEvent)
    case runFailed(
        Bound?,
        clientRunId: String,
        threadId: String?,
        messageId: String?,
        code: ApiAgentV2ErrorCode,
        retryable: Bool,
        resetAt: Double?
    )
    case runCancelled(Bound)
    case availabilityChanged(ApiAgentV2AvailabilityState)
    case userQuotaChanged(ApiAgentV2UserQuota?)
    case walletAuthorityChanged(threadId: String?, preservesActiveRuns: Bool)
    case walletContextChanged
    case threadChanged(threadId: String, thread: ApiAgentV2ThreadSummary)

    public struct Bound: Decodable, Equatable, Sendable {
        public let clientRunId: String
        public let runId: String
        public let threadId: String
    }

    private enum CodingKeys: String, CodingKey {
        case kind, generation, clientRunId, runId, threadId, threadRevision, messageId, inputMessageId, delta, finishReason, contentKind, responseLanguage
        case action, items, content, code, retryable, resetAt, availability, quota, thread
        case toolCallId, toolName, operation, status, event, tables, tableReferences, link, preservesActiveRuns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        func bound() throws -> Bound {
            try Bound(
                clientRunId: container.decode(String.self, forKey: .clientRunId),
                runId: container.decode(String.self, forKey: .runId),
                threadId: container.decode(String.self, forKey: .threadId)
            )
        }

        switch kind {
        case "runtimeReady":
            self = try .runtimeReady(generation: container.decode(Int.self, forKey: .generation))
        case "runStarted":
            self = try .runStarted(
                bound(),
                threadRevision: container.decode(Int.self, forKey: .threadRevision),
                inputMessageId: container.decodeIfPresent(String.self, forKey: .inputMessageId)
            )
        case "messageStarted":
            self = try .messageStarted(
                bound(),
                messageId: container.decode(String.self, forKey: .messageId),
                contentKind: container.decode(ApiAgentV2ContentKind.self, forKey: .contentKind),
                responseLanguage: container.decodeIfPresent(String.self, forKey: .responseLanguage)
            )
        case "textDelta":
            self = try .textDelta(
                bound(),
                messageId: container.decode(String.self, forKey: .messageId),
                delta: container.decode(String.self, forKey: .delta)
            )
        case "answerTablesChanged":
            self = try .answerTablesChanged(
                bound(), messageId: container.decode(String.self, forKey: .messageId),
                tables: container.decode([ApiAgentV2AnswerTable].self, forKey: .tables),
                tableReferences: container.decode([ApiAgentV2AnswerTableReference].self, forKey: .tableReferences)
            )
        case "answerLinkAdded":
            self = try .answerLinkAdded(
                bound(), messageId: container.decode(String.self, forKey: .messageId),
                link: container.decode(ApiAgentV2AnswerLink.self, forKey: .link)
            )
        case "messageContentEnded":
            self = try .messageContentEnded(
                bound(),
                messageId: container.decode(String.self, forKey: .messageId)
            )
        case "messageCompleted":
            self = try .messageCompleted(
                bound(),
                messageId: container.decode(String.self, forKey: .messageId),
                finishReason: container.decode(String.self, forKey: .finishReason)
            )
        case "actionAvailable":
            self = try .actionAvailable(
                bound(),
                messageId: container.decode(String.self, forKey: .messageId),
                action: container.decode(ApiAgentV2ActionProposal.self, forKey: .action)
            )
        case "followupsAvailable":
            self = try .followupsAvailable(
                bound(),
                messageId: container.decode(String.self, forKey: .messageId),
                items: container.decodeAgentV2FollowUps(forKey: .items)
            )
        case "semanticContentAvailable":
            self = try .semanticContentAvailable(
                bound(),
                messageId: container.decode(String.self, forKey: .messageId),
                content: container.decode(ApiAgentV2SemanticContent.self, forKey: .content)
            )
        case "toolActivityChanged":
            self = try .toolActivityChanged(
                bound(),
                toolCallId: container.decode(String.self, forKey: .toolCallId),
                toolName: container.decode(String.self, forKey: .toolName),
                operation: container.decodeIfPresent(String.self, forKey: .operation),
                status: container.decode(String.self, forKey: .status)
            )
        case "runActivityChanged":
            self = try .runActivityChanged(
                bound(),
                event: container.decode(ApiAgentV2RunActivityEvent.self, forKey: .event)
            )
        case "runFailed":
            let clientRunId = try container.decode(String.self, forKey: .clientRunId)
            let runId = try container.decodeIfPresent(String.self, forKey: .runId)
            let threadId = try container.decodeIfPresent(String.self, forKey: .threadId)
            let binding = runId.flatMap { runId in threadId.map { Bound(clientRunId: clientRunId, runId: runId, threadId: $0) } }
            self = try .runFailed(
                binding,
                clientRunId: clientRunId,
                threadId: threadId,
                messageId: container.decodeIfPresent(String.self, forKey: .messageId),
                code: container.decode(ApiAgentV2ErrorCode.self, forKey: .code),
                retryable: container.decode(Bool.self, forKey: .retryable),
                resetAt: container.decodeIfPresent(Double.self, forKey: .resetAt)
            )
        case "runCancelled":
            self = try .runCancelled(bound())
        case "availabilityChanged":
            self = try .availabilityChanged(
                container.decode(ApiAgentV2AvailabilityState.self, forKey: .availability)
            )
        case "userQuotaChanged":
            self = try .userQuotaChanged(
                container.decodeIfPresent(ApiAgentV2UserQuota.self, forKey: .quota)
            )
        case "walletAuthorityChanged":
            self = try .walletAuthorityChanged(
                threadId: container.decodeIfPresent(String.self, forKey: .threadId),
                preservesActiveRuns: container.decodeIfPresent(Bool.self, forKey: .preservesActiveRuns) ?? false
            )
        case "walletContextChanged":
            self = .walletContextChanged
        case "threadChanged":
            self = try .threadChanged(
                threadId: container.decode(String.self, forKey: .threadId),
                thread: container.decode(ApiAgentV2ThreadSummary.self, forKey: .thread)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unsupported Agent V2 update")
        }
    }
}

import Foundation
import WalletContext
import WalletCore

enum AgentV2Copy {
    struct Prompt {
        let title: String
        var prompt: String { title }
    }

    static func hint(_ id: ApiAgentV2StarterHint.ID) -> Prompt {
        switch id {
        case .agentCapabilities: Prompt(title: lang("$agent_hint_capabilities_title"))
        case .portfolioPerformance: Prompt(title: lang("$agent_hint_portfolio_title"))
        case .learnSwap: Prompt(title: lang("$agent_hint_swap_title"))
        case .learnStaking: Prompt(title: lang("$agent_hint_staking_title"))
        case .learnSecurity: Prompt(title: lang("$agent_hint_security_title"))
        case .receiveTokens: Prompt(title: lang("$agent_hint_receive_title"))
        }
    }

    static func runActivity(_ event: ApiAgentV2RunActivityEvent) -> String {
        if event.status == .completed {
            if event.code == .webReadingSources, let count = event.detail?.count {
                return langFormat("$agent_activity_web_reading_sources_completed", count)
            }
            return switch event.code {
            case .planning: lang("$agent_activity_planning_completed")
            case .webSearching: lang("$agent_activity_web_searching_completed")
            case .webReadingSources: lang("$agent_activity_web_reading_sources_completed_generic")
            case .helpSearching: lang("$agent_activity_help_searching_completed")
            case .marketData: lang("$agent_activity_market_data_completed")
            case .checkingFreshness: lang("$agent_activity_checking_freshness_completed")
            case .computing: lang("$agent_activity_computing_completed")
            case .writing: lang("$agent_activity_writing_completed")
            }
        }

        return switch event.code {
        case .planning: lang("$agent_activity_planning")
        case .webSearching: lang("$agent_activity_web_searching")
        case .webReadingSources: lang("$agent_activity_web_reading_sources")
        case .helpSearching: lang("$agent_activity_help_searching")
        case .marketData: lang("$agent_activity_market_data")
        case .checkingFreshness: lang("$agent_activity_checking_freshness")
        case .computing: lang("$agent_activity_computing")
        case .writing: lang("$agent_activity_writing")
        }
    }

    static func notice(_ notice: ApiAgentV2NoticeContent) -> String {
        self.notice(notice.code)
    }

    static func notice(_ code: ApiAgentV2NoticeContent.Code) -> String {
        switch code {
        case .agentUnavailable: lang("$agent_error_generic")
        case .contentOverBudget: lang("$agent_notice_content_over_budget")
        case .webSearchNoResults: lang("$agent_notice_web_search_no_results")
        }
    }

    static func error(_ code: ApiAgentV2ErrorCode) -> String {
        switch code {
        case .clientUpdateRequired:
            lang("$agent_error_update_required")
        case .deviceTokenMissing, .deviceTokenInvalid, .deviceTokenExpired, .profileIdInvalid, .profileDeleted:
            lang("$agent_error_session")
        case .rateLimited, .userQuotaExhausted, .agentCapacityExhausted, .runBudgetExceeded,
             .outputLimitReached, .contextTooLargeRetryable, .deviceTokenRateLimited:
            lang("$agent_error_limit")
        case .toolUnsupported, .toolScopeMismatch, .toolResultAlreadySubmitted, .toolRejected,
             .walletContextChanged, .toolTimeout, .toolFailed, .toolResultTooLarge, .actionUnsupported:
            lang("$agent_error_tool")
        case .marketDataUnavailable:
            lang("$agent_error_generic")
        case .networkError:
            lang("$agent_connection_interrupted")
        case .providerTimeout, .providerUnavailable:
            lang("$agent_capacity_limit_unknown")
        case .invalidEvent:
            lang("$agent_error_invalid_response")
        case .invalidRequest, .deviceIdInvalid, .idempotencyMismatch,
             .threadRevisionConflict, .threadNotFound, .threadRunInProgress, .runNotFound,
             .runInterrupted, .runReplayExpired, .messageNotFound, .messageNotEditable,
             .regenerateTargetInvalid, .followupReferenceInvalid, .feedbackTargetInvalid,
             .feedbackRevisionConflict, .providerCapabilityUnavailable, .providerError,
             .emptyResponse, .internalError:
            lang("$agent_error_generic")
        }
    }
}

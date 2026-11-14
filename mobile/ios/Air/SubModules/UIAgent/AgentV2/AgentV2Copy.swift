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

    static func displayError(_ error: Error) -> DisplayError? {
        guard !(error is CancellationError) else { return nil }
        if let error = error as? ApiAgentV2MutationError {
            guard error.code != .runInterrupted else { return nil }
            return DisplayError(text: self.error(error.code))
        }
        return DisplayError(text: lang("$agent_error_generic"))
    }

    @MainActor
    static func error(_ code: ApiAgentV2ErrorCode, resetAt: Date?) -> String {
        guard code == .userQuotaExhausted, let resetAt, resetAt > Date() else { return error(code) }
        return langFormat(
            "$agent_daily_limit_resets_at",
            BaseAgentModel.formattedTime(resetAt, locale: LocalizationSupport.shared.locale)
        )
    }

    static func error(_ code: ApiAgentV2ErrorCode) -> String {
        switch code {
        case .clientUpdateRequired:
            lang("$agent_error_update_required")
        case .supportEscalationRateLimited:
            lang("$agent_support_rate_limited")
        case .deviceTokenMissing, .deviceTokenInvalid, .deviceTokenExpired, .profileIdInvalid, .profileDeleted:
            lang("$agent_error_session")
        case .userQuotaExhausted:
            lang("$agent_daily_limit_reached")
        case .rateLimited, .agentCapacityExhausted, .runBudgetExceeded,
             .outputLimitReached, .contextTooLargeRetryable, .deviceTokenRateLimited:
            lang("$agent_error_limit")
        case .toolUnsupported, .toolScopeMismatch, .toolResultAlreadySubmitted, .toolRejected,
             .walletContextChanged, .toolTimeout, .toolFailed, .toolResultTooLarge, .actionUnsupported:
            lang("$agent_error_tool")
        case .digestUnavailable:
            lang("$agent_digest_unavailable")
        case .marketDataUnavailable:
            lang("$agent_error_generic")
        case .newsUnavailable:
            lang("$agent_news_unavailable")
        case .networkError:
            lang("$agent_connection_lost")
        case .providerTimeout, .providerUnavailable:
            lang("$agent_capacity_limit_unknown")
        case .invalidEvent:
            lang("$agent_error_invalid_response")
        case .recordingTooLarge:
            lang("$agent_error_recording_too_large")
        case .audioUnreadable:
            lang("$agent_error_audio_unreadable")
        case .transcriptionUnavailable:
            lang("$agent_error_transcription_unavailable")
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

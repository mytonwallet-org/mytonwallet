import Foundation
import WalletContext
import WalletCore

enum AgentV2Copy {
    struct Prompt {
        let title: String
        /// The question the agent gets; the chip shows the shorter title
        let prompt: String

        init(title: String, prompt: String? = nil) {
            self.title = title
            self.prompt = prompt ?? title
        }
    }

    static func hint(_ id: ApiAgentV2StarterHint.ID) -> Prompt {
        switch id {
        case .agentCapabilities: Prompt(title: lang("$agent_hint_capabilities_title"))
        case .learnSwap: Prompt(title: lang("$agent_hint_swap_title"))
        case .learnStaking: Prompt(title: lang("$agent_hint_staking_title"))
        case .learnSecurity: Prompt(title: lang("$agent_hint_security_title"), prompt: lang("$agent_hint_security_prompt"))
        case .receiveTokens: Prompt(title: lang("$agent_hint_receive_title"))
        case .walletAssets: Prompt(title: lang("$agent_hint_assets_title"), prompt: lang("$agent_hint_assets_prompt"))
        case .walletTotal: Prompt(title: lang("$agent_hint_total_title"), prompt: lang("$agent_hint_total_prompt"))
        case .walletSpending: Prompt(title: lang("$agent_hint_spending_title"), prompt: lang("$agent_hint_spending_prompt"))
        case .walletLastTransfer: Prompt(title: lang("$agent_hint_last_transfer_title"), prompt: lang("$agent_hint_last_transfer_prompt"))
        case .walletFund: Prompt(title: lang("$agent_hint_fund_title"), prompt: lang("$agent_hint_fund_prompt"))
        case .marketToday: Prompt(title: lang("$agent_hint_market_today_title"), prompt: lang("$agent_hint_market_today_prompt"))
        case .newsToday: Prompt(title: lang("$agent_hint_news_today_title"), prompt: lang("$agent_hint_news_today_prompt"))
        case .marketBitcoin: Prompt(title: lang("$agent_hint_bitcoin_title"), prompt: lang("$agent_hint_bitcoin_prompt"))
        case .marketPrice: Prompt(title: lang("$agent_hint_price_title"))
        case .stakingYield: Prompt(title: lang("$agent_hint_staking_yield_title"), prompt: lang("$agent_hint_staking_yield_prompt"))
        case .stakingOptions: Prompt(title: lang("$agent_hint_staking_options_title"), prompt: lang("$agent_hint_staking_options_prompt"))
        case .learnMultisend: Prompt(title: lang("$agent_hint_multisend_title"), prompt: lang("$agent_hint_multisend_prompt"))
        case .actionSwap: Prompt(title: lang("$agent_hint_action_swap_title"))
        case .actionSend: Prompt(title: lang("$agent_hint_action_send_title"))
        case .actionStake: Prompt(title: lang("$agent_hint_action_stake_title"))
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
        if isConnectionError(error) { return DisplayError(text: self.error(.networkError)) }
        return DisplayError(text: lang("$agent_error_generic"))
    }

    /// What a failed load says: without a network, that the device has no connection
    static func loadError(_ code: ApiAgentV2ErrorCode) -> String {
        code == .networkError ? lang("No internet connection. Please check your connection and try again.") : error(code)
    }

    /// What a failed load says, as `loadError(_:)` for the Agent's errors and the system's connection failures
    static func loadErrorText(_ error: Error) -> String {
        if isConnectionError(error) { return loadError(.networkError) }
        if let error = error as? ApiAgentV2MutationError {
            return loadError(error.code)
        }
        return lang("$agent_error_generic")
    }

    static func isConnectionError(_ error: Error) -> Bool {
        if (error as? ApiAgentV2MutationError)?.code == .networkError { return true }
        guard let error = error as? URLError else { return false }
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed:
            return true
        default:
            return false
        }
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
            lang("No internet connection. Please check your connection and try again.")
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

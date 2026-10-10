/* eslint-disable */
// Generated from specs/schemas/agent-v2-public.schema.json. Do not edit.

/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "ActionSendRecipientV1".
 */
export type ActionSendRecipientV1 =
  | {
      kind: 'address';
      chain: AgentApiChain;
      address: string;
    }
  | {
      kind: 'domain';
      chain: AgentApiChain;
      domain: string;
    }
  | {
      kind: 'savedAddress';
      addressRef: string;
    };
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentApiChain".
 */
export type AgentApiChain = string;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "Uuid".
 */
export type Uuid = string;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentActionProposal".
 */
export type AgentActionProposal =
  | AgentReceiveActionV2
  | AgentReceiveActionV3
  | AgentStakeActionV2
  | AgentSwapActionV2
  | AgentSendFormActionV1
  | AgentOpenDappActionV1;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentStakeAmountV2".
 */
export type AgentStakeAmountV2 =
  | {
      kind: 'exact';
      value: string;
    }
  | {
      kind: 'all';
    };
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "UtcTimestampMs".
 */
export type UtcTimestampMs = string;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentActionKind".
 */
export type AgentActionKind = 'send' | 'receive' | 'stake' | 'swap' | 'openDapp';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentDisplayTableV1".
 */
export type AgentDisplayTableV1 = {
  [k: string]: unknown;
} & {
  kind: 'display';
  /**
   * @minItems 1
   * @maxItems 12
   */
  headers: string[];
  /**
   * @maxItems 320
   */
  rows: string[][];
  /**
   * @maxItems 16
   */
  notes: string[];
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentApiChainList".
 */
export type AgentApiChainList = AgentApiChain[];
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentErrorRetryabilityBinding".
 */
export type AgentErrorRetryabilityBinding = {
  [k: string]: unknown;
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentAppName".
 */
export type AgentAppName = 'My Wallet' | 'Gram Wallet';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentAvailabilityResponseV2".
 */
export type AgentAvailabilityResponseV2 =
  | {
      protocolVersion: 3;
      state: 'available';
    }
  | {
      protocolVersion: 3;
      state: 'capacity_exhausted';
      resetAt?: UtcTimestampMs;
    };
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentClientFeature".
 */
export type AgentClientFeature = 'followups' | 'walletDirectory' | 'sendRecipientWithoutAsset' | 'walletChainLookup';
export type AgentApiChainList1 = AgentApiChain[];
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "UuidInput".
 */
export type UuidInput = string;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentEntryPoint".
 */
export type AgentEntryPoint =
  | {
      kind: 'agentTab';
    }
  | {
      kind: 'portfolioChart';
      source?: 'analyzeIt' | 'manual';
      chartId: string;
      range: '1d' | '7d' | '1m' | '3m' | '1y' | 'all';
      accountScope?: 'current';
      datasetFocus?: {
        datasetId?: string;
        assetSlug?: string;
        chain?: string;
      };
    }
  | {
      kind: 'tokenScreen';
      asset: AgentAssetRefV2;
    }
  | {
      kind: 'globalSearch';
      query: string;
    }
  | {
      kind: 'emptyState';
      surface: 'agentTab';
      hintId?: AgentStarterHintIdV2;
      catalogVersion?: string;
    };
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentStarterHintIdV2".
 */
export type AgentStarterHintIdV2 =
  'agent.capabilities' | 'learn.swap' | 'learn.staking' | 'learn.security' | 'receive.tokens';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentErrorCodeV2".
 */
export type AgentErrorCodeV2 =
  | 'invalid_request'
  | 'invalid_event'
  | 'client_update_required'
  | 'network_error'
  | 'device_token_missing'
  | 'device_token_invalid'
  | 'device_token_rate_limited'
  | 'idempotency_mismatch'
  | 'thread_revision_conflict'
  | 'thread_not_found'
  | 'thread_run_in_progress'
  | 'run_not_found'
  | 'run_interrupted'
  | 'run_replay_expired'
  | 'rate_limited'
  | 'user_quota_exhausted'
  | 'agent_capacity_exhausted'
  | 'tool_scope_mismatch'
  | 'tool_result_already_submitted'
  | 'wallet_context_changed'
  | 'tool_timeout'
  | 'tool_failed'
  | 'tool_result_too_large'
  | 'market_data_unavailable'
  | 'message_not_editable'
  | 'regenerate_target_invalid'
  | 'followup_reference_invalid'
  | 'provider_timeout'
  | 'provider_unavailable'
  | 'provider_error'
  | 'empty_response'
  | 'internal_error';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentErrorEvent".
 */
export type AgentErrorEvent = AgentErrorRetryabilityBinding & {
  [k: string]: unknown;
} & {
  type: 'error';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  code: AgentErrorCodeV2;
  retryable: boolean;
  messageId?: Uuid;
  retryAfterMs?: number;
  resetAt?: UtcTimestampMs;
  createdAt?: UtcTimestampMs;
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentEventType".
 */
export type AgentEventType =
  | 'run_start'
  | 'thread'
  | 'message_start'
  | 'text_delta'
  | 'text_draft'
  | 'table_data'
  | 'table_reference'
  | 'text_link'
  | 'message_content_end'
  | 'tool_call'
  | 'tool_status'
  | 'run_activity'
  | 'action'
  | 'followups'
  | 'semantic_content'
  | 'message_end'
  | 'error';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletQueryCapabilityV1".
 */
export type AgentWalletQueryCapabilityV1 = {
  [k: string]: unknown;
} & {
  status: AgentWalletQueryFeatureStatusV1;
  filterCatalog?: {
    version: 1;
    digest: string;
    requiresClientTimeZone: true;
  };
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletQueryFeatureStatusV1".
 */
export type AgentWalletQueryFeatureStatusV1 = 'available' | 'disabled';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentPublicFollowUpOpaqueIdV2".
 */
export type AgentPublicFollowUpOpaqueIdV2 = string;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentFollowUpTextV1".
 */
export type AgentFollowUpTextV1 = string;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgenticWalletToolErrorCode".
 */
export type AgenticWalletToolErrorCode =
  | 'consent_required'
  | 'tool_unsupported'
  | 'capability_unsupported'
  | 'invalid_arguments'
  | 'invalid_amount'
  | 'invalid_recipient'
  | 'recipient_unresolved'
  | 'recipient_inactive'
  | 'memo_required'
  | 'wallet_not_initialized'
  | 'account_scope_not_allowed'
  | 'view_only_prepare_forbidden'
  | 'asset_ambiguous'
  | 'address_ambiguous'
  | 'validation_failed'
  | 'insufficient_balance'
  | 'quote_unavailable'
  | 'offline_prepare_unavailable'
  | 'stale_data_unavailable'
  | 'result_too_large'
  | 'tool_scope_mismatch'
  | 'wallet_context_changed'
  | 'tool_timeout'
  | 'tool_failed';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMarketAssetIdentityV1".
 */
export type AgentMarketAssetIdentityV1 = {
  [k: string]: unknown;
} & {
  resolverVersion: 'market-asset-resolver-v1';
  identityKey: string;
  assetClass: 'native' | 'token';
  slug: string;
  chain: AgentMarketCanonicalChainV1;
  symbol: string;
  name?: string;
  tokenAddress?: string;
  providerBindings: {
    binance?: string;
    alternative_me?: string;
    coingecko?: string;
  };
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMarketCanonicalChainV1".
 */
export type AgentMarketCanonicalChainV1 =
  | 'ton'
  | 'tron'
  | 'solana'
  | 'bitcoin'
  | 'ethereum'
  | 'base'
  | 'bnb'
  | 'polygon'
  | 'arbitrum'
  | 'monad'
  | 'avalanche'
  | 'hyperliquid';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMarketEvidenceSnippetV1".
 */
export type AgentMarketEvidenceSnippetV1 =
  | {
      id: string;
      kind: 'quote';
      labelKey: 'market.quote';
      value: string;
      asset: AgentMarketAssetIdentityV1;
      source: AgentMarketQuoteSourceRefV1;
      asOf: UtcTimestampMs;
      severity: 'info' | 'watch' | 'important';
      interpretationKey?: 'market.observed_only' | 'market.stale_caveat';
    }
  | {
      id: string;
      kind: 'price_change';
      labelKey: 'market.price_change';
      value: string;
      asset: AgentMarketAssetIdentityV1;
      source: AgentMarketPriceSeriesSourceRefV1;
      asOf: UtcTimestampMs;
      severity: 'info' | 'watch' | 'important';
      interpretationKey?: 'market.observed_only' | 'market.stale_caveat' | 'market.insufficient_data';
    }
  | {
      id: string;
      kind: 'technical_indicator';
      labelKey: 'market.trend' | 'market.sma_cross' | 'market.rsi' | 'market.volatility' | 'market.drawdown';
      value: string;
      asset: AgentMarketAssetIdentityV1;
      source: AgentMarketPriceSeriesSourceRefV1;
      asOf: UtcTimestampMs;
      severity: 'info' | 'watch' | 'important';
      interpretationKey?: 'market.observed_only' | 'market.stale_caveat' | 'market.insufficient_data';
    }
  | {
      id: string;
      kind: 'public_signal';
      labelKey: 'market.fear_greed';
      value: string;
      source: AgentMarketFearGreedSourceRefV1;
      asOf: UtcTimestampMs;
      severity: 'info' | 'watch';
      interpretationKey?: 'market.observed_only';
    }
  | {
      id: string;
      kind: 'public_signal';
      labelKey: 'market.btc_dominance' | 'market.total_market_cap' | 'market.stablecoin_dominance';
      value: string;
      source: AgentMarketGlobalSignalSourceRefV1;
      asOf: UtcTimestampMs;
      severity: 'info' | 'watch';
      interpretationKey?: 'market.observed_only';
    }
  | {
      id: string;
      kind: 'public_signal';
      labelKey: 'market.volatility';
      value: string;
      /**
       * @minItems 2
       * @maxItems 10
       */
      sourceSeries: AgentMarketSeriesEvidenceRefV1[];
      asOf: UtcTimestampMs;
      severity: 'info' | 'watch';
      interpretationKey?: 'market.observed_only';
    }
  | {
      id: string;
      kind: 'freshness';
      labelKey: 'market.freshness';
      value: 'fresh' | 'stale' | 'insufficient_data';
      severity: 'info' | 'watch' | 'important';
      interpretationKey?: 'market.stale_caveat' | 'market.insufficient_data';
    }
  | {
      id: string;
      kind: 'coverage';
      labelKey: 'market.coverage';
      value: 'partial' | 'complete' | 'insufficient_data';
      severity: 'info' | 'watch' | 'important';
      interpretationKey?: 'market.partial_coverage' | 'market.insufficient_data';
    };
export type AgentMarketQuoteSourceRefV1 = {
  [k: string]: unknown;
} & {
  provider: 'main_backend';
  endpoint: 'main.agent_market_current';
};
export type AgentMarketPriceSeriesSourceRefV1 = {
  [k: string]: unknown;
} & {
  provider: 'main_backend';
  endpoint: 'main.agent_market_chart';
};
export type AgentMarketFearGreedSourceRefV1 = {
  [k: string]: unknown;
} & {
  provider: 'alternative_me';
  endpoint: 'alternative.fng';
};
export type AgentMarketGlobalSignalSourceRefV1 = {
  [k: string]: unknown;
} & {
  provider: 'coingecko';
  endpoint: 'coingecko.global';
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMarketFearGreedSourceRefV1".
 */
export type AgentMarketSourceRefV1 = {
  [k: string]: unknown;
} & {
  provider: 'alternative_me';
  endpoint: 'alternative.fng';
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMarketGlobalSignalSourceRefV1".
 */
export type AgentMarketSourceRefV11 = {
  [k: string]: unknown;
} & {
  provider: 'coingecko';
  endpoint: 'coingecko.global';
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMarketLimitationCodeV1".
 */
export type AgentMarketLimitationCodeV1 =
  | 'asset_ambiguous'
  | 'asset_unresolved'
  | 'asset_metadata_rejected'
  | 'provider_unavailable'
  | 'provider_timeout'
  | 'provider_rate_limited'
  | 'provider_schema_mismatch'
  | 'upstream_contract_mismatch'
  | 'insufficient_ohlcv'
  | 'insufficient_signal_coverage'
  | 'synthetic_series_forbidden'
  | 'stale_data'
  | 'future_timestamp'
  | 'provider_conflict'
  | 'unsupported_range'
  | 'unsupported_base_currency'
  | 'market_request_too_large'
  | 'provider_disabled'
  | 'attribution_capability_missing';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMarketPriceSeriesSourceRefV1".
 */
export type AgentMarketSourceRefV12 = {
  [k: string]: unknown;
} & {
  provider: 'main_backend';
  endpoint: 'main.agent_market_chart';
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMarketProviderNameV1".
 */
export type AgentMarketProviderNameV1 = 'main_backend' | 'binance' | 'alternative_me' | 'coingecko';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMarketQuoteSourceRefV1".
 */
export type AgentMarketSourceRefV13 = {
  [k: string]: unknown;
} & {
  provider: 'main_backend';
  endpoint: 'main.agent_market_current';
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMarketSourceRefV1".
 */
export type AgentMarketSourceRefV14 = {
  [k: string]: unknown;
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMessageContentV1".
 */
export type AgentMessageContentV1 = AgentMarkdownMessageContentV1 | AgentSemanticMessageContentV1;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMessageCursorV2".
 */
export type AgentMessageCursorV2 = string;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMessageErrorV2".
 */
export type AgentMessageErrorV2 = AgentErrorRetryabilityBinding & {
  [k: string]: unknown;
} & {
  code: AgentErrorCodeV2;
  retryable: boolean;
  retryAfterMs?: number;
  resetAt?: UtcTimestampMs;
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentResponseLanguageV1".
 */
export type AgentResponseLanguageV1 = string;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentSendAmountRejectionCodeV1".
 */
export type AgentSendAmountRejectionCodeV1 =
  | 'amount_empty'
  | 'amount_exponent_not_allowed'
  | 'amount_sign_not_allowed'
  | 'amount_non_positive'
  | 'amount_invalid_character'
  | 'amount_digit_set_not_allowed'
  | 'amount_mixed_digit_set'
  | 'amount_invalid_grouping'
  | 'amount_invalid_syntax'
  | 'amount_too_long';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentReceiveFailureV1".
 */
export type AgentReceiveFailureV1 =
  | 'planning_unavailable'
  | 'active_account_unavailable'
  | 'client_receive_unavailable'
  | 'chain_unsupported'
  | 'active_network_mismatch';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentSendFailureV1".
 */
export type AgentSendFailureV1 =
  | 'no_sendable_balance'
  | 'asset_not_held'
  | 'insufficient_balance'
  | 'recipient_not_found'
  | 'recipient_ambiguous'
  | 'address_book_unavailable'
  | 'recipient_matching_unavailable'
  | 'intent_extraction_unavailable'
  | 'intent_provider_unavailable'
  | 'invalid_recipient'
  | 'recipient_unresolved'
  | 'recipient_inactive'
  | 'memo_required'
  | 'wallet_not_initialized'
  | 'active_account_unavailable'
  | 'chain_unsupported'
  | 'client_send_unavailable'
  | 'view_only_prepare_forbidden'
  | 'offline_prepare_unavailable'
  | 'wallet_context_changed'
  | 'source_wallet_selection_required'
  | 'validation_failed'
  | 'prepare_unavailable';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentStakeFailureV1".
 */
export type AgentStakeFailureV1 =
  | 'planning_unavailable'
  | 'active_account_unavailable'
  | 'view_only_staking_forbidden'
  | 'client_staking_unavailable'
  | 'catalog_unavailable'
  | 'asset_unavailable'
  | 'amount_invalid'
  | 'wallet_context_changed';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentSwapDetailsRequiredV1".
 */
export type AgentSwapDetailsRequiredV1 = {
  [k: string]: unknown;
} & {
  field: 'source_asset' | 'destination_asset' | 'amount' | 'direction';
  /**
   * @minItems 2
   * @maxItems 3
   */
  candidates?: AgentSemanticAssetV1[];
  hasMore?: boolean;
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentSwapFailureV1".
 */
export type AgentSwapFailureV1 =
  | 'planning_unavailable'
  | 'active_account_unavailable'
  | 'view_only_swap_forbidden'
  | 'client_swap_unavailable'
  | 'wallet_context_changed'
  | 'tool_timeout'
  | 'tool_failed'
  | 'invalid_tool_result';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentNoticeCodeV1".
 */
export type AgentNoticeCodeV1 =
  | 'agent_unavailable'
  | 'analysis_unavailable'
  | 'asset_not_found'
  | 'clarification_required'
  | 'consent_required'
  | 'content_over_budget'
  | 'dapp_ready'
  | 'dapp_unavailable'
  | 'empty_result'
  | 'portfolio_unavailable'
  | 'receive_details_required'
  | 'receive_ready'
  | 'receive_unavailable'
  | 'retry_required'
  | 'send_details_required'
  | 'send_form_amount_required'
  | 'send_form_ready'
  | 'send_ready'
  | 'send_unavailable'
  | 'staking_ready'
  | 'staking_unavailable'
  | 'swap_details_required'
  | 'swap_unavailable'
  | 'tool_unavailable'
  | 'wallet_data_unavailable'
  | 'wallet_filter_ambiguous'
  | 'web_search_no_results'
  | 'web_search_unavailable';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentNoticeContentV1".
 */
export type AgentNoticeContentV1 = {
  kind: 'notice';
  schemaVersion: 1;
  code: AgentNoticeCodeV1;
  clarificationText?: string;
  arguments?: AgentNoticeArgumentsV1;
} & {
  [k: string]: unknown;
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentPersistedActionV2".
 */
export type AgentPersistedActionV2 = AgentPreparedPersistedActionV2 & {
  title: string;
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentPreparedPersistedActionV2".
 */
export type AgentPreparedPersistedActionV2 =
  AgentPersistedWalletActionV2 | AgentPersistedSendFormActionV1 | AgentPersistedNavigationActionV3;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentPersistedWalletActionV2".
 */
export type AgentPersistedWalletActionV2 =
  | {
      id: Uuid;
      kind: 'receive';
      title?: string;
      labelCode: 'open_receive';
      effect: 'open_receive';
      localDraftRequired: false;
      requiresConfirmation: false;
    }
  | {
      id: Uuid;
      schemaVersion: 3;
      kind: 'receive';
      title?: string;
      labelCode: 'open_receive';
      effect: 'open_receive';
      targetNetwork: AgentApiChain;
      localDraftRequired: false;
      requiresConfirmation: false;
    }
  | AgentPersistedStakeActionV2
  | AgentPersistedSwapActionV2;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentPersistedMessageV2".
 */
export type AgentPersistedMessageV2 = {
  [k: string]: unknown;
} & {
  id: Uuid;
  threadId: Uuid;
  role: 'user' | 'assistant';
  status: 'complete' | 'error' | 'cancelled';
  content?: AgentMessageContentV1;
  responseLanguage?: AgentResponseLanguageV1;
  createdAt: UtcTimestampMs;
  runId?: Uuid;
  error?: AgentMessageErrorV2;
  /**
   * @maxItems 8
   */
  actions?: AgentPersistedActionV2[];
  /**
   * @maxItems 3
   */
  followups?: AgentPublicFollowUpV2[];
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentRunActivityCodeV1".
 */
export type AgentRunActivityCodeV1 =
  'web.searching' | 'web.reading_sources' | 'help.searching' | 'data.reading_market' | 'analysis.computing';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentRunInputV2".
 */
export type AgentRunInputV2 = AgentRunAppendInputV2 | AgentRunEditInputV2 | AgentRunRegenerateInputV2;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentRunOriginInputV2".
 */
export type AgentRunOriginInputV2 =
  | {
      entryPoint?: never;
      followupOf?: never;
      input: AgentRunAppendInputV2;
    }
  | {
      entryPoint: AgentEntryPoint;
      followupOf?: never;
      input: AgentRunAppendInputV2;
    }
  | {
      entryPoint?: never;
      followupOf: AgentRunFollowupRef;
      input: AgentRunAppendInputV2;
    }
  | {
      entryPoint?: never;
      followupOf?: never;
      input: AgentRunEditInputV2;
    }
  | {
      entryPoint?: never;
      followupOf?: never;
      input: AgentRunRegenerateInputV2;
    };
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentRunRequestV2".
 */
export type AgentRunRequestV2 = AgentRunRequestWireV2 &
  AgentRunOriginInputV2 & {
    [k: string]: unknown;
  };
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletContextV2".
 */
export type AgentWalletContextV2 =
  | {
      mode: 'none';
      reason: 'noConsent' | 'noWallet' | 'unsupportedClient';
    }
  | AgentWalletContextGrantV2;
/**
 * @minItems 1
 */
export type AgentApiChainList2 = AgentApiChain[];
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentStreamEventV2".
 */
export type AgentStreamEventV2 =
  | AgentRunStartEvent
  | AgentThreadEvent
  | AgentMessageStartEvent
  | AgentTextDeltaEvent
  | AgentTextDraftEvent
  | AgentTableReferenceEvent
  | AgentTableDataEvent
  | AgentTextLinkEvent
  | AgentMessageContentEndEvent
  | AgentToolCallEvent
  | AgentToolStatusEvent
  | AgentRunActivityEvent
  | AgentActionEvent
  | AgentFollowupsEvent
  | AgentSemanticContentEvent
  | AgentMessageEndEvent
  | AgentErrorEvent;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolCall".
 */
export type AgentToolCall = AgentWalletDataQueryToolCall | AgentWalletDirectoryQueryToolCall;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDataQueryArgs".
 */
export type AgentWalletDataQueryArgs =
  | AgentWalletAccountInventoryArgs
  | AgentWalletAssetsSearchArgs
  | AgentWalletPositionsListArgs
  | AgentWalletPortfolioAggregateArgs
  | AgentWalletTransactionsListArgs
  | AgentWalletTransactionsDetailArgs
  | AgentWalletContactsListArgs
  | AgentWalletValueSeriesArgs;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletQueryAccountSelectorV2".
 */
export type AgentWalletQueryAccountSelectorV2 =
  | {
      kind: 'current';
    }
  | {
      kind: 'explicitAll';
    }
  | {
      kind: 'named';
      label: string;
    }
  | {
      kind: 'ordinal';
      index: number;
    };
export type AgentApiChainList3 = AgentApiChain[];
export type AgentApiChainList4 = AgentApiChain[];
export type AgentApiChainList5 = AgentApiChain[];
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletPositionKindV1".
 */
export type AgentWalletPositionKindV1 = 'fungible' | 'nft' | 'staking' | 'vesting' | 'vault';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletRiskModeV1".
 */
export type AgentWalletRiskModeV1 = 'exclude' | 'only' | 'all';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletVisibilityModeV1".
 */
export type AgentWalletVisibilityModeV1 = 'visible' | 'hidden' | 'all';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletPortfolioAggregateArgs".
 */
export type AgentWalletPortfolioAggregateArgs = {
  [k: string]: unknown;
} & {
  operation: 'portfolio.aggregate';
  accountSelector: AgentWalletQueryAccountSelectorV2;
  accountFilter?: AgentWalletAccountFilterV1;
  chains: AgentApiChainList6;
  range: AgentWalletQueryHistoryRangeV1;
  historySource?: 'backend';
  /**
   * @minItems 1
   * @maxItems 4
   */
  groupBy: ('account' | 'asset' | 'network' | 'position_type')[];
  riskMode: AgentWalletRiskModeV1;
  visibilityMode: AgentWalletVisibilityModeV1;
};
export type AgentApiChainList6 = AgentApiChain[];
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletQueryHistoryRangeV1".
 */
export type AgentWalletQueryHistoryRangeV1 = '1d' | '7d' | '1m' | '3m' | '1y' | 'all';
export type AgentApiChainList7 = AgentApiChain[];
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletFilterClauseV1".
 */
export type AgentWalletFilterClauseV1 =
  | {
      field: 'transaction.status';
      operator: 'in';
      /**
       * @minItems 1
       * @maxItems 6
       */
      values: ('pending' | 'pendingTrusted' | 'confirmed' | 'completed' | 'failed' | 'expired')[];
    }
  | {
      field: 'transaction.direction';
      operator: 'in';
      /**
       * @minItems 1
       * @maxItems 3
       */
      values: ('incoming' | 'outgoing' | 'self')[];
    }
  | {
      field: 'transaction.chain';
      operator: 'in';
      values: AgentApiChainList8;
    }
  | {
      field: 'transaction.timestamp';
      operator: 'timestamp_range';
      range: AgentWalletTimestampRangeV1;
    }
  | {
      field: 'transaction.asset';
      operator: 'asset_matches_any';
      /**
       * @minItems 1
       * @maxItems 10
       */
      values: AgentAssetSelector[];
    };
/**
 * @minItems 1
 */
export type AgentApiChainList8 = AgentApiChain[];
export type AgentApiChainList9 = AgentApiChain[];
export type AgentApiChainList10 = AgentApiChain[];
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletValueSeriesArgs".
 */
export type AgentWalletValueSeriesArgs = {
  [k: string]: unknown;
} & {
  operation: 'value.series';
  accountSelector: AgentWalletQueryAccountSelectorV2;
  chains: AgentApiChainList11;
  metric: 'portfolio_value' | 'position_value';
  /**
   * @maxItems 5
   */
  assetSelectors: AgentAssetSelector[];
  range: AgentWalletQueryHistoryRangeV1;
  maxPoints: number;
};
export type AgentApiChainList11 = AgentApiChain[];
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolError".
 */
export type AgentToolError = AgentToolErrorRetryabilityBinding & {
  code: AgenticWalletToolErrorCode;
  retryable: boolean;
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolErrorRetryabilityBinding".
 */
export type AgentToolErrorRetryabilityBinding = {
  [k: string]: unknown;
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolFreshness".
 */
export type AgentToolFreshness = {
  [k: string]: unknown;
} & {
  asOf: UtcTimestampMs;
  source: 'store' | 'store_refreshed' | 'network' | 'offline_cache';
  isStale: boolean;
  staleReason?: 'ttl_expired' | 'offline' | 'refresh_failed';
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolName".
 */
export type AgentToolName = 'wallet.data.query' | 'wallet.directory.query';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolResultRequestV2".
 */
export type AgentToolResultRequestV2 =
  | AgentWalletDirectorySuccessToolResultRequestV1
  | AgentWalletDirectoryFailureToolResultRequestV1
  | AgentUnsupportedToolResultRequestV1
  | {
      protocolVersion: 3;
      runId: UuidInput;
      threadId: UuidInput;
      toolCallId: UuidInput;
      clientToolResultId: UuidInput;
      toolName: 'wallet.data.query';
      status: 'success';
      completedAt: UtcTimestampMs;
      walletContextSession: AgentToolWalletContextSessionInputV2;
      result: AgentWalletDataQuerySuccess;
    }
  | {
      protocolVersion: 3;
      runId: UuidInput;
      threadId: UuidInput;
      toolCallId: UuidInput;
      clientToolResultId: UuidInput;
      toolName: 'wallet.data.query';
      status: 'error';
      completedAt: UtcTimestampMs;
      walletContextSession: AgentToolWalletContextSessionInputV2;
      error: AgentToolError;
    }
  | {
      protocolVersion: 3;
      runId: UuidInput;
      threadId: UuidInput;
      toolCallId: UuidInput;
      clientToolResultId: UuidInput;
      toolName: 'wallet.data.query';
      status: 'rejected';
      completedAt: UtcTimestampMs;
      walletContextSession: AgentToolWalletContextSessionInputV2;
      error: AgentToolError;
    }
  | {
      protocolVersion: 3;
      runId: UuidInput;
      threadId: UuidInput;
      toolCallId: UuidInput;
      clientToolResultId: UuidInput;
      toolName: 'wallet.data.query';
      status: 'cancelled';
      completedAt: UtcTimestampMs;
      walletContextSession: AgentToolWalletContextSessionInputV2;
      error: AgentToolError;
    };
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDirectorySuccessV1".
 */
export type AgentWalletDirectorySuccessV1 = AgentToolSuccessEnvelopeBaseV1 & {
  freshness: {
    asOf: UtcTimestampMs;
    source: 'store' | 'store_refreshed';
    isStale: false;
  };
  redaction: {
    level: 'scoped';
    omittedFields: [];
    maxResultBytes: number;
  };
  result: AgentWalletDirectoryResultV1;
};
/**
 * @minItems 1
 */
export type AgentApiChainList12 = AgentApiChain[];
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDataQuerySuccess".
 */
export type AgentWalletDataQuerySuccess = AgentToolSuccessEnvelopeBaseV1 & {
  result: AgentWalletDataQueryResult;
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDataQueryResult".
 */
export type AgentWalletDataQueryResult =
  | AgentWalletAccountInventoryResult
  | AgentWalletAssetsSearchResult
  | AgentWalletPositionsListResult
  | AgentWalletPortfolioAggregateResult
  | AgentWalletTransactionsListResult
  | AgentWalletTransactionsDetailResult
  | AgentWalletContactsListResult
  | AgentWalletValueSeriesResult
  | AgentWalletScopeResolutionRequiredResult;
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDataCoverage".
 */
export type AgentWalletDataCoverage = {
  [k: string]: unknown;
} & {
  status: 'complete' | 'partial' | 'unavailable';
  emptyReason?: 'no_matching_rows';
  accountsRequested: number;
  accountsIncluded: number;
  rowsOmitted: number;
  /**
   * @maxItems 8
   */
  limitations: AgentWalletDataCoverageLimitationV1[];
  /**
   * @minItems 1
   * @maxItems 8
   */
  sourceOutcomes: AgentWalletSourceOutcomeV1[];
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDataCoverageLimitationV1".
 */
export type AgentWalletDataCoverageLimitationV1 =
  | 'account_limit'
  | 'row_limit'
  | 'history_limit'
  | 'source_partial'
  | 'source_unavailable'
  | 'stale_data'
  | 'unpriced_positions'
  | 'retry_exhausted';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletSourceOutcomeV1".
 */
export type AgentWalletSourceOutcomeV1 = {
  [k: string]: unknown;
} & {
  domain: 'accounts' | 'assets' | 'positions' | 'portfolio' | 'transactions' | 'value_series' | 'contacts';
  status: 'complete' | 'complete_empty' | 'failed_retryable' | 'failed_terminal' | 'not_loaded' | 'stale';
  attempts: number;
  accountsRequested?: number;
  accountsIncluded?: number;
  reason?:
    | 'timeout'
    | 'transport'
    | 'upstream_unavailable'
    | 'unsupported'
    | 'not_found'
    | 'authorization'
    | 'stale_cache'
    | 'deadline_exceeded'
    | 'unknown';
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDataAccountRowV3".
 */
export type AgentWalletDataAccountRowV3 = {
  rowId: string;
  kind: 'account';
  accountRef: string;
  accountLabel: string;
  accountType: 'regular' | 'ledger' | 'viewOnly' | 'multisig' | 'unknown';
  isCurrent: boolean;
  state: 'active' | 'stale' | 'deleted';
  isViewOnly: boolean;
  portfolioTotalStatus?: 'complete' | 'partial' | 'unavailable';
  portfolioTotal?: AgentWalletPortfolioTotalV1;
  chains: AgentApiChainList13;
  /**
   * @minItems 1
   */
  publicAddresses?: {
    chain: AgentApiChain;
    address: string;
    disclosureReason: 'receive' | 'wallet_location' | 'prepare_validation' | 'chain_lookup';
  }[];
} & AgentWalletDataAccountRowV31;
export type AgentApiChainList13 = AgentApiChain[];
export type AgentWalletDataAccountRowV31 =
  | {
      portfolioTotalStatus?: never;
      portfolioTotal?: never;
    }
  | {
      portfolioTotalStatus: 'complete' | 'partial';
      portfolioTotal: AgentWalletPortfolioTotalV1;
    }
  | {
      portfolioTotalStatus: 'unavailable';
      portfolioTotal?: never;
    };
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletAssetsSearchResult".
 */
export type AgentWalletAssetsSearchResult = {
  [k: string]: unknown;
} & {
  operation: 'assets.search';
  status: 'resolved';
  generatedAt: UtcTimestampMs;
  freshness: AgentWalletDataFreshnessV2;
  coverage: AgentWalletDataCoverage;
  /**
   * @maxItems 10
   */
  assets: AgentWalletAssetSearchRowV1[];
  resolution: 'no_match' | 'unique' | 'ambiguous';
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDataPositionRowV3".
 */
export type AgentWalletDataPositionRowV3 = {
  [k: string]: unknown;
} & {
  rowId: string;
  kind: 'position';
  accountRef: string;
  accountLabel: string;
  positionKind: AgentWalletPositionKindV1;
  chain: AgentApiChain;
  label: string;
  assetRef?: string;
  asset: AgentAssetIdentityV2;
  quantity: string;
  decimals: number;
  availableQuantity?: string;
  valuationStatus: 'valued' | 'unpriced' | 'not_applicable';
  fiatValue?: string;
  baseCurrency?: string;
  status?: 'active' | 'unstaking' | 'ready' | 'frozen' | 'locked';
  apy?: string;
  rewards?: string;
  collection?: string;
  isOnSale?: boolean;
  riskVerdict?: 'spam';
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDataSeriesV1".
 */
export type AgentWalletDataSeriesV1 = {
  [k: string]: unknown;
} & {
  seriesId: string;
  metric: 'portfolio_value' | 'position_value';
  label: string;
  baseCurrency: string;
  asset?: AgentAssetIdentityV2;
  /**
   * @minItems 1
   * @maxItems 64
   */
  points: AgentWalletDataSeriesPointV1[];
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDataTransactionRowV3".
 */
export type AgentWalletDataTransactionRowV3 = {
  [k: string]: unknown;
} & {
  rowId: string;
  kind: 'transaction';
  accountRef: string;
  accountLabel: string;
  chain: AgentApiChain;
  displayHash: string;
  transactionType:
    | 'transfer'
    | 'swap'
    | 'stake'
    | 'unstake'
    | 'unstakeRequest'
    | 'callContract'
    | 'excess'
    | 'contractDeploy'
    | 'bounced'
    | 'mint'
    | 'burn'
    | 'auctionBid'
    | 'nftTrade'
    | 'dnsChangeAddress'
    | 'dnsChangeSite'
    | 'dnsChangeSubdomains'
    | 'dnsChangeStorage'
    | 'dnsDelete'
    | 'dnsRenew'
    | 'liquidityDeposit'
    | 'liquidityWithdraw';
  direction: 'incoming' | 'outgoing' | 'self';
  status: 'pending' | 'pendingTrusted' | 'confirmed' | 'completed' | 'failed' | 'expired';
  timestamp: UtcTimestampMs;
  asset?: AgentAssetIdentityV2;
  quantity?: string;
  decimals?: number;
  fee?: AgentWalletTransactionAmountV1;
  counterparty?: AgentWalletTransactionCounterpartyV1;
  safeDescription: string;
  swapDetails?: AgentWalletTransactionSwapDetailsV1;
  nftDetails?: AgentWalletTransactionNftDetailsV1;
  contractDetails?: AgentWalletTransactionContractDetailsV1;
  stakingDetails?: AgentWalletTransactionStakingDetailsV1;
  failureReason?: string;
  riskVerdict?: 'spam';
};
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolScope".
 */
export type AgentToolScope = 'wallet.data.read' | 'wallet.directory.read';
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletSemanticOperationV2".
 */
export type AgentWalletSemanticOperationV2 =
  | 'account.inventory'
  | 'assets.search'
  | 'positions.list'
  | 'portfolio.aggregate'
  | 'transactions.list'
  | 'transactions.detail'
  | 'contacts.list'
  | 'value.series';
export type AgentApiChainList14 = AgentApiChain[];

export interface MyTonWalletAgentProtocolV2StandalonePublicWireContract {
  [k: string]: unknown;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentActionEvent".
 */
export interface AgentActionEvent {
  type: 'action';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  messageId: Uuid;
  action: AgentActionProposal & {
    title: string;
  };
  createdAt?: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentReceiveActionV2".
 */
export interface AgentReceiveActionV2 {
  id: Uuid;
  kind: 'receive';
  title?: string;
  labelCode: 'open_receive';
  effect: 'open_receive';
  contextBinding: AgentReceiveContextBindingV2;
  localDraftRequired: false;
  requiresConfirmation: false;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentReceiveContextBindingV2".
 */
export interface AgentReceiveContextBindingV2 {
  sessionId: Uuid;
  revision: number;
  activeAccountRef: string;
  activeNetwork: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentReceiveActionV3".
 */
export interface AgentReceiveActionV3 {
  id: Uuid;
  schemaVersion: 3;
  kind: 'receive';
  title?: string;
  labelCode: 'open_receive';
  effect: 'open_receive';
  contextBinding: AgentReceiveContextBindingV2;
  targetNetwork: AgentApiChain;
  localDraftRequired: false;
  requiresConfirmation: false;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentStakeActionV2".
 */
export interface AgentStakeActionV2 {
  id: Uuid;
  schemaVersion: 2;
  kind: 'stake';
  title?: string;
  labelCode: 'open_staking';
  effect: 'open_staking';
  contextBinding: AgentStakeContextBindingV1;
  productId: string;
  asset: AgentAssetIdentityV2;
  amount?: AgentStakeAmountV2;
  localDraftRequired: false;
  requiresConfirmation: false;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentStakeContextBindingV1".
 */
export interface AgentStakeContextBindingV1 {
  sessionId: Uuid;
  revision: number;
  activeAccountRef: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentAssetIdentityV2".
 */
export interface AgentAssetIdentityV2 {
  slug: string;
  chain: AgentApiChain;
  symbol: string;
  name?: string;
  tokenAddress?: string;
  decimals?: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentSwapActionV2".
 */
export interface AgentSwapActionV2 {
  id: Uuid;
  schemaVersion: 2;
  kind: 'swap';
  title?: string;
  labelCode: 'open_swap';
  effect: 'open_swap';
  contextBinding: AgentSwapContextBindingV1;
  sourceAsset?: AgentAssetIdentityV2;
  destinationAsset?: AgentAssetIdentityV2;
  amount?: AgentSwapAmountV1;
  localDraftRequired: false;
  requiresConfirmation: false;
  url: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentSwapContextBindingV1".
 */
export interface AgentSwapContextBindingV1 {
  sessionId: Uuid;
  revision: number;
  activeAccountRef: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentSwapAmountV1".
 */
export interface AgentSwapAmountV1 {
  value: string;
  valueType: 'decimal';
  side: 'source' | 'destination';
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentSendFormActionV1".
 */
export interface AgentSendFormActionV1 {
  id: Uuid;
  kind: 'send';
  title?: string;
  labelCode: 'open_send';
  effect: 'open_send';
  contextBinding: AgentReceiveContextBindingV2;
  asset?: AgentAssetRefV2;
  recipient?: ActionSendRecipientV1;
  localDraftRequired: false;
  requiresConfirmation: false;
  amount?: string;
  isMaxAmount?: true;
  comment?: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentAssetRefV2".
 */
export interface AgentAssetRefV2 {
  slug: string;
  chain: AgentApiChain;
  tokenAddress?: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentOpenDappActionV1".
 */
export interface AgentOpenDappActionV1 {
  id: Uuid;
  schemaVersion: 1;
  kind: 'openDapp';
  title?: string;
  labelCode: 'open_external_link';
  url: string;
  requiresConfirmation: true;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentAnswerLinkV1".
 */
export interface AgentAnswerLinkV1 {
  textOffset: number;
  textLength: number;
  url: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentAnswerTableReferenceV1".
 */
export interface AgentAnswerTableReferenceV1 {
  tableId: string;
  textOffset: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentAnswerTableV1".
 */
export interface AgentAnswerTableV1 {
  id: string;
  content: AgentDisplayTableV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentApiErrorV2".
 *
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentRunApiErrorV2".
 *
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentThreadApiErrorV2".
 */
export interface AgentApiErrorV2 {
  protocolVersion: 3;
  error: AgentErrorRetryabilityBinding;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentAssetSelector".
 */
export interface AgentAssetSelector {
  slug?: string;
  chain?: AgentApiChain;
  tokenAddress?: string;
  symbol?: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentCapabilities".
 */
export interface AgentCapabilities {
  protocolVersion: 3;
  /**
   * @maxItems 11
   */
  supportedActions: AgentActionKind[];
  features: AgentClientFeature[];
  /**
   * @maxItems 32
   */
  builtinDapps?: {
    name: string;
    url: string;
  }[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentContext".
 */
export interface AgentContext {
  platform: 'classic' | 'ios' | 'android';
  client?: 'web' | 'electron' | 'extension' | 'tma' | 'native' | 'capacitor';
  lang: string;
  baseCurrency: string;
  appName?: 'My Wallet' | 'Gram Wallet';
  timeZone?: string;
  appVersion?: string;
  knowledgeBaseVersion?: string;
  theme?: string;
  activeWalletChains?: AgentApiChainList1;
  permissions: AgentContextPermissions;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentContextPermissions".
 */
export interface AgentContextPermissions {
  agentConsentAccepted: boolean;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentDefaultThreadResponseV2".
 */
export interface AgentDefaultThreadResponseV2 {
  protocolVersion: 3;
  thread: AgentThreadSummaryV2;
  created: boolean;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentThreadSummaryV2".
 */
export interface AgentThreadSummaryV2 {
  id: Uuid;
  revision: number;
  createdAt: UtcTimestampMs;
  updatedAt: UtcTimestampMs;
  lastActivityAt: UtcTimestampMs;
  clearedAt?: UtcTimestampMs;
  messageCount: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentDeviceTokenIssueRequestV2".
 */
export interface AgentDeviceTokenIssueRequestV2 {
  protocolVersion: 3;
  deviceId: UuidInput;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentDeviceTokenIssueResponseV2".
 */
export interface AgentDeviceTokenIssueResponseV2 {
  protocolVersion: 3;
  deviceId: Uuid;
  deviceToken: string;
  expiresAt: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentFeatureCapabilitiesResponseV2".
 */
export interface AgentFeatureCapabilitiesResponseV2 {
  protocolVersion: 3;
  walletQuery: AgentWalletQueryCapabilityV1;
  problemReport: AgentProblemReportCapabilityV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentProblemReportCapabilityV1".
 */
export interface AgentProblemReportCapabilityV1 {
  status: 'available' | 'disabled';
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentFollowupsEvent".
 */
export interface AgentFollowupsEvent {
  type: 'followups';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  messageId: Uuid;
  /**
   * @minItems 1
   * @maxItems 3
   */
  items: AgentPublicFollowUpV2[];
  createdAt?: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentPublicFollowUpV2".
 */
export interface AgentPublicFollowUpV2 {
  id: AgentPublicFollowUpOpaqueIdV2;
  kind: 'suggested_prompt';
  text: AgentFollowUpTextV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentHintsResponseV2".
 */
export interface AgentHintsResponseV2 {
  protocolVersion: 3;
  catalogVersion: 'agent-starter-hints-v1';
  /**
   * @maxItems 5
   */
  items: AgentStarterHintV2[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentStarterHintV2".
 */
export interface AgentStarterHintV2 {
  id: AgentStarterHintIdV2;
  /**
   * @maxItems 2
   */
  requiredCapabilities?: ('wallet_read' | 'receive_action')[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentIntentSource".
 */
export interface AgentIntentSource {
  kind: 'userMessage';
  messageId: Uuid;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMarkdownMessageContentV1".
 */
export interface AgentMarkdownMessageContentV1 {
  kind: 'markdown';
  text: string;
  /**
   * @maxItems 16
   */
  tables?: AgentAnswerTableV1[];
  /**
   * @maxItems 16
   */
  tableReferences?: AgentAnswerTableReferenceV1[];
  /**
   * @maxItems 64
   */
  links?: AgentAnswerLinkV1[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMarketSeriesEvidenceRefV1".
 */
export interface AgentMarketSeriesEvidenceRefV1 {
  assetIdentityKey: string;
  seriesPolicyVersion: 'market-indicator-daily-series-v1';
  sourceSeriesDigest: string;
  seriesDigest: string;
  source: AgentMarketPriceSeriesSourceRefV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMessageContentEndEvent".
 */
export interface AgentMessageContentEndEvent {
  type: 'message_content_end';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  messageId: Uuid;
  createdAt: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentSemanticMessageContentV1".
 */
export interface AgentSemanticMessageContentV1 {
  kind: 'semantic';
  content: AgentSemanticContentV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentSemanticContentV1".
 */
export interface AgentSemanticContentV1 {
  kind: 'notice';
  schemaVersion: 1;
  code: 'agent_unavailable' | 'content_over_budget' | 'web_search_no_results';
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMessageEndEvent".
 */
export interface AgentMessageEndEvent {
  type: 'message_end';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  messageId: Uuid;
  finishReason: 'complete' | 'cancelled' | 'tool_unavailable' | 'run_interrupted';
  createdAt?: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentMessageStartEvent".
 */
export interface AgentMessageStartEvent {
  type: 'message_start';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  messageId: Uuid;
  role: 'assistant';
  contentKind: 'markdown' | 'semantic';
  responseLanguage?: AgentResponseLanguageV1;
  createdAt?: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentNoticeArgumentsV1".
 */
export interface AgentNoticeArgumentsV1 {
  asset?: AgentSemanticAssetV1;
  chain?: AgentApiChain;
  field?:
    | 'account'
    | 'address'
    | 'amount'
    | 'asset'
    | 'network'
    | 'price_assumption'
    | 'query'
    | 'quote_currency'
    | 'recipient'
    | 'scope'
    | 'staking_product'
    | 'time_horizon';
  repairReason?:
    | 'unrecognized_input'
    | 'ambiguous_request'
    | 'multiple_requests'
    | 'unsupported_market_section'
    | 'unsupported_market_period';
  analysisFailure?:
    | 'planning_unavailable'
    | 'source_unavailable'
    | 'stale_evidence'
    | 'inconsistent_snapshot'
    | 'compute_failed'
    | 'source_constraint_conflict'
    | 'plan_resolution_failed'
    | 'deadline_exceeded'
    | 'result_too_large'
    | 'answer_generation_failed';
  /**
   * @minItems 1
   * @maxItems 3
   */
  fields?: ('amount' | 'asset' | 'recipient')[];
  amountRejection?: AgentSendAmountRejectionCodeV1;
  retryAfterMs?: number;
  scope?: 'current' | 'explicitAll';
  receiveFailure?: AgentReceiveFailureV1;
  /**
   * @minItems 1
   * @maxItems 2
   */
  receiveFields?: ('asset' | 'network')[];
  receiveMemoRequirement?: 'not_required';
  requestedChain?: AgentApiChain;
  activeChain?: AgentApiChain;
  dappFailure?: 'no_matching_destination';
  recipientLabel?: string;
  sendFailure?: AgentSendFailureV1;
  stakeFailure?: AgentStakeFailureV1;
  swapDetails?: AgentSwapDetailsRequiredV1;
  swapFailure?: AgentSwapFailureV1;
  /**
   * @minItems 2
   * @maxItems 2
   */
  sendFailures?: ('recipient_not_found' | 'recipient_ambiguous' | 'asset_not_held' | 'insufficient_balance')[];
  webSearchFailure?:
    | 'capability_unavailable'
    | 'planning_failed'
    | 'budget_denied'
    | 'provider_rate_limited'
    | 'provider_unavailable'
    | 'no_results'
    | 'invalid_sources'
    | 'synthesis_timeout'
    | 'synthesis_invalid'
    | 'synthesis_unavailable'
    | 'policy_rejected';
  walletQueryFailure?: 'result_not_presentable';
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentSemanticAssetV1".
 */
export interface AgentSemanticAssetV1 {
  slug: string;
  chain: AgentApiChain;
  symbol: string;
  name?: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentPersistedStakeActionV2".
 */
export interface AgentPersistedStakeActionV2 {
  id: Uuid;
  schemaVersion: 2;
  kind: 'stake';
  title?: string;
  labelCode: 'open_staking';
  effect: 'open_staking';
  productId: string;
  asset: AgentAssetIdentityV2;
  amount?: AgentStakeAmountV2;
  localDraftRequired: false;
  requiresConfirmation: false;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentPersistedSwapActionV2".
 */
export interface AgentPersistedSwapActionV2 {
  id: Uuid;
  schemaVersion: 2;
  kind: 'swap';
  title?: string;
  labelCode: 'open_swap';
  effect: 'open_swap';
  sourceAsset?: AgentAssetIdentityV2;
  destinationAsset?: AgentAssetIdentityV2;
  amount?: AgentSwapAmountV1;
  localDraftRequired: false;
  requiresConfirmation: false;
  url: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentPersistedSendFormActionV1".
 */
export interface AgentPersistedSendFormActionV1 {
  id: Uuid;
  kind: 'send';
  title?: string;
  labelCode: 'open_send';
  effect: 'live_only';
  localDraftRequired: false;
  requiresConfirmation: false;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentPersistedNavigationActionV3".
 */
export interface AgentPersistedNavigationActionV3 {
  id: Uuid;
  schemaVersion: 3;
  kind: 'openDapp';
  title?: string;
  labelCode: 'open_external_link';
  url: string;
  requiresConfirmation: true;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentProblemReportRequestV2".
 */
export interface AgentProblemReportRequestV2 {
  protocolVersion: 3;
  clientOperationId: UuidInput;
  messageId?: UuidInput;
  comment?: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentProblemReportResponseV2".
 */
export interface AgentProblemReportResponseV2 {
  protocolVersion: 3;
  reportId: Uuid;
  duplicate: boolean;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentRunActivityEvent".
 */
export interface AgentRunActivityEvent {
  type: 'run_activity';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  ephemeral?: true;
  code: AgentRunActivityCodeV1;
  status: 'active' | 'completed';
  createdAt?: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentRunAppendInputV2".
 */
export interface AgentRunAppendInputV2 {
  kind: 'append';
  message: AgentRunUserMessage;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentRunUserMessage".
 */
export interface AgentRunUserMessage {
  id: UuidInput;
  text: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentRunCancelRequestV2".
 */
export interface AgentRunCancelRequestV2 {
  protocolVersion: 3;
  clientOperationId: UuidInput;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentRunCancelResponseV2".
 */
export interface AgentRunCancelResponseV2 {
  protocolVersion: 3;
  runId: Uuid;
  state: 'completed' | 'completed_with_tool_error' | 'failed' | 'cancelled' | 'run_interrupted';
  lastSequence: number;
  thread: AgentThreadSummaryV2;
  duplicate?: boolean;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentRunEditInputV2".
 */
export interface AgentRunEditInputV2 {
  kind: 'edit';
  targetUserMessageId: UuidInput;
  message: AgentRunUserMessage;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentRunFollowupRef".
 */
export interface AgentRunFollowupRef {
  messageId: UuidInput;
  followupId: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentRunRegenerateInputV2".
 */
export interface AgentRunRegenerateInputV2 {
  kind: 'regenerate';
  targetAssistantMessageId: UuidInput;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentRunRequestWireV2".
 */
export interface AgentRunRequestWireV2 {
  protocolVersion: 3;
  clientRunId: UuidInput;
  threadId?: UuidInput;
  expectedThreadRevision: number;
  resumeAfterSequence?: number;
  entryPoint?: AgentEntryPoint;
  followupOf?: AgentRunFollowupRef;
  input: AgentRunInputV2;
  context: AgentContext;
  capabilities: AgentCapabilities;
  walletContext: AgentWalletContextV2;
  walletSnapshotRef?: AgentWalletSnapshotRefV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletContextGrantV2".
 */
export interface AgentWalletContextGrantV2 {
  mode: 'wallet';
  sessionId: UuidInput;
  revision: number;
  activeAccount: AgentWalletActiveAccountV2;
  activeNetwork: AgentApiChain;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletActiveAccountV2".
 */
export interface AgentWalletActiveAccountV2 {
  accountRef: string;
  state: 'active' | 'stale' | 'deleted';
  isViewOnly: boolean;
  chains: AgentApiChainList2;
  /**
   * @maxItems 4
   */
  supportedActions: ('send' | 'receive' | 'stake' | 'swap')[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletSnapshotRefV1".
 */
export interface AgentWalletSnapshotRefV1 {
  instanceId: Uuid;
  sessionId: Uuid;
  revision: number;
  snapshotRevision: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentRunStartEvent".
 */
export interface AgentRunStartEvent {
  type: 'run_start';
  protocolVersion: 3;
  sequence: 1;
  runId: Uuid;
  clientRunId: Uuid;
  threadId: Uuid;
  threadRevision: number;
  createdAt?: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentSemanticContentEvent".
 */
export interface AgentSemanticContentEvent {
  type: 'semantic_content';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  messageId: Uuid;
  content: AgentSemanticContentV1;
  createdAt?: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentThreadEvent".
 */
export interface AgentThreadEvent {
  type: 'thread';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  thread: AgentThreadSummaryV2;
  createdAt?: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentTextDeltaEvent".
 */
export interface AgentTextDeltaEvent {
  type: 'text_delta';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  messageId: Uuid;
  delta: string;
  createdAt?: UtcTimestampMs;
  offset?: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentTextDraftEvent".
 */
export interface AgentTextDraftEvent {
  type: 'text_draft';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  messageId: Uuid;
  delta: string;
  createdAt?: UtcTimestampMs;
  offset: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentTableReferenceEvent".
 */
export interface AgentTableReferenceEvent {
  type: 'table_reference';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  messageId: Uuid;
  createdAt?: UtcTimestampMs;
  reference: AgentAnswerTableReferenceV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentTableDataEvent".
 */
export interface AgentTableDataEvent {
  type: 'table_data';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  messageId: Uuid;
  createdAt?: UtcTimestampMs;
  table: AgentAnswerTableV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentTextLinkEvent".
 */
export interface AgentTextLinkEvent {
  type: 'text_link';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  messageId: Uuid;
  createdAt?: UtcTimestampMs;
  link: AgentAnswerLinkV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolCallEvent".
 */
export interface AgentToolCallEvent {
  type: 'tool_call';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  toolCall: AgentToolCall;
  createdAt?: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDataQueryToolCall".
 */
export interface AgentWalletDataQueryToolCall {
  id: Uuid;
  name: 'wallet.data.query';
  maxResultBytes?: number;
  arguments: AgentWalletDataQueryArgs;
  scopes: ['wallet.data.read'];
  timeoutMs: number;
  walletContextSession: AgentToolWalletContextSessionV2;
  intentSource?: AgentIntentSource;
  scopeIntent?: AgentToolScopeIntentV2;
  reason?: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletAccountInventoryArgs".
 */
export interface AgentWalletAccountInventoryArgs {
  operation: 'account.inventory';
  accountSelector: AgentWalletQueryAccountSelectorV2;
  chains: AgentApiChainList3;
  includePublicAddressReason?: 'receive' | 'wallet_location' | 'prepare_validation' | 'chain_lookup';
  includePortfolioTotals?: true;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletAssetsSearchArgs".
 */
export interface AgentWalletAssetsSearchArgs {
  operation: 'assets.search';
  query: string;
  chains: AgentApiChainList4;
  pageSize: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletPositionsListArgs".
 */
export interface AgentWalletPositionsListArgs {
  operation: 'positions.list';
  accountSelector: AgentWalletQueryAccountSelectorV2;
  chains: AgentApiChainList5;
  /**
   * @maxItems 10
   */
  assetSelectors: AgentAssetSelector[];
  /**
   * @minItems 1
   * @maxItems 5
   */
  positionKinds: AgentWalletPositionKindV1[];
  riskMode: AgentWalletRiskModeV1;
  visibilityMode: AgentWalletVisibilityModeV1;
  includeZero: boolean;
  sort: 'wallet_order' | 'value_desc' | 'quantity_desc';
  pageSize: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletAccountFilterV1".
 */
export interface AgentWalletAccountFilterV1 {
  viewOnly: 'include' | 'exclude' | 'only';
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletTransactionsListArgs".
 */
export interface AgentWalletTransactionsListArgs {
  operation: 'transactions.list';
  accountSelector: AgentWalletQueryAccountSelectorV2;
  chains: AgentApiChainList7;
  filters: AgentWalletFilterSetV1;
  riskMode: AgentWalletRiskModeV1;
  pageSize: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletFilterSetV1".
 */
export interface AgentWalletFilterSetV1 {
  schemaVersion: 1;
  catalogDigest: string;
  /**
   * @maxItems 8
   */
  clauses: AgentWalletFilterClauseV1[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletTimestampRangeV1".
 */
export interface AgentWalletTimestampRangeV1 {
  rangeKind:
    | 'today'
    | 'yesterday'
    | 'current_week'
    | 'previous_week'
    | 'current_month'
    | 'previous_month'
    | 'rolling_days'
    | 'rolling_weeks'
    | 'rolling_months'
    | 'absolute';
  fromInclusive: UtcTimestampMs;
  toExclusive: UtcTimestampMs;
  timeZone: string;
  resolvedAt: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletTransactionsDetailArgs".
 */
export interface AgentWalletTransactionsDetailArgs {
  operation: 'transactions.detail';
  accountSelector: AgentWalletQueryAccountSelectorV2;
  hash: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletContactsListArgs".
 */
export interface AgentWalletContactsListArgs {
  operation: 'contacts.list';
  purpose?: 'send_recipient_resolution';
  accountSelector: AgentWalletQueryAccountSelectorV2;
  query: string | null;
  chains: AgentApiChainList9;
  ownWalletChains: AgentApiChainList10;
  pageSize: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolWalletContextSessionV2".
 */
export interface AgentToolWalletContextSessionV2 {
  sessionId: Uuid;
  revision: number;
  accountScope: 'current' | 'selected' | 'explicitAll';
  activeAccountRef: string;
  activeNetwork?: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolScopeIntentV2".
 */
export interface AgentToolScopeIntentV2 {
  messageId: Uuid;
  reason: 'selected_wallet_query' | 'explicit_all_wallet_query';
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDirectoryQueryToolCall".
 */
export interface AgentWalletDirectoryQueryToolCall {
  id: Uuid;
  name: 'wallet.directory.query';
  maxResultBytes: number;
  arguments: AgentWalletDirectoryQueryArgsV1;
  scopes: ['wallet.directory.read'];
  timeoutMs: number;
  directorySession: AgentWalletDirectorySessionV1;
  directoryGrant: AgentWalletDirectoryGrantV1;
  intentSource: AgentIntentSource;
  reason?: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDirectoryQueryArgsV1".
 */
export interface AgentWalletDirectoryQueryArgsV1 {
  schemaVersion: 1;
  purpose: 'send_wallet_resolution';
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDirectorySessionV1".
 */
export interface AgentWalletDirectorySessionV1 {
  sessionId: Uuid;
  revision: number;
  activeAccountRef: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDirectoryGrantV1".
 */
export interface AgentWalletDirectoryGrantV1 {
  schemaVersion: 1;
  kind: 'send_wallet_resolution';
  sourceCapabilityId: 'wallet.send-prepare';
  messageId: Uuid;
  sessionId: Uuid;
  revision: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolStatusEvent".
 */
export interface AgentToolStatusEvent {
  type: 'tool_status';
  protocolVersion: 3;
  runId: Uuid;
  sequence: number;
  toolCallId: Uuid;
  status: 'complete' | 'failed' | 'timeout' | 'rejected' | 'cancelled';
  createdAt?: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentThreadClearRequestV2".
 */
export interface AgentThreadClearRequestV2 {
  protocolVersion: 3;
  expectedThreadRevision: number;
  clientOperationId: UuidInput;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentThreadClearResponseV2".
 */
export interface AgentThreadClearResponseV2 {
  protocolVersion: 3;
  thread: AgentThreadSummaryV2;
  duplicate: boolean;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentThreadMessagesPageV2".
 */
export interface AgentThreadMessagesPageV2 {
  protocolVersion: 3;
  thread: AgentThreadSummaryV2;
  /**
   * @maxItems 100
   */
  messages: AgentPersistedMessageV2[];
  nextCursor?: AgentMessageCursorV2;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentThreadMessagesRequestV2".
 */
export interface AgentThreadMessagesRequestV2 {
  cursor?: AgentMessageCursorV2;
  limit?: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolRedaction".
 */
export interface AgentToolRedaction {
  level: 'minimal' | 'scoped';
  /**
   * @maxItems 32
   */
  omittedFields?: string[];
  maxResultBytes: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolResultAckV2".
 */
export interface AgentToolResultAckV2 {
  protocolVersion: 3;
  runId: Uuid;
  toolCallId: Uuid;
  clientToolResultId: Uuid;
  accepted: true;
  duplicate?: boolean;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDirectorySuccessToolResultRequestV1".
 */
export interface AgentWalletDirectorySuccessToolResultRequestV1 {
  protocolVersion: 3;
  runId: UuidInput;
  threadId: UuidInput;
  toolCallId: UuidInput;
  clientToolResultId: UuidInput;
  toolName: 'wallet.directory.query';
  status: 'success';
  completedAt: UtcTimestampMs;
  directorySession: AgentWalletDirectorySessionInputV1;
  result: AgentWalletDirectorySuccessV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDirectorySessionInputV1".
 */
export interface AgentWalletDirectorySessionInputV1 {
  sessionId: UuidInput;
  revision: number;
  activeAccountRef: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolSuccessEnvelopeBaseV1".
 */
export interface AgentToolSuccessEnvelopeBaseV1 {
  schemaVersion: 1;
  freshness: AgentToolFreshness;
  redaction: AgentToolRedaction;
  /**
   * @maxItems 8
   */
  warnings?: AgentToolWarning[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolWarning".
 */
export interface AgentToolWarning {
  code: 'stale_data' | 'partial_coverage' | 'omitted_optional_data' | 'refresh_failed';
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDirectoryResultV1".
 */
export interface AgentWalletDirectoryResultV1 {
  schemaVersion: 1;
  status: 'complete';
  generatedAt: UtcTimestampMs;
  coverage: {
    accountsRequested: number;
    accountsIncluded: number;
    rowsOmitted: 0;
  };
  sessionId: Uuid;
  revision: number;
  /**
   * @minItems 1
   * @maxItems 100
   */
  accounts: AgentWalletDirectoryAccountRowV1[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDirectoryAccountRowV1".
 */
export interface AgentWalletDirectoryAccountRowV1 {
  accountRef: string;
  label: string;
  isCurrent: boolean;
  state: 'active' | 'stale';
  chains: AgentApiChainList12;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDirectoryFailureToolResultRequestV1".
 */
export interface AgentWalletDirectoryFailureToolResultRequestV1 {
  protocolVersion: 3;
  runId: UuidInput;
  threadId: UuidInput;
  toolCallId: UuidInput;
  clientToolResultId: UuidInput;
  toolName: 'wallet.directory.query';
  status: 'error' | 'rejected' | 'cancelled';
  completedAt: UtcTimestampMs;
  directorySession: AgentWalletDirectorySessionInputV1;
  error: AgentToolError;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentUnsupportedToolResultRequestV1".
 */
export interface AgentUnsupportedToolResultRequestV1 {
  protocolVersion: 3;
  runId: UuidInput;
  threadId: UuidInput;
  toolCallId: UuidInput;
  clientToolResultId: UuidInput;
  toolName: string;
  status: 'rejected';
  completedAt: UtcTimestampMs;
  error: {
    code: 'tool_unsupported';
    retryable: false;
  };
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentToolWalletContextSessionInputV2".
 */
export interface AgentToolWalletContextSessionInputV2 {
  sessionId: UuidInput;
  revision: number;
  accountScope: 'current' | 'selected' | 'explicitAll';
  activeAccountRef: string;
  activeNetwork?: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletAccountInventoryResult".
 */
export interface AgentWalletAccountInventoryResult {
  operation: 'account.inventory';
  status: 'resolved';
  resolvedScope: AgentWalletResolvedScopeV1;
  generatedAt: UtcTimestampMs;
  freshness: AgentWalletDataFreshnessV2;
  coverage: AgentWalletDataCoverage;
  /**
   * @maxItems 100
   */
  accounts: AgentWalletDataAccountRowV3[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletResolvedScopeV1".
 */
export interface AgentWalletResolvedScopeV1 {
  kind: 'current' | 'explicitAll' | 'named' | 'ordinal';
  /**
   * @minItems 1
   * @maxItems 100
   */
  accounts: {
    accountRef: string;
    accountLabel: string;
  }[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDataFreshnessV2".
 */
export interface AgentWalletDataFreshnessV2 {
  asOf: UtcTimestampMs;
  source: 'cache' | 'network' | 'mixed';
  isStale: boolean;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletPortfolioTotalV1".
 */
export interface AgentWalletPortfolioTotalV1 {
  value: string;
  baseCurrency: string;
  unpricedCount: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletAssetSearchRowV1".
 */
export interface AgentWalletAssetSearchRowV1 {
  asset: AgentAssetIdentityV2;
  matchQuality: 'exact' | 'prefix' | 'partial' | 'fuzzy';
  matchedOn: 'symbol' | 'name' | 'slug' | 'address';
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletPositionsListResult".
 */
export interface AgentWalletPositionsListResult {
  operation: 'positions.list';
  status: 'resolved';
  resolvedScope: AgentWalletResolvedScopeV1;
  generatedAt: UtcTimestampMs;
  freshness: AgentWalletDataFreshnessV2;
  coverage: AgentWalletDataCoverage;
  policySummary: AgentWalletDataPolicySummaryV1;
  /**
   * @maxItems 100
   */
  positions: AgentWalletDataPositionRowV3[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDataPolicySummaryV1".
 */
export interface AgentWalletDataPolicySummaryV1 {
  riskMode: AgentWalletRiskModeV1;
  visibilityMode?: AgentWalletVisibilityModeV1;
  spamMatches: AgentWalletPolicyCounterV1;
  hiddenMatches: AgentWalletPolicyCounterV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletPolicyCounterV1".
 */
export interface AgentWalletPolicyCounterV1 {
  count: number;
  accuracy: 'exact' | 'lower_bound';
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletPortfolioAggregateResult".
 */
export interface AgentWalletPortfolioAggregateResult {
  operation: 'portfolio.aggregate';
  status: 'resolved';
  resolvedScope: AgentWalletResolvedScopeV1;
  generatedAt: UtcTimestampMs;
  freshness: AgentWalletDataFreshnessV2;
  coverage: AgentWalletDataCoverage;
  policySummary: AgentWalletDataPolicySummaryV1;
  total: AgentWalletPortfolioTotalV1;
  rangePnl?: AgentWalletPortfolioRangePnlV1;
  /**
   * @maxItems 100
   */
  historyAccounts?: {
    accountRef: string;
    wallets: string[];
  }[];
  /**
   * @maxItems 100
   */
  allocations: AgentWalletPortfolioAllocationV1[];
  /**
   * @maxItems 100
   */
  positions: AgentWalletDataPositionRowV3[];
  /**
   * @maxItems 100
   */
  aggregates: AgentWalletDataAggregateRowV2[];
  /**
   * @maxItems 5
   */
  series: AgentWalletDataSeriesV1[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletPortfolioRangePnlV1".
 */
export interface AgentWalletPortfolioRangePnlV1 {
  semantics: 'portfolio_pnl';
  range: AgentWalletQueryHistoryRangeV1;
  amount: string;
  percent?: string;
  baseCurrency: string;
  startAt: UtcTimestampMs;
  endAt: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletPortfolioAllocationV1".
 */
export interface AgentWalletPortfolioAllocationV1 {
  asset: AgentAssetIdentityV2;
  value: string;
  baseCurrency: string;
  percent: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDataAggregateRowV2".
 */
export interface AgentWalletDataAggregateRowV2 {
  rowId: string;
  kind: 'aggregate';
  groupKind: 'total' | 'account' | 'asset' | 'network' | 'position_type';
  label: string;
  value: string;
  baseCurrency: string;
  unpricedCount: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDataSeriesPointV1".
 */
export interface AgentWalletDataSeriesPointV1 {
  timestamp: UtcTimestampMs;
  value: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletTransactionsListResult".
 */
export interface AgentWalletTransactionsListResult {
  operation: 'transactions.list';
  status: 'resolved';
  resolvedScope: AgentWalletResolvedScopeV1;
  generatedAt: UtcTimestampMs;
  freshness: AgentWalletDataFreshnessV2;
  coverage: AgentWalletDataCoverage;
  policySummary: AgentWalletDataPolicySummaryV1;
  appliedFilterDigest: string;
  /**
   * @maxItems 50
   */
  transactions: AgentWalletDataTransactionRowV3[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletTransactionAmountV1".
 */
export interface AgentWalletTransactionAmountV1 {
  asset: AgentAssetIdentityV2;
  quantity: string;
  decimals: number;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletTransactionCounterpartyV1".
 */
export interface AgentWalletTransactionCounterpartyV1 {
  kind: 'wallet' | 'contact' | 'external' | 'contract' | 'unknown';
  display: string;
  addressRef?: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletTransactionSwapDetailsV1".
 */
export interface AgentWalletTransactionSwapDetailsV1 {
  from: AgentWalletTransactionAmountV1;
  to: AgentWalletTransactionAmountV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletTransactionNftDetailsV1".
 */
export interface AgentWalletTransactionNftDetailsV1 {
  action: 'transfer' | 'purchase' | 'sale' | 'mint' | 'burn' | 'other';
  displayName: string;
  collectionName?: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletTransactionContractDetailsV1".
 */
export interface AgentWalletTransactionContractDetailsV1 {
  contractDisplay: string;
  method?: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletTransactionStakingDetailsV1".
 */
export interface AgentWalletTransactionStakingDetailsV1 {
  action: 'stake' | 'unstake' | 'unstake_request' | 'claim';
  validatorDisplay?: string;
  amount?: AgentWalletTransactionAmountV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletTransactionsDetailResult".
 */
export interface AgentWalletTransactionsDetailResult {
  operation: 'transactions.detail';
  status: 'resolved';
  resolvedScope: AgentWalletResolvedScopeV1;
  generatedAt: UtcTimestampMs;
  freshness: AgentWalletDataFreshnessV2;
  coverage: AgentWalletDataCoverage;
  transaction: AgentWalletDataTransactionRowV3 | null;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletContactsListResult".
 */
export interface AgentWalletContactsListResult {
  operation: 'contacts.list';
  status: 'resolved';
  resolvedScope: AgentWalletResolvedScopeV1;
  generatedAt: UtcTimestampMs;
  freshness: AgentWalletDataFreshnessV2;
  coverage: AgentWalletDataCoverage;
  /**
   * @maxItems 300
   */
  contacts: AgentWalletDataContactRowV3[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletDataContactRowV3".
 */
export interface AgentWalletDataContactRowV3 {
  rowId: string;
  kind: 'contact';
  contactRef: string;
  addressRef: string;
  name: string;
  chain: AgentApiChain;
  addressDisplay: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletValueSeriesResult".
 */
export interface AgentWalletValueSeriesResult {
  operation: 'value.series';
  status: 'resolved';
  resolvedScope: AgentWalletResolvedScopeV1;
  generatedAt: UtcTimestampMs;
  freshness: AgentWalletDataFreshnessV2;
  coverage: AgentWalletDataCoverage;
  baseCurrency?: string;
  /**
   * @maxItems 100
   */
  historyAccounts?: {
    accountRef: string;
    asset?: AgentAssetIdentityV2;
    wallets: string[];
  }[];
  /**
   * @maxItems 5
   */
  series: AgentWalletDataSeriesV1[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletScopeResolutionRequiredResult".
 */
export interface AgentWalletScopeResolutionRequiredResult {
  operation:
    | 'account.inventory'
    | 'positions.list'
    | 'portfolio.aggregate'
    | 'transactions.list'
    | 'transactions.detail'
    | 'contacts.list'
    | 'value.series';
  status: 'scope_resolution_required';
  reason: 'ambiguous' | 'not_found';
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentUserQuotaResponseV2".
 */
export interface AgentUserQuotaResponseV2 {
  protocolVersion: 3;
  quota: AgentUserQuotaV2;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentUserQuotaV2".
 */
export interface AgentUserQuotaV2 {
  limit: number;
  used: number;
  remaining: number;
  resetAt: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletSnapshotAccountV1".
 */
export interface AgentWalletSnapshotAccountV1 {
  accountRef: string;
  label: string;
  state: 'active' | 'stale';
  chains: AgentApiChainList14;
  accountType: 'regular' | 'ledger' | 'viewOnly' | 'multisig' | 'unknown';
  isViewOnly: boolean;
  positions: AgentWalletSnapshotPositionsV1;
  rowId: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletSnapshotPositionsV1".
 */
export interface AgentWalletSnapshotPositionsV1 {
  asOf: UtcTimestampMs;
  status: 'complete' | 'partial' | 'unavailable';
  /**
   * @maxItems 10000
   */
  items: {
    row: AgentWalletDataPositionRowV3;
    visibility: 'visible' | 'hidden';
  }[];
  sourceAsOf?: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletSnapshotAckV1".
 */
export interface AgentWalletSnapshotAckV1 {
  snapshotRef: AgentWalletSnapshotRefV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletSnapshotContactsV1".
 */
export interface AgentWalletSnapshotContactsV1 {
  asOf: UtcTimestampMs;
  status: 'complete' | 'partial' | 'unavailable';
  /**
   * @maxItems 10000
   */
  items: {
    row: AgentWalletDataContactRowV3;
    accountRef?: string;
    source: 'saved' | 'own_wallet' | 'profile';
    identityRef: string;
  }[];
  sourceAsOf?: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWalletSnapshotV1".
 */
export interface AgentWalletSnapshotV1 {
  schemaVersion: 1;
  instanceId: Uuid;
  sessionId: Uuid;
  revision: number;
  snapshotRevision: number;
  activeAccountRef: string;
  activeNetwork: string;
  baseCurrency: string;
  capturedAt: UtcTimestampMs;
  /**
   * @maxItems 100
   */
  accounts: AgentWalletSnapshotAccountV1[];
  contacts: AgentWalletSnapshotContactsV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWebDigestContentV1".
 */
export interface AgentWebDigestContentV1 {
  kind: 'webDigest';
  schemaVersion: 1;
  outcome: 'complete' | 'partial' | 'empty';
  summary?: string;
  /**
   * @maxItems 20
   */
  items: AgentWebDigestItemV1[];
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "AgentWebDigestItemV1".
 */
export interface AgentWebDigestItemV1 {
  headline: string;
  summary?: string;
  url: string;
  publishedAt?: UtcTimestampMs;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "PortfolioTopPositionRowV1".
 */
export interface PortfolioTopPositionRowV1 {
  assetRef?: string;
  asset: AgentAssetIdentityV2;
  amount: PortfolioTopPositionValueV1;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "PortfolioTopPositionValueV1".
 */
export interface PortfolioTopPositionValueV1 {
  value: string;
  currency: string;
}
/**
 * This interface was referenced by `MyTonWalletAgentProtocolV2StandalonePublicWireContract`'s JSON-Schema
 * via the `definition` "PortfolioUnpricedPositionRowV1".
 */
export interface PortfolioUnpricedPositionRowV1 {
  assetRef?: string;
  asset: AgentAssetIdentityV2;
}

export interface AgentV2PublicContractTypes {
  ActionSendRecipientV1: ActionSendRecipientV1;
  AgentActionEvent: AgentActionEvent;
  AgentActionKind: AgentActionKind;
  AgentActionProposal: AgentActionProposal;
  AgentAnswerLinkV1: AgentAnswerLinkV1;
  AgentAnswerTableReferenceV1: AgentAnswerTableReferenceV1;
  AgentAnswerTableV1: AgentAnswerTableV1;
  AgentApiChain: AgentApiChain;
  AgentApiChainList: AgentApiChainList;
  AgentApiErrorV2: AgentApiErrorV2;
  AgentAppName: AgentAppName;
  AgentAssetIdentityV2: AgentAssetIdentityV2;
  AgentAssetRefV2: AgentAssetRefV2;
  AgentAssetSelector: AgentAssetSelector;
  AgentAvailabilityResponseV2: AgentAvailabilityResponseV2;
  AgentCapabilities: AgentCapabilities;
  AgentClientFeature: AgentClientFeature;
  AgentContext: AgentContext;
  AgentContextPermissions: AgentContextPermissions;
  AgentDefaultThreadResponseV2: AgentDefaultThreadResponseV2;
  AgentDeviceTokenIssueRequestV2: AgentDeviceTokenIssueRequestV2;
  AgentDeviceTokenIssueResponseV2: AgentDeviceTokenIssueResponseV2;
  AgentDisplayTableV1: AgentDisplayTableV1;
  AgentEntryPoint: AgentEntryPoint;
  AgentErrorCodeV2: AgentErrorCodeV2;
  AgentErrorEvent: AgentErrorEvent;
  AgentErrorRetryabilityBinding: AgentErrorRetryabilityBinding;
  AgentEventType: AgentEventType;
  AgentFeatureCapabilitiesResponseV2: AgentFeatureCapabilitiesResponseV2;
  AgentFollowUpTextV1: AgentFollowUpTextV1;
  AgentFollowupsEvent: AgentFollowupsEvent;
  AgentHintsResponseV2: AgentHintsResponseV2;
  AgentIntentSource: AgentIntentSource;
  AgentMarkdownMessageContentV1: AgentMarkdownMessageContentV1;
  AgentMarketAssetIdentityV1: AgentMarketAssetIdentityV1;
  AgentMarketCanonicalChainV1: AgentMarketCanonicalChainV1;
  AgentMarketEvidenceSnippetV1: AgentMarketEvidenceSnippetV1;
  AgentMarketFearGreedSourceRefV1: AgentMarketSourceRefV1;
  AgentMarketGlobalSignalSourceRefV1: AgentMarketSourceRefV1;
  AgentMarketLimitationCodeV1: AgentMarketLimitationCodeV1;
  AgentMarketPriceSeriesSourceRefV1: AgentMarketSourceRefV1;
  AgentMarketProviderNameV1: AgentMarketProviderNameV1;
  AgentMarketQuoteSourceRefV1: AgentMarketSourceRefV1;
  AgentMarketSeriesEvidenceRefV1: AgentMarketSeriesEvidenceRefV1;
  AgentMarketSourceRefV1: AgentMarketSourceRefV1;
  AgentMessageContentEndEvent: AgentMessageContentEndEvent;
  AgentMessageContentV1: AgentMessageContentV1;
  AgentMessageCursorV2: AgentMessageCursorV2;
  AgentMessageEndEvent: AgentMessageEndEvent;
  AgentMessageErrorV2: AgentMessageErrorV2;
  AgentMessageStartEvent: AgentMessageStartEvent;
  AgentNoticeArgumentsV1: AgentNoticeArgumentsV1;
  AgentNoticeCodeV1: AgentNoticeCodeV1;
  AgentNoticeContentV1: AgentNoticeContentV1;
  AgentOpenDappActionV1: AgentOpenDappActionV1;
  AgentPersistedActionV2: AgentPersistedActionV2;
  AgentPersistedMessageV2: AgentPersistedMessageV2;
  AgentPersistedNavigationActionV3: AgentPersistedNavigationActionV3;
  AgentPersistedSendFormActionV1: AgentPersistedSendFormActionV1;
  AgentPersistedStakeActionV2: AgentPersistedStakeActionV2;
  AgentPersistedSwapActionV2: AgentPersistedSwapActionV2;
  AgentPersistedWalletActionV2: AgentPersistedWalletActionV2;
  AgentPreparedPersistedActionV2: AgentPreparedPersistedActionV2;
  AgentProblemReportCapabilityV1: AgentProblemReportCapabilityV1;
  AgentProblemReportRequestV2: AgentProblemReportRequestV2;
  AgentProblemReportResponseV2: AgentProblemReportResponseV2;
  AgentPublicFollowUpOpaqueIdV2: AgentPublicFollowUpOpaqueIdV2;
  AgentPublicFollowUpV2: AgentPublicFollowUpV2;
  AgentReceiveActionV2: AgentReceiveActionV2;
  AgentReceiveActionV3: AgentReceiveActionV3;
  AgentReceiveContextBindingV2: AgentReceiveContextBindingV2;
  AgentReceiveFailureV1: AgentReceiveFailureV1;
  AgentResponseLanguageV1: AgentResponseLanguageV1;
  AgentRunActivityCodeV1: AgentRunActivityCodeV1;
  AgentRunActivityEvent: AgentRunActivityEvent;
  AgentRunApiErrorV2: AgentApiErrorV2;
  AgentRunAppendInputV2: AgentRunAppendInputV2;
  AgentRunCancelRequestV2: AgentRunCancelRequestV2;
  AgentRunCancelResponseV2: AgentRunCancelResponseV2;
  AgentRunEditInputV2: AgentRunEditInputV2;
  AgentRunFollowupRef: AgentRunFollowupRef;
  AgentRunInputV2: AgentRunInputV2;
  AgentRunOriginInputV2: AgentRunOriginInputV2;
  AgentRunRegenerateInputV2: AgentRunRegenerateInputV2;
  AgentRunRequestV2: AgentRunRequestV2;
  AgentRunRequestWireV2: AgentRunRequestWireV2;
  AgentRunStartEvent: AgentRunStartEvent;
  AgentRunUserMessage: AgentRunUserMessage;
  AgentSemanticAssetV1: AgentSemanticAssetV1;
  AgentSemanticContentEvent: AgentSemanticContentEvent;
  AgentSemanticContentV1: AgentSemanticContentV1;
  AgentSemanticMessageContentV1: AgentSemanticMessageContentV1;
  AgentSendAmountRejectionCodeV1: AgentSendAmountRejectionCodeV1;
  AgentSendFailureV1: AgentSendFailureV1;
  AgentSendFormActionV1: AgentSendFormActionV1;
  AgentStakeActionV2: AgentStakeActionV2;
  AgentStakeAmountV2: AgentStakeAmountV2;
  AgentStakeContextBindingV1: AgentStakeContextBindingV1;
  AgentStakeFailureV1: AgentStakeFailureV1;
  AgentStarterHintIdV2: AgentStarterHintIdV2;
  AgentStarterHintV2: AgentStarterHintV2;
  AgentStreamEventV2: AgentStreamEventV2;
  AgentSwapActionV2: AgentSwapActionV2;
  AgentSwapAmountV1: AgentSwapAmountV1;
  AgentSwapContextBindingV1: AgentSwapContextBindingV1;
  AgentSwapDetailsRequiredV1: AgentSwapDetailsRequiredV1;
  AgentSwapFailureV1: AgentSwapFailureV1;
  AgentTableDataEvent: AgentTableDataEvent;
  AgentTableReferenceEvent: AgentTableReferenceEvent;
  AgentTextDeltaEvent: AgentTextDeltaEvent;
  AgentTextDraftEvent: AgentTextDraftEvent;
  AgentTextLinkEvent: AgentTextLinkEvent;
  AgentThreadApiErrorV2: AgentApiErrorV2;
  AgentThreadClearRequestV2: AgentThreadClearRequestV2;
  AgentThreadClearResponseV2: AgentThreadClearResponseV2;
  AgentThreadEvent: AgentThreadEvent;
  AgentThreadMessagesPageV2: AgentThreadMessagesPageV2;
  AgentThreadMessagesRequestV2: AgentThreadMessagesRequestV2;
  AgentThreadSummaryV2: AgentThreadSummaryV2;
  AgentToolCall: AgentToolCall;
  AgentToolCallEvent: AgentToolCallEvent;
  AgentToolError: AgentToolError;
  AgentToolErrorRetryabilityBinding: AgentToolErrorRetryabilityBinding;
  AgentToolFreshness: AgentToolFreshness;
  AgentToolName: AgentToolName;
  AgentToolRedaction: AgentToolRedaction;
  AgentToolResultAckV2: AgentToolResultAckV2;
  AgentToolResultRequestV2: AgentToolResultRequestV2;
  AgentToolScope: AgentToolScope;
  AgentToolScopeIntentV2: AgentToolScopeIntentV2;
  AgentToolStatusEvent: AgentToolStatusEvent;
  AgentToolSuccessEnvelopeBaseV1: AgentToolSuccessEnvelopeBaseV1;
  AgentToolWalletContextSessionInputV2: AgentToolWalletContextSessionInputV2;
  AgentToolWalletContextSessionV2: AgentToolWalletContextSessionV2;
  AgentToolWarning: AgentToolWarning;
  AgentUnsupportedToolResultRequestV1: AgentUnsupportedToolResultRequestV1;
  AgentUserQuotaResponseV2: AgentUserQuotaResponseV2;
  AgentUserQuotaV2: AgentUserQuotaV2;
  AgentWalletAccountFilterV1: AgentWalletAccountFilterV1;
  AgentWalletAccountInventoryArgs: AgentWalletAccountInventoryArgs;
  AgentWalletAccountInventoryResult: AgentWalletAccountInventoryResult;
  AgentWalletActiveAccountV2: AgentWalletActiveAccountV2;
  AgentWalletAssetSearchRowV1: AgentWalletAssetSearchRowV1;
  AgentWalletAssetsSearchArgs: AgentWalletAssetsSearchArgs;
  AgentWalletAssetsSearchResult: AgentWalletAssetsSearchResult;
  AgentWalletContactsListArgs: AgentWalletContactsListArgs;
  AgentWalletContactsListResult: AgentWalletContactsListResult;
  AgentWalletContextGrantV2: AgentWalletContextGrantV2;
  AgentWalletContextV2: AgentWalletContextV2;
  AgentWalletDataAccountRowV3: AgentWalletDataAccountRowV3;
  AgentWalletDataAggregateRowV2: AgentWalletDataAggregateRowV2;
  AgentWalletDataContactRowV3: AgentWalletDataContactRowV3;
  AgentWalletDataCoverage: AgentWalletDataCoverage;
  AgentWalletDataCoverageLimitationV1: AgentWalletDataCoverageLimitationV1;
  AgentWalletDataFreshnessV2: AgentWalletDataFreshnessV2;
  AgentWalletDataPolicySummaryV1: AgentWalletDataPolicySummaryV1;
  AgentWalletDataPositionRowV3: AgentWalletDataPositionRowV3;
  AgentWalletDataQueryArgs: AgentWalletDataQueryArgs;
  AgentWalletDataQueryResult: AgentWalletDataQueryResult;
  AgentWalletDataQuerySuccess: AgentWalletDataQuerySuccess;
  AgentWalletDataQueryToolCall: AgentWalletDataQueryToolCall;
  AgentWalletDataSeriesPointV1: AgentWalletDataSeriesPointV1;
  AgentWalletDataSeriesV1: AgentWalletDataSeriesV1;
  AgentWalletDataTransactionRowV3: AgentWalletDataTransactionRowV3;
  AgentWalletDirectoryAccountRowV1: AgentWalletDirectoryAccountRowV1;
  AgentWalletDirectoryFailureToolResultRequestV1: AgentWalletDirectoryFailureToolResultRequestV1;
  AgentWalletDirectoryGrantV1: AgentWalletDirectoryGrantV1;
  AgentWalletDirectoryQueryArgsV1: AgentWalletDirectoryQueryArgsV1;
  AgentWalletDirectoryQueryToolCall: AgentWalletDirectoryQueryToolCall;
  AgentWalletDirectoryResultV1: AgentWalletDirectoryResultV1;
  AgentWalletDirectorySessionInputV1: AgentWalletDirectorySessionInputV1;
  AgentWalletDirectorySessionV1: AgentWalletDirectorySessionV1;
  AgentWalletDirectorySuccessToolResultRequestV1: AgentWalletDirectorySuccessToolResultRequestV1;
  AgentWalletDirectorySuccessV1: AgentWalletDirectorySuccessV1;
  AgentWalletFilterClauseV1: AgentWalletFilterClauseV1;
  AgentWalletFilterSetV1: AgentWalletFilterSetV1;
  AgentWalletPolicyCounterV1: AgentWalletPolicyCounterV1;
  AgentWalletPortfolioAggregateArgs: AgentWalletPortfolioAggregateArgs;
  AgentWalletPortfolioAggregateResult: AgentWalletPortfolioAggregateResult;
  AgentWalletPortfolioAllocationV1: AgentWalletPortfolioAllocationV1;
  AgentWalletPortfolioRangePnlV1: AgentWalletPortfolioRangePnlV1;
  AgentWalletPortfolioTotalV1: AgentWalletPortfolioTotalV1;
  AgentWalletPositionKindV1: AgentWalletPositionKindV1;
  AgentWalletPositionsListArgs: AgentWalletPositionsListArgs;
  AgentWalletPositionsListResult: AgentWalletPositionsListResult;
  AgentWalletQueryAccountSelectorV2: AgentWalletQueryAccountSelectorV2;
  AgentWalletQueryCapabilityV1: AgentWalletQueryCapabilityV1;
  AgentWalletQueryFeatureStatusV1: AgentWalletQueryFeatureStatusV1;
  AgentWalletQueryHistoryRangeV1: AgentWalletQueryHistoryRangeV1;
  AgentWalletResolvedScopeV1: AgentWalletResolvedScopeV1;
  AgentWalletRiskModeV1: AgentWalletRiskModeV1;
  AgentWalletScopeResolutionRequiredResult: AgentWalletScopeResolutionRequiredResult;
  AgentWalletSemanticOperationV2: AgentWalletSemanticOperationV2;
  AgentWalletSnapshotAccountV1: AgentWalletSnapshotAccountV1;
  AgentWalletSnapshotAckV1: AgentWalletSnapshotAckV1;
  AgentWalletSnapshotContactsV1: AgentWalletSnapshotContactsV1;
  AgentWalletSnapshotPositionsV1: AgentWalletSnapshotPositionsV1;
  AgentWalletSnapshotRefV1: AgentWalletSnapshotRefV1;
  AgentWalletSnapshotV1: AgentWalletSnapshotV1;
  AgentWalletSourceOutcomeV1: AgentWalletSourceOutcomeV1;
  AgentWalletTimestampRangeV1: AgentWalletTimestampRangeV1;
  AgentWalletTransactionAmountV1: AgentWalletTransactionAmountV1;
  AgentWalletTransactionContractDetailsV1: AgentWalletTransactionContractDetailsV1;
  AgentWalletTransactionCounterpartyV1: AgentWalletTransactionCounterpartyV1;
  AgentWalletTransactionNftDetailsV1: AgentWalletTransactionNftDetailsV1;
  AgentWalletTransactionStakingDetailsV1: AgentWalletTransactionStakingDetailsV1;
  AgentWalletTransactionSwapDetailsV1: AgentWalletTransactionSwapDetailsV1;
  AgentWalletTransactionsDetailArgs: AgentWalletTransactionsDetailArgs;
  AgentWalletTransactionsDetailResult: AgentWalletTransactionsDetailResult;
  AgentWalletTransactionsListArgs: AgentWalletTransactionsListArgs;
  AgentWalletTransactionsListResult: AgentWalletTransactionsListResult;
  AgentWalletValueSeriesArgs: AgentWalletValueSeriesArgs;
  AgentWalletValueSeriesResult: AgentWalletValueSeriesResult;
  AgentWalletVisibilityModeV1: AgentWalletVisibilityModeV1;
  AgentWebDigestContentV1: AgentWebDigestContentV1;
  AgentWebDigestItemV1: AgentWebDigestItemV1;
  AgenticWalletToolErrorCode: AgenticWalletToolErrorCode;
  PortfolioTopPositionRowV1: PortfolioTopPositionRowV1;
  PortfolioTopPositionValueV1: PortfolioTopPositionValueV1;
  PortfolioUnpricedPositionRowV1: PortfolioUnpricedPositionRowV1;
  UtcTimestampMs: UtcTimestampMs;
  Uuid: Uuid;
  UuidInput: UuidInput;
}

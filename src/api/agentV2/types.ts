import type {
  AgentAccountType, AgentAnswerLinkV1, AgentAnswerTableReferenceV1, AgentAnswerTableV1, AgentV2ErrorCode,
} from './protocol/types';
import type {
  AgentApiChain,
  AgentCapabilities,
  AgentEntryPoint,
  AgentHintsResponseV2,
  AgentPersistedMessageV2,
  AgentProblemReportRequestV2,
  AgentPublicFollowUpV2,
  AgentRunActivityEvent,
  AgentSemanticContentV1,
  AgentStakeAmountV2,
  AgentSwapAmountV1,
  AgentThreadMessagesPageV2,
  AgentThreadSummaryV2,
  AgentToolName,
  AgentToolStatusEvent,
  AgentUserQuotaV2,
  AgentV2LiveAction,
  AgentWalletSemanticOperationV2,
} from './protocol/types';

export interface AgentV2HostAsset {
  slug: string;
  chain: AgentApiChain;
  symbol: string;
  name?: string;
  tokenAddress?: string;
  decimals: number;
  priceUsd?: string | number;
  percentChange24h?: string | number;
}

export interface AgentV2HostHolding {
  asset: AgentV2HostAsset;
  balance: string;
  availableBalance?: string;
  fiatValue?: string;
  /** Canonical base-currency quote used only to revalue a read-only refreshed balance. */
  fiatPrice?: string;
  valuationStatus?: 'valued' | 'unpriced';
  visibility?: 'visible' | 'hidden';
  riskVerdict?: 'spam';
}

export type AgentV2WalletDomain =
  | 'accounts'
  | AgentV2PositionKind
  | 'transactions'
  | 'value_series'
  | 'contacts';

export type AgentV2PositionKind = 'fungible' | AgentV2HostPosition['kind'];

export interface AgentV2HostDomainState {
  state: 'fresh' | 'stale' | 'notLoaded' | 'unavailable';
  updatedAt?: string;
}

/** An NFT is its own asset; every other position names the asset its quantity is denominated in */
export type AgentV2HostPosition = AgentV2HostPositionFields & (
  | { kind: 'nft'; asset?: AgentV2HostAsset }
  | { kind: 'staking' | 'vesting' | 'vault'; asset: AgentV2HostAsset }
);

interface AgentV2HostPositionFields {
  id: string;
  chain: AgentApiChain;
  label: string;
  quantity?: string;
  valuationStatus: 'valued' | 'unpriced' | 'not_applicable';
  fiatValue?: string;
  status?: string;
  apy?: string;
  rewards?: string;
  collection?: string;
  isOnSale?: boolean;
  visibility?: 'visible' | 'hidden';
  riskVerdict?: 'spam';
}

export interface AgentV2HostAccount {
  accountId: string;
  label?: string;
  state: 'active' | 'stale' | 'deleted';
  accountType: AgentAccountType;
  isViewOnly: boolean;
  chains: AgentApiChain[];
  addresses: Partial<Record<AgentApiChain, string>>;
  /** Mainnet-only Portfolio API keys in the canonical `chain:address` form. */
  portfolioWalletKeys?: string[];
  holdings: AgentV2HostHolding[];
  positions?: AgentV2HostPosition[];
  savedAddresses?: AgentV2HostSavedAddress[];
  /** The networks whose NFTs the app has read in full; the SDK decides from them whether the NFTs of a read are */
  nftLoadedChains?: AgentApiChain[];
  domainStates?: Partial<Record<Exclude<AgentV2WalletDomain, 'nft'>, AgentV2HostDomainState>>;
}

export interface AgentV2HostSavedAddress {
  id: string;
  name: string;
  chain: AgentApiChain;
  address: string;
}

export interface AgentV2HostUiCapabilities {
  supportedActions: AgentCapabilities['supportedActions'];
  supportsFollowups: boolean;
  supportsRunActivity: boolean;
  supportsWalletDirectory: boolean;
  supportsMessageEdit: boolean;
  supportsRegenerate: boolean;
  supportsSendRecipientWithoutAsset?: boolean;
}

export interface AgentV2HostContextSnapshot {
  uiCapabilities: AgentV2HostUiCapabilities;
  builtinDapps?: { name: string; url: string }[];
  platform: 'classic' | 'ios' | 'android';
  client: 'web' | 'electron' | 'extension' | 'tma' | 'native' | 'capacitor';
  /** Frontend-only layout input for APIs whose catalog varies between compact and wide clients. */
  isLandscape?: boolean;
  lang: string;
  baseCurrency: string;
  currencyRate?: string;
  timeZone?: string;
  appVersion?: string;
  theme?: string;
  activeAccountId?: string;
  activeNetwork?: AgentApiChain;
  isTestnet?: boolean;
  /** Ordered frontend-owned staking products. Only eligible identities are projected into the run wallet grant. */
  isStakingDisabled?: boolean;
  accounts: AgentV2HostAccount[];
  /** Bounded local token catalog. It is available to wallet tools and is never sent in a run request. */
  assetCatalog?: AgentV2HostAsset[];
  /** Locally loaded swap catalog used only by the Swap preparation tool. Never sent in a run request. */
  swapAssetCatalog?: AgentV2HostAsset[];
  savedAddresses: AgentV2HostSavedAddress[];
}

type AgentV2RunCommandBase = {
  threadId?: string;
  expectedThreadRevision: number;
  /** Private, non-wire staging instruction captured when this run is started. */
};

type AgentV2RunCommandWithoutOrigin = {
  entryPoint?: never;
  followupOf?: never;
};

type AgentV2AppendOrigin = AgentV2RunCommandWithoutOrigin
  | {
    entryPoint: AgentEntryPoint;
    followupOf?: never;
  }
  | {
    entryPoint?: never;
    followupOf: { messageId: string; followupId: string };
  };

export type AgentV2AppendRunCommand = AgentV2RunCommandBase
  & { input: { kind: 'append'; text: string } }
  & AgentV2AppendOrigin;

export type AgentV2EditRunCommand = AgentV2RunCommandBase
  & { input: { kind: 'edit'; targetUserMessageId: string; text: string } }
  & AgentV2RunCommandWithoutOrigin;

export type AgentV2RegenerateRunCommand = AgentV2RunCommandBase
  & {
    input: {
      kind: 'regenerate';
      targetAssistantMessageId: string;
      /** The user message the target answers, which the run answers again; only it can widen a wallet read's scope */
      userMessageId?: string;
    };
  }
  & AgentV2RunCommandWithoutOrigin;

export type AgentV2RunCommand = (AgentV2AppendRunCommand | AgentV2EditRunCommand | AgentV2RegenerateRunCommand) & {
  developmentTraceId?: string;
};

type AgentV2RunCommandWithoutThread<T> = T extends AgentV2RunCommand
  ? Omit<T, 'threadId' | 'expectedThreadRevision'>
  : never;

export type AgentV2RunCommandInput = AgentV2RunCommandWithoutThread<AgentV2RunCommand>;

export interface AgentV2RunResult {
  clientRunId: string;
  runId?: string;
  inputMessageId?: string;
  state: 'completed' | 'failed' | 'cancelled' | 'interrupted';
}

/** A problem report on the conversation, or on one of its messages when `messageId` names it */
export type AgentV2ProblemReport = Pick<AgentProblemReportRequestV2, 'comment' | 'messageId'>;

export interface AgentV2OperationError {
  code: AgentV2ErrorCode;
  retryable: boolean;
}

export type AgentV2OperationResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: AgentV2OperationError };

export interface AgentV2HostContextUpdate {
  authorityChanged: boolean;
  preservesActiveRuns?: true;
  generation: number;
}

export type AgentV2MutationError = AgentV2OperationError;
export type AgentV2MutationResult<T> = AgentV2OperationResult<T>;

export interface AgentV2RuntimeStatus {
  enabled: boolean;
}

export type AgentV2ResolvedAction =
  | { kind: 'openReceive'; chain: AgentApiChain }
  | {
    kind: 'openStaking';
    productId: string;
    tokenSlug: string;
    amount?: AgentStakeAmountV2;
  }
  | {
    kind: 'openSwap';
    url: string;
    tokenInSlug?: string;
    tokenOutSlug?: string;
    amount?: AgentSwapAmountV1['value'];
    amountSide?: AgentSwapAmountV1['side'];
  }
  | { kind: 'sendForm'; url: string; isMaxAmount?: true }
  | { kind: 'openDapp'; url: string }
  | { kind: 'inactive' };

export type AgentV2ActionPresentation =
  | {
    kind: 'send';
    status: 'active';
    amount?: { value: string; symbol: string };
    network: AgentApiChain;
    accountLabel: string;
    recipient?: {
      kind: 'savedAddress' | 'external' | 'domain';
      label?: string;
    };
    feeStatus: 'estimated' | 'calculated_in_wallet';
    warningCodes: Array<'scam_suspected' | 'memo_required' | 'new_address'>;
    expiresAt?: string;
  }
  | { kind: 'inactive' };

type AgentV2BoundRunUpdate<T> = T & {
  clientRunId: string;
  runId: string;
  threadId: string;
};

type AgentV2RunFailure = {
  kind: 'runFailed';
  code: AgentV2ErrorCode;
  retryable: boolean;
  messageId?: string;
  resetAt?: number;
};

export type AgentV2AvailabilityState =
  | { state: 'available' }
  | { state: 'capacity_exhausted'; resetAt?: number };

export type AgentV2RateLimitState = {
  kind: 'rateLimit';
  resetAt: number;
  clientRunId: string;
};

export type AgentV2ComposerStatus =
  | { kind: 'capacity'; mode: 'blocked'; resetAt: number }
  | { kind: 'capacity'; mode: 'degraded' }
  | {
    kind: 'userQuota';
    mode: 'blocked' | 'informational';
    quota: AgentUserQuotaV2;
    resetAt: number;
    clientRunId?: string;
  }
  | (AgentV2RateLimitState & { mode: 'blocked' | 'informational' });

export type AgentV2ClientUpdate = AgentV2ClientUpdateBody & { developmentTraceId?: string };

type AgentV2ClientUpdateBody =
  | {
    kind: 'runtimeReady';
    generation: number;
    clientRunId?: never;
    runId?: never;
    threadId?: never;
  }
  | AgentV2BoundRunUpdate<{
    kind: 'runStarted';
    threadRevision: number;
    inputMessageId?: string;
  }>
  | AgentV2BoundRunUpdate<{
    kind: 'messageStarted';
    messageId: string;
    contentKind: 'markdown' | 'semantic';
    responseLanguage?: AgentPersistedMessageV2['responseLanguage'];
  }>
  | AgentV2BoundRunUpdate<{
    kind: 'answerTablesChanged';
    messageId: string;
    tables: AgentAnswerTableV1[];
    tableReferences: AgentAnswerTableReferenceV1[];
  }>
  | AgentV2BoundRunUpdate<{ kind: 'answerLinkAdded'; messageId: string; link: AgentAnswerLinkV1 }>
  | AgentV2BoundRunUpdate<{ kind: 'textDelta'; messageId: string; delta: string }>
  | AgentV2BoundRunUpdate<{ kind: 'messageContentEnded'; messageId: string }>
  | AgentV2BoundRunUpdate<{
    kind: 'messageCompleted';
    messageId: string;
    finishReason: string;
  }>
  | AgentV2BoundRunUpdate<{ kind: 'actionAvailable'; messageId: string; action: AgentV2LiveAction }>
  | AgentV2BoundRunUpdate<{
    kind: 'followupsAvailable';
    messageId: string;
    items: AgentPublicFollowUpV2[];
  }>
  | AgentV2BoundRunUpdate<{
    kind: 'semanticContentAvailable';
    messageId: string;
    content: AgentSemanticContentV1;
  }>
  | AgentV2BoundRunUpdate<{
    kind: 'toolActivityChanged';
    toolCallId: string;
    toolName: AgentToolName;
    operation?: AgentWalletSemanticOperationV2;
    status: AgentToolStatusEvent['status'] | 'running';
  }>
  | AgentV2BoundRunUpdate<{
    kind: 'runActivityChanged';
    event: AgentRunActivityEvent;
  }>
  | AgentV2BoundRunUpdate<AgentV2RunFailure>
  | AgentV2RunFailure & {
    clientRunId: string;
    runId?: never;
    threadId?: string;
  }
  | AgentV2BoundRunUpdate<{ kind: 'runCancelled' }>
  | {
    kind: 'availabilityChanged';
    availability: AgentV2AvailabilityState;
    clientRunId?: never;
    runId?: never;
    threadId?: never;
  }
  | {
    kind: 'userQuotaChanged';
    quota?: AgentUserQuotaV2;
    clientRunId?: never;
    runId?: never;
    threadId?: never;
  }
  | {
    kind: 'walletAuthorityChanged';
    preservesActiveRuns?: true;
    clientRunId?: never;
    runId?: never;
    threadId?: string;
  }
  | {
    kind: 'walletContextChanged';
    clientRunId?: never;
    runId?: never;
    threadId?: never;
  }
  | AgentV2BoundRunUpdate<{ kind: 'threadChanged'; thread: AgentThreadSummaryV2 }>
  | {
    kind: 'threadChanged';
    threadId: string;
    clientRunId?: never;
    runId?: never;
    thread: AgentThreadSummaryV2;
  };

export interface AgentV2ThreadHydration {
  thread: AgentThreadSummaryV2;
  messages: AgentV2HydratedMessage[];
  nextCursor?: AgentThreadMessagesPageV2['nextCursor'];
  incompatibleMessages?: AgentV2IncompatibleHistoryMessage[];
}

export interface AgentV2IncompatibleHistoryMessage {
  index: number;
  category: 'contract' | 'compatibility';
  boundary: string;
  messageId?: string;
}

export type AgentV2HydratedMessage = AgentPersistedMessageV2;

export type AgentV2Hints = AgentHintsResponseV2;

export type ApiUpdateAgentV2 = {
  type: 'agentV2';
  update: AgentV2ClientUpdate;
};

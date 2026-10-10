import type {
  ApiActivity,
} from '../types';
import type {
  AgentApiChain,
  AgentToolCall,
  AgentWalletDataPositionRowV3,
  AgentWalletDataQueryArgs,
  AgentWalletResolvedScopeV1,
} from './protocol/types';
import type { AgentV2HostAccount, AgentV2HostAsset } from './types';
import type { AgentV2WalletSession } from './walletSession';

export type FetchPastActivities = (
  accountId: string,
  limit: number,
  tokenSlug?: string,
  toTimestamp?: number,
  options?: { signal?: AbortSignal; shouldThrowOnError?: boolean },
) => Promise<{ activities: ApiActivity[]; hasMore: boolean } | undefined>;

export type RefreshWalletHoldings = (
  accounts: AgentV2HostAccount[],
  signal: AbortSignal,
) => Promise<Map<string, {
  byChain: Partial<Record<AgentApiChain, Record<string, bigint>>>;
  failedChains: AgentApiChain[];
}>>;

export interface WalletQueryMaterializationScope {
  accountIds: string[];
  accountScope: 'current' | 'selected' | 'explicitAll';
  accountsRequested: number;
}

export interface WalletQueryAuthorityBinding {
  accountDigest: string;
  accountScope: 'current' | 'selected' | 'explicitAll';
  activeAccountRef: string;
  profileDigest: string;
  revision: number;
  sessionId: string;
}

export interface WalletQueryMaterializationDependencies {
  session: AgentV2WalletSession;
  authorityBinding: WalletQueryAuthorityBinding;
  args: AgentWalletDataQueryArgs;
  call: AgentToolCall;
  completedAt: string;
  signal: AbortSignal;
  scope?: WalletQueryMaterializationScope;
  resolvedScope?: AgentWalletResolvedScopeV1;
  filterDigest?: string;
  fetchPastActivities?: FetchPastActivities;
  fetchActivityDetails?: (accountId: string, activity: ApiActivity, signal?: AbortSignal) => Promise<ApiActivity>;
  getTokenBySlug?: (slug: string) => AgentV2HostAsset | undefined;
  refreshWalletHoldings?: RefreshWalletHoldings;
}

export interface PositionCandidate {
  row: AgentWalletDataPositionRowV3;
  riskVerdict?: 'spam';
  visibility: 'visible' | 'hidden';
}

export interface TransactionScanOutcome {
  account: AgentV2HostAccount;
  activities: ApiActivity[];
  attempts: number;
  failed: boolean;
  hasMore: boolean;
}

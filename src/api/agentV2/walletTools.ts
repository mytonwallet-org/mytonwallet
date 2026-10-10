import type { ApiActivity } from '../types';
import type {
  AgentToolCall,
  AgentToolFreshness,
  AgentToolResultRequestV2,
  AgentWalletDirectoryResultV1,
  AgentWalletDirectorySuccessV1,
} from './protocol/types';
import type { AgentV2ToolExecutionContext, AgentV2ToolExecutor } from './runtime';
import type {
  AgentV2HostAsset,
  AgentV2HostContextSnapshot,
} from './types';
import type { WalletQueryPreflightFailure } from './walletQueryPreflight';
import type {
  FetchPastActivities,
  RefreshWalletHoldings,
} from './walletQueryTypes';
import type { AgentV2WalletSession } from './walletSession';

import { throwIfAborted } from '../../util/abortSignal';
import { logDebug } from '../../util/logs';
import {
  AGENT_V2_TOOL_CONTRACTS,
  type AgentV2ToolContractMetadata,
} from './protocol/toolContractCatalog';
import {
  AgentV2ContractError,
  decodeAgentV2ToolArguments,
} from './protocol/transportContracts';
import { classifyAgentV2Error } from './errors';
import { WalletQueryProjectionError } from './walletQueryErrors';
import { getWalletQueryPreflightFailure } from './walletQueryPreflight';
import {
  buildWalletQueryProjection,
  fitWalletQueryV5Request,
} from './walletQueryProjection';

const MAX_RESULT_BYTES = 98_304;
export interface AgentV2WalletToolDispatcherDependencies {
  session: AgentV2WalletSession;
  getConsent: () => Promise<boolean>;
  randomUuid?: () => string;
  now?: () => number;
  fetchPastActivities?: FetchPastActivities;
  fetchActivityDetails?: (
    accountId: string,
    activity: ApiActivity,
    signal?: AbortSignal,
  ) => Promise<ApiActivity>;
  getTokenBySlug?: (slug: string) => AgentV2HostAsset | undefined;
  refreshWalletHoldings?: RefreshWalletHoldings;
}

export class AgentV2WalletToolDispatcher implements AgentV2ToolExecutor {
  private readonly randomUuid: () => string;
  private readonly now: () => number;

  constructor(private readonly dependencies: AgentV2WalletToolDispatcherDependencies) {
    this.randomUuid = dependencies.randomUuid ?? (() => crypto.randomUUID());
    this.now = dependencies.now ?? Date.now;
  }

  async execute(toolCall: AgentToolCall, context: AgentV2ToolExecutionContext): Promise<AgentToolResultRequestV2> {
    const completedAt = new Date(this.now()).toISOString();
    const commonBase = {
      protocolVersion: 3 as const,
      runId: context.runId,
      threadId: context.threadId,
      toolCallId: toolCall.id,
      clientToolResultId: this.randomUuid(),
      completedAt,
    };
    if (!await this.dependencies.getConsent()) {
      return failure(commonBase, toolCall, 'consent_required', false);
    }

    const { signal } = context;
    let request: AgentToolResultRequestV2;

    try {
      const contract = AGENT_V2_TOOL_CONTRACTS.find(({ name }) => name === toolCall.name);
      if (!contract) throw new WalletToolError('tool_unsupported', 'This wallet tool is not supported.', false);
      this.assertAdmission(toolCall, contract, context);
      try {
        decodeAgentV2ToolArguments(toolCall);
      } catch (error) {
        if (error instanceof AgentV2ContractError) {
          throw new WalletToolError('validation_failed', 'The wallet tool arguments are invalid.', false);
        }
        throw error;
      }

      const authority = await this.captureAuthority(toolCall);
      if (toolCall.name === 'wallet.directory.query') {
        const result = this.dependencies.session.buildWalletDirectory(completedAt);
        request = {
          ...commonBase,
          directorySession: toolCall.directorySession,
          toolName: toolCall.name,
          status: 'success',
          result: directorySuccessEnvelope(result, completedAt, toolCall.maxResultBytes),
        } satisfies AgentToolResultRequestV2;
      } else if (toolCall.name === 'wallet.data.query') {
        const result = await this.executeWalletQuery(toolCall, completedAt, context, authority);
        request = {
          ...commonBase,
          walletContextSession: toolCall.walletContextSession,
          toolName: toolCall.name,
          status: 'success',
          result: successEnvelope(result, completedAt, {
            freshness: storeFreshness(completedAt),
            omittedFields: ['rawAccountId', 'fullTransactionHash'],
            maxResultBytes: toolCall.maxResultBytes,
          }),
        } satisfies AgentToolResultRequestV2;
        fitWalletQueryV5Request(request, toolCall.maxResultBytes ?? MAX_RESULT_BYTES);
      } else {
        throw new WalletToolError('tool_unsupported', 'This wallet tool is not supported.', false);
      }

      throwIfAborted(signal);
      await this.assertConsentAndAuthority(toolCall, authority);
      const preflightFailure = getWalletQueryPreflightFailure(toolCall, request);
      if (preflightFailure) {
        throw new WalletToolError('validation_failed', getWalletQueryPreflightMessage(preflightFailure), false);
      }
      if (serializedByteLength(request) > (toolCall.maxResultBytes ?? MAX_RESULT_BYTES)) {
        request = failure(commonBase, toolCall, 'result_too_large', false);
      }
      await this.assertConsentAndAuthority(toolCall, authority);
    } catch (error) {
      const failureKind = classifyAgentV2Error(error).kind;
      const isCancelled = failureKind === 'cancellation';
      logDebug('AgentV2 wallet tool execution', {
        stage: 'failed',
        failureKind,
        toolCallId: toolCall.id,
        toolName: toolCall.name,
        errorCode: error instanceof WalletToolError || error instanceof WalletQueryProjectionError
          ? error.code
          : undefined,
      });
      request = error instanceof WalletToolError || error instanceof WalletQueryProjectionError
        ? failure(commonBase, toolCall, error.code, error.retryable, 'status' in error ? error.status : 'rejected')
        : failure(
          commonBase,
          toolCall,
          'tool_failed',
          true,
          isCancelled ? 'cancelled' : 'error',
        );
    }

    if (context.signal.aborted) {
      return failure(commonBase, toolCall, 'tool_failed', true, 'cancelled');
    }
    return request;
  }

  private async executeWalletQuery(
    toolCall: Extract<AgentToolCall, { name: 'wallet.data.query' }>,
    completedAt: string,
    context: AgentV2ToolExecutionContext,
    authority: Awaited<ReturnType<AgentV2WalletSession['walletAuthorityBinding']>>,
  ) {
    const args = toolCall.arguments;
    logDebug('AgentV2 wallet query', {
      stage: 'projection_started',
      toolCallId: toolCall.id,
      operation: args.operation,
    });
    const result = await buildWalletQueryProjection({
      session: this.dependencies.session,
      args,
      call: toolCall,
      completedAt,
      signal: context.signal,
      fetchPastActivities: this.dependencies.fetchPastActivities,
      fetchActivityDetails: this.dependencies.fetchActivityDetails,
      getTokenBySlug: this.dependencies.getTokenBySlug,
      refreshWalletHoldings: this.dependencies.refreshWalletHoldings,
      authorityBinding: {
        accountDigest: authority.accountDigest,
        accountScope: toolCall.walletContextSession.accountScope,
        activeAccountRef: toolCall.walletContextSession.activeAccountRef,
        profileDigest: authority.profileDigest,
        revision: toolCall.walletContextSession.revision,
        sessionId: toolCall.walletContextSession.sessionId,
      },
    });
    logDebug('AgentV2 wallet query', {
      stage: 'projection_completed',
      toolCallId: toolCall.id,
      operation: result.operation,
      resultStatus: result.status,
    });
    return result;
  }

  private assertAdmission(
    toolCall: AgentToolCall,
    contract: AgentV2ToolContractMetadata,
    context: AgentV2ToolExecutionContext,
  ) {
    throwIfAborted(context.signal);
    if (toolCall.scopes.length !== 1 || toolCall.scopes[0] !== contract.scopes[0]) {
      throw new WalletToolError('tool_scope_mismatch', 'The wallet tool scope is invalid.', false);
    }
    const isToolSupported = toolCall.name === 'wallet.data.query'
      ? this.dependencies.session.isWalletQueryAvailable()
      : this.dependencies.session.buildContext().capabilities.features.includes('walletDirectory');
    if (!isToolSupported) {
      throw new WalletToolError('capability_unsupported', 'This wallet tool is not available.', false);
    }
    const snapshot = this.dependencies.session.snapshot();
    const active = getActiveAccount(snapshot.host);
    const activeRef = active ? snapshot.accountRefs.get(active.accountId) : undefined;
    if (toolCall.name === 'wallet.directory.query') {
      const session = toolCall.directorySession;
      const grant = toolCall.directoryGrant;
      if (
        !active
        || active.state !== 'active'
        || !activeRef
        || !session
        || !grant
        || toolCall.intentSource?.kind !== 'userMessage'
        || toolCall.intentSource.messageId !== context.messageId
        || grant.messageId !== context.messageId
        || grant.sessionId !== session.sessionId
        || grant.revision !== session.revision
        || session.sessionId !== snapshot.sessionId
        || session.revision !== snapshot.revision
        || session.activeAccountRef !== activeRef
      ) throw new WalletToolError('tool_scope_mismatch', 'The wallet directory authority is invalid.', false);
      return;
    }
    const walletSession = toolCall.walletContextSession;
    if (
      !active
      || active.state !== 'active'
      || !activeRef
      || !walletSession
      || walletSession.sessionId !== snapshot.sessionId
      || walletSession.revision !== snapshot.revision
      || walletSession.activeAccountRef !== activeRef
      || walletSession.activeNetwork !== snapshot.host?.activeNetwork
    ) throw new WalletToolError('wallet_context_changed', 'The active wallet changed.', false);
  }

  private async captureAuthority(toolCall: AgentToolCall) {
    const authority = await this.dependencies.session.walletAuthorityBinding();
    const session = toolCall.name === 'wallet.directory.query'
      ? toolCall.directorySession
      : toolCall.walletContextSession;
    if (
      !session
      || authority.sessionId !== session.sessionId
      || authority.revision !== session.revision
    ) throw new WalletToolError('wallet_context_changed', 'The active wallet changed.', false);
    return authority;
  }

  private async assertConsentAndAuthority(
    toolCall: AgentToolCall,
    expected: Awaited<ReturnType<AgentV2WalletSession['walletAuthorityBinding']>>,
  ) {
    if (!await this.dependencies.getConsent()) {
      throw new WalletToolError('consent_required', 'Agent consent is required.', false);
    }
    const current = await this.captureAuthority(toolCall);
    if (authorityBinding(current) !== authorityBinding(expected)) {
      throw new WalletToolError('wallet_context_changed', 'The active wallet changed.', false);
    }
  }
}

class WalletToolError extends Error {
  constructor(
    readonly code: Extract<AgentToolResultRequestV2, { status: 'error' }>['error']['code'],
    message: string,
    readonly retryable: boolean,
    readonly status: 'error' | 'rejected' | 'cancelled' = 'rejected',
  ) {
    super(message);
  }
}

function authorityBinding(authority: Awaited<ReturnType<AgentV2WalletSession['walletAuthorityBinding']>>) {
  return JSON.stringify([
    authority.accountDigest,
    authority.profileDigest,
    authority.revision,
    authority.sessionId,
  ]);
}

function getWalletQueryPreflightMessage(failure: WalletQueryPreflightFailure) {
  switch (failure.reason) {
    case 'duplicate_transaction_row_id':
      return 'Wallet transaction identifiers are invalid.';
    case 'invalid_transaction_quantity':
      return 'Wallet transaction amounts are invalid.';
    case 'non_monotonic_transaction_order':
      return 'Wallet transactions are not in a valid order.';
    case 'transaction_timestamp_out_of_bounds':
      return 'Wallet transaction timestamps are outside the requested range.';
    case 'transaction_detail_hash_leaked':
      return 'Wallet transaction details contain a full transaction hash.';
  }
}

type ToolResultBase = Pick<
  AgentToolResultRequestV2,
  'protocolVersion' | 'runId' | 'threadId' | 'toolCallId' | 'clientToolResultId' | 'completedAt'
>;
type ToolResultFailureStatus = 'error' | 'rejected' | 'cancelled';

function failure(
  base: ToolResultBase,
  toolCall: AgentToolCall,
  code: Extract<AgentToolResultRequestV2, { status: 'error' }>['error']['code'],
  retryable: boolean,
  status: ToolResultFailureStatus = 'rejected',
): AgentToolResultRequestV2 {
  if (toolCall.name === 'wallet.directory.query') {
    return {
      ...base,
      directorySession: toolCall.directorySession,
      toolName: toolCall.name,
      status,
      error: { code, retryable },
    } satisfies AgentToolResultRequestV2;
  }

  const resultBase = {
    ...base,
    walletContextSession: toolCall.walletContextSession,
    toolName: toolCall.name,
    error: { code, retryable },
  };
  switch (status) {
    case 'error':
      return { ...resultBase, status: 'error' } satisfies AgentToolResultRequestV2;
    case 'rejected':
      return { ...resultBase, status: 'rejected' } satisfies AgentToolResultRequestV2;
    case 'cancelled':
      return { ...resultBase, status: 'cancelled' } satisfies AgentToolResultRequestV2;
  }
}

function successEnvelope<T>(
  result: T,
  completedAt: string,
  metadata?: {
    freshness?: AgentToolFreshness;
    omittedFields?: string[];
    maxResultBytes?: number;
    redactionLevel?: 'minimal' | 'scoped';
    warnings?: { code: 'partial_coverage' }[];
  },
) {
  return {
    schemaVersion: 1 as const,
    freshness: metadata?.freshness ?? storeFreshness(completedAt),
    redaction: {
      level: metadata?.redactionLevel ?? 'scoped' as const,
      omittedFields: metadata?.omittedFields ?? ['rawAccountId', 'address', 'walletAddress'],
      maxResultBytes: metadata?.maxResultBytes ?? MAX_RESULT_BYTES,
    },
    ...(metadata?.warnings?.length ? { warnings: metadata.warnings } : {}),
    result,
  };
}

function directorySuccessEnvelope(
  result: AgentWalletDirectoryResultV1,
  completedAt: string,
  maxResultBytes = MAX_RESULT_BYTES,
): AgentWalletDirectorySuccessV1 {
  return {
    schemaVersion: 1,
    freshness: storeFreshness(completedAt),
    redaction: {
      level: 'scoped',
      omittedFields: [],
      maxResultBytes,
    },
    result,
  };
}

function serializedByteLength(value: unknown) {
  return new TextEncoder().encode(JSON.stringify(value)).byteLength;
}

function storeFreshness(asOf: string) {
  return { asOf, source: 'store' as const, isStale: false as const };
}

function getActiveAccount(host?: AgentV2HostContextSnapshot) {
  return host?.accounts.find(({ accountId }) => accountId === host.activeAccountId);
}

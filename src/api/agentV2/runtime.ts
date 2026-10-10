import type { Storage } from '../storages/types';
import type {
  AgentMessageEndEvent,
  AgentRunCancelResponseV2,
  AgentRunRequestWireV2,
  AgentToolCall,
  AgentToolResultRequestV2,
  AgentV2FinishReason,
  AgentWalletSemanticOperationV2,
} from './protocol/types';
import type {
  AgentV2ActionPresentation,
  AgentV2ClientUpdate,
  AgentV2Hints,
  AgentV2HostContextSnapshot,
  AgentV2ProblemReport,
  AgentV2ResolvedAction,
  AgentV2RunCommand,
  AgentV2RunResult,
  AgentV2ThreadHydration,
} from './types';

import { APP_ENV } from '../../config';
import { mergeAbortSignalsWithTimeout, pauseWithAbortSignal } from '../../util/abortSignal';
import { logDebug, logDebugError } from '../../util/logs';
import { decodeAgentV2WalletSnapshotAck } from './protocol/decoders/coreRun';
import {
  AgentV2CompatibilityError,
  AgentV2ContractError,
  decodeAgentV2DefaultThread,
  decodeAgentV2Messages,
  decodeAgentV2ProblemReport,
  decodeAgentV2RunCancel,
  decodeAgentV2ThreadClear,
} from './protocol/transportContracts';
import { AgentV2ActionResolver } from './actionResolver';
import {
  AgentClientTrace,
  type ClientTimingSink,
  createClientTimingSender,
  newClientTraceId,
} from './developmentTelemetry';
import { classifyAgentV2Error, isRetryableAgentV2RunError } from './errors';
import {
  AGENT_V2_REQUEST_TIMEOUT_MS,
  AgentV2HttpError,
  AgentV2IdentityService,
  decodeHttpError,
} from './identity';
import {
  type AgentV2StreamBinding,
  type AgentV2StreamItem,
  AgentV2StreamTransportError,
  type AgentV2UnsupportedToolCall,
  parseAgentV2Ndjson,
} from './ndjson';
import { buildAgentV2RunOrigin } from './runCommand';
import { AgentV2RuntimeProbes } from './runtimeProbes';
import { DEFAULT_SECRET_PHRASE_PLACEHOLDER, getSecretPhraseWordList, removeSecretPhrases } from './secretPhrase';
import { AgentV2StreamMessage } from './streamMessage';
import { type AgentV2ToolExecutionContext, type AgentV2ToolExecutor, AgentV2ToolRunner } from './toolRunner';
import { isWalletSelectionChange } from './walletAuthority';
import { AgentV2WalletSession } from './walletSession';
import { AgentV2WalletSnapshotSync } from './walletSnapshotSync';

export type { AgentV2ToolExecutionContext, AgentV2ToolExecutor } from './toolRunner';

export const AGENT_V2_CONSENT_STORAGE_KEY = 'agentV2Consent';
const RECONNECT_MAX_DELAY_MS = 2_000;
const RETRY_BASE_DELAY_MS = 250;
const RECONNECT_BACKOFF_EXPONENT_CAP = 3;
const PRE_ADMISSION_MAX_ATTEMPTS = 3;
const STREAM_PROTOCOL_NO_PROGRESS_MAX_ATTEMPTS = 3;
const REMOTE_CANCEL_TIMEOUT_MS = 3_000;
const UTC_DAY_MS = 24 * 60 * 60_000;
const FAILED_RUN_RETRY_GRACE_MS = 5 * 60_000;
const FAILED_RUN_RETRY_MAX_TTL_MS = UTC_DAY_MS;
interface RunState {
  trace?: AgentClientTrace;
  authorityGeneration: number;
  runGeneration: number;
  clientRunId: string;
  request: AgentRunRequestWireV2;
  /** The user message the run answers; a regenerate request names only the answer it replaces */
  userMessageId?: string;
  controller: AbortController;
  binding: AgentV2StreamBinding;
  outcome?: AgentV2RunResult['state'];
  threadId?: string;
  message: AgentV2StreamMessage;
  pendingToolResults: Map<string, AgentToolResultRequestV2>;
  pendingToolCallIds: Set<string>;
  toolActivityByCallId: Map<string, {
    name: AgentToolCall['name'];
    operation?: AgentWalletSemanticOperationV2;
  }>;
}

interface FailedRunRequest {
  expiresAt: number;
  request: AgentRunRequestWireV2;
  userMessageId?: string;
}

export interface AgentV2RuntimeDependencies {
  telemetrySink?: ClientTimingSink;
  storage: Storage;
  baseUrl: string;
  fetch: typeof fetch;
  onUpdate: (update: AgentV2ClientUpdate) => void;
  now?: () => number;
  randomUuid?: () => string;
  wait?: (milliseconds: number, signal: AbortSignal) => Promise<void>;
  requestTimeoutMs?: number;
  walletSession?: AgentV2WalletSession;
  toolExecutor?: AgentV2ToolExecutor;
}

export class AgentV2Runtime {
  private readonly snapshots: AgentV2WalletSnapshotSync;
  private isChatActive = false;
  private readonly timingSink?: ClientTimingSink;
  private readonly toolRunner: AgentV2ToolRunner;
  private readonly probes: AgentV2RuntimeProbes;
  private readonly identity: AgentV2IdentityService;
  private readonly walletSession: AgentV2WalletSession;
  private readonly randomUuid: () => string;
  /** The last report that got no answer, so sending it again reuses its operation id */
  private unansweredProblemReport?: { key: string; clientOperationId: string };
  private readonly wait: (milliseconds: number, signal: AbortSignal) => Promise<void>;
  private readonly requestTimeoutMs: number;
  private readonly lifecycleController = new AbortController();
  private readonly runs = new Map<string, RunState>();
  private readonly actions: AgentV2ActionResolver;
  private readonly backgroundTasks = new Set<Promise<void>>();
  private readonly clearGenerationByThreadId = new Map<string, number>();

  private authorityGeneration = 0;
  private runGeneration = 0;
  private walletContextGeneration = 0;
  private threadGeneration = 0;
  private consentPromise?: Promise<boolean>;
  private failedRunRequestTimer?: ReturnType<typeof setTimeout>;
  private toolExecutor: AgentV2ToolExecutor;
  private consentWritePromise?: Promise<boolean>;
  private failedRunRequest?: FailedRunRequest;

  constructor(private readonly dependencies: AgentV2RuntimeDependencies) {
    this.timingSink
      = dependencies.telemetrySink
        ?? (APP_ENV === 'development'
          && /^https?:\/\/(?:localhost|127\.0\.0\.1|\[::1\])(?::[0-9]+)?\//.test(dependencies.baseUrl)
          ? createClientTimingSender(dependencies.baseUrl, dependencies.fetch)
          : undefined);
    this.randomUuid = dependencies.randomUuid ?? (() => crypto.randomUUID());
    this.wait = dependencies.wait ?? pauseWithAbortSignal;
    this.requestTimeoutMs = dependencies.requestTimeoutMs ?? AGENT_V2_REQUEST_TIMEOUT_MS;
    this.walletSession = dependencies.walletSession ?? new AgentV2WalletSession();
    this.actions = new AgentV2ActionResolver(this.walletSession, () => this.now());
    this.toolExecutor = dependencies.toolExecutor ?? new UnsupportedToolExecutor(this.randomUuid);
    this.identity = new AgentV2IdentityService({
      storage: dependencies.storage,
      baseUrl: dependencies.baseUrl,
      fetch: dependencies.fetch,
      now: dependencies.now,
      randomUuid: this.randomUuid,
      requestTimeoutMs: this.requestTimeoutMs,
    });
    this.snapshots = new AgentV2WalletSnapshotSync({
      session: this.walletSession, now: () => this.now(), instanceId: this.randomUuid,
      send: (snapshot, signal) => this.getJson(`${this.dependencies.baseUrl}/wallet-snapshots`,
        decodeAgentV2WalletSnapshotAck, {
          method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(snapshot), signal,
        }),
    });
    this.probes = new AgentV2RuntimeProbes({
      baseUrl: dependencies.baseUrl,
      walletSession: this.walletSession,
      getJson: (url, decoder, init, trace) => this.getJson(url, decoder, init, { trace }),
      onUpdate: (update) => this.emitUpdate(update),
      now: () => this.now(),
    });
    this.toolRunner = new AgentV2ToolRunner({
      getJson: (url, decoder, init, options) => this.getJson(url, decoder, init, options),
      baseUrl: dependencies.baseUrl,
      executor: () => this.toolExecutor,
      discard: (toolCallId) => this.discardToolResult(toolCallId),
      now: () => this.now(),
      randomUuid: this.randomUuid,
      wait: this.wait,
      requestTimeoutMs: this.requestTimeoutMs,
    });
  }

  setToolExecutor(executor: AgentV2ToolExecutor) {
    this.assertActive();
    this.toolExecutor = executor;
  }

  getConsent(): Promise<boolean> {
    this.assertActive();
    this.consentPromise ??= this.readConsent();
    return this.consentPromise;
  }

  acceptConsent() {
    this.assertActive();
    const operation = this.persistConsent().finally(() => {
      if (this.consentWritePromise === operation) this.consentWritePromise = undefined;
    });
    this.consentWritePromise = operation;
    return operation;
  }

  private async persistConsent() {
    const record = JSON.stringify({
      version: 2,
      accepted: true,
      updatedAt: new Date(this.now()).toISOString(),
    });
    await this.dependencies.storage.setItem(AGENT_V2_CONSENT_STORAGE_KEY, record);
    this.assertActive();
    this.consentPromise = Promise.resolve(true);
    return true;
  }

  updateHostContext(snapshot?: AgentV2HostContextSnapshot): Promise<boolean> {
    this.assertActive();
    const previousHost = this.walletSession.snapshot().host;
    let walletSessionUpdate: ReturnType<AgentV2WalletSession['update']>;

    try {
      walletSessionUpdate = this.walletSession.update(snapshot);
    } catch (error) {
      logDebugError('AgentV2 host context', { stage: 'degraded_to_no_wallet' }, error);
      walletSessionUpdate = this.walletSession.update();
    }

    const { hasAuthorityChanged, hasWalletContextChanged } = walletSessionUpdate;
    if (hasWalletContextChanged) {
      this.walletContextGeneration += 1;
    }
    if (hasAuthorityChanged) {
      this.authorityGeneration += 1;
      const isSelectionChange = isWalletSelectionChange(previousHost, this.walletSession.snapshot().host);
      if (!isSelectionChange) this.runGeneration += 1;
      const runIds = isSelectionChange ? [] : this.cancelAllLocally();
      this.clearFailedRunRequests();
      this.toolExecutor.clear?.();
      this.emitUpdate({
        kind: 'walletAuthorityChanged',
        ...(isSelectionChange ? { preservesActiveRuns: true as const } : {}),
      });
      runIds.forEach((runId) => this.scheduleRemoteCancellation(runId));
    } else if (hasWalletContextChanged) {
      this.emitUpdate({ kind: 'walletContextChanged' });
    }
    if (this.isChatActive) {
      this.snapshots.refresh();
    } else if (!this.walletSession.snapshot().host?.activeAccountId) {
      this.snapshots.reset();
    }
    return Promise.resolve(hasAuthorityChanged);
  }

  async setChatActive(isActive: boolean) {
    this.isChatActive = isActive;
    this.snapshots.setActive(false);
    if (!isActive || !await this.getConsent()) return;
    if (this.lifecycleController.signal.aborted || !this.isChatActive) return;
    this.snapshots.setActive(true);
  }

  getRunLifecycleGeneration() {
    return this.runGeneration;
  }

  getHints(langCode?: string): Promise<AgentV2Hints> {
    this.assertActive();
    return this.probes.getHints(langCode);
  }

  async getAvailability() {
    this.assertActive();
    await this.requireConsent();
    await this.probes.ensureAvailability();
    this.assertActive();
  }

  async getUserQuota() {
    this.assertActive();
    await this.requireConsent();
    await this.probes.ensureUserQuota();
    this.assertActive();
  }

  /** Whether the server takes problem reports, as of its feature capabilities cached by this runtime */
  async getProblemReportAvailability() {
    this.assertActive();
    await this.requireConsent();
    await this.probes.ensureFeatureCapabilities();
    this.assertActive();
    return this.probes.isProblemReportAvailable();
  }

  async getDefaultThread() {
    this.assertActive();
    await this.requireConsent();
    return this.getJson(`${this.dependencies.baseUrl}/threads/default`, decodeAgentV2DefaultThread);
  }

  async getMessages(threadId: string, cursorValue?: string, limit = 100): Promise<AgentV2ThreadHydration> {
    this.assertActive();
    await this.requireConsent();
    const authorityGeneration = this.authorityGeneration;
    const walletContextGeneration = this.walletContextGeneration;
    const threadGeneration = this.threadGeneration;
    const params = new URLSearchParams({ limit: String(limit) });
    if (cursorValue) params.set('cursor', cursorValue);
    const page = await this.getJson(
      `${this.dependencies.baseUrl}/threads/${encodeURIComponent(threadId)}/messages?${params}`,
      decodeAgentV2Messages,
    );
    this.assertAuthorityGeneration(authorityGeneration);
    this.assertWalletContextGeneration(walletContextGeneration);
    this.assertThreadBinding(threadId, page.thread.id);
    page.messages.forEach((message) => this.assertThreadBinding(threadId, message.threadId));
    const persistedMessages = page.messages;
    if (threadGeneration !== this.threadGeneration) throw invalidStreamEvent();
    this.assertAuthorityGeneration(authorityGeneration);
    this.assertWalletContextGeneration(walletContextGeneration);
    for (const message of persistedMessages) {
      for (const action of message.actions ?? []) {
        this.actions.registerPersistedAction(threadId, message.id, action);
      }
    }
    return {
      thread: page.thread,
      messages: persistedMessages,
      nextCursor: page.nextCursor,
      ...(page.incompatibleMessages?.length && {
        incompatibleMessages: page.incompatibleMessages,
      }),
    };
  }

  recordDevelopmentTelemetry(events: Parameters<ClientTimingSink>[0]) {
    this.timingSink?.(events);
  }

  async startRun(command: AgentV2RunCommand): Promise<AgentV2RunResult> {
    const trace = this.timingSink
      ? new AgentClientTrace(command.developmentTraceId ?? newClientTraceId(), this.timingSink)
      : undefined;
    const end = trace?.start('client_request');
    try {
      const result = await this.startRunWithTrace(command, trace);
      end?.(result.state === 'completed' ? 'success' : result.state === 'cancelled' ? 'cancelled' : 'error');
      return result;
    } catch (error) {
      end?.('error');
      throw error;
    }
  }

  private async startRunWithTrace(
    command: AgentV2RunCommand,
    trace?: AgentClientTrace,
  ): Promise<AgentV2RunResult> {
    const prepared = trace?.start('client_preparation');
    try {
      this.assertActive();
      const origin = buildAgentV2RunOrigin(command);
      const clearGeneration = this.getClearGeneration(command.threadId);
      await this.requireConsent();
      if (command.threadId && command.input.kind !== 'append') this.invalidateThread(command.threadId);
      const clientRunId = this.randomUuid();
      const messageId = command.input.kind === 'regenerate' ? undefined : this.randomUuid();
      await this.probes.ensureFeatureCapabilities(prepared?.trace);
      this.assertActive();
      const authorityGeneration = this.authorityGeneration;
      const runGeneration = this.runGeneration;
      const built = this.walletSession.buildContext();
      const input
        = command.input.kind === 'append'
          ? { kind: 'append' as const, message: { id: messageId!, text: hideSecretPhrases(command.input.text) } }
          : command.input.kind === 'edit'
            ? {
              kind: 'edit' as const,
              targetUserMessageId: command.input.targetUserMessageId,
              message: { id: messageId!, text: hideSecretPhrases(command.input.text) },
            }
            : { kind: 'regenerate' as const, targetAssistantMessageId: command.input.targetAssistantMessageId };
      const request: AgentRunRequestWireV2 = {
        protocolVersion: 3,
        clientRunId,
        ...(command.threadId ? { threadId: command.threadId } : {}),
        expectedThreadRevision: command.expectedThreadRevision,
        ...origin,
        input,
        context: built.context,
        capabilities: built.capabilities,
        walletContext: built.walletContext,
        ...this.snapshots.forRun(),
      };
      await this.requireConsent();
      if (runGeneration !== this.runGeneration) this.assertAuthorityGeneration(authorityGeneration);
      // A clear of the thread cancels a run it finds still being prepared, before the run reaches the server
      if (clearGeneration !== this.getClearGeneration(command.threadId)) {
        prepared?.('cancelled');
        return { clientRunId, ...(messageId ? { inputMessageId: messageId } : {}), state: 'cancelled' };
      }
      prepared?.();
      const userMessageId = command.input.kind === 'regenerate' ? command.input.userMessageId : messageId;
      return this.executeRun(request, authorityGeneration, trace, userMessageId);
    } catch (error) {
      prepared?.('error');
      throw error;
    }
  }

  async retryRun(clientRunId: string): Promise<AgentV2RunResult | undefined> {
    this.assertActive();
    await this.requireConsent();
    const authorityGeneration = this.authorityGeneration;
    const failed = this.failedRunRequest?.request.clientRunId === clientRunId
      ? this.failedRunRequest
      : undefined;
    if (!failed) return undefined;
    this.clearFailedRunRequests();
    if (failed.expiresAt <= this.now()) return undefined;
    const trace = this.timingSink ? new AgentClientTrace(newClientTraceId(), this.timingSink) : undefined;
    const end = trace?.start('client_request');
    try {
      await this.probes.ensureFeatureCapabilities(trace);
      this.assertAuthorityGeneration(authorityGeneration);
      await this.requireConsent();
      this.assertAuthorityGeneration(authorityGeneration);
      const result = await this.executeRun(failed.request, authorityGeneration, trace, failed.userMessageId);
      end?.(result.state === 'completed' ? 'success' : result.state === 'cancelled' ? 'cancelled' : 'error');
      return result;
    } catch (error) {
      end?.('error');
      throw error;
    }
  }

  private async executeRun(
    request: AgentRunRequestWireV2,
    authorityGeneration = this.authorityGeneration,
    trace?: AgentClientTrace,
    userMessageId?: string,
  ): Promise<AgentV2RunResult> {
    const inputMessageId = getRunInputMessageId(request);
    const state: RunState = {
      trace: trace ?? (this.timingSink ? new AgentClientTrace(newClientTraceId(), this.timingSink) : undefined),
      authorityGeneration,
      runGeneration: this.runGeneration,
      clientRunId: request.clientRunId,
      request,
      ...(userMessageId ? { userMessageId } : {}),
      controller: new AbortController(),
      binding: { clientRunId: request.clientRunId, lastSequence: 0, rawBySequence: new Map() },
      message: new AgentV2StreamMessage(),
      pendingToolResults: new Map(),
      pendingToolCallIds: new Set(),
      toolActivityByCallId: new Map(),
    };
    this.runs.set(request.clientRunId, state);

    try {
      await this.followRun(state);
      return {
        clientRunId: request.clientRunId,
        runId: state.binding.runId,
        ...(inputMessageId ? { inputMessageId } : {}),
        state: state.outcome ?? 'interrupted',
      };
    } catch (error) {
      if (state.controller.signal.aborted) {
        return {
          clientRunId: request.clientRunId,
          runId: state.binding.runId,
          ...(inputMessageId ? { inputMessageId } : {}),
          state: 'cancelled',
        };
      }
      if (state.binding.lastSequence === 0 && this.isAuthorityGenerationCurrent(state.authorityGeneration)) {
        const retryExpiresAt = failedRunRequestExpiresAt(error, this.now());
        if (retryExpiresAt !== undefined) {
          this.retainFailedRunRequest(request, retryExpiresAt, state.userMessageId);
        }
      }
      this.emitFailure(error, state);
      const outcome = error instanceof AgentV2HttpError
        && error.status === 409
        && error.code === 'run_replay_expired'
        ? 'interrupted'
        : 'failed';
      return {
        clientRunId: request.clientRunId,
        runId: state.binding.runId,
        ...(inputMessageId ? { inputMessageId } : {}),
        state: outcome,
      };
    } finally {
      state.pendingToolCallIds.forEach((toolCallId) => this.discardToolResult(toolCallId));
      state.pendingToolCallIds.clear();
      state.pendingToolResults.clear();
      this.runs.delete(request.clientRunId);
      if (this.isRunCurrent(state)) {
        if (
          state.outcome === 'completed'
        ) {
          void this.probes.refreshAvailability();
        }
        void this.probes.refreshUserQuota();
      }
    }
  }

  async cancelRun(runId: string) {
    this.assertActive();
    const state = [...this.runs.values()].find((candidate) => candidate.binding.runId === runId);
    let result: AgentRunCancelResponseV2;
    try {
      result = await this.requestRunCancel(runId);
    } catch (error) {
      // The user stopped the run, so it stops here even when the server did not confirm
      state?.controller.abort();
      throw error;
    }
    this.assertRunBinding(runId, result.runId);
    this.emitUpdate({ kind: 'threadChanged', threadId: result.thread.id, thread: result.thread });
    state?.controller.abort();
    const threadId = state?.threadId ?? state?.request.threadId;
    if (state && threadId) {
      this.emitUpdate({
        kind: 'runCancelled',
        clientRunId: state.clientRunId,
        runId: result.runId,
        threadId,
      });
    }
    return result;
  }

  async clearThread(threadId: string, expectedThreadRevision: number) {
    this.assertActive();
    await this.requireConsent();
    const hasCancelledRuns = this.cancelThreadRuns(threadId);
    const result = await this.requestThreadClear(threadId, expectedThreadRevision).catch((error: unknown) => {
      // A cancelled answer may have moved the revision after the caller read it, so the clear is sent once more
      const currentThread = hasCancelledRuns && error instanceof AgentV2HttpError
        && error.code === 'thread_revision_conflict' ? error.currentThread : undefined;
      if (currentThread?.id !== threadId) throw error;
      return this.requestThreadClear(threadId, currentThread.revision);
    });
    this.assertThreadBinding(threadId, result.thread.id);
    // The server revokes every run of the thread, including one admitted while the clear was pending
    this.cancelThreadRuns(threadId);
    this.invalidateThread(threadId);
    this.emitUpdate({ kind: 'threadChanged', threadId: result.thread.id, thread: result.thread });
    return result;
  }

  private requestThreadClear(threadId: string, expectedThreadRevision: number) {
    return this.getJson(
      `${this.dependencies.baseUrl}/threads/${encodeURIComponent(threadId)}/clear`,
      decodeAgentV2ThreadClear,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          protocolVersion: 3,
          expectedThreadRevision,
          clientOperationId: this.randomUuid(),
        }),
      },
    );
  }

  async reportProblem(threadId: string, { messageId, comment }: AgentV2ProblemReport) {
    this.assertActive();
    await this.requireConsent();
    const trimmedComment = comment !== undefined ? hideSecretPhrases(comment.trim()) : undefined;
    // The server may have stored a report whose answer was lost, so sending the same report again must not repeat it
    const key = [threadId, messageId ?? '', trimmedComment ?? ''].join('\n');
    const previous = this.unansweredProblemReport;
    const clientOperationId = previous?.key === key ? previous.clientOperationId : this.randomUuid();
    this.unansweredProblemReport = { key, clientOperationId };
    const result = await this.getJson(
      `${this.dependencies.baseUrl}/threads/${encodeURIComponent(threadId)}/reports`,
      decodeAgentV2ProblemReport,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          protocolVersion: 3,
          clientOperationId,
          ...(messageId ? { messageId } : {}),
          ...(trimmedComment ? { comment: trimmedComment } : {}),
        }),
      },
    ).catch((err: unknown) => {
      // A server that has switched reports off refuses them, so the next availability check asks it again
      this.probes.expireFeatureCapabilities();
      throw err;
    });
    // A report sent after this one may own the record by now
    if (this.unansweredProblemReport?.clientOperationId === clientOperationId) {
      this.unansweredProblemReport = undefined;
    }
    return result;
  }

  resolveAction(messageId: string, actionId: string): AgentV2ResolvedAction {
    this.assertActive();
    return this.actions.resolveAction(messageId, actionId);
  }

  getActionPresentation(messageId: string, actionId: string): AgentV2ActionPresentation {
    this.assertActive();
    return this.actions.getActionPresentation(messageId, actionId);
  }

  async destroy({
    shouldClearPersistentIdentity = false,
  }: { shouldClearPersistentIdentity?: boolean } = {}) {
    this.lifecycleController.abort();
    this.snapshots.reset();
    const pendingOperations: Promise<unknown>[] = [];
    pendingOperations.push(...this.backgroundTasks);
    if (this.consentWritePromise) pendingOperations.push(this.consentWritePromise);
    this.runs.forEach(({ controller }) => controller.abort());
    this.runs.clear();
    this.clearFailedRunRequests();
    this.actions.clear();
    this.toolExecutor.clear?.();
    this.probes.destroy();
    const identityDestroy = this.identity.destroy({
      shouldClearPersistentIdentity,
    });
    await Promise.allSettled(pendingOperations);
    await identityDestroy;
    if (shouldClearPersistentIdentity) {
      await this.walletSession.reset({ shouldClearPersistentState: true });
      await this.dependencies.storage.removeItem(AGENT_V2_CONSENT_STORAGE_KEY);
      this.consentPromise = Promise.resolve(false);
    } else {
      await this.walletSession.flushPersistence();
    }
  }

  private async followRun(state: RunState) {
    let attempt = 0;
    let lastProtocolFailureSequence: number | undefined;
    let protocolFailureCount = 0;
    while (!state.outcome && !state.controller.signal.aborted) {
      let endStream: ReturnType<AgentClientTrace['start']> | undefined;
      try {
        const response = await this.identity.authenticatedFetch(
          `${this.dependencies.baseUrl}/runs`,
          {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              ...(state.trace ? { 'x-agent-trace-id': state.trace.traceId } : {}),
            },
            body: JSON.stringify({
              ...state.request,
              ...(state.binding.lastSequence ? { resumeAfterSequence: state.binding.lastSequence } : {}),
            }),
            cache: 'no-store',
            signal: state.controller.signal,
          },
          { shouldSkipUnauthorizedRecovery: state.binding.lastSequence !== 0, trace: state.trace },
        );
        if (!response.ok) throw await decodeHttpError(response);
        if (!response.body || !response.headers.get('content-type')?.startsWith('application/x-ndjson')) {
          throw invalidStreamEvent();
        }
        logDebug('AgentV2 run stream', {
          stage: 'connected',
          clientRunId: state.clientRunId,
          lastSequence: state.binding.lastSequence,
        });
        endStream = state.trace?.start('client_stream');
        for await (const event of parseAgentV2Ndjson(response.body, state.binding)) {
          if (event.type !== 'text_delta') {
            logDebug('AgentV2 run stream', {
              stage: 'event_received',
              clientRunId: state.clientRunId,
              eventType: event.type,
              sequence: event.sequence,
            });
          }
          state.trace?.mark('client_event_received', { sequence: event.sequence, eventType: event.type });
          if (event.type === 'text_delta') state.trace?.markOnce('client_first_text');
          if (event.type === 'message_end') state.trace?.markOnce('client_terminal');
          await this.acceptEvent(event, state);
          if (event.type !== 'run_activity' || !event.ephemeral) {
            attempt = 0;
            lastProtocolFailureSequence = undefined;
            protocolFailureCount = 0;
          }
        }
        if (!state.outcome && !state.controller.signal.aborted) {
          throw new AgentV2StreamTransportError('Agent V2 stream ended before a terminal event');
        }
        endStream?.(state.controller.signal.aborted ? 'cancelled' : state.outcome === 'failed' ? 'error' : 'success');
      } catch (error) {
        endStream?.(state.controller.signal.aborted ? 'cancelled' : 'error');
        if (state.controller.signal.aborted || state.outcome) return;
        logDebugError(
          'AgentV2 run stream',
          {
            stage: 'read_failed',
            clientRunId: state.clientRunId,
            lastSequence: state.binding.lastSequence,
            attempt: attempt + 1,
          },
          error,
        );
        if (error instanceof AgentV2CompatibilityError) {
          logDebug('AgentV2 protocol compatibility', {
            boundary: error.boundary,
            discriminator: error.discriminator,
            version: error.version,
          });
          throw clientUpdateRequired();
        }
        const failure = classifyAgentV2Error(error);
        let isRetryableTransport = false;
        if (failure.kind === 'protocol') {
          if (!failure.retryable) throw invalidStreamEvent();
          if (lastProtocolFailureSequence === state.binding.lastSequence) {
            protocolFailureCount += 1;
          } else {
            lastProtocolFailureSequence = state.binding.lastSequence;
            protocolFailureCount = 1;
          }
          if (protocolFailureCount >= STREAM_PROTOCOL_NO_PROGRESS_MAX_ATTEMPTS) {
            throw invalidStreamEvent();
          }
          isRetryableTransport = true;
        } else if (error instanceof AgentV2HttpError) {
          if (!isRetryableAgentV2RunError(error)) throw error;
          isRetryableTransport = true;
        } else if (failure.kind === 'network') {
          isRetryableTransport = true;
        } else {
          throw new AgentV2HttpError(0, failure.code, 'Agent operation failed.', failure.retryable);
        }
        if (!isRetryableTransport) throw invalidStreamEvent();
        attempt += 1;
        if (state.binding.lastSequence === 0 && attempt >= PRE_ADMISSION_MAX_ATTEMPTS) throw error;
        const endWait = state.trace?.start('client_reconnect_wait');
        try {
          await this.wait(
            Math.min(
              RECONNECT_MAX_DELAY_MS,
              RETRY_BASE_DELAY_MS * 2 ** Math.min(attempt, RECONNECT_BACKOFF_EXPONENT_CAP),
            ),
            state.controller.signal,
          );
        } finally {
          endWait?.(state.controller.signal.aborted ? 'cancelled' : 'success');
        }
      }
    }
  }

  private async acceptEvent(event: AgentV2StreamItem, state: RunState) {
    if (!this.isRunCurrent(state) || state.controller.signal.aborted || state.outcome) return;
    if (event.type === 'run_start') {
      if (state.request.threadId && event.threadId !== state.request.threadId) {
        throw new AgentV2HttpError(
          0,
          'invalid_event',
          'Agent stream changed its chat binding.',
          false,
        );
      }
      state.threadId = event.threadId;
      if (state.request.input.kind !== 'append') this.invalidateThread(event.threadId);
    }
    const threadId = state.threadId ?? state.request.threadId;
    if (!threadId) throw new Error('Agent V2 stream event is missing a thread binding');
    const routing = { clientRunId: state.clientRunId, runId: event.runId, threadId };
    state.message.accept(event);

    switch (event.type) {
      case 'run_start': {
        const inputMessageId = getRunInputMessageId(state.request);
        this.emitUpdate({
          kind: 'runStarted',
          ...routing,
          threadRevision: event.threadRevision,
          ...(inputMessageId ? { inputMessageId } : {}),
        });
        void this.probes.refreshUserQuota();
        break;
      }
      case 'thread':
        this.assertThreadBinding(threadId, event.thread.id);
        this.emitUpdate({ kind: 'threadChanged', ...routing, thread: event.thread });
        break;
      case 'message_start':
        this.emitUpdate({
          kind: 'messageStarted',
          ...routing,
          messageId: event.messageId,
          contentKind: event.contentKind,
          ...(event.responseLanguage ? { responseLanguage: event.responseLanguage } : {}),
        });
        break;
      case 'table_data':
      case 'table_reference':
        this.emitUpdate({ kind: 'answerTablesChanged', ...routing, messageId: event.messageId,
          tables: state.message.tables, tableReferences: state.message.tableReferences });
        break;
      case 'text_link':
        if (state.message.links.at(-1) === event.link) {
          this.emitUpdate({ kind: 'answerLinkAdded', ...routing, messageId: event.messageId, link: event.link });
        }
        break;
      case 'text_delta':
        this.emitUpdate({
          kind: 'textDelta',
          ...routing,
          messageId: event.messageId,
          delta: event.delta,
        });
        break;
      case 'message_content_end':
        this.emitUpdate({
          kind: 'messageContentEnded',
          ...routing,
          messageId: event.messageId,
        });
        break;
      case 'tool_call':
        await this.executeTool(event.runId, state, event.toolCall);
        break;
      case 'unsupported_tool_call':
        await this.rejectUnsupportedTool(event.runId, state, event.toolCall);
        break;
      case 'tool_status': {
        const activity = state.toolActivityByCallId.get(event.toolCallId);
        if (!activity) break;
        this.emitToolActivity({
          ...routing,
          toolCallId: event.toolCallId,
          toolName: activity.name,
          ...(activity.operation ? { operation: activity.operation } : {}),
          status: event.status,
        });
        break;
      }
      case 'run_activity':
        this.emitUpdate({ kind: 'runActivityChanged', ...routing, event });
        break;
      case 'action':
      case 'semantic_content':
        break;
      case 'followups':
        this.emitUpdate({
          kind: 'followupsAvailable',
          ...routing,
          messageId: event.messageId,
          items: event.items,
        });
        break;
      case 'error': {
        state.outcome = 'failed';
        const resetAt = absoluteResetAt(event.resetAt, event.retryAfterMs, this.now());
        if (event.code === 'agent_capacity_exhausted') {
          this.probes.applyLocalCapacityFailure(resetAt);
        }
        this.emitUpdate({
          kind: 'runFailed',
          ...routing,
          code: event.code,
          retryable: event.retryable,
          ...(event.messageId
            ? { messageId: event.messageId }
            : state.message.id
              ? { messageId: state.message.id }
              : {}),
          ...(resetAt ? { resetAt } : {}),
        });
        break;
      }
      case 'message_end': {
        const finishReason = event.finishReason === 'complete'
          && state.binding.incompleteMessageIds?.has(event.messageId) ? 'error' : event.finishReason;
        state.outcome = terminalOutcome(finishReason);
        this.publishStructuredOutput(state, event.runId, threadId, event.messageId, event.finishReason);
        this.emitUpdate({
          kind: 'messageCompleted',
          ...routing,
          messageId: event.messageId,
          finishReason,
        });
        if (finishReason !== event.finishReason) {
          this.emitUpdate({ kind: 'runFailed', ...routing, messageId: event.messageId,
            code: 'invalid_event', retryable: false });
        }
        if (event.finishReason === 'cancelled') {
          this.emitUpdate({ kind: 'runCancelled', ...routing });
        }
        break;
      }
    }
  }

  private publishStructuredOutput(
    state: RunState,
    runId: string,
    threadId: string,
    messageId: string,
    finishReason: AgentMessageEndEvent['finishReason'],
  ) {
    const pending = state.message.finish(messageId, finishReason);
    if (!this.isRunCurrent(state) || state.controller.signal.aborted || !pending) return;

    const routing = { clientRunId: state.clientRunId, runId, threadId };
    if (pending.semanticContent) {
      this.emitUpdate({
        kind: 'semanticContentAvailable',
        ...routing,
        messageId,
        content: pending.semanticContent,
      });
    }
    // A run kept across a wallet selection change publishes its actions, which open for the current wallet
    const threadGeneration = this.threadGeneration;
    for (const action of pending.actions) {
      if (!this.isRunCurrent(state)
        || state.controller.signal.aborted
        || threadGeneration !== this.threadGeneration
      ) { return; }
      this.actions.registerAction(threadId, messageId, action);
      this.emitUpdate({
        kind: 'actionAvailable',
        ...routing,
        messageId,
        action,
      });
    }
  }

  private async executeTool(runId: string, state: RunState, call: AgentToolCall) {
    const threadId = state.threadId ?? state.request.threadId;
    if (!threadId) throw new Error('Agent V2 tool call is missing a thread binding');
    if (call.name === 'wallet.data.query' && call.scopeIntent
      && call.scopeIntent.messageId !== state.userMessageId) {
      throw invalidStreamEvent();
    }
    const operation = call.name === 'wallet.data.query'
      ? call.arguments.operation
      : undefined;
    const currentActivity = state.toolActivityByCallId.get(call.id);
    if (currentActivity && (currentActivity.name !== call.name || currentActivity.operation !== operation)) {
      throw invalidStreamEvent();
    }
    state.toolActivityByCallId.set(call.id, {
      name: call.name,
      ...(operation ? { operation } : {}),
    });
    state.pendingToolCallIds.add(call.id);
    logDebug('AgentV2 tool lifecycle', {
      stage: 'received',
      runId,
      toolCallId: call.id,
      toolName: call.name,
      timeoutMs: call.timeoutMs,
    });
    let result = state.pendingToolResults.get(call.id);
    if (!result) {
      const messageId = state.message.id
        ?? call.intentSource?.messageId
        ?? state.userMessageId;
      if (!messageId) throw invalidStreamEvent();
      this.emitToolActivity({
        clientRunId: state.clientRunId,
        runId,
        threadId,
        toolCallId: call.id,
        toolName: call.name,
        ...(operation ? { operation } : {}),
        status: 'running',
      });
      const endTool = state.trace?.start('client_tool', { toolName: call.name });
      try {
        result = await this.toolRunner.execute(
          call,
          {
            messageId,
            runId,
            threadId,
          },
          state.controller.signal,
        );
        endTool?.(result.status === 'error' ? 'error' : 'success');
      } catch (error) {
        endTool?.(state.controller.signal.aborted ? 'cancelled' : 'error');
        throw error;
      }
      if (!this.isRunCurrent(state) || state.controller.signal.aborted) return;
      logDebug('AgentV2 tool lifecycle', {
        stage: 'executed',
        runId,
        toolCallId: call.id,
        toolName: call.name,
        status: result.status,
      });
      state.pendingToolResults.set(call.id, result);
    }
    const submit = (value: AgentToolResultRequestV2) => this.submitToolResult(runId, state, call, value);
    try {
      await submit(result);
    } catch (error) {
      if (state.controller.signal.aborted || !this.isRunCurrent(state)
        || result.status !== 'success' || !(error instanceof AgentV2HttpError)
        || (error.status !== 413 && error.code !== 'tool_result_too_large')) throw error;
      this.discardToolResult(call.id);
      const { result: omittedResult, ...binding } = result;
      result = {
        ...binding,
        clientToolResultId: this.randomUuid(),
        status: 'error',
        error: { code: 'result_too_large', retryable: false },
      };
      state.pendingToolResults.set(call.id, result);
      await submit(result);
    }
    state.pendingToolResults.delete(call.id);
    state.pendingToolCallIds.delete(call.id);
  }

  private async rejectUnsupportedTool(
    runId: string,
    state: RunState,
    call: AgentV2UnsupportedToolCall['toolCall'],
  ) {
    const threadId = state.threadId ?? state.request.threadId;
    if (!threadId) throw new Error('Agent V2 tool call is missing a thread binding');
    logDebug('AgentV2 tool lifecycle', { stage: 'unsupported', runId, toolCallId: call.id, toolName: call.name });
    state.pendingToolCallIds.add(call.id);
    const result = state.pendingToolResults.get(call.id) ?? {
      protocolVersion: 3,
      runId,
      threadId,
      toolCallId: call.id,
      clientToolResultId: this.randomUuid(),
      toolName: call.name,
      status: 'rejected',
      completedAt: new Date(this.now()).toISOString(),
      error: { code: 'tool_unsupported', retryable: false },
    } satisfies AgentToolResultRequestV2;
    state.pendingToolResults.set(call.id, result);
    await this.submitToolResult(runId, state, call, result);
    state.pendingToolResults.delete(call.id);
    state.pendingToolCallIds.delete(call.id);
  }

  private submitToolResult(
    runId: string,
    state: RunState,
    call: { id: string; name: string },
    result: AgentToolResultRequestV2,
  ) {
    const send = (child?: AgentClientTrace) => this.toolRunner.submit(
      runId, call, result, state.controller.signal, () => this.isRunCurrent(state), child,
    );
    return state.trace ? state.trace.observe('client_tool_submission', send) : send();
  }

  private emitToolActivity(update: Omit<
    Extract<AgentV2ClientUpdate, { kind: 'toolActivityChanged' }>,
    'kind'
  >) {
    try {
      this.emitUpdate({ kind: 'toolActivityChanged', ...update });
    } catch (error) {
      // Tool progress is presentational and must not interrupt the tool-result protocol.
      logDebugError('AgentV2 tool progress update', {
        runId: update.runId,
        toolCallId: update.toolCallId,
        toolName: update.toolName,
        status: update.status,
      }, error);
    }
  }

  private discardToolResult(toolCallId: string) {
    this.toolExecutor.discard?.(toolCallId);
  }

  private async getJson<T>(
    url: string,
    decoder: (value: unknown) => T,
    init: RequestInit = {},
    {
      trace,
      shouldSkipUnauthorizedRecovery = false,
      timeoutMs = this.requestTimeoutMs,
    }: { trace?: AgentClientTrace; shouldSkipUnauthorizedRecovery?: boolean; timeoutMs?: number } = {},
  ): Promise<T> {
    this.assertActive();
    const { signal, cleanup } = mergeAbortSignalsWithTimeout(
      timeoutMs,
      init.signal ?? this.lifecycleController.signal,
    );
    try {
      const response = await this.identity.authenticatedFetch(
        url,
        {
          ...init,
          cache: 'no-store',
          signal,
        },
        { trace, shouldSkipUnauthorizedRecovery },
      );
      this.assertActive();
      try {
        if (!response.ok) throw await decodeHttpError(response);
        const result = decoder(await response.json());
        this.assertActive();
        return result;
      } catch (error) {
        const failure = classifyAgentV2Error(error);
        logDebug('AgentV2 HTTP decoding', { operation: decoder.name, category: failure.kind,
          ...(error instanceof AgentV2ContractError ? { boundary: error.path } : {}),
          ...(error instanceof AgentV2CompatibilityError
            ? { boundary: error.boundary, format: error.discriminator, version: error.version }
            : {}),
        });
        throw error;
      }
    } finally {
      cleanup();
    }
  }

  private retainFailedRunRequest(
    request: AgentRunRequestWireV2,
    expiresAt: number,
    userMessageId: string | undefined,
  ) {
    this.clearFailedRunRequests();
    const failedRunRequest = { request, expiresAt, ...(userMessageId ? { userMessageId } : {}) };
    this.failedRunRequest = failedRunRequest;
    this.failedRunRequestTimer = setTimeout(() => {
      this.failedRunRequestTimer = undefined;
      if (this.failedRunRequest === failedRunRequest) this.failedRunRequest = undefined;
    }, Math.max(0, expiresAt - this.now()));
  }

  private clearFailedRunRequests() {
    if (this.failedRunRequestTimer !== undefined) clearTimeout(this.failedRunRequestTimer);
    this.failedRunRequestTimer = undefined;
    this.failedRunRequest = undefined;
  }

  private now() {
    return this.dependencies.now?.() ?? Date.now();
  }

  private emitUpdate(update: AgentV2ClientUpdate) {
    if (this.lifecycleController.signal.aborted) return;
    const trace = update.clientRunId ? this.runs.get(update.clientRunId)?.trace : undefined;
    if (trace) {
      trace.markOnce('client_update_dispatched');
      this.dependencies.onUpdate({ ...update, developmentTraceId: trace.traceId });
    } else this.dependencies.onUpdate(update);
  }

  private assertActive() {
    if (this.lifecycleController.signal.aborted) throw new Error('Agent V2 runtime is destroyed');
  }

  private async requireConsent() {
    this.assertActive();
    if (!await this.getConsent()) throw new Error('Agent V2 consent is required');
    this.assertActive();
  }

  private async readConsent() {
    const stored = await this.dependencies.storage.getItem(AGENT_V2_CONSENT_STORAGE_KEY);
    this.assertActive();
    try {
      const record = typeof stored === 'string'
        ? JSON.parse(stored) as { version?: unknown; accepted?: unknown }
        : stored;
      return record?.version === 2 && record.accepted === true;
    } catch {
      return false;
    }
  }

  private cancelAllLocally() {
    const states = [...this.runs.values()];
    const runIds = states
      .flatMap(({ binding }) => binding.runId ? [binding.runId] : []);
    states.forEach((state) => this.cancelRunLocally(state));
    return runIds;
  }

  // Returns whether a run that may have reached the server was stopped
  private cancelThreadRuns(threadId: string) {
    this.clearGenerationByThreadId.set(threadId, this.getClearGeneration(threadId) + 1);
    const states = [...this.runs.values()].filter((state) => (
      !state.outcome && (state.threadId ?? state.request.threadId) === threadId
    ));
    states.forEach((state) => {
      this.cancelRunLocally(state);
      if (state.binding.runId) {
        this.emitUpdate({ kind: 'runCancelled', clientRunId: state.clientRunId, runId: state.binding.runId, threadId });
      }
    });
    return states.length > 0;
  }

  private cancelRunLocally(state: RunState) {
    state.outcome = 'cancelled';
    state.controller.abort();
    state.pendingToolCallIds.forEach((toolCallId) => this.discardToolResult(toolCallId));
    state.pendingToolCallIds.clear();
    state.pendingToolResults.clear();
  }

  private getClearGeneration(threadId?: string) {
    return threadId ? this.clearGenerationByThreadId.get(threadId) ?? 0 : 0;
  }

  private scheduleRemoteCancellation(runId: string) {
    this.trackBackgroundTask(this.cancelRunRemotely(runId).catch((error) => {
      if (this.lifecycleController.signal.aborted) return;
      logDebugError('AgentV2 run cancellation', { runId, stage: 'authority_change' }, error);
    }));
  }

  private async cancelRunRemotely(runId: string) {
    const result = await this.requestRunCancel(runId, REMOTE_CANCEL_TIMEOUT_MS);
    this.assertRunBinding(runId, result.runId);
    this.emitUpdate({ kind: 'threadChanged', threadId: result.thread.id, thread: result.thread });
  }

  private requestRunCancel(runId: string, timeoutMs?: number) {
    return this.getJson(`${this.dependencies.baseUrl}/runs/${runId}/cancel`, decodeAgentV2RunCancel, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ protocolVersion: 3, clientOperationId: this.randomUuid() }),
    }, { shouldSkipUnauthorizedRecovery: true, timeoutMs });
  }

  private trackBackgroundTask(task: Promise<void>) {
    this.backgroundTasks.add(task);
    void task.then(
      () => this.backgroundTasks.delete(task),
      () => this.backgroundTasks.delete(task),
    );
  }

  private isRunCurrent(state: RunState) {
    return !this.lifecycleController.signal.aborted && state.runGeneration === this.runGeneration;
  }

  private isAuthorityGenerationCurrent(authorityGeneration: number) {
    return !this.lifecycleController.signal.aborted && authorityGeneration === this.authorityGeneration;
  }

  private assertAuthorityGeneration(authorityGeneration: number) {
    if (authorityGeneration === this.authorityGeneration) return;
    throw new AgentV2HttpError(
      0,
      'wallet_context_changed',
      'The active wallet changed.',
      false,
    );
  }

  private isWalletContextGenerationCurrent(walletContextGeneration: number) {
    return !this.lifecycleController.signal.aborted
      && walletContextGeneration === this.walletContextGeneration;
  }

  private assertWalletContextGeneration(walletContextGeneration: number) {
    if (this.isWalletContextGenerationCurrent(walletContextGeneration)) return;
    throw new AgentV2HttpError(
      0,
      'wallet_context_changed',
      'The wallet context changed.',
      false,
    );
  }

  private invalidateThread(threadId: string) {
    this.threadGeneration += 1;
    const failedRunRequest = this.failedRunRequest;
    if (failedRunRequest?.request.threadId === threadId) this.clearFailedRunRequests();
    this.actions.clear(threadId);
    this.toolExecutor.clear?.(threadId);
    this.emitUpdate({ kind: 'walletAuthorityChanged', threadId });
  }

  private assertThreadBinding(expectedThreadId: string, actualThreadId: string) {
    if (actualThreadId !== expectedThreadId) {
      throw new AgentV2HttpError(
        0,
        'invalid_event',
        'Agent response changed its chat binding.',
        false,
      );
    }
  }

  private assertRunBinding(expectedRunId: string, actualRunId: string) {
    if (actualRunId !== expectedRunId) {
      throw new AgentV2HttpError(
        0,
        'invalid_event',
        'Agent response changed its run binding.',
        false,
      );
    }
  }

  private emitFailure(error: unknown, state: RunState) {
    if (!this.isRunCurrent(state)) return;
    const classification = classifyAgentV2Error(error);
    const safe = error instanceof AgentV2HttpError
      ? error
      : new AgentV2HttpError(0, classification.code, 'Agent operation failed.', classification.retryable);
    const resetAt = absoluteResetAt(safe.resetAt, safe.retryAfterMs, this.now());
    const failure = {
      kind: 'runFailed',
      clientRunId: state.clientRunId,
      code: safe.code,
      retryable: safe.retryable,
      ...(state.message.id ? { messageId: state.message.id } : {}),
      ...(resetAt ? { resetAt } : {}),
    } as const;
    if (safe.code === 'agent_capacity_exhausted') {
      this.probes.applyLocalCapacityFailure(resetAt);
    }
    if (safe.code === 'user_quota_exhausted' && safe.quota) {
      this.probes.applyUserQuota({ protocolVersion: 3, quota: safe.quota });
    }
    const threadId = state.threadId ?? state.request.threadId;

    if (state.binding.runId && threadId) {
      this.emitUpdate({ ...failure, runId: state.binding.runId, threadId });
    } else {
      this.emitUpdate({ ...failure, ...(threadId ? { threadId } : {}) });
    }
  }
}

class UnsupportedToolExecutor implements AgentV2ToolExecutor {
  constructor(private readonly randomUuid: () => string) {}

  execute(toolCall: AgentToolCall, context: AgentV2ToolExecutionContext): Promise<AgentToolResultRequestV2> {
    return Promise.resolve({
      protocolVersion: 3,
      runId: context.runId,
      threadId: context.threadId,
      toolCallId: toolCall.id,
      clientToolResultId: this.randomUuid(),
      completedAt: new Date().toISOString(),
      ...toolResultSessionBinding(toolCall),
      status: 'rejected',
      error: {
        code: 'tool_unsupported',
        retryable: false,
      },
    });
  }

  discard() {}
}

// A recovery phrase never leaves the device, whichever app sent the text
function hideSecretPhrases(text: string) {
  return removeSecretPhrases(text, getSecretPhraseWordList(), DEFAULT_SECRET_PHRASE_PLACEHOLDER);
}

function toolResultSessionBinding(call: AgentToolCall) {
  return call.name === 'wallet.directory.query'
    ? { toolName: call.name, directorySession: call.directorySession }
    : { toolName: call.name, walletContextSession: call.walletContextSession };
}

function terminalOutcome(finishReason: AgentV2FinishReason) {
  if (finishReason === 'cancelled') return 'cancelled' as const;
  if (finishReason === 'run_interrupted') return 'interrupted' as const;
  if (finishReason === 'error') return 'failed' as const;
  return 'completed' as const;
}

function getRunInputMessageId(request: AgentRunRequestWireV2) {
  return request.input.kind === 'regenerate' ? undefined : request.input.message.id;
}

function invalidStreamEvent() {
  return new AgentV2HttpError(
    0,
    'invalid_event',
    'Agent stream returned an invalid event.',
    false,
  );
}

function clientUpdateRequired() {
  return new AgentV2HttpError(
    0,
    'client_update_required',
    'Update the app to continue.',
    false,
  );
}

function absoluteResetAt(resetAt: string | undefined, retryAfterMs: number | undefined, now: number) {
  if (resetAt) {
    const timestamp = Date.parse(resetAt);
    if (Number.isFinite(timestamp)) return timestamp;
  }
  return retryAfterMs ? now + retryAfterMs : undefined;
}

function failedRunRequestExpiresAt(error: unknown, now: number) {
  if (error instanceof AgentV2HttpError) {
    const isLimitFailure = error.code === 'rate_limited' || error.code === 'user_quota_exhausted';
    if (!isLimitFailure && !isRetryableAgentV2RunError(error)) return undefined;
    const resetAt = absoluteResetAt(error.resetAt, error.retryAfterMs, now) ?? now;
    return Math.min(resetAt + FAILED_RUN_RETRY_GRACE_MS, now + FAILED_RUN_RETRY_MAX_TTL_MS);
  }
  if (classifyAgentV2Error(error).kind === 'network') {
    return now + FAILED_RUN_RETRY_GRACE_MS;
  }
  return undefined;
}

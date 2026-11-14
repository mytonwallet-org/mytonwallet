import type { Storage } from '../storages/types';
import type {
  AgentAnswerFeedbackV2,
  AgentMessageEndEvent,
  AgentRunCancelResponseV2,
  AgentRunRequestWireV2,
  AgentThreadCreateRequestV2,
  AgentThreadListRequestV2,
  AgentThreadListResponseV2,
  AgentThreadSummaryV2,
  AgentToolCall,
  AgentToolResultRequestV2,
  AgentV2FinishReason,
  AgentWalletSemanticOperationV2,
} from './protocol/types';
import type {
  AgentV2ActionPresentation,
  AgentV2ClientUpdate,
  AgentV2Hints,
  AgentV2HintWalletState,
  AgentV2HostContextSnapshot,
  AgentV2NewsFeedRequest,
  AgentV2ProblemReport,
  AgentV2ResolvedAction,
  AgentV2RunCommand,
  AgentV2RunResult,
  AgentV2StarterHints,
  AgentV2ThreadHydration,
  AgentV2ThreadUpdate,
  AgentV2Transcription,
} from './types';

import { APP_ENV } from '../../config';
import {
  mergeAbortSignalsWithTimeout,
  pauseWithAbortSignal,
  raceWithAbortSignal,
  throwIfAborted,
} from '../../util/abortSignal';
import { getAgentNewsFeedLocale } from '../../util/agent/agentNewsFeedLocale';
import { logDebug, logDebugError } from '../../util/logs';
import { decodeAgentV2WalletSnapshotAck } from './protocol/decoders/coreRun';
import { uuid } from './protocol/decoders/readers';
import {
  AgentV2CompatibilityError,
  AgentV2ContractError,
  decodeAgentV2AnswerFeedback,
  decodeAgentV2DefaultThread,
  decodeAgentV2Messages,
  decodeAgentV2NewsFeed,
  decodeAgentV2ProblemReport,
  decodeAgentV2RunCancel,
  decodeAgentV2ThreadClear,
  decodeAgentV2ThreadCreate,
  decodeAgentV2ThreadDelete,
  decodeAgentV2ThreadList,
  decodeAgentV2ThreadUpdate,
  decodeAgentV2Transcription,
} from './protocol/transportContracts';
import { getAgentV2ActionAvailability } from './actionAvailability';
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
import { selectAgentV2StarterHints } from './starterHints';
import { AgentV2StreamMessage } from './streamMessage';
import {
  beginThreadListCacheRequest,
  beginThreadMessagesCacheRequest,
  cacheMessages,
  cacheThreads,
  clearThreadCache,
  deleteCachedMessages,
  deleteCachedThread,
  getCachedMessages,
  getCachedThreads,
  THREAD_CACHE_MESSAGE_LIMIT,
  updateCachedThread,
} from './threadCache';
import { getIsAgentV2ThreadStarted } from './threadStarted';
import { type AgentV2ToolExecutionContext, type AgentV2ToolExecutor, AgentV2ToolRunner } from './toolRunner';
import { isWalletSelectionChange } from './walletAuthority';
import { AgentV2WalletSession, readAgentV2HostContext } from './walletSession';
import { AgentV2WalletSnapshotSync } from './walletSnapshotSync';

export type { AgentV2ToolExecutionContext, AgentV2ToolExecutor } from './toolRunner';

export const AGENT_V2_CONSENT_STORAGE_KEY = 'agentV2Consent';
const RECONNECT_MAX_DELAY_MS = 2_000;
const RETRY_BASE_DELAY_MS = 250;
const RECONNECT_BACKOFF_EXPONENT_CAP = 3;
const PRE_ADMISSION_MAX_ATTEMPTS = 3;
const STREAM_PROTOCOL_NO_PROGRESS_MAX_ATTEMPTS = 3;
const REMOTE_CANCEL_TIMEOUT_MS = 3_000;
// The server allows a transcription up to 100 s, but a minute of waiting for one phrase is already too long
const TRANSCRIPTION_TIMEOUT_MS = 60_000;
const UTC_DAY_MS = 24 * 60 * 60_000;
const FAILED_RUN_RETRY_GRACE_MS = 5 * 60_000;
const FAILED_RUN_RETRY_MAX_TTL_MS = UTC_DAY_MS;
// How many pages past the first the chat list reads to make up for the untouched news discussions it leaves out
const MAX_SKIPPED_THREAD_PAGES = 10;
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
  /** Set by `stopRun`. A stopped run the server has not named yet reads its stream on only for the id to cancel it. */
  isStopped?: boolean;
  /** Ends `executeRun` with the cancelled result once the run is stopped */
  resolveStop: () => void;
  /** Settles once the run stops reading its stream */
  completion?: Promise<AgentV2RunResult>;
  /** The revision a stopped answer moved the thread to, which a revision conflict sends the run once more with */
  revisionAfterStop?: number;
}

/** A run before it reaches the server, which `stopRun` ends at once */
interface RunPreparation {
  threadId?: string;
  clientRunId?: string;
  controller: AbortController;
  /** The server cancellation of a stopped answer that the run waited for */
  stopCancellation?: Promise<AgentThreadSummaryV2 | undefined>;
}

interface FailedRunRequest {
  expiresAt: number;
  request: AgentRunRequestWireV2;
  userMessageId?: string;
  timer: ReturnType<typeof setTimeout>;
  /** The account active when the run was asked, the only one it goes again for */
  accountId?: string;
  /** The wallet context the request was built with, which a retry builds afresh once it has changed */
  walletContextGeneration: number;
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
  private readonly unansweredProblemReportByThreadId = new Map<string, { key: string; clientOperationId: string }>();
  private readonly unansweredThreadDeletionByThreadId = new Map<string, string>();
  private readonly wait: (milliseconds: number, signal: AbortSignal) => Promise<void>;
  private readonly requestTimeoutMs: number;
  private readonly lifecycleController = new AbortController();
  private readonly runs = new Map<string, RunState>();
  private readonly runPreparations = new Set<RunPreparation>();
  // The server cancellation of each thread's stopped answers, which the thread's next run waits for
  private readonly stopCancellationByThreadId = new Map<string, Promise<AgentThreadSummaryV2 | undefined>>();
  private readonly actions: AgentV2ActionResolver;
  private readonly backgroundTasks = new Set<Promise<void>>();
  private readonly clearGenerationByThreadId = new Map<string, number>();
  private readonly threadGenerationByThreadId = new Map<string, number>();
  private readonly failedRunRequestByThreadId = new Map<string | undefined, FailedRunRequest>();
  // The latest rating request of each answer; the next one waits for it, so the server keeps the last rating made
  private readonly feedbackRequestByMessageId = new Map<string, Promise<unknown>>();

  private authorityGeneration = 0;
  private runGeneration = 0;
  private walletContextGeneration = 0;
  private consentPromise?: Promise<boolean>;
  private toolExecutor: AgentV2ToolExecutor;
  private consentWritePromise?: Promise<boolean>;

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

  /**
   * Reads the consent once it is given and keeps it from then on. A refusal or a failed read is read again next time,
   * so consent given elsewhere, as in another tab, shows.
   */
  getConsent(): Promise<boolean> {
    this.assertActive();
    if (this.consentPromise) return this.consentPromise;

    const read = this.readConsent();
    this.consentPromise = read;
    // A read that ends after `acceptConsent` leaves the consent it stored
    const forgetRead = () => {
      if (this.consentPromise === read) this.consentPromise = undefined;
    };
    read.then((isAccepted) => {
      if (!isAccepted) forgetRead();
    }, forgetRead);
    return read;
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
    // A chat shown before consent, as a news discussion is, starts syncing the wallet once the user allows the Agent
    if (this.isChatActive) this.snapshots.setActive(true);
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
    const nextHost = this.walletSession.snapshot().host;
    if (hasWalletContextChanged) {
      this.walletContextGeneration += 1;
    }
    // A run a limit held goes again only for the account it was asked for: once another account is active, it is
    // dropped for good, even if the first comes back. The same account published again keeps it.
    if (previousHost?.activeAccountId !== nextHost?.activeAccountId) this.clearFailedRunRequests();
    if (hasAuthorityChanged) {
      this.authorityGeneration += 1;
      const isSelectionChange = isWalletSelectionChange(previousHost, nextHost);
      if (!isSelectionChange) this.runGeneration += 1;
      const runIds = isSelectionChange ? [] : this.cancelAllLocally();
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

  async getStarterHints(
    walletState?: AgentV2HintWalletState | null,
    host?: AgentV2HostContextSnapshot | null,
  ): Promise<AgentV2StarterHints> {
    this.assertActive();
    // The actions belong to the account whose `walletState` the host passed. A native host publishes its context
    // only while a chat is open, so it passes the context with the call, which leaves the published one as it is.
    // `null`, which a native bridge sends, says the host has no context now: the one a chat published earlier may
    // describe another account.
    const passedHost = host ? readAgentV2HostContext(host) : undefined;
    const { walletSupportedActions } = getAgentV2ActionAvailability(
      host === undefined ? this.walletSession.snapshot().host : passedHost,
    );
    const { catalogVersion, items } = await this.probes.getHintPool();
    this.assertActive();
    return {
      catalogVersion,
      items: selectAgentV2StarterHints(items, walletSupportedActions, walletState ?? undefined),
    };
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

  /**
   * The user's chats, without the news discussions they have not written in. A page that holds none of those comes
   * back as the server gave it. Otherwise the chats of the following pages join the page's until there are `limit` of
   * them, or without a `limit` at least one, until the list ends or after `MAX_SKIPPED_THREAD_PAGES` more pages, with
   * the cursor of the last page read. Whole pages join, so the chats can be more than `limit`, none lost or repeated.
   */
  async listThreads({ cursor, limit, query }: AgentThreadListRequestV2 = {}) {
    this.assertActive();
    const cacheGeneration = !cursor && !query ? beginThreadListCacheRequest() : undefined;
    await this.requireConsent();
    let pageCursor = cursor;
    let result: AgentThreadListResponseV2;
    const threads: AgentThreadListResponseV2['threads'] = [];
    for (let skippedPages = 0; ; skippedPages++) {
      const params = new URLSearchParams();
      if (pageCursor) params.set('cursor', pageCursor);
      if (limit !== undefined) params.set('limit', String(limit));
      const trimmedQuery = query?.trim();
      if (trimmedQuery) params.set('query', trimmedQuery);
      const search = params.toString();
      const page = await this.getJson(
        `${this.dependencies.baseUrl}/threads${search ? `?${search}` : ''}`,
        decodeAgentV2ThreadList,
      );
      const startedThreads = page.threads.filter(({ thread }) => getIsAgentV2ThreadStarted(thread));
      if (!skippedPages && startedThreads.length === page.threads.length) {
        result = page;
        break;
      }
      threads.push(...startedThreads);
      const isFilled = limit === undefined ? threads.length > 0 : threads.length >= limit;
      if (isFilled || !page.nextCursor || skippedPages >= MAX_SKIPPED_THREAD_PAGES) {
        result = { ...page, threads };
        break;
      }
      pageCursor = page.nextCursor;
    }
    if (cacheGeneration !== undefined) {
      void this.accessThreadCache((deviceId) => cacheThreads(deviceId, result.threads, cacheGeneration));
    }
    return result;
  }

  getCachedThreads() {
    return this.accessThreadCache(async (deviceId) => {
      const cached = await getCachedThreads(deviceId);
      if (!cached || !await this.getConsent()) return undefined;

      return cached;
    });
  }

  getCachedMessages(threadId: string) {
    return this.accessThreadCache(async (deviceId) => {
      const cached = await getCachedMessages(deviceId, threadId);
      if (!cached || (!cached.thread.news && !cached.thread.digest && !await this.getConsent())) return undefined;

      // A stored copy may give operator photos by their path on the agent origin
      return {
        ...cached,
        messages: cached.messages.map((message) => resolveOperatorAvatarUrl(message, this.dependencies.baseUrl)),
      };
    });
  }

  /**
   * The news feed is readable before the user allows the Agent, as are a news or digest discussion's thread and its
   * messages: their requests carry only the device's token, the feed's locale and digest time, the news or digest
   * reference or the thread's id, nothing about the wallet or the user's messages. The messages of any other thread
   * need the consent.
   */
  async getNewsFeed({
    lang, view, cursor, digestHour, digestMinute, timeZone,
  }: AgentV2NewsFeedRequest) {
    this.assertActive();
    const params = new URLSearchParams({ locale: getAgentNewsFeedLocale(lang) });
    if (cursor) params.set('cursor', cursor);
    if (digestHour !== undefined && timeZone !== undefined) {
      params.set('digestHour', String(digestHour));
      if (digestMinute) params.set('digestMinute', String(digestMinute));
      params.set('timeZone', timeZone);
    }
    if (view === 'digests') params.set('view', view);
    const { locale, items, nextCursor, digests } = await this.getJson(
      `${this.dependencies.baseUrl}/news-feed?${params}`,
      decodeAgentV2NewsFeed,
    );
    return {
      locale,
      items,
      ...(nextCursor !== undefined && { nextCursor }),
      ...(digests !== undefined && { digests }),
    };
  }

  // A news or digest discussion opens with its post and suggestions before consent; any other chat needs it
  async createThread({ news, digest }: Omit<AgentThreadCreateRequestV2, 'protocolVersion'> = {}) {
    this.assertActive();
    if (news === undefined && digest === undefined) await this.requireConsent();
    return this.getJson(`${this.dependencies.baseUrl}/threads`, decodeAgentV2ThreadCreate, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        protocolVersion: 3,
        ...(news !== undefined && { news }),
        ...(digest !== undefined && { digest: { id: digest.id } }),
      }),
    });
  }

  async updateThread(threadId: string, { title, isPinned }: AgentV2ThreadUpdate) {
    this.assertActive();
    await this.requireConsent();
    const threadGeneration = this.getThreadGeneration(threadId);
    const result = await this.getJson(
      `${this.dependencies.baseUrl}/threads/${encodeURIComponent(threadId)}/update`,
      decodeAgentV2ThreadUpdate,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ protocolVersion: 3, title, isPinned }),
      },
    );
    this.assertThreadBinding(threadId, result.thread.id);
    if (threadGeneration === this.getThreadGeneration(threadId)) {
      this.emitUpdate({ kind: 'threadChanged', threadId, thread: result.thread });
    }
    return result;
  }

  async deleteThread(threadId: string) {
    this.assertActive();
    await this.requireConsent();
    const clientOperationId = this.unansweredThreadDeletionByThreadId.get(threadId) ?? this.randomUuid();
    this.unansweredThreadDeletionByThreadId.set(threadId, clientOperationId);
    const result = await this.getJson(
      `${this.dependencies.baseUrl}/threads/${encodeURIComponent(threadId)}/delete`,
      decodeAgentV2ThreadDelete,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ protocolVersion: 3, clientOperationId }),
      },
    ).catch((error: unknown) => {
      const hasReceivedResponse = (error instanceof AgentV2HttpError && error.status > 0)
        || error instanceof AgentV2ContractError
        || error instanceof AgentV2CompatibilityError
        || error instanceof SyntaxError;
      if (hasReceivedResponse && this.unansweredThreadDeletionByThreadId.get(threadId) === clientOperationId) {
        this.unansweredThreadDeletionByThreadId.delete(threadId);
      }
      throw error;
    });
    if (this.unansweredThreadDeletionByThreadId.get(threadId) === clientOperationId) {
      this.unansweredThreadDeletionByThreadId.delete(threadId);
    }
    this.assertThreadBinding(threadId, result.threadId);
    this.cancelThreadRuns(threadId);
    this.unansweredProblemReportByThreadId.delete(threadId);
    this.invalidateThread(threadId);
    void this.accessThreadCache((deviceId) => deleteCachedThread(deviceId, threadId));
    return result;
  }

  async getMessages(threadId: string, cursorValue?: string, limit = 100): Promise<AgentV2ThreadHydration> {
    this.assertActive();
    const cacheGeneration = !cursorValue && limit >= THREAD_CACHE_MESSAGE_LIMIT
      ? beginThreadMessagesCacheRequest(threadId) : undefined;
    const authorityGeneration = this.authorityGeneration;
    const walletContextGeneration = this.walletContextGeneration;
    const threadGeneration = this.getThreadGeneration(threadId);
    const params = new URLSearchParams({ limit: String(limit) });
    if (cursorValue) params.set('cursor', cursorValue);
    const page = await this.getJson(
      `${this.dependencies.baseUrl}/threads/${encodeURIComponent(threadId)}/messages?${params}`,
      decodeAgentV2Messages,
    ).catch((error: unknown) => {
      if (error instanceof AgentV2HttpError && error.code === 'thread_not_found') {
        void this.accessThreadCache((deviceId) => deleteCachedThread(deviceId, threadId, cacheGeneration));
      }
      throw error;
    });
    this.assertAuthorityGeneration(authorityGeneration);
    this.assertWalletContextGeneration(walletContextGeneration);
    this.assertThreadBinding(threadId, page.thread.id);
    page.messages.forEach((message) => this.assertThreadBinding(threadId, message.threadId));
    if (!page.thread.news && !page.thread.digest) await this.requireConsent();
    const persistedMessages = page.messages.map((message) => (
      resolveOperatorAvatarUrl(message, this.dependencies.baseUrl)
    ));
    if (threadGeneration !== this.getThreadGeneration(threadId)) throw invalidStreamEvent();
    this.assertAuthorityGeneration(authorityGeneration);
    this.assertWalletContextGeneration(walletContextGeneration);
    for (const message of persistedMessages) {
      for (const action of message.actions ?? []) {
        this.actions.registerPersistedAction(threadId, message.id, action);
      }
    }
    if (cacheGeneration !== undefined && !page.thread.news && !page.thread.digest) {
      void this.accessThreadCache((deviceId) => cacheMessages(
        deviceId, threadId, { ...page, messages: persistedMessages }, cacheGeneration,
      ));
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
    if (command.clientRunId !== undefined) this.assertNewClientRunId(command.clientRunId);
    const prepared = trace?.start('client_preparation');
    const preparation = this.startRunPreparation(command.threadId, command.clientRunId);
    let clientRunId = command.clientRunId;
    let messageId: string | undefined;
    try {
      this.assertActive();
      const origin = buildAgentV2RunOrigin(command);
      const clearGeneration = this.getClearGeneration(command.threadId);
      await raceWithAbortSignal(this.requireConsent(), preparation.controller.signal);
      if (command.threadId && command.input.kind !== 'append') this.invalidateThread(command.threadId);
      clientRunId ??= this.randomUuid();
      preparation.clientRunId = clientRunId;
      messageId = command.input.kind === 'regenerate' ? undefined : this.randomUuid();
      await raceWithAbortSignal(
        this.probes.ensureFeatureCapabilities(prepared?.trace),
        preparation.controller.signal,
      );
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
      const stoppedThread = await this.waitForStopCancellation(preparation, command.threadId);
      await raceWithAbortSignal(this.requireConsent(), preparation.controller.signal);
      if (runGeneration !== this.runGeneration) this.assertAuthorityGeneration(authorityGeneration);
      // A clear of the thread cancels a run it finds still being prepared, before the run reaches the server
      if (clearGeneration !== this.getClearGeneration(command.threadId)) {
        prepared?.('cancelled');
        return buildCancelledRunResult(clientRunId, messageId);
      }
      this.finishRunPreparation(preparation);
      prepared?.();
      const userMessageId = command.input.kind === 'regenerate' ? command.input.userMessageId : messageId;
      return this.executeRun(request, authorityGeneration, trace, userMessageId, stoppedThread);
    } catch (error) {
      if (preparation.controller.signal.aborted) {
        prepared?.('cancelled');
        return buildCancelledRunResult(clientRunId ?? this.randomUuid(), messageId);
      }
      prepared?.('error');
      throw error;
    } finally {
      this.runPreparations.delete(preparation);
    }
  }

  async retryRun(clientRunId: string): Promise<AgentV2RunResult | undefined> {
    this.assertActive();
    const preparation = this.startRunPreparation(
      this.findFailedRunRequest(clientRunId)?.request.threadId, clientRunId,
    );
    let end: ReturnType<AgentClientTrace['start']> | undefined;
    let inputMessageId: string | undefined;
    try {
      await raceWithAbortSignal(this.requireConsent(), preparation.controller.signal);
      const authorityGeneration = this.authorityGeneration;
      const failed = this.findFailedRunRequest(clientRunId);
      if (!failed) return undefined;
      const threadId = failed.request.threadId;
      const clearGeneration = this.getClearGeneration(threadId);
      inputMessageId = getRunInputMessageId(failed.request);
      this.clearFailedRunRequest(threadId);
      if (failed.expiresAt <= this.now() || failed.accountId !== this.getActiveAccountId()) return undefined;
      const trace = this.timingSink ? new AgentClientTrace(newClientTraceId(), this.timingSink) : undefined;
      end = trace?.start('client_request');
      await raceWithAbortSignal(this.probes.ensureFeatureCapabilities(trace), preparation.controller.signal);
      this.assertAuthorityGeneration(authorityGeneration);
      const stoppedThread = await this.waitForStopCancellation(preparation, threadId);
      await raceWithAbortSignal(this.requireConsent(), preparation.controller.signal);
      this.assertAuthorityGeneration(authorityGeneration);
      if (clearGeneration !== this.getClearGeneration(threadId)) {
        end?.('cancelled');
        return buildCancelledRunResult(clientRunId, inputMessageId);
      }
      this.finishRunPreparation(preparation);
      const result = await this.executeRun(
        this.rebindFailedRunRequest(failed), authorityGeneration, trace, failed.userMessageId, stoppedThread,
      );
      end?.(result.state === 'completed' ? 'success' : result.state === 'cancelled' ? 'cancelled' : 'error');
      return result;
    } catch (error) {
      if (preparation.controller.signal.aborted) {
        end?.('cancelled');
        return buildCancelledRunResult(clientRunId, inputMessageId);
      }
      end?.('error');
      throw error;
    } finally {
      this.runPreparations.delete(preparation);
    }
  }

  /**
   * Stops every run of the thread at once. A run still being prepared never reaches the server; the others end with
   * `cancelled`, emit nothing more and drop their tool results. The server cancellation goes on in the background.
   */
  stopRun(threadId: string) {
    this.assertActive();
    this.runPreparations.forEach((preparation) => {
      if (preparation.threadId === threadId) preparation.controller.abort();
    });
    [...this.runs.values()]
      .filter((state) => (
        !state.outcome && !state.controller.signal.aborted && (state.threadId ?? state.request.threadId) === threadId
      ))
      .forEach((state) => this.stopRunState(state, threadId));
    return Promise.resolve();
  }

  private startRunPreparation(threadId: string | undefined, clientRunId: string | undefined) {
    const preparation: RunPreparation = {
      ...(threadId ? { threadId } : {}),
      ...(clientRunId ? { clientRunId } : {}),
      controller: new AbortController(),
    };
    this.runPreparations.add(preparation);
    return preparation;
  }

  // A caller that chooses its run ids tells the runs' updates apart only while no other run has the same id
  private assertNewClientRunId(clientRunId: string) {
    let isUuid = true;
    try {
      uuid(clientRunId, '$.clientRunId');
    } catch {
      isUuid = false;
    }
    const isHeld = this.runs.has(clientRunId)
      || [...this.runPreparations].some((preparation) => preparation.clientRunId === clientRunId)
      || Boolean(this.findFailedRunRequest(clientRunId));
    if (!isUuid || isHeld) {
      throw new AgentV2HttpError(0, 'invalid_request', 'Agent run id is invalid or already in use.', false);
    }
  }

  // The thread's next run waits for the server to cancel a stopped answer, since until then the server refuses it
  private async waitForStopCancellation(preparation: RunPreparation, threadId: string | undefined) {
    const stopCancellation = threadId ? this.stopCancellationByThreadId.get(threadId) : undefined;
    if (!stopCancellation) return undefined;
    preparation.stopCancellation = stopCancellation;
    return raceWithAbortSignal(stopCancellation, preparation.controller.signal);
  }

  // A run that reaches the server takes over the revision its wait brought, so later runs wait for nothing
  private finishRunPreparation(preparation: RunPreparation) {
    throwIfAborted(preparation.controller.signal);
    this.runPreparations.delete(preparation);
    const { threadId, stopCancellation } = preparation;
    if (threadId && stopCancellation && this.stopCancellationByThreadId.get(threadId) === stopCancellation) {
      this.stopCancellationByThreadId.delete(threadId);
    }
  }

  /**
   * The request a retry sends: the same one while the wallet context stays as it was, and otherwise the same question
   * bound to the wallet context as it is now, as after the same account's authority was published again
   */
  private rebindFailedRunRequest({ request, walletContextGeneration }: FailedRunRequest): AgentRunRequestWireV2 {
    if (walletContextGeneration === this.walletContextGeneration) return request;
    const { walletSnapshotRef, ...unboundRequest } = request;
    const built = this.walletSession.buildContext();
    return {
      ...unboundRequest,
      context: built.context,
      capabilities: built.capabilities,
      walletContext: built.walletContext,
      ...this.snapshots.forRun(),
    };
  }

  private getActiveAccountId() {
    return this.walletSession.snapshot().host?.activeAccountId;
  }

  private findFailedRunRequest(clientRunId: string) {
    return [...this.failedRunRequestByThreadId.values()]
      .find(({ request }) => request.clientRunId === clientRunId);
  }

  private executeRun(
    request: AgentRunRequestWireV2,
    authorityGeneration = this.authorityGeneration,
    trace?: AgentClientTrace,
    userMessageId?: string,
    stoppedThread?: AgentThreadSummaryV2,
  ): Promise<AgentV2RunResult> {
    const inputMessageId = getRunInputMessageId(request);
    let resolveStop!: () => void;
    const stop = new Promise<void>((resolve) => {
      resolveStop = resolve;
    });
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
      resolveStop,
      ...(stoppedThread && stoppedThread.revision > request.expectedThreadRevision
        ? { revisionAfterStop: stoppedThread.revision }
        : {}),
    };
    this.runs.set(request.clientRunId, state);
    state.completion = this.completeRun(state, inputMessageId);
    return Promise.race([
      state.completion,
      stop.then(() => buildCancelledRunResult(request.clientRunId, inputMessageId, state.binding.runId)),
    ]);
  }

  private async completeRun(state: RunState, inputMessageId: string | undefined): Promise<AgentV2RunResult> {
    const { clientRunId } = state;
    try {
      await this.followRun(state);
      return {
        clientRunId,
        runId: state.binding.runId,
        ...(inputMessageId ? { inputMessageId } : {}),
        state: state.outcome ?? 'interrupted',
      };
    } catch (error) {
      if (state.controller.signal.aborted || state.isStopped) {
        return {
          clientRunId,
          runId: state.binding.runId,
          ...(inputMessageId ? { inputMessageId } : {}),
          state: 'cancelled',
        };
      }
      if (state.binding.lastSequence === 0 && state.request.entryPoint?.kind !== 'supportRequest'
        && this.isAuthorityGenerationCurrent(state.authorityGeneration)) {
        const retryExpiresAt = failedRunRequestExpiresAt(error, this.now());
        if (retryExpiresAt !== undefined) {
          this.retainFailedRunRequest(state.request, retryExpiresAt, state.userMessageId);
        }
      }
      this.emitFailure(error, state);
      const outcome = error instanceof AgentV2HttpError
        && error.status === 409
        && error.code === 'run_replay_expired'
        ? 'interrupted'
        : 'failed';
      return {
        clientRunId,
        runId: state.binding.runId,
        ...(inputMessageId ? { inputMessageId } : {}),
        state: outcome,
      };
    } finally {
      state.pendingToolCallIds.forEach((toolCallId) => this.discardToolResult(toolCallId));
      state.pendingToolCallIds.clear();
      state.pendingToolResults.clear();
      this.runs.delete(clientRunId);
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
    // Until the server has cancelled a stopped answer, it refuses the clear
    const stoppedThread = await this.stopCancellationByThreadId.get(threadId);
    const result = await this.requestThreadClear(threadId, expectedThreadRevision).catch((error: unknown) => {
      if (!(error instanceof AgentV2HttpError) || error.code !== 'thread_revision_conflict') throw error;
      // A cancelled or stopped answer may have moved the revision after the caller read it, so the clear is sent
      // once more
      const currentThread = hasCancelledRuns ? error.currentThread
        : stoppedThread && stoppedThread.revision > expectedThreadRevision ? stoppedThread : undefined;
      if (currentThread?.id !== threadId) throw error;
      return this.requestThreadClear(threadId, currentThread.revision);
    });
    this.assertThreadBinding(threadId, result.thread.id);
    // The server revokes every run of the thread, including one admitted while the clear was pending
    this.cancelThreadRuns(threadId);
    this.invalidateThread(threadId);
    void this.accessThreadCache((deviceId) => deleteCachedMessages(deviceId, threadId));
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
    const previous = this.unansweredProblemReportByThreadId.get(threadId);
    const clientOperationId = previous?.key === key ? previous.clientOperationId : this.randomUuid();
    this.unansweredProblemReportByThreadId.set(threadId, { key, clientOperationId });
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
    if (this.unansweredProblemReportByThreadId.get(threadId)?.clientOperationId === clientOperationId) {
      this.unansweredProblemReportByThreadId.delete(threadId);
    }
    return result;
  }

  /** Turns one dictated recording into composer text; nothing is stored or sent as a message */
  async transcribe({ audio, format, lang }: AgentV2Transcription) {
    this.assertActive();
    await this.requireConsent();
    return this.getJson(
      `${this.dependencies.baseUrl}/transcriptions`,
      decodeAgentV2Transcription,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ protocolVersion: 3, audio, format, ...(lang && { lang }) }),
      },
      { timeoutMs: TRANSCRIPTION_TIMEOUT_MS },
    );
  }

  /**
   * Sets the user's rating of a complete answer, or withdraws it without `feedback`; a repeated request changes nothing.
   * Requests for one answer reach the server one after another, so it keeps the rating made last.
   */
  async setMessageFeedback(threadId: string, messageId: string, feedback?: AgentAnswerFeedbackV2) {
    this.assertActive();
    const previousRequest = this.feedbackRequestByMessageId.get(messageId);
    const request = (async () => {
      await previousRequest?.catch(() => undefined);
      await this.requireConsent();
      const threadUrl = `${this.dependencies.baseUrl}/threads/${encodeURIComponent(threadId)}`;
      return this.getJson(
        `${threadUrl}/messages/${encodeURIComponent(messageId)}/feedback`,
        decodeAgentV2AnswerFeedback,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          // eslint-disable-next-line no-null/no-null -- The wire withdraws a rating with `null`, as the native apps pass it
          body: JSON.stringify({ protocolVersion: 3, feedback: feedback ?? null }),
        },
      );
    })();
    this.feedbackRequestByMessageId.set(messageId, request);
    try {
      return await request;
    } finally {
      if (this.feedbackRequestByMessageId.get(messageId) === request) this.feedbackRequestByMessageId.delete(messageId);
    }
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
    const cacheCleanup = shouldClearPersistentIdentity ? clearThreadCache() : undefined;
    this.snapshots.reset();
    const pendingOperations: Promise<unknown>[] = [];
    pendingOperations.push(...this.backgroundTasks);
    if (this.consentWritePromise) pendingOperations.push(this.consentWritePromise);
    this.runs.forEach(({ controller }) => controller.abort());
    this.runs.clear();
    this.runPreparations.clear();
    this.stopCancellationByThreadId.clear();
    this.clearFailedRunRequests();
    this.unansweredProblemReportByThreadId.clear();
    this.unansweredThreadDeletionByThreadId.clear();
    this.threadGenerationByThreadId.clear();
    this.clearGenerationByThreadId.clear();
    this.actions.clear();
    this.toolExecutor.clear?.();
    this.probes.destroy();
    const identityDestroy = this.identity.destroy({
      shouldClearPersistentIdentity,
    });
    await Promise.allSettled(pendingOperations);
    await cacheCleanup;
    await identityDestroy;
    if (shouldClearPersistentIdentity) {
      await this.walletSession.reset({ shouldClearPersistentState: true });
      await this.dependencies.storage.removeItem(AGENT_V2_CONSENT_STORAGE_KEY);
      this.consentPromise = undefined;
    } else {
      await this.walletSession.flushPersistence();
    }
  }

  private async followRun(state: RunState) {
    let attempt = 0;
    let lastProtocolFailureSequence: number | undefined;
    let protocolFailureCount = 0;
    // A stopped run the server has not named goes on reconnecting as a run before admission does, to learn its id
    const isFollowing = () => (!state.outcome || (state.isStopped && !state.binding.runId))
      && !state.controller.signal.aborted;
    while (isFollowing()) {
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
        for await (const event of parseAgentV2Ndjson(response.body, state.binding, state.controller.signal)) {
          // A stopped run reads its stream only until the server names it, so that it can be cancelled by that name
          if (state.isStopped && state.binding.runId) {
            state.controller.abort();
            break;
          }
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
        if (isFollowing()) {
          throw new AgentV2StreamTransportError('Agent V2 stream ended before a terminal event');
        }
        endStream?.(state.controller.signal.aborted ? 'cancelled' : state.outcome === 'failed' ? 'error' : 'success');
      } catch (error) {
        endStream?.(state.controller.signal.aborted ? 'cancelled' : 'error');
        if (!isFollowing()) return;
        // A stopped answer moved the thread past the revision this run was sent with, so it is sent once more
        const { revisionAfterStop } = state;
        if (revisionAfterStop !== undefined && !state.isStopped && state.binding.lastSequence === 0
          && error instanceof AgentV2HttpError && error.code === 'thread_revision_conflict') {
          state.revisionAfterStop = undefined;
          state.request = { ...state.request, expectedThreadRevision: revisionAfterStop };
          continue;
        }
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
      if (state.request.entryPoint?.kind === 'supportRequest') this.clearFailedRunRequest(event.threadId);
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
    const threadGeneration = this.getThreadGeneration(threadId);
    for (const action of pending.actions) {
      if (!this.isRunCurrent(state)
        || state.controller.signal.aborted
        || threadGeneration !== this.getThreadGeneration(threadId)
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
    const threadId = request.threadId;
    this.clearFailedRunRequest(threadId);
    const accountId = this.getActiveAccountId();
    const failedRunRequest: FailedRunRequest = {
      request,
      expiresAt,
      ...(userMessageId ? { userMessageId } : {}),
      ...(accountId ? { accountId } : {}),
      walletContextGeneration: this.walletContextGeneration,
      timer: setTimeout(() => {
        if (this.failedRunRequestByThreadId.get(threadId) === failedRunRequest) {
          this.failedRunRequestByThreadId.delete(threadId);
        }
      }, Math.max(0, expiresAt - this.now())),
    };
    this.failedRunRequestByThreadId.set(threadId, failedRunRequest);
  }

  private clearFailedRunRequest(threadId: string | undefined) {
    const failed = this.failedRunRequestByThreadId.get(threadId);
    if (failed) clearTimeout(failed.timer);
    this.failedRunRequestByThreadId.delete(threadId);
  }

  private clearFailedRunRequests() {
    this.failedRunRequestByThreadId.forEach(({ timer }) => clearTimeout(timer));
    this.failedRunRequestByThreadId.clear();
  }

  private now() {
    return this.dependencies.now?.() ?? Date.now();
  }

  private emitUpdate(update: AgentV2ClientUpdate) {
    if (this.lifecycleController.signal.aborted) return;
    if (update.kind === 'threadChanged') {
      void this.accessThreadCache((deviceId) => updateCachedThread(deviceId, update.thread));
    }
    const trace = update.clientRunId ? this.runs.get(update.clientRunId)?.trace : undefined;
    if (trace) {
      trace.markOnce('client_update_dispatched');
      this.dependencies.onUpdate({ ...update, developmentTraceId: trace.traceId });
    } else this.dependencies.onUpdate(update);
  }

  private async accessThreadCache<T>(operation: (deviceId: string) => Promise<T>): Promise<T | undefined> {
    try {
      if (this.lifecycleController.signal.aborted) return undefined;
      const deviceId = await this.identity.getDeviceId();
      if (!deviceId || this.lifecycleController.signal.aborted) return undefined;
      return await operation(deviceId);
    } catch (error) {
      logDebugError('AgentV2 thread cache', error);
      return undefined;
    }
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
    // A stopped run has its own server cancellation
    const runIds = states
      .flatMap(({ binding, isStopped }) => binding.runId && !isStopped ? [binding.runId] : []);
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

  private stopRunState(state: RunState, threadId: string) {
    const runId = state.binding.runId;
    // The server runs an answer apart from its stream, so a run it has not named yet keeps reading its stream
    if (runId) {
      this.cancelRunLocally(state);
    } else {
      state.outcome = 'cancelled';
    }
    state.isStopped = true;
    state.resolveStop();
    if (runId) this.emitUpdate({ kind: 'runCancelled', clientRunId: state.clientRunId, runId, threadId });

    const cancellation = this.limitStopCancellation(this.cancelStoppedRun(state));
    const previous = this.stopCancellationByThreadId.get(threadId);
    const threadCancellation = previous
      ? Promise.all([previous, cancellation]).then(([first, second]) => (
        first && (!second || first.revision > second.revision) ? first : second
      ))
      : cancellation;
    this.stopCancellationByThreadId.set(threadId, threadCancellation);
    this.trackBackgroundTask(threadCancellation.then(() => undefined));
  }

  // The thread's next run and clear wait for the cancellation no longer than for any other request
  private limitStopCancellation(cancellation: Promise<AgentThreadSummaryV2 | undefined>) {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<undefined>((resolve) => {
      timer = setTimeout(resolve, this.requestTimeoutMs, undefined);
    });
    return Promise.race([cancellation, timeout]).finally(() => clearTimeout(timer));
  }

  private async cancelStoppedRun(state: RunState) {
    if (!state.binding.runId) {
      // A stream that does not name the run in time is given up, together with the run's cancellation
      const timer = setTimeout(() => state.controller.abort(), this.requestTimeoutMs);
      await state.completion;
      clearTimeout(timer);
    }
    const runId = state.binding.runId;
    if (!runId || this.lifecycleController.signal.aborted) return undefined;
    try {
      const result = await this.requestRunCancel(runId, REMOTE_CANCEL_TIMEOUT_MS);
      this.assertRunBinding(runId, result.runId);
      this.emitUpdate({ kind: 'threadChanged', threadId: result.thread.id, thread: result.thread });
      return result.thread;
    } catch (error) {
      if (!this.lifecycleController.signal.aborted) {
        logDebugError('AgentV2 run cancellation', { runId, stage: 'stop' }, error);
      }
      return undefined;
    }
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
    this.threadGenerationByThreadId.set(threadId, this.getThreadGeneration(threadId) + 1);
    this.clearFailedRunRequest(threadId);
    this.actions.clear(threadId);
    this.toolExecutor.clear?.(threadId);
    this.emitUpdate({ kind: 'walletAuthorityChanged', threadId });
  }

  private getThreadGeneration(threadId: string) {
    return this.threadGenerationByThreadId.get(threadId) ?? 0;
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

function buildCancelledRunResult(clientRunId: string, inputMessageId?: string, runId?: string): AgentV2RunResult {
  return {
    clientRunId,
    ...(runId ? { runId } : {}),
    ...(inputMessageId ? { inputMessageId } : {}),
    state: 'cancelled',
  };
}

function getRunInputMessageId(request: AgentRunRequestWireV2) {
  return request.input.kind === 'regenerate' ? undefined : request.input.message.id;
}

/**
 * The agent gives an operator's photo by a path on its own origin, which every host shows by its full address. A
 * malformed address goes, so the operator's initial shows instead of the whole history failing.
 */
function resolveOperatorAvatarUrl<T extends { author?: { avatarUrl?: string } }>(message: T, baseUrl: string): T {
  if (message.author?.avatarUrl === undefined) return message;
  const { avatarUrl, ...author } = message.author;
  const href = resolveHttpUrl(avatarUrl, baseUrl);
  return { ...message, author: href ? { ...author, avatarUrl: href } : author };
}

function resolveHttpUrl(url: string, baseUrl: string) {
  if (!url.trim()) return undefined;
  try {
    const resolved = new URL(url, new URL(baseUrl).origin);
    return resolved.protocol === 'https:' || resolved.protocol === 'http:' ? resolved.href : undefined;
  } catch {
    return undefined;
  }
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

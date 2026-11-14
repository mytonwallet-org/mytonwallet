import type {
  AgentEntryPoint,
  AgentPublicFollowUpV2,
  AgentThreadClearResponseV2,
  AgentThreadSummaryV2,
  AgentV2ErrorCode,
} from '../../../api/agentV2/protocol/types';
import type {
  AgentV2ClientUpdate,
  AgentV2MutationResult,
  AgentV2RunCommand,
  AgentV2RunCommandInput,
  AgentV2RunResult,
  AgentV2StarterHints,
  AgentV2SupportRequestSource,
} from '../../../api/agentV2/types';
import type { AgentHint, AgentMessage } from '../../../global/types';
import type {
  AgentV2HeldLimitState,
  AgentV2MessagesState,
  AgentV2MessagesStateAction,
  AgentV2RunOperationKind,
} from './agentV2MessagesState';
import type { AgentV2StreamController } from './agentV2StreamController';

import { getIsAgentV2SupportActive } from '../../../global/agentV2/uiCapabilities';
import { isAgentV2ComposerBlocked } from '../../agentV2/agentComposerStatus';
import { agentUiTrace } from './agentDevelopmentTiming';
import {
  getRunOperationId,
  selectAgentV2ComposerStatusForState,
  selectAgentV2HeldLimitRunId,
  selectCanRequestAgentV2Support,
  selectIsAgentV2InputDisabled,
  selectIsAgentV2RunActive,
  selectIsAgentV2SendDisabled,
} from './agentV2MessagesState';

// The longest delay `setTimeout` keeps; a longer one fires at once
const MAX_TIMEOUT_MS = 2 ** 31 - 1;

export type AgentV2StarterHintEntryPoint = Extract<AgentEntryPoint, { kind: 'emptyState' }>;

type AgentV2RunAdmission =
  | { kind: 'append'; messageId: number }
  | { kind: 'edit'; targetMessageId: number; text: string }
  | { kind: 'regenerate'; targetMessageId: number };

type AgentV2ActiveRunAdmission = {
  admission: AgentV2RunAdmission;
  isApplied: boolean;
  isSupportRequest: boolean;
};

export interface AgentV2HeldLimitRun {
  clientRunId: string;
  admission: AgentV2RunAdmission;
  limit: AgentV2HeldLimitState;
  message?: AgentMessage;
  sourceId?: string;
  isQueueRetried: boolean;
}

type AgentV2ThreadClearOperation = {
  operationId: number;
  threadId: string;
  threadRevision: number;
};

export interface AgentV2RunControllerDependencies {
  buildConnectionError: () => string;
  clearThread: (
    threadId: string,
    expectedRevision: number,
  ) => Promise<AgentV2MutationResult<AgentThreadClearResponseV2> | undefined>;
  dispatch: (action: AgentV2MessagesStateAction) => void;
  getErrorText: (code: AgentV2ErrorCode) => string;
  getSupportRequestText: () => string;
  getState: () => AgentV2MessagesState;
  /** The account active in the wallet, which queued questions and a run a limit held are asked for */
  getActiveAccountId: () => string | undefined;
  isQueueHeld?: () => boolean;
  hydrate: (shouldPreserveLiveContent?: boolean, isFailureSilent?: boolean) => Promise<boolean>;
  now: () => number;
  retryRun: (clientRunId: string) => Promise<AgentV2RunResult | undefined>;
  resetHistory: NoneToVoidFunction;
  /** `isStopped` tells whether the user stopped the answer before the run reached the runtime */
  startRun: (command: AgentV2RunCommand, isStopped: () => boolean) => Promise<AgentV2RunResult | undefined>;
  stopRun: (threadId: string) => Promise<unknown>;
  /** A queued question has left the queue for its run */
  onQueuedMessageSent?: (messageId: number) => void;
  stream: AgentV2StreamController;
  // The message as it is shown and sent: a recovery phrase replaced with a placeholder before either
  hideSecretPhrases: (text: string) => string;
}

export interface AgentV2RunController {
  clearChat: NoneToVoidFunction;
  dispose: NoneToVoidFunction;
  handleUpdate: (update: AgentV2ClientUpdate) => void;
  isCancelledRunUpdate: (update: AgentV2ClientUpdate) => boolean;
  isInputBlocked: () => boolean;
  hasPendingAdmission: () => boolean;
  getHeldLimitRun: () => AgentV2HeldLimitRun | undefined;
  restoreHeldLimitRun: (held: AgentV2HeldLimitRun) => void;
  releaseStaleThreadClearOperation: (
    thread: AgentThreadSummaryV2,
    shouldMatchRevision: boolean,
  ) => void;
  retryAdmission: NoneToVoidFunction;
  /** Queues again the questions a wallet switch failed, behind the answer being produced */
  retryFailedQueue: NoneToVoidFunction;
  retryMessage: (messageId: number) => void;
  sendFollowup: (
    messageId: number, followup: AgentPublicFollowUpV2, shownMessage?: AgentV2ShownMessage,
  ) => boolean;
  sendHint: (hint: AgentHint) => void;
  requestSupport: (source: AgentV2SupportRequestSource, shownMessage?: AgentV2ShownMessage) => boolean;
  /**
   * `shownMessage` is the question already on screen, which the sent message takes the place of, and `hintEntryPoint`
   * tells the starter hint it came from. Nothing is sent while an answer is being produced or questions wait.
   */
  sendMessage: (
    text: string,
    editMessageId?: number,
    shownMessage?: AgentV2ShownMessage,
    hintEntryPoint?: AgentV2StarterHintEntryPoint,
  ) => boolean;
  /**
   * The composer's send. A question sent while an answer is being produced, or while others wait, is queued: it shows
   * at once and goes after them. An edit waits for a free chat.
   */
  sendOrQueueMessage: (text: string, editMessageId?: number) => boolean;
  /** Sends the next queued question if the chat is free, as once a limit that held the queue has reset */
  sendQueuedMessage: NoneToVoidFunction;
  /**
   * An answer is being produced that `stopRun` stops; one that has ended or is already stopped is not. Stop also stays
   * while a stop sends the next queued question, whose answer `stopRun` leaves until its run has started.
   */
  canStopRun: () => boolean;
  stopRun: NoneToVoidFunction;
}

type AgentV2ShownMessage = Pick<AgentMessage, 'id' | 'timestamp'>;
type AgentV2RunFailedUpdate = Extract<AgentV2ClientUpdate, { kind: 'runFailed' }>;

export function createAgentV2RunController(
  dependencies: AgentV2RunControllerDependencies,
): AgentV2RunController {
  let nextRunOperationId = 0;
  let nextThreadMutationOperationId = 0;
  let isDisposed = false;
  const admissionsByOperation = new Map<number, AgentV2ActiveRunAdmission>();
  const retainedAdmissions = new Map<string, AgentV2RunAdmission>();
  const cancelledRunOperationIds = new Set<number>();
  // Stopped operations, a subset of the cancelled ones, which never send a run they have not sent yet
  const stoppedRunOperationIds = new Set<number>();
  // Operator replies raise the revision of a thread with support, which the client learns only by polling
  const supportResendOperationIds = new Set<number>();
  const revisionConflictsByOperation = new Map<number, AgentV2RunFailedUpdate>();
  // Stopped runs, whose later updates are dropped. The chat may follow a run it has not started, which it gets
  // replayed when it opens during the run.
  const stoppedClientRunIds = new Set<string>();
  // The answer the latest run started
  let latestAnswer: { clientRunId: string; messageId: number } | undefined;
  // The thread of the answer stopped last, whose history is read again once the server has cancelled the answer
  let stoppedThreadId: string | undefined;
  // The thread whose history is read again once the chat is free
  let refreshThreadId: string | undefined;
  // A stop sends the next queued question, whose operation can't be stopped until its run has started, so that a
  // second tap on Stop, which stays in place, doesn't stop that question too
  let isQueueAdvancedByStop = false;
  let operationStartedByStop: number | undefined;
  // The account the queue and a run a limit held were asked for, as the latest wallet authority the chat learned of
  let authorityAccountId = dependencies.getActiveAccountId();
  // Runs a limit held that the queue has sent again, once each, so that one failing again doesn't hold the queue
  const queueRetriedClientRunIds = new Set<string>();
  let queueResetTimeout: number | undefined;

  return {
    clearChat,
    dispose,
    handleUpdate,
    isCancelledRunUpdate,
    isInputBlocked,
    hasPendingAdmission,
    getHeldLimitRun,
    restoreHeldLimitRun,
    releaseStaleThreadClearOperation,
    retryAdmission,
    retryFailedQueue,
    retryMessage,
    sendFollowup,
    sendHint,
    requestSupport,
    sendMessage,
    sendOrQueueMessage,
    sendQueuedMessage,
    canStopRun,
    stopRun,
  };

  function dispose() {
    isDisposed = true;
    window.clearTimeout(queueResetTimeout);
    admissionsByOperation.clear();
    retainedAdmissions.clear();
    cancelledRunOperationIds.clear();
    stoppedRunOperationIds.clear();
    supportResendOperationIds.clear();
    revisionConflictsByOperation.clear();
    stoppedClientRunIds.clear();
    queueRetriedClientRunIds.clear();
  }

  function sendMessage(
    text: string,
    editMessageId?: number,
    shownMessage?: AgentV2ShownMessage,
    hintEntryPoint?: AgentV2StarterHintEntryPoint,
  ) {
    return send(text, editMessageId, shownMessage, false, hintEntryPoint);
  }

  function sendOrQueueMessage(text: string, editMessageId?: number) {
    return send(text, editMessageId, undefined, true);
  }

  function send(
    text: string,
    editMessageId: number | undefined,
    shownMessage: AgentV2ShownMessage | undefined,
    canQueue: boolean,
    hintEntryPoint?: AgentV2StarterHintEntryPoint,
  ) {
    if (isDisposed) return false;
    handleWalletAuthorityChanged();
    const trimmed = text.trim();
    const thread = dependencies.getState().thread;
    if (!trimmed || !thread || isSendBlocked()) return false;
    const canEditMessage = !getIsAgentV2SupportActive(thread);
    const message = dependencies.hideSecretPhrases(trimmed);

    const targetMessageId = editMessageId && canEditMessage
      ? dependencies.stream.getSourceId(editMessageId) : undefined;
    if (editMessageId && canEditMessage && !targetMessageId) return false;
    // An edit changes the conversation an answer is being produced for, so it waits for a free chat
    if (targetMessageId && isInputBlocked()) return false;

    if (!targetMessageId && isInputBlocked()) {
      if (!canQueue) return false;
      dependencies.dispatch({
        kind: 'messageQueued',
        message: {
          id: dependencies.stream.createLocalMessageId(),
          text: message,
          isOutgoing: true,
          timestamp: dependencies.now(),
        },
      });
      sendQueuedMessage();
      return true;
    }

    if (targetMessageId) {
      void run(
        { input: { kind: 'edit', targetUserMessageId: targetMessageId, text: message } },
        { kind: 'edit', targetMessageId: editMessageId!, text: message },
      );
      return true;
    }

    void appendMessage(message, shownMessage, hintEntryPoint);
    return true;
  }

  function appendMessage(
    message: string, shownMessage?: AgentV2ShownMessage, hintEntryPoint?: AgentV2StarterHintEntryPoint,
  ) {
    const thread = dependencies.getState().thread!;
    const outgoingMessageId = addOptimisticMessage(message, shownMessage);
    const input = { kind: 'append', text: message } as const;
    return run(thread.news || thread.digest ? { input } : {
      input, entryPoint: hintEntryPoint ?? { kind: 'agentTab' },
    }, { kind: 'append', messageId: outgoingMessageId });
  }

  // The next queued question goes once the chat is free: no answer being produced, nothing loading or being cleared,
  // and no limit holding questions back. It keeps its place and its bubble.
  function sendQueuedMessage() {
    window.clearTimeout(queueResetTimeout);
    queueResetTimeout = undefined;
    if (isDisposed || dependencies.isQueueHeld?.()) return;
    handleWalletAuthorityChanged();
    const current = dependencies.getState();
    const [message] = current.queuedMessages;
    if (!message || !current.thread || selectIsAgentV2SendDisabled(current, false)
      || selectIsAgentV2RunActive(current)) return;
    const composerStatus = selectAgentV2ComposerStatusForState(current, dependencies.now());
    if (composerStatus?.mode === 'blocked') {
      queueResetTimeout = window.setTimeout(
        sendQueuedMessage, Math.min(composerStatus.resetAt - dependencies.now(), MAX_TIMEOUT_MS),
      );
      return;
    }
    // The question a limit held back before the server took it goes first, as its Retry sends it, and the queue
    // follows it
    const heldClientRunId = selectAgentV2HeldLimitRunId(current);
    if (heldClientRunId && retainedAdmissions.has(heldClientRunId) && !queueRetriedClientRunIds.has(heldClientRunId)) {
      queueRetriedClientRunIds.add(heldClientRunId);
      retryHeldRun(heldClientRunId);
      return;
    }
    void appendMessage(message.text, message);
    if (isQueueAdvancedByStop) operationStartedByStop = nextRunOperationId;
    dependencies.onQueuedMessageSent?.(message.id);
  }

  function sendHint(hint: AgentHint) {
    const current = dependencies.getState();
    const entryPoint = current.starterHints && buildAgentV2StarterHintEntryPoint(current.starterHints, hint.id);
    if (!current.thread || !entryPoint || isInputBlocked()) return;
    const outgoingMessageId = addOptimisticMessage(hint.title);
    void run({
      input: { kind: 'append', text: hint.title },
      entryPoint,
    }, { kind: 'append', messageId: outgoingMessageId });
  }

  function requestSupport(source: AgentV2SupportRequestSource, shownMessage?: AgentV2ShownMessage) {
    if (isDisposed || !selectCanRequestAgentV2Support(dependencies.getState(), dependencies.now())) return false;
    const text = dependencies.getSupportRequestText();
    const outgoingMessageId = addOptimisticMessage(text, shownMessage);
    void run({
      input: { kind: 'append', text },
      entryPoint: { kind: 'supportRequest', source },
    }, { kind: 'append', messageId: outgoingMessageId });
    return true;
  }

  function sendFollowup(
    messageId: number, followup: AgentPublicFollowUpV2, shownMessage?: AgentV2ShownMessage,
  ) {
    const thread = dependencies.getState().thread;
    const sourceMessageId = dependencies.stream.getSourceId(messageId);
    if (!thread || !sourceMessageId || isInputBlocked()) return false;
    const { text } = followup;
    const outgoingMessageId = addOptimisticMessage(text, shownMessage);
    void run({
      input: { kind: 'append', text },
      followupOf: { messageId: sourceMessageId, followupId: followup.id },
    }, { kind: 'append', messageId: outgoingMessageId });
    return true;
  }

  function retryMessage(messageId: number) {
    const { thread, messages } = dependencies.getState();
    const sourceMessageId = dependencies.stream.getSourceId(messageId);
    if (!thread || !sourceMessageId || isInputBlocked()) return;
    if (getIsAgentV2SupportActive(thread)) return;
    const message = messages.find(({ id }) => id === messageId);
    if (!message || message.operator || message.supportEvent) return;
    const userMessageId = getAnsweredUserMessageId(messageId);
    void run(
      {
        input: {
          kind: 'regenerate',
          targetAssistantMessageId: sourceMessageId,
          ...(userMessageId ? { userMessageId } : {}),
        },
      },
      { kind: 'regenerate', targetMessageId: messageId },
    );
  }

  // The server answers again the last user message before the regenerated answer
  function getAnsweredUserMessageId(messageId: number) {
    const { messages } = dependencies.getState();
    for (let index = messages.findIndex(({ id }) => id === messageId) - 1; index >= 0; index -= 1) {
      if (messages[index].isOutgoing) return dependencies.stream.getSourceId(messages[index].id);
    }
    return undefined;
  }

  function retryAdmission() {
    if (isDisposed) return;
    handleWalletAuthorityChanged();
    const current = dependencies.getState();
    const clientRunId = current.admissionFailure?.clientRunId
      ?? current.quotaRetry?.clientRunId
      ?? current.userRateLimit?.clientRunId;
    // A question a limit held back goes again before those queued after it
    if (!clientRunId || isSendBlocked() || selectIsAgentV2RunActive(current)) return;
    retryHeldRun(clientRunId);
  }

  function hasPendingAdmission() {
    for (const { isApplied } of admissionsByOperation.values()) {
      if (!isApplied) return true;
    }
    return false;
  }

  function getHeldLimitRun(): AgentV2HeldLimitRun | undefined {
    const current = dependencies.getState();
    if (selectIsAgentV2RunActive(current)) return undefined;
    const clientRunId = selectAgentV2HeldLimitRunId(current);
    const admission = clientRunId ? retainedAdmissions.get(clientRunId) : undefined;
    if (!clientRunId || !admission) return undefined;
    const { quotaRetry, userRateLimit, admissionFailure } = current;
    return {
      clientRunId,
      admission,
      limit: {
        quotaRetry, userRateLimit,
        admissionFailure: admissionFailure?.clientRunId === clientRunId ? admissionFailure : undefined,
      },
      ...(admission.kind === 'append'
        ? { message: current.messages.find(({ id }) => id === admission.messageId) }
        : { sourceId: dependencies.stream.getSourceId(admission.targetMessageId) }),
      isQueueRetried: queueRetriedClientRunIds.has(clientRunId),
    };
  }

  function restoreHeldLimitRun(held: AgentV2HeldLimitRun) {
    const { clientRunId, admission, limit } = held;
    const messageId = admission.kind === 'append'
      ? dependencies.stream.createLocalMessageId()
      : dependencies.stream.getMessageId(held.sourceId!);
    retainedAdmissions.set(clientRunId, admission.kind === 'append'
      ? { ...admission, messageId }
      : { ...admission, targetMessageId: messageId });
    if (held.isQueueRetried) queueRetriedClientRunIds.add(clientRunId);
    dependencies.dispatch({
      kind: 'heldLimitRestored',
      limit: {
        ...limit,
        quotaRetry: limit.quotaRetry && {
          ...limit.quotaRetry,
          ...(limit.quotaRetry.optimisticMessageId !== undefined ? { optimisticMessageId: messageId } : {}),
        },
        userRateLimit: limit.userRateLimit && {
          ...limit.userRateLimit,
          ...(limit.userRateLimit.optimisticMessageId !== undefined ? { optimisticMessageId: messageId } : {}),
        },
        admissionFailure: limit.admissionFailure && {
          ...limit.admissionFailure,
          ...(limit.admissionFailure.optimisticMessageId !== undefined ? { optimisticMessageId: messageId } : {}),
          ...(limit.admissionFailure.retryMessageId !== undefined ? { retryMessageId: messageId } : {}),
        },
      },
      ...(admission.kind === 'append' ? { message: { ...held.message!, id: messageId } } : {}),
    });
  }

  // The same run goes again, with the question its failure held
  function retryHeldRun(clientRunId: string) {
    const operationId = requestRun('admissionRetry', retainedAdmissions.get(clientRunId));
    void retryAdmissionRun(clientRunId, operationId);
  }

  // Questions that failed in the queue go back to its front, behind the answer being produced, as on Android
  function retryFailedQueue() {
    if (isDisposed) return;
    handleWalletAuthorityChanged();
    const current = dependencies.getState();
    if (!current.failedQueue || isSendBlocked()) return;
    dependencies.dispatch({ kind: 'queuedMessagesRetried' });
    sendQueuedMessage();
  }

  // A confirmed clear also cancels a running answer, whose operation then settles without presenting its result
  function clearChat() {
    const current = dependencies.getState();
    const thread = current.thread;
    if (
      isDisposed
      || !thread
      || current.isLoading
      || ((thread.news || thread.digest) && !current.hasHydratedHistory)
      || current.threadMutation.phase === 'clearing'
    ) return;

    const operation = {
      operationId: ++nextThreadMutationOperationId,
      threadId: thread.id,
      threadRevision: thread.revision,
    };
    const runOperationId = getRunOperationId(current.run);
    if (runOperationId !== undefined) cancelledRunOperationIds.add(runOperationId);
    retainedAdmissions.clear();
    // The clear leaves no stopped answer to read again
    stoppedThreadId = undefined;
    refreshThreadId = undefined;
    dependencies.resetHistory();
    dependencies.stream.resetMessageArtifacts();
    dependencies.dispatch({ kind: 'threadClearStarted', ...operation });
    void clearThread(thread, operation);
  }

  // The answer stops at once, keeping the text it has shown. The operation of a run this chat started settles without
  // presenting its result; a run the chat follows without one frees the chat at once. The runtime cancels the run on
  // the server.
  function stopRun() {
    const { thread, run } = dependencies.getState();
    if (!isRunStoppable() || run.phase === 'idle' || run.phase === 'terminal') return;
    const { operationId } = run;
    const clientRunId = run.phase === 'streaming' ? run.clientRunId : undefined;
    if (operationId !== undefined) {
      cancelledRunOperationIds.add(operationId);
      stoppedRunOperationIds.add(operationId);
    }
    if (clientRunId !== undefined) stoppedClientRunIds.add(clientRunId);
    stoppedThreadId = thread!.id;
    dependencies.stream.flushDeltas();
    dependencies.stream.terminalizeTextRevealPresentations();
    dependencies.dispatch({
      kind: 'runStopped',
      ...(latestAnswer && latestAnswer.clientRunId === clientRunId ? { messageId: latestAnswer.messageId } : {}),
    });
    void dependencies.stopRun(thread!.id);
    // The next queued question goes as soon as the stopped run frees the chat: at once for a run without an
    // operation here, and otherwise once its operation settles, which the runtime does at the stop
    isQueueAdvancedByStop = true;
    if (operationId === undefined) {
      sendQueuedMessage();
      isQueueAdvancedByStop = false;
    }
  }

  // Stop stays in place while a stop sends the next queued question, as on Android, so a second tap lands on it
  function canStopRun() {
    return isRunStoppable() || isStopHeldForQueue();
  }

  // A run that has ended waits only for its result, and a stopped or cleared one only to settle
  function isRunStoppable() {
    const { thread, run } = dependencies.getState();
    if (isDisposed || !thread || (run.phase !== 'admitting' && run.phase !== 'streaming')) return false;
    const { operationId } = run;
    if (run.phase === 'admitting' && operationId === operationStartedByStop) return false;
    const clientRunId = run.phase === 'streaming' ? run.clientRunId : undefined;
    return !(operationId !== undefined && cancelledRunOperationIds.has(operationId))
      && !(clientRunId !== undefined && stoppedClientRunIds.has(clientRunId));
  }

  // From the stop until the run of the queued question it sends has started: the stopped run settling, then the
  // question being admitted
  function isStopHeldForQueue() {
    const { run, queuedMessages } = dependencies.getState();
    const operationId = getRunOperationId(run);
    if (isDisposed || operationId === undefined) return false;
    if (operationId === operationStartedByStop) {
      return run.phase === 'admitting' && !cancelledRunOperationIds.has(operationId);
    }
    return isQueueAdvancedByStop && stoppedRunOperationIds.has(operationId) && queuedMessages.length > 0;
  }

  // The server keeps what a stopped answer has shown, or the whole answer when it finished first, so the history is
  // read again once the server has cancelled the answer and the chat is free
  function requestStoppedAnswerRefresh(thread: AgentThreadSummaryV2) {
    if (thread.id !== stoppedThreadId) return;
    stoppedThreadId = undefined;
    refreshThreadId = thread.id;
  }

  function refreshStoppedAnswer() {
    if (isDisposed || !refreshThreadId) return;
    const current = dependencies.getState();
    if (current.thread?.id !== refreshThreadId) {
      refreshThreadId = undefined;
      return;
    }
    if (selectIsAgentV2RunActive(current) || current.threadMutation.phase === 'clearing') return;
    refreshThreadId = undefined;
    void dependencies.hydrate(false, true);
  }

  // The runtime emits nothing for the thread's runs once it sends a clear or a stop, and no run starts while a clear
  // or a cancelled operation is pending, so a run update in that time is late output of the cancelled answer
  function isCancelledRunUpdate(update: AgentV2ClientUpdate) {
    if (update.clientRunId === undefined) return false;
    const current = dependencies.getState();
    const runOperationId = getRunOperationId(current.run);
    return current.threadMutation.phase === 'clearing'
      || stoppedClientRunIds.has(update.clientRunId)
      || (runOperationId !== undefined && cancelledRunOperationIds.has(runOperationId));
  }

  function addOptimisticMessage(text: string, shownMessage?: AgentV2ShownMessage) {
    const messageId = shownMessage?.id ?? dependencies.stream.createLocalMessageId();
    const timestamp = shownMessage?.timestamp ?? dependencies.now();
    dependencies.dispatch({
      kind: 'optimisticMessageAdded',
      message: {
        id: messageId,
        text,
        isOutgoing: true,
        timestamp,
      },
    });
    return messageId;
  }

  async function run(command: AgentV2RunCommandInput, admission: AgentV2RunAdmission) {
    const thread = dependencies.getState().thread;
    if (!thread || isDisposed) return;
    const operationId = requestRun(
      command.entryPoint?.kind === 'supportRequest' ? 'supportRequest' : 'command', admission,
    );
    if (admission.kind === 'append' && getIsAgentV2SupportActive(thread)) supportResendOperationIds.add(operationId);
    const trace = agentUiTrace();
    trace?.mark('ui_submit');
    function startRun(threadRevision: number) {
      return dependencies.startRun({
        ...command,
        ...(trace ? { developmentTraceId: trace.traceId } : {}),
        threadId: thread!.id,
        expectedThreadRevision: threadRevision,
      }, () => stoppedRunOperationIds.has(operationId));
    }
    try {
      let result = await startRun(thread.revision);
      const revisionConflict = revisionConflictsByOperation.get(operationId);
      if (revisionConflict) {
        revisionConflictsByOperation.delete(operationId);
        const revision = await refreshThreadForResend(operationId, thread.id, admission, revisionConflict);
        if (revision === undefined) return;
        result = await startRun(revision);
      }
      await settleRunResult(result, operationId, false);
    } catch {
      setRunConnectionError(operationId);
    } finally {
      finishRunOperation(operationId);
      trace?.mark('ui_complete');
    }
  }

  // The message stays on screen while the thread is read again, and is sent once more to its new revision.
  // A read that fails or is superseded reports the conflict instead.
  async function refreshThreadForResend(
    operationId: number,
    threadId: string,
    admission: AgentV2RunAdmission,
    revisionConflict: AgentV2RunFailedUpdate,
  ) {
    const messageId = admission.kind === 'append' ? admission.messageId : undefined;
    const outgoingMessage = dependencies.getState().messages.find(({ id }) => id === messageId);
    const isHydrated = await dependencies.hydrate(false, true);
    const current = dependencies.getState();
    if (
      isDisposed
      || cancelledRunOperationIds.has(operationId)
      || getRunOperationId(current.run) !== operationId
      || current.thread?.id !== threadId
    ) return undefined;
    if (!isHydrated) {
      reportRunFailure(revisionConflict);
      return undefined;
    }
    if (outgoingMessage && !current.messages.some(({ id }) => id === outgoingMessage.id)) {
      dependencies.dispatch({ kind: 'optimisticMessageAdded', message: outgoingMessage });
    }
    return current.thread.revision;
  }

  async function retryAdmissionRun(clientRunId: string, operationId: number) {
    try {
      const result = await dependencies.retryRun(clientRunId);
      await settleRunResult(result, operationId, true);
    } catch {
      setRunConnectionError(operationId);
    } finally {
      finishRunOperation(operationId);
    }
  }

  async function settleRunResult(
    result: AgentV2RunResult | undefined,
    operationId: number,
    shouldConsumeAdmissionRetry: boolean,
  ) {
    if (isDisposed || cancelledRunOperationIds.has(operationId)) return;
    if (!result) {
      if (getRunOperationId(dependencies.getState().run) === operationId) setRunConnectionError(operationId);
      return;
    }
    if (getRunOperationId(dependencies.getState().run) === operationId && result.runId) {
      applyRunAdmission(result.inputMessageId, operationId);
    } else {
      bindRunInputMessage(result.inputMessageId, operationId);
    }
    if (result.state === 'failed') retainRunAdmission(result.clientRunId, operationId);
    if (getRunOperationId(dependencies.getState().run) !== operationId) return;
    switch (result.state) {
      case 'completed':
        retainedAdmissions.delete(result.clientRunId);
        if (shouldConsumeAdmissionRetry) {
          dependencies.dispatch({ kind: 'admissionRetryConsumed', operationId });
        }
        break;
      case 'cancelled':
        retainedAdmissions.delete(result.clientRunId);
        dependencies.stream.flushDeltas();
        dependencies.stream.terminalizeTextRevealPresentations();
        dependencies.dispatch({ kind: 'runCancelled', clientRunId: result.clientRunId });
        if (shouldConsumeAdmissionRetry) {
          dependencies.dispatch({ kind: 'admissionRetryConsumed', operationId });
        }
        break;
      case 'failed':
        break;
      case 'interrupted':
        retainedAdmissions.delete(result.clientRunId);
        // The history holds the run the connection lost as a failure that offers Retry. The run goes on until the
        // history is in, so that its caption comes once, with Retry; the connection's own caption shows without it.
        await dependencies.hydrate(true, true);
        setRunConnectionError(operationId);
        break;
      default:
        assertUnreachable(result.state);
    }
  }

  function requestRun(
    operationKind: AgentV2RunOperationKind,
    admission?: AgentV2RunAdmission,
  ) {
    const operationId = ++nextRunOperationId;
    if (admission) {
      admissionsByOperation.set(operationId, {
        admission, isApplied: false, isSupportRequest: operationKind === 'supportRequest',
      });
    }
    dependencies.dispatch({ kind: 'runRequested', operationId, operationKind });
    return operationId;
  }

  function finishRunOperation(operationId: number) {
    const isStopped = stoppedRunOperationIds.has(operationId);
    admissionsByOperation.delete(operationId);
    cancelledRunOperationIds.delete(operationId);
    stoppedRunOperationIds.delete(operationId);
    supportResendOperationIds.delete(operationId);
    revisionConflictsByOperation.delete(operationId);
    if (operationStartedByStop === operationId) operationStartedByStop = undefined;
    if (!isDisposed) {
      dependencies.dispatch({ kind: 'runSettled', operationId });
      // A stopped answer's history is read again only after the questions queued behind it have been answered
      sendQueuedMessage();
    }
    if (isStopped) isQueueAdvancedByStop = false;
    refreshStoppedAnswer();
  }

  function bindRunInputMessage(inputMessageId: string | undefined, operationId: number) {
    if (!inputMessageId) return;
    const activeAdmission = admissionsByOperation.get(operationId);
    if (!activeAdmission || activeAdmission.admission.kind === 'regenerate') return;
    const messageId = activeAdmission.admission.kind === 'append'
      ? activeAdmission.admission.messageId
      : activeAdmission.admission.targetMessageId;
    dependencies.stream.bindMessageSource(messageId, inputMessageId);
  }

  function applyRunAdmission(inputMessageId: string | undefined, operationId: number) {
    const activeAdmission = admissionsByOperation.get(operationId);
    if (!activeAdmission || activeAdmission.isApplied) return;
    const { admission } = activeAdmission;
    if (admission.kind !== 'regenerate' && !inputMessageId) return;
    activeAdmission.isApplied = true;

    switch (admission.kind) {
      case 'append':
        dependencies.stream.bindMessageSource(admission.messageId, inputMessageId!);
        break;
      case 'edit':
        pruneAdmittedMessages(admission.targetMessageId, true);
        dependencies.dispatch({
          kind: 'editRunAdmitted',
          targetMessageId: admission.targetMessageId,
          text: admission.text,
        });
        dependencies.stream.bindMessageSource(admission.targetMessageId, inputMessageId!);
        break;
      case 'regenerate':
        pruneAdmittedMessages(admission.targetMessageId, false);
        dependencies.dispatch({ kind: 'regenerateRunAdmitted', targetMessageId: admission.targetMessageId });
        break;
      default:
        assertUnreachable(admission);
    }
  }

  function pruneAdmittedMessages(targetMessageId: number, shouldRetainTarget: boolean) {
    const messages = dependencies.getState().messages;
    const targetIndex = messages.findIndex(({ id }) => id === targetMessageId);
    if (targetIndex < 0) return;
    const endIndex = shouldRetainTarget ? targetIndex + 1 : targetIndex;
    dependencies.stream.pruneMessageArtifacts(new Set(
      messages.slice(0, endIndex).map(({ id }) => id),
    ));
  }

  function retainRunAdmission(clientRunId: string, operationId: number) {
    const activeAdmission = admissionsByOperation.get(operationId);
    if (!activeAdmission || activeAdmission.isApplied || activeAdmission.isSupportRequest) return;
    retainedAdmissions.set(clientRunId, activeAdmission.admission);
  }

  function handleUpdate(update: AgentV2ClientUpdate) {
    if (isDisposed) return;
    switch (update.kind) {
      case 'runStarted': {
        const current = dependencies.getState();
        if (current.run.phase !== 'idle' && current.run.operationKind === 'supportRequest') retainedAdmissions.clear();
        const operationId = getRunOperationId(current.run);
        if (operationId !== undefined) applyRunAdmission(update.inputMessageId, operationId);
        dependencies.dispatch({
          kind: 'runStarted',
          clientRunId: update.clientRunId,
          threadId: update.threadId,
          threadRevision: update.threadRevision,
        });
        break;
      }
      case 'toolActivityChanged':
        dependencies.dispatch({
          kind: 'toolActivityChanged',
          clientRunId: update.clientRunId,
          activity: update.status === 'running'
            ? {
              kind: 'tool',
              toolName: update.toolName,
              ...(update.operation ? { operation: update.operation } : {}),
            }
            : { kind: 'preparingResponse' },
        });
        break;
      case 'runActivityChanged':
        dependencies.dispatch({
          kind: 'runActivityChanged',
          clientRunId: update.clientRunId,
          event: update.event,
        });
        break;
      case 'threadChanged':
        if (dependencies.getState().thread?.id !== update.thread.id) retainedAdmissions.clear();
        releaseStaleThreadClearOperation(update.thread, false);
        dependencies.dispatch({ kind: 'threadChanged', thread: update.thread });
        if (!update.clientRunId) requestStoppedAnswerRefresh(update.thread);
        break;
      case 'runFailed':
        handleRunFailed(update);
        break;
      case 'runCancelled':
        dependencies.dispatch({ kind: 'runCancelled', clientRunId: update.clientRunId });
        break;
      case 'availabilityChanged':
        dependencies.dispatch({ kind: 'availabilityChanged', availability: update.availability });
        break;
      case 'userQuotaChanged':
        dependencies.dispatch({ kind: 'userQuotaChanged', quota: update.quota });
        break;
      case 'messageStarted': {
        const messageId = dependencies.stream.findMessageId(update.messageId);
        if (messageId !== undefined) latestAnswer = { clientRunId: update.clientRunId, messageId };
        break;
      }
      case 'walletAuthorityChanged':
        handleWalletAuthorityChanged();
        break;
      case 'runtimeReady':
      case 'answerTablesChanged':
      case 'answerLinkAdded':
      case 'textDelta':
      case 'messageContentEnded':
      case 'followupsAvailable':
      case 'actionAvailable':
      case 'semanticContentAvailable':
      case 'messageCompleted':
      case 'walletContextChanged':
        break;
      default:
        assertUnreachable(update);
    }
    // An update can free the chat, as the end of an answer the chat follows does, or end a limit
    sendQueuedMessage();
    refreshStoppedAnswer();
  }

  // Queued questions and a run a limit held go only for the account they were asked for: once another account is
  // active, they fail, the questions with Retry. The same account's authority published again, as when its chains
  // change, keeps them waiting, and they go bound to it.
  function handleWalletAuthorityChanged() {
    const accountId = dependencies.getActiveAccountId();
    if (accountId === authorityAccountId) return;
    authorityAccountId = accountId;
    dependencies.dispatch({ kind: 'activeAccountChanged' });
    if (!dependencies.getState().queuedMessages.length) return;
    dependencies.dispatch({
      kind: 'queuedMessagesFailed',
      failure: {
        id: dependencies.stream.createLocalMessageId(),
        text: '',
        isOutgoing: false,
        timestamp: dependencies.now(),
        error: { code: 'internal_error', retryable: true },
      },
    });
  }

  function handleRunFailed(update: AgentV2RunFailedUpdate) {
    const operationId = getRunOperationId(dependencies.getState().run);
    if (
      operationId !== undefined
      && update.code === 'thread_revision_conflict'
      && !update.runId
      && !update.messageId
      && !admissionsByOperation.get(operationId)?.isApplied
      && supportResendOperationIds.delete(operationId)
    ) {
      revisionConflictsByOperation.set(operationId, update);
      return;
    }
    reportRunFailure(update);
  }

  function reportRunFailure(update: AgentV2RunFailedUpdate) {
    // A held run that a limit holds once more goes first again once that limit resets
    if (update.resetAt !== undefined && update.resetAt > dependencies.now()) {
      queueRetriedClientRunIds.delete(update.clientRunId);
    }
    const errorText = dependencies.getErrorText(update.code);
    const messageId = update.messageId ? dependencies.stream.findMessageId(update.messageId) : undefined;
    const operationId = getRunOperationId(dependencies.getState().run);
    const activeAdmission = operationId !== undefined
      ? admissionsByOperation.get(operationId)
      : undefined;
    const isPreAdmissionFailure = !update.runId && messageId === undefined;
    if (operationId !== undefined && isPreAdmissionFailure && update.retryable) {
      retainRunAdmission(update.clientRunId, operationId);
    }
    dependencies.dispatch({
      kind: 'runFailed',
      clientRunId: update.clientRunId,
      code: update.code,
      retryable: update.retryable,
      ...(messageId !== undefined ? { messageId } : {}),
      ...(update.resetAt ? {
        resetAt: update.resetAt,
        resetAtIso: new Date(update.resetAt).toISOString(),
      } : {}),
      hasRunId: Boolean(update.runId),
      ...(isPreAdmissionFailure
        && !activeAdmission?.isApplied
        && activeAdmission?.admission.kind === 'append'
        ? { optimisticMessageId: activeAdmission.admission.messageId }
        : {}),
      ...(isPreAdmissionFailure
        && !activeAdmission?.isApplied
        && activeAdmission?.admission.kind === 'regenerate'
        ? { retryMessageId: activeAdmission.admission.targetMessageId }
        : {}),
      errorText,
      timestamp: dependencies.now(),
    });
    if (update.code === 'thread_revision_conflict') {
      void dependencies.hydrate(false, true).then(() => setError(errorText));
    }
  }

  async function clearThread(thread: AgentThreadSummaryV2, operation: AgentV2ThreadClearOperation) {
    try {
      const result = await dependencies.clearThread(thread.id, thread.revision);
      if (!isThreadClearOperationActive(operation)) return;
      if (!result?.ok) {
        await failThreadClear(operation);
        return;
      }
      if (doesThreadClearOperationMatch(operation, result.value.thread)) {
        dependencies.resetHistory();
        dependencies.stream.resetMessageArtifacts();
        retainedAdmissions.clear();
      }
      dependencies.dispatch({
        kind: 'threadClearSucceeded',
        operationId: operation.operationId,
        thread: result.value.thread,
      });
    } catch {
      if (!isThreadClearOperationActive(operation)) return;
      await failThreadClear(operation);
    }
  }

  // A clear that got no answer may still have been applied, so the thread is read again while the clear still
  // blocks input. A thread with a new revision releases the clear; only one without it reports the failure.
  async function failThreadClear(operation: AgentV2ThreadClearOperation) {
    await dependencies.hydrate(true, true);
    if (!isThreadClearOperationActive(operation)) return;
    dependencies.dispatch({
      kind: 'threadClearFailed',
      operationId: operation.operationId,
      error: buildConnectionError(),
    });
  }

  function isThreadClearOperationActive(operation: AgentV2ThreadClearOperation) {
    const current = dependencies.getState().threadMutation;
    return !isDisposed
      && current.phase === 'clearing'
      && current.operationId === operation.operationId
      && current.threadId === operation.threadId
      && current.threadRevision === operation.threadRevision;
  }

  function releaseStaleThreadClearOperation(
    thread: AgentThreadSummaryV2,
    shouldMatchRevision: boolean,
  ) {
    dependencies.dispatch({ kind: 'threadMutationReconciled', thread, shouldMatchRevision });
  }

  function doesThreadClearOperationMatch(
    operation: AgentV2ThreadClearOperation,
    succeededThread: AgentThreadSummaryV2,
  ) {
    const currentThread = dependencies.getState().thread;
    return currentThread?.id === operation.threadId
      && (
        currentThread.revision === operation.threadRevision
        || (
          currentThread.id === succeededThread.id
          && currentThread.revision === succeededThread.revision
        )
      );
  }

  function setRunConnectionError(operationId: number) {
    if (isDisposed || cancelledRunOperationIds.has(operationId)) return;
    const activeAdmission = admissionsByOperation.get(operationId);
    const supportMessageId = activeAdmission?.isSupportRequest && !activeAdmission.isApplied
      && activeAdmission.admission.kind === 'append' ? activeAdmission.admission.messageId : undefined;
    dependencies.dispatch({
      kind: 'runConnectionFailed',
      operationId,
      ...(supportMessageId !== undefined ? { optimisticMessageId: supportMessageId } : {}),
      error: {
        ...buildConnectionError(),
        cause: { code: 'network_error', retryable: supportMessageId === undefined },
      },
    });
  }

  function setError(text: string) {
    if (isDisposed) return;
    dependencies.dispatch({ kind: 'errorSet', error: { text, timestamp: dependencies.now() } });
  }

  function buildConnectionError() {
    return { text: dependencies.buildConnectionError(), timestamp: dependencies.now() };
  }

  function isInputBlocked() {
    if (isDisposed) return true;
    const current = dependencies.getState();
    const composerStatus = selectAgentV2ComposerStatusForState(current, dependencies.now());
    return selectIsAgentV2InputDisabled(current, isAgentV2ComposerBlocked(composerStatus));
  }

  // Loading, a clear or a limit keep a question from being sent or queued
  function isSendBlocked() {
    if (isDisposed) return true;
    const current = dependencies.getState();
    const composerStatus = selectAgentV2ComposerStatusForState(current, dependencies.now());
    return selectIsAgentV2SendDisabled(current, isAgentV2ComposerBlocked(composerStatus));
  }
}

function assertUnreachable(value: never): never {
  throw new Error(`Unsupported Agent V2 value: ${String(value)}`);
}

/** The entry point of a question sent from one of `starterHints`; none for a hint they do not hold */
export function buildAgentV2StarterHintEntryPoint(
  starterHints: AgentV2StarterHints, hintId: string,
): AgentV2StarterHintEntryPoint | undefined {
  const hint = starterHints.items.find(({ id }) => id === hintId);
  return hint && {
    kind: 'emptyState', surface: 'agentTab', hintId: hint.id, catalogVersion: starterHints.catalogVersion,
  };
}

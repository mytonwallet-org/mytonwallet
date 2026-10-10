import type {
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
} from '../../../api/agentV2/types';
import type { AgentHint } from '../../../global/types';
import type {
  AgentV2MessagesState,
  AgentV2MessagesStateAction,
} from './agentV2MessagesState';
import type { AgentV2StreamController } from './agentV2StreamController';

import {
  isAgentV2ComposerBlocked,
  selectAgentV2ComposerStatus,
} from '../../agentV2/agentComposerStatus';
import { agentUiTrace } from './agentDevelopmentTiming';
import {
  getRunOperationId,
  selectIsAgentV2InputDisabled,
} from './agentV2MessagesState';

type AgentV2RunAdmission =
  | { kind: 'append'; messageId: number }
  | { kind: 'edit'; targetMessageId: number; text: string }
  | { kind: 'regenerate'; targetMessageId: number };

type AgentV2ActiveRunAdmission = {
  admission: AgentV2RunAdmission;
  isApplied: boolean;
};

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
  getState: () => AgentV2MessagesState;
  hydrate: (shouldPreserveLiveContent?: boolean, isFailureSilent?: boolean) => Promise<void>;
  now: () => number;
  retryRun: (clientRunId: string) => Promise<AgentV2RunResult | undefined>;
  resetHistory: NoneToVoidFunction;
  startRun: (command: AgentV2RunCommand) => Promise<AgentV2RunResult | undefined>;
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
  releaseStaleThreadClearOperation: (
    thread: AgentThreadSummaryV2,
    shouldMatchRevision: boolean,
  ) => void;
  retryAdmission: NoneToVoidFunction;
  retryMessage: (messageId: number) => void;
  sendFollowup: (messageId: number, followup: AgentPublicFollowUpV2) => void;
  sendHint: (hint: AgentHint) => void;
  sendMessage: (text: string, editMessageId?: number) => void;
}

export function createAgentV2RunController(
  dependencies: AgentV2RunControllerDependencies,
): AgentV2RunController {
  let nextRunOperationId = 0;
  let nextThreadMutationOperationId = 0;
  let isDisposed = false;
  const admissionsByOperation = new Map<number, AgentV2ActiveRunAdmission>();
  const retainedAdmissions = new Map<string, AgentV2RunAdmission>();
  const cancelledRunOperationIds = new Set<number>();

  return {
    clearChat,
    dispose,
    handleUpdate,
    isCancelledRunUpdate,
    isInputBlocked,
    releaseStaleThreadClearOperation,
    retryAdmission,
    retryMessage,
    sendFollowup,
    sendHint,
    sendMessage,
  };

  function dispose() {
    isDisposed = true;
    admissionsByOperation.clear();
    retainedAdmissions.clear();
    cancelledRunOperationIds.clear();
  }

  function sendMessage(text: string, editMessageId?: number) {
    const trimmed = text.trim();
    const thread = dependencies.getState().thread;
    if (!trimmed || !thread || isInputBlocked()) return;
    const message = dependencies.hideSecretPhrases(trimmed);

    const targetMessageId = editMessageId ? dependencies.stream.getSourceId(editMessageId) : undefined;
    if (editMessageId && !targetMessageId) return;

    if (targetMessageId) {
      void run(
        { input: { kind: 'edit', targetUserMessageId: targetMessageId, text: message } },
        { kind: 'edit', targetMessageId: editMessageId!, text: message },
      );
      return;
    }

    const outgoingMessageId = addOptimisticMessage(message);
    void run({
      input: { kind: 'append', text: message },
      entryPoint: { kind: 'agentTab' },
    }, { kind: 'append', messageId: outgoingMessageId });
  }

  function sendHint(hint: AgentHint) {
    const current = dependencies.getState();
    const sourceHint = current.hintsResponse?.items.find(({ id }) => id === hint.id);
    if (!current.thread || !current.hintsResponse || !sourceHint || isInputBlocked()) return;
    const outgoingMessageId = addOptimisticMessage(hint.prompt);
    void run({
      input: { kind: 'append', text: hint.prompt },
      entryPoint: {
        kind: 'emptyState',
        surface: 'agentTab',
        hintId: sourceHint.id,
        catalogVersion: current.hintsResponse.catalogVersion,
      },
    }, { kind: 'append', messageId: outgoingMessageId });
  }

  function sendFollowup(messageId: number, followup: AgentPublicFollowUpV2) {
    const thread = dependencies.getState().thread;
    const sourceMessageId = dependencies.stream.getSourceId(messageId);
    if (!thread || !sourceMessageId || isInputBlocked()) return;
    const { text } = followup;
    const outgoingMessageId = addOptimisticMessage(text);
    void run({
      input: { kind: 'append', text },
      followupOf: { messageId: sourceMessageId, followupId: followup.id },
    }, { kind: 'append', messageId: outgoingMessageId });
  }

  function retryMessage(messageId: number) {
    const thread = dependencies.getState().thread;
    const sourceMessageId = dependencies.stream.getSourceId(messageId);
    if (!thread || !sourceMessageId || isInputBlocked()) return;
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
    const current = dependencies.getState();
    const clientRunId = current.admissionFailure?.clientRunId
      ?? current.quotaRetry?.clientRunId
      ?? current.userRateLimit?.clientRunId;
    if (!clientRunId || isInputBlocked()) return;
    const operationId = requestRun('admissionRetry', retainedAdmissions.get(clientRunId));
    void retryAdmissionRun(clientRunId, operationId);
  }

  // A confirmed clear also cancels a running answer, whose operation then settles without presenting its result
  function clearChat() {
    const current = dependencies.getState();
    const thread = current.thread;
    if (
      isDisposed
      || !thread
      || current.isLoading
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
    dependencies.resetHistory();
    dependencies.stream.resetMessageArtifacts();
    dependencies.dispatch({ kind: 'threadClearStarted', ...operation });
    void clearThread(thread, operation);
  }

  // The runtime emits nothing for the thread's runs once it sends a clear, and no run starts while a clear or a
  // cancelled operation is pending, so a run update in that time is late output of the cancelled answer
  function isCancelledRunUpdate(update: AgentV2ClientUpdate) {
    if (update.clientRunId === undefined) return false;
    const current = dependencies.getState();
    const runOperationId = getRunOperationId(current.run);
    return current.threadMutation.phase === 'clearing'
      || (runOperationId !== undefined && cancelledRunOperationIds.has(runOperationId));
  }

  function addOptimisticMessage(text: string) {
    const timestamp = dependencies.now();
    const messageId = dependencies.stream.createLocalMessageId();
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
    const operationId = requestRun('command', admission);
    const trace = agentUiTrace();
    trace?.mark('ui_submit');
    try {
      const result = await dependencies.startRun({
        ...command,
        ...(trace ? { developmentTraceId: trace.traceId } : {}),
        threadId: thread.id,
        expectedThreadRevision: thread.revision,
      });
      await settleRunResult(result, operationId, false);
    } catch {
      setRunConnectionError(operationId);
    } finally {
      finishRunOperation(operationId);
      trace?.mark('ui_complete');
    }
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
        setRunConnectionError(operationId);
        await dependencies.hydrate(true, true);
        break;
      default:
        assertUnreachable(result.state);
    }
  }

  function requestRun(
    operationKind: 'command' | 'admissionRetry',
    admission?: AgentV2RunAdmission,
  ) {
    const operationId = ++nextRunOperationId;
    if (admission) admissionsByOperation.set(operationId, { admission, isApplied: false });
    dependencies.dispatch({ kind: 'runRequested', operationId, operationKind });
    return operationId;
  }

  function finishRunOperation(operationId: number) {
    admissionsByOperation.delete(operationId);
    cancelledRunOperationIds.delete(operationId);
    if (!isDisposed) dependencies.dispatch({ kind: 'runSettled', operationId });
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
    if (!activeAdmission || activeAdmission.isApplied) return;
    retainedAdmissions.set(clientRunId, activeAdmission.admission);
  }

  function handleUpdate(update: AgentV2ClientUpdate) {
    if (isDisposed) return;
    switch (update.kind) {
      case 'runStarted': {
        const operationId = getRunOperationId(dependencies.getState().run);
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
      case 'runtimeReady':
      case 'messageStarted':
      case 'answerTablesChanged':
      case 'answerLinkAdded':
      case 'textDelta':
      case 'messageContentEnded':
      case 'followupsAvailable':
      case 'actionAvailable':
      case 'semanticContentAvailable':
      case 'messageCompleted':
      case 'walletAuthorityChanged':
      case 'walletContextChanged':
        break;
      default:
        assertUnreachable(update);
    }
  }

  function handleRunFailed(update: Extract<AgentV2ClientUpdate, { kind: 'runFailed' }>) {
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
    dependencies.dispatch({
      kind: 'runConnectionFailed',
      operationId,
      error: {
        ...buildConnectionError(),
        cause: { code: 'network_error', retryable: true },
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
    const composerStatus = selectAgentV2ComposerStatus(
      current.availability,
      current.userQuota,
      current.quotaRetry,
      current.userRateLimit,
      dependencies.now(),
    );
    return selectIsAgentV2InputDisabled(current, isAgentV2ComposerBlocked(composerStatus));
  }
}

function assertUnreachable(value: never): never {
  throw new Error(`Unsupported Agent V2 value: ${String(value)}`);
}

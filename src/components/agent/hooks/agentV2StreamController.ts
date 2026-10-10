import type {
  AgentPersistedActionV2,
  AgentV2LiveAction,
} from '../../../api/agentV2/protocol/types';
import type {
  AgentV2ActionPresentation,
  AgentV2ClientUpdate,
  AgentV2HydratedMessage,
} from '../../../api/agentV2/types';
import type { AgentMessage } from '../../../global/types';
import type {
  AgentV2MessagesState,
  AgentV2MessagesStateAction,
  AgentV2NormalizedMessageEntry,
} from './agentV2MessagesState';
import type { TextRevealPresentations } from './textRevealPresentation';

import { agentUiTrace } from './agentDevelopmentTiming';
import { findAgentV2MessageId } from './agentV2MessagesState';
import {
  createTextRevealPresentation,
  updateTextRevealPresentation,
} from './textRevealPresentation';

type SetTextRevealPresentations = (
  update: (current: TextRevealPresentations) => TextRevealPresentations,
) => void;

export interface AgentV2StreamControllerDependencies {
  cancelFrame: (frameId: number) => void;
  dispatch: (action: AgentV2MessagesStateAction) => void;
  getActionPresentation: (
    sourceId: string,
    actionId: string,
  ) => Promise<AgentV2ActionPresentation | undefined>;
  getState: () => AgentV2MessagesState;
  now: () => number;
  requestFrame: (callback: () => void) => number;
  setTextRevealPresentations: SetTextRevealPresentations;
}

export interface AgentV2StreamController {
  advanceTextRevealGeneration: NoneToVoidFunction;
  bindMessageSource: (messageId: number, sourceId: string) => void;
  createLocalMessageId: () => number;
  consumeTextRevealSession: (messageId: number, key: string) => void;
  dispose: NoneToVoidFunction;
  flushDeltas: NoneToVoidFunction;
  getActionLifecycleGeneration: () => number;
  getActionPresentationGeneration: () => number;
  findMessageId: (sourceId: string) => number | undefined;
  getMessageId: (sourceId: string) => number;
  getSourceId: (messageId: number) => string | undefined;
  handleUpdate: (update: AgentV2ClientUpdate) => void;
  invalidateActionPresentations: NoneToVoidFunction;
  loadSendActionPresentations: (messages: AgentV2HydratedMessage[], generation: number) => void;
  mapPersistedMessageEntry: (message: AgentV2HydratedMessage) => AgentV2NormalizedMessageEntry;
  pruneMessageArtifacts: (retainedMessageIds: Set<number>) => void;
  resetMessageArtifacts: NoneToVoidFunction;
  setActionPresentation: (
    sourceId: string,
    actionId: string,
    presentation: AgentV2ActionPresentation,
    generation?: number,
  ) => void;
  settleTextRevealSession: (messageId: number, key: string) => void;
  terminalizeTextRevealPresentations: (sourceId?: string) => void;
}

export function createAgentV2StreamController(
  dependencies: AgentV2StreamControllerDependencies,
): AgentV2StreamController {
  const pendingDeltas = new Map<string, string>();
  const textFrameTraces = new Set<string>();
  let nextMessageId = 1;
  let actionLifecycleGeneration = 0;
  let actionPresentationGeneration = 0;
  let textRevealGeneration = 0;
  let textRevealSequence = 0;
  let deltaFrameId: number | undefined;
  let isDisposed = false;

  return {
    advanceTextRevealGeneration: () => {
      textRevealGeneration += 1;
    },
    bindMessageSource,
    createLocalMessageId,
    consumeTextRevealSession,
    dispose,
    flushDeltas,
    findMessageId: (sourceId) => findAgentV2MessageId(dependencies.getState(), sourceId),
    getActionLifecycleGeneration: () => actionLifecycleGeneration,
    getActionPresentationGeneration: () => actionPresentationGeneration,
    getMessageId,
    getSourceId: (messageId) => dependencies.getState().sourceIdByMessageId[messageId],
    handleUpdate,
    invalidateActionPresentations,
    loadSendActionPresentations,
    mapPersistedMessageEntry,
    pruneMessageArtifacts,
    resetMessageArtifacts,
    setActionPresentation,
    settleTextRevealSession,
    terminalizeTextRevealPresentations,
  };

  function dispose() {
    if (isDisposed) return;
    isDisposed = true;
    invalidateActionPresentations();
    if (deltaFrameId !== undefined) dependencies.cancelFrame(deltaFrameId);
    deltaFrameId = undefined;
    pendingDeltas.clear();
  }

  function handleUpdate(update: AgentV2ClientUpdate) {
    const trace = update.developmentTraceId ? agentUiTrace(update.developmentTraceId) : undefined;
    trace?.markOnce('ui_update_received');
    if (isDisposed) return;
    switch (update.kind) {
      case 'runtimeReady':
        invalidateActionPresentations();
        break;
      case 'messageStarted':
        dependencies.dispatch({
          kind: 'messageStarted',
          clientRunId: update.clientRunId,
          message: {
            id: getMessageId(update.messageId),
            text: '',
            isOutgoing: false,
            timestamp: dependencies.now(),
            isStreaming: true,
            ...(update.responseLanguage ? { responseLanguage: update.responseLanguage } : {}),
          },
        });
        break;
      case 'textDelta':
        appendTextDelta(update.messageId, update.delta);
        if (trace && !textFrameTraces.has(trace.traceId)) {
          textFrameTraces.add(trace.traceId);
          if (textFrameTraces.size > 32) textFrameTraces.delete(textFrameTraces.values().next().value!);
          dependencies.requestFrame(() => {
            trace.markOnce('ui_text_committed');
            dependencies.requestFrame(() => trace.markOnce('ui_text_frame'));
          });
        }
        break;
      case 'messageContentEnded':
        flushDeltas();
        dependencies.dispatch({
          kind: 'messageContentEnded',
          messageId: getMessageId(update.messageId),
        });
        break;
      case 'followupsAvailable':
        dependencies.dispatch({
          kind: 'followupsAvailable',
          messageId: getMessageId(update.messageId),
          items: update.items,
        });
        break;
      case 'actionAvailable':
        dependencies.dispatch({
          kind: 'actionAvailable',
          messageId: getMessageId(update.messageId),
          action: update.action,
        });
        if (update.action.kind === 'send') {
          void loadActionPresentation(
            update.messageId,
            update.action.id,
            actionPresentationGeneration,
          );
        }
        break;
      case 'answerTablesChanged':
        flushDeltas();
        dependencies.dispatch({ kind: 'answerTablesChanged', messageId: getMessageId(update.messageId),
          tables: update.tables, tableReferences: update.tableReferences });
        break;
      case 'answerLinkAdded':
        flushDeltas();
        dependencies.dispatch({ kind: 'answerLinkAdded', messageId: getMessageId(update.messageId),
          link: update.link });
        break;
      case 'semanticContentAvailable':
        dependencies.dispatch({
          kind: 'semanticContentAvailable',
          messageId: getMessageId(update.messageId),
          content: update.content,
        });
        break;
      case 'messageCompleted':
        flushDeltas();
        dependencies.dispatch({
          kind: 'messageCompleted',
          clientRunId: update.clientRunId,
          messageId: getMessageId(update.messageId),
          finishReason: update.finishReason,
        });
        break;
      case 'threadChanged':
        if (dependencies.getState().thread?.id !== update.thread.id) resetMessageArtifacts();
        break;
      case 'runFailed':
        flushDeltas();
        terminalizeTextRevealPresentations(update.messageId);
        break;
      case 'runCancelled':
        flushDeltas();
        terminalizeTextRevealPresentations();
        break;
      case 'walletAuthorityChanged':
        if (!update.threadId || dependencies.getState().thread?.id === update.threadId) {
          advanceActionPresentationGeneration();
          dependencies.dispatch({ kind: 'walletAuthorityChanged', threadId: update.threadId });
          reloadSendActionPresentations(actionPresentationGeneration);
          break;
        }
        dependencies.dispatch({ kind: 'walletAuthorityChanged', threadId: update.threadId });
        break;
      case 'walletContextChanged':
        advanceActionPresentationGeneration();
        dependencies.dispatch({ kind: 'walletContextChanged' });
        reloadSendActionPresentations(actionPresentationGeneration);
        break;
      case 'runStarted':
      case 'toolActivityChanged':
      case 'runActivityChanged':
      case 'availabilityChanged':
      case 'userQuotaChanged':
        break;
      default:
        assertUnreachable(update);
    }
  }

  function appendTextDelta(sourceId: string, delta: string) {
    const messageId = getMessageId(sourceId);
    ensureTextRevealPresentation(messageId);
    pendingDeltas.set(sourceId, `${pendingDeltas.get(sourceId) ?? ''}${delta}`);
    if (deltaFrameId !== undefined) return;
    deltaFrameId = dependencies.requestFrame(() => {
      deltaFrameId = undefined;
      flushDeltas();
    });
  }

  function ensureTextRevealPresentation(messageId: number) {
    textRevealSequence += 1;
    const presentation = createTextRevealPresentation(
      textRevealGeneration,
      messageId,
      textRevealSequence,
    );
    dependencies.setTextRevealPresentations((current) => current[messageId] ? current : {
      ...current,
      [messageId]: presentation,
    });
  }

  function flushDeltas() {
    if (!pendingDeltas.size) return;
    const deltas = [...pendingDeltas].flatMap(([sourceId, delta]) => {
      const messageId = findAgentV2MessageId(dependencies.getState(), sourceId);
      return messageId === undefined ? [] : [[messageId, delta] as [number, string]];
    });
    pendingDeltas.clear();
    dependencies.dispatch({ kind: 'textDeltasFlushed', deltas });
  }

  function consumeTextRevealSession(messageId: number, key: string) {
    dependencies.setTextRevealPresentations((current) => updateTextRevealPresentation(
      current,
      messageId,
      key,
      { shouldRevealFromStart: false },
    ));
  }

  function settleTextRevealSession(messageId: number, key: string) {
    dependencies.setTextRevealPresentations((current) => updateTextRevealPresentation(
      current,
      messageId,
      key,
      { status: 'settled', shouldRevealFromStart: false },
    ));
  }

  function terminalizeTextRevealPresentations(sourceId?: string) {
    const messageId = sourceId ? findAgentV2MessageId(dependencies.getState(), sourceId) : undefined;
    dependencies.setTextRevealPresentations((current) => Object.fromEntries(
      Object.entries(current).map(([currentMessageId, presentation]) => {
        const shouldFail = messageId !== undefined
          ? Number(currentMessageId) === messageId
          : presentation.status === 'active';
        return [currentMessageId, shouldFail ? {
          ...presentation,
          status: 'error',
          shouldRevealFromStart: false,
        } : presentation];
      }),
    ));
  }

  function mapPersistedMessageEntry(message: AgentV2HydratedMessage): AgentV2NormalizedMessageEntry {
    return { message: mapPersistedMessage(message), sourceId: message.id };
  }

  function mapPersistedMessage(message: AgentV2HydratedMessage): AgentMessage {
    const text = message.content?.kind === 'markdown' ? message.content.text : '';
    const semanticContent = message.content?.kind === 'semantic' ? message.content.content : undefined;
    const actionPresentations: Record<string, AgentV2ActionPresentation> = Object.fromEntries(
      message.actions
        ?.filter((action) => action.kind === 'send')
        .map((action) => [action.id, { kind: 'inactive' }]) ?? [],
    );
    return {
      id: getMessageId(message.id),
      text,
      isOutgoing: message.role === 'user',
      timestamp: new Date(message.createdAt).getTime(),
      ...(message.responseLanguage ? { responseLanguage: message.responseLanguage } : {}),
      ...(semanticContent ? { semanticContent } : {}),
      ...(message.content?.kind === 'markdown' && message.content.tables ? {
        tables: message.content.tables, tableReferences: message.content.tableReferences,
      } : {}),
      ...(message.content?.kind === 'markdown' && message.content.links?.length
        ? { links: message.content.links } : {}),
      ...(message.actions?.length ? { actions: message.actions } : {}),
      ...(Object.keys(actionPresentations).length ? { actionPresentations } : {}),
      ...(message.followups?.length ? { followups: message.followups } : {}),
      ...(message.error ? { error: message.error } : {}),
      ...(message.error?.retryable ? { isRetryAvailable: true } : {}),
    };
  }

  function createLocalMessageId() {
    const current = dependencies.getState();
    for (const { id } of current.messages) nextMessageId = Math.max(nextMessageId, id + 1);
    for (const id in current.sourceIdByMessageId) nextMessageId = Math.max(nextMessageId, Number(id) + 1);
    return nextMessageId++;
  }

  function getMessageId(sourceId: string) {
    const existingId = findAgentV2MessageId(dependencies.getState(), sourceId);
    if (existingId !== undefined) return existingId;
    const messageId = createLocalMessageId();
    dependencies.dispatch({ kind: 'messageSourceReserved', messageId, sourceId });
    return messageId;
  }

  function bindMessageSource(messageId: number, sourceId: string) {
    dependencies.dispatch({ kind: 'messageSourceBound', messageId, sourceId });
  }

  function pruneMessageArtifacts(retainedMessageIds: Set<number>) {
    for (const sourceId of pendingDeltas.keys()) {
      const messageId = findAgentV2MessageId(dependencies.getState(), sourceId);
      if (messageId === undefined || !retainedMessageIds.has(messageId)) pendingDeltas.delete(sourceId);
    }
    dependencies.dispatch({ kind: 'messageSourcesPruned', retainedMessageIds });
    dependencies.setTextRevealPresentations((current) => Object.fromEntries(
      Object.entries(current).filter(([messageId]) => retainedMessageIds.has(Number(messageId))),
    ));
  }

  function resetMessageArtifacts() {
    if (deltaFrameId !== undefined) dependencies.cancelFrame(deltaFrameId);
    deltaFrameId = undefined;
    dependencies.dispatch({ kind: 'messageSourcesReset' });
    nextMessageId = 1;
    pendingDeltas.clear();
    invalidateActionPresentations();
    textRevealGeneration += 1;
    dependencies.setTextRevealPresentations(() => ({}));
  }

  function invalidateActionPresentations() {
    actionLifecycleGeneration += 1;
    advanceActionPresentationGeneration();
  }

  function advanceActionPresentationGeneration() {
    actionPresentationGeneration += 1;
  }

  function loadSendActionPresentations(messages: AgentV2HydratedMessage[], generation: number) {
    messages.forEach((message) => message.actions?.forEach((action) => {
      if (action.kind === 'send') void loadActionPresentation(message.id, action.id, generation);
    }));
  }

  function reloadSendActionPresentations(generation: number) {
    dependencies.getState().messages.forEach((message) => {
      const sourceId = dependencies.getState().sourceIdByMessageId[message.id];
      if (!sourceId) return;
      message.actions?.forEach((action) => {
        if (action.kind === 'send') void loadActionPresentation(sourceId, action.id, generation);
      });
    });
  }

  async function loadActionPresentation(sourceId: string, actionId: string, generation: number) {
    let presentation: AgentV2ActionPresentation | undefined;
    try {
      presentation = await dependencies.getActionPresentation(sourceId, actionId);
    } catch {
      presentation = undefined;
    }
    if (isDisposed || generation !== actionPresentationGeneration) return;
    setActionPresentation(sourceId, actionId, presentation ?? { kind: 'inactive' }, generation);
  }

  function setActionPresentation(
    sourceId: string,
    actionId: string,
    presentation: AgentV2ActionPresentation,
    generation = actionPresentationGeneration,
  ) {
    const messageId = findAgentV2MessageId(dependencies.getState(), sourceId);
    if (generation !== actionPresentationGeneration || messageId === undefined) return;
    dependencies.dispatch({ kind: 'actionPresentationChanged', messageId, actionId, presentation });
  }
}

function assertUnreachable(value: never): never {
  throw new Error(`Unsupported Agent V2 update: ${String(value)}`);
}

export type AgentV2SendAction = Extract<
  AgentV2LiveAction | AgentPersistedActionV2,
  { kind: 'send' }
>;

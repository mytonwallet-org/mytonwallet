import type { AgentV2ClientUpdate } from '../api/agentV2/types';

type Listener = (update: AgentV2ClientUpdate) => void;
type RuntimeReadyListener = (generation: number) => void;
type RuntimeReadyUpdate = Extract<AgentV2ClientUpdate, { kind: 'runtimeReady' }>;

const MAX_REPLAY_UPDATES_PER_RUN = 32;
const MAX_REPLAY_TEXT_LENGTH = 1_048_576;

interface ActiveRunReplay {
  updates: AgentV2ClientUpdate[];
  isTextOverflowed: boolean;
}

const listeners = new Set<Listener>();
const runtimeReadyListeners = new Set<RuntimeReadyListener>();
const activeRunReplays = new Map<string, ActiveRunReplay>();
let latestRuntimeReadyUpdate: RuntimeReadyUpdate | undefined;

export function subscribeToAgentV2Updates(listener: Listener) {
  listeners.add(listener);
  if (latestRuntimeReadyUpdate) listener(latestRuntimeReadyUpdate);
  activeRunReplays.forEach(({ updates }) => {
    updates.forEach(listener);
  });
  return () => listeners.delete(listener);
}

export function getLatestAgentV2RuntimeGeneration() {
  return latestRuntimeReadyUpdate?.generation;
}

export function subscribeToAgentV2RuntimeReady(listener: RuntimeReadyListener) {
  runtimeReadyListeners.add(listener);
  return () => runtimeReadyListeners.delete(listener);
}

export function publishAgentV2Update(update: AgentV2ClientUpdate) {
  if (update.kind === 'runtimeReady') {
    latestRuntimeReadyUpdate = update;
    cancelAgentV2ActiveRunReplays();
    runtimeReadyListeners.forEach((listener) => listener(update.generation));
  }
  recordActiveRunUpdate(update);
  listeners.forEach((listener) => listener(update));
  const terminalRunId = getTerminalRunId(update);
  if (terminalRunId) activeRunReplays.delete(terminalRunId);
}

export function cancelAgentV2ActiveRunReplays() {
  const cancellations = [...activeRunReplays.values()].flatMap(({ updates }) => {
    const started = updates.find((update) => update.kind === 'runStarted');
    return started ? [{
      kind: 'runCancelled' as const,
      clientRunId: started.clientRunId,
      runId: started.runId,
      threadId: started.threadId,
    }] : [];
  });
  activeRunReplays.clear();
  cancellations.forEach((update) => {
    listeners.forEach((listener) => listener(update));
  });
}

function recordActiveRunUpdate(update: AgentV2ClientUpdate) {
  if (update.kind === 'runStarted') {
    activeRunReplays.set(update.runId, { updates: [update], isTextOverflowed: false });
    return;
  }
  const runId = getRunId(update);
  if (!runId || getTerminalRunId(update)) return;
  const replay = activeRunReplays.get(runId);
  if (!replay) return;

  const index = findReplaceableUpdate(replay.updates, update);
  if (update.kind === 'textDelta') {
    if (replay.isTextOverflowed) return;
    const previous = index >= 0 ? replay.updates[index] : undefined;
    const delta = previous?.kind === 'textDelta' ? `${previous.delta}${update.delta}` : update.delta;
    if (delta.length > MAX_REPLAY_TEXT_LENGTH) {
      replay.isTextOverflowed = true;
      replay.updates = replay.updates.filter((candidate) => candidate.kind !== 'textDelta');
      return;
    }
    update = { ...update, delta };
  }

  if (index >= 0) {
    replay.updates[index] = update;
  } else if (replay.updates.length < MAX_REPLAY_UPDATES_PER_RUN || update.kind === 'answerLinkAdded') {
    // Links add up instead of replacing each other; the SDK bounds them per message
    replay.updates.push(update);
  }
}

function findReplaceableUpdate(updates: AgentV2ClientUpdate[], update: AgentV2ClientUpdate) {
  return updates.findIndex((candidate) => {
    if (candidate.kind !== update.kind) return false;
    switch (update.kind) {
      case 'messageStarted':
      case 'textDelta':
      case 'messageContentEnded':
      case 'followupsAvailable':
      case 'answerTablesChanged':
      case 'semanticContentAvailable':
        return candidate.kind === update.kind && candidate.messageId === update.messageId;
      case 'toolActivityChanged':
        return candidate.kind === update.kind && candidate.toolCallId === update.toolCallId;
      case 'actionAvailable':
        return candidate.kind === update.kind
          && candidate.messageId === update.messageId
          && candidate.action.id === update.action.id;
      case 'threadChanged':
        return Boolean(candidate.runId);
      default:
        return false;
    }
  });
}

function getRunId(update: AgentV2ClientUpdate) {
  return typeof update.runId === 'string' ? update.runId : undefined;
}

function getTerminalRunId(update: AgentV2ClientUpdate) {
  const runId = getRunId(update);
  return runId && (
    update.kind === 'messageCompleted'
    || update.kind === 'runFailed'
    || update.kind === 'runCancelled'
  ) ? runId : undefined;
}

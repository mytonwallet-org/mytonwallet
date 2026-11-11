import type { AgentThreadSummaryV2 } from '../../api/agentV2/protocol/types';
import type { AgentMessage } from '../../global/types';
import type { ReadRecord, StoredReadState } from '../../util/agent/agentV2LocalState';

import {
  AGENT_THREAD_READ_STATE_STORAGE_KEY as STORAGE_KEY,
  agentThreadReadStateListeners as listeners,
  getAgentV2LocalState,
} from '../../util/agent/agentV2LocalState';

/**
 * Which chats hold an answer the user has not seen, for the chat list's unread dot. It belongs to this device, as on
 * mobile.
 *
 * An answer that completes while its chat is off screen marks the chat, and so does a chat whose message count grows
 * past the count the list saw after the user last left it. Showing the chat clears both. Operator replies newer than
 * the latest operator reply shown locally also mark the chat. Message counts alone leave chats this device has never
 * shown read.
 */

/**
 * Where the messages the user has not seen start in a chat: the position of the first of them from the chat's first
 * message, or its latest answer when an answer completed while the chat was off screen
 */
export type AgentThreadUnreadStart = number | 'latestAnswer';

// Records beyond this many, the oldest first, are dropped: those chats count as read again
const RECORD_LIMIT = 500;

export function getIsAgentThreadUnread(thread: AgentThreadSummaryV2) {
  const isShown = getAgentV2LocalState().shownThreadCounts.has(thread.id);
  if (isShown && document.visibilityState === 'visible') return false;
  const record = getState().records[thread.id];
  if (thread.support?.lastOperatorMessageAt
    && Date.parse(thread.support.lastOperatorMessageAt) > (record?.seenAt ?? 0)) return true;
  if (isShown) return false;

  if (!record) return false;
  if (record.isMarkedUnread) return true;
  if (record.isBaselineNeeded || record.seenMessageCount === undefined) return false;

  return thread.messageCount > record.seenMessageCount;
}

/** Where the messages that make the chat unread start, or nothing for a chat the list shows as read */
export function getAgentThreadUnreadStart(thread: AgentThreadSummaryV2): AgentThreadUnreadStart | undefined {
  if (!getIsAgentThreadUnread(thread)) return undefined;

  const record = getState().records[thread.id];
  return !record || record.isMarkedUnread || record.seenMessageCount === undefined
    || thread.messageCount <= record.seenMessageCount
    ? 'latestAnswer' : record.seenMessageCount;
}

/**
 * The first message the user has not seen among the latest `messages` of a chat of `messageCount` stored messages,
 * with its position from the chat's first message. Counting from the end leaves out failures the chat shows of its
 * own, which are not stored. Messages beyond those loaded start at the first one loaded.
 */
export function findAgentThreadFirstUnreadMessage(
  messages: AgentMessage[], messageCount: number, unreadStart: AgentThreadUnreadStart,
) {
  // The thread's message count leaves out the lines about support, as it does the chat's own failures
  const storedMessages = messages.filter(({ failureText, supportEvent }) => !failureText && !supportEvent);
  const index = unreadStart === 'latestAnswer'
    ? findLatestAnswerIndex(storedMessages)
    : Math.max(0, storedMessages.length - (messageCount - unreadStart));

  const message = storedMessages[index];
  return message && { messageId: message.id, position: messageCount - (storedMessages.length - index) };
}

// The first answer after the last question, or the last answer when no question comes after one
function findLatestAnswerIndex(messages: AgentMessage[]) {
  let index = messages.length - 1;
  while (index >= 0 && messages[index].isOutgoing) index--;
  while (index > 0 && !messages[index - 1].isOutgoing) index--;
  return index;
}

/** Call as a chat comes on screen; while it is on screen it stays read */
export function markAgentThreadShown(threadId: string) {
  const shownCounts = getAgentV2LocalState().shownThreadCounts;
  shownCounts.set(threadId, (shownCounts.get(threadId) ?? 0) + 1);
  markSeen(threadId);
}

export function markAgentThreadHidden(threadId: string) {
  const shownCounts = getAgentV2LocalState().shownThreadCounts;
  const count = shownCounts.get(threadId);
  if (count === undefined) return;

  if (count > 1) {
    shownCounts.set(threadId, count - 1);
  } else {
    shownCounts.delete(threadId);
  }
  markSeen(threadId);
}

export function markAgentThreadSupportSeen(threadId: string, lastOperatorMessageAt: string) {
  if (document.visibilityState !== 'visible') return;
  const record = getState().records[threadId];
  const operatorMessageAt = Date.parse(lastOperatorMessageAt);
  if (operatorMessageAt <= (record?.seenAt ?? 0)) return;

  storeRecord(threadId, {
    ...(record ?? { isBaselineNeeded: true, isMarkedUnread: false }),
    seenAt: operatorMessageAt,
  });
  save(true);
}

/** An answer completed in the chat; off screen, the chat gets the dot */
export function markAgentThreadAnswerCompleted(threadId: string) {
  if (getAgentV2LocalState().shownThreadCounts.has(threadId) || getState().records[threadId]?.isMarkedUnread) return;

  const record = getState().records[threadId] ?? { isBaselineNeeded: false, isMarkedUnread: false };
  storeRecord(threadId, { ...record, isMarkedUnread: true });
  save(true);
}

/**
 * Takes the listed counts as seen for chats the user has left and that no longer answer, and for chats listed for the
 * first time, so that only what arrives later marks them
 */
export function observeAgentThreadCounts(threads: AgentThreadSummaryV2[], answeringThreadIds: Set<string>) {
  const { records } = getState();
  const shownCounts = getAgentV2LocalState().shownThreadCounts;
  let hasChanged = false;
  threads.forEach(({ id, messageCount }) => {
    if (answeringThreadIds.has(id) || shownCounts.has(id)) return;

    const record = records[id] ?? { isBaselineNeeded: true, isMarkedUnread: false };
    if (!record.isBaselineNeeded) return;

    storeRecord(id, { ...record, isBaselineNeeded: false, seenMessageCount: messageCount });
    hasChanged = true;
  });

  if (hasChanged) save(false);
}

export function forgetAgentThreadReadState(threadId: string) {
  const current = getState();
  if (!current.records[threadId]) return;

  const { [threadId]: removed, ...records } = current.records;
  getAgentV2LocalState().threadReadState = { records, order: current.order.filter((id) => id !== threadId) };
  save(true);
}

export function subscribeToAgentThreadReadState(listener: NoneToVoidFunction) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function markSeen(threadId: string) {
  const record = getState().records[threadId];
  if (record?.isBaselineNeeded && !record.isMarkedUnread) return;

  storeRecord(threadId, {
    seenMessageCount: record?.seenMessageCount, seenAt: record?.seenAt, isBaselineNeeded: true, isMarkedUnread: false,
  });
  save(true);
}

function storeRecord(threadId: string, record: ReadRecord) {
  const current = getState();
  const order = [...current.order.filter((id) => id !== threadId), threadId];
  const records = { ...current.records, [threadId]: record };
  order.splice(0, Math.max(0, order.length - RECORD_LIMIT)).forEach((id) => {
    delete records[id];
  });
  getAgentV2LocalState().threadReadState = { records, order };
}

function getState() {
  const localState = getAgentV2LocalState();
  localState.threadReadState ??= readState();
  return localState.threadReadState;
}

function readState(): StoredReadState {
  try {
    const json = localStorage.getItem(STORAGE_KEY);
    const stored = json ? JSON.parse(json) as Partial<StoredReadState> : undefined;
    if (stored?.records && Array.isArray(stored.order)) {
      const { records } = stored;
      return { records, order: stored.order.filter((id) => records[id]) };
    }
  } catch {
    // An unreadable record counts every chat as read
  }

  return { records: {}, order: [] };
}

function save(shouldNotify: boolean) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(getAgentV2LocalState().threadReadState));
  } catch {
    // Without storage the dots last until the next launch
  }

  if (shouldNotify) listeners.forEach((listener) => listener());
}

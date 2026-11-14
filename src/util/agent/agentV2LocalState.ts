import type { AgentThreadSummaryV2 } from '../../api/agentV2/protocol/types';
import type { AgentConversationSession } from '../../components/agent/AgentConversationShell';
import type { AgentV2CachedChat, AgentV2FailedQueue } from '../../components/agent/hooks/agentV2MessagesState';
import type {
  AgentV2HeldLimitRun, AgentV2StarterHintEntryPoint,
} from '../../components/agent/hooks/agentV2RunController';
import type {
  AgentV2ChatTarget, AgentV2DiscussionThreadResolution,
} from '../../components/agent/hooks/useAgentV2Messages';
import type { AgentNewsFeedView } from '../../components/agentV2/agentNewsFeedView';
import type { AgentThreadUnreadStart } from '../../components/agentV2/agentThreadReadState';
import type { AgentMessage } from '../../global/types';

import { throttleWithTickEnd } from '../schedulers';

export interface ChatSelection {
  /** Remounts the chat for each chat the user opens */
  key: number;
  target: AgentV2ChatTarget;
  /** Known once the chat resolves a new or default target */
  threadId?: string;
  /** The list's copy of the thread, which names the chat before its history loads */
  thread?: AgentThreadSummaryV2;
  initialMessage?: string;
  /** The starter hint `initialMessage` is the title of */
  initialHintEntryPoint?: AgentV2StarterHintEntryPoint;
  shouldRequestSupport?: boolean;
  /** The news whose discussion this is, when the user opened it from the feed; back gives the focus to its card */
  newsEventId?: number;
  /** The digest whose headline opened the discussion of [newsEventId]; back returns to the digest */
  newsDigestId?: string;
  /** Where the messages the user had not seen started as the chat opened; the "New" line stays there */
  unreadStart?: AgentThreadUnreadStart;
  /** A cached list row leaves the unread position unknown until fresh history loads */
  isUnreadStateUnknown?: boolean;
}

export interface FeedSelection {
  /** Remounts the feed each time it opens, so that it scrolls to where it opens again */
  key: number;
}

export interface ReadRecord {
  /** The message count the list saw once the user had left the chat and it stopped answering */
  seenMessageCount?: number;
  seenAt?: number;
  /** The user left the chat, and the list has not yet seen its count with the answer settled */
  isBaselineNeeded: boolean;
  isMarkedUnread: boolean;
}

export interface StoredReadState {
  records: Record<string, ReadRecord>;
  /** Thread ids in the order their records last changed, oldest first */
  order: string[];
}

interface AgentV2LocalState {
  /** The question typed under the list, kept for its next mount */
  draftOnMount: string;
  /** How the list was left as the app switched layouts */
  switchedLayoutOnMount?: { isComposing: boolean; isInputFocused: boolean; scrollTop: number };
  /** The chat and feed open when the section unmounted, also carried across the phone breakpoint */
  openChatOnMount?: ChatSelection;
  openParentChatOnMount?: ChatSelection;
  openFeedOnMount?: FeedSelection;
  /** The draft and place in the conversation of the open chat */
  chatSessionOnMount?: { chatKey: number; session: AgentConversationSession };
  /** The place in each view of the open news feed */
  feedSessionsOnMount?: { feedKey: number; sessions: Partial<Record<AgentNewsFeedView, AgentConversationSession>> };
  /** The consent known as the app switched layouts */
  isConsentAcceptedOnSwitch?: boolean;
  threadReadState?: StoredReadState;
  shownThreadCounts: Map<string, number>;
  /** The chats shown last, oldest first, which open again at once with the history they had */
  recentChats: Map<string, AgentV2CachedChat>;
  /**
   * The chats left with questions queued, by thread, which go on sending them until done or taken over, and those
   * that hold questions a wallet switch failed until the chat opens again
   */
  backgroundQueues: Map<string, AgentV2BackgroundQueue>;
  /**
   * The threads feed discussions are creating for their first question, by the news or digest discussed, which a
   * discussion opened again from the feed follows until the question is sent
   */
  pendingDiscussionThreads: Map<string, AgentV2DiscussionThreadResolution>;
  pendingThreadDeletionIds: Set<string>;
  /** Threads deleted here, whose chats send nothing more once left */
  deletedThreadIds: Set<string>;
}

/** The queue of a chat that has been left */
export interface AgentV2BackgroundQueue {
  /** Sends the next question once a failed deletion releases the queue */
  resume: NoneToVoidFunction;
  /** Hands over queued and failed questions once its pending admission has ended or its run can be followed */
  take: () => AgentV2LeftQueue | undefined;
  /** The opening question of a news or digest discussion has not been admitted or handed over to the ordinary queue */
  hasOpeningQuestion: () => boolean;
  /** Nothing is queued or being answered */
  isDone: () => boolean;
  /** Questions a wallet switch failed wait for the chat to open again */
  hasFailures: () => boolean;
  /** The chat lets go of its controllers, sending nothing more */
  dispose: NoneToVoidFunction;
}

interface AgentV2LeftQueue {
  queuedMessages: AgentMessage[];
  failedQueue?: AgentV2FailedQueue;
  heldRun?: AgentV2HeldLimitRun;
}

export const AGENT_THREAD_READ_STATE_STORAGE_KEY = 'mytonwallet-agent-thread-read-state';
// As many recent chats as iOS keeps loaded
const RECENT_CHAT_LIMIT = 8;
export const agentThreadReadStateListeners = new Set<NoneToVoidFunction>();
export const agentThreadListListeners = new Set<(threads: AgentThreadSummaryV2[]) => void>();
export const agentV2BackgroundQueueListeners = new Set<NoneToVoidFunction>();

let localState: AgentV2LocalState = createLocalState();

export function getAgentV2LocalState() {
  return localState;
}

export function getRecentAgentChat(threadId: string) {
  return localState.recentChats.get(threadId);
}

export function keepRecentAgentChat(chat: AgentV2CachedChat) {
  const { recentChats } = localState;
  recentChats.delete(chat.thread.id);
  recentChats.set(chat.thread.id, chat);
  if (recentChats.size > RECENT_CHAT_LIMIT) recentChats.delete(recentChats.keys().next().value!);
}

export function forgetRecentAgentChat(threadId: string) {
  localState.recentChats.delete(threadId);
}

export function keepAgentV2QueueInBackground(threadId: string, queue: AgentV2BackgroundQueue) {
  const { backgroundQueues, deletedThreadIds } = localState;
  backgroundQueues.get(threadId)?.dispose();
  if (deletedThreadIds.has(threadId)) {
    backgroundQueues.delete(threadId);
    queue.dispose();
    return;
  }
  backgroundQueues.set(threadId, queue);
  queue.resume();
}

export function holdAgentV2BackgroundQueue(threadId: string) {
  localState.pendingThreadDeletionIds.add(threadId);
}

export function isAgentV2QueueHeld(threadId: string) {
  return localState.pendingThreadDeletionIds.has(threadId) || localState.deletedThreadIds.has(threadId);
}

/** Deleting a chat drops its queue: a chat of the thread that has been left, or is left later, sends nothing more */
export function dropAgentV2BackgroundQueue(threadId: string) {
  const { backgroundQueues, deletedThreadIds } = localState;
  localState.pendingThreadDeletionIds.delete(threadId);
  deletedThreadIds.add(threadId);
  backgroundQueues.get(threadId)?.dispose();
  backgroundQueues.delete(threadId);
}

export function forgetAgentV2ThreadDeletion(threadId: string) {
  localState.pendingThreadDeletionIds.delete(threadId);
  localState.backgroundQueues.get(threadId)?.resume();
}

/** The queue a chat left for the thread, which the chat that opens again takes over */
export function takeAgentV2BackgroundQueue(threadId: string): AgentV2LeftQueue | undefined {
  const { backgroundQueues } = localState;
  const queue = backgroundQueues.get(threadId);
  if (!queue) return undefined;
  const left = queue.take();
  if (!left) return undefined;
  // The failures go with the rest, so a chat with nothing more to send lets go at once
  if (queue.isDone()) {
    backgroundQueues.delete(threadId);
    queue.dispose();
  }
  return left;
}

/**
 * A left chat lets go once the answer it waits for has ended and its queue is empty, keeping the questions a wallet
 * switch failed for the chat that opens again. It looks once the tick's changes are done, as a queued question leaves
 * the queue for the chat just before its run starts.
 */
export const releaseDrainedAgentV2Queues = throttleWithTickEnd(() => {
  const { backgroundQueues } = localState;
  backgroundQueues.forEach((queue, threadId) => {
    if (!queue.isDone()) return;
    queue.dispose();
    if (!queue.hasFailures()) backgroundQueues.delete(threadId);
  });
});

export function resetAgentV2LocalState() {
  // Questions queued in chats that have been left are not sent after a sign-out
  localState.backgroundQueues.forEach((queue) => queue.dispose());
  localState = createLocalState();
  try {
    localStorage.removeItem(AGENT_THREAD_READ_STATE_STORAGE_KEY);
    localStorage.removeItem('mytonwallet-agent-last-thread');
  } catch {
    // An unavailable store does not block sign-out
  }
  agentThreadReadStateListeners.forEach((listener) => listener());
}

function createLocalState(): AgentV2LocalState {
  return {
    draftOnMount: '',
    shownThreadCounts: new Map(),
    recentChats: new Map(),
    backgroundQueues: new Map(),
    pendingDiscussionThreads: new Map(),
    pendingThreadDeletionIds: new Set(),
    deletedThreadIds: new Set(),
  };
}

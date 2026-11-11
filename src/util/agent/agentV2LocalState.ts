import type { AgentThreadSummaryV2 } from '../../api/agentV2/protocol/types';
import type { AgentConversationSession } from '../../components/agent/AgentConversationShell';
import type { AgentV2CachedChat } from '../../components/agent/hooks/agentV2MessagesState';
import type { AgentV2ChatTarget } from '../../components/agent/hooks/useAgentV2Messages';
import type { AgentThreadUnreadStart } from '../../components/agentV2/agentThreadReadState';

export interface ChatSelection {
  /** Remounts the chat for each chat the user opens */
  key: number;
  target: AgentV2ChatTarget;
  /** Known once the chat resolves a new or default target */
  threadId?: string;
  /** The list's copy of the thread, which names the chat before its history loads */
  thread?: AgentThreadSummaryV2;
  initialMessage?: string;
  /** The news whose discussion this is, when the user opened it from the feed; back gives the focus to its card */
  newsEventId?: number;
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
  openFeedOnMount?: FeedSelection;
  /** The draft and place in the conversation of the open chat */
  chatSessionOnMount?: { chatKey: number; session: AgentConversationSession };
  /** The place in the open news feed */
  feedSessionOnMount?: { feedKey: number; session: AgentConversationSession };
  /** The consent known as the app switched layouts */
  isConsentAcceptedOnSwitch?: boolean;
  threadReadState?: StoredReadState;
  shownThreadCounts: Map<string, number>;
  /** The chats shown last, oldest first, which open again at once with the history they had */
  recentChats: Map<string, AgentV2CachedChat>;
}

export const AGENT_THREAD_READ_STATE_STORAGE_KEY = 'mytonwallet-agent-thread-read-state';
// As many recent chats as iOS keeps loaded
const RECENT_CHAT_LIMIT = 8;
export const agentThreadReadStateListeners = new Set<NoneToVoidFunction>();
export const agentThreadListListeners = new Set<(threads: AgentThreadSummaryV2[]) => void>();

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

export function resetAgentV2LocalState() {
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
  return { draftOnMount: '', shownThreadCounts: new Map(), recentChats: new Map() };
}

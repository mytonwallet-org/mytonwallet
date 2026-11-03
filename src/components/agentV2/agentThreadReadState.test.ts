import type { AgentThreadSummaryV2 } from '../../api/agentV2/protocol/types';
import type { AgentMessage } from '../../global/types';
import type { resetAgentV2LocalState } from '../../util/agent/agentV2LocalState';

type ReadStateModule = typeof import('./agentThreadReadState');

const NO_ANSWERS = new Set<string>();
let resetLocalState: typeof resetAgentV2LocalState;

// A fresh module reads the stored state again, as a new launch does
function loadReadState() {
  let readStateModule: ReadStateModule;

  jest.isolateModules(() => {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    readStateModule = require('./agentThreadReadState') as ReadStateModule;
    resetLocalState = jest.requireActual<typeof import('../../util/agent/agentV2LocalState')>(
      '../../util/agent/agentV2LocalState',
    ).resetAgentV2LocalState;
  });

  return readStateModule!;
}

beforeEach(() => {
  localStorage.clear();
});

describe('agentThreadReadState', () => {
  it('starts a chat this device has not shown as read', () => {
    const readState = loadReadState();
    readState.observeAgentThreadCounts([buildThread('a', 2)], NO_ANSWERS);

    expect(readState.getIsAgentThreadUnread(buildThread('a', 2))).toBe(false);
    expect(readState.getIsAgentThreadUnread(buildThread('b', 5))).toBe(false);
  });

  it('marks a chat whose count grows past the listed one, until it is shown', () => {
    const readState = loadReadState();
    readState.observeAgentThreadCounts([buildThread('a', 2)], NO_ANSWERS);

    expect(readState.getIsAgentThreadUnread(buildThread('a', 4))).toBe(true);

    readState.markAgentThreadShown('a');
    expect(readState.getIsAgentThreadUnread(buildThread('a', 4))).toBe(false);

    readState.markAgentThreadHidden('a');
    readState.observeAgentThreadCounts([buildThread('a', 4)], NO_ANSWERS);
    expect(readState.getIsAgentThreadUnread(buildThread('a', 4))).toBe(false);
  });

  it('tells where the messages of an unread chat start, and nothing for a read one', () => {
    const readState = loadReadState();
    readState.observeAgentThreadCounts([buildThread('a', 2), buildThread('b', 3)], NO_ANSWERS);

    expect(readState.getAgentThreadUnreadStart(buildThread('a', 2))).toBeUndefined();
    expect(readState.getAgentThreadUnreadStart(buildThread('a', 5))).toBe(2);

    readState.markAgentThreadAnswerCompleted('b');
    expect(readState.getAgentThreadUnreadStart(buildThread('b', 3))).toBe('latestAnswer');

    readState.markAgentThreadShown('a');
    expect(readState.getAgentThreadUnreadStart(buildThread('a', 5))).toBeUndefined();
  });

  it('finds the first unread message among those loaded, leaving out failures the chat shows of its own', () => {
    const readState = loadReadState();
    const messages = [
      buildMessage(1, true), buildMessage(2, false), buildMessage(3, true), buildMessage(4, false),
      buildMessage(5, false), { ...buildMessage(6, false), failureText: 'Connection lost' },
    ];

    expect(readState.findAgentThreadFirstUnreadMessage(messages, 10, 8)).toEqual({ messageId: 4, position: 8 });
    expect(readState.findAgentThreadFirstUnreadMessage(messages, 10, 2)).toEqual({ messageId: 1, position: 5 });
    expect(readState.findAgentThreadFirstUnreadMessage(messages, 10, 'latestAnswer'))
      .toEqual({ messageId: 4, position: 8 });
    expect(readState.findAgentThreadFirstUnreadMessage(messages.slice(0, 3), 3, 'latestAnswer'))
      .toEqual({ messageId: 2, position: 1 });
    expect(readState.findAgentThreadFirstUnreadMessage([], 0, 'latestAnswer')).toBeUndefined();
  });

  it('marks a chat whose answer completes off screen, and never the one on screen', () => {
    const readState = loadReadState();
    readState.markAgentThreadShown('a');
    readState.markAgentThreadAnswerCompleted('a');
    expect(readState.getIsAgentThreadUnread(buildThread('a', 2))).toBe(false);

    readState.markAgentThreadHidden('a');
    readState.markAgentThreadAnswerCompleted('a');
    expect(readState.getIsAgentThreadUnread(buildThread('a', 2))).toBe(true);
  });

  it('takes no baseline while the chat is still answering', () => {
    const readState = loadReadState();
    readState.markAgentThreadShown('a');
    readState.markAgentThreadHidden('a');
    readState.observeAgentThreadCounts([buildThread('a', 1)], new Set(['a']));
    readState.observeAgentThreadCounts([buildThread('a', 2)], NO_ANSWERS);

    expect(readState.getIsAgentThreadUnread(buildThread('a', 2))).toBe(false);
    expect(readState.getIsAgentThreadUnread(buildThread('a', 3))).toBe(true);
  });

  it('keeps the dots across launches and forgets a deleted chat', () => {
    const firstLaunch = loadReadState();
    firstLaunch.markAgentThreadAnswerCompleted('a');

    const secondLaunch = loadReadState();
    expect(secondLaunch.getIsAgentThreadUnread(buildThread('a', 2))).toBe(true);

    secondLaunch.forgetAgentThreadReadState('a');
    expect(loadReadState().getIsAgentThreadUnread(buildThread('a', 2))).toBe(false);
  });

  it('clears stored and cached read state on full sign-out', () => {
    const readState = loadReadState();
    readState.markAgentThreadAnswerCompleted('a');
    readState.markAgentThreadShown('b');
    localStorage.setItem('mytonwallet-agent-last-thread', 'a');

    expect(readState.getIsAgentThreadUnread(buildThread('a', 2))).toBe(true);
    expect(localStorage.getItem('mytonwallet-agent-last-thread')).toBe('a');
    expect(localStorage.getItem('mytonwallet-agent-thread-read-state')).not.toBeNull();

    resetLocalState();
    readState.markAgentThreadHidden('b');
    expect(localStorage.getItem('mytonwallet-agent-last-thread')).toBeNull();
    expect(localStorage.getItem('mytonwallet-agent-thread-read-state')).toBeNull();
    expect(readState.getIsAgentThreadUnread(buildThread('a', 2))).toBe(false);
    expect(loadReadState().getIsAgentThreadUnread(buildThread('a', 2))).toBe(false);

    readState.markAgentThreadAnswerCompleted('b');
    expect(readState.getIsAgentThreadUnread(buildThread('b', 2))).toBe(true);
  });

  it('keeps the latest 500 records', () => {
    const readState = loadReadState();
    for (let i = 0; i <= 500; i++) {
      readState.markAgentThreadAnswerCompleted(`thread-${i}`);
    }

    expect(readState.getIsAgentThreadUnread(buildThread('thread-0', 2))).toBe(false);
    expect(readState.getIsAgentThreadUnread(buildThread('thread-1', 2))).toBe(true);
    expect(readState.getIsAgentThreadUnread(buildThread('thread-500', 2))).toBe(true);
  });

  it('tells the listeners about a dot that comes or goes', () => {
    const readState = loadReadState();
    const listener = jest.fn();
    const unsubscribe = readState.subscribeToAgentThreadReadState(listener);

    readState.markAgentThreadAnswerCompleted('a');
    readState.markAgentThreadShown('a');
    unsubscribe();
    readState.markAgentThreadHidden('a');
    readState.markAgentThreadAnswerCompleted('a');

    expect(listener).toHaveBeenCalledTimes(2);
  });
});

function buildThread(id: string, messageCount: number): AgentThreadSummaryV2 {
  const timestamp = '2026-10-21T12:00:00.000Z';
  return {
    id, revision: 1, createdAt: timestamp, updatedAt: timestamp, lastActivityAt: timestamp, messageCount,
  };
}

function buildMessage(id: number, isOutgoing: boolean): AgentMessage {
  return {
    id, text: `Message ${id}`, isOutgoing, timestamp: id,
  };
}

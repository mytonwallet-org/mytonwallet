import type { AgentV2ClientUpdate } from '../../api/agentV2/types';

import AgentThreadActivityTracker, { ACTIVITY_STALE_INTERVAL_MS } from './AgentThreadActivityTracker';

const NOW = 1_000_000;

describe('AgentThreadActivityTracker', () => {
  it('follows a run from the analysis through its steps to the writing', () => {
    const tracker = new AgentThreadActivityTracker();

    expect(tracker.handleUpdate(buildRunStarted('a', 'run-1'), NOW, 0)).toEqual(new Set(['a']));
    expect(tracker.getLangKey('a')).toBe('$agent_activity_analyzing_request');

    tracker.handleUpdate(buildRunActivity('a', 'run-1', 'web.searching', 'active'), NOW, 0);
    expect(tracker.getLangKey('a')).toBe('$agent_activity_web_searching');

    // A completed step leaves the step in progress in place, as the chat does
    const completedStep = buildRunActivity('a', 'run-1', 'web.searching', 'completed');
    expect(tracker.handleUpdate(completedStep, NOW, 0)).toEqual(new Set());
    expect(tracker.getLangKey('a')).toBe('$agent_activity_web_searching');

    tracker.handleUpdate(bindRunUpdate('a', 'run-1', { kind: 'textDelta', messageId: 'm', delta: 'Hi' }), NOW, 0);
    expect(tracker.getLangKey('a')).toBe('$agent_activity_writing');
    expect(tracker.getAnsweringThreadIds()).toEqual(new Set(['a']));
  });

  it('holds the last status of a completed answer until a later list load', () => {
    const tracker = new AgentThreadActivityTracker();
    tracker.handleUpdate(buildRunStarted('a', 'run-1'), NOW, 1);
    tracker.handleUpdate(bindRunUpdate('a', 'run-1', { kind: 'textDelta', messageId: 'm', delta: 'Hi' }), NOW, 1);

    expect(tracker.handleUpdate(buildMessageCompleted('a', 'run-1'), NOW, 1)).toEqual(new Set());
    expect(tracker.getLangKey('a')).toBe('$agent_activity_writing');
    expect(tracker.getAnsweringThreadIds()).toEqual(new Set());

    // The load that started before the completion does not have the answer yet
    expect(tracker.releaseAnswered(1, new Map())).toEqual(new Set());
    expect(tracker.releaseAnswered(2, new Map())).toEqual(new Set(['a']));
    expect(tracker.getLangKey('a')).toBeUndefined();
  });

  it('releases a held status once the listed revision passes the run', () => {
    const tracker = new AgentThreadActivityTracker();
    tracker.handleUpdate(buildRunStarted('a', 'run-1', 3), NOW, 1);
    tracker.handleUpdate(buildMessageCompleted('a', 'run-1'), NOW, 1);

    expect(tracker.releaseAnswered(1, new Map([['a', 3]]))).toEqual(new Set());
    expect(tracker.releaseAnswered(1, new Map([['a', 4]]))).toEqual(new Set(['a']));
  });

  it('ignores the late steps of a finished run and keeps a newer run', () => {
    const tracker = new AgentThreadActivityTracker();
    tracker.handleUpdate(buildRunStarted('a', 'run-1'), NOW, 0);
    tracker.handleUpdate(bindRunUpdate('a', 'run-1', { kind: 'runCancelled' }), NOW, 0);
    expect(tracker.getLangKey('a')).toBeUndefined();

    expect(tracker.handleUpdate(buildRunActivity('a', 'run-1', 'web.searching', 'active'), NOW, 0)).toEqual(new Set());
    expect(tracker.getLangKey('a')).toBeUndefined();

    tracker.handleUpdate(buildRunStarted('a', 'run-2'), NOW, 0);
    tracker.handleUpdate(bindRunUpdate('a', 'run-1', { kind: 'runCancelled' }), NOW, 0);
    expect(tracker.getLangKey('a')).toBe('$agent_activity_analyzing_request');
  });

  it('ends every status when the wallet loses its authority', () => {
    const tracker = new AgentThreadActivityTracker();
    tracker.handleUpdate(buildRunStarted('a', 'run-1'), NOW, 0);
    tracker.handleUpdate(buildRunStarted('b', 'run-2'), NOW, 0);

    expect(tracker.handleUpdate({ kind: 'walletAuthorityChanged' }, NOW, 0)).toEqual(new Set(['a', 'b']));
  });

  it('takes the open chat at its word and drops statuses that went quiet', () => {
    const tracker = new AgentThreadActivityTracker();
    expect(tracker.syncWithLoadedChat('a', '$agent_activity_writing', NOW)).toEqual(new Set(['a']));
    tracker.handleUpdate(buildRunStarted('b', 'run-2'), NOW, 0);

    const later = NOW + ACTIVITY_STALE_INTERVAL_MS + 1;
    expect(tracker.removeStale(later, 'a')).toEqual(new Set(['b']));
    expect(tracker.syncWithLoadedChat('a', undefined, later)).toEqual(new Set(['a']));
  });
});

// The run updates in the tests carry only the fields the tracker reads
function bindRunUpdate(threadId: string, runId: string, update: Record<string, unknown>) {
  return {
    ...update, threadId, runId, clientRunId: `client-${runId}`,
  } as unknown as AgentV2ClientUpdate;
}

function buildRunStarted(threadId: string, runId: string, threadRevision = 1) {
  return bindRunUpdate(threadId, runId, { kind: 'runStarted', threadRevision });
}

function buildRunActivity(threadId: string, runId: string, code: string, status: 'active' | 'completed') {
  return bindRunUpdate(threadId, runId, {
    kind: 'runActivityChanged',
    event: {
      type: 'run_activity', protocolVersion: 3, runId, sequence: 1, code, status,
    },
  });
}

function buildMessageCompleted(threadId: string, runId: string) {
  return bindRunUpdate(threadId, runId, { kind: 'messageCompleted', messageId: 'm', finishReason: 'stop' });
}

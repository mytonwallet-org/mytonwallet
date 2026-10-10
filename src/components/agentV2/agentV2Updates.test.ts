import type { AgentV2ClientUpdate } from '../../api/agentV2/types';

import {
  cancelAgentV2ActiveRunReplays,
  publishAgentV2Update,
  subscribeToAgentV2Updates,
} from '../../util/agentV2Updates';

const CLIENT_RUN_ID = '11111111-1111-4111-8111-111111111111';
const RUN_ID = '22222222-2222-4222-8222-222222222222';
const THREAD_ID = '33333333-3333-4333-8333-333333333333';
const MESSAGE_ID = '44444444-4444-4444-8444-444444444444';
const TOOL_CALL_ID = '55555555-5555-4555-8555-555555555555';
const TOOL_CALL_ID_2 = '55555555-5555-4555-8555-555555555556';

describe('Agent V2 active run update replay', () => {
  afterEach(() => {
    cancelAgentV2ActiveRunReplays();
  });

  it('reattaches a remounted listener to ordered coalesced active-run updates', () => {
    const firstUpdates: AgentV2ClientUpdate[] = [];
    const unsubscribeFirst = subscribeToAgentV2Updates((update) => firstUpdates.push(update));

    publishAgentV2Update(runStarted());
    publishAgentV2Update(messageStarted());
    publishAgentV2Update(textDelta('Hello '));
    unsubscribeFirst();
    publishAgentV2Update(textDelta('from the background'));

    const remountedUpdates: AgentV2ClientUpdate[] = [];
    const unsubscribeRemounted = subscribeToAgentV2Updates((update) => remountedUpdates.push(update));

    expect(firstUpdates).toEqual([runStarted(), messageStarted(), textDelta('Hello ')]);
    expect(remountedUpdates).toEqual([
      runStarted(),
      messageStarted(),
      textDelta('Hello from the background'),
    ]);
    expect(JSON.stringify(remountedUpdates)).not.toContain('tool_call');

    publishAgentV2Update({
      kind: 'messageCompleted',
      ...routing(),
      messageId: MESSAGE_ID,
      finishReason: 'complete',
    });
    unsubscribeRemounted();

    const afterTerminal: AgentV2ClientUpdate[] = [];
    const unsubscribeAfterTerminal = subscribeToAgentV2Updates((update) => afterTerminal.push(update));
    expect(afterTerminal).toEqual([]);
    unsubscribeAfterTerminal();
  });

  it('retains only the latest safe activity for each tool call', () => {
    publishAgentV2Update(runStarted());
    publishAgentV2Update(toolActivity(TOOL_CALL_ID, 'wallet.data.query', 'running'));
    publishAgentV2Update(toolActivity(TOOL_CALL_ID_2, 'wallet.directory.query', 'running'));
    publishAgentV2Update(toolActivity(TOOL_CALL_ID, 'wallet.data.query', 'complete'));

    const replayedUpdates: AgentV2ClientUpdate[] = [];
    const unsubscribe = subscribeToAgentV2Updates((update) => replayedUpdates.push(update));

    expect(replayedUpdates).toEqual([
      runStarted(),
      toolActivity(TOOL_CALL_ID, 'wallet.data.query', 'complete'),
      toolActivity(TOOL_CALL_ID_2, 'wallet.directory.query', 'running'),
    ]);
    unsubscribe();
  });
});

function runStarted(): AgentV2ClientUpdate {
  return { kind: 'runStarted', ...routing(), threadRevision: 2 };
}

function messageStarted(): AgentV2ClientUpdate {
  return { kind: 'messageStarted', ...routing(), messageId: MESSAGE_ID, contentKind: 'markdown' };
}

function textDelta(delta: string): AgentV2ClientUpdate {
  return { kind: 'textDelta', ...routing(), messageId: MESSAGE_ID, delta };
}

function toolActivity(
  toolCallId: string,
  toolName: 'wallet.data.query' | 'wallet.directory.query',
  status: 'running' | 'complete',
): AgentV2ClientUpdate {
  return { kind: 'toolActivityChanged', ...routing(), toolCallId, toolName, status };
}

function routing() {
  return { clientRunId: CLIENT_RUN_ID, runId: RUN_ID, threadId: THREAD_ID };
}

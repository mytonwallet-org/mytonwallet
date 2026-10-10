import type { AgentV2AppendRunCommand, AgentV2RunCommand } from './types';

import runOriginFixture from '../../../tests/fixtures/agentV2/run-origin-bindings.v1.json';
import { buildAgentV2RunOrigin } from './runCommand';

const THREAD_ID = '11111111-1111-4111-8111-111111111111';
const MESSAGE_ID = '22222222-2222-4222-8222-222222222222';

describe('Agent V2 run command', () => {
  it.each([
    ['without an origin', appendCommand(), {}],
    ['with an entry point', appendCommand({
      entryPoint: { kind: 'agentTab' },
    }), { entryPoint: { kind: 'agentTab' } }],
    ['with a follow-up', appendCommand({
      followupOf: { messageId: MESSAGE_ID, followupId: 'followup-1' },
    }), { followupOf: { messageId: MESSAGE_ID, followupId: 'followup-1' } }],
  ] as const)('builds append origin %s', (_label, command, expected) => {
    expect(buildAgentV2RunOrigin(command)).toEqual(expected);
  });

  it.each([
    {
      ...appendCommand(),
      entryPoint: { kind: 'agentTab' },
      followupOf: { messageId: MESSAGE_ID, followupId: 'followup-1' },
    },
    {
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'edit', targetUserMessageId: MESSAGE_ID, text: 'Edited' },
      followupOf: { messageId: MESSAGE_ID, followupId: 'followup-1' },
    },
    {
      threadId: THREAD_ID,
      expectedThreadRevision: 1,
      input: { kind: 'regenerate', targetAssistantMessageId: MESSAGE_ID },
      entryPoint: { kind: 'agentTab' },
    },
  ])('rejects an invalid deserialized origin combination', (command) => {
    expect(() => buildAgentV2RunOrigin(command as AgentV2RunCommand)).toThrow(expect.objectContaining({
      code: 'invalid_request',
      retryable: false,
    }));
  });

  it.each(runOriginFixture.cases)(
    'executes the backend run-origin fixture $id at the runtime boundary',
    (fixtureCase) => {
      const command: Record<string, unknown> = {
        threadId: THREAD_ID,
        expectedThreadRevision: 1,
        input: fixtureCase.inputKind === 'append'
          ? { kind: 'append', text: runOriginFixture.inputs.append.message.text }
          : fixtureCase.inputKind === 'edit'
            ? {
              kind: 'edit',
              targetUserMessageId: runOriginFixture.inputs.edit.targetUserMessageId,
              text: runOriginFixture.inputs.edit.message.text,
            }
            : {
              kind: 'regenerate',
              targetAssistantMessageId: runOriginFixture.inputs.regenerate.targetAssistantMessageId,
            },
      };
      fixtureCase.origins.forEach((originName) => {
        command[originName] = runOriginFixture.originBindings[
          originName as keyof typeof runOriginFixture.originBindings
        ];
      });

      if (fixtureCase.expectedValid) {
        expect(() => buildAgentV2RunOrigin(command as AgentV2RunCommand)).not.toThrow();
      } else {
        expect(() => buildAgentV2RunOrigin(command as AgentV2RunCommand)).toThrow(expect.objectContaining({
          code: 'invalid_request',
          retryable: false,
        }));
      }
    },
  );
});

function appendCommand(
  origin: Omit<
    AgentV2AppendRunCommand,
    'threadId' | 'expectedThreadRevision' | 'input'
  > = {},
): AgentV2RunCommand {
  return {
    threadId: THREAD_ID,
    expectedThreadRevision: 1,
    input: { kind: 'append', text: 'Hello' },
    ...origin,
  } as AgentV2AppendRunCommand;
}

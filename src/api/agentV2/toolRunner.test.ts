import type { AgentToolResultRequestV2 } from './protocol/types';

import { AgentV2ToolRunner } from './toolRunner';

describe('AgentV2ToolRunner', () => {
  it('gives a larger tool result more time to upload', async () => {
    const getJson = jest.fn((..._args: unknown[]) => Promise.resolve({
      runId: 'run', toolCallId: 'call', clientToolResultId: 'result',
    }));
    const runner = new AgentV2ToolRunner({
      getJson: getJson as never,
      baseUrl: 'https://agent.test/api/v2',
      executor: () => ({ execute: jest.fn() }),
      discard: jest.fn(),
      now: Date.now,
      randomUuid: () => 'result',
      wait: () => Promise.resolve(),
      requestTimeoutMs: 20_000,
    });
    const submit = (payload: string) => runner.submit(
      'run',
      { id: 'call', name: 'wallet.data.query' },
      { clientToolResultId: 'result', payload } as unknown as AgentToolResultRequestV2,
      new AbortController().signal,
      () => true,
    );

    await submit('');
    await submit('x'.repeat(100 * 1024));

    const [small, large] = getJson.mock.calls.map((args) => (args[3] as { timeoutMs: number }).timeoutMs);
    expect(small).toBeLessThan(21_000);
    expect(large - small).toBeGreaterThanOrEqual(50_000);
  });
});

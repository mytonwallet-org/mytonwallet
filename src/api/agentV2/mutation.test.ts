import { AgentV2CompatibilityError, AgentV2ContractError } from './protocol/wireReader';
import { AgentV2HttpError } from './identity';
import { runSafeAgentV2Operation } from './mutation';
import { AgentV2StreamProtocolError, AgentV2StreamTransportError } from './ndjson';

describe('Agent V2 worker mutation results', () => {
  it('returns a typed success value', async () => {
    await expect(runSafeAgentV2Operation(() => Promise.resolve({ duplicate: true }))).resolves.toEqual({
      ok: true,
      value: { duplicate: true },
    });
  });

  it('allowlists safe HTTP error fields', async () => {
    const failure = new AgentV2HttpError(
      409,
      'thread_revision_conflict',
      'Refresh the chat and try again.',
      true,
    );

    await expect(runSafeAgentV2Operation(() => Promise.reject(failure))).resolves.toEqual({
      ok: false,
      error: {
        code: 'thread_revision_conflict',
        retryable: true,
      },
    });
  });

  it.each([
    [new AgentV2ContractError('private-path'), 'invalid_event', false],
    [new SyntaxError('private JSON body'), 'invalid_event', false],
    [new AgentV2CompatibilityError('private-boundary', 'future-version'), 'client_update_required', false],
    [new AgentV2StreamProtocolError('sequence gap', true), 'invalid_event', true],
    [new DOMException('private reason', 'AbortError'), 'run_interrupted', false],
    [new AgentV2StreamTransportError('read failed', { cause: new DOMException('stop', 'AbortError') }),
      'run_interrupted', false],
    [new DOMException('private timeout', 'TimeoutError'), 'network_error', true],
    [new TypeError('Failed to fetch private-url'), 'network_error', true],
    [new AgentV2StreamTransportError('private transport'), 'network_error', true],
    [new TypeError('private implementation detail'), 'internal_error', false],
    [new Error('private failure'), 'internal_error', false],
  ] as const)('classifies %s without leaking internal details', async (failure, code, retryable) => {
    await expect(runSafeAgentV2Operation(() => Promise.reject(failure))).resolves.toEqual({
      ok: false, error: { code, retryable },
    });
  });
});

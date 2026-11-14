import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';
import { formatAgentTime } from '../agent/helpers/agentDateFormat';

import {
  AgentComposerStatus,
  AgentDictationAnnouncement,
  AgentDictationNotice,
  AgentFailureCaption,
} from './AgentStatusNotice';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => (key: string, values?: string | number | unknown[]) => (
    values === undefined ? key : `${key}:${Array.isArray(values) ? values.join(',') : String(values)}`
  ),
}));

describe('Agent V2 failure and composer status notices', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('shows a refused microphone and reads out every dictation failure once, as an alert', async () => {
    TeactDOM.render(<AgentDictationNotice notice={{ kind: 'microphoneDenied' }} />, root);
    await pause(20);
    expect(root.textContent).toBe('$agent_dictation_microphone_denied');
    expect(root.querySelector('[role="status"], [role="alert"]')).toBeNull();
    expect(root.querySelector('button')).toBeNull();

    TeactDOM.render(<AgentDictationAnnouncement failure={{ kind: 'error', code: 'rate_limited' }} />, root);
    await pause(20);
    const announcement = root.querySelector('[role="alert"]')!;
    expect(announcement.classList.contains('visually-hidden')).toBe(true);
    expect(announcement.textContent).toBe('$agent_error_limit');
    expect(root.querySelector('button')).toBeNull();

    TeactDOM.render(<AgentDictationAnnouncement failure={{ kind: 'microphoneDenied' }} />, root);
    await pause(20);
    expect(root.querySelector('[role="alert"]')!.textContent).toBe('$agent_dictation_microphone_denied');
  });

  it('renders a historical failure as a caption without a live status role or Retry', async () => {
    TeactDOM.render(<AgentFailureCaption text="Agent could not complete the request." />, root);
    await pause(20);

    expect(root.textContent).toBe('Agent could not complete the request.');
    expect(root.querySelector('[role="status"]')).toBeNull();
    expect(root.querySelector('button')).toBeNull();
  });

  it('ends the latest failure with an inline Retry while the request can be retried', async () => {
    const onRetry = jest.fn();
    TeactDOM.render(<AgentFailureCaption text="Connection to the agent was interrupted." onRetry={onRetry} />, root);
    await pause(20);

    const button = root.querySelector('p > button') as HTMLButtonElement;
    expect(button.textContent).toBe('Retry');
    expect(button.getAttribute('aria-label')).toBe('$agent_retry_request');
    button.click();
    expect(onRetry).toHaveBeenCalledTimes(1);
  });

  it('announces only the current composer status and keeps countdown updates quiet', async () => {
    TeactDOM.render(
      <AgentComposerStatus
        status={{ kind: 'capacity', mode: 'blocked', resetAt: Date.now() + 120_000 }}
      />,
      root,
    );
    await pause(20);

    expect(root.querySelectorAll('[role="status"]')).toHaveLength(1);
    expect(root.textContent).toContain('$agent_capacity_limit_title');
    expect(root.textContent).toContain('$agent_capacity_limit_known');
    expect(root.querySelector('[aria-live="off"]')).not.toBeNull();
  });

  it('tells the daily quota reset time on one status line', async () => {
    const resetAt = Date.now() + 3_600_000;
    TeactDOM.render(
      <AgentComposerStatus
        status={{
          kind: 'userQuota',
          mode: 'blocked',
          quota: {
            limit: 20, used: 20, remaining: 0, resetAt: new Date(resetAt).toISOString(),
          },
          resetAt,
        }}
      />,
      root,
    );
    await pause(20);

    expect(root.querySelectorAll('[role="status"]')).toHaveLength(1);
    expect(root.querySelector('[role="status"]')!.textContent)
      .toBe(`$agent_daily_limit_resets_at:${formatAgentTime('en', resetAt)}`);
  });

  it('offers no Retry while a limit holds', async () => {
    TeactDOM.render(
      <AgentComposerStatus
        status={{
          kind: 'rateLimit', mode: 'blocked', resetAt: Date.now() + 120_000, clientRunId: 'run-1',
        }}
        onRetry={jest.fn()}
      />,
      root,
    );
    await pause(20);

    expect(root.textContent).toContain('$agent_rate_limit_title');
    expect(root.querySelector('button')).toBeNull();
  });

  it('tells a question the reset limit kept from starting as a failed request with Retry', async () => {
    const onRetry = jest.fn();
    const status = {
      kind: 'rateLimit', mode: 'informational', resetAt: Date.now() - 1_000, clientRunId: 'run-1',
    } as const;
    TeactDOM.render(<AgentComposerStatus status={status} onRetry={onRetry} />, root);
    await pause(20);

    expect(root.querySelector('[role="status"]')).toBeNull();
    expect(root.querySelector('p > span')!.textContent).toBe('$agent_error_limit');
    (root.querySelector('p > button') as HTMLButtonElement).click();
    expect(onRetry).toHaveBeenCalledTimes(1);

    TeactDOM.render(<AgentComposerStatus status={status} />, root);
    await pause(20);
    expect(root.textContent).toBe('');
  });

  it('cross-fades the reset limit into its failure, keeping the last second until the reset', async () => {
    const onRetry = jest.fn();
    const resetAt = Date.now() + 1_100;
    TeactDOM.render(
      <AgentComposerStatus status={{ kind: 'rateLimit', mode: 'blocked', resetAt, clientRunId: 'run-1' }} />,
      root,
    );
    await pause(1_200);
    expect(root.querySelector('[role="status"]')!.textContent)
      .toContain('$agent_rate_limit_body:$agent_time_seconds:1');

    TeactDOM.render(
      <AgentComposerStatus
        status={{
          kind: 'rateLimit', mode: 'informational', resetAt, clientRunId: 'run-1',
        }}
        onRetry={onRetry}
      />,
      root,
    );
    await pause(20);
    const leaving = root.querySelector('[aria-hidden]')!;
    expect(leaving.textContent).toContain('$agent_rate_limit_title');
    expect(root.querySelector('p > button')!.textContent).toBe('Retry');

    await pause(300);
    expect(leaving.isConnected).toBe(false);
    expect(root.querySelector('[aria-hidden]')).toBeNull();
    expect(root.textContent).toBe('$agent_error_limitRetry');
  });

  it('shows unknown capacity as a non-blocking degraded status', async () => {
    TeactDOM.render(
      <AgentComposerStatus status={{ kind: 'capacity', mode: 'degraded' }} />,
      root,
    );
    await pause(20);

    expect(root.textContent).toContain('$agent_capacity_degraded_title');
    expect(root.textContent).toContain('$agent_capacity_limit_unknown');
    expect(root.querySelector('button')).toBeNull();
  });
});

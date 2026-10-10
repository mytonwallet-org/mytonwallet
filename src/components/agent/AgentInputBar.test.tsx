import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import AgentInputBar from './AgentInputBar';

jest.mock('../ui/Input', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => (key: string, values?: number[] | number | string) => {
    if (key === '$agent_user_quota_meter') {
      const [remaining, limit] = values as number[];
      return `Agent quota: ${remaining} of ${limit} units remaining`;
    }
    if (key === '$agent_user_quota_reset') return `Daily quota resets in ${String(values)}.`;
    if (key === '$agent_time_hours') return `${String(values)} h`;
    if (key === '$agent_time_minutes') return `${String(values)} min`;
    if (key === '$agent_time_seconds') return `${String(values)} sec`;
    return key;
  },
}));

describe('AgentInputBar quota status', () => {
  it('renders a persistent status notice inside the measured input wrapper', async () => {
    const root = document.createElement('div');
    document.body.appendChild(root);

    TeactDOM.render(
      <AgentInputBar
        inputValue=""
        statusNotice={<div data-status-notice>Agent status</div>}
        onInput={jest.fn()}
        onKeyDown={jest.fn()}
        onSend={jest.fn()}
      />,
      root,
    );
    await pause(20);

    const wrapper = root.firstElementChild!;
    const notice = root.querySelector('[data-status-notice]')!;
    expect(wrapper.contains(notice)).toBe(true);

    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('reveals the quota status only after its button is pressed', async () => {
    const root = document.createElement('div');
    document.body.appendChild(root);

    TeactDOM.render(
      <AgentInputBar
        inputValue=""
        userQuota={{
          limit: 200,
          used: 4,
          remaining: 196,
          resetAt: new Date(Date.now() + 13 * 60 * 60_000).toISOString(),
        }}
        quotaStatus={(
          <div>
            Agent quota: 196 of 200 units remaining
            Daily quota resets in 13 h.
          </div>
        )}
        onInput={jest.fn()}
        onKeyDown={jest.fn()}
        onSend={jest.fn()}
      />,
      root,
    );
    await pause(20);

    const toggle = root.querySelector('button[aria-expanded]')!;
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
    expect(root.textContent).not.toContain('Agent quota: 196 of 200 units remaining');

    (toggle as HTMLButtonElement).click();
    await pause(20);

    expect(toggle.getAttribute('aria-expanded')).toBe('true');
    expect(root.textContent).toContain('Agent quota: 196 of 200 units remaining');
    expect(root.textContent).toContain('Daily quota resets in 13 h.');

    (toggle as HTMLButtonElement).click();
    await pause(20);

    expect(toggle.getAttribute('aria-expanded')).toBe('false');
    expect(root.textContent).not.toContain('Agent quota: 196 of 200 units remaining');

    TeactDOM.render(undefined, root);
    root.remove();
  });
});

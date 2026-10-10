import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { waitForCondition } from '../../../tests/util/async';

import AgentRunActivity from './AgentRunActivity';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => (key: string) => ({
    $agent_activity_analyzing_request: 'Analyzing your request…',
    $agent_activity_wallet: 'Reading wallet data…',
    $agent_activity_transactions: 'Reviewing wallet activity…',
    $agent_activity_preparing_response: 'Preparing your answer…',
    $agent_activity_web_reading_sources: 'Reviewing sources…',
    $agent_activity_help_searching: 'Searching the Help Center…',
  }[key] ?? key),
}));

describe('AgentRunActivity', () => {
  it('announces safe localized run phases without exposing tool details', async () => {
    const root = document.createElement('div');
    document.body.appendChild(root);

    TeactDOM.render(
      <AgentRunActivity activity={{ kind: 'analyzingRequest' }} />,
      root,
    );
    await waitForCondition(() => root.textContent === 'Analyzing your request…');
    expect(root.textContent).toBe('Analyzing your request…');

    TeactDOM.render(
      <AgentRunActivity
        activity={{ kind: 'tool', toolName: 'wallet.data.query' }}
      />,
      root,
    );
    await waitForCondition(() => root.textContent === 'Reading wallet data…');
    expect(root.textContent).toBe('Reading wallet data…');
    expect(root.textContent).not.toContain('wallet.data.query');

    TeactDOM.render(
      <AgentRunActivity
        activity={{
          kind: 'tool', toolName: 'wallet.data.query', operation: 'transactions.list',
        }}
      />,
      root,
    );
    await waitForCondition(() => root.textContent === 'Reviewing wallet activity…');
    expect(root.textContent).toBe('Reviewing wallet activity…');

    TeactDOM.render(
      <AgentRunActivity activity={{ kind: 'preparingResponse' }} />,
      root,
    );
    await waitForCondition(() => root.textContent === 'Preparing your answer…');
    const status = root.querySelector('[role="status"]');
    expect(status?.getAttribute('aria-live')).toBe('polite');
    expect(status?.getAttribute('aria-atomic')).toBe('true');
    expect(root.textContent).toBe('Preparing your answer…');

    TeactDOM.render(
      <AgentRunActivity
        activity={{ kind: 'server', code: 'web.reading_sources' }}
      />,
      root,
    );
    await waitForCondition(() => root.textContent === 'Reviewing sources…');
    expect(root.textContent).toBe('Reviewing sources…');
    expect(root.textContent).not.toContain('web.reading_sources');
    expect(root.querySelectorAll('[role="status"]')).toHaveLength(1);

    TeactDOM.render(
      <AgentRunActivity activity={{ kind: 'server', code: 'help.searching' }} />,
      root,
    );
    await waitForCondition(() => root.textContent === 'Searching the Help Center…');
    expect(root.textContent).toBe('Searching the Help Center…');

    // The last phase stays on screen while the indicator fades out, then leaves the DOM
    TeactDOM.render(<AgentRunActivity />, root);
    await waitForCondition(() => root.querySelector('[role="status"]')?.classList.contains('closing') === true);
    expect(root.textContent).toBe('Searching the Help Center…');
    await waitForCondition(() => !root.querySelector('[role="status"]'));

    TeactDOM.render(undefined, root);
    root.remove();
  });
});

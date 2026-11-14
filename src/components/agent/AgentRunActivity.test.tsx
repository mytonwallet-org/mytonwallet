import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';
import { waitForCondition } from '../../../tests/util/async';

import AgentRunActivity, { createAgentRunActivityHandoff } from './AgentRunActivity';
import AgentSpinningTop from './AgentSpinningTop';

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

jest.mock('./AgentSpinningTop', () => ({
  __esModule: true,
  default: jest.fn(() => undefined),
}));

// A step stays at least 1.2 s before the next one replaces it
const STEP_TIMEOUT = 2_000;

describe('AgentRunActivity', () => {
  it('stays stopped while it closes after a Stop', async () => {
    const root = document.createElement('div');
    document.body.appendChild(root);
    const getTopState = () => jest.mocked(AgentSpinningTop).mock.calls.at(-1)![0].agentState;

    TeactDOM.render(<AgentRunActivity activity={{ kind: 'analyzingRequest' }} />, root);
    await pause(20);
    expect(getTopState()).toBe('thinking');

    TeactDOM.render(<AgentRunActivity activity={{ kind: 'analyzingRequest' }} isStopped />, root);
    await pause(20);
    expect(getTopState()).toBe('stopped');

    TeactDOM.render(<AgentRunActivity />, root);
    await pause(20);
    expect(getTopState()).toBe('stopped');

    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('announces safe localized run phases without exposing tool details', async () => {
    const root = document.createElement('div');
    document.body.appendChild(root);

    TeactDOM.render(
      <AgentRunActivity activity={{ kind: 'analyzingRequest' }} />,
      root,
    );
    await waitForCondition(() => getStepText(root) === 'Analyzing your request…', { timeout: STEP_TIMEOUT });
    expect(getStepText(root)).toBe('Analyzing your request…');

    TeactDOM.render(
      <AgentRunActivity
        activity={{ kind: 'tool', toolName: 'wallet.data.query' }}
      />,
      root,
    );
    await waitForCondition(() => getStepText(root) === 'Reading wallet data…', { timeout: STEP_TIMEOUT });
    expect(getStepText(root)).toBe('Reading wallet data…');
    expect(root.textContent).not.toContain('wallet.data.query');

    TeactDOM.render(
      <AgentRunActivity
        activity={{
          kind: 'tool', toolName: 'wallet.data.query', operation: 'transactions.list',
        }}
      />,
      root,
    );
    await waitForCondition(() => getStepText(root) === 'Reviewing wallet activity…', { timeout: STEP_TIMEOUT });
    expect(getStepText(root)).toBe('Reviewing wallet activity…');

    TeactDOM.render(
      <AgentRunActivity activity={{ kind: 'preparingResponse' }} />,
      root,
    );
    await waitForCondition(() => getStepText(root) === 'Preparing your answer…', { timeout: STEP_TIMEOUT });
    const status = root.querySelector('[role="status"]');
    expect(status?.getAttribute('aria-live')).toBe('polite');
    expect(status?.getAttribute('aria-atomic')).toBe('true');
    expect(getStepText(root)).toBe('Preparing your answer…');

    TeactDOM.render(
      <AgentRunActivity
        activity={{ kind: 'server', code: 'web.reading_sources' }}
      />,
      root,
    );
    await waitForCondition(() => getStepText(root) === 'Reviewing sources…', { timeout: STEP_TIMEOUT });
    expect(getStepText(root)).toBe('Reviewing sources…');
    expect(root.textContent).not.toContain('web.reading_sources');
    expect(root.querySelectorAll('[role="status"]')).toHaveLength(1);

    TeactDOM.render(
      <AgentRunActivity activity={{ kind: 'server', code: 'help.searching' }} />,
      root,
    );
    await waitForCondition(() => getStepText(root) === 'Searching the Help Center…', { timeout: STEP_TIMEOUT });
    expect(getStepText(root)).toBe('Searching the Help Center…');

    // The last phase stays on screen while the indicator fades out, then leaves the DOM
    TeactDOM.render(<AgentRunActivity />, root);
    await waitForCondition(() => root.querySelector('[role="status"]')?.classList.contains('closing') === true);
    expect(getStepText(root)).toBe('Searching the Help Center…');
    await waitForCondition(() => !root.querySelector('[role="status"]'));

    TeactDOM.render(undefined, root);
    root.remove();
  }, 15_000);

  it('keeps a step on screen for a while and skips the steps that came meanwhile', async () => {
    const root = document.createElement('div');
    document.body.appendChild(root);

    TeactDOM.render(<AgentRunActivity activity={{ kind: 'analyzingRequest' }} />, root);
    await waitForCondition(() => getStepText(root) === 'Analyzing your request…');
    const shownAt = Date.now();

    TeactDOM.render(<AgentRunActivity activity={{ kind: 'tool', toolName: 'wallet.data.query' }} />, root);
    await pause(100);
    TeactDOM.render(<AgentRunActivity activity={{ kind: 'preparingResponse' }} />, root);
    await pause(100);
    expect(getStepText(root)).toBe('Analyzing your request…');

    await waitForCondition(() => getStepText(root) !== 'Analyzing your request…', { timeout: STEP_TIMEOUT });
    expect(Date.now() - shownAt).toBeGreaterThanOrEqual(1_100);
    expect(getStepText(root)).toBe('Preparing your answer…');

    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('stays over the answer taking its place for as long as the answer grows out of it', async () => {
    const root = document.createElement('div');
    document.body.appendChild(root);

    TeactDOM.render(<AgentRunActivity activity={{ kind: 'preparingResponse' }} isAnswerPlaceholder />, root);
    // The indicator has come on screen, as one that an answer takes the place of has
    await waitForCondition(() => root.querySelector('[role="status"]')?.classList.contains('open') === true);
    expect(getStepText(root)).toBe('Preparing your answer…');

    const closedAt = Date.now();
    TeactDOM.render(<AgentRunActivity isAnswerPlaceholder />, root);
    await waitForCondition(() => root.querySelector('[role="status"]')?.classList.contains('closing') === true);
    await waitForCondition(() => !root.querySelector('[role="status"]'));
    // Past the 200 ms an indicator at the chat's end takes to fade
    expect(Date.now() - closedAt).toBeGreaterThanOrEqual(300);

    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('lights each step with a glint once, as it comes into focus, as on iOS', async () => {
    const root = document.createElement('div');
    document.body.appendChild(root);

    TeactDOM.render(<AgentRunActivity activity={{ kind: 'analyzingRequest' }} />, root);
    await waitForCondition(() => getStepText(root) === 'Analyzing your request…');
    // The first step's glint waits for the indicator to rise into place as well
    expect(getGlintDelays(root)).toEqual([480]);

    TeactDOM.render(<AgentRunActivity activity={{ kind: 'tool', toolName: 'wallet.data.query' }} />, root);
    await waitForCondition(() => getStepText(root) === 'Reading wallet data…', { timeout: STEP_TIMEOUT });
    // The step that blurs away has none
    expect(getLeavingStepText(root)).toBe('Analyzing your request…');
    expect(getGlintDelays(root)).toEqual([300]);

    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('lights a step standing in for the answer without waiting for an entrance', () => {
    const root = document.createElement('div');
    document.body.appendChild(root);

    TeactDOM.render(<AgentRunActivity activity={{ kind: 'analyzingRequest' }} isAnswerPlaceholder />, root);
    expect(getGlintDelays(root)).toEqual([300]);

    TeactDOM.render(undefined, root);
    root.remove();
  });
});

describe('AgentRunActivity handoff', () => {
  it('blurs the step of the indicator whose place it takes into its own, or goes on with it', async () => {
    const footer = document.createElement('div');
    const message = document.createElement('div');
    document.body.append(message, footer);
    const handoff = createAgentRunActivityHandoff();

    TeactDOM.render(<AgentRunActivity activity={{ kind: 'analyzingRequest' }} handoff={handoff} />, footer);
    await waitForCondition(() => getStepText(footer) === 'Analyzing your request…');

    // The answer's message takes the indicator from the chat's end as the step changes
    TeactDOM.render(
      <AgentRunActivity activity={{ kind: 'preparingResponse' }} isAnswerPlaceholder handoff={handoff} />,
      message,
    );
    TeactDOM.render(undefined, footer);
    expect(getStepText(message)).toBe('Preparing your answer…');
    expect(getLeavingStepText(message)).toBe('Analyzing your request…');
    await waitForCondition(() => !getLeavingStepText(message));

    // An indicator that takes the place with the same step goes on with it
    TeactDOM.render(undefined, message);
    TeactDOM.render(<AgentRunActivity activity={{ kind: 'preparingResponse' }} handoff={handoff} />, footer);
    expect(getStepText(footer)).toBe('Preparing your answer…');
    expect(getLeavingStepText(footer)).toBeUndefined();
    TeactDOM.render(undefined, footer);

    // A later indicator, once the handoff is stale, starts with its own step
    await pause(400);
    TeactDOM.render(<AgentRunActivity activity={{ kind: 'analyzingRequest' }} handoff={handoff} />, footer);
    expect(getStepText(footer)).toBe('Analyzing your request…');
    expect(getLeavingStepText(footer)).toBeUndefined();

    TeactDOM.render(undefined, footer);
    footer.remove();
    message.remove();
  });

  it('goes on with the glint of the step it takes over, and plays none once it has passed', async () => {
    const footer = document.createElement('div');
    const message = document.createElement('div');
    document.body.append(message, footer);
    const handoff = createAgentRunActivityHandoff();
    const startedAt = Date.now();
    const now = jest.spyOn(Date, 'now').mockReturnValue(startedAt);

    TeactDOM.render(<AgentRunActivity activity={{ kind: 'analyzingRequest' }} handoff={handoff} />, footer);
    expect(getGlintDelays(footer)).toEqual([480]);
    now.mockReturnValue(startedAt + 100);

    TeactDOM.render(
      <AgentRunActivity activity={{ kind: 'analyzingRequest' }} isAnswerPlaceholder handoff={handoff} />,
      message,
    );
    TeactDOM.render(undefined, footer);
    // The glint keeps its time rather than starting over, which would put it 300 ms away
    expect(getGlintDelays(message)).toEqual([380]);
    now.mockRestore();

    // Past the glint, a step that goes on has none
    await pause(1_300);
    TeactDOM.render(undefined, message);
    TeactDOM.render(<AgentRunActivity activity={{ kind: 'analyzingRequest' }} handoff={handoff} />, footer);
    expect(getStepText(footer)).toBe('Analyzing your request…');
    expect(getGlintDelays(footer)).toEqual([]);

    TeactDOM.render(undefined, footer);
    footer.remove();
    message.remove();
  });
});

// The step that blurs away is hidden from assistive technology, as the top is
function getLeavingStepText(root: HTMLElement) {
  return [...root.querySelectorAll('[aria-hidden]')].map((element) => element.textContent).find(Boolean);
}

function getStepText(root: HTMLElement) {
  return root.querySelector('[data-agent-activity-step]')?.textContent;
}

// When the glints shown start, in milliseconds from their steps' coming
function getGlintDelays(root: HTMLElement) {
  return Array.from(
    root.querySelectorAll<HTMLElement>('[data-agent-activity-glint]'),
    (glint) => parseFloat(glint.style.getPropertyValue('--glint-delay')),
  );
}

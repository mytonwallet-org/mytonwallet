import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import AgentMessageControls from './AgentMessageControls';

describe('AgentMessageControls', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('renders suggested followups as buttons bound to their ids', async () => {
    TeactDOM.render(
      <AgentMessageControls
        followups={[{ id: 'followup-1', kind: 'suggested_prompt', text: 'How do rewards accrue?' }]}
        isDisabled={false}
        shouldShowFollowups
        onFollowup={jest.fn()}
      />,
      root,
    );
    await pause(20);

    const followups = root.querySelectorAll('button[data-agent-followup-id]');
    expect(followups).toHaveLength(1);
    expect(followups[0].getAttribute('data-agent-followup-id')).toBe('followup-1');
    expect(followups[0].textContent).toBe('How do rewards accrue?');
  });

  it('removes the followups of an older answer from the DOM', async () => {
    const followups = [{ id: 'followup-1', kind: 'suggested_prompt' as const, text: 'How do rewards accrue?' }];
    const render = (shouldShowFollowups: boolean) => TeactDOM.render(
      <AgentMessageControls
        followups={followups}
        isDisabled={false}
        shouldShowFollowups={shouldShowFollowups}
        onFollowup={jest.fn()}
      >
        <button type="button" data-action>Open</button>
      </AgentMessageControls>,
      root,
    );

    render(false);
    await pause(20);
    expect(root.querySelector('[data-action]')).not.toBeNull();
    expect(root.querySelector('button[data-agent-followup-id]')).toBeNull();

    render(true);
    await pause(20);
    expect(root.querySelector('button[data-agent-followup-id]')).not.toBeNull();

    render(false);
    await pause(20);
    expect(root.querySelector('button[data-agent-followup-id]')).not.toBeNull();
    await pause(250);
    expect(root.querySelector('button[data-agent-followup-id]')).toBeNull();
  });
});

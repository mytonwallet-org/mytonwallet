import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';
import { waitForCondition } from '../../../tests/util/async';

import AgentMessagesSkeleton from './AgentMessagesSkeleton';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => (key: string) => key,
}));

describe('AgentMessagesSkeleton', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('shows the placeholder at once, open from its first frame', () => {
    TeactDOM.render(<AgentMessagesSkeleton isOpen />, root);

    const skeleton = root.querySelector<HTMLElement>('[data-agent-skeleton]');
    expect(skeleton?.classList.contains('open')).toBe(true);
    expect(root.querySelectorAll('[data-agent-skeleton-role]').length).toBeGreaterThan(0);
  });

  it('leaves once the history has come, and tells so once', async () => {
    const onClosed = jest.fn();
    TeactDOM.render(<AgentMessagesSkeleton isOpen onClosed={onClosed} />, root);
    await pause(20);
    expect(root.querySelector('[data-agent-skeleton]')).not.toBeNull();

    TeactDOM.render(<AgentMessagesSkeleton isOpen={false} onClosed={onClosed} />, root);
    await waitForCondition(() => onClosed.mock.calls.length > 0);
    await pause(20);
    expect(root.querySelector('[data-agent-skeleton]')).toBeNull();
    expect(onClosed).toHaveBeenCalledTimes(1);
  });
});

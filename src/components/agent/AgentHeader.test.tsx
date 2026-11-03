import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import AgentHeader from './AgentHeader';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));

describe('AgentHeader', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('leads with the wallet\'s Back button, chevron and label, which goes back', async () => {
    const onBack = jest.fn();
    TeactDOM.render(<AgentHeader isScrolled={false} title="Staking" onBack={onBack} />, root);
    await pause(20);

    const button = root.querySelector('button')!;
    expect(button.textContent).toBe('Back');
    expect(button.querySelector('i')!.classList).toContain('icon-chevron-left');
    button.click();
    expect(onBack).toHaveBeenCalledTimes(1);
  });

  it('has no Back button on the chat list', async () => {
    TeactDOM.render(<AgentHeader isScrolled={false} />, root);
    await pause(20);

    expect(root.querySelector('button')).toBeNull();
  });
});

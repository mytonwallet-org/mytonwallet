import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import AgentNewsRow from './AgentNewsRow';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));

describe('AgentNewsRow', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it.each([
    [0, ''],
    [1, '1'],
    [29, '29'],
    [30, '30+'],
    [45, '30+'],
    [1234, '30+'],
  ])('counts %i unread news as %j after the preview', async (unreadCount, countText) => {
    TeactDOM.render(<AgentNewsRow unreadCount={unreadCount} onClick={jest.fn()} />, root);
    await pause(20);

    expect(root.textContent).toBe(`NewsCrypto Market News${countText}`);
  });
});

import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import AgentNewsRow from './AgentNewsRow';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));
// Each class name is its own key here
jest.mock('./AgentThreadList.module.scss', () => new Proxy({}, {
  get: (target, key) => (key === '__esModule' ? false : key),
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
    [0, '', false],
    [1, '1', false],
    [10, '10', false],
    [11, '', true],
    [1234, '', true],
  ])('marks %i unread news with %j after the preview, or with a dot alone', async (unreadCount, countText, hasDot) => {
    TeactDOM.render(<AgentNewsRow unreadCount={unreadCount} onClick={jest.fn()} />, root);
    await pause(20);

    expect(root.textContent).toBe(`NewsCrypto Market News${countText}`);
    expect(Boolean(root.querySelector('.unreadDot'))).toBe(hasDot);
  });
});

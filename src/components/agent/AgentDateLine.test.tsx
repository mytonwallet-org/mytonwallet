import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';

import DropdownMenu from '../ui/DropdownMenu';
import AgentDateLine from './AgentDateLine';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));
jest.mock('../ui/DropdownMenu', () => ({ __esModule: true, default: jest.fn(() => undefined) }));

describe('AgentDateLine', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('centers its Copy menu on the line', async () => {
    TeactDOM.render(<AgentDateLine timestamp={Date.UTC(2026, 9, 21, 9)} />, root);
    await pause(20);

    const line = root.firstElementChild as HTMLElement;
    line.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, button: 2, clientX: 5, clientY: 5 }));
    await pause(20);

    const menuProps = jest.mocked(DropdownMenu).mock.calls.at(-1)![0];
    expect(menuProps.getTriggerElement!()).toBe(line);
    expect(menuProps.getLayout!()).toMatchObject({ withPortal: true, isCenteredHorizontally: true });
  });
});

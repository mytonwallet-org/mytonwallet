import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import { pause } from '../../util/schedulers';
import { copyAgentText } from './helpers/copyAgentText';

import DropdownMenu from '../ui/DropdownMenu';
import AgentDateLine from './AgentDateLine';

let mockIsPortrait = false;

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
}));
jest.mock('../../hooks/useDeviceScreen', () => ({ useDeviceScreen: () => ({ isPortrait: mockIsPortrait }) }));
// Every style module maps to the same stub, so its one mock names the classes of the line and of the menu's tint
jest.mock('./Agent.module.scss', () => ({
  dateLine: 'date-line',
  dateLineDayHeader: 'date-line-day-header',
  dateSeparator: 'date-separator',
  dateSeparatorDay: 'date-separator-day',
  backdrop: 'menu-backdrop',
  visible: 'visible',
  wrapperVisible: 'over-menu-backdrop',
  wrapperHide: 'hiding',
}));
jest.mock('../ui/DropdownMenu', () => ({ __esModule: true, default: jest.fn(() => undefined) }));
jest.mock('./helpers/copyAgentText', () => ({ copyAgentText: jest.fn() }));

describe('AgentDateLine', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    mockIsPortrait = false;
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('centers its Copy menu on the line', async () => {
    const line = await openMenu();

    const menuProps = jest.mocked(DropdownMenu).mock.calls.at(-1)![0];
    expect(menuProps.isOpen).toBe(true);
    expect(menuProps.getTriggerElement!()).toBe(line);
    expect(menuProps.getLayout!()).toMatchObject({ withPortal: true, isCenteredHorizontally: true });
    // Off a phone the chat behind the menu is not tinted
    expect(root.querySelector('.menu-backdrop')).toBeNull();
    expect(line.classList.contains('over-menu-backdrop')).toBe(false);
  });

  it('tints the chat behind its menu on a phone, with the line over the tint', async () => {
    mockIsPortrait = true;
    const line = await openMenu();

    // The list keeps one element for each item, which holds the line and the tint
    expect(root.children).toHaveLength(1);
    expect(root.firstElementChild!.classList.contains('date-line')).toBe(true);
    expect(line.previousElementSibling!.classList.contains('menu-backdrop')).toBe(true);
    expect(line.classList.contains('over-menu-backdrop')).toBe(true);
  });

  it('names the day alone over a day of the news feed, and copies it alone', async () => {
    const line = await openMenu(true);

    expect(root.firstElementChild!.classList.contains('date-line-day-header')).toBe(true);
    const day = line.querySelector('.date-separator-day')!.textContent;
    expect(line.textContent).toBe(day);

    jest.mocked(DropdownMenu).mock.calls.at(-1)![0].onSelect!('copy');
    expect(copyAgentText).toHaveBeenLastCalledWith(day, '$agent_copied');
  });

  async function openMenu(isDayHeader = false) {
    TeactDOM.render(<AgentDateLine timestamp={Date.UTC(2026, 9, 21, 9)} isDayHeader={isDayHeader} />, root);
    await pause(20);

    const line = root.querySelector<HTMLElement>('.date-separator')!;
    line.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, button: 2, clientX: 5, clientY: 5 }));
    await pause(20);

    return line;
  }
});

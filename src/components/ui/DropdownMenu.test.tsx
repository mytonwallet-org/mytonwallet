import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { DropdownItem } from './Dropdown';

import { pause } from '../../util/schedulers';

import DropdownMenu from './DropdownMenu';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en', isRtl: false }),
}));
jest.mock('./Menu.module.scss', () => ({ backdrop: 'backdrop', bubble: 'bubble' }));
jest.mock('../../util/windowSize', () => ({
  __esModule: true,
  default: { get: () => ({ width: 1024, height: 600, safeAreaBottom: 0 }) },
}));

type Value = 'sources' | 'source' | 'copy';

const ITEMS: DropdownItem<Value>[] = [
  { value: 'sources', name: 'Sources', subItems: [{ value: 'source', name: 'Source' }] },
  { value: 'copy', name: 'Copy' },
];
const MANY_SOURCES: DropdownItem<string>[] = [{
  value: 'sources',
  name: 'Sources',
  subItems: Array.from({ length: 16 }, (_, index) => ({ value: `source-${index}`, name: `Source ${index}` })),
}];

describe('DropdownMenu', () => {
  let root: HTMLDivElement;
  let portals: HTMLDivElement;
  let onSelect: jest.Mock;
  let onClose: jest.Mock;

  beforeEach(async () => {
    root = document.createElement('div');
    portals = document.createElement('div');
    portals.id = 'portals';
    document.body.appendChild(root);
    document.body.appendChild(portals);
    onSelect = jest.fn();
    onClose = jest.fn();
    TeactDOM.render(<DropdownMenu isOpen items={ITEMS} onSelect={onSelect} onClose={onClose} />, root);
    await pause(20);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    portals.remove();
  });

  it('keeps the submenu that hovering an item opened when the item is then clicked', async () => {
    const sourcesButton = findButton('Sources');
    sourcesButton.dispatchEvent(new MouseEvent('mouseenter'));
    await pause(20);
    expect(sourcesButton.getAttribute('aria-expanded')).toBe('true');

    sourcesButton.click();
    await pause(20);

    expect(sourcesButton.getAttribute('aria-expanded')).toBe('true');
    expect(onSelect).not.toHaveBeenCalled();
    findButton('Source').click();
    expect(onSelect).toHaveBeenCalledWith('source', expect.anything());
  });

  it('keeps its backdrop under an open submenu, so the press that closes it misses what is beneath', async () => {
    findButton('Sources').click();
    await pause(200);
    expect(root.querySelector('.backdrop')).not.toBeNull();

    // A press in the submenu keeps the menus open
    findButton('Source').dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
    expect(onClose).not.toHaveBeenCalled();

    const backdrop = root.querySelector('.backdrop')!;
    const mouseDown = new MouseEvent('mousedown', { bubbles: true, cancelable: true });
    backdrop.dispatchEvent(mouseDown);
    expect(onClose).toHaveBeenCalledTimes(1);
    expect(mouseDown.defaultPrevented).toBe(true);
  });

  it('places a submenu taller than the screen allows by the height it is shown at', async () => {
    TeactDOM.render(<DropdownMenu isOpen items={MANY_SOURCES} onClose={onClose} />, root);
    await pause(20);
    findButton('Sources').click();
    await pause(20);

    // 16 rows are 720px, more than the 360px, 60vh of the 600px window, the menu is shown at
    const subMenu = findButton('Source 0').closest<HTMLElement>('.menu-bubble')!.parentElement!;
    expect(parseFloat(subMenu.style.top)).toBeGreaterThanOrEqual(16);
  });
});

function findButton(name: string) {
  return Array.from(document.body.querySelectorAll('button')).find(({ textContent }) => textContent === name)!;
}

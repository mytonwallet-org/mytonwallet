import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentMessage } from '../../global/types';

import { pause } from '../../util/schedulers';

import MessageBubble from './MessageBubble';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
  LangProvider: ({ children }: { children: unknown }) => children,
  useLangForCode: () => Object.assign((key: string) => key, { code: 'en' }),
}));

describe('a message menu', () => {
  let root: HTMLDivElement;
  let portals: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    portals = document.createElement('div');
    portals.id = 'portals';
    document.body.appendChild(portals);
    jest.spyOn(document.body, 'getBoundingClientRect').mockReturnValue({
      x: 0, y: 0, left: 0, top: 0, right: 402, bottom: 874, width: 402, height: 874, toJSON: () => undefined,
    });
    // jsdom computes no margins, which the menu's placement adds up
    const { getComputedStyle } = window;
    jest.spyOn(window, 'getComputedStyle').mockImplementation((element, pseudo) => {
      const style = getComputedStyle(element, pseudo);
      return new Proxy(style, {
        get: (target, property) => {
          if (property === 'marginTop') return target.marginTop || '0px';
          const value: unknown = Reflect.get(target, property);
          return typeof value === 'function' ? value.bind(target) : value;
        },
      });
    });
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    portals.remove();
    jest.restoreAllMocks();
  });

  const message: AgentMessage = {
    id: 3, text: 'You hold 12 TON', timestamp: 0, isOutgoing: false,
  };

  async function openMenu(init: MouseEventInit, pointerType?: string) {
    TeactDOM.render(<MessageBubble message={message} isDisabled={false} />, root);
    await pause(20);
    const event = new MouseEvent('contextmenu', { bubbles: true, cancelable: true, ...init });
    if (pointerType) Object.defineProperty(event, 'pointerType', { value: pointerType });
    root.querySelector('[data-agent-static-text]')!.dispatchEvent(event);
    await pause(50);
    return [...portals.querySelectorAll<HTMLElement>('[style]')].find((element) => element.style.left);
  }

  it('opens at the pointer on a right click, as a token\'s does', async () => {
    const menu = await openMenu({ button: 2, clientX: 200, clientY: 150 });

    expect(menu?.style.left).toBe('203px');
    expect(menu?.style.top).toBe('154px');
  });

  it('hangs from the bubble after a long press on a touch screen', async () => {
    // jsdom lays the bubble out at the window's top
    const menu = await openMenu({ clientX: 200, clientY: 150 }, 'touch');

    expect(menu?.style.top).toBe('6px');
  });
});

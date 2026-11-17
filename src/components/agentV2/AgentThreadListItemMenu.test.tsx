import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentThreadListItemV2 } from '../../api/agentV2/protocol/types';

import { pause } from '../../util/schedulers';

import AgentThreadListItem from './AgentThreadListItem';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string, value?: string) => (
    key === '$agent_digest_discussion_title' ? `News for ${value}` : key
  ), { code: 'en' }),
  LangProvider: ({ children }: { children: unknown }) => children,
  useLangForCode: () => Object.assign((key: string) => key, { code: 'en' }),
}));

describe('a chat row menu', () => {
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

  const item: AgentThreadListItemV2 = {
    thread: {
      id: 'thread-1',
      revision: 1,
      createdAt: '2026-08-11T10:00:00.000Z',
      updatedAt: '2026-08-11T10:00:00.000Z',
      lastActivityAt: '2026-08-11T10:00:00.000Z',
      messageCount: 2,
      title: 'Staking',
    },
    preview: 'How does staking work?',
  };

  async function openMenu(init: MouseEventInit, pointerType?: string) {
    TeactDOM.render(
      <AgentThreadListItem
        item={item}
        isUnread={false}
        onSelect={jest.fn()}
        onRename={jest.fn()}
        onTogglePin={jest.fn()}
        onDelete={jest.fn()}
      />,
      root,
    );
    await pause(20);
    const event = new MouseEvent('contextmenu', { bubbles: true, cancelable: true, ...init });
    if (pointerType) Object.defineProperty(event, 'pointerType', { value: pointerType });
    root.querySelector('[data-agent-row-key]')!.dispatchEvent(event);
    await pause(50);
    return [...portals.querySelectorAll<HTMLElement>('[style]')].find((element) => element.style.left);
  }

  it('opens at the pointer on a right click, as a token\'s and a message\'s do', async () => {
    const menu = await openMenu({ button: 2, clientX: 200, clientY: 150 });

    expect(menu?.style.left).toBe('203px');
    expect(menu?.style.top).toBe('154px');
  });

  it('hangs from the row rather than the touch after a long press on a touch screen', async () => {
    const menu = await openMenu({ clientX: 200, clientY: 150 }, 'touch');

    expect(menu).toBeDefined();
    expect(menu?.style.top).not.toBe('154px');
  });
});

describe('a chat row title', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  const windowEnd = new Date(new Date().getFullYear(), 10, 11, 9).toISOString();
  const digestItem: AgentThreadListItemV2 = {
    thread: {
      id: 'thread-1',
      revision: 1,
      createdAt: windowEnd,
      updatedAt: windowEnd,
      lastActivityAt: windowEnd,
      messageCount: 2,
      icon: '🗓',
      digest: { id: 'en:digest', windowEnd, total: 1, top: [{ eventId: 42, headline: 'TON update' }] },
    },
    preview: 'What changed in the TON network?',
  };

  it.each([
    ['names a digest\'s discussion by its day, over its preview', digestItem, 'News for November 11',
      'What changed in the TON network?'],
    ['keeps the name the user gave a digest\'s discussion', {
      ...digestItem, thread: { ...digestItem.thread, title: 'My digest' },
    }, 'My digest', 'What changed in the TON network?'],
  ])('%s', async (_name, item, title, preview) => {
    TeactDOM.render(
      <AgentThreadListItem
        item={item}
        isUnread={false}
        onSelect={jest.fn()}
        onRename={jest.fn()}
        onTogglePin={jest.fn()}
        onDelete={jest.fn()}
      />,
      root,
    );
    await pause(20);

    // The row shows its title over its preview, and its label reads them in the same order
    const [top, bottom] = Array.from(root.querySelector('[role="button"] > div[aria-hidden]')!.children);
    expect(top.querySelector('span')!.textContent).toBe(title);
    expect(bottom.querySelector('span')!.textContent).toBe(preview);
    const label = root.querySelector('[role="button"]')!.getAttribute('aria-label')!;
    expect(label.split(', ').slice(0, 2)).toEqual([title, preview]);
  });
});

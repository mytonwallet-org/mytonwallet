import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentMessage } from '../../global/types';

import { copyTextToClipboard } from '../../util/clipboard';
import { pause } from '../../util/schedulers';

import MessageBubble from './MessageBubble';

jest.mock('../../util/clipboard', () => ({ copyTextToClipboard: jest.fn() }));
jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string) => key, { code: 'en' }),
  LangProvider: ({ children }: { children: unknown }) => children,
  useLangForCode: () => Object.assign((key: string) => key, { code: 'en' }),
}));

describe('copying Agent answers', () => {
  let root: HTMLDivElement;
  let portals: HTMLDivElement;

  beforeEach(() => {
    jest.clearAllMocks();
    root = document.createElement('div');
    document.body.appendChild(root);
    portals = document.createElement('div');
    portals.id = 'portals';
    document.body.appendChild(portals);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    portals.remove();
  });

  it.each(['🪙\n\nAfter', ''])('copies table cells and notes within the answer %j', async (text) => {
    const message: AgentMessage = {
      id: 1,
      text,
      timestamp: 0,
      isOutgoing: false,
      tables: [{ id: 't1', content: { kind: 'display',
        headers: ['Asset', 'Value'],
        rows: [['A & B_[token]', '123456789.000000001 TON']],
        notes: ['Partial data'],
      } }],
      tableReferences: [{ tableId: 't1', textOffset: text ? 4 : 0 }],
    };
    TeactDOM.render(<MessageBubble message={message} isDisabled={false} />, root);
    await pause(20);

    root.querySelector('[data-agent-static-text]')!.dispatchEvent(new MouseEvent('contextmenu', {
      bubbles: true,
      clientX: 10,
      clientY: 10,
    }));
    await pause(20);
    const copyButton = Array.from(document.querySelectorAll('button'))
      .find((button) => button.textContent === 'Copy');
    expect(copyButton).toBeDefined();
    copyButton!.click();

    const tableText = 'Partial data\n\nAsset\tValue\nA & B_[token]\t123456789.000000001 TON';
    expect(copyTextToClipboard).toHaveBeenCalledWith(text ? `🪙\n\n\n\n${tableText}\n\nAfter` : `\n\n${tableText}\n\n`);
  });

  it('offers a finished answer for a problem report, but not one still being written', async () => {
    const onReport = jest.fn();
    const message: AgentMessage = {
      id: 7, text: 'You hold 12 TON', timestamp: 0, isOutgoing: false,
    };

    const openMenu = async (isStreaming: boolean) => {
      TeactDOM.render(
        <MessageBubble message={{ ...message, isStreaming }} isDisabled={false} onReport={onReport} />,
        root,
      );
      await pause(20);
      root.querySelector('[data-agent-v2-message-id="7"] [data-agent-static-text]')!
        .dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, clientX: 10, clientY: 10 }));
      await pause(20);
      return Array.from(document.querySelectorAll('button'));
    };

    const streamingMenu = (await openMenu(true)).map((button) => button.textContent);
    expect(streamingMenu).toContain('Copy');
    expect(streamingMenu).not.toContain('Report a Problem');
    (await openMenu(false)).find((button) => button.textContent === 'Report a Problem')!.click();

    expect(onReport).toHaveBeenCalledWith(7);
  });
});

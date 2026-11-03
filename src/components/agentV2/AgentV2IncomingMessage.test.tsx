import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentMessage } from '../../global/types';

import { pause } from '../../util/schedulers';

import MessageBubble from '../agent/MessageBubble';

const mockResponseLang = Object.assign((key: string) => key, {
  code: 'ar',
  isRtl: true,
});

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => mockResponseLang,
  LangProvider: ({ children }: { children: unknown }) => children,
  useLangForCode: () => mockResponseLang,
}));

describe('AgentV2IncomingMessage', () => {
  let root: HTMLDivElement;
  let portals: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    root.dir = 'ltr';
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

  it('inherits text direction from the interface instead of the response language', async () => {
    TeactDOM.render(
      <MessageBubble
        message={message()}
        isDisabled={false}
      />,
      root,
    );
    await pause(20);

    const response = root.querySelector<HTMLElement>('[lang="ar"]')!;
    expect(response.getAttribute('dir')).toBeNull();
    expect(response.closest('[dir]')).toBe(root);
  });

  it('rates a complete answer from its menu and withdraws the chosen rating on a second press', async () => {
    const onRate = jest.fn();
    TeactDOM.render(
      <>
        <MessageBubble
          message={{ ...message(), id: 1, isComplete: true, feedback: 'like' }}
          isDisabled
          onRate={onRate}
        />
        <MessageBubble message={{ ...message(), id: 2 }} isDisabled={false} onRate={onRate} />
      </>,
      root,
    );
    await pause(20);

    async function openMenu(id: number) {
      root.querySelector(`[data-agent-v2-message-id="${id}"] [data-agent-static-text]`)!
        .dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, clientX: 10, clientY: 10 }));
      await pause(20);
      return Array.from(document.body.querySelectorAll<HTMLButtonElement>('button[aria-pressed]'));
    }

    expect(await openMenu(2)).toEqual([]);

    const buttons = await openMenu(1);
    expect(buttons.map((button) => [button.getAttribute('aria-label'), button.getAttribute('aria-pressed')]))
      .toEqual([['Like', 'true'], ['Dislike', 'false']]);
    buttons[0].click();
    (await openMenu(1))[1].click();
    expect(onRate.mock.calls).toEqual([[1, undefined], [1, 'dislike']]);
  });

  it('drops the activity at once when the answer fails', async () => {
    function renderAnswer(error?: AgentMessage['error']) {
      TeactDOM.render(
        <MessageBubble
          message={{ ...message(), text: '', followups: undefined, ...(error && { error }) }}
          isDisabled={false}
          isLatest
          activity={{ kind: 'preparingResponse' }}
        />,
        root,
      );
    }

    renderAnswer();
    await pause(20);
    expect(root.querySelector('[data-agent-activity-step]')).not.toBeNull();

    renderAnswer({ code: 'provider_error', retryable: true });
    // Well before the activity's own 200 ms fade would end
    await pause(20);
    expect(root.querySelector('[data-agent-activity-step]')).toBeNull();
    expect(root.querySelector('[data-agent-v2-message-status="error"]')).not.toBeNull();
  });

  it('keeps the suggestions of an answer being answered again as they are, out of reach', async () => {
    function renderAnswer(isRegenerating: boolean) {
      TeactDOM.render(
        <MessageBubble
          message={message()}
          isDisabled
          isLatest
          areFollowupsHeld
          isRegenerating={isRegenerating}
        />,
        root,
      );
    }

    renderAnswer(true);
    await pause(20);
    const followup = root.querySelector<HTMLButtonElement>('[data-agent-followup-id="followup"]')!;
    expect(followup.disabled).toBe(false);
    expect(followup.closest<HTMLElement>('[data-agent-v2-message-id]')!.inert).toBe(true);

    renderAnswer(false);
    await pause(250);
    expect(root.querySelector('[data-agent-followup-id]')).toBeNull();
  });
});

function message(): AgentMessage {
  return {
    id: 1,
    text: 'Arabic response',
    isOutgoing: false,
    timestamp: Date.now(),
    responseLanguage: 'ar',
    followups: [{ id: 'followup', kind: 'suggested_prompt', text: 'Follow up' }],
  };
}

import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentV2LiveAction } from '../../api/agentV2/protocol/types';
import type { AgentMessage } from '../../global/types';

import { pause, waitFor } from '../../util/schedulers';
import { formatAgentTime } from '../agent/helpers/agentDateFormat';
import { startTypingAnswerMorph } from '../agent/helpers/typingAnswerMorph';

import MessageBubble from '../agent/MessageBubble';

const mockResponseLang = Object.assign((key: string, value?: string) => (
  key === '$agent_daily_limit_resets_at' ? `${key}:${value}` : key
), {
  code: 'ar',
  isRtl: true,
});

// Telegram's animations of the reactions do not play here
jest.mock('../ui/AnimatedSticker', () => ({ __esModule: true, default: () => undefined }));

jest.mock('../agent/helpers/typingAnswerMorph', () => ({
  ...jest.requireActual('../agent/helpers/typingAnswerMorph'),
  startTypingAnswerMorph: jest.fn(),
}));

// Class names are their own keys, so that the bubble's look can be read from them. Style modules and assets resolve to
// one stub, which still reads as a file where an asset's URL is used.
jest.mock('../agent/MessageBubble.module.scss', () => new Proxy({}, {
  get: (target, key) => {
    if (key === '__esModule') return false;
    if (key === Symbol.toPrimitive) return () => 'test-file-stub';
    return key;
  },
}));

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
    jest.mocked(startTypingAnswerMorph).mockClear();
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
    const onRate = jest.fn().mockResolvedValue(() => true);
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
    expect(await waitFor(() => portals.querySelectorAll('.menu-bubble').length === 1, 10, 100)).toBe(true);
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
          isActivityHost
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

  it('keeps a daily refusal timed until its reset, then leaves its untimed caption', async () => {
    const resetAt = new Date(Date.now() + 1_000).toISOString();
    TeactDOM.render(
      <MessageBubble
        message={{ ...message(), text: '', error: { code: 'user_quota_exhausted', retryable: true, resetAt } }}
        isDisabled={false}
      />,
      root,
    );
    await pause(20);

    expect(root.textContent).toContain(`$agent_daily_limit_resets_at:${formatAgentTime('ar', resetAt)}`);
    expect(await waitFor(() => root.textContent!.includes('$agent_daily_limit_reached'), 10, 2_000)).toBe(true);
    expect(root.textContent).not.toContain('$agent_daily_limit_resets_at');
  });

  it('grows the answer\'s bubble out of the run\'s indicator as its first text comes', async () => {
    function renderAnswer(text: string, shouldAnimate = true) {
      TeactDOM.render(
        <MessageBubble
          message={{ ...message(), text, followups: undefined }}
          isDisabled={false}
          isLatest
          isActivityHost
          shouldAnimateTextStreaming={shouldAnimate}
          activity={text ? undefined : { kind: 'preparingResponse' }}
        />,
        root,
      );
    }

    renderAnswer('');
    await pause(20);
    expect(startTypingAnswerMorph).not.toHaveBeenCalled();

    renderAnswer('The answer');
    await pause(20);
    expect(startTypingAnswerMorph).toHaveBeenCalledTimes(1);
    const [row, bubble] = jest.mocked(startTypingAnswerMorph).mock.calls[0];
    expect(row).toBe(root.querySelector('[data-agent-run-activity]'));
    expect(bubble.textContent).toContain('The answer');
    expect(row.contains(bubble)).toBe(false);

    // Where motion is reduced, the bubble takes the indicator's place without growing out of it
    TeactDOM.render(undefined, root);
    jest.mocked(startTypingAnswerMorph).mockClear();
    renderAnswer('', false);
    await pause(20);
    renderAnswer('The answer', false);
    await pause(20);
    expect(startTypingAnswerMorph).not.toHaveBeenCalled();
  });

  it('grows the bubble of an answer that questions wait under out of the run\'s indicator', async () => {
    function renderAnswer(text: string) {
      TeactDOM.render(
        <MessageBubble
          message={{ ...message(), text, followups: undefined }}
          isDisabled={false}
          isActivityHost
          shouldAnimateTextStreaming
          activity={text ? undefined : { kind: 'preparingResponse' }}
        />,
        root,
      );
    }

    renderAnswer('');
    await pause(20);
    renderAnswer('The answer');
    await pause(20);
    expect(startTypingAnswerMorph).toHaveBeenCalledTimes(1);
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

  it('takes the tail away while suggestions hang from the answer and gives it back once they go', async () => {
    const action = { id: 'send', kind: 'send', title: 'Review transfer' } as AgentV2LiveAction;
    function renderAnswer(props: { isLatest?: boolean; areFollowupsHeld?: boolean; hasActions?: boolean } = {}) {
      const { isLatest = true, areFollowupsHeld = false, hasActions = false } = props;
      TeactDOM.render(
        <MessageBubble
          message={{ ...message(), ...(hasActions && { actions: [action] }) }}
          isDisabled={false}
          isLatest={isLatest}
          areFollowupsHeld={areFollowupsHeld}
        />,
        root,
      );
    }
    const getIsTailless = () => root.querySelector('.bubble.incoming')!.classList.contains('tailless');

    renderAnswer();
    await pause(20);
    expect(root.querySelector('[data-agent-followup-id]')).not.toBeNull();
    expect(getIsTailless()).toBe(true);

    // A tapped suggestion starts a run, which takes the suggestions away before the question comes
    renderAnswer({ areFollowupsHeld: true });
    await pause(20);
    expect(getIsTailless()).toBe(false);

    renderAnswer();
    await pause(20);
    expect(getIsTailless()).toBe(true);

    // A new question takes them away as well
    renderAnswer({ isLatest: false });
    await pause(20);
    expect(getIsTailless()).toBe(false);

    // Action buttons hang from the bubble's body and leave the tail in place
    renderAnswer({ hasActions: true });
    await pause(20);
    expect(getIsTailless()).toBe(false);
  });

  it('shows inactive suggestions as pressable ones, which a press does not send until they are active', async () => {
    const onFollowup = jest.fn();
    function renderAnswer(areFollowupsInactive: boolean) {
      TeactDOM.render(
        <MessageBubble
          message={message()}
          isDisabled={areFollowupsInactive}
          isLatest
          areFollowupsInactive={areFollowupsInactive}
          onFollowup={onFollowup}
        />,
        root,
      );
    }

    renderAnswer(true);
    await pause(20);
    const followup = root.querySelector<HTMLButtonElement>('[data-agent-followup-id="followup"]')!;
    expect(followup.disabled).toBe(false);
    expect(followup.getAttribute('aria-disabled')).toBe('true');
    followup.click();
    expect(onFollowup).not.toHaveBeenCalled();

    renderAnswer(false);
    await pause(20);
    const activeFollowup = root.querySelector<HTMLButtonElement>('[data-agent-followup-id="followup"]')!;
    expect(activeFollowup.hasAttribute('aria-disabled')).toBe(false);
    activeFollowup.click();
    expect(onFollowup).toHaveBeenCalledWith(1, message().followups![0]);
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

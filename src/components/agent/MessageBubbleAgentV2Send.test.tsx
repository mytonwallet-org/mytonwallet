import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentPersistedActionV2, AgentV2LiveAction } from '../../api/agentV2/protocol/types';
import type { AgentV2ActionPresentation } from '../../api/agentV2/types';
import type { AgentMessage } from '../../global/types';

import { pause } from '../../util/schedulers';

import MessageBubble from './MessageBubble';

const COPY: Record<string, string> = {
  $agent_error_generic: 'Agent could not complete the request. Please try again.',
  $agent_semantic_web_digest: 'Web results',
  Continue: 'Continue',
};
const ACTIVE_DRAFT_EXPIRES_AT = new Date(Date.now() + 10 * 60_000).toISOString();

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => (key: string) => COPY[key] ?? key,
  LangProvider: ({ children }: { children: unknown }) => children,
  useLangForCode: () => (key: string) => COPY[key] ?? key,
}));

describe('MessageBubble Agent V2 actions', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
  });

  it('renders arbitrary model titles literally while dispatching the same typed action', async () => {
    const action = { ...sendAction(), title: 'Проверить перевод 🪙' };
    const onAction = jest.fn();
    TeactDOM.render(
      <MessageBubble
        message={message(action, sendPresentation())}
        isDisabled={false}
        onAction={onAction}
      />, root);
    await pause(20);
    const button = root.querySelector('button')!;
    expect(button.textContent).toBe(action.title);
    button.click();
    await pause(0);
    expect(onAction).toHaveBeenCalledWith(1, action);
  });

  it('renders prepared Send as the standard action button and invokes the typed action', async () => {
    const action = sendAction();
    const onAction = jest.fn();
    TeactDOM.render(
      <MessageBubble
        message={message(action, sendPresentation())}
        isDisabled={false}
        onAction={onAction}
      />,
      root,
    );
    await pause(20);

    expect(root.textContent).toBe('Review transfer');
    expect(root.querySelectorAll('button[data-agent-action-kind="send"]')).toHaveLength(1);
    expect(root.querySelector('section')).toBeNull();
    const reviewButton = getReviewButton(root);
    expect(reviewButton.disabled).toBe(false);

    reviewButton.click();
    await pause(0);
    expect(onAction).toHaveBeenCalledWith(1, action);
  });

  it('disables prepared Send with parent blocking or an inactive presentation', async () => {
    const action = sendAction();
    const onAction = jest.fn();
    TeactDOM.render(
      <MessageBubble
        message={message(action, sendPresentation())}
        isDisabled
        onAction={onAction}
      />,
      root,
    );
    await pause(20);

    expect(getReviewButton(root).disabled).toBe(true);

    TeactDOM.render(
      <MessageBubble
        message={message(action, { kind: 'inactive' })}
        isDisabled={false}
        onAction={onAction}
      />,
      root,
    );
    await pause(20);

    expect(root.textContent).toBe('Review transfer');
    expect(getReviewButton(root).disabled).toBe(true);
    getReviewButton(root).click();
    expect(onAction).not.toHaveBeenCalled();
  });

  it('keeps a prepared Send enabled when its expiry is further out than a timer can hold', async () => {
    const action = sendAction();
    // Just past the 32-bit ceiling, where the delay wraps to a negative number and fires at once.
    const farFuture = new Date(Date.now() + 25 * 24 * 60 * 60 * 1000).toISOString();
    TeactDOM.render(
      <MessageBubble
        message={message(action, { ...sendPresentation(), expiresAt: farFuture })}
        isDisabled={false}
        onAction={jest.fn()}
      />,
      root,
    );
    await pause(20);

    expect(getReviewButton(root).disabled).toBe(false);
  });

  it('disables a prepared Send whose presentation is already expired', async () => {
    const action = sendAction();
    TeactDOM.render(
      <MessageBubble
        message={message(action, { ...sendPresentation(), expiresAt: '2000-01-01T00:00:00.000Z' })}
        isDisabled={false}
        onAction={jest.fn()}
      />,
      root,
    );
    await pause(20);

    expect(root.textContent).toBe('Review transfer');
    expect(getReviewButton(root).disabled).toBe(true);
  });

  it('renders every non-Send action and dispatches only after a click', async () => {
    const actions = nonSendActions();
    const onAction = jest.fn();
    TeactDOM.render(
      <MessageBubble
        message={messageWithActions(actions)}
        isDisabled={false}
        onAction={onAction}
      />,
      root,
    );
    await pause(20);

    expect(root.textContent).toContain('Open receive');
    expect(root.textContent).toContain('Open link');
    expect(onAction).not.toHaveBeenCalled();

    Array.from(root.querySelectorAll('button')).forEach((button) => button.click());
    await pause(0);

    expect(onAction.mock.calls).toEqual(actions.map((action) => [1, action]));
  });

  it('disables a non-Send action after local resolution marks it inactive', async () => {
    const action = nonSendActions()[0];
    const onAction = jest.fn();
    const inactiveMessage = messageWithActions([action]);
    inactiveMessage.actionPresentations = { [action.id]: { kind: 'inactive' } };

    TeactDOM.render(
      <MessageBubble
        message={inactiveMessage}
        isDisabled={false}
        onAction={onAction}
      />,
      root,
    );
    await pause(20);

    const button = root.querySelector('button')!;
    expect(button.disabled).toBe(true);
    button.click();
    expect(onAction).not.toHaveBeenCalled();
  });

  it('renders an incomplete Send action as the existing Open Send button', async () => {
    const action = sendFormAction();
    const onAction = jest.fn();
    TeactDOM.render(
      <MessageBubble
        message={message(action, {
          kind: 'send',
          status: 'active',
          network: 'ton',
          accountLabel: 'Main Wallet',
          recipient: { kind: 'savedAddress', label: 'DeFi' },
          feeStatus: 'calculated_in_wallet',
          warningCodes: [],
        })}
        isDisabled={false}
        onAction={onAction}
      />,
      root,
    );
    await pause(20);

    expect(root.textContent).toContain('Open Send');
    expect(root.textContent).not.toContain('Amount—');
    expect(root.textContent).not.toContain('DeFi');
    root.querySelector('button')?.click();
    await pause(0);
    expect(onAction).toHaveBeenCalledWith(1, action);
  });

  it('renders semantic notices as standard incoming text', async () => {
    TeactDOM.render(
      <MessageBubble
        message={{
          id: 1,
          text: '',
          isOutgoing: false,
          timestamp: Date.now(),
          semanticContent: { kind: 'notice', schemaVersion: 1, code: 'agent_unavailable' },
        }}
        isDisabled={false}
      />,
      root,
    );
    await pause(20);

    const incomingMessage = root.querySelector('[data-agent-v2-message-role="assistant"]');
    expect(incomingMessage?.textContent).toBe('Agent could not complete the request. Please try again.');
    expect(incomingMessage?.querySelector('section')).toBeNull();
  });

  it('renders model-authored deeplinks as passive text', async () => {
    TeactDOM.render(
      <MessageBubble
        message={{
          id: 1,
          text: '[Open Agent](mtw://agent)',
          isOutgoing: false,
          timestamp: Date.now(),
        }}
        isDisabled={false}
      />,
      root,
    );
    await pause(20);

    expect(root.textContent).toContain('Open Agent');
    expect(root.querySelector('button')).toBeNull();
  });

  it('preserves literal wallet links in code without creating an action', async () => {
    TeactDOM.render(
      <MessageBubble
        message={{ ...messageWithActions([]), text: '`[Receive](mtw://receive)`' }}
        isDisabled={false}
      />,
      root,
    );
    await pause(100);

    expect(root.querySelector('code')?.textContent).toBe('[Receive](mtw://receive)');
    expect(root.querySelector('a')).toBeNull();
    expect(root.querySelector('button')).toBeNull();
  });

  it('forwards V2 reveal completion after the response settles', async () => {
    const onTextRevealComplete = jest.fn();
    TeactDOM.render(
      <MessageBubble
        message={{
          id: 1,
          text: 'Completed answer',
          isOutgoing: false,
          timestamp: Date.now(),
        }}
        isDisabled={false}
        textRevealPresentation={{
          key: 'v2:1:1',
          status: 'active',
          shouldRevealFromStart: true,
        }}
        onTextRevealComplete={onTextRevealComplete}
      />,
      root,
    );
    await pause(20);

    expect(onTextRevealComplete).toHaveBeenCalledTimes(1);
  });
});

function sendAction() {
  return { ...sendFormAction(), title: 'Review transfer' };
}

function sendFormAction(): Extract<AgentV2LiveAction, { kind: 'send'; effect: 'open_send' }> {
  return {
    id: '66666666-6666-4666-8666-666666666660',
    kind: 'send',
    title: 'Open Send',
    labelCode: 'open_send',
    effect: 'open_send',
    contextBinding: {
      sessionId: '99999999-9999-4999-8999-999999999999',
      revision: 1,
      activeAccountRef: 'current',
      activeNetwork: 'ton',
    },
    asset: { slug: 'gram', chain: 'ton' },
    recipient: { kind: 'savedAddress', addressRef: 'address-defi' },
    localDraftRequired: false,
    requiresConfirmation: false,
  };
}

function sendPresentation(): Extract<AgentV2ActionPresentation, { kind: 'send' }> {
  return {
    kind: 'send',
    status: 'active',
    amount: { value: '1.5', symbol: 'TON' },
    network: 'ton',
    accountLabel: 'Main Wallet',
    recipient: { kind: 'savedAddress', label: 'Mom' },
    feeStatus: 'calculated_in_wallet',
    warningCodes: ['new_address'],
    expiresAt: ACTIVE_DRAFT_EXPIRES_AT,
  };
}

function message(
  action: Extract<AgentV2LiveAction | AgentPersistedActionV2, { kind: 'send' }>,
  presentation: AgentV2ActionPresentation,
): AgentMessage {
  return {
    id: 1,
    text: '',
    isOutgoing: false,
    timestamp: Date.now(),
    actions: [action],
    actionPresentations: { [action.id]: presentation },
  };
}

function messageWithActions(actions: AgentV2LiveAction[]): AgentMessage {
  return {
    id: 1,
    text: '',
    isOutgoing: false,
    timestamp: Date.now(),
    actions,
  };
}

function nonSendActions(): AgentV2LiveAction[] {
  return [
    {
      id: '66666666-6666-4666-8666-666666666661',
      kind: 'receive',
      title: 'Open receive',
      labelCode: 'open_receive',
      effect: 'open_receive',
      contextBinding: {
        sessionId: '99999999-9999-4999-8999-999999999999',
        revision: 1,
        activeAccountRef: 'current',
        activeNetwork: 'ton',
      },
      localDraftRequired: false,
      requiresConfirmation: false,
    },
    {
      id: '66666666-6666-4666-8666-666666666663',
      schemaVersion: 1,
      kind: 'openDapp',
      title: 'Open link',
      labelCode: 'open_external_link',
      url: 'https://example.com/help',
      requiresConfirmation: true,
    },
  ];
}

function getReviewButton(root: HTMLElement) {
  const button = Array.from(root.querySelectorAll('button'))
    .find(({ textContent }) => textContent === 'Review transfer');
  if (!button) throw new Error('Review transfer button was not rendered');
  return button;
}

import type { AgentV2LiveAction } from './protocol/types';

import { hostUiCapabilities } from './testing/hostUiCapabilities';
import { AgentV2ActionResolver } from './actionResolver';
import { AgentV2WalletSession } from './walletSession';

const THREAD_ID = 'thread';
const MESSAGE_ID = 'message';

function navigationAction(id: string): Extract<AgentV2LiveAction, { kind: 'openDapp' }> {
  return {
    id, title: 'Open link', schemaVersion: 1, kind: 'openDapp', labelCode: 'open_external_link',
    url: 'https://example.com', requiresConfirmation: true,
  };
}

describe('AgentV2ActionResolver retention', () => {
  it('withdraws live and persisted navigation when the host no longer supports it', () => {
    const session = navigationSession();
    const actions = new AgentV2ActionResolver(session);
    actions.registerAction(THREAD_ID, MESSAGE_ID, navigationAction('live'));
    actions.registerPersistedAction(THREAD_ID, MESSAGE_ID, { ...navigationAction('persisted'), schemaVersion: 3 });
    session.update({
      ...session.snapshot().host!,
      uiCapabilities: { ...hostUiCapabilities(), supportedActions: [] },
    });
    expect(actions.resolveAction(MESSAGE_ID, 'live')).toEqual({ kind: 'inactive' });
    expect(actions.resolveAction(MESSAGE_ID, 'persisted')).toEqual({ kind: 'inactive' });
  });

  it('bounds live and persisted actions together and expires them at the exact deadline', () => {
    let now = 0;
    const actions = new AgentV2ActionResolver(navigationSession(), () => now);
    for (let index = 0; index < 513; index++) {
      const action = navigationAction(String(index));
      if (index % 2) {
        actions.registerAction(THREAD_ID, MESSAGE_ID, action);
      } else {
        actions.registerPersistedAction(THREAD_ID, MESSAGE_ID, { ...action, schemaVersion: 3 });
      }
    }
    expect(actions.resolveAction(MESSAGE_ID, '0')).toEqual({ kind: 'inactive' });
    expect(actions.resolveAction(MESSAGE_ID, '1')).toEqual({ kind: 'openDapp', url: 'https://example.com' });
    now = 24 * 60 * 60_000 - 1;
    expect(actions.resolveAction(MESSAGE_ID, '512')).toEqual({ kind: 'openDapp', url: 'https://example.com' });
    now += 1;
    expect(actions.resolveAction(MESSAGE_ID, '1')).toEqual({ kind: 'inactive' });
    expect(actions.resolveAction(MESSAGE_ID, '512')).toEqual({ kind: 'inactive' });
  });

  it('isolates message bindings and clears live and persisted actions for only the requested thread', () => {
    const actions = new AgentV2ActionResolver(navigationSession());
    actions.registerAction(THREAD_ID, MESSAGE_ID, navigationAction('live'));
    actions.registerPersistedAction(THREAD_ID, MESSAGE_ID, { ...navigationAction('persisted'), schemaVersion: 3 });
    actions.registerAction('other-thread', 'other-message', navigationAction('live'));
    expect(actions.resolveAction('unknown-message', 'live')).toEqual({ kind: 'inactive' });

    actions.clear(THREAD_ID);
    expect(actions.resolveAction(MESSAGE_ID, 'live')).toEqual({ kind: 'inactive' });
    expect(actions.resolveAction(MESSAGE_ID, 'persisted')).toEqual({ kind: 'inactive' });
    expect(actions.resolveAction('other-message', 'live')).toEqual({ kind: 'openDapp', url: 'https://example.com' });

    actions.clear();
    expect(actions.resolveAction('other-message', 'live')).toEqual({ kind: 'inactive' });
  });

  it('prefers the live binding to a hydrated action with the same message and action id', () => {
    const actions = new AgentV2ActionResolver(navigationSession());
    actions.registerAction(THREAD_ID, MESSAGE_ID, navigationAction('link'));
    actions.registerPersistedAction(THREAD_ID, MESSAGE_ID, {
      ...navigationAction('link'), schemaVersion: 3, url: 'https://example.com/hydrated',
    });
    expect(actions.resolveAction(MESSAGE_ID, 'link')).toEqual({ kind: 'openDapp', url: 'https://example.com' });
  });
});

function navigationSession() {
  const session = new AgentV2WalletSession();
  session.update({
    platform: 'classic', client: 'web', lang: 'en', baseCurrency: 'USD',
    uiCapabilities: hostUiCapabilities(), accounts: [], savedAddresses: [],
  });
  return session;
}

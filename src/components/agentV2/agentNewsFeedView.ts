import type { AgentNewsFeedRequestV2 } from '../../api/agentV2/protocol/types';

import { createCallbackManager } from '../../util/callbacks';

export type AgentNewsFeedView = NonNullable<AgentNewsFeedRequestV2['view']>;

const STORAGE_KEY = 'mytonwallet-agent-mypulse-news-view';
const viewChanges = createCallbackManager<(view: AgentNewsFeedView) => void>();
let fallbackView: AgentNewsFeedView = 'all';
let hasWriteFailed = false;

export function setAgentNewsFeedView(view: AgentNewsFeedView) {
  const previousView = getAgentNewsFeedView();
  fallbackView = view;
  if (view === previousView) return;

  try {
    localStorage.setItem(STORAGE_KEY, view);
    hasWriteFailed = false;
  } catch {
    hasWriteFailed = true;
  }
  viewChanges.runCallbacks(view);
}

export function subscribeToAgentNewsFeedView(callback: (view: AgentNewsFeedView) => void) {
  const unsubscribe = viewChanges.addCallback(callback);
  function handleStorage(event: StorageEvent) {
    if (event.storageArea === localStorage && (!event.key || event.key === STORAGE_KEY)) {
      callback(getAgentNewsFeedView());
    }
  }
  window.addEventListener('storage', handleStorage);
  return () => {
    unsubscribe();
    window.removeEventListener('storage', handleStorage);
  };
}

export function getAgentNewsFeedView(): AgentNewsFeedView {
  if (hasWriteFailed) return fallbackView;
  try {
    const view = localStorage.getItem(STORAGE_KEY);
    fallbackView = view === 'all' || view === 'digests' ? view : 'all';
  } catch {
    // The last selection survives remounts while storage is unavailable
  }
  return fallbackView;
}

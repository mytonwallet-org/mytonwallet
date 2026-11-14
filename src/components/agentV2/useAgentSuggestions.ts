import { useEffect, useMemo, useRef, useState } from '../../lib/teact/teact';
import { getGlobal } from '../../global';

import type { AgentThreadListItemV2 } from '../../api/agentV2/protocol/types';
import type { AgentV2HintWalletState, AgentV2StarterHints } from '../../api/agentV2/types';
import type { AgentHint, GlobalState } from '../../global/types';
import type { ChatSelection } from '../../util/agent/agentV2LocalState';
import type { LangFn } from '../../util/langProvider';
import type { AgentV2ChatTarget } from '../agent/hooks/useAgentV2Messages';

import { getIsAgentV2SupportEntryVisible } from '../../global/agentV2/uiCapabilities';
import {
  selectAccountStakingStates,
  selectCurrentAccountId,
  selectCurrentAccountTokens,
} from '../../global/selectors';
import { calculateFullBalance } from '../../util/calculateFullBalance';
import { callApi } from '../../api';
import { mapAgentV2StarterHints } from './agentV2Copy';
import { findAgentV2SupportThread } from './useAgentV2ThreadList';

import useSyncEffect from '../../hooks/useSyncEffect';

interface AgentV2StarterHintsView {
  starterHints: AgentV2StarterHints;
  hints: AgentHint[];
}

/**
 * The questions suggested for a new chat while the user composes one under the chat list. Each time they are shown,
 * one hint of each group is picked anew, and the pick stays while they are on screen and as they leave.
 */
export default function useAgentSuggestions(lang: LangFn, isShown: boolean) {
  const [pick, setPick] = useState<{ showingId: number; starterHints: AgentV2StarterHints }>();
  const showingIdRef = useRef(0);
  // A new showing drops the previous pick at once, before its own comes
  useSyncEffect(() => {
    if (isShown) showingIdRef.current += 1;
  }, [isShown]);

  useEffect(() => {
    if (!isShown) return undefined;

    const showingId = showingIdRef.current;
    let isCurrent = true;
    void loadAgentV2StarterHints().then((starterHints) => {
      // A failed load shows no hints
      if (isCurrent) setPick(starterHints && { showingId, starterHints });
    });

    return () => {
      isCurrent = false;
    };
  }, [isShown]);

  const starterHints = pick?.showingId === showingIdRef.current ? pick.starterHints : undefined;
  return useMemo<AgentV2StarterHintsView | undefined>(() => starterHints && {
    starterHints,
    hints: mapAgentV2StarterHints(starterHints.items, lang),
  }, [lang, starterHints]);
}

/** Picks the starter hints for the active account, by its balance once the balance is known */
export function loadAgentV2StarterHints() {
  const walletState = selectAgentV2HintWalletState(getGlobal());
  return walletState
    ? callApi('getAgentV2StarterHints', walletState)
    : callApi('getAgentV2StarterHints');
}

function selectAgentV2HintWalletState(global: GlobalState): AgentV2HintWalletState | undefined {
  const accountId = selectCurrentAccountId(global);
  const tokens = selectCurrentAccountTokens(global);
  if (!accountId || !tokens) return undefined;

  const { primaryValue } = calculateFullBalance(
    tokens, selectAccountStakingStates(global, accountId), global.currencyRates[global.settings.baseCurrency],
  );
  return primaryValue === '0' ? 'empty' : 'funded';
}

export function requestAgentV2Support(
  items: readonly AgentThreadListItemV2[],
  openChat: (target: AgentV2ChatTarget, options?: Pick<ChatSelection, 'shouldRequestSupport'>) => void,
) {
  if (!getCanRequestAgentV2SupportFromList(items)) return false;
  const thread = findAgentV2SupportThread(items);
  if (thread) {
    openChat({ kind: 'thread', threadId: thread.id });
    return true;
  }
  openChat({ kind: 'new' }, { shouldRequestSupport: true });
  return true;
}

export function getCanRequestAgentV2SupportFromList(items?: readonly AgentThreadListItemV2[]) {
  return items !== undefined && getIsAgentV2SupportEntryVisible();
}

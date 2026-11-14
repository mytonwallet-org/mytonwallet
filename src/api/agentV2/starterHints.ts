import type { AgentActionKind, AgentHintPoolItemV2 } from './protocol/types';
import type { AgentV2HintWalletState, AgentV2StarterHint } from './types';

/**
 * Picks one random hint per group, in the order the groups first appear in `items`. A hint is eligible when the
 * active account supports all its `requiredActions` and its `walletState`, if any, is the one the host reports.
 */
export function selectAgentV2StarterHints(
  items: readonly AgentHintPoolItemV2[],
  walletSupportedActions: readonly AgentActionKind[],
  walletState?: AgentV2HintWalletState,
  getRandom: () => number = Math.random,
): AgentV2StarterHint[] {
  const eligibleByGroup = new Map<AgentHintPoolItemV2['group'], AgentHintPoolItemV2[]>();
  items.forEach((item) => {
    const eligible = eligibleByGroup.get(item.group) ?? [];
    eligibleByGroup.set(item.group, eligible);
    if (isEligible(item, walletSupportedActions, walletState)) eligible.push(item);
  });
  return [...eligibleByGroup.values()].flatMap((eligible) => {
    if (!eligible.length) return [];
    const { id, group } = eligible[Math.floor(getRandom() * eligible.length)];
    return [{ id, group }];
  });
}

function isEligible(
  { requiredActions, walletState: requiredWalletState }: AgentHintPoolItemV2,
  walletSupportedActions: readonly AgentActionKind[],
  walletState?: AgentV2HintWalletState,
) {
  return (!requiredActions || requiredActions.every((action) => walletSupportedActions.includes(action)))
    && (!requiredWalletState || requiredWalletState === walletState);
}

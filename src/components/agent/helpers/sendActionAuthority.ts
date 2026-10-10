import type { AgentV2HostContextSnapshot } from '../../../api/agentV2/types';

export function buildAgentV2SendAuthorityKey(host?: AgentV2HostContextSnapshot) {
  const activeAccount = host?.accounts.find(({ accountId }) => accountId === host.activeAccountId);
  const activeNetwork = host?.activeNetwork;
  const activeAddress = activeNetwork ? activeAccount?.addresses[activeNetwork] : undefined;
  if (
    !activeAccount
    || !activeNetwork
    || !activeAddress
    || activeAccount.state !== 'active'
  ) {
    return undefined;
  }

  return JSON.stringify({
    accountId: activeAccount.accountId,
    accountType: activeAccount.accountType,
    isViewOnly: activeAccount.isViewOnly,
    network: activeNetwork,
    address: activeAddress,
    chains: [...activeAccount.chains].sort(),
  });
}

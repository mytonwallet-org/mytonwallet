import type { AgentV2HostContextSnapshot } from './types';

export function getAgentV2ActionAvailability(host?: AgentV2HostContextSnapshot) {
  const activeAccount = host?.accounts.find(({ accountId }) => accountId === host.activeAccountId);
  const uiActions = host?.uiCapabilities?.supportedActions ?? [];
  const supportedNavigationActions = uiActions.includes('openDapp') ? ['openDapp' as const] : [];
  const isNavigationSupported = supportedNavigationActions.length > 0;
  const isActiveAccountAvailable = activeAccount?.state === 'active';
  const canOpenReceive = uiActions.includes('receive') && isActiveAccountAvailable;
  const canOpenSend = uiActions.includes('send') && isActiveAccountAvailable;
  const canOpenStaking = uiActions.includes('stake')
    && isActiveAccountAvailable
    && activeAccount.isViewOnly === false
    && host?.isTestnet === false
    && !host?.isStakingDisabled
    && activeAccount.chains.includes('ton');
  const canPrepareSwap = uiActions.includes('swap')
    && isActiveAccountAvailable
    && activeAccount.isViewOnly === false
    && activeAccount.accountType !== 'ledger'
    && host?.isTestnet === false;
  const walletSupportedActions = [
    ...(canOpenSend ? ['send' as const] : []),
    ...(canOpenReceive ? ['receive' as const] : []),
    ...(canOpenStaking ? ['stake' as const] : []),
    ...(canPrepareSwap ? ['swap' as const] : []),
  ];
  const supportedActions = [...walletSupportedActions, ...supportedNavigationActions];
  return {
    canOpenSend, canOpenReceive, canOpenStaking, canPrepareSwap,
    isNavigationSupported, walletSupportedActions, supportedActions,
  };
}

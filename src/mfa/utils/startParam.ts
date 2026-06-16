export type MfaWalletApp = 'gram' | 'mytonwallet';

type MfaStartParam = {
  id?: string;
  requestId?: string;
  isInstall: boolean;
  walletApp: MfaWalletApp;
};

export function parseMfaStartParam(startParam?: string): MfaStartParam {
  const { id, walletApp } = parseWalletPrefix(startParam);
  const isInstall = id?.startsWith('i-') ?? false;

  return {
    id,
    requestId: isInstall ? id?.slice(2) : id,
    isInstall,
    walletApp,
  };
}

export function getMfaWalletAppInfo(walletApp: MfaWalletApp) {
  return walletApp === 'gram'
    ? { name: 'Gram Wallet', deeplink: 'https://go.gramwallet.io' }
    : { name: 'My Wallet', deeplink: 'https://go.mytonwallet.org' };
}

function parseWalletPrefix(startParam?: string): Pick<MfaStartParam, 'id' | 'walletApp'> {
  if (startParam?.startsWith('g_')) {
    return { id: startParam.slice(2), walletApp: 'gram' };
  }

  if (startParam?.startsWith('m_')) {
    return { id: startParam.slice(2), walletApp: 'mytonwallet' };
  }

  return { walletApp: 'mytonwallet' };
}

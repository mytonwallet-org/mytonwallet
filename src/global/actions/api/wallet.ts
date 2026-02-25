import type { ApiAnyDisplayError, ApiChain, ApiSwapAsset, ApiToken, ApiTokenWithPrice } from '../../../api/types';
import { ApiHardwareError } from '../../../api/types';

import { getDoesUsePinPad } from '../../../util/biometrics';
import { getChainTitle } from '../../../util/chain';
import { unique } from '../../../util/iteratees';
import { getTranslation } from '../../../util/langProvider';
import { logDebugError } from '../../../util/logs';
import { pause } from '../../../util/schedulers';
import { buildUserToken } from '../../../util/tokens';
import { callApi } from '../../../api';
import { errorCodeToMessage } from '../../helpers/errors';
import { isErrorTransferResult } from '../../helpers/transfer';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import {
  changeBalance,
  updateCurrentAccountSettings,
  updateCurrentAccountState,
  updateCurrentSignature,
  updateSettings,
} from '../../reducers';
import { updateTokenInfo } from '../../reducers/tokens';
import {
  selectAccount,
  selectAccountState,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
} from '../../selectors';

const IMPORT_TOKEN_PAUSE = 250;

addActionHandler('setIsBackupRequired', (global, actions, { isMnemonicChecked }) => {
  const { isBackupRequired } = selectCurrentAccountState(global) ?? {};

  setGlobal(updateCurrentAccountState(global, {
    isBackupRequired: isMnemonicChecked ? undefined : isBackupRequired,
  }));
});

addActionHandler('submitSignature', async (global, actions, payload) => {
  const { password } = payload;
  const { promiseId } = global.currentSignature!;

  if (!(await callApi('verifyPassword', password))) {
    const error = getDoesUsePinPad() ? 'Wrong passcode, please try again.' : 'Wrong password, please try again.';
    setGlobal(updateCurrentSignature(getGlobal(), { error }));

    return;
  }

  await callApi('confirmDappRequest', promiseId, password);

  setGlobal(updateCurrentSignature(getGlobal(), { isSigned: true }));
});

addActionHandler('clearSignatureError', (global) => {
  setGlobal(updateCurrentSignature(global, { error: undefined }));
});

addActionHandler('cancelSignature', (global) => {
  const { promiseId } = global.currentSignature || {};

  if (promiseId) {
    void callApi('cancelDappRequest', promiseId, 'Canceled by the user');
  }

  setGlobal({
    ...global,
    currentSignature: undefined,
  });
});

addActionHandler('addToken', (global, actions, { token }) => {
  if (!global.tokenInfo?.bySlug?.[token.slug]) {
    global = updateTokenInfo(global, {
      [token.slug]: {
        name: token.name,
        symbol: token.symbol,
        slug: token.slug,
        decimals: token.decimals,
        chain: token.chain,
        image: token.image,
        keywords: token.keywords,
        priceUsd: token.priceUsd ?? 0,
        percentChange24h: token.change24h ?? 0,
      },
    });
  }

  const { balances } = selectCurrentAccountState(global) ?? {};

  if (!balances?.bySlug[token.slug]) {
    global = updateCurrentAccountState(global, {
      balances: {
        ...balances,
        bySlug: {
          ...balances?.bySlug,
          [token.slug]: 0n,
        },
      },
    });
  }

  const settings = selectCurrentAccountSettings(global);
  global = updateCurrentAccountSettings(global, {
    importedSlugs: [...settings?.importedSlugs ?? [], token.slug],
  });

  const accountSettings = selectCurrentAccountSettings(global) ?? {};
  global = updateCurrentAccountSettings(global, {
    ...accountSettings,
    alwaysShownSlugs: unique([...accountSettings.alwaysShownSlugs ?? [], token.slug]),
    alwaysHiddenSlugs: accountSettings.alwaysHiddenSlugs?.filter((slug) => slug !== token.slug),
    deletedSlugs: accountSettings.deletedSlugs?.filter((slug) => slug !== token.slug),
  });

  if (token.tokenAddress) {
    void callApi('importToken', selectCurrentAccountId(global)!, token.chain, token.tokenAddress);
  }

  return global;
});

addActionHandler('importToken', async (global, actions, { chain, address }) => {
  const accountId = selectCurrentAccountId(global)!;

  global = updateSettings(global, {
    importToken: {
      isLoading: true,
      token: undefined,
      error: undefined,
    },
  });
  setGlobal(global);

  const slug = (await callApi('buildTokenSlug', chain, address))!;
  global = getGlobal();

  let token: ApiTokenWithPrice | ApiToken | { error: ApiAnyDisplayError } | undefined = global.tokenInfo.bySlug?.[slug];

  if (!token) {
    token = await callApi('fetchToken', accountId, chain, address);
    await pause(IMPORT_TOKEN_PAUSE);
    global = getGlobal();

    if (isErrorTransferResult(token)) {
      global = updateSettings(global, {
        importToken: {
          isLoading: false,
          token: undefined,
          error: errorCodeToMessage(token?.error),
        },
      });
      setGlobal(global);
      return;
    } else {
      const apiToken: ApiTokenWithPrice = {
        ...token,
        priceUsd: 0,
        percentChange24h: 0,
      };
      global = updateTokenInfo(global, { [apiToken.slug]: apiToken });
      setGlobal(global);
    }
  }

  const balances = selectAccountState(global, accountId)?.balances?.bySlug ?? {};
  const shouldUpdateBalance = !(token.slug in balances);

  const userToken = buildUserToken(token);

  global = getGlobal();
  global = updateSettings(global, {
    importToken: {
      isLoading: false,
      token: userToken,
      error: undefined,
    },
  });
  if (shouldUpdateBalance) {
    global = changeBalance(global, accountId, token.slug, 0n);
  }
  setGlobal(global);
});

addActionHandler('resetImportToken', (global) => {
  global = updateSettings(global, {
    importToken: {
      isLoading: false,
      token: undefined,
      error: undefined,
    },
  });
  setGlobal(global);
});

addActionHandler('verifyHardwareAddress', async (global, actions, { chain }) => {
  const accountId = selectCurrentAccountId(global)!;
  const currentAddress = selectAccount(global, accountId)?.byChain[chain]?.address;

  if (!(await connectLedger(chain))) {
    actions.showError({
      error: getTranslation('$ledger_not_ready', { chain: getChainTitle(chain) }),
    });
    return;
  }

  actions.showDialog({ title: 'Ledger', message: '$ledger_verify_address_on_device' });
  const ledgerAddress = await callApi('verifyLedgerWalletAddress', accountId, chain);

  if (isErrorTransferResult(ledgerAddress)) {
    if (ledgerAddress?.error !== ApiHardwareError.RejectedByUser) {
      actions.showError({ error: ledgerAddress?.error });
    }
    return;
  }

  if (ledgerAddress !== currentAddress) {
    actions.showError({ error: '$ledger_wrong_device' });
  }
});

// A cute mini version of the `initializeHardwareWalletConnection` action
async function connectLedger(chain: ApiChain, noRetry?: boolean) {
  const ledgerApi = await import('../../../util/ledger');

  // Step 1: Connect to the Ledger device

  const isLedgerConnected = await ledgerApi.connectLedger();
  if (!isLedgerConnected) {
    return false;
  }

  // Step 2: Ensure that the chain app is open on the Ledger device

  const isChainAppConnected = await callApi('waitForLedgerApp', chain);
  if (isErrorTransferResult(isChainAppConnected)) {
    const isLedgerDisconnected = isChainAppConnected?.error === ApiHardwareError.ConnectionBroken;
    if (isLedgerDisconnected && !noRetry) {
      return connectLedger(chain, true);
    }

    logDebugError('wallet / connectLedger', isChainAppConnected?.error);
    return false;
  }

  return isChainAppConnected;
}

addActionHandler('setActiveContentTab', (global, actions, { tab }) => {
  return updateCurrentAccountState(global, {
    activeContentTab: tab,
  });
});

addActionHandler('addSwapToken', (global, actions, { token }) => {
  const isAlreadyExist = token.slug in global.swapTokenInfo.bySlug;

  if (isAlreadyExist) {
    return;
  }

  const apiSwapAsset: ApiSwapAsset = {
    name: token.name,
    symbol: token.symbol,
    chain: token.chain,
    slug: token.slug,
    decimals: token.decimals,
    image: token.image,
    tokenAddress: token.tokenAddress,
    keywords: token.keywords,
    isPopular: false,
    priceUsd: token.priceUsd,
  };

  setGlobal({
    ...global,
    swapTokenInfo: {
      ...global.swapTokenInfo,
      bySlug: {
        ...global.swapTokenInfo.bySlug,
        [apiSwapAsset.slug]: apiSwapAsset,
      },
    },
  });
});

addActionHandler('apiUpdateWalletVersions', (global, actions, params) => {
  const { accountId, versions, currentVersion } = params;
  global = {
    ...global,
    walletVersions: {
      ...global.walletVersions,
      currentVersion,
      byId: {
        ...global.walletVersions?.byId,
        [accountId]: versions,
      },
    },
  };
  setGlobal(global);
});

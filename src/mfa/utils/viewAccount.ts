import { getGlobal } from '../../global';

import { AppState } from '../../global/types';

import {
  createAndSetTemporaryAccount,
  importTemporaryViewAccount,
  removeTemporaryAccount,
} from '../../global/helpers/auth';
import { ensureMfaGlobalReady, ensureMfaTokenInfoReady } from '../runtime';

let currentAddress: string | undefined;
let currentPromise: Promise<void> | undefined;

export async function ensureMfaViewAccount(address: string) {
  if (!address) {
    throw new Error('Wallet address is required');
  }

  if (currentAddress === address && currentPromise) {
    return currentPromise;
  }

  // eslint-disable-next-line no-console
  console.info('[MFA] ensureMfaViewAccount start', { address });
  currentAddress = address;
  currentPromise = bootstrapViewAccount(address);

  try {
    await currentPromise;
    // eslint-disable-next-line no-console
    console.info('[MFA] ensureMfaViewAccount success', { address });
  } catch (err) {
    if (currentAddress === address) {
      currentAddress = undefined;
      currentPromise = undefined;
    }

    throw err;
  }
}

async function bootstrapViewAccount(address: string) {
  await ensureMfaGlobalReady();
  await ensureMfaTokenInfoReady();

  const global = getGlobal();
  const currentTemporaryAccountId = global.currentTemporaryViewAccountId;
  const currentTemporaryAddress = currentTemporaryAccountId
    ? global.accounts?.byId[currentTemporaryAccountId]?.byChain.ton?.address
    : undefined;

  if (currentTemporaryAddress === address) {
    // eslint-disable-next-line no-console
    console.info('[MFA] ensureMfaViewAccount reuse', { address, currentTemporaryAccountId });
    return;
  }

  if (currentTemporaryAccountId) {
    // eslint-disable-next-line no-console
    console.info('[MFA] ensureMfaViewAccount removePrevious', { currentTemporaryAccountId });
    await removeTemporaryAccount(currentTemporaryAccountId);
  }

  const result = await importTemporaryViewAccount('mainnet', { ton: address });
  if (!result || 'error' in result) {
    throw new Error(result?.error || 'Failed to bootstrap view account');
  }

  createAndSetTemporaryAccount(result, {
    currentAccountId: result.accountId,
    appState: AppState.Main,
  });
}

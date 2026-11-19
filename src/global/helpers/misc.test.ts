import type { ApiActivity, ApiChain } from '../../api/types';
import type { AccountState, GlobalState } from '../types';

import { BASE_USDC_MAINNET, BITCOIN, BITCOINCASH, SOLANA } from '../../config';
import { getChainConfig } from '../../util/chain';
import { INITIAL_STATE } from '../initialState';
import { parsePlainAddressQr, resolveReplacedActivityId } from './misc';

const ACCOUNT_ID = 'test-account';
const EVM_ADDRESS = '0x742d35Cc6634C0532925a3b844Bc454e4438f44e';
const BITCOIN_LEGACY_ADDRESS = '1BoatSLRHtKNngkdXEeobR76b53LETtpyT';

function buildQrGlobal(tokenSlug: string, chains: ApiChain[]): GlobalState {
  const byChain = Object.fromEntries(chains.map((chain) => [chain, {
    address: getChainConfig(chain).feeCheckAddress,
  }]));

  return {
    ...INITIAL_STATE,
    currentAccountId: ACCOUNT_ID,
    currentTransfer: { ...INITIAL_STATE.currentTransfer, tokenSlug },
    accounts: {
      byId: { [ACCOUNT_ID]: { title: 'Test', type: 'mnemonic', byChain } },
    } as GlobalState['accounts'],
  };
}

describe('parsePlainAddressQr', () => {
  it('keeps the selected Base token when scanning an address shared with Ethereum', () => {
    const global = buildQrGlobal(BASE_USDC_MAINNET.slug, ['ethereum', 'base']);

    expect(parsePlainAddressQr(global, EVM_ADDRESS)).toEqual({
      toAddress: EVM_ADDRESS,
      tokenSlug: BASE_USDC_MAINNET.slug,
    });
  });

  it('keeps BCH when scanning a legacy address shared with Bitcoin', () => {
    const global = buildQrGlobal(BITCOINCASH.slug, ['bitcoin', 'bitcoincash']);

    expect(parsePlainAddressQr(global, BITCOIN_LEGACY_ADDRESS)).toEqual({
      toAddress: BITCOIN_LEGACY_ADDRESS,
      tokenSlug: BITCOINCASH.slug,
    });
  });

  it('selects BTC when a scanned legacy Bitcoin address also matches Solana', () => {
    const global = buildQrGlobal(SOLANA.slug, ['bitcoin', 'solana']);

    expect(parsePlainAddressQr(global, BITCOIN_LEGACY_ADDRESS)).toEqual({
      toAddress: BITCOIN_LEGACY_ADDRESS,
      tokenSlug: BITCOIN.slug,
    });
  });

  it('rejects an address whose chain is unavailable', () => {
    const global = buildQrGlobal(SOLANA.slug, ['solana']);

    expect(parsePlainAddressQr(global, EVM_ADDRESS)).toBeUndefined();
  });

  it('rejects an invalid address', () => {
    const global = buildQrGlobal(BITCOINCASH.slug, ['bitcoin', 'bitcoincash']);

    expect(parsePlainAddressQr(global, 'invalid-address')).toBeUndefined();
  });
});

function makeActivities(
  ids: string[],
  activityIdReplacements?: Record<string, string>,
): AccountState['activities'] {
  return {
    byId: Object.fromEntries(ids.map((id) => [id, { id } as ApiActivity])),
    activityIdReplacements,
  };
}

describe('resolveReplacedActivityId', () => {
  it('keeps an id that is present in `byId`', () => {
    const activities = makeActivities(['local', 'chain'], { local: 'chain' });

    expect(resolveReplacedActivityId(activities, 'local')).toBe('local');
  });

  it('follows a chain of replacements to the id that is present in `byId`', () => {
    const activities = makeActivities(['aggregate'], { local: 'backend', backend: 'aggregate' });

    expect(resolveReplacedActivityId(activities, 'local')).toBe('aggregate');
  });

  it('returns the last id of a chain that leads nowhere', () => {
    const activities = makeActivities([], { local: 'backend' });

    expect(resolveReplacedActivityId(activities, 'local')).toBe('backend');
  });

  it('stops on a replacement cycle', () => {
    const activities = makeActivities([], { first: 'second', second: 'first' });

    expect(resolveReplacedActivityId(activities, 'first')).toBe('first');
  });

  it('returns the id when there are no activities', () => {
    expect(resolveReplacedActivityId(undefined, 'local')).toBe('local');
  });
});

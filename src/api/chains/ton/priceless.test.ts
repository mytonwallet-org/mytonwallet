import type { ApiTokenWithPrice, ApiUpdate } from '../../types';
import type { AccountState } from './toncenter/types';

import { PRICELESS_TOKEN_HASHES } from '../../../config';
import {
  getTokensCache,
  pauseTokenUpdates,
  resumeTokenUpdates,
  sendUpdateTokens,
  tokensPreload,
  updateTokens,
  updateTokensFromBackend,
} from '../../common/tokens';
import { updateTokenHashes } from './priceless';
import { getAccountStates } from './toncenter';

jest.mock('../../db', () => ({
  tokenRepository: { bulkPut: jest.fn().mockResolvedValue(undefined) },
}));

jest.mock('../../common/backend', () => ({
  callBackendGet: jest.fn().mockResolvedValue([]),
  callBackendPost: jest.fn().mockResolvedValue([]),
}));

jest.mock('./toncenter', () => ({ getAccountStates: jest.fn() }));

const TOKEN: ApiTokenWithPrice = {
  slug: 'ton-lp-delivery',
  tokenAddress: 'EQLpDelivery',
  chain: 'ton',
  name: 'Liquidity pool',
  symbol: 'LP',
  decimals: 9,
  priceUsd: 0,
  percentChange24h: 0,
};
const [CODE_HASH] = PRICELESS_TOKEN_HASHES;

describe('updateTokenHashes', () => {
  afterEach(() => {
    delete getTokensCache().bySlug[TOKEN.slug];
    pauseTokenUpdates();
    jest.clearAllMocks();
  });

  it.each([undefined, 2])('delivers hashes without changing quote availability (price %s)', async (priceUsd) => {
    const received: Record<string, ApiTokenWithPrice> = {};
    const onUpdate = jest.fn((update: ApiUpdate) => {
      if (update.type !== 'updateTokens') return;
      Object.assign(received, JSON.parse(JSON.stringify(update.tokens)));
    });
    const state: AccountState = {
      address: TOKEN.tokenAddress!,
      account_state_hash: '',
      balance: '0',
      code_boc: '',
      code_hash: Buffer.from(CODE_HASH, 'hex').toString('base64'),
      data_boc: '',
      data_hash: '',
      frozen_hash: '',
      last_transaction_hash: '',
      last_transaction_lt: 0,
      status: 'active',
    };
    jest.mocked(getAccountStates).mockResolvedValue({ [state.address]: state });
    tokensPreload.resolve();
    resumeTokenUpdates();
    await updateTokens([{ ...TOKEN, priceUsd }]);
    await updateTokensFromBackend(onUpdate);
    const sentToken = getTokensCache().bySlug[TOKEN.slug];
    expect(received[TOKEN.slug].codeHash).toBeUndefined();
    onUpdate.mockClear();

    await updateTokenHashes('mainnet', [TOKEN.slug], () => sendUpdateTokens(onUpdate));

    expect(onUpdate).toHaveBeenCalledWith({
      type: 'updateTokens',
      kind: 'partial',
      tokens: { [TOKEN.slug]: { ...TOKEN, priceUsd: priceUsd ?? 0, codeHash: CODE_HASH } },
      ...(priceUsd === undefined && { unpricedSlugs: [TOKEN.slug] }),
    });
    expect(received[TOKEN.slug].codeHash).toBe(CODE_HASH);
    expect(sentToken.codeHash).toBeUndefined();

    onUpdate.mockClear();
    await updateTokensFromBackend(onUpdate);
    await updateTokenHashes('mainnet', [TOKEN.slug], () => sendUpdateTokens(onUpdate));

    expect(onUpdate).not.toHaveBeenCalled();
    expect(getAccountStates).toHaveBeenCalledTimes(1);
  });
});

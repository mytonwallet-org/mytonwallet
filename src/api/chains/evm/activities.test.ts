import type { ApiAccountAny, ApiBackendConfig } from '../../types';
import type { ZerionNftTransfer, ZerionTransaction } from './types';

import { getIsHiddenNftActivity, isScamTransaction } from '../../../util/activities';
import { fetchJson } from '../../../util/fetch';
import { untrackableRegistry } from './util/untrackable';
import { fetchStoredAccount } from '../../common/accounts';
import { setBackendConfigCache } from '../../common/cache';
import { ApiServerError } from '../../errors';
import { fetchActivitySlice, fetchEvmTxs, transformEvmTxToUnified } from './activities';
import { fetchNftByAddress } from './nfts';

// Mock only the network call; keep isNegativeCacheableStatus real so the adapter's classification
// is exercised end to end.
jest.mock('../../../util/fetch', () => ({
  ...jest.requireActual('../../../util/fetch'),
  fetchJson: jest.fn(),
}));

jest.mock('../../common/accounts', () => ({
  fetchStoredAccount: jest.fn(),
}));

const fetchJsonMock = jest.mocked(fetchJson);
const fetchStoredAccountMock = jest.mocked(fetchStoredAccount);

function setNegVerdictCacheFlag(enabled: boolean) {
  setBackendConfigCache({ isNegVerdictCacheEnabled: enabled } as unknown as ApiBackendConfig);
}

const BASE = { chain: 'ethereum', network: 'mainnet', limit: 50 } as const;

describe('NFT spam metadata and activity identity', () => {
  const OWNER = '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045';
  const CONTRACT = '0x000000000000888741B254d37e1b27128AfEAaBC';
  const TOKEN_ID = '5261405894391250505533265397778618870761357154713600';

  function makeTransaction(flags?: ZerionNftTransfer['nft_info']['flags'], isTrash = false): ZerionTransaction {
    return {
      type: 'transactions',
      id: 'nft-tx',
      attributes: {
        address: OWNER,
        operation_type: 'receive',
        hash: '0xnft',
        mined_at_block: 1,
        mined_at: '2026-10-26T00:00:00Z',
        sent_from: CONTRACT,
        sent_to: OWNER,
        status: 'confirmed',
        nonce: 1,
        fee: { quantity: { int: '0', decimals: 18, float: 0, numeric: '0' }, price: 0, value: 0 },
        transfers: [{
          direction: 'in',
          sender: CONTRACT,
          recipient: OWNER,
          act_id: '0',
          quantity: { int: '1', decimals: 0, float: 1, numeric: '1' },
          price: 0,
          value: 0,
          nft_info: {
            contract_address: CONTRACT.toLowerCase(), token_id: TOKEN_ID, name: 'SLOW', interface: 'ERC721', flags,
          },
        }],
        approvals: [],
        flags: { is_trash: isTrash },
        acts: [],
      },
      relationships: { chain: { links: { related: '' }, data: { type: 'chains', id: 'base' } } },
    };
  }

  it.each([CONTRACT, CONTRACT.toLowerCase()])('matches gallery hide/show for Alchemy casing %s', async (contract) => {
    fetchJsonMock.mockResolvedValueOnce({
      contract: { address: contract, tokenType: 'ERC721' }, tokenId: TOKEN_ID, image: {}, raw: {},
    });
    const galleryNft = await fetchNftByAddress('base', 'mainnet', CONTRACT, TOKEN_ID, OWNER);
    const activity = transformEvmTxToUnified('base', makeTransaction({ is_spam: true }), OWNER);
    if (activity.kind !== 'transaction') throw new Error('Expected NFT transaction');

    expect(activity.nft).toMatchObject({
      address: galleryNft.address,
      interface: 'ERC721',
      isHidden: true,
      spamInfo: { provider: 'zerion', isSpam: true },
    });
    expect(isScamTransaction(activity)).toBeFalsy();
    expect(getIsHiddenNftActivity(activity)).toBe(true);
    expect(getIsHiddenNftActivity(activity, [], [galleryNft.address])).toBe(false);
    expect(getIsHiddenNftActivity(activity, [galleryNft.address], [galleryNft.address])).toBe(true);
  });

  it('preserves the ERC1155 transfer interface even before the NFT gallery loads', () => {
    const tx = makeTransaction();
    (tx.attributes.transfers[0] as ZerionNftTransfer).nft_info.interface = 'ERC1155';
    const activity = transformEvmTxToUnified('base', tx, OWNER);
    if (activity.kind !== 'transaction') throw new Error('Expected NFT transaction');

    expect(activity.nft?.interface).toBe('ERC1155');
  });

  // eslint-disable-next-line no-null/no-null
  it.each([false, null, undefined])('does not hide an NFT for the %s provider verdict', (isSpam) => {
    const activity = transformEvmTxToUnified('base', makeTransaction({ is_spam: isSpam }), OWNER);
    if (activity.kind !== 'transaction') throw new Error('Expected NFT transaction');

    expect(activity.nft?.spamInfo).toEqual({ provider: 'zerion', isSpam: isSpam ?? undefined });
    expect(getIsHiddenNftActivity(activity)).toBe(false);
  });

  it('still honors transaction-level trash when NFT flags are missing', () => {
    const activity = transformEvmTxToUnified('base', makeTransaction(undefined, true), OWNER);
    if (activity.kind !== 'transaction') throw new Error('Expected NFT transaction');

    expect(activity.nft?.spamInfo?.isSpam).toBeUndefined();
    expect(isScamTransaction(activity)).toBe(true);
  });
});

describe('fetchEvmTxs untrackable handling', () => {
  beforeEach(() => {
    untrackableRegistry.reset();
    fetchJsonMock.mockReset();
    setNegVerdictCacheFlag(false);
  });

  it('flag off: a deterministic 400 rethrows unchanged and marks nothing (dark-ship guard)', async () => {
    fetchJsonMock.mockRejectedValue(new ApiServerError('untrackable wallet address', 400));

    await expect(fetchEvmTxs({ ...BASE, address: '0xdead' })).rejects.toBeInstanceOf(ApiServerError);
    expect(untrackableRegistry.has('mainnet', '0xdead')).toBe(false);
  });

  it('flag on: a plain-history 400 marks the address, returns empty, and short-circuits the next call', async () => {
    setNegVerdictCacheFlag(true);
    fetchJsonMock.mockRejectedValue(new ApiServerError('untrackable wallet address', 400));

    await expect(fetchEvmTxs({ ...BASE, address: '0xdead' })).resolves.toEqual([]);
    expect(untrackableRegistry.has('mainnet', '0xdead')).toBe(true);

    fetchJsonMock.mockClear();
    await expect(fetchEvmTxs({ ...BASE, address: '0xdead' })).resolves.toEqual([]);
    expect(fetchJsonMock).not.toHaveBeenCalled();
  });

  it('flag on: a hash-scoped 400 does NOT mark the address (a user fetches their own tx by hash)', async () => {
    setNegVerdictCacheFlag(true);
    fetchJsonMock.mockRejectedValue(new ApiServerError('bad search_query', 400));

    await expect(fetchEvmTxs({ ...BASE, address: '0xuser', hash: '0xabc' })).rejects.toBeInstanceOf(ApiServerError);
    expect(untrackableRegistry.has('mainnet', '0xuser')).toBe(false);
  });

  it('flag on: a token-scoped 422 does NOT mark the address (the token filter may be at fault)', async () => {
    setNegVerdictCacheFlag(true);
    fetchJsonMock.mockRejectedValue(new ApiServerError('bad fungible filter', 422));

    await expect(fetchEvmTxs({ ...BASE, address: '0xuser', slug: 'ethereum-0xtoken' }))
      .rejects.toBeInstanceOf(ApiServerError);
    expect(untrackableRegistry.has('mainnet', '0xuser')).toBe(false);
  });
});

// Robinhood rides the Ethereum wallet, so an account created before the chain existed has no
// Robinhood entry of its own. The per-token activity path still asks for that chain by name.
describe('fetchActivitySlice on a chain sharing another chain\'s wallet', () => {
  const ADDRESS = '0x5819e5Ff34198F315322e1863Be6C3dC927cC5C3';

  beforeEach(() => {
    untrackableRegistry.reset();
    fetchJsonMock.mockReset();
    fetchJsonMock.mockResolvedValue({ data: [] });
    setNegVerdictCacheFlag(false);
    fetchStoredAccountMock.mockResolvedValue({
      type: 'bip39',
      byChain: { ethereum: { address: ADDRESS, index: 0 } },
    } as ApiAccountAny);
  });

  it('asks Zerion for that chain using the address of the wallet it shares', async () => {
    await expect(fetchActivitySlice('robinhood', { accountId: '0-mainnet', limit: 50 })).resolves.toEqual([]);

    const [url, params] = fetchJsonMock.mock.calls[0];
    expect(url).toContain(`/wallets/${ADDRESS}/transactions/`);
    expect(params).toMatchObject({ 'filter[chain_ids]': 'robinhood' });
  });
});

describe('transformEvmTxToUnified on allowance transactions', () => {
  const OWNER = '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045';
  const SPENDER = '0x2891F8b941067F8B5a3F34545A30Cf71E3E23617';
  const TOKEN = '0xA27EC0006e59f245217Ff08CD52A7E8b169E62D2';
  const MAX_UINT256 = (1n << 256n) - 1n;

  function buildApprovalTx(
    approvalAmount: bigint,
    operationType: ZerionTransaction['attributes']['operation_type'],
    actMetadata?: ZerionTransaction['attributes']['application_metadata'],
  ): ZerionTransaction {
    return {
      type: 'transactions',
      id: '0xhash',
      attributes: {
        address: OWNER,
        operation_type: operationType,
        hash: '0xhash',
        mined_at_block: 1,
        mined_at: '2026-09-01T00:00:00Z',
        sent_from: OWNER.toLowerCase(),
        sent_to: TOKEN.toLowerCase(),
        status: 'confirmed',
        nonce: 1,
        fee: { quantity: { int: '21000', decimals: 18, float: 0, numeric: '0' }, price: 0, value: 0 },
        transfers: [],
        approvals: [{
          act_id: '0',
          sender: SPENDER.toLowerCase(),
          quantity: {
            int: approvalAmount.toString(),
            decimals: 18,
            float: 0,
            numeric: '0',
          },
          fungible_info: {
            id: 'token-id',
            name: 'Token',
            symbol: 'TKN',
            icon: { url: 'https://token.example/icon.png' },
            flags: { verified: true },
            implementations: [{ chain_id: 'ethereum', address: TOKEN.toLowerCase(), decimals: 18 }],
          },
        }],
        flags: { is_trash: false },
        acts: [{ id: '0', type: 'approve', application_metadata: actMetadata }],
      },
      relationships: { chain: { links: { related: '' }, data: { type: 'chains', id: 'ethereum' } } },
    };
  }

  it('parses an unlimited grant as an unlimited approval towards the spender', () => {
    const activity = transformEvmTxToUnified(
      'ethereum',
      buildApprovalTx(MAX_UINT256, 'approve', { contract_address: SPENDER.toLowerCase() }),
      OWNER,
    );

    expect(activity).toMatchObject({
      kind: 'transaction',
      type: 'approval',
      isApprovalUnlimited: true,
      amount: MAX_UINT256,
      isIncoming: false,
      fromAddress: OWNER,
      toAddress: SPENDER,
      slug: 'ethereum-0xa27ec000',
    });
  });

  it('parses a revoke as a zero, limited approval even when the act carries no contract', () => {
    const activity = transformEvmTxToUnified('ethereum', buildApprovalTx(0n, 'revoke'), OWNER);

    expect(activity).toMatchObject({
      type: 'approval',
      isApprovalUnlimited: false,
      amount: 0n,
      toAddress: SPENDER,
    });
  });

  it('still falls back to a contract call when the transaction sets no allowance', () => {
    const tx = buildApprovalTx(0n, 'execute');
    tx.attributes.approvals = [];

    expect(transformEvmTxToUnified('ethereum', tx, OWNER)).toMatchObject({ type: 'callContract' });
  });
});

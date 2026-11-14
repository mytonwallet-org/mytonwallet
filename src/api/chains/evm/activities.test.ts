import type { ApiAccountAny, ApiBackendConfig } from '../../types';
import type { ZerionNftTransfer, ZerionTransaction } from './types';

import { ARBITRUM_USDC_MAINNET } from '../../../config';
import { getIsHiddenNftActivity, isScamTransaction } from '../../../util/activities';
import { fetchJson } from '../../../util/fetch';
import { untrackableRegistry } from './util/untrackable';
import { fetchStoredAccount } from '../../common/accounts';
import { setBackendConfigCache } from '../../common/cache';
import {
  PERPS_CCTP_EXTENSION_ADDRESS,
  PERPS_CCTP_FORWARD_FEE_USDC_BASE_UNITS,
  PERPS_HYPERCORE_BRIDGE_RELAYER,
} from '../../common/perps';
import * as tokenApi from '../../common/tokens';
import { ApiServerError } from '../../errors';
import { PIMLICO_SINGLETON_PAYMASTER_ADDRESS } from './smartAccount/constants';
import { fetchActivityDetails, fetchActivitySlice, fetchEvmTxs, transformEvmTxToUnified } from './activities';
import { normalizeAddress } from './address';
import { fetchNftByAddress } from './nfts';

jest.mock('../../../config', () => ({
  ...jest.requireActual('../../../config'),
  IS_PERPS_ENABLED: true,
}));

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

describe('transformEvmTxToUnified on token mints', () => {
  const OWNER = '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045';
  const MINTER = '0x0000000000000000000000000000000000000000';
  const TOKEN = '0xA27EC0006e59f245217Ff08CD52A7E8b169E62D2';
  const MINTED_AMOUNT = 1_000_000n;

  function buildMintTx(
    operationType: ZerionTransaction['attributes']['operation_type'],
    actType: ZerionTransaction['attributes']['acts'][number]['type'],
  ): ZerionTransaction {
    return {
      type: 'transactions',
      id: '0xmint',
      attributes: {
        address: OWNER,
        operation_type: operationType,
        hash: '0xmint',
        mined_at_block: 1,
        mined_at: '2026-09-01T00:00:00Z',
        sent_from: OWNER.toLowerCase(),
        sent_to: TOKEN.toLowerCase(),
        status: 'confirmed',
        nonce: 1,
        fee: { quantity: { int: '21000', decimals: 18, float: 0, numeric: '0' }, price: 0, value: 0 },
        transfers: [{
          act_id: '0',
          direction: 'in',
          sender: MINTER,
          recipient: OWNER.toLowerCase(),
          quantity: { int: MINTED_AMOUNT.toString(), decimals: 6, float: 1, numeric: '1' },
          // eslint-disable-next-line no-null/no-null
          price: null,
          // eslint-disable-next-line no-null/no-null
          value: null,
          fungible_info: {
            id: 'token-id',
            name: 'Token',
            symbol: 'TKN',
            icon: { url: 'https://token.example/icon.png' },
            flags: { verified: true },
            implementations: [{ chain_id: 'ethereum', address: TOKEN.toLowerCase(), decimals: 6 }],
          },
        }],
        approvals: [],
        flags: { is_trash: false },
        acts: [{ id: '0', type: actType }],
      },
      relationships: { chain: { links: { related: '' }, data: { type: 'chains', id: 'ethereum' } } },
    };
  }

  it('parses a transaction Zerion marks mint as a token mint', () => {
    const activity = transformEvmTxToUnified('ethereum', buildMintTx('mint', 'receive'), OWNER);

    expect(activity).toMatchObject({
      kind: 'transaction',
      type: 'mint',
      amount: MINTED_AMOUNT,
      isIncoming: true,
      fromAddress: OWNER,
      toAddress: OWNER,
      slug: 'ethereum-0xa27ec000',
    });
  });

  it('parses a mint act inside another operation as a token mint', () => {
    const activity = transformEvmTxToUnified('ethereum', buildMintTx('execute', 'mint'), OWNER);

    expect(activity).toMatchObject({
      type: 'mint',
      amount: MINTED_AMOUNT,
      slug: 'ethereum-0xa27ec000',
    });
  });

  it('leaves an ordinary incoming transfer unmarked', () => {
    const activity = transformEvmTxToUnified('ethereum', buildMintTx('receive', 'receive'), OWNER);

    expect(activity).toMatchObject({ kind: 'transaction', isIncoming: true, amount: MINTED_AMOUNT });
    expect(activity).not.toHaveProperty('type', 'mint');
  });

  it('classifies a HyperCore relayer Arbitrum USDC mint as perps withdrawal', () => {
    const tx = buildMintTx('mint', 'mint');
    tx.attributes.sent_from = PERPS_HYPERCORE_BRIDGE_RELAYER.toLowerCase();
    tx.relationships.chain.data.id = 'arbitrum';
    tx.attributes.transfers[0] = {
      ...tx.attributes.transfers[0],
      fungible_info: {
        id: 'arbitrum-usdc',
        name: 'USD Coin',
        symbol: 'USDC',
        // eslint-disable-next-line no-null/no-null
        icon: null,
        flags: { verified: true },
        implementations: [{
          chain_id: 'arbitrum',
          address: ARBITRUM_USDC_MAINNET.tokenAddress.toLowerCase(),
          decimals: 6,
        }],
      },
    };

    const activity = transformEvmTxToUnified('arbitrum', tx, OWNER);

    expect(activity).toMatchObject({
      kind: 'transaction',
      type: 'perps_withdraw',
      slug: ARBITRUM_USDC_MAINNET.slug,
      fromAddress: normalizeAddress(PERPS_HYPERCORE_BRIDGE_RELAYER),
      amount: MINTED_AMOUNT,
      isIncoming: true,
    });
  });
});

describe('transformEvmTxToUnified on perps deposits', () => {
  const OWNER = '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045';
  const BRIDGE = PERPS_CCTP_EXTENSION_ADDRESS.toLowerCase();
  const GROSS_DEPOSIT = 10_000_000n;
  const NET_DEPOSIT = GROSS_DEPOSIT - PERPS_CCTP_FORWARD_FEE_USDC_BASE_UNITS;

  function arbitrumUsdcFungibleInfo() {
    return {
      id: 'arbitrum-usdc',
      name: 'USD Coin',
      symbol: 'USDC',
      // eslint-disable-next-line no-null/no-null
      icon: null,
      flags: { verified: true },
      implementations: [{
        chain_id: 'arbitrum',
        address: ARBITRUM_USDC_MAINNET.tokenAddress.toLowerCase(),
        decimals: 6,
      }],
    };
  }

  function buildPerpsDepositTx(transfers: ZerionTransaction['attributes']['transfers']): ZerionTransaction {
    return {
      type: 'transactions',
      id: '0xdeposit',
      attributes: {
        address: OWNER,
        operation_type: 'execute',
        hash: '0xdeposit',
        mined_at_block: 1,
        mined_at: '2026-09-01T00:00:00Z',
        sent_from: OWNER.toLowerCase(),
        sent_to: BRIDGE,
        status: 'confirmed',
        nonce: 1,
        fee: { quantity: { int: '21000', decimals: 18, float: 0, numeric: '0' }, price: 0, value: 0 },
        transfers,
        approvals: [],
        flags: { is_trash: false },
        acts: [],
      },
      relationships: { chain: { links: { related: '' }, data: { type: 'chains', id: 'arbitrum' } } },
    };
  }

  it('parses a single gross USDC transfer to the CCTP extension as perps deposit', () => {
    const activity = transformEvmTxToUnified('arbitrum', buildPerpsDepositTx([{
      act_id: '0',
      direction: 'out',
      sender: OWNER.toLowerCase(),
      recipient: BRIDGE,
      quantity: { int: GROSS_DEPOSIT.toString(), decimals: 6, float: 10, numeric: '10' },
      // eslint-disable-next-line no-null/no-null
      price: null,
      // eslint-disable-next-line no-null/no-null
      value: null,
      fungible_info: arbitrumUsdcFungibleInfo(),
    }]), OWNER);

    expect(activity).toMatchObject({
      kind: 'transaction',
      type: 'perps_deposit',
      slug: ARBITRUM_USDC_MAINNET.slug,
      amount: -NET_DEPOSIT,
      isIncoming: false,
      toAddress: normalizeAddress(PERPS_CCTP_EXTENSION_ADDRESS),
    });
  });

  it('parses separate bridge fee and deposit USDC transfers as one perps deposit', () => {
    const activity = transformEvmTxToUnified('arbitrum', buildPerpsDepositTx([
      {
        act_id: '0',
        direction: 'out',
        sender: OWNER.toLowerCase(),
        recipient: BRIDGE,
        quantity: { int: PERPS_CCTP_FORWARD_FEE_USDC_BASE_UNITS.toString(), decimals: 6, float: 0.2, numeric: '0.2' },
        // eslint-disable-next-line no-null/no-null
        price: null,
        // eslint-disable-next-line no-null/no-null
        value: null,
        fungible_info: arbitrumUsdcFungibleInfo(),
      },
      {
        act_id: '1',
        direction: 'out',
        sender: OWNER.toLowerCase(),
        recipient: BRIDGE,
        quantity: { int: NET_DEPOSIT.toString(), decimals: 6, float: 9.8, numeric: '9.8' },
        // eslint-disable-next-line no-null/no-null
        price: null,
        // eslint-disable-next-line no-null/no-null
        value: null,
        fungible_info: arbitrumUsdcFungibleInfo(),
      },
    ]), OWNER);

    expect(activity).toMatchObject({
      type: 'perps_deposit',
      amount: -NET_DEPOSIT,
    });
  });

  it('ignores a transfer that only covers the bridge fee', () => {
    const activity = transformEvmTxToUnified('arbitrum', buildPerpsDepositTx([{
      act_id: '0',
      direction: 'out',
      sender: OWNER.toLowerCase(),
      recipient: BRIDGE,
      quantity: { int: PERPS_CCTP_FORWARD_FEE_USDC_BASE_UNITS.toString(), decimals: 6, float: 0.2, numeric: '0.2' },
      // eslint-disable-next-line no-null/no-null
      price: null,
      // eslint-disable-next-line no-null/no-null
      value: null,
      fungible_info: arbitrumUsdcFungibleInfo(),
    }]), OWNER);

    expect(activity).not.toMatchObject({ type: 'perps_deposit' });
  });
});

describe('transformEvmTxToUnified on gasless transfers', () => {
  const OWNER = '0x3e9526b6e3648abe93de78994cf4a3edbebe6032';
  const RECIPIENT = '0x6add56d0631ebca7ae53f3c19f61db9ab9d42cf3';
  const FEE_RECIPIENT = '0x4337ff05c84b9a80ea0a78dbe7b8e102f66d4c08';
  const PAYMASTER = PIMLICO_SINGLETON_PAYMASTER_ADDRESS.toLowerCase();
  const TRANSFER_AMOUNT = 1_000_000n;
  const FEE_AMOUNT = 10_388n;

  function usdcFungibleInfo() {
    return {
      id: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
      name: 'USDC',
      symbol: 'USDC',
      // eslint-disable-next-line no-null/no-null
      icon: null,
      flags: { verified: true },
      implementations: [{
        chain_id: 'arbitrum',
        address: ARBITRUM_USDC_MAINNET.tokenAddress.toLowerCase(),
        decimals: 6,
      }],
    };
  }

  function tokenTransfer(
    actId: string,
    sender: string,
    recipient: string,
    amount: bigint,
  ): ZerionTransaction['attributes']['transfers'][number] {
    return {
      act_id: actId,
      direction: 'out',
      sender,
      recipient,
      quantity: { int: amount.toString(), decimals: 6, float: 0, numeric: '0' },
      // eslint-disable-next-line no-null/no-null
      price: null,
      // eslint-disable-next-line no-null/no-null
      value: null,
      fungible_info: usdcFungibleInfo(),
    };
  }

  function buildGaslessTx(options?: {
    paymaster?: string;
    direction?: 'in' | 'out';
  }): ZerionTransaction {
    const paymaster = options?.paymaster ?? PAYMASTER;
    const direction = options?.direction ?? 'out';

    return {
      type: 'transactions',
      id: 'gasless',
      attributes: {
        address: OWNER,
        operation_type: 'execute',
        hash: '0xgasless',
        mined_at_block: 1,
        mined_at: '2026-11-06T14:35:37Z',
        sent_from: '0x43373008077485193bb7bc36ac3ce0f5f315383c',
        sent_to: '0x0000000071727de22e5e9d8baf0edac6f37da032',
        status: 'confirmed',
        nonce: 1,
        fee: { quantity: { int: '4267552989600', decimals: 18, float: 0, numeric: '0' }, price: 0, value: 0 },
        transfers: [
          tokenTransfer('1', OWNER, RECIPIENT, TRANSFER_AMOUNT),
          tokenTransfer('2', OWNER, FEE_RECIPIENT, FEE_AMOUNT),
        ].map((transfer) => ({ ...transfer, direction })),
        approvals: [],
        flags: { is_trash: false },
        acts: [
          { id: '0', type: 'approve', sent_from: OWNER, counterparty_address: paymaster },
          { id: '1', type: 'send', sent_from: OWNER, counterparty_address: RECIPIENT },
          { id: '2', type: 'send', sent_from: paymaster, counterparty_address: FEE_RECIPIENT },
        ],
        paymaster,
      },
      relationships: { chain: { links: { related: '' }, data: { type: 'chains', id: 'arbitrum' } } },
    };
  }

  it('reads the wallet send as the transfer and the paymaster send as the token fee', () => {
    const activity = transformEvmTxToUnified('arbitrum', buildGaslessTx(), OWNER);

    expect(activity).toMatchObject({
      kind: 'transaction',
      id: '0xgasless',
      fromAddress: normalizeAddress(OWNER),
      toAddress: normalizeAddress(RECIPIENT),
      amount: -TRANSFER_AMOUNT,
      slug: ARBITRUM_USDC_MAINNET.slug,
      isIncoming: false,
      fee: FEE_AMOUNT,
      extra: { isGasless: true },
    });
    expect(activity).not.toMatchObject({ type: 'callContract' });
  });

  it('keeps an incoming gasless transfer without charging the recipient the token fee', () => {
    const tx = buildGaslessTx({ direction: 'in' });
    tx.attributes.acts[1] = { id: '1', type: 'send', sent_from: RECIPIENT, counterparty_address: OWNER };
    tx.attributes.transfers[0] = {
      ...tx.attributes.transfers[0],
      direction: 'in',
      sender: RECIPIENT,
      recipient: OWNER,
    };
    tx.attributes.transfers[1] = {
      ...tx.attributes.transfers[1],
      sender: RECIPIENT,
    };

    const activity = transformEvmTxToUnified('arbitrum', tx, OWNER);

    expect(activity).toMatchObject({
      kind: 'transaction',
      fromAddress: normalizeAddress(RECIPIENT),
      toAddress: normalizeAddress(OWNER),
      amount: TRANSFER_AMOUNT,
      isIncoming: true,
      fee: 0n,
    });
    expect(activity.extra?.isGasless).toBeUndefined();
  });

  it('leaves a two-transfer execute alone when the paymaster is not Pimlico', () => {
    const activity = transformEvmTxToUnified('arbitrum', buildGaslessTx({ paymaster: FEE_RECIPIENT }), OWNER);

    expect(activity).toMatchObject({ type: 'callContract', amount: 0n });
  });
});

describe('transformEvmTxToUnified on gasless swaps', () => {
  const OWNER = '0x3e9526b6e3648abe93de78994cf4a3edbebe6032';
  const ROUTER = '0x2d01411773c8c24805306e89a41f7855c3c4fe65';
  const FEE_RECIPIENT = '0x4337ff05c84b9a80ea0a78dbe7b8e102f66d4c08';
  const PAYMASTER = PIMLICO_SINGLETON_PAYMASTER_ADDRESS.toLowerCase();
  const SOLD = 1_000_000n;
  const BOUGHT = 5n * 10n ** 18n;
  const FEE = 21_319n;
  const ARB_ADDRESS = '0x912ce59144191c1204e64559fe8253a0e49e6548';

  beforeEach(() => {
    jest.spyOn(tokenApi, 'getTokenBySlug').mockImplementation((slug) => ({
      slug,
      decimals: slug === ARBITRUM_USDC_MAINNET.slug ? 6 : 18,
      symbol: 'T',
      name: 'T',
      chain: 'arbitrum',
      priceUsd: 1,
    } as never));
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  function fungible(symbol: string, address: string, decimals: number) {
    return {
      id: address,
      name: symbol,
      symbol,
      // eslint-disable-next-line no-null/no-null
      icon: null,
      flags: { verified: true },
      implementations: [{ chain_id: 'arbitrum', address, decimals }],
    };
  }

  function buildSwapTx(withPaymaster: boolean): ZerionTransaction {
    return {
      type: 'transactions',
      id: 'swap',
      attributes: {
        address: OWNER,
        operation_type: 'execute',
        hash: '0xswap',
        mined_at_block: 1,
        mined_at: '2026-11-06T15:48:27Z',
        sent_from: '0x4337f6a4f786754045407d5b1653becccf8d89d7',
        sent_to: '0x0000000071727de22e5e9d8baf0edac6f37da032',
        status: 'confirmed',
        nonce: 1,
        fee: { quantity: { int: '1000', decimals: 18, float: 0, numeric: '0' }, price: 0, value: 0 },
        transfers: [
          {
            act_id: '2',
            direction: 'in',
            sender: ROUTER,
            recipient: OWNER,
            quantity: { int: BOUGHT.toString(), decimals: 18, float: 0, numeric: '0' },
            // eslint-disable-next-line no-null/no-null
            price: null,
            // eslint-disable-next-line no-null/no-null
            value: null,
            fungible_info: fungible('ARB', ARB_ADDRESS, 18),
          },
          {
            act_id: '2',
            direction: 'out',
            sender: OWNER,
            recipient: ROUTER,
            quantity: { int: SOLD.toString(), decimals: 6, float: 0, numeric: '0' },
            // eslint-disable-next-line no-null/no-null
            price: null,
            // eslint-disable-next-line no-null/no-null
            value: null,
            fungible_info: fungible('USDC', ARBITRUM_USDC_MAINNET.tokenAddress.toLowerCase(), 6),
          },
          {
            act_id: '3',
            direction: 'out',
            sender: OWNER,
            recipient: FEE_RECIPIENT,
            quantity: { int: FEE.toString(), decimals: 6, float: 0, numeric: '0' },
            // eslint-disable-next-line no-null/no-null
            price: null,
            // eslint-disable-next-line no-null/no-null
            value: null,
            fungible_info: fungible('USDC', ARBITRUM_USDC_MAINNET.tokenAddress.toLowerCase(), 6),
          },
        ],
        approvals: [],
        flags: { is_trash: false },
        acts: [
          { id: '2', type: 'trade', sent_from: OWNER, counterparty_address: ROUTER },
          {
            id: '3',
            type: 'send',
            sent_from: withPaymaster ? PAYMASTER : FEE_RECIPIENT,
            counterparty_address: FEE_RECIPIENT,
          },
        ],
        ...(withPaymaster ? { paymaster: PAYMASTER } : undefined),
      },
      relationships: { chain: { links: { related: '' }, data: { type: 'chains', id: 'arbitrum' } } },
    };
  }

  it('keeps the trade and writes the paymaster send as the token fee', () => {
    const activity = transformEvmTxToUnified('arbitrum', buildSwapTx(true), OWNER);

    expect(activity).toMatchObject({
      kind: 'swap',
      from: ARBITRUM_USDC_MAINNET.slug,
      fromAmount: '1',
      toAmount: '5',
      networkFee: '0.021319',
      extra: { isGasless: true },
    });
  });

  it('writes the paymaster token fee when a swap row is waiting for details', async () => {
    const hash = `0x${'ab'.repeat(32)}`;
    const tx = buildSwapTx(true);
    tx.attributes.hash = hash;
    fetchJsonMock.mockResolvedValueOnce({ data: [tx] });

    const detailed = await fetchActivityDetails('0-mainnet', {
      id: '1::backend-swap',
      kind: 'swap',
      timestamp: 1,
      from: ARBITRUM_USDC_MAINNET.slug,
      fromAmount: '1',
      to: 'arbitrum-0x912ce591',
      toAmount: '5',
      fromAddress: OWNER,
      networkFee: '0',
      swapFee: '0',
      status: 'completed',
      hashes: [hash],
      transactionIds: { outgoing: { hash, chain: 'arbitrum' } },
      shouldLoadDetails: true,
    });

    expect(detailed).toMatchObject({
      networkFee: '0.021319',
      shouldLoadDetails: undefined,
      extra: { isGasless: true },
    });
  });

  it('keeps the native fee when a swap has no Pimlico paymaster', () => {
    const activity = transformEvmTxToUnified('arbitrum', buildSwapTx(false), OWNER);

    expect(activity).toMatchObject({
      kind: 'swap',
      fromAmount: '1',
      toAmount: '5',
      networkFee: '0.000000000000001',
    });
    expect(activity.extra?.isGasless).toBeUndefined();
  });
});

import type { Cell, TupleItem } from '@ton/core';
import { Address, beginCell, TupleReader } from '@ton/core';

import { buildTokenSlug } from '../../../common/tokens';
import { isTransferPayloadDangerous } from '../../../dappProtocols/adapters/tonConnect';
import { parsePayloadBase64 } from './metadata';

const mockGetContractInfo = jest.fn();
const mockRunMethod = jest.fn();
const mockFetchToken = jest.fn();
const mockGetTokenByAddress = jest.fn();

jest.mock('../tokens', () => ({
  ...jest.requireActual('../tokens'),
  fetchToken: (...args: unknown[]) => mockFetchToken(...args),
}));
jest.mock('../../../common/tokens', () => ({
  ...jest.requireActual('../../../common/tokens'),
  getTokenByAddress: (...args: unknown[]) => mockGetTokenByAddress(...args),
}));

jest.mock('../wallet', () => ({
  ...jest.requireActual('../wallet'),
  getContractInfo: (...args: unknown[]) => mockGetContractInfo(...args),
}));
jest.mock('./tonCore', () => ({
  ...jest.requireActual('./tonCore'),
  getTonClient: () => ({ runMethod: mockRunMethod }),
}));

const VAULT = 'EQDa4VOnTYlLvDJ0gZjNYm5PXfSmmtL6Vs6A_CZEtXCNICq_';
const POOL = 'EQDcm06RlreuMurm-yik9WbL6kI617B77OrSRF_ZjoCYFuny';
const SIGNER = 'UQD-uIkQSbifhe99q3__pk9eNFrft7EuflWVZyvPdK3tLfJl';
const OTHER = Address.parse(`0:${'1'.repeat(64)}`);
const DUST = new Address(0, Buffer.from('65aac9b5e380eae928db3c8e238d9bc0d61a9320fdc2bc7a2f6c87d6fedf9208', 'hex'));
const POOL_HASH = '1275095b6da3911292406f4f4386f9e780099b854c6dee9ee2895ddce70927c1';
// Captured from dedust.io on MW iOS Pro A: 1 native coin -> DUST, with 0.25 attached for gas. Never signed.
const CAPTURED_PAYLOAD = 'te6cckEBAwEASQABbeoGGF067C2U7zJ3uEO5rKAIAbk2nSMtb1xl1c32UUnqzZfUhHWvYPfZ'
  + '1aSIv7MdATAsSaKr2+QBAglq2plzDgICAAguHPqCsv2tSg==';
const OPTIONS = { expectedOwnerAddress: SIGNER, messageAmount: 1_250_000_000n, supportsDedustSwap: true };
const DUST_TOKEN = {
  slug: buildTokenSlug('ton', DUST.toString()), name: 'Dust', symbol: 'DUST', decimals: 9,
  chain: 'ton', tokenAddress: DUST.toString(),
};

function stack(...items: TupleItem[]) {
  return { stack: new TupleReader(items) };
}

function addressItem(address: Address): TupleItem {
  return { type: 'slice', cell: beginCell().storeAddress(address).endCell() };
}

function buildPayload(options: {
  amount?: bigint; minimum?: bigint; kind?: boolean; next?: Cell;
  recipient?: Address; referral?: Address; fulfill?: Cell; reject?: Cell;
  extraRoot?: boolean; extraParams?: boolean;
} = {}) {
  const params = beginCell().storeUint(0, 32).storeAddress(options.recipient).storeAddress(options.referral)
    .storeMaybeRef(options.fulfill).storeMaybeRef(options.reject);
  if (options.extraParams) params.storeBit(true);
  const root = beginCell().storeUint(0xea06185d, 32).storeUint(0, 64)
    .storeCoins(options.amount ?? 1_000_000_000n).storeAddress(Address.parse(POOL))
    .storeBit(options.kind ?? false).storeCoins(options.minimum ?? 2_580_000_000n)
    .storeMaybeRef(options.next).storeRef(params.endCell());
  if (options.extraRoot) root.storeRef(beginCell().endCell());
  return root.endCell().toBoc().toString('base64');
}

describe('DeDust native swap payload classification', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetTokenByAddress.mockReturnValue(undefined);
    mockFetchToken.mockResolvedValue(DUST_TOKEN);
    mockGetContractInfo.mockImplementation((_network, address) => {
      if (Address.parse(address).equals(Address.parse(VAULT))) {
        return { isInitialized: true, contractInfo: { name: 'dedustVaultNativeV2' } };
      }
      if (Address.parse(address).equals(Address.parse(POOL))) {
        return { isInitialized: true, codeHash: POOL_HASH };
      }
      return { isInitialized: true, contractInfo: { name: 'W5' } };
    });
    mockRunMethod.mockImplementation((_address, method) => {
      if (method === 'get_assets') {
        return stack(
          { type: 'cell', cell: beginCell().storeUint(0, 4).endCell() },
          { type: 'cell', cell: beginCell().storeUint(1, 4).storeInt(0, 8).storeBuffer(DUST.hash).endCell() },
        );
      }
      if (method === 'is_stable') return stack({ type: 'int', value: 0n });
      if (method === 'get_pool_address') return stack(addressItem(Address.parse(POOL)));
      throw new Error('Unexpected method');
    });
  });

  it('recognizes the captured request without any emulation result', async () => {
    const result = await parsePayloadBase64('mainnet', VAULT, CAPTURED_PAYLOAD, OPTIONS);
    expect(result).toEqual({
      type: 'dedust:native-swap', queryId: 4245818666395006904n, amount: 1_000_000_000n,
      poolAddress: POOL, toSlug: buildTokenSlug('ton', DUST.toString()), toToken: DUST_TOKEN,
      minimumAmountOut: 2_586_492_350n, recipientAddress: Address.parse(SIGNER).toString(), deadline: 1792711027,
    });
    expect(isTransferPayloadDangerous(result, SIGNER)).toBe(false);
  });

  it('requires a client that supports the swap presentation', async () => {
    for (const supportsDedustSwap of [undefined, false]) {
      const result = await parsePayloadBase64('mainnet', VAULT, CAPTURED_PAYLOAD, { ...OPTIONS, supportsDedustSwap });
      expect(result.type).toBe('unknown');
      expect(isTransferPayloadDangerous(result, SIGNER)).toBe(true);
    }
    expect(mockGetContractInfo).not.toHaveBeenCalled();
  });

  it('includes uncached output metadata rather than assuming nine decimals', async () => {
    const toToken = { ...DUST_TOKEN, decimals: 18 };
    mockFetchToken.mockResolvedValue(toToken);
    const result = await parsePayloadBase64('mainnet', VAULT, buildPayload({ minimum: 10n ** 18n }), OPTIONS);
    expect(result).toMatchObject({ type: 'dedust:native-swap', minimumAmountOut: 10n ** 18n, toToken });
    expect(mockFetchToken).toHaveBeenCalledWith('mainnet', DUST.toString());
  });

  it('reuses metadata already resolved for the output master', async () => {
    mockGetTokenByAddress.mockReturnValue(DUST_TOKEN);
    expect((await parsePayloadBase64('mainnet', VAULT, CAPTURED_PAYLOAD, OPTIONS)).type).toBe('dedust:native-swap');
    expect(mockFetchToken).not.toHaveBeenCalled();
  });

  it.each([
    { error: 'Unavailable' },
    ...[-1, 1.5, 256, NaN].map((decimals) => ({ ...DUST_TOKEN, decimals })),
  ])('keeps unresolved or invalid output metadata unknown %#', async (metadata) => {
    mockFetchToken.mockResolvedValue(metadata);
    const result = await parsePayloadBase64('mainnet', VAULT, CAPTURED_PAYLOAD, OPTIONS);
    expect(result.type).toBe('unknown');
    expect(isTransferPayloadDangerous(result, SIGNER)).toBe(true);
  });

  it('supports absent notifications and an explicit signer recipient', async () => {
    const result = await parsePayloadBase64('mainnet', VAULT, buildPayload({
      recipient: Address.parse(SIGNER),
    }), OPTIONS);
    expect(result.type).toBe('dedust:native-swap');
  });

  it.each([
    ['different recipient', { recipient: OTHER }],
    ['referral', { referral: OTHER }],
    ['exact-output mode', { kind: true }],
    ['multi-hop route', { next: beginCell().endCell() }],
    ['zero input', { amount: 0n }],
    ['zero minimum', { minimum: 0n }],
    ['unknown callback', { fulfill: beginCell().storeUint(1, 32).endCell() }],
    ['unknown rejection callback', { reject: beginCell().storeUint(1, 32).endCell() }],
    ['notification with arguments', { fulfill: beginCell().storeUint(0x2e1cfa82, 32).storeBit(true).endCell() }],
    ['notification with references', { reject: beginCell().storeUint(0x2e1cfa82, 32).storeRef(beginCell()).endCell() }],
    ['extra root reference', { extraRoot: true }],
    ['extra parameter bits', { extraParams: true }],
  ] as const)('keeps %s unknown', async (_name, options) => {
    const result = await parsePayloadBase64('mainnet', VAULT, buildPayload(options), OPTIONS);
    expect(result.type).toBe('unknown');
    expect(isTransferPayloadDangerous(result, SIGNER)).toBe(true);
  });

  it.each([
    undefined,
    { expectedOwnerAddress: SIGNER, supportsDedustSwap: true },
    { messageAmount: 1_250_000_000n, supportsDedustSwap: true },
    { ...OPTIONS, messageAmount: 1_000_000_000n },
    { ...OPTIONS, messageAmount: 999_999_999n },
    { ...OPTIONS, messageAmount: 1_300_000_001n },
    { ...OPTIONS, stateInit: 'state-init' },
  ])('requires a consistent message context %#', async (options) => {
    expect((await parsePayloadBase64('mainnet', VAULT, CAPTURED_PAYLOAD, options)).type).toBe('unknown');
  });

  it('does not trust the same opcode at another address or on another network', async () => {
    expect((await parsePayloadBase64('mainnet', OTHER.toString(), CAPTURED_PAYLOAD, OPTIONS)).type).toBe('unknown');
    expect((await parsePayloadBase64('testnet', VAULT, CAPTURED_PAYLOAD, OPTIONS)).type).toBe('unknown');
    expect(mockGetContractInfo).not.toHaveBeenCalled();
  });

  it.each(['vault', 'pool', 'wallet', 'factory', 'rpc'])('fails closed on unverified %s', async (failure) => {
    if (failure === 'rpc') mockGetContractInfo.mockRejectedValue(new Error('Unavailable'));
    if (failure === 'vault') mockGetContractInfo.mockResolvedValue({ isInitialized: false });
    if (failure === 'pool') {
      mockGetContractInfo.mockImplementation((_network, address) => (
        address === VAULT
          ? { isInitialized: true, contractInfo: { name: 'dedustVaultNativeV2' } }
          : { isInitialized: true, codeHash: 'unknown' }
      ));
    }
    if (failure === 'wallet') {
      mockGetContractInfo.mockImplementation((_network, address) => (
        address === VAULT
          ? { isInitialized: true, contractInfo: { name: 'dedustVaultNativeV2' } }
          : { isInitialized: true, codeHash: POOL_HASH, contractInfo: { name: 'telegram' } }
      ));
    }
    if (failure === 'factory') {
      const valid = mockRunMethod.getMockImplementation()!;
      mockRunMethod.mockImplementation((address, method) => (
        method === 'get_pool_address' ? stack(addressItem(OTHER)) : valid(address, method)
      ));
    }
    expect((await parsePayloadBase64('mainnet', VAULT, CAPTURED_PAYLOAD, OPTIONS)).type).toBe('unknown');
  });

  it('does not accept a truncated payload', async () => {
    const payload = beginCell().storeUint(0xea06185d, 32).storeUint(0, 64).endCell().toBoc().toString('base64');
    expect((await parsePayloadBase64('mainnet', VAULT, payload, OPTIONS)).type).toBe('unknown');
  });
});

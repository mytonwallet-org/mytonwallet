import { Address, beginCell, Cell } from '@ton/core';

import type { ApiAccountWithChain, ApiSwapBuildTransactionRequest } from '../../types';
import type { TonTransferParams } from './types';

import { SWAP_FEE_ADDRESS } from '../../../config';
import { OpCode } from './constants';
import { validateDexSwapTransfers } from './swap';

const mockGetContractInfo = jest.fn();
const mockResolveTokenWalletAddress = jest.fn();
const mockGetTokenByAddress = jest.fn();

jest.mock('./wallet', () => ({ getContractInfo: (...args: unknown[]) => mockGetContractInfo(...args) }));
jest.mock('./util/tonCore', () => ({
  ...jest.requireActual('./util/tonCore'),
  resolveTokenWalletAddress: (...args: unknown[]) => mockResolveTokenWalletAddress(...args),
}));
jest.mock('../../common/tokens', () => ({
  ...jest.requireActual('../../common/tokens'),
  getTokenByAddress: (...args: unknown[]) => mockGetTokenByAddress(...args),
}));

const OWNER = 'EQALlDeWN7gL49-tvhl5ZR28r8iSHKDLR78zP0F9dk6oYULB';
const ATTACKER = 'EQBvgReNRyFPokbDMi1ftAK5IvYAc8b0MV1qK280WAl4Qx1P';
const MASTER = 'EQAmoQqDz6woBJ1dvwFl14PHdD6CE3eVMd58INFRKp3n9Ycw';
const WALLET = 'EQALy-63XUWvd819Mus4AI12D8YoZt30YcKJuL7q9jov_Moz';
const GROSS = 1_000_000_000n;
const FEE = 8_750_000n;
const ACCOUNT = { type: 'mnemonic', byChain: { ton: { version: 'W5' } } } as unknown as ApiAccountWithChain<'ton'>;

function request(overrides: Partial<ApiSwapBuildTransactionRequest> = {}) {
  return {
    from: MASTER, to: 'TON', fromAddress: OWNER, fromAmount: '1',
    toAmount: '0.0074', toMinAmount: '0.007326', slippage: 1,
    ourFee: '0.00875', dieselFee: '0', ...overrides,
  } as ApiSwapBuildTransactionRequest;
}

function sellPayload({
  amount = GROSS - FEE, minimum = 7_326_000n, excessesTo = OWNER,
  partner, referrer, trailing = false,
}: {
  amount?: bigint;
  minimum?: bigint;
  excessesTo?: string;
  partner?: Cell;
  referrer?: Cell;
  trailing?: boolean;
} = {}) {
  const builder = beginCell().storeUint(0xb7459e2c, 32).storeUint(1n, 64)
    .storeCoins(amount).storeCoins(minimum).storeAddress(Address.parse(excessesTo))
    .storeMaybeRef(partner).storeMaybeRef(referrer);
  if (trailing) builder.storeBit(0);
  return builder.endCell();
}

function feePayload(amount = FEE, destination = SWAP_FEE_ADDRESS) {
  return beginCell().storeUint(0x0f8a7ea5, 32).storeUint(2n, 64)
    .storeCoins(amount).storeAddress(Address.parse(destination)).storeAddress(Address.parse(OWNER))
    .storeMaybeRef(undefined).storeCoins(1n)
    .storeBit(1).storeRef(beginCell().storeUint(OpCode.OurFee, 32).endCell()).endCell();
}

function transfers(main: Partial<TonTransferParams> = {}, fee: Partial<TonTransferParams> = {}) {
  return [
    { toAddress: WALLET, amount: 50_000_000n, payload: sellPayload(), ...main },
    { toAddress: WALLET, amount: 50_000_000n, payload: feePayload(), ...fee },
  ] as TonTransferParams[];
}

describe('direct Uranus sell validation', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetTokenByAddress.mockReturnValue({ decimals: 9, tokenAddress: MASTER });
    mockResolveTokenWalletAddress.mockResolvedValue(WALLET);
    mockGetContractInfo.mockImplementation((_network, address) => Promise.resolve(
      address === MASTER
        ? { isInitialized: true, isSwapAllowed: true,
          codeHash: 'f4ba4ebd2678dde0c750564bd22ee0876aa2f39a1e8d3aacb606ba0c39a71d9a',
          contractInfo: { nativeSwapPayload: 'dedustUranusMemepadBuy' } }
        : { isInitialized: true,
          codeHash: 'e2da88070dcf9d1b2ed4ab9079b8c473625bf320f38423ed86ee03ef5c326858' },
    ));
  });

  it('accepts a direct included-fee sell and a zero-fee sell', async () => {
    await expect(validateDexSwapTransfers('mainnet', OWNER, request(), transfers(), ACCOUNT))
      .resolves.toBe(7_326_000n);
    await expect(validateDexSwapTransfers('mainnet', OWNER,
      request({ ourFee: '0' }),
      [transfers({ payload: sellPayload({ amount: GROSS }) })[0]], ACCOUNT))
      .resolves.toBe(7_326_000n);
  });

  it('accepts the read-only live LEEK router build for a historical holder', async () => {
    // DeDust /v4/router/swap for 991250000 LEEK units, quoted on 2026-10-17; no broadcast.
    const livePayload = Cell.fromBase64(
      'te6cckEBAQEANwAAabdFniw67C2UIsSMOUOxVGUCBbGAAXKG8sb3AXx79bfDLyyjt5X5EkOUGWj35mfoL67J1QwkEqu/jQ==',
    );
    await expect(validateDexSwapTransfers('mainnet', OWNER,
      request({ toAmount: '0.000001472', toMinAmount: '0.000001457' }),
      transfers({ payload: livePayload }), ACCOUNT)).resolves.toBe(1457n);
  });

  it('accepts MAX with integer-unit fee rounding', async () => {
    const gross = 4_170_000_001n;
    const fee = gross * 875n / 100000n;
    await expect(validateDexSwapTransfers('mainnet', OWNER,
      request({ fromAmount: '4.170000001', ourFee: '0.0364875' }),
      transfers({ payload: sellPayload({ amount: gross - fee }) }, { payload: feePayload(fee) }), ACCOUNT))
      .resolves.toBe(7_326_000n);
  });

  it.each([
    ['wrong sell amount', () => transfers({ payload: sellPayload({ amount: GROSS }) })],
    ['attacker excesses', () => transfers({ payload: sellPayload({ excessesTo: ATTACKER }) })],
    ['partner attribution', () => transfers({ payload: sellPayload({ partner: beginCell().endCell() }) })],
    ['referrer attribution', () => transfers({ payload: sellPayload({ referrer: beginCell().endCell() }) })],
    ['trailing payload', () => transfers({ payload: sellPayload({ trailing: true }) })],
    ['bad fee receiver', () => transfers({}, { payload: feePayload(FEE, ATTACKER) })],
    ['bad fee amount', () => transfers({}, { payload: feePayload(FEE + 1n) })],
    ['excessive gas', () => transfers({ amount: 101_000_000n })],
    ['excessive combined gas', () => transfers({ amount: 60_000_000n })],
    ['state init', () => transfers({ stateInit: beginCell().endCell() })],
    ['poisoned minimum', () => transfers({ payload: sellPayload({ minimum: 1n }) })],
  ])('rejects %s', async (_label, build) => {
    await expect(validateDexSwapTransfers('mainnet', OWNER, request(), build(), ACCOUNT)).rejects.toThrow();
  });

  it('rejects an untrusted wallet code hash', async () => {
    mockGetContractInfo.mockImplementation((_network, address) => Promise.resolve(
      address === MASTER
        ? { isInitialized: true, isSwapAllowed: true,
          codeHash: 'f4ba4ebd2678dde0c750564bd22ee0876aa2f39a1e8d3aacb606ba0c39a71d9a',
          contractInfo: { nativeSwapPayload: 'dedustUranusMemepadBuy' } }
        : { isInitialized: true, codeHash: 'attacker' },
    ));
    await expect(validateDexSwapTransfers('mainnet', OWNER, request(), transfers(), ACCOUNT)).rejects.toThrow();
  });

  it('rejects diesel and unexpected extra transfers', async () => {
    await expect(validateDexSwapTransfers('mainnet', OWNER,
      request({ dieselFee: '0.01' }), transfers(), ACCOUNT)).rejects.toThrow();
    await expect(validateDexSwapTransfers('mainnet', OWNER,
      request({ ourFee: '0' }), transfers(), ACCOUNT)).rejects.toThrow();
  });

  it.each([
    ['V2', '722d37be518ee0d4b6714077727ed60724bf379e8f1479c220b853d1af3cf00d',
      '21097ae6d15af88099db08eb49b71df933905c86a09c3823fd5f0e1a8b6acdae'],
    ['V3', '1e4f8fcaabefdbbb9b397372d9f021511c272eda2b492ca2d33b817bc3251afe',
      'e2da88070dcf9d1b2ed4ab9079b8c473625bf320f38423ed86ee03ef5c326858'],
    ['V3.1', 'f4ba4ebd2678dde0c750564bd22ee0876aa2f39a1e8d3aacb606ba0c39a71d9a',
      'e2da88070dcf9d1b2ed4ab9079b8c473625bf320f38423ed86ee03ef5c326858'],
    ['V3.2', '7369f9b9f570e1bf78b0dc9d52cbab7ce21a4f000ee858ea6e81d43232c1a2d6',
      '0621a91b5f2762f0ca34dc73b1b93186542b6e3dd89ab8f71ba91c2c8a17b6f2'],
  ])('matches the %s master to its independently observed wallet class', async (_version, masterHash, walletHash) => {
    mockGetContractInfo.mockImplementation((_network, address) => Promise.resolve(
      address === MASTER
        ? { isInitialized: true, isSwapAllowed: true, codeHash: masterHash,
          contractInfo: { nativeSwapPayload: 'dedustUranusMemepadBuy' } }
        : { isInitialized: true, codeHash: walletHash },
    ));
    await expect(validateDexSwapTransfers('mainnet', OWNER, request(), transfers(), ACCOUNT))
      .resolves.toBe(7_326_000n);
  });
});

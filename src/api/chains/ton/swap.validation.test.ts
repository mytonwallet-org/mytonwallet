import { Address, beginCell, type Cell } from '@ton/core';

import type { ApiAccountWithChain, ApiSwapBuildTransactionRequest } from '../../types';
import type { TonTransferParams } from './types';

import { DIESEL_ADDRESS, SWAP_FEE_ADDRESS } from '../../../config';
import { OpCode } from './constants';
import { validateDexSwapTransfers } from './swap';
import { getContractInfo } from './wallet';

jest.mock('./wallet', () => ({
  getContractInfo: jest.fn(),
}));

const USER_ADDRESS = 'EQDI24m89j6OUi_Qi0Es9DtdOEQgMgKvm6jhPb474bGk_F68';
const ATTACKER_ADDRESS = 'EQBvgReNRyFPokbDMi1ftAK5IvYAc8b0MV1qK280WAl4Qx1P';
const URANUS_MEME_ADDRESS = 'EQAmoQqDz6woBJ1dvwFl14PHdD6CE3eVMd58INFRKp3n9Ycw';
const OTHER_URANUS_MEME_ADDRESS = 'EQA69EB5TreoR3Kf3rm0gjHtdbvIejQUDabrPglnFXji8uAo';
const BUY_OPCODE = 0x94826557;
const ONE_TON = 1_000_000_000n;
const OUR_FEE = 8_750_000n;
const BUY_AMOUNT = ONE_TON - OUR_FEE;
const ACCOUNT = {
  type: 'mnemonic',
  byChain: { ton: { version: 'W5' } },
} as unknown as ApiAccountWithChain<'ton'>;

function buildRequest(overrides: Partial<ApiSwapBuildTransactionRequest> = {}): ApiSwapBuildTransactionRequest {
  return {
    from: 'TON',
    to: URANUS_MEME_ADDRESS,
    fromAmount: '1',
    fromAddress: USER_ADDRESS,
    toAmount: '1',
    toMinAmount: '0.99',
    slippage: 1,
    ourFee: '0.00875',
    dieselFee: '0',
    ...overrides,
  };
}

function buildUranusBuyPayload({
  opcode = BUY_OPCODE,
  amount = BUY_AMOUNT,
  minimalAmountOut = 990_000_000n,
  excessesTo = USER_ADDRESS,
  partnerConfig,
  referrerConfig,
  hasTrailingBit = false,
}: {
  opcode?: number;
  amount?: bigint;
  minimalAmountOut?: bigint;
  excessesTo?: string;
  partnerConfig?: Cell;
  referrerConfig?: Cell;
  hasTrailingBit?: boolean;
} = {}) {
  const builder = beginCell()
    .storeUint(opcode, 32)
    .storeUint(1n, 64)
    .storeCoins(amount)
    .storeCoins(minimalAmountOut)
    .storeAddress(Address.parse(excessesTo))
    .storeMaybeRef(partnerConfig)
    .storeMaybeRef(referrerConfig);

  if (hasTrailingBit) {
    builder.storeBit(0);
  }

  return builder.endCell();
}

function buildTransfer(overrides: Partial<TonTransferParams> = {}): TonTransferParams {
  return {
    toAddress: URANUS_MEME_ADDRESS,
    amount: BUY_AMOUNT + 80_000_000n,
    payload: buildUranusBuyPayload(),
    ...overrides,
  };
}

function withFee(mainTransfer: TonTransferParams = buildTransfer(), fee = OUR_FEE): TonTransferParams[] {
  return [mainTransfer, { toAddress: SWAP_FEE_ADDRESS, amount: fee,
    payload: beginCell().storeUint(OpCode.OurFee, 32).endCell() }];
}

function buildConfigCell() {
  return beginCell()
    .storeUint(1n, 256)
    .storeUint(60, 16)
    .endCell();
}

describe('validateDexSwapTransfers Uranus memepad buys', () => {
  it('keeps standard native-in swap contract validation unchanged', async () => {
    jest.mocked(getContractInfo).mockResolvedValueOnce({
      isInitialized: true,
      isSwapAllowed: true,
      codeHash: '875fac5e08e5062f0f7c5c9f4c989607108e35a9ad88dc563e3e4fc7a3d3e75c',
      contractInfo: {
        name: 'dedustVaultNativeV2',
        hash: '875fac5e08e5062f0f7c5c9f4c989607108e35a9ad88dc563e3e4fc7a3d3e75c',
        isSwapAllowed: true,
      },
    });

    await expect(validateDexSwapTransfers(
      'mainnet',
      USER_ADDRESS,
      buildRequest({ ourFee: '0' }),
      [buildTransfer({ payload: undefined })],
      ACCOUNT,
    )).resolves.toBeUndefined();
  });

  beforeEach(() => {
    jest.clearAllMocks();
    jest.mocked(getContractInfo).mockResolvedValue({
      isInitialized: true,
      isSwapAllowed: true,
      codeHash: 'f4ba4ebd2678dde0c750564bd22ee0876aa2f39a1e8d3aacb606ba0c39a71d9a',
      contractInfo: {
        name: 'dedustUranusMemeV3_1',
        hash: 'f4ba4ebd2678dde0c750564bd22ee0876aa2f39a1e8d3aacb606ba0c39a71d9a',
        isSwapAllowed: true,
        nativeSwapPayload: 'dedustUranusMemepadBuy',
      },
    });
  });

  it('accepts a valid native-in Uranus memepad buy', async () => {
    await expect(validateDexSwapTransfers(
      'mainnet',
      USER_ADDRESS,
      buildRequest(),
      withFee(),
      ACCOUNT,
    )).resolves.toBe(990_000_000n);
  });

  it('accepts a MAX buy whose signed amount matches the estimate input', async () => {
    const amount = 4_170_000_000n;
    const fee = amount * 875n / 100000n;
    await expect(validateDexSwapTransfers(
      'mainnet',
      USER_ADDRESS,
      buildRequest({ fromAmount: '4.17', ourFee: '0.0364875' }),
      withFee(buildTransfer({ amount: amount - fee + 50_000_000n,
        payload: buildUranusBuyPayload({ amount: amount - fee }) }), fee),
      ACCOUNT,
    )).resolves.toBe(990_000_000n);
  });

  it('rounds the included fee down to whole nanotons', async () => {
    const gross = ONE_TON + 1n;
    const fee = OUR_FEE;
    await expect(validateDexSwapTransfers(
      'mainnet', USER_ADDRESS,
      buildRequest({ fromAmount: '1.000000001' }),
      withFee(buildTransfer({ amount: gross - fee + 50_000_000n,
        payload: buildUranusBuyPayload({ amount: gross - fee }) }), fee),
      ACCOUNT,
    )).resolves.toBe(990_000_000n);
  });

  it('rejects another Uranus master even when it has the same trusted code hash and a valid buy payload', async () => {
    await expect(validateDexSwapTransfers(
      'mainnet',
      USER_ADDRESS,
      buildRequest(), // The user selected LEEK; the build redirects the buy to GW.
      withFee(buildTransfer({ toAddress: OTHER_URANUS_MEME_ADDRESS })),
      ACCOUNT,
    )).rejects.toThrow('Uranus memepad buy destination is not the selected token');
  });

  it('rejects Uranus buy state init', async () => {
    await expect(validateDexSwapTransfers(
      'mainnet',
      USER_ADDRESS,
      buildRequest(),
      withFee(buildTransfer({ stateInit: beginCell().endCell() })),
      ACCOUNT,
    )).rejects.toThrow('Uranus memepad buy transfer must not have state init');
  });

  it('rejects a wrong Uranus buy opcode', async () => {
    await expect(validateDexSwapTransfers(
      'mainnet',
      USER_ADDRESS,
      buildRequest(),
      withFee(buildTransfer({ payload: buildUranusBuyPayload({ opcode: 0xb7459e2c }) })),
      ACCOUNT,
    )).rejects.toThrow('Unexpected Uranus memepad buy opcode');
  });

  it('rejects a truncated Uranus buy payload', async () => {
    const payload = beginCell()
      .storeUint(BUY_OPCODE, 32)
      .storeUint(1n, 64)
      .storeCoins(ONE_TON)
      .endCell();

    await expect(validateDexSwapTransfers(
      'mainnet',
      USER_ADDRESS,
      buildRequest(),
      withFee(buildTransfer({ payload })),
      ACCOUNT,
    )).rejects.toThrow('Uranus memepad buy transfer payload is invalid');
  });

  it('rejects an attacker excesses address', async () => {
    await expect(validateDexSwapTransfers(
      'mainnet',
      USER_ADDRESS,
      buildRequest(),
      withFee(buildTransfer({ payload: buildUranusBuyPayload({ excessesTo: ATTACKER_ADDRESS }) })),
      ACCOUNT,
    )).rejects.toThrow('Uranus memepad buy excesses address is not the wallet address');
  });

  it('rejects partner and referrer fee configs', async () => {
    await expect(validateDexSwapTransfers(
      'mainnet',
      USER_ADDRESS,
      buildRequest(),
      withFee(buildTransfer({ payload: buildUranusBuyPayload({ partnerConfig: buildConfigCell() }) })),
      ACCOUNT,
    )).rejects.toThrow('Uranus memepad buy partner config is not allowed');

    await expect(validateDexSwapTransfers(
      'mainnet',
      USER_ADDRESS,
      buildRequest(),
      withFee(buildTransfer({ payload: buildUranusBuyPayload({ referrerConfig: buildConfigCell() }) })),
      ACCOUNT,
    )).rejects.toThrow('Uranus memepad buy referrer config is not allowed');
  });

  it('rejects a buy payload amount that differs from the requested TON amount', async () => {
    await expect(validateDexSwapTransfers(
      'mainnet',
      USER_ADDRESS,
      buildRequest(),
      withFee(buildTransfer({ payload: buildUranusBuyPayload({ amount: BUY_AMOUNT - 1n }) })),
      ACCOUNT,
    )).rejects.toThrow('Uranus memepad buy amount plus fee does not match request amount');
  });

  it('accepts a black-tier or campaign zero-fee buy with principal equal to X', async () => {
    for (const ourFee of ['0', undefined]) {
      await expect(validateDexSwapTransfers(
        'mainnet', USER_ADDRESS, buildRequest({ ourFee }),
        [buildTransfer({ amount: ONE_TON + 50_000_000n,
          payload: buildUranusBuyPayload({ amount: ONE_TON }) })], ACCOUNT,
      )).resolves.toBe(990_000_000n);
    }
  });

  it('accepts zero fee for MAX and a positive loyalty discount', async () => {
    const maxGross = 4_170_000_000n;
    await expect(validateDexSwapTransfers(
      'mainnet', USER_ADDRESS, buildRequest({ fromAmount: '4.17', ourFee: '0' }),
      [buildTransfer({ amount: maxGross + 50_000_000n,
        payload: buildUranusBuyPayload({ amount: maxGross }) })], ACCOUNT,
    )).resolves.toBe(990_000_000n);

    const discountedFee = 4_375_000n;
    await expect(validateDexSwapTransfers(
      'mainnet', USER_ADDRESS, buildRequest({ ourFee: '0.004375' }),
      withFee(buildTransfer({ amount: ONE_TON - discountedFee + 50_000_000n,
        payload: buildUranusBuyPayload({ amount: ONE_TON - discountedFee }) }), discountedFee), ACCOUNT,
    )).resolves.toBe(990_000_000n);
  });

  it('rejects a buy that omits the quoted positive fee transfer', async () => {
    await expect(validateDexSwapTransfers(
      'mainnet', USER_ADDRESS, buildRequest(), [buildTransfer()], ACCOUNT,
    )).rejects.toThrow();
  });

  it('rejects an extra fee transfer when the quote says zero', async () => {
    const main = buildTransfer({ amount: ONE_TON + 50_000_000n,
      payload: buildUranusBuyPayload({ amount: ONE_TON }) });
    for (const feeAddress of [SWAP_FEE_ADDRESS, ATTACKER_ADDRESS]) {
      const transfers = withFee(main, 1n);
      transfers[1].toAddress = feeAddress;
      await expect(validateDexSwapTransfers(
        'mainnet', USER_ADDRESS, buildRequest({ ourFee: '0' }), transfers, ACCOUNT,
      )).rejects.toThrow('Uranus memepad buy must have exactly one main transfer');
    }
  });

  it('rejects a native Uranus quote with a separate diesel fee', async () => {
    await expect(validateDexSwapTransfers(
      'mainnet', USER_ADDRESS, buildRequest({ dieselFee: '0.000000001' }), withFee(), ACCOUNT,
    )).rejects.toThrow('Uranus memepad buy does not support diesel fee');
  });

  it('rejects a fee above the client cap even when the backend quote and payload agree', async () => {
    const fee = 8_750_001n;
    await expect(validateDexSwapTransfers(
      'mainnet', USER_ADDRESS, buildRequest({ ourFee: '0.008750001' }),
      withFee(buildTransfer({ payload: buildUranusBuyPayload({ amount: ONE_TON - fee }) }), fee), ACCOUNT,
    )).rejects.toThrow('Uranus memepad fee exceeds the client cap');
  });

  it('rejects a fee transfer to a different configured fee address', async () => {
    const transfers = withFee();
    transfers[1].toAddress = ATTACKER_ADDRESS;
    await expect(validateDexSwapTransfers(
      'mainnet', USER_ADDRESS, buildRequest(), transfers, ACCOUNT,
    )).rejects.toThrow('Unexpected fee transfer address');

    transfers[1].toAddress = DIESEL_ADDRESS;
    await expect(validateDexSwapTransfers(
      'mainnet', USER_ADDRESS, buildRequest(), transfers, ACCOUNT,
    )).rejects.toThrow('Uranus memepad fee destination is invalid');
  });

  it('rejects a nonzero fee transfer with the wrong opcode', async () => {
    const transfers = withFee();
    transfers[1].payload = beginCell().storeUint(0x12345678, 32).endCell();
    await expect(validateDexSwapTransfers(
      'mainnet', USER_ADDRESS, buildRequest(), transfers, ACCOUNT,
    )).rejects.toThrow('Uranus memepad fee transfer payload is invalid');
  });

  it('rejects a quoted fee that differs from the signed fee transfer', async () => {
    await expect(validateDexSwapTransfers(
      'mainnet', USER_ADDRESS, buildRequest(), withFee(buildTransfer(), OUR_FEE - 1n), ACCOUNT,
    )).rejects.toThrow('Uranus memepad fee does not match quote');
  });

  it('rejects overlarge gas/buy-value slack', async () => {
    await expect(validateDexSwapTransfers(
      'mainnet',
      USER_ADDRESS,
      buildRequest(),
      withFee(buildTransfer({ amount: BUY_AMOUNT + 201_000_000n })),
      ACCOUNT,
    )).rejects.toThrow('Uranus memepad buy gas amount is too big');
  });

  it('rejects a signed minimum output below the quoted minimum', async () => {
    await expect(validateDexSwapTransfers(
      'mainnet',
      USER_ADDRESS,
      buildRequest({ toAmount: '0.95' }),
      withFee(buildTransfer({ payload: buildUranusBuyPayload({ minimalAmountOut: 989_999_999n }) })),
      ACCOUNT,
    )).rejects.toThrow('Uranus memepad buy minimum amount out is too low');
  });

  it('rejects a backend-poisoned minimum even when the signed payload repeats that minimum', async () => {
    await expect(validateDexSwapTransfers(
      'mainnet',
      USER_ADDRESS,
      buildRequest({ toMinAmount: '0.000000001' }),
      withFee(buildTransfer({ payload: buildUranusBuyPayload({ minimalAmountOut: 1n }) })),
      ACCOUNT,
    )).rejects.toThrow('Uranus memepad buy minimum amount out is below the quoted output and slippage');
  });

  it('requires a displayed quote and the user slippage setting', async () => {
    await expect(validateDexSwapTransfers(
      'mainnet', USER_ADDRESS, buildRequest({ toAmount: undefined }), withFee(), ACCOUNT,
    )).rejects.toThrow('Uranus memepad buy quoted amount out is missing');

    await expect(validateDexSwapTransfers(
      'mainnet', USER_ADDRESS, buildRequest({ slippage: undefined }), withFee(), ACCOUNT,
    )).rejects.toThrow('Uranus memepad buy slippage is invalid');
  });

  it('rejects trailing payload data', async () => {
    await expect(validateDexSwapTransfers(
      'mainnet',
      USER_ADDRESS,
      buildRequest(),
      withFee(buildTransfer({ payload: buildUranusBuyPayload({ hasTrailingBit: true }) })),
      ACCOUNT,
    )).rejects.toThrow('Unexpected extra data in swap payload');
  });
});

import { Address, beginCell, Cell, internal, SendMode, storeMessageRelaxed } from '@ton/core';
import { storeOutListExtendedV5R1 } from '@ton/ton/dist/wallets/v5r1/WalletV5R1Actions';
import { WalletContractV5R1 } from '@ton/ton/dist/wallets/WalletContractV5R1';

jest.mock('../api/connector', () => ({
  callMfaApiWithThrow: jest.fn(),
}));

import { callMfaApiWithThrow } from '../api/connector';
import { emulatePayload, getTrustedMfaRefillAmount } from './extension';

const extensionAddress = Address.parseRaw(`0:${'1'.repeat(64)}`);
const otherAddress = Address.parseRaw(`0:${'2'.repeat(64)}`);
const refillAmount = 123456789n;
const refillMode = SendMode.PAY_GAS_SEPARATELY | SendMode.IGNORE_ERRORS;

function makePayload() {
  const payload = beginCell().storeUint(0xabcdef, 32).endCell();
  return {
    rawPayload: payload.toBoc().toString('base64'),
    payloadHash: payload.hash().toString('base64'),
  };
}

function makeWalletBody({
  mode = refillMode,
  to = extensionAddress,
  value = refillAmount,
  body = new Cell(),
} = {}) {
  return beginCell()
    .storeUint(WalletContractV5R1.OpCodes.auth_extension, 32)
    .storeUint(0n, 64)
    .store(storeOutListExtendedV5R1([{
      type: 'sendMsg' as const,
      mode,
      outMsg: internal({ to, value, body }),
    }]))
    .endCell();
}

function makeMfaSendActionsPayload(walletBody = makeWalletBody()) {
  const walletAddress = Address.parseRaw(`0:${'3'.repeat(64)}`);
  const messageToWallet = internal({
    to: walletAddress,
    value: 1n,
    body: walletBody,
  });
  const outAction = beginCell()
    .storeUint(SendMode.PAY_GAS_SEPARATELY | SendMode.IGNORE_ERRORS, 8)
    .storeRef(beginCell().store(storeMessageRelaxed(messageToWallet)).endCell())
    .endCell();
  const payload = beginCell()
    .storeUint(0xb15f2c8c, 32)
    .storeUint(0, 32)
    .storeRef(outAction)
    .endCell();

  return {
    rawPayload: payload.toBoc().toString('base64'),
    payloadHash: payload.hash().toString('base64'),
    walletAddress: walletAddress.toString({ urlSafe: true, bounceable: false }),
  };
}

describe('getTrustedMfaRefillAmount', () => {
  it('accepts the final empty-body refill action with the deterministic refill send mode', () => {
    const { rawPayload, payloadHash } = makePayload();

    expect(getTrustedMfaRefillAmount(
      rawPayload,
      makeWalletBody(),
      extensionAddress,
      { amount: refillAmount.toString(), payloadHash },
    )).toBe(refillAmount);
  });

  it('rejects a refill marker when the final action uses another send mode', () => {
    const { rawPayload, payloadHash } = makePayload();

    expect(getTrustedMfaRefillAmount(
      rawPayload,
      makeWalletBody({ mode: SendMode.CARRY_ALL_REMAINING_BALANCE | SendMode.IGNORE_ERRORS }),
      extensionAddress,
      { amount: refillAmount.toString(), payloadHash },
    )).toBeUndefined();
  });

  it('rejects a refill marker when the final action targets another address', () => {
    const { rawPayload, payloadHash } = makePayload();

    expect(getTrustedMfaRefillAmount(
      rawPayload,
      makeWalletBody({ to: otherAddress }),
      extensionAddress,
      { amount: refillAmount.toString(), payloadHash },
    )).toBeUndefined();
  });
});

describe('emulatePayload MFA refill activity folding', () => {
  beforeEach(() => {
    jest.mocked(callMfaApiWithThrow).mockReset();
  });

  it('hides the outgoing negative refill transfer and folds it into the real fee', async () => {
    const { rawPayload, payloadHash, walletAddress } = makeMfaSendActionsPayload();
    const refillActivity = {
      kind: 'transaction',
      id: 'refill',
      timestamp: 0,
      isIncoming: false,
      fromAddress: walletAddress,
      toAddress: extensionAddress.toString({ urlSafe: true, bounceable: true }),
      amount: -refillAmount,
      slug: 'toncoin',
      fee: 0n,
      normalizedAddress: extensionAddress.toString({ urlSafe: true, bounceable: true }),
      status: 'completed',
    } as const;

    jest.mocked(callMfaApiWithThrow).mockResolvedValueOnce({
      activities: [refillActivity],
      realFee: 7n,
    });

    const result = await emulatePayload(
      rawPayload,
      walletAddress,
      extensionAddress,
      { amount: refillAmount.toString(), payloadHash },
    );

    expect(result).toEqual({
      activities: [{ ...refillActivity, shouldHide: true }],
      realFee: 7n + refillAmount,
    });
  });
});

import type { ApiPerpsAccountPosition, ApiPerpsFill, ApiPerpsOperation, ApiPerpsQuote } from '../../api/types';
import type { Account, PerpsAccountSnapshot, PerpsTradeState } from '../types';

import {
  buildPerpsDraft,
  findPerpsReceiptPosition,
  getIsPerpsAccountDisabled,
  getPerpsErrorCode,
  getPerpsErrorDetails,
  getPerpsFractionAmount,
  isPerpsAmountEqual,
} from './perps';

const BASE_TRADE: PerpsTradeState = {
  id: 'trade-1',
  accountId: '0-mainnet',
  step: 'form',
  assetId: 'hyperliquid:hl:BTC',
  side: 'long',
  amount: '100',
  leverage: 5,
};

const EDIT_TRADE: PerpsTradeState = {
  ...BASE_TRADE,
  kind: 'edit',
  amount: '120',
  currentAmount: '100.23',
  currentCollateral: '100.234567',
  leverage: 2,
};

describe('getIsPerpsAccountDisabled', () => {
  const byChain = { arbitrum: { address: '0x1' } };

  it.each([
    ['allows a multichain software wallet', { type: 'mnemonic', byChain }, false],
    ['refuses a wallet without an Arbitrum address', { type: 'mnemonic', byChain: {} }, true],
    ['refuses a view-only wallet', { type: 'view', byChain }, true],
    ['refuses a Ledger wallet', { type: 'hardware', byChain }, true],
    ['refuses a wallet that needs recovery', { type: 'mnemonic', byChain, isRecoveryRequired: true }, true],
  ])('%s', (_, account, expected) => {
    expect(getIsPerpsAccountDisabled(account as Account)).toBe(expected);
  });
});

describe('buildPerpsDraft', () => {
  it('sends the collateral of a new position in dollars', () => {
    expect(buildPerpsDraft({ ...BASE_TRADE, kind: 'open' })).toEqual({
      assetId: BASE_TRADE.assetId, side: 'long', leverage: 5, amount: '100',
    });
  });

  it('sends the target collateral of an edit', () => {
    expect(buildPerpsDraft(EDIT_TRADE)).toMatchObject({ amount: '120', editing: true, leverage: 2 });
  });

  it('resizes a share of the exact current collateral', () => {
    expect(buildPerpsDraft({ ...EDIT_TRADE, amount: '75.18', fraction: -25 })).toEqual({
      assetId: BASE_TRADE.assetId,
      side: 'long',
      leverage: 2,
      fraction: -25,
      amount: '100.234567',
      editing: true,
    });
  });

  it('keeps the share of a new position in every request', () => {
    expect(buildPerpsDraft({ ...BASE_TRADE, kind: 'open', amount: '25.5', fraction: 50 }))
      .toMatchObject({ amount: '25.5', fraction: 50 });
  });

  it.each([
    ['a new position', { kind: 'open' as const }],
    ['an edit', EDIT_TRADE],
  ])('pays %s from the Hyperliquid balance the user chose', (_, trade) => {
    expect(buildPerpsDraft({ ...BASE_TRADE, ...trade, fundingSource: 'balance' }))
      .toMatchObject({ funding: 'balance' });
    expect(buildPerpsDraft({ ...BASE_TRADE, ...trade, fundingSource: 'wallet' })).not.toHaveProperty('funding');
  });

  it('closes the whole position', () => {
    expect(buildPerpsDraft({ ...BASE_TRADE, kind: 'close', amount: '0' })).toMatchObject({
      amount: '0', editing: true, close: true,
    });
  });
});

describe('getPerpsErrorCode', () => {
  it.each([
    [new Error('PerpsQuoteExpired'), 'PerpsQuoteExpired'],
    [new Error('PerpsOrderRejected: insufficient margin'), 'PerpsOrderRejected'],
    [new Error('Wallet is unavailable.'), 'PerpsUnavailable'],
  ])('reads %s as %s', (error, code) => {
    expect(getPerpsErrorCode(error)).toBe(code);
  });
});

describe('getPerpsErrorDetails', () => {
  it('reads the amounts the SDK attaches to the error', () => {
    const error = Object.assign(new Error('PerpsAmountTooSmall'), { minimumAmount: '10.5', isMinimumExclusive: true });

    expect(getPerpsErrorDetails(error)).toEqual({ minimumAmount: '10.5', isMinimumExclusive: true });
    expect(getPerpsErrorDetails(Object.assign(new Error('PerpsInsufficientBalance'), {
      requiredBalance: undefined, availableBalance: '.5',
    }))).toEqual({ availableBalance: '.5' });
  });

  it('drops amounts that are not plain decimals and a flag that is not a boolean', () => {
    const error = Object.assign(new Error('PerpsAmountTooSmall'), {
      minimumAmount: '1e3',
      isMinimumExclusive: 'true',
      minimumReduction: '-1',
      requiredBalance: 3,
      availableBalance: '1.2.3',
    });

    expect(getPerpsErrorDetails(error)).toBeUndefined();
    expect(getPerpsErrorDetails(Object.assign(new Error('PerpsAmountTooSmall'), {
      minimumAmount: '10', isMinimumExclusive: 1,
    }))).toEqual({ minimumAmount: '10' });
    expect(getPerpsErrorDetails('PerpsAmountTooSmall')).toBeUndefined();
  });
});

describe('isPerpsAmountEqual', () => {
  it.each([
    ['100', '100.0', true],
    ['100.', '100', true],
    ['100.01', '100', false],
    ['', '', false],
    [undefined, '100', false],
  ])('compares %s with %s', (amount, other, expected) => {
    expect(isPerpsAmountEqual(amount, other)).toBe(expected);
  });
});

describe('getPerpsFractionAmount', () => {
  it('fills a share of the collateral the wallet can open with, in cents', () => {
    const trade: PerpsTradeState = {
      ...BASE_TRADE,
      kind: 'open',
      funding: {
        requiredUsdc: '0',
        requiredBridgeFeeUsdc: '0',
        requiredGasUsdc: '0',
        requiredEth: '0',
        requiredEthUsd: '0',
        usdcBalance: '0',
        availableCollateral: '51.005',
        ethBalance: '0',
        needsUsdc: false,
        needsEth: false,
      },
    };

    expect(getPerpsFractionAmount(trade, 50)).toBe('25.5');
    expect(getPerpsFractionAmount({ ...trade, funding: { ...trade.funding!, availableCollateral: '12.345678' } }, 100))
      .toBe('12.34');
  });

  it('changes the current collateral by the percentage', () => {
    expect(getPerpsFractionAmount(EDIT_TRADE, -25)).toBe('75.17');
    expect(getPerpsFractionAmount(EDIT_TRADE, 5)).toBe('105.24');
  });

  it('waits for the collateral a new position can take', () => {
    expect(getPerpsFractionAmount({ ...BASE_TRADE, kind: 'open' }, 25)).toBeUndefined();
  });
});

describe('findPerpsReceiptPosition', () => {
  const operation = {
    id: 'op-1', accountId: '0-mainnet', assetId: BASE_TRADE.assetId, kind: 'open', state: 'completed', createdAt: 1,
  } as ApiPerpsOperation;
  const quote = { side: 'long', leverage: 5 } as ApiPerpsQuote;
  const position = {
    assetId: BASE_TRADE.assetId, dex: '', side: 'long', size: '0.2', raw: { leverage: { value: 5 } },
  } as ApiPerpsAccountPosition;
  const snapshot = { positions: [position], unavailableDexs: [], timestamp: 2 } as unknown as PerpsAccountSnapshot;

  it.each([
    ['the size after the fill in another notation', '0.20', position],
    ['another size', '0.21', undefined],
  ])('compares the position with %s', (_, positionSize, expected) => {
    const fill = { positionSize } as ApiPerpsFill;

    expect(findPerpsReceiptPosition(operation, quote, snapshot, fill)).toBe(expected);
  });
});

import './initial';

import type { GlobalState } from '../../types';

import { BASE, BASE_USDC_MAINNET } from '../../../config';
import { addActionHandler } from '../../index';

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
  getActions: jest.fn(() => ({})),
}));

jest.mock('../../../util/notificationSound', () => ({
  initializeSounds: jest.fn(),
}));

type ActionHandler = (global: GlobalState, actions: AnyLiteral, payload: AnyLiteral) => void;

const ACCOUNT_ID = '0-mainnet';

function getHandler(name: string): ActionHandler {
  const call = (addActionHandler as jest.Mock).mock.calls.find(([actionName]) => actionName === name);
  return call![1] as ActionHandler;
}

describe('selectToken', () => {
  it('sends the selected token and leaves the swap as is', () => {
    const actions = {
      changeTransferToken: jest.fn(),
      setDefaultSwapParams: jest.fn(),
    };
    const global = {
      currentAccountId: ACCOUNT_ID,
      accounts: { byId: { [ACCOUNT_ID]: {} } },
      byAccountId: { [ACCOUNT_ID]: {} },
      currentSwap: {},
    };

    getHandler('selectToken')(global as unknown as GlobalState, actions, { slug: BASE_USDC_MAINNET.slug });

    expect(actions.changeTransferToken).toHaveBeenCalledWith({ tokenSlug: BASE_USDC_MAINNET.slug });
    expect(actions.setDefaultSwapParams).not.toHaveBeenCalled();
  });

  it('selects a token of an account whose state is not created yet', () => {
    const actions = {
      changeTransferToken: jest.fn(),
      setDefaultSwapParams: jest.fn(),
    };
    const global = {
      currentAccountId: ACCOUNT_ID,
      accounts: { byId: { [ACCOUNT_ID]: {} } },
      byAccountId: {},
      currentSwap: {},
    };

    getHandler('selectToken')(global as unknown as GlobalState, actions, { slug: BASE_USDC_MAINNET.slug });

    expect(actions.changeTransferToken).toHaveBeenCalledWith({ tokenSlug: BASE_USDC_MAINNET.slug });
  });

  it.each([
    ['closing', {}],
    ['switching to another token', { slug: BASE.slug }],
  ])('resets a swap that carries the token of the screen it is %s', (_, payload) => {
    const actions = {
      changeTransferToken: jest.fn(),
      setDefaultSwapParams: jest.fn(),
    };
    const global = {
      currentAccountId: ACCOUNT_ID,
      accounts: { byId: { [ACCOUNT_ID]: {} } },
      byAccountId: { [ACCOUNT_ID]: { currentTokenSlug: BASE_USDC_MAINNET.slug } },
      currentSwap: { tokenInSlug: BASE.slug, tokenOutSlug: BASE_USDC_MAINNET.slug },
      currentTransfer: {},
    };

    getHandler('selectToken')(global as unknown as GlobalState, actions, payload);

    expect(actions.setDefaultSwapParams).toHaveBeenCalledWith({ withResetAmount: true });
  });
});

describe('selectToken with a market token', () => {
  function selectToken(isMarketOpen?: boolean) {
    const global = {
      currentAccountId: ACCOUNT_ID,
      accounts: { byId: { [ACCOUNT_ID]: {} } },
      byAccountId: { [ACCOUNT_ID]: { currentTokenSlug: BASE.slug } },
      currentSwap: {},
      currentTransfer: {},
      isMarketOpen,
      marketTokenSlug: BASE.slug,
    };
    const handler = getHandler('selectToken') as unknown as (...args: Parameters<ActionHandler>) => GlobalState;

    return handler(global as unknown as GlobalState, { changeTransferToken: jest.fn() }, {
      slug: BASE_USDC_MAINNET.slug,
    }).marketTokenSlug;
  }

  it('follows a switch to another token in the open market', () => {
    expect(selectToken(true)).toBe(BASE_USDC_MAINNET.slug);
  });

  it('gives a token selected after the market closes to the wallet', () => {
    expect(selectToken()).toBeUndefined();
  });
});

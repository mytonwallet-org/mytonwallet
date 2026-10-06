import './initial';

import type { GlobalState } from '../../types';

import { BASE_USDC_MAINNET } from '../../../config';
import { addActionHandler } from '../../index';
import { selectSwapTokens } from '../../selectors';

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
  getActions: jest.fn(() => ({})),
}));

jest.mock('../../../util/notificationSound', () => ({
  initializeSounds: jest.fn(),
}));

jest.mock('../../selectors', () => ({
  ...jest.requireActual('../../selectors'),
  selectSwapTokens: jest.fn(),
}));

type ActionHandler = (global: GlobalState, actions: AnyLiteral, payload: AnyLiteral) => void;

const ACCOUNT_ID = '0-mainnet';

function getHandler(name: string): ActionHandler {
  const call = (addActionHandler as jest.Mock).mock.calls.find(([actionName]) => actionName === name);
  return call![1] as ActionHandler;
}

describe('selectToken', () => {
  it('sends the selected token even when swap does not offer it', () => {
    (selectSwapTokens as jest.Mock).mockReturnValue([]);

    const actions = {
      changeTransferToken: jest.fn(),
      setDefaultSwapParams: jest.fn(),
    };
    const global = {
      currentAccountId: ACCOUNT_ID,
      accounts: { byId: { [ACCOUNT_ID]: {} } },
      byAccountId: { [ACCOUNT_ID]: {} },
    };

    getHandler('selectToken')(global as unknown as GlobalState, actions, { slug: BASE_USDC_MAINNET.slug });

    expect(actions.changeTransferToken).toHaveBeenCalledWith({ tokenSlug: BASE_USDC_MAINNET.slug });
    expect(actions.setDefaultSwapParams).not.toHaveBeenCalled();
  });
});

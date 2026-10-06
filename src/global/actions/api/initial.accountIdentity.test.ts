import './initial';

import type { GlobalState } from '../../types';

import { callApi, initApi } from '../../../api';
import { addActionHandler, getGlobal, setGlobal } from '../../index';

jest.mock('../../../api', () => ({ callApi: jest.fn(), initApi: jest.fn() }));
jest.mock('../../../util/installAttribution', () => ({ captureBrowserAttribution: jest.fn(() => ({})) }));
jest.mock('../../helpers/auth', () => ({ removeTemporaryAccount: jest.fn() }));
jest.mock('../../index', () => ({
  addActionHandler: jest.fn(), getGlobal: jest.fn(), setGlobal: jest.fn(),
}));

type Handler = (global: GlobalState, actions: AnyLiteral) => unknown;

const ACCOUNT_ID = '0-mainnet';
const EVM_ADDRESS = '0x1111111111111111111111111111111111111111';

beforeEach(() => {
  jest.mocked(callApi).mockReset().mockResolvedValue(undefined);
  jest.mocked(initApi).mockReset();
  jest.mocked(setGlobal).mockReset();
});

it('serializes every populated UI chain into the initialization identity', async () => {
  const global = {
    auth: {},
    currentAccountId: ACCOUNT_ID,
    accounts: {
      byId: {
        [ACCOUNT_ID]: {
          type: 'view',
          byChain: {
            ethereum: { address: EVM_ADDRESS },
            base: { address: EVM_ADDRESS },
          },
        },
      },
    },
    byAccountId: { [ACCOUNT_ID]: {} },
    isDerivationsSynced: true,
    settings: { langCode: 'en', isTestnet: false, byAccountId: {} },
  } as unknown as GlobalState;
  jest.mocked(getGlobal).mockReturnValue(global);
  const handler = jest.mocked(addActionHandler).mock.calls
    .find(([action]) => action === 'initApi')![1] as Handler;

  await handler(global, { apiUpdate: jest.fn() });
  const readInitialization = jest.mocked(initApi).mock.calls[0][2]!;

  expect(readInitialization()).toEqual({
    current: {
      accountId: ACCOUNT_ID,
      type: 'view',
      addressByChain: { ethereum: EVM_ADDRESS, base: EVM_ADDRESS },
      newestActivityTimestamps: {},
    },
    isLegacyCoreMigrationCompleted: undefined,
  });
});

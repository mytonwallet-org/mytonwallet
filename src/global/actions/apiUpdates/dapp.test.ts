import './dapp';

import type { ApiUpdateProcessDeeplink } from '../../../api/types/updates';

import { processDeeplink } from '../../../util/deeplink';
import { addActionHandler } from '../../index';

jest.mock('../../../util/deeplink', () => ({
  processDeeplink: jest.fn(),
}));

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  setGlobal: jest.fn(),
}));

jest.mock('../../reducers', () => {
  function returnGlobal(global: unknown) {
    return global;
  }

  return {
    clearCurrentDappTransfer: jest.fn(returnGlobal),
    clearCurrentSignature: jest.fn(returnGlobal),
    clearCurrentTransfer: jest.fn(returnGlobal),
    clearDappConnectRequest: jest.fn(returnGlobal),
    updateCurrentDappSignData: jest.fn(returnGlobal),
    updateCurrentDappTransfer: jest.fn(returnGlobal),
    updateCurrentSignature: jest.fn(returnGlobal),
    updateCurrentTransfer: jest.fn(returnGlobal),
    updateCurrentTransferByCheckResult: jest.fn(returnGlobal),
  };
});

type ApiUpdateHandler = (
  global: AnyLiteral,
  actions: AnyLiteral,
  update: ApiUpdateProcessDeeplink,
) => void;

function getApiUpdateHandler() {
  const call = (addActionHandler as jest.Mock).mock.calls.find(([name]) => name === 'apiUpdate');
  return call![1] as ApiUpdateHandler;
}

describe('dapp api updates', () => {
  beforeEach(() => {
    (processDeeplink as jest.Mock).mockClear();
  });

  it('should preserve page deeplink source when processing popup updates', () => {
    const handler = getApiUpdateHandler();
    const url = 'mtw://offramp?depositWalletAddress=UQAddress&baseCurrencyCode=ton';
    const update: ApiUpdateProcessDeeplink = {
      type: 'processDeeplink',
      url,
      isFromInAppBrowser: true,
    };

    handler({} as AnyLiteral, {} as AnyLiteral, update);

    expect(processDeeplink).toHaveBeenCalledWith(url, true);
  });
});

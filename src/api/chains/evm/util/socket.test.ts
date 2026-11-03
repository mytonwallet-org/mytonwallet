import type { InMessageCallback, WalletWatcher } from '../../../common/websocket/abstractWsClient';
import type { AlchemySocketClientMessage, AlchemySocketServerMessage } from '../types';

import { getErc20Balance, getWalletBalance } from '../wallet';
import { getAlchemySocket } from './socket';

const mockSocket = {
  isConnected: true,
  send: jest.fn<void, [AlchemySocketClientMessage]>(),
  close: jest.fn(),
  onMessage: jest.fn<void, [InMessageCallback<AlchemySocketServerMessage>]>(),
  onConnect: jest.fn(),
  onDisconnect: jest.fn(),
};

jest.mock('../../../../util/reconnectingWebsocket', () => ({
  __esModule: true,
  default: jest.fn(() => mockSocket),
}));

jest.mock('../wallet', () => ({
  getErc20Balance: jest.fn(),
  getWalletBalance: jest.fn(),
}));

const ADDRESS = '0x5819e5Ff34198F315322e1863Be6C3dC927cC5C3';
const TOKEN_ADDRESS = '0xAbC';
const BALANCE = 2000000000000000n;

async function connectWatcher() {
  const onBalanceUpdate = jest.fn();
  const watcher = getAlchemySocket('mainnet', 'ethereum').watchWallets(
    [{ address: ADDRESS, chain: 'ethereum' }],
    { onBalanceUpdate },
  );
  await jest.advanceTimersByTimeAsync(1000);

  const receive = mockSocket.onMessage.mock.calls[0][0];
  const subscriptions = mockSocket.send.mock.calls.map(([message]) => message);
  subscriptions.forEach((message) => receive({ jsonrpc: '2.0', id: message.id, result: message.id }));

  async function receiveBalanceNotification(type: 'native' | 'erc20', blockNumber?: string) {
    const subscription = subscriptions.find((message) => message.method === 'eth_subscribe'
      && message.params[0] === (type === 'native' ? 'alchemy_minedTransactions' : 'logs'))!;

    await receive({
      jsonrpc: '2.0',
      method: 'eth_subscription',
      params: {
        subscription: subscription.id,
        result: type === 'native' ? {
          transaction: {
            accessList: [],
            blockHash: '0xblock',
            blockNumber: blockNumber ?? '',
            chainId: '0x1',
            from: ADDRESS,
            gas: '0x1',
            gasPrice: '0x1',
            hash: '0xtransaction',
            input: '0x',
            maxFeePerGas: '0x1',
            maxPriorityFeePerGas: '0x1',
            nonce: '0x1',
            r: '0x1',
          },
        } : { address: TOKEN_ADDRESS, topics: ['transfer', 'from', 'to'], blockNumber },
      },
    });
    await jest.advanceTimersByTimeAsync(0);
  }

  return { watcher, onBalanceUpdate, receiveBalanceNotification };
}

describe('AlchemySocket balance updates', () => {
  let watcher: WalletWatcher;

  beforeEach(() => {
    jest.useFakeTimers();
    jest.clearAllMocks();
    jest.mocked(getWalletBalance).mockResolvedValue(BALANCE);
    jest.mocked(getErc20Balance).mockResolvedValue(BALANCE);
  });

  afterEach(async () => {
    watcher?.destroy();
    await jest.runAllTimersAsync();
    jest.useRealTimers();
  });

  it.each([
    ['native', '0x69', 105],
    ['erc20', '0x6a', 106],
    ['erc20', undefined, undefined],
    ['native', '0x69invalid', undefined],
  ] as const)('passes the block for %s notification %s', async (type, blockNumber, expectedBlock) => {
    const connection = await connectWatcher();
    watcher = connection.watcher;
    const { onBalanceUpdate, receiveBalanceNotification } = connection;

    await receiveBalanceNotification(type, blockNumber);

    expect(onBalanceUpdate).toHaveBeenCalledWith({
      address: ADDRESS,
      tokenAddress: type === 'native' ? undefined : TOKEN_ADDRESS.toLowerCase(),
      balance: BALANCE,
      blockNumber: expectedBlock,
      finality: 'confirmed',
    });
    if (type === 'native') {
      expect(getWalletBalance).toHaveBeenCalledWith('ethereum', 'mainnet', ADDRESS.toLowerCase(), expectedBlock);
    } else {
      expect(getErc20Balance).toHaveBeenCalledWith(
        'mainnet', 'ethereum', ADDRESS.toLowerCase(), TOKEN_ADDRESS.toLowerCase(), expectedBlock,
      );
    }
  });

  it.each([
    ['native', 'UNKNOWN_ERROR'],
    ['erc20', 'CALL_EXCEPTION'],
  ] as const)('retries a failed pinned %s balance at latest without a block stamp', async (type, code) => {
    const connection = await connectWatcher();
    watcher = connection.watcher;
    const { onBalanceUpdate, receiveBalanceNotification } = connection;
    const getBalance = jest.mocked(type === 'native' ? getWalletBalance : getErc20Balance);
    const latestBalance = BALANCE + 1n;
    getBalance.mockRejectedValueOnce(Object.assign(new Error('Pinned balance unavailable'), { code }))
      .mockResolvedValue(latestBalance);

    await receiveBalanceNotification(type, '0x69');

    expect(getBalance).toHaveBeenCalledTimes(2);
    const expectedArgs = type === 'native'
      ? ['ethereum', 'mainnet', ADDRESS.toLowerCase()]
      : ['mainnet', 'ethereum', ADDRESS.toLowerCase(), TOKEN_ADDRESS.toLowerCase()];
    expect(getBalance).toHaveBeenNthCalledWith(1, ...expectedArgs, 105);
    expect(getBalance).toHaveBeenNthCalledWith(2, ...expectedArgs, undefined);
    expect(onBalanceUpdate).toHaveBeenCalledTimes(1);
    expect(onBalanceUpdate).toHaveBeenLastCalledWith({
      address: ADDRESS,
      tokenAddress: type === 'native' ? undefined : TOKEN_ADDRESS.toLowerCase(),
      balance: latestBalance,
      blockNumber: undefined,
      finality: 'confirmed',
    });

    await receiveBalanceNotification(type);

    expect(getBalance).toHaveBeenCalledTimes(3);
    expect(getBalance).toHaveBeenLastCalledWith(...expectedArgs, undefined);
    expect(onBalanceUpdate).toHaveBeenCalledTimes(2);
    expect(onBalanceUpdate).toHaveBeenLastCalledWith({
      address: ADDRESS,
      tokenAddress: type === 'native' ? undefined : TOKEN_ADDRESS.toLowerCase(),
      balance: latestBalance,
      blockNumber: undefined,
      finality: 'confirmed',
    });
  });
});

import type { ApiPerpsBuildPositionRequest, ApiPerpsExecutePositionResult, ApiUpdate, OnApiUpdate } from '../types';

import { perpsWithdrawalFixture } from '../../../tests/helpers/perpsWithdrawal';
import { fetchPrivateKeyString } from '../chains/evm/auth';
import {
  buildPerpsCctpDepositTransferWithPrivateKey,
  signHyperliquidExchangeBuild,
  signHyperliquidExchangePayload,
  signHyperliquidWithdrawPermit,
  submitPerpsCctpDepositTransfer,
} from '../chains/evm/perps';
import { fetchStoredChainAccount } from '../common/accounts';
import { callBackendPost } from '../common/backend';
import {
  executePerpsClosePosition,
  executePerpsDepositMargin,
  executePerpsModifyPosition,
  executePerpsOpenFromBalance,
  executePerpsOpenPosition,
  executePerpsWithdrawMargin,
  initPerps,
  perpsBuildWithdrawal,
  perpsEstimatePosition,
  perpsGetActivities,
  perpsGetAsset,
  perpsGetAssetChart,
  perpsWithdrawReleasedMargin,
} from './perps';

jest.mock('../chains/evm/util/account', () => ({
  fetchEvmWallet: jest.fn().mockResolvedValue({ address: '0x123' }),
}));
jest.mock('../chains/evm/auth', () => ({ fetchPrivateKeyString: jest.fn() }));
jest.mock('../common/accounts', () => ({ fetchStoredChainAccount: jest.fn() }));
jest.mock('../common/backend', () => ({ callBackendGet: jest.fn(), callBackendPost: jest.fn() }));
jest.mock('../chains/evm/perps', () => ({
  buildPerpsCctpDepositTransferWithPrivateKey: jest.fn(),
  signHyperliquidExchangeBuild: jest.fn().mockResolvedValue({ r: '0x1', s: '0x2', v: 27 }),
  signHyperliquidExchangePayload: jest.fn().mockResolvedValue({}),
  signHyperliquidWithdrawPermit: jest.fn().mockResolvedValue({ r: '0x1', s: '0x2', v: 27 }),
  submitPerpsCctpDepositTransfer: jest.fn(),
}));

const request: ApiPerpsBuildPositionRequest = {
  chain: 'hyperliquid', address: '0x123', asset: 'hyperliquid:hl:BTC',
  side: 'long', depositAmount: '50.2', leverage: 10, isCross: false,
};
const resize = { chain: request.chain, address: request.address, asset: request.asset, depositAmount: '50.2' };

test('activity reads use the configured backend and preserve time bounds', async () => {
  const request = { addressByChain: { hyperliquid: '0x123' }, startTime: 1000, endTime: 2000 };
  const response = { activitiesByChain: { hyperliquid: { address: '0x123', activities: [] } } };
  jest.mocked(callBackendPost).mockResolvedValueOnce(response);
  expect(await perpsGetActivities(request)).toBe(response);
  expect(callBackendPost).toHaveBeenCalledWith('/perps/activities', request);
});
const build = {
  address: request.address,
  action: { type: 'order', orders: [], grouping: 'na' },
  hash: '0xbuild', nonce: 1, typedData: {},
  deposit: { amountUsdc: '50.2', creditedAmountUsdc: '50' },
  updateLeverage: {},
};
const trade: ApiPerpsExecutePositionResult = {
  address: request.address, status: 'filled', oid: 7, filledSize: '0.005', avgPrice: '100000', rawResponse: {},
};
let onUpdate: jest.MockedFunction<OnApiUpdate>;

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason: Error) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

beforeEach(() => {
  jest.clearAllMocks();
  onUpdate = jest.fn();
  initPerps(onUpdate);
  jest.mocked(fetchStoredChainAccount).mockResolvedValue({ type: 'mnemonic' } as any);
  jest.mocked(fetchPrivateKeyString).mockResolvedValue('private-key');
  jest.mocked(buildPerpsCctpDepositTransferWithPrivateKey).mockResolvedValue({ chain: 'arbitrum', calls: [] });
  jest.mocked(submitPerpsCctpDepositTransfer).mockResolvedValue({ txHash: '0xdeposit' });
});

test.each([
  ['open', () => executePerpsOpenPosition('1-mainnet', 'token', request, {})],
  ['modify', () => executePerpsModifyPosition('1-mainnet', 'token', resize, {})],
  ['close', () => executePerpsClosePosition('1-mainnet', 'token', request, {})],
] as const)('%s rejects a backend build for another wallet before signing or submitting', async (_, execute) => {
  jest.mocked(callBackendPost).mockResolvedValue({ ...build, address: '0x456' });
  await expect(execute()).rejects.toThrow('PerpsReviewChanged');
  expect(signHyperliquidExchangeBuild).not.toHaveBeenCalled();
  expect(submitPerpsCctpDepositTransfer).not.toHaveBeenCalled();
  expect(callBackendPost).toHaveBeenCalledTimes(1);
});

test('partial reduction forwards the same gross withdrawal amount through build and execute', async () => {
  const reduceBuild = { ...build, deposit: undefined, updateLeverage: undefined };
  jest.mocked(callBackendPost).mockImplementation((url) => url.endsWith('/build')
    ? Promise.resolve(reduceBuild) : Promise.resolve({ phase: 'withdraw_unavailable', close: trade }));
  await executePerpsModifyPosition('1-mainnet', 'token', {
    chain: 'hyperliquid', address: request.address, asset: request.asset, depositAmount: '5', reduceOnly: true,
  }, {});
  expect(callBackendPost).toHaveBeenNthCalledWith(1, '/perps/position/modify/build', expect.objectContaining({
    depositAmount: '5', reduceOnly: true,
  }), expect.anything());
  expect(callBackendPost).toHaveBeenNthCalledWith(2, '/perps/position/close/execute', expect.objectContaining({
    depositAmount: '5', skipPositionFlatWait: true, destination: request.address,
  }), expect.anything());
});

test('reviewed full close uses close/build and still waits for a flat position', async () => {
  const closeBuild = { ...build, deposit: undefined, updateLeverage: undefined,
    action: { type: 'order', grouping: 'na',
      orders: [{ a: 0, b: false, p: '99500', s: '0.005', r: true, t: { limit: { tif: 'Ioc' } } }],
    } };
  jest.mocked(callBackendPost).mockImplementation((url) => url.endsWith('/build')
    ? Promise.resolve(closeBuild) : Promise.resolve({ phase: 'withdraw_unavailable', close: trade }));
  const validateBuild = jest.fn();
  const result = await executePerpsClosePosition('1-mainnet', 'token', {
    chain: 'hyperliquid', address: request.address, asset: request.asset, slippage: 0.002,
  }, { validateBuild });
  expect(result).toMatchObject({ phase: 'withdraw_unavailable', close: trade });
  expect(validateBuild).toHaveBeenCalledWith(closeBuild);
  expect(callBackendPost).toHaveBeenNthCalledWith(1, '/perps/position/close/build', {
    chain: 'hyperliquid', address: request.address, asset: request.asset,
    slippage: 0.002,
  }, expect.anything());
  const execution = jest.mocked(callBackendPost).mock.calls[1];
  expect(execution[0]).toBe('/perps/position/close/execute');
  expect(execution[1]).not.toHaveProperty('skipPositionFlatWait');
  expect(execution[1]).toMatchObject({ action: closeBuild.action });
});

test('leverage decrease estimates, builds, and starts execute before the deposit', async () => {
  const execution = deferred<ApiPerpsExecutePositionResult>();
  const order: string[] = [];
  const leverageBuild = {
    address: request.address,
    deposit: { amountUsdc: '20.2', creditedAmountUsdc: '20' },
    updateLeverage: { action: { type: 'updateLeverage' }, nonce: 2, hash: '0xlev', typedData: {} },
    updateIsolatedMargin: { action: { type: 'updateIsolatedMargin' }, nonce: 3, hash: '0xmargin', typedData: {} },
  };
  jest.mocked(callBackendPost).mockImplementation((url) => {
    order.push(url);
    if (url.endsWith('/modify/estimate')) return Promise.resolve({ depositAmount: '20.2' });
    if (url.endsWith('/build')) return Promise.resolve(leverageBuild);
    return execution.promise;
  });
  jest.mocked(submitPerpsCctpDepositTransfer).mockImplementation(() => {
    order.push('deposit');
    return Promise.resolve({ txHash: '0xdeposit' });
  });

  const deposited = deferred<string>();
  const pending = executePerpsModifyPosition('1-mainnet', 'token', {
    chain: 'hyperliquid', address: request.address, asset: request.asset, leverage: 5, depositAmount: '20.2',
  }, { onDeposit: deposited.resolve });

  expect(await deposited.promise).toBe('0xdeposit');
  expect(order).toEqual([
    '/perps/position/modify/estimate',
    '/perps/position/modify/build',
    '/perps/position/execute',
    'deposit',
  ]);
  expect(callBackendPost).toHaveBeenCalledWith(
    '/perps/position/modify/build',
    expect.objectContaining({ leverage: 5, depositAmount: '20.2' }),
    expect.anything(),
  );
  expect(callBackendPost).toHaveBeenCalledWith(
    '/perps/position/execute',
    expect.objectContaining({ depositAmount: '20.2', updateLeverage: {}, updateIsolatedMargin: {} }),
    expect.anything(),
  );
  execution.resolve({ ...trade, status: 'ok' });
  expect(await pending).toEqual({ ...trade, status: 'ok', depositTxHash: '0xdeposit' });
});

test('a leverage deposit that no longer matches the estimate is not built', async () => {
  jest.mocked(callBackendPost).mockResolvedValue({ depositAmount: '30' });
  const result = await executePerpsModifyPosition('1-mainnet', 'token', {
    chain: 'hyperliquid', address: request.address, asset: request.asset, leverage: 5, depositAmount: '20.2',
  }, {});
  expect(result).toEqual({ error: 'PerpsQuoteExpired' });
  expect(callBackendPost).toHaveBeenCalledTimes(1);
  expect(submitPerpsCctpDepositTransfer).not.toHaveBeenCalled();
});

test.each(['open', 'modify'] as const)('reviewed %s waits for execution', async (flow) => {
  const execution = deferred<ApiPerpsExecutePositionResult>();
  const deposited = deferred<string>();
  const onTrade = jest.fn();
  jest.mocked(callBackendPost).mockImplementation((url) =>
    url.endsWith('/build') ? Promise.resolve(build) : execution.promise);
  const hooks = { onDeposit: deposited.resolve, onTrade };
  let finished = false;
  const pending = (flow === 'open'
    ? executePerpsOpenPosition('1-mainnet', 'token', request, hooks)
    : executePerpsModifyPosition('1-mainnet', 'token', resize, hooks))
    .then((result) => {
      finished = true;
      return result;
    });
  await deposited.promise;
  expect(finished).toBe(false);
  execution.resolve(trade);
  expect(await pending).toEqual({ ...trade, depositTxHash: '0xdeposit' });
  expect(onTrade).toHaveBeenCalledWith(trade);
  expect(onUpdate).not.toHaveBeenCalled();
});

test('execution failure after a deposit reaches the reviewed caller', async () => {
  const execution = deferred<ApiPerpsExecutePositionResult>();
  const deposited = deferred<string>();
  jest.mocked(callBackendPost).mockImplementation((url) =>
    url.endsWith('/build') ? Promise.resolve(build) : execution.promise);
  const pending = executePerpsOpenPosition('1-mainnet', 'token', request, { onDeposit: deposited.resolve });
  await deposited.promise;
  execution.reject(new Error('timeout'));
  await expect(pending).rejects.toThrow('timeout');
  expect(onUpdate).not.toHaveBeenCalled();
});

test('a changed backend build is rejected before signing or submitting funds', async () => {
  jest.mocked(callBackendPost).mockResolvedValue(build);
  await expect(executePerpsOpenPosition('1-mainnet', 'token', request, {
    validateBuild: () => { throw new Error('PerpsReviewChanged'); },
  })).rejects.toThrow('PerpsReviewChanged');
  expect(signHyperliquidExchangeBuild).not.toHaveBeenCalled();
  expect(submitPerpsCctpDepositTransfer).not.toHaveBeenCalled();
});

test('reduce retains its fill and partial withdrawal state for reviewed callers', async () => {
  jest.mocked(callBackendPost).mockImplementation((url) => url.endsWith('/build')
    ? Promise.resolve(build) : Promise.resolve({ phase: 'withdraw_unavailable', close: trade }));
  const result = await executePerpsModifyPosition('1-mainnet', 'token', { ...request, reduceOnly: true }, {});
  expect(result).toEqual({ ...trade, withdrawalPhase: 'withdraw_unavailable' });
  expect(submitPerpsCctpDepositTransfer).not.toHaveBeenCalled();
  expect(signHyperliquidWithdrawPermit).not.toHaveBeenCalled();
});

test.each(['reduce', 'close'] as const)('%s preserves the rejection without starting withdrawal', async (kind) => {
  const rejected = { ...trade, oid: undefined, filledSize: undefined, avgPrice: undefined,
    status: 'error: Order must have minimum value of $10. asset=0' };
  jest.mocked(callBackendPost).mockImplementation((url) => url.endsWith('/build')
    ? Promise.resolve(build) : Promise.resolve({ phase: 'withdraw_unavailable', close: rejected }));
  const onTrade = jest.fn();
  const result = kind === 'reduce'
    ? await executePerpsModifyPosition('1-mainnet', 'token', { ...request, reduceOnly: true }, { onTrade })
    : await executePerpsClosePosition('1-mainnet', 'token', {
      chain: request.chain, address: request.address, asset: request.asset,
    }, { onTrade });
  expect(result).toEqual({ error: rejected.status });
  expect(onTrade).toHaveBeenCalledWith(rejected);
  expect(signHyperliquidWithdrawPermit).not.toHaveBeenCalled();
  expect(submitPerpsCctpDepositTransfer).not.toHaveBeenCalled();
});

test('a resting close order cannot be treated as a completed trade or trigger withdrawal', async () => {
  jest.mocked(callBackendPost).mockImplementation((url) => url.endsWith('/build')
    ? Promise.resolve(build) : Promise.resolve({
      phase: 'awaiting_withdraw_signature', close: { ...trade, status: 'resting' },
      withdraw: perpsWithdrawalFixture(request.address, '50'),
    }));
  expect(await executePerpsClosePosition('1-mainnet', 'token', {
    chain: request.chain, address: request.address, asset: request.asset,
  }, {})).toHaveProperty('error');
  expect(signHyperliquidWithdrawPermit).not.toHaveBeenCalled();
});

test('recovery signs only a withdrawal to the wallet and never places another order', async () => {
  const completed = { address: request.address, phase: 'completed', withdrawResult: { ...trade, status: 'ok' } };
  jest.mocked(callBackendPost).mockResolvedValue(completed);
  const withdraw = perpsWithdrawalFixture(request.address, '50');
  expect(await perpsWithdrawReleasedMargin('1-mainnet', 'token', withdraw)).toEqual(completed);
  expect(signHyperliquidWithdrawPermit).toHaveBeenCalledWith('mainnet', 'private-key',
    expect.objectContaining({ amountUsdc: '50', destination: request.address }), request.address);
  expect(callBackendPost).toHaveBeenCalledTimes(1);
  expect(callBackendPost).toHaveBeenCalledWith('/perps/position/close/execute', expect.objectContaining({
    action: expect.objectContaining({
      type: 'sendToEvmWithData', amount: '50', sourceDex: 'spot', destinationRecipient: request.address,
    }),
  }), expect.anything());
  expect(signHyperliquidExchangeBuild).not.toHaveBeenCalled();
  expect(submitPerpsCctpDepositTransfer).not.toHaveBeenCalled();
});

test('withdrawal submission starts only after authentication and signing succeed', async () => {
  const onSubmitting = jest.fn();
  const withdraw = perpsWithdrawalFixture(request.address, '50');
  jest.mocked(fetchPrivateKeyString).mockResolvedValueOnce(undefined);
  await expect(perpsWithdrawReleasedMargin('1-mainnet', 'invalid', withdraw, onSubmitting))
    .rejects.toThrow('InvalidPassword');
  expect(onSubmitting).not.toHaveBeenCalled();
  expect(callBackendPost).not.toHaveBeenCalled();

  jest.mocked(signHyperliquidWithdrawPermit).mockRejectedValueOnce(new Error('invalid permit'));
  await expect(perpsWithdrawReleasedMargin('1-mainnet', 'token', withdraw, onSubmitting))
    .rejects.toThrow('invalid permit');
  expect(onSubmitting).not.toHaveBeenCalled();
  expect(callBackendPost).not.toHaveBeenCalled();

  jest.mocked(callBackendPost).mockImplementationOnce(() => {
    expect(onSubmitting).toHaveBeenCalledTimes(1);
    return Promise.reject(new Error('network timeout'));
  });
  await expect(perpsWithdrawReleasedMargin('1-mainnet', 'token', withdraw, onSubmitting))
    .rejects.toThrow('network timeout');
  expect(onSubmitting).toHaveBeenCalledTimes(1);
});

test('perps asset page reads detail and chart from the backend', async () => {
  jest.mocked(callBackendPost).mockClear();
  jest.mocked(callBackendPost)
    .mockResolvedValueOnce({ address: '0x123', asset: { id: 'hyperliquid:hl:BTC' }, activities: [] })
    .mockResolvedValueOnce([[1_700_000_000, 100]]);

  await perpsGetAsset({
    address: '0x123',
    asset: 'hyperliquid:hl:BTC',
    chain: 'hyperliquid',
  });
  await perpsGetAssetChart({ asset: 'hyperliquid:hl:BTC', period: '1D', chain: 'hyperliquid' });

  expect(callBackendPost).toHaveBeenNthCalledWith(
    1,
    '/perps/asset',
    { address: '0x123', asset: 'hyperliquid:hl:BTC', chain: 'hyperliquid' },
  );
  expect(callBackendPost).toHaveBeenNthCalledWith(
    2,
    '/perps/asset/chart',
    { asset: 'hyperliquid:hl:BTC', period: '1D', chain: 'hyperliquid' },
  );
});

test('position estimates preserve backend figures', async () => {
  const estimate = { orderValue: '19.8', marginRequired: '9.9', size: '0.0002', liquidationPrice: '50250' };
  const estimateRequest = {
    chain: 'hyperliquid' as const, address: request.address, asset: request.asset,
    depositAmount: '10.2', side: 'long' as const, leverage: 2, isCross: false,
  };
  jest.mocked(callBackendPost).mockResolvedValueOnce(estimate);

  expect(await perpsEstimatePosition(estimateRequest)).toBe(estimate);
  expect(callBackendPost).toHaveBeenCalledWith('/perps/position/estimate', estimateRequest, {
    isAllowBadRequest: true,
  });
});

test.each([
  [{ errors: [{ msg: 'Deposit is below the minimum' }, { msg: 'Invalid size' }] },
    'Deposit is below the minimum, Invalid size'],
  [{ error: 'Position is no longer open' }, 'Position is no longer open'],
  [{ errors: [] }, 'Estimate failed.'],
  [{ error: '' }, 'Estimate failed.'],
])('position estimates return backend validation errors: %j', async (response, error) => {
  jest.mocked(callBackendPost).mockResolvedValueOnce(response);
  expect(await perpsEstimatePosition({
    chain: request.chain, address: request.address, asset: request.asset,
  })).toEqual({ error });
});

test('withdrawal review asks the backend for the exact reduction and never starts execution', async () => {
  const withdraw = perpsWithdrawalFixture(request.address, '5');
  const recovery = { chain: 'hyperliquid' as const, address: request.address, asset: request.asset, amountUsdc: '5' };
  jest.mocked(callBackendPost).mockResolvedValueOnce({ address: request.address, withdraw });
  expect(await perpsBuildWithdrawal(recovery)).toEqual({ address: request.address, withdraw });
  expect(callBackendPost).toHaveBeenCalledWith('/perps/position/withdraw/build', recovery);
  expect(signHyperliquidWithdrawPermit).not.toHaveBeenCalled();
  expect(signHyperliquidExchangeBuild).not.toHaveBeenCalled();
});

const balanceOrder = {
  a: 0, b: true, p: '103000', s: '0.005', r: false, t: { limit: { tif: 'Ioc' } },
};

test('a balance deposit bridges the confirmed amount without waiting on the burn', async () => {
  const execution = deferred<ApiPerpsExecutePositionResult>();
  const bridge = deferred<{ txHash: string }>();
  const deposit = { amountUsdc: '10.2', creditedAmountUsdc: '10' };
  const spotToPerp = { action: { type: 'usdClassTransfer', amount: '10' }, nonce: 4, hash: '0xspot', typedData: {} };
  jest.mocked(callBackendPost).mockImplementation((url) => url === '/perps/deposit/build'
    ? Promise.resolve({ address: request.address, deposit, spotToPerp })
    : execution.promise);
  jest.mocked(submitPerpsCctpDepositTransfer).mockImplementation(() => bridge.promise);
  const submitted = deferred<ApiUpdate>();
  onUpdate.mockImplementation((update) => {
    if (update.type === 'perpsDepositSubmitted') submitted.resolve(update);
  });
  const pending = await executePerpsDepositMargin('1-mainnet', 'token', {
    chain: 'hyperliquid', address: request.address, amount: '10.2',
  });

  expect(pending).toMatchObject({ submitted: true });
  if (!('completion' in pending)) throw new Error('expected a background deposit');
  expect(submitPerpsCctpDepositTransfer).toHaveBeenCalledWith(expect.objectContaining({ deposit }));
  expect(onUpdate).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'perpsDepositSubmitted' }));
  expect(signHyperliquidExchangeBuild).not.toHaveBeenCalled();
  expect(signHyperliquidExchangePayload).toHaveBeenCalledWith('mainnet', 'private-key', spotToPerp, {
    expectedSpotToPerpAmountUsdc: '10',
  });
  const executeCall = jest.mocked(callBackendPost).mock.calls.find((call) => call[0] === '/perps/position/execute');
  expect(executeCall?.[1]).toEqual(expect.objectContaining({
    chain: 'hyperliquid', address: request.address, depositAmount: '10.2', spotToPerp: {},
  }));
  expect(executeCall?.[1]).not.toHaveProperty('action');

  bridge.resolve({ txHash: '0xdeposit' });
  expect(await submitted.promise).toEqual({
    type: 'perpsDepositSubmitted', accountId: '1-mainnet', flow: 'deposit', depositTxHash: '0xdeposit',
  });
  let settled = false;
  const done = pending.completion.then(() => {
    settled = true;
  });
  await Promise.resolve();
  expect(settled).toBe(false);
  execution.resolve({ ...trade, status: 'ok' });
  await done;
  expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
    type: 'perpsExecuteComplete', flow: 'deposit', depositTxHash: '0xdeposit',
  }));
});

test('a balance deposit for a different amount is refused before signing or bridging', async () => {
  jest.mocked(callBackendPost).mockResolvedValue({
    address: request.address,
    deposit: { amountUsdc: '99', creditedAmountUsdc: '98.8' },
  });
  await expect(executePerpsDepositMargin('1-mainnet', 'token', {
    chain: 'hyperliquid', address: request.address, amount: '10.2',
  })).rejects.toThrow('PerpsReviewChanged');
  expect(signHyperliquidExchangePayload).not.toHaveBeenCalled();
  expect(submitPerpsCctpDepositTransfer).not.toHaveBeenCalled();
  expect(callBackendPost).toHaveBeenCalledTimes(1);
});

test('a balance withdrawal signs only sendToEvmWithData back to the wallet', async () => {
  const action = {
    type: 'sendToEvmWithData', amount: '10.2', destinationRecipient: request.address,
  };
  const withdrawBuild = { address: request.address, hash: '0xwd', nonce: 5, action, typedData: {} };
  jest.mocked(callBackendPost).mockImplementation((url) => url === '/perps/withdraw/build'
    ? Promise.resolve(withdrawBuild)
    : Promise.resolve({ ...trade, status: 'ok' }));
  expect(await executePerpsWithdrawMargin('1-mainnet', 'token', {
    chain: 'hyperliquid', address: request.address, amount: '10.2',
  })).toMatchObject({ status: 'ok' });
  expect(signHyperliquidExchangeBuild).toHaveBeenCalledWith('mainnet', 'private-key', withdrawBuild, {
    expectedWalletRecipient: request.address,
  });
  const executeCall = jest.mocked(callBackendPost).mock.calls.find((call) => call[0] === '/perps/position/execute');
  expect(executeCall?.[1]).toEqual({
    chain: 'hyperliquid',
    address: request.address,
    action,
    nonce: 5,
    signature: { r: '0x1', s: '0x2', v: 27 },
  });
  expect(submitPerpsCctpDepositTransfer).not.toHaveBeenCalled();
  expect(signHyperliquidWithdrawPermit).not.toHaveBeenCalled();
});

test('a balance withdrawal built for another recipient is refused before signing', async () => {
  jest.mocked(callBackendPost).mockResolvedValue({
    address: request.address, hash: '0xwd', nonce: 5, typedData: {},
    action: { type: 'sendToEvmWithData', amount: '10.2', destinationRecipient: '0x456' },
  });
  await expect(executePerpsWithdrawMargin('1-mainnet', 'token', {
    chain: 'hyperliquid', address: request.address, amount: '10.2',
  })).rejects.toThrow('PerpsReviewChanged');
  expect(signHyperliquidExchangeBuild).not.toHaveBeenCalled();
  expect(callBackendPost).toHaveBeenCalledTimes(1);
});

test('opening from the perps balance signs leverage and the order without a deposit', async () => {
  const openBuild = {
    address: request.address,
    action: { type: 'order', orders: [balanceOrder], grouping: 'na' },
    hash: '0xbuild', nonce: 1, typedData: {},
    marketReferencePrice: '100000',
    updateLeverage: {
      action: { type: 'updateLeverage', asset: 0, leverage: 10, isCross: false },
      nonce: 2, hash: '0xlev', typedData: {},
    },
  };
  jest.mocked(callBackendPost).mockImplementation((url) => url === '/perps/position/open'
    ? Promise.resolve(openBuild)
    : Promise.resolve(trade));
  expect(await executePerpsOpenFromBalance('1-mainnet', 'token', {
    chain: 'hyperliquid', address: request.address, asset: request.asset,
    side: 'long', amount: '50', leverage: 10, isCross: false,
  })).toEqual(trade);
  expect(callBackendPost).toHaveBeenNthCalledWith(1, '/perps/position/open', expect.objectContaining({
    asset: request.asset, side: 'long', amount: '50', leverage: 10, isCross: false, slippage: 0.03,
  }), expect.anything());
  const executeCall = jest.mocked(callBackendPost).mock.calls.find((call) => call[0] === '/perps/position/execute');
  expect(executeCall?.[1]).toEqual(expect.objectContaining({
    action: openBuild.action,
    nonce: 1,
    updateLeverage: {},
    signature: { r: '0x1', s: '0x2', v: 27 },
  }));
  expect(executeCall?.[1]).not.toHaveProperty('depositAmount');
  expect(submitPerpsCctpDepositTransfer).not.toHaveBeenCalled();
});

test('an open from balance whose size does not match the margin is not signed', async () => {
  jest.mocked(callBackendPost).mockResolvedValue({
    address: request.address,
    action: { type: 'order', orders: [{ ...balanceOrder, s: '1' }], grouping: 'na' },
    hash: '0xbuild', nonce: 1, typedData: {},
    updateLeverage: {
      action: { type: 'updateLeverage', asset: 0, leverage: 10, isCross: false },
      nonce: 2, hash: '0xlev', typedData: {},
    },
  });
  await expect(executePerpsOpenFromBalance('1-mainnet', 'token', {
    chain: 'hyperliquid', address: request.address, asset: request.asset,
    side: 'long', amount: '50', leverage: 10, isCross: false,
  })).rejects.toThrow('PerpsReviewChanged');
  expect(signHyperliquidExchangeBuild).not.toHaveBeenCalled();
  expect(callBackendPost).toHaveBeenCalledTimes(1);
});

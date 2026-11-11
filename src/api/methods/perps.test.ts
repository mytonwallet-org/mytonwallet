import type { ApiPerpsBuildPositionRequest, ApiPerpsExecutePositionResult, ApiUpdate, OnApiUpdate } from '../types';

import executeRequestsFixture from '../../../tests/fixtures/perpsExecuteRequests.json';
import { perpsWithdrawalFixture } from '../../../tests/helpers/perpsWithdrawal';
import { chains } from '../chains';
import {
  buildPerpsCctpDepositTransfer,
  signHyperliquidExchangeBuild,
  signHyperliquidExchangePayload,
  signHyperliquidWithdrawPermit,
  submitPerpsCctpDepositTransfer,
} from '../chains/evm/perps';
import { fetchStoredChainAccount } from '../common/accounts';
import { callBackendPost } from '../common/backend';
import { ApiServerError } from '../errors';
import {
  executePerpsClosePosition,
  executePerpsDepositMargin,
  executePerpsModifyPosition,
  executePerpsOpenFromBalance,
  executePerpsOpenPosition,
  executePerpsOpenPositionFromBalance,
  executePerpsWithdrawMargin,
  initPerps,
  perpsBuildWithdrawal,
  perpsEstimatePosition,
  perpsGetActivities,
  perpsGetAsset,
  perpsGetAssetChart,
  perpsWithdrawReleasedMargin,
} from './perps';

jest.mock('../chains', () => ({ chains: { arbitrum: { fetchPrivateKeyString: jest.fn() } } }));
jest.mock('../common/accounts', () => ({ fetchStoredChainAccount: jest.fn() }));
jest.mock('../common/backend', () => ({ callBackendGet: jest.fn(), callBackendPost: jest.fn() }));
jest.mock('../chains/evm/perps', () => ({
  buildPerpsCctpDepositTransfer: jest.fn(),
  signHyperliquidExchangeBuild: jest.fn().mockResolvedValue({ r: '0x1', s: '0x2', v: 27 }),
  signHyperliquidExchangePayload: jest.fn().mockResolvedValue({}),
  signHyperliquidWithdrawPermit: jest.fn().mockResolvedValue({ r: '0x1', s: '0x2', v: 27 }),
  submitPerpsCctpDepositTransfer: jest.fn(),
}));

const fetchPrivateKeyString = jest.mocked(chains.arbitrum.fetchPrivateKeyString);
const request: ApiPerpsBuildPositionRequest = {
  chain: 'hyperliquid', address: '0x123', asset: 'hyperliquid:hl:BTC',
  side: 'long', depositAmount: '50.2', leverage: 10, isCross: false,
};
const resize = { chain: request.chain, address: request.address, asset: request.asset, depositAmount: '50.2' };
const signer = { network: 'mainnet', address: request.address, privateKey: 'private-key' };

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
  updateLeverage: { action: { type: 'updateLeverage' } },
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
  jest.mocked(fetchStoredChainAccount).mockResolvedValue({
    type: 'mnemonic', byChain: { arbitrum: { address: request.address } },
  } as any);
  fetchPrivateKeyString.mockResolvedValue('private-key');
  jest.mocked(buildPerpsCctpDepositTransfer).mockResolvedValue({ calls: [] });
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

test('a reduce sizes its order from the released margin and withdraws what the order frees', async () => {
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
    skipPositionFlatWait: true, destination: request.address,
  }), expect.anything());
  expect(jest.mocked(callBackendPost).mock.calls[1][1]).not.toHaveProperty('depositAmount');
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
  expect(result).toBeUndefined();
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

test.each(['view', 'ledger'])('a %s account is refused before any build request or key read', async (type) => {
  jest.mocked(fetchStoredChainAccount).mockResolvedValue({
    type, byChain: { arbitrum: { address: request.address } },
  } as any);
  const balanceRequest = { chain: request.chain, address: request.address, amount: '10.2' };
  for (const execute of [
    () => executePerpsOpenPosition('1-mainnet', 'token', request, {}),
    () => executePerpsModifyPosition('1-mainnet', 'token', resize, {}),
    () => executePerpsClosePosition('1-mainnet', 'token', request, {}),
    () => executePerpsDepositMargin('1-mainnet', 'token', balanceRequest),
    () => executePerpsWithdrawMargin('1-mainnet', 'token', balanceRequest),
    () => executePerpsOpenFromBalance('1-mainnet', 'token', { ...balanceRequest, asset: request.asset,
      side: 'long', amount: '50', leverage: 10, isCross: false }),
  ]) {
    expect(await execute()).toEqual({ error: 'UnsuccesfulTransfer' });
  }
  await expect(perpsWithdrawReleasedMargin('1-mainnet', 'token', perpsWithdrawalFixture(request.address)))
    .rejects.toThrow('PerpsUnsupportedAccount');
  expect(callBackendPost).not.toHaveBeenCalled();
  expect(fetchPrivateKeyString).not.toHaveBeenCalled();
});

test('open validates and signs the build before starting execution, then deposits and reports the trade', async () => {
  const events: string[] = [];
  jest.mocked(callBackendPost).mockImplementation((url) => {
    events.push(url);
    return Promise.resolve(url.endsWith('/build') ? build : trade);
  });
  jest.mocked(signHyperliquidExchangeBuild).mockImplementationOnce(() => {
    events.push('sign');
    return Promise.resolve({ r: '0x1', s: '0x2', v: 27 });
  });
  jest.mocked(submitPerpsCctpDepositTransfer).mockImplementationOnce(() => {
    events.push('deposit');
    return Promise.resolve({ txHash: '0xdeposit' });
  });
  expect(await executePerpsOpenPosition('1-mainnet', 'token', request, {
    validateBuild: () => events.push('validateBuild'),
    onSubmitting: () => events.push('onSubmitting'),
    onDeposit: () => events.push('onDeposit'),
    onTrade: () => events.push('onTrade'),
  })).toEqual({ ...trade, depositTxHash: '0xdeposit' });
  expect(events).toEqual([
    '/perps/position/build', 'validateBuild', 'sign', 'onSubmitting', '/perps/position/execute', 'deposit',
    'onDeposit', 'onTrade',
  ]);
});

test.each([
  ['a higher estimate', '30'],
  ['an estimate that no longer needs a deposit', '0'],
])('a reviewed leverage deposit is not built on %s', async (_, depositAmount) => {
  jest.mocked(callBackendPost).mockResolvedValue({ depositAmount });
  const result = await executePerpsModifyPosition('1-mainnet', 'token', {
    chain: 'hyperliquid', address: request.address, asset: request.asset, leverage: 5, depositAmount: '20.2',
  }, {});
  expect(result).toEqual({ error: 'PerpsQuoteExpired' });
  expect(callBackendPost).toHaveBeenCalledTimes(1);
  expect(submitPerpsCctpDepositTransfer).not.toHaveBeenCalled();
});

test('a reviewed leverage deposit above a lower estimate builds with the reviewed amount', async () => {
  jest.mocked(callBackendPost).mockImplementation((url) => (url === '/perps/position/modify/estimate'
    ? Promise.resolve({ depositAmount: '19.837411' })
    : Promise.reject(new Error('stop after the build'))));
  await expect(executePerpsModifyPosition('1-mainnet', 'token', {
    chain: 'hyperliquid', address: request.address, asset: request.asset, leverage: 5, depositAmount: '20.2',
  }, {})).rejects.toThrow('stop after the build');
  expect(callBackendPost).toHaveBeenLastCalledWith('/perps/position/modify/build',
    expect.objectContaining({ leverage: 5, depositAmount: '20.2' }), expect.anything());
});

test.each(['open', 'modify'] as const)('reviewed %s waits for execution', async (flow) => {
  const execution = deferred<ApiPerpsExecutePositionResult>();
  const deposited = deferred<string>();
  const onTrade = jest.fn();
  jest.mocked(callBackendPost).mockImplementation((url) =>
    url.endsWith('/build') ? Promise.resolve(build) : execution.promise);
  const onDeposit = jest.fn(deposited.resolve);
  const hooks = { onDeposit, onTrade };
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
  expect(onDeposit).toHaveBeenCalledWith('0xdeposit');
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

test('a reduce the backend prepares no withdrawal for reports its fill', async () => {
  jest.mocked(callBackendPost).mockImplementation((url) => url.endsWith('/build')
    ? Promise.resolve(build) : Promise.resolve({ phase: 'withdraw_unavailable', close: trade }));
  const result = await executePerpsModifyPosition('1-mainnet', 'token', { ...request, reduceOnly: true }, {});
  expect(result).toEqual(trade);
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

test('a first order signs the switch to Unified for its own account and sends it to execute', async () => {
  const setAbstraction = { action: { type: 'userSetAbstraction' }, nonce: 5, hash: '0x5', typedData: {} };
  const signedSwitch = { action: setAbstraction.action, nonce: 5, signature: { r: '0x1', s: '0x2', v: 27 } };
  jest.mocked(signHyperliquidExchangePayload).mockImplementation((_, payload) => Promise.resolve(
    ((payload as unknown) === setAbstraction ? signedSwitch : {}) as any,
  ));
  jest.mocked(callBackendPost).mockImplementation((url) => url.endsWith('/build')
    ? Promise.resolve({ ...build, setAbstraction }) : Promise.resolve(trade));

  await executePerpsOpenPosition('1-mainnet', 'token', request, {});

  expect(signHyperliquidExchangePayload).toHaveBeenCalledWith(signer, setAbstraction, {
    expectedSpotToPerpAmountUsdc: '50', expectedAccount: signer.address,
  });
  const executeCall = jest.mocked(callBackendPost).mock.calls.find((call) => call[0] === '/perps/position/execute');
  expect(executeCall?.[1]).toMatchObject({ setAbstraction: signedSwitch });
});

test.each([
  'approveBuilderFee', 'spotToPerp', 'updateLeverage',
])('a switch carried as %s is not signed', async (slot) => {
  const setAbstraction = { action: { type: 'userSetAbstraction' }, nonce: 5, hash: '0x5', typedData: {} };
  jest.mocked(callBackendPost).mockImplementation((url) => url.endsWith('/build')
    ? Promise.resolve({ ...build, [slot]: setAbstraction }) : Promise.resolve(trade));

  await expect(executePerpsOpenPosition('1-mainnet', 'token', request, {})).rejects.toThrow('Invalid build');

  expect(signHyperliquidExchangeBuild).not.toHaveBeenCalled();
  expect(signHyperliquidExchangePayload).not.toHaveBeenCalled();
  expect(submitPerpsCctpDepositTransfer).not.toHaveBeenCalled();
});

test('a build whose own action is the switch is not signed', async () => {
  jest.mocked(callBackendPost).mockImplementation((url) => url.endsWith('/build')
    ? Promise.resolve({ ...build, action: { type: 'userSetAbstraction' } }) : Promise.resolve(trade));

  await expect(executePerpsOpenPosition('1-mainnet', 'token', request, {})).rejects.toThrow('Invalid build');

  expect(signHyperliquidExchangeBuild).not.toHaveBeenCalled();
  expect(signHyperliquidExchangePayload).not.toHaveBeenCalled();
});

test.each(['reduce', 'close'] as const)('a %s keeps its filled order when the venue rejects its withdrawal', async (
  kind,
) => {
  const reason = '[HL_EXCHANGE_ERROR] Insufficient USDC or HYPE balance for token transfer gas.';
  const withdraw = perpsWithdrawalFixture(request.address, '50');
  jest.mocked(callBackendPost).mockImplementation((url, body) => {
    if (url.endsWith('/build')) return Promise.resolve(build);
    return (body as { action?: { type?: string } }).action?.type === 'sendToEvmWithData'
      ? Promise.reject(new ApiServerError(reason, 500))
      : Promise.resolve({ phase: 'awaiting_withdraw_signature', close: trade, withdraw });
  });
  const onWithdrawalRejected = jest.fn();
  const result = kind === 'reduce'
    ? await executePerpsModifyPosition('1-mainnet', 'token', { ...request, reduceOnly: true }, { onWithdrawalRejected })
    : await executePerpsClosePosition('1-mainnet', 'token', {
      chain: request.chain, address: request.address, asset: request.asset,
    }, { onWithdrawalRejected });
  expect(result).toEqual(kind === 'reduce' ? trade : undefined);
  expect(onWithdrawalRejected).toHaveBeenCalledWith(reason);
});

test('a failed withdrawal request is not reported as a venue rejection', async () => {
  const withdraw = perpsWithdrawalFixture(request.address, '50');
  jest.mocked(callBackendPost).mockImplementation((url, body) => {
    if (url.endsWith('/build')) return Promise.resolve(build);
    return (body as { action?: { type?: string } }).action?.type === 'sendToEvmWithData'
      ? Promise.reject(new ApiServerError('Exchange request timed out', 500))
      : Promise.resolve({ phase: 'awaiting_withdraw_signature', close: trade, withdraw });
  });
  const onWithdrawalRejected = jest.fn();
  await expect(executePerpsClosePosition('1-mainnet', 'token', {
    chain: request.chain, address: request.address, asset: request.asset,
  }, { onWithdrawalRejected })).rejects.toThrow('Exchange request timed out');
  expect(onWithdrawalRejected).not.toHaveBeenCalled();
});

test.each(['close', 'reduce'])('a %s without the builder fee approval signs and sends it', async (kind) => {
  const approveBuilderFee = { hash: '0xa', nonce: 9, action: { type: 'approveBuilderFee' }, typedData: {} };
  const signedApproval = { action: approveBuilderFee.action, nonce: 9, signature: { r: '0x1', s: '0x2', v: 27 } };
  const exitBuild = { ...build, deposit: undefined, updateLeverage: undefined, approveBuilderFee,
    action: { type: 'order', grouping: 'na',
      orders: [{ a: 0, b: false, p: '99500', s: '0.005', r: true, t: { limit: { tif: 'Ioc' } } }],
    } };
  jest.mocked(signHyperliquidExchangePayload).mockResolvedValueOnce(signedApproval as any);
  jest.mocked(callBackendPost).mockImplementation((url) => url.endsWith('/build')
    ? Promise.resolve(exitBuild) : Promise.resolve({ phase: 'withdraw_unavailable', close: trade }));

  await (kind === 'close'
    ? executePerpsClosePosition('1-mainnet', 'token', {
      chain: 'hyperliquid', address: request.address, asset: request.asset, slippage: 0.002,
    }, {})
    : executePerpsModifyPosition('1-mainnet', 'token', { ...request, reduceOnly: true }, {}));

  expect(callBackendPost).toHaveBeenLastCalledWith(
    '/perps/position/close/execute', expect.objectContaining({ approveBuilderFee: signedApproval }), expect.anything(),
  );
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
  expect(signHyperliquidWithdrawPermit).toHaveBeenCalledWith(signer,
    expect.objectContaining({ amountUsdc: '50', destination: request.address }));
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
  fetchPrivateKeyString.mockResolvedValueOnce(undefined);
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
  expect(submitPerpsCctpDepositTransfer).toHaveBeenCalledWith(signer, []);
  expect(onUpdate).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'perpsDepositSubmitted' }));
  expect(signHyperliquidExchangeBuild).not.toHaveBeenCalled();
  expect(signHyperliquidExchangePayload).toHaveBeenCalledWith(signer, spotToPerp, {
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
  expect(signHyperliquidExchangeBuild).toHaveBeenCalledWith(signer, withdrawBuild, {
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

test('a reviewed balance withdrawal validates its build before signing and reports submission after it', async () => {
  const events: string[] = [];
  const withdrawBuild = {
    address: request.address, hash: '0xwd', nonce: 5, typedData: {},
    action: { type: 'sendToEvmWithData', amount: '10.2', destinationRecipient: request.address, sourceDex: 'spot' },
  };
  jest.mocked(callBackendPost).mockImplementation((url) => {
    events.push(url);
    return Promise.resolve(url === '/perps/withdraw/build' ? withdrawBuild : { ...trade, status: 'success' });
  });
  jest.mocked(signHyperliquidExchangeBuild).mockImplementationOnce(() => {
    events.push('sign');
    return Promise.resolve({ r: '0x1', s: '0x2', v: 27 });
  });
  expect(await executePerpsWithdrawMargin('1-mainnet', 'token', {
    chain: 'hyperliquid', address: request.address, amount: '10.2',
  }, {
    validateBuild: (build) => events.push(`validateBuild:${String(build.action?.sourceDex)}`),
    onSubmitting: () => events.push('onSubmitting'),
  })).toMatchObject({ status: 'success' });
  expect(events).toEqual([
    '/perps/withdraw/build', 'validateBuild:spot', 'sign', 'onSubmitting', '/perps/position/execute',
  ]);
});

test('a balance withdrawal its reviewer refuses is neither signed nor submitted', async () => {
  const onSubmitting = jest.fn();
  jest.mocked(callBackendPost).mockResolvedValue({
    address: request.address, hash: '0xwd', nonce: 5, typedData: {},
    action: { type: 'sendToEvmWithData', amount: '10.2', destinationRecipient: request.address, sourceDex: 'spot' },
  });
  await expect(executePerpsWithdrawMargin('1-mainnet', 'token', {
    chain: 'hyperliquid', address: request.address, amount: '10.2',
  }, {
    validateBuild: () => {
      throw new Error('PerpsReviewChanged');
    },
    onSubmitting,
  })).rejects.toThrow('PerpsReviewChanged');
  expect(signHyperliquidExchangeBuild).not.toHaveBeenCalled();
  expect(onSubmitting).not.toHaveBeenCalled();
  expect(callBackendPost).toHaveBeenCalledTimes(1);
});

test('a balance withdrawal build carrying another action is refused before signing', async () => {
  jest.mocked(callBackendPost).mockResolvedValue({
    address: request.address, hash: '0xwd', nonce: 5, typedData: {},
    action: { type: 'usdClassTransfer', amount: '10.2', destinationRecipient: request.address },
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

const signedPayload = (type: string, nonce: number) => ({ action: { type }, nonce, hash: `0x${nonce}`, typedData: {} });
const marketOrder = {
  type: 'order', grouping: 'na',
  orders: [{ a: 0, b: true, p: '103000', s: '0.005', r: false, t: { limit: { tif: 'Ioc' } } }],
};

test('execute requests keep their wire shape', async () => {
  // Each signed side payload is recognizable in the request by its nonce.
  jest.mocked(signHyperliquidExchangePayload).mockImplementation((...args: unknown[]) => Promise.resolve({
    signed: (args.find((arg) => typeof arg === 'object' && Boolean(arg) && 'nonce' in arg) as { nonce: number }).nonce,
  } as any));
  const withdraw = {
    requiresPermitSignature: true as const, amountUsdc: '50', destination: request.address,
    action: { type: 'sendToEvmWithData', amount: '50', nonce: 9 }, nonce: 9,
    permitData: { domain: {}, types: {}, values: {} },
  };
  const sides = {
    approveBuilderFee: signedPayload('approveBuilderFee', 2), spotToPerp: signedPayload('usdClassTransfer', 3),
    updateLeverage: signedPayload('updateLeverage', 4), updateIsolatedMargin: signedPayload('updateIsolatedMargin', 5),
  };
  const deposit = { amountUsdc: '50.2', creditedAmountUsdc: '50' };
  const orderBuild = { address: request.address, action: marketOrder, hash: '0x1', nonce: 1, typedData: {} };
  const bodies = async (responses: Record<string, unknown>, run: () => Promise<unknown>) => {
    jest.mocked(callBackendPost).mockReset();
    jest.mocked(callBackendPost).mockImplementation((url, body) => Promise.resolve(
      url === '/perps/position/close/execute'
        ? body.action.type === 'order'
          ? { phase: 'awaiting_withdraw_signature', close: trade, withdraw }
          : { phase: 'completed', withdrawResult: { ...trade, status: 'ok' } }
        : responses[url] ?? trade,
    ));
    const result = await run();
    if (result && typeof result === 'object' && 'completion' in result) await result.completion;
    return jest.mocked(callBackendPost).mock.calls.map(([url, body]) => [url, JSON.parse(JSON.stringify(body))]);
  };
  const captured = {
    open: await bodies({ '/perps/position/build': { ...orderBuild, deposit, ...sides } },
      () => executePerpsOpenPosition('1-mainnet', 'token', request, {})),
    increase: await bodies({ '/perps/position/modify/build': { ...orderBuild, deposit, ...sides } },
      () => executePerpsModifyPosition('1-mainnet', 'token', resize, {})),
    leverageDeposit: await bodies({
      '/perps/position/modify/estimate': { depositAmount: '20.2' },
      '/perps/position/modify/build': { address: request.address, deposit, ...sides },
    }, () => executePerpsModifyPosition('1-mainnet', 'token', { ...resize, depositAmount: '20.2', leverage: 5 }, {})),
    leverage: await bodies({
      '/perps/position/modify/estimate': { depositAmount: '0' },
      '/perps/position/modify/build': { address: request.address, updateLeverage: sides.updateLeverage },
    }, () => executePerpsModifyPosition('1-mainnet', 'token', { ...resize, depositAmount: '0', leverage: 20 }, {})),
    reduce: await bodies({ '/perps/position/modify/build': { ...orderBuild, ...sides } },
      () => executePerpsModifyPosition('1-mainnet', 'token', { ...resize, depositAmount: '5', reduceOnly: true }, {}),
    ),
    close: await bodies({ '/perps/position/close/build': orderBuild },
      () => executePerpsClosePosition('1-mainnet', 'token', { ...resize, slippage: 0.03 }, {})),
    deposit: await bodies({
      '/perps/deposit/build': { address: request.address, deposit, spotToPerp: sides.spotToPerp },
    }, () => executePerpsDepositMargin('1-mainnet', 'token', {
      chain: 'hyperliquid', address: request.address, amount: '50.2',
    })),
    withdraw: await bodies({ '/perps/withdraw/build': {
      ...orderBuild, action: { type: 'sendToEvmWithData', amount: '10.2', destinationRecipient: request.address },
    } }, () => executePerpsWithdrawMargin('1-mainnet', 'token', {
      chain: 'hyperliquid', address: request.address, amount: '10.2',
    })),
    openFromBalance: await bodies({ '/perps/position/open': {
      ...orderBuild, marketReferencePrice: '100000', approveBuilderFee: sides.approveBuilderFee,
      updateLeverage: {
        ...sides.updateLeverage, action: { type: 'updateLeverage', asset: 0, leverage: 10, isCross: false },
      },
    } }, () => executePerpsOpenFromBalance('1-mainnet', 'token', {
      chain: 'hyperliquid', address: request.address, asset: request.asset,
      side: 'long', amount: '50', leverage: 10, isCross: false,
    })),
    releasedMargin: await bodies({}, () => perpsWithdrawReleasedMargin('1-mainnet', 'token', withdraw)),
  };
  jest.mocked(signHyperliquidExchangePayload).mockResolvedValue({} as any);
  expect(captured).toEqual(executeRequestsFixture);
});

describe('balance funding', () => {
  const openRequest = {
    chain: 'hyperliquid' as const, address: request.address, asset: request.asset,
    side: 'long' as const, amount: '50', leverage: 10, isCross: false, slippage: 0.03,
  };
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
  const increase = { ...resize, depositAmount: '20', reduceOnly: false, fundingSource: 'balance' as const };
  const leverage = { ...resize, depositAmount: undefined, leverage: 5, fundingSource: 'balance' as const };

  function executeBody() {
    return jest.mocked(callBackendPost).mock.calls.find(([url]) => url === '/perps/position/execute')?.[1];
  }

  test('a reviewed open from the balance validates its build and executes with the balance as source', async () => {
    const events: string[] = [];
    jest.mocked(callBackendPost).mockImplementation((url) => {
      events.push(url);
      return Promise.resolve(url === '/perps/position/open' ? openBuild : trade);
    });
    const validateBuild = jest.fn(() => events.push('validateBuild'));
    expect(await executePerpsOpenPositionFromBalance('1-mainnet', 'token', openRequest, {
      validateBuild, onSubmitting: () => events.push('onSubmitting'),
    })).toEqual(trade);
    expect(validateBuild).toHaveBeenCalledWith(openBuild);
    expect(events).toEqual(['/perps/position/open', 'validateBuild', 'onSubmitting', '/perps/position/execute']);
    expect(callBackendPost).toHaveBeenNthCalledWith(1, '/perps/position/open', openRequest, expect.anything());
    expect(executeBody()).toEqual({
      chain: 'hyperliquid', address: request.address, action: openBuild.action, nonce: 1,
      signature: { r: '0x1', s: '0x2', v: 27 }, updateLeverage: {}, fundingSource: 'balance',
    });
    expect(buildPerpsCctpDepositTransfer).not.toHaveBeenCalled();
    expect(submitPerpsCctpDepositTransfer).not.toHaveBeenCalled();
  });

  test('a reviewed open checks its size against the review, so lot rounding of a small order passes', async () => {
    // 15.5 USDC at 1× is 0.000155 BTC; the backend rounds it down to the 0.00015 lot.
    const smallBuild = { ...openBuild,
      action: { ...openBuild.action, orders: [{ ...balanceOrder, s: '0.00015' }] },
      updateLeverage: { ...openBuild.updateLeverage, action: { ...openBuild.updateLeverage.action, leverage: 1 } } };
    const smallRequest = { ...openRequest, amount: '15.5', leverage: 1 };
    jest.mocked(callBackendPost).mockImplementation((url) =>
      Promise.resolve(url === '/perps/position/open' ? smallBuild : trade));
    await expect(executePerpsOpenFromBalance('1-mainnet', 'token', smallRequest)).rejects.toThrow('PerpsReviewChanged');
    expect(await executePerpsOpenPositionFromBalance('1-mainnet', 'token', smallRequest, { validateBuild: jest.fn() }))
      .toEqual(trade);
  });

  test.each([
    ['a deposit', { deposit: { amountUsdc: '50.2', creditedAmountUsdc: '50' } }],
    ['a mode switch', {
      setAbstraction: { action: { type: 'userSetAbstraction' }, nonce: 3, hash: '0x3', typedData: {} },
    }],
    ['a spot transfer', { spotToPerp: { action: { type: 'usdClassTransfer' }, nonce: 3, hash: '0x3', typedData: {} } }],
  ])('a reviewed open whose build carries %s is not signed', async (_, extra) => {
    jest.mocked(callBackendPost).mockResolvedValue({ ...openBuild, ...extra });
    const validateBuild = jest.fn();
    await expect(executePerpsOpenPositionFromBalance('1-mainnet', 'token', openRequest, { validateBuild }))
      .rejects.toThrow('PerpsReviewChanged');
    expect(validateBuild).not.toHaveBeenCalled();
    expect(signHyperliquidExchangeBuild).not.toHaveBeenCalled();
    expect(callBackendPost).toHaveBeenCalledTimes(1);
  });

  test('an increase from the balance builds and executes its order without a deposit', async () => {
    const orderBuild = { address: request.address, action: marketOrder, hash: '0x1', nonce: 1, typedData: {} };
    jest.mocked(callBackendPost).mockImplementation((url) =>
      Promise.resolve(url === '/perps/position/modify/build' ? orderBuild : trade));
    const onSubmitting = jest.fn();
    expect(await executePerpsModifyPosition('1-mainnet', 'token', increase, { onSubmitting })).toEqual(trade);
    expect(callBackendPost).toHaveBeenNthCalledWith(1, '/perps/position/modify/build', {
      ...increase, slippage: 0.03,
    }, expect.anything());
    expect(executeBody()).toEqual({
      chain: 'hyperliquid', address: request.address, action: marketOrder, nonce: 1,
      signature: { r: '0x1', s: '0x2', v: 27 }, fundingSource: 'balance',
    });
    expect(onSubmitting).toHaveBeenCalledTimes(1);
    expect(buildPerpsCctpDepositTransfer).not.toHaveBeenCalled();
    expect(submitPerpsCctpDepositTransfer).not.toHaveBeenCalled();
  });

  test.each([
    ['a deposit', { deposit: { amountUsdc: '20.2', creditedAmountUsdc: '20' } }],
    ['a spot transfer', { spotToPerp: { action: { type: 'usdClassTransfer' }, nonce: 3, hash: '0x3', typedData: {} } }],
  ])('an increase from the balance whose build carries %s bridges nothing', async (_, extra) => {
    jest.mocked(callBackendPost).mockResolvedValue({
      address: request.address, action: marketOrder, hash: '0x1', nonce: 1, typedData: {}, ...extra,
    });
    await expect(executePerpsModifyPosition('1-mainnet', 'token', increase, {})).rejects.toThrow('PerpsReviewChanged');
    expect(signHyperliquidExchangeBuild).not.toHaveBeenCalled();
    expect(buildPerpsCctpDepositTransfer).not.toHaveBeenCalled();
    expect(submitPerpsCctpDepositTransfer).not.toHaveBeenCalled();
    expect(callBackendPost).toHaveBeenCalledTimes(1);
  });

  test('a leverage decrease from the balance re-reads its margin and builds without a deposit', async () => {
    const leverageBuild = {
      address: request.address,
      updateLeverage: signedPayload('updateLeverage', 2),
      updateIsolatedMargin: signedPayload('updateIsolatedMargin', 3),
    };
    jest.mocked(callBackendPost).mockImplementation((url) => Promise.resolve(
      url === '/perps/position/modify/estimate' ? { depositAmount: '0', marginAmount: '20' }
        : url === '/perps/position/modify/build' ? leverageBuild : { ...trade, status: 'ok' },
    ));
    expect(await executePerpsModifyPosition('1-mainnet', 'token', leverage, {}, '20'))
      .toEqual({ ...trade, status: 'ok' });
    const bodies = jest.mocked(callBackendPost).mock.calls
      .map(([url, body]) => [url, JSON.parse(JSON.stringify(body))]);
    expect(bodies).toEqual([
      ['/perps/position/modify/estimate', {
        chain: 'hyperliquid', address: request.address, asset: request.asset, leverage: 5, fundingSource: 'balance',
      }],
      ['/perps/position/modify/build', {
        chain: 'hyperliquid', address: request.address, asset: request.asset, leverage: 5,
        fundingSource: 'balance', marginAmount: '20', slippage: 0.03,
      }],
      ['/perps/position/execute', {
        chain: 'hyperliquid', address: request.address, updateLeverage: {}, updateIsolatedMargin: {},
        fundingSource: 'balance',
      }],
    ]);
    expect(signHyperliquidExchangePayload).toHaveBeenCalledTimes(2);
    expect(submitPerpsCctpDepositTransfer).not.toHaveBeenCalled();
  });

  test.each([
    ['a smaller reviewed margin', '20', '15'],
    ['no reviewed margin', '20', undefined],
    ['a reviewed margin it no longer needs', '0', '25'],
  ])('a leverage change from the balance with %s is not built', async (_, marginAmount, reviewed) => {
    jest.mocked(callBackendPost).mockResolvedValue({ depositAmount: '0', marginAmount });
    expect(await executePerpsModifyPosition('1-mainnet', 'token', leverage, {}, reviewed))
      .toEqual({ error: 'PerpsQuoteExpired' });
    expect(callBackendPost).toHaveBeenCalledTimes(1);
    expect(fetchPrivateKeyString).not.toHaveBeenCalled();
  });

  test('a leverage change from the balance builds with the reviewed margin above a lower estimate', async () => {
    jest.mocked(callBackendPost).mockImplementation((url) => (url === '/perps/position/modify/estimate'
      ? Promise.resolve({ depositAmount: '0', marginAmount: '19.837411' })
      : Promise.reject(new Error('stop after the build'))));
    await expect(executePerpsModifyPosition('1-mainnet', 'token', leverage, {}, '25'))
      .rejects.toThrow('stop after the build');
    expect(callBackendPost).toHaveBeenLastCalledWith('/perps/position/modify/build',
      expect.objectContaining({ leverage: 5, fundingSource: 'balance', marginAmount: '25' }), expect.anything());
  });
});

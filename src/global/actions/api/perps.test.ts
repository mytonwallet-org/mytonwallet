import './perps';
import '../apiUpdates/perps';
import '../ui/perps';

import type {
  ApiPerpsAccountPosition,
  ApiPerpsFill,
  ApiPerpsFundingRequirements,
  ApiPerpsMarketAsset,
  ApiPerpsOperation,
  ApiPerpsQuote,
} from '../../../api/types';
import type { Account, GlobalState, PerpsTradeState } from '../../types';

import Deferred from '../../../util/Deferred';
import { buildPerpsMarketFixture } from '../../../../tests/helpers/perpsMarket';
import { callApi, callApiWithThrow } from '../../../api';
import { persistPerpsSubmission } from '../../helpers/perpsSubmission';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { INITIAL_STATE } from '../../initialState';
import {
  addPerpsReceipt, updateAccountPerps, updatePerpsMarket, updatePerpsSnapshot,
} from '../../reducers/perps';
import { switchAccount } from './auth';

jest.mock('../../../config', () => ({
  __esModule: true,
  ...jest.requireActual('../../../config'),
  IS_PERPS_SUPPORTED: true,
}));

jest.mock('./auth', () => ({ switchAccount: jest.fn() }));

jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
}));

jest.mock('../../../api', () => ({
  callApi: jest.fn(),
  callApiWithThrow: jest.fn(),
}));

jest.mock('../../cache', () => ({ persistCache: jest.fn() }));

jest.mock('../../helpers/perpsSubmission', () => ({
  ...jest.requireActual('../../helpers/perpsSubmission'),
  persistPerpsSubmission: jest.fn(),
}));

jest.mock('../../helpers/enclave', () => ({
  withEnclaveSessionRelease: (handler: AnyFunction) => handler,
}));

type Handler = (global: GlobalState, actions: AnyLiteral, payload?: AnyLiteral) => unknown;

const ACCOUNT_ID = '0-mainnet';

// The handlers register on import, before `clearAllMocks` empties the calls
const handlers = new Map<string, Handler>(
  (addActionHandler as jest.Mock).mock.calls.map(([name, handler]) => [name as string, handler as Handler]),
);

let currentGlobal: GlobalState;

function getHandler(name: string): Handler {
  return handlers.get(name)!;
}

function buildActions() {
  return {
    apiUpdate: jest.fn(),
    preparePerpsTrade: jest.fn(),
    loadPerpsSnapshot: jest.fn(),
    loadPerpsHistory: jest.fn(),
    loadPerpsMarket: jest.fn(),
    loadPerpsFundingRequirements: jest.fn(),
    openPerpsOperation: jest.fn(),
    openFuturesPosition: jest.fn(),
    showError: jest.fn(),
  };
}

function buildOperation(operation: Partial<ApiPerpsOperation>) {
  return {
    id: 'op-1',
    accountId: ACCOUNT_ID,
    assetId: 'hyperliquid:hl:BTC',
    kind: 'open',
    state: 'running',
    stage: 'preparing',
    createdAt: 1,
    ...operation,
  } as ApiPerpsOperation;
}

function setOperations(accountId: string, operations: ApiPerpsOperation[]) {
  currentGlobal = {
    ...currentGlobal,
    currentAccountId: accountId,
    byAccountId: {
      ...currentGlobal.byAccountId,
      [accountId]: {
        ...currentGlobal.byAccountId[accountId],
        perpsOperations: Object.fromEntries(operations.map((operation) => [operation.id, operation])),
      },
    },
  };
}

function setTrade(trade: Partial<PerpsTradeState>) {
  const global = updatePerpsSnapshot(updatePerpsMarket({
    ...INITIAL_STATE,
    currentAccountId: ACCOUNT_ID,
    accounts: { byId: { [ACCOUNT_ID]: { type: 'mnemonic', byChain: { arbitrum: { address: '0x1' } } } } },
  }, buildPerpsMarketFixture([
    { id: 'hyperliquid:hl:BTC', tradingAvailability: { isAvailable: true } } as ApiPerpsMarketAsset,
  ])), ACCOUNT_ID, {
    ...buildPerpsMarketFixture(),
    positions: [],
    totalEquity: '0',
    totalPnl: '0',
    timestamp: 1,
    unavailableDexs: [],
    tradingAvailability: { isAvailable: true },
  });

  currentGlobal = {
    ...global,
    perps: {
      ...global.perps,
      trade: {
        id: 'trade-1',
        accountId: ACCOUNT_ID,
        step: 'password',
        kind: 'open',
        assetId: 'hyperliquid:hl:BTC',
        side: 'long',
        amount: '100',
        leverage: 2,
        ...trade,
      },
    },
  };
}

function buildQuote(quote: Partial<ApiPerpsQuote> = {}) {
  return {
    id: 'quote-1',
    accountId: ACCOUNT_ID,
    assetId: 'hyperliquid:hl:BTC',
    kind: 'open',
    expiresAt: Date.now() + 60_000,
    ...quote,
  } as ApiPerpsQuote;
}

beforeEach(() => {
  jest.clearAllMocks();
  (getGlobal as jest.Mock).mockImplementation(() => currentGlobal);
  (setGlobal as jest.Mock).mockImplementation((global: GlobalState) => {
    currentGlobal = global;
  });
});

describe('submitPerpsTrade', () => {
  it('sends nothing when the operation could not be saved', async () => {
    setTrade({ quote: buildQuote() });
    (persistPerpsSubmission as jest.Mock).mockImplementation(() => {
      throw new Error('Could not save the operation');
    });

    await getHandler('submitPerpsTrade')(currentGlobal, buildActions(), { enclaveToken: 'token' });

    expect(callApiWithThrow).not.toHaveBeenCalled();
    expect(currentGlobal.perps.trade?.step).toBe('review');
    expect(currentGlobal.byAccountId[ACCOUNT_ID].perpsReceipts).toEqual({});
  });

  it('saves the signed quote for the receipt together with the operation', async () => {
    setTrade({ quote: buildQuote() });
    let savedQuote: ApiPerpsQuote | undefined;
    (persistPerpsSubmission as jest.Mock).mockImplementation((operation: ApiPerpsOperation) => {
      savedQuote = getGlobal().byAccountId[ACCOUNT_ID].perpsReceipts?.[operation.id]?.quote;
    });
    (callApiWithThrow as jest.Mock).mockResolvedValue(undefined);

    await getHandler('submitPerpsTrade')(currentGlobal, buildActions(), { enclaveToken: 'token' });

    expect(savedQuote).toMatchObject({ id: 'quote-1' });
  });

  it('records an unknown outcome when the worker does not answer', async () => {
    setTrade({ quote: buildQuote() });
    (persistPerpsSubmission as jest.Mock).mockImplementation(() => undefined);
    (callApiWithThrow as jest.Mock).mockResolvedValue(undefined);
    const actions = buildActions();

    await getHandler('submitPerpsTrade')(currentGlobal, actions, { enclaveToken: 'token' });

    expect(actions.apiUpdate).toHaveBeenCalledWith({
      type: 'perpsOperationUpdated',
      operation: expect.objectContaining({ state: 'unknown' }),
    });
    expect(currentGlobal.perps.trade?.step).toBe('receipt');
  });

  it('reviews again after the SDK rejects an expired quote', async () => {
    setTrade({ quote: buildQuote() });
    (persistPerpsSubmission as jest.Mock).mockImplementation(() => undefined);
    (callApiWithThrow as jest.Mock).mockRejectedValue(new Error('PerpsQuoteExpired'));
    const actions = buildActions();

    await getHandler('submitPerpsTrade')(currentGlobal, actions, { enclaveToken: 'token' });

    expect(actions.apiUpdate).toHaveBeenCalledWith({
      type: 'perpsOperationUpdated',
      operation: expect.objectContaining({ state: 'failed' }),
    });
    expect(currentGlobal.perps.trade).toMatchObject({ step: 'review', operationId: undefined });
    expect(actions.preparePerpsTrade).toHaveBeenCalled();
  });

  it('reviews again when the SDK reports that the order changed', async () => {
    setTrade({ quote: buildQuote() });
    (persistPerpsSubmission as jest.Mock).mockImplementation(() => undefined);
    (callApiWithThrow as jest.Mock).mockImplementation((_, __, ___, ____, operationId: string) => Promise.resolve(
      buildOperation({ id: operationId, state: 'failed', error: 'PerpsReviewChanged' }),
    ));
    const actions = buildActions();

    await getHandler('submitPerpsTrade')(currentGlobal, actions, { enclaveToken: 'token' });

    expect(currentGlobal.perps.trade).toMatchObject({ step: 'review', operationId: undefined });
    expect(actions.preparePerpsTrade).toHaveBeenCalled();
  });

  it('never submits a quote that expired while the password was typed', async () => {
    setTrade({ quote: buildQuote({ expiresAt: Date.now() - 1 }) });
    const actions = buildActions();

    await getHandler('submitPerpsTrade')(currentGlobal, actions, { enclaveToken: 'token' });

    expect(persistPerpsSubmission).not.toHaveBeenCalled();
    expect(callApiWithThrow).not.toHaveBeenCalled();
    expect(actions.preparePerpsTrade).toHaveBeenCalled();
  });
});

describe('preparePerpsTrade', () => {
  it('does not replace the reviewed change with a change of another kind', async () => {
    setTrade({ step: 'review', kind: 'edit', quote: buildQuote({ kind: 'increase' }) });
    (callApiWithThrow as jest.Mock).mockResolvedValue(buildQuote({ id: 'quote-2', kind: 'reduce' }));

    await getHandler('preparePerpsTrade')(currentGlobal, buildActions());

    expect(currentGlobal.perps.trade).toMatchObject({ error: 'PerpsPositionChanged', quote: { id: 'quote-1' } });
  });

  it('tells that the review changed once the new quote arrives', async () => {
    setTrade({ step: 'review', quote: buildQuote() });
    (callApiWithThrow as jest.Mock).mockResolvedValue(buildQuote({ id: 'quote-2' }));

    await getHandler('preparePerpsTrade')(currentGlobal, buildActions());

    expect(currentGlobal.perps.trade).toMatchObject({ reviewNotice: 'PerpsReviewUpdated', quote: { id: 'quote-2' } });
  });

  it('drops the quote of the previous amount and lets the user review again', async () => {
    setTrade({ step: 'form' });
    const reply = new Deferred<ApiPerpsQuote>();
    (callApiWithThrow as jest.Mock).mockReturnValue(reply.promise);

    const preparing = getHandler('preparePerpsTrade')(currentGlobal, buildActions());
    currentGlobal = getHandler('setPerpsTradeAmount')(currentGlobal, buildActions(), { amount: '1000' }) as GlobalState;
    reply.resolve(buildQuote());
    await preparing;

    expect(currentGlobal.perps.trade).toMatchObject({ step: 'form', amount: '1000' });
    expect(currentGlobal.perps.trade?.quote).toBeUndefined();
    expect(currentGlobal.perps.trade?.isPreparing).toBeUndefined();
  });

  it.each([
    ['the form, after a refresh of the Review screen', 'review', 'form'],
    ['the wallet list', 'form', 'selectAccount'],
  ] as const)('leaves the user on %s when the quote arrives', async (_, step, nextStep) => {
    setTrade({ step, quote: buildQuote() });
    const reply = new Deferred<ApiPerpsQuote>();
    (callApiWithThrow as jest.Mock).mockReturnValue(reply.promise);

    const preparing = getHandler('preparePerpsTrade')(currentGlobal, buildActions());
    currentGlobal = getHandler('setPerpsTradeStep')(currentGlobal, buildActions(), { step: nextStep }) as GlobalState;
    reply.resolve(buildQuote({ id: 'quote-2' }));
    await preparing;

    expect(currentGlobal.perps.trade).toMatchObject({ step: nextStep, quote: { id: 'quote-1' } });
    expect(currentGlobal.perps.trade?.isPreparing).toBeUndefined();
  });

  it('shows a toast and opens no review when a close cannot be prepared, as on iOS', async () => {
    setTrade({ step: 'review', kind: 'close' });
    (callApiWithThrow as jest.Mock).mockRejectedValue(new Error('PerpsTradingUnavailable'));
    const actions = buildActions();

    await getHandler('preparePerpsTrade')(currentGlobal, actions);

    expect(currentGlobal.perps.trade).toBeUndefined();
    expect(actions.showError).toHaveBeenCalled();
  });

  it('tells the balance a refreshed quote needs', async () => {
    setTrade({ step: 'review', fundingSource: 'balance', quote: buildQuote() });
    (callApiWithThrow as jest.Mock).mockRejectedValue(
      Object.assign(new Error('PerpsInsufficientBalance'), { requiredBalance: '3.01', availableBalance: '0.5' }),
    );

    await getHandler('preparePerpsTrade')(currentGlobal, buildActions());

    expect(currentGlobal.perps.trade).toMatchObject({
      step: 'review',
      error: 'PerpsInsufficientBalance',
      errorDetails: { requiredBalance: '3.01', availableBalance: '0.5' },
    });
  });
});

describe('the receipt of a submitted trade', () => {
  it('replaces the progress once the operation goes out, as on iOS', () => {
    setTrade({ step: 'progress', operationId: 'op-1' });

    getHandler('apiUpdate')(currentGlobal, buildActions(), {
      type: 'perpsOperationUpdated', operation: buildOperation({ stage: 'deposit' }),
    });

    expect(currentGlobal.perps.trade?.step).toBe('receipt');
    expect(currentGlobal.byAccountId[ACCOUNT_ID].perpsOperations?.['op-1']).toBeDefined();
    // A dev build rejects a second `setGlobal` of a global derived before the first one
    expect(setGlobal).toHaveBeenCalledTimes(1);
  });

  it('keeps the progress for an operation that failed before the submission', () => {
    setTrade({ step: 'progress', operationId: 'op-1' });

    getHandler('apiUpdate')(currentGlobal, buildActions(), {
      type: 'perpsOperationUpdated', operation: buildOperation({ state: 'failed', error: 'PerpsQuoteExpired' }),
    });

    expect(currentGlobal.perps.trade?.step).toBe('progress');
  });

  it('forgets the receipts of operations the journal dropped', () => {
    setTrade({ step: 'receipt', operationId: 'op-2' });
    const kept = buildOperation({ id: 'op-2', state: 'completed' });
    setOperations(ACCOUNT_ID, [kept]);
    currentGlobal = addPerpsReceipt(currentGlobal, ACCOUNT_ID, 'op-1', buildQuote());
    currentGlobal = addPerpsReceipt(currentGlobal, ACCOUNT_ID, 'op-2', buildQuote());

    getHandler('apiUpdate')(currentGlobal, buildActions(), { type: 'perpsOperationUpdated', operation: kept });

    expect(Object.keys(currentGlobal.byAccountId[ACCOUNT_ID].perpsReceipts!)).toEqual(['op-2']);
  });
});

describe('acknowledgePerpsOperation', () => {
  const unknown = buildOperation({ state: 'unknown', stage: 'trade' });

  it('allows new orders and closes the status', async () => {
    setTrade({ step: 'status', kind: undefined, operationId: unknown.id });
    setOperations(ACCOUNT_ID, [unknown]);
    (callApiWithThrow as jest.Mock).mockResolvedValue({ ...unknown, acknowledgedAt: 2 });
    const actions = buildActions();

    await getHandler('acknowledgePerpsOperation')(currentGlobal, actions, { operationId: unknown.id });

    expect(actions.apiUpdate).toHaveBeenCalledWith({
      type: 'perpsOperationUpdated', operation: expect.objectContaining({ acknowledgedAt: 2 }),
    });
    expect(currentGlobal.perps.trade).toBeUndefined();
  });

  it('refuses an answer about another operation', async () => {
    setTrade({ step: 'status', kind: undefined, operationId: unknown.id });
    setOperations(ACCOUNT_ID, [unknown]);
    (callApiWithThrow as jest.Mock).mockResolvedValue({ ...unknown, assetId: 'hyperliquid:hl:ETH', acknowledgedAt: 2 });
    const actions = buildActions();

    await getHandler('acknowledgePerpsOperation')(currentGlobal, actions, { operationId: unknown.id });

    expect(actions.apiUpdate).not.toHaveBeenCalled();
    expect(currentGlobal.perps.trade).toMatchObject({ step: 'status', error: 'PerpsUnavailable' });
  });
});

describe('loadPerpsTradePreview', () => {
  it('loads the funding requirements when the account lacks funds', async () => {
    setTrade({ step: 'form' });
    (callApiWithThrow as jest.Mock).mockRejectedValue(new Error('PerpsInsufficientUsdc'));
    const actions = buildActions();

    await getHandler('loadPerpsTradePreview')(currentGlobal, actions);

    expect(currentGlobal.perps.trade?.error).toBe('PerpsInsufficientUsdc');
    expect(actions.loadPerpsFundingRequirements).toHaveBeenCalled();
  });

  it('tells at once that a pending operation blocks the change the quote turned out to be', async () => {
    setTrade({ step: 'form' });
    setOperations(ACCOUNT_ID, [buildOperation({ id: 'op-2', state: 'running', stage: 'trade' })]);
    (callApiWithThrow as jest.Mock).mockResolvedValue(buildQuote());

    await getHandler('loadPerpsTradePreview')(currentGlobal, buildActions());

    expect(currentGlobal.perps.trade).toMatchObject({ error: 'PerpsOperationPending', preview: { id: 'quote-1' } });
  });

  it('drops an estimate of the previous amount and waits for the estimate of the new one', async () => {
    setTrade({ step: 'form' });
    const reply = new Deferred<ApiPerpsQuote>();
    (callApiWithThrow as jest.Mock).mockReturnValue(reply.promise);

    const loading = getHandler('loadPerpsTradePreview')(currentGlobal, buildActions());
    currentGlobal = getHandler('setPerpsTradeAmount')(currentGlobal, buildActions(), { amount: '1000' }) as GlobalState;
    reply.resolve(buildQuote());
    await loading;

    expect(currentGlobal.perps.trade).toMatchObject({ amount: '1000', isPreviewLoading: true });
    expect(currentGlobal.perps.trade?.preview).toBeUndefined();
  });

  it('keeps the minimum the SDK named until the amount changes', async () => {
    setTrade({ step: 'form', amount: '5' });
    (callApiWithThrow as jest.Mock).mockRejectedValue(
      Object.assign(new Error('PerpsAmountTooSmall'), { minimumAmount: '10.004', isMinimumExclusive: false }),
    );

    await getHandler('loadPerpsTradePreview')(currentGlobal, buildActions());
    expect(currentGlobal.perps.trade).toMatchObject({
      error: 'PerpsAmountTooSmall', errorDetails: { minimumAmount: '10.004', isMinimumExclusive: false },
    });

    currentGlobal = getHandler('setPerpsTradeAmount')(currentGlobal, buildActions(), { amount: '20' }) as GlobalState;
    expect(currentGlobal.perps.trade?.errorDetails).toBeUndefined();
  });
});

describe('loadPerpsFundingRequirements', () => {
  it('drops the requirements of the previous amount, which would block the new one', async () => {
    setTrade({ step: 'form', amount: '1000' });
    const reply = new Deferred<ApiPerpsFundingRequirements>();
    (callApiWithThrow as jest.Mock).mockReturnValue(reply.promise);

    const loading = getHandler('loadPerpsFundingRequirements')(currentGlobal, buildActions());
    currentGlobal = getHandler('setPerpsTradeAmount')(currentGlobal, buildActions(), { amount: '10' }) as GlobalState;
    reply.resolve({ needsUsdc: true } as ApiPerpsFundingRequirements);
    await loading;

    expect(currentGlobal.perps.trade?.amount).toBe('10');
    expect(currentGlobal.perps.trade?.funding).toBeUndefined();
  });
});

describe('confirmPerpsTrade', () => {
  it('prepares the order again instead of asking for the password with an expired quote', () => {
    setTrade({ step: 'review', quote: buildQuote({ expiresAt: Date.now() - 1 }) });
    const actions = buildActions();

    getHandler('confirmPerpsTrade')(currentGlobal, actions);

    expect(actions.preparePerpsTrade).toHaveBeenCalled();
    expect(currentGlobal.perps.trade?.step).toBe('review');
  });
});

describe('reconcilePerpsOperations', () => {
  const running = {
    id: 'op-1', accountId: ACCOUNT_ID, assetId: 'hyperliquid:hl:BTC', kind: 'open', state: 'running',
    stage: 'trade', createdAt: 1,
  } as const;

  function setRunningOperation() {
    setTrade({});
    currentGlobal = {
      ...currentGlobal,
      byAccountId: { [ACCOUNT_ID]: { perpsOperations: { [running.id]: running } } },
    };
  }

  it.each([
    ['the SDK reads it', { ...running, state: 'unknown' }],
    ['the SDK does not answer', undefined],
  ])('reads an operation an earlier launch left running back as unknown when %s, as on iOS', async (_, reply) => {
    setRunningOperation();
    (callApi as jest.Mock).mockResolvedValue(reply);
    const actions = buildActions();

    await getHandler('reconcilePerpsOperations')(currentGlobal, actions);

    expect(callApi).toHaveBeenCalledWith('perpsReconcileOperation', ACCOUNT_ID, running);
    expect(actions.apiUpdate).toHaveBeenCalledWith({
      type: 'perpsOperationUpdated',
      operation: { ...running, state: 'unknown' },
    });
  });

  it('keeps an operation of an earlier popup running while the SDK still executes it', async () => {
    setRunningOperation();
    (callApi as jest.Mock).mockResolvedValue({ ...running });
    const actions = buildActions();

    await getHandler('reconcilePerpsOperations')(currentGlobal, actions);

    expect(actions.apiUpdate).not.toHaveBeenCalled();
  });

  it('ignores a restored record of another operation', async () => {
    setTrade({});
    const saved = {
      id: 'op-1', accountId: ACCOUNT_ID, assetId: 'hyperliquid:hl:BTC', kind: 'open', state: 'unknown',
      stage: 'trade', createdAt: 1,
    } as const;
    currentGlobal = {
      ...currentGlobal,
      byAccountId: { [ACCOUNT_ID]: { perpsOperations: { [saved.id]: saved } } },
    };
    (callApi as jest.Mock).mockResolvedValue({ ...saved, assetId: 'hyperliquid:hl:ETH', state: 'completed' });
    const actions = buildActions();

    await getHandler('reconcilePerpsOperations')(currentGlobal, actions);

    expect(actions.apiUpdate).not.toHaveBeenCalled();
  });
});

describe('the withdrawal of released funds', () => {
  const partial = {
    id: 'op-1', accountId: ACCOUNT_ID, assetId: 'hyperliquid:hl:BTC', kind: 'reduce', state: 'partial',
    stage: 'withdrawal', createdAt: 1,
  } as const;

  function setPartialOperation(step: PerpsTradeState['step']) {
    setTrade({ step, operationId: partial.id });
    currentGlobal = {
      ...currentGlobal,
      byAccountId: {
        [ACCOUNT_ID]: { ...currentGlobal.byAccountId[ACCOUNT_ID], perpsOperations: { [partial.id]: partial } },
      },
    };
  }

  it('asks to confirm the amount the SDK prepared', async () => {
    setPartialOperation('status');
    (callApiWithThrow as jest.Mock).mockResolvedValue('12.5');

    await getHandler('preparePerpsWithdrawal')(currentGlobal, buildActions(), { operationId: partial.id });

    expect(currentGlobal.perps.trade).toMatchObject({ step: 'withdrawal', withdrawalAmount: '12.5' });
  });

  it('prepares nothing while trading is unavailable', async () => {
    setPartialOperation('status');
    currentGlobal = updatePerpsSnapshot(currentGlobal, ACCOUNT_ID, {
      ...buildPerpsMarketFixture(),
      positions: [],
      totalEquity: '0',
      totalPnl: '0',
      timestamp: 2,
      unavailableDexs: [],
      tradingAvailability: { isAvailable: false, reason: 'PerpsTradingUnavailable' },
    });

    await getHandler('preparePerpsWithdrawal')(currentGlobal, buildActions(), { operationId: partial.id });

    expect(callApiWithThrow).not.toHaveBeenCalled();
    expect(currentGlobal.perps.trade).toMatchObject({ step: 'status', error: 'PerpsTradingUnavailable' });
  });

  it('keeps the operation partial when the retry fails before submission', async () => {
    setPartialOperation('withdrawalPassword');
    (persistPerpsSubmission as jest.Mock).mockImplementation(() => undefined);
    (callApiWithThrow as jest.Mock).mockRejectedValue(new Error('PerpsQuoteExpired'));
    const actions = buildActions();

    await getHandler('submitPerpsWithdrawal')(currentGlobal, actions, {
      operationId: partial.id,
      enclaveToken: 'token',
    });

    expect(persistPerpsSubmission).toHaveBeenCalledWith(expect.objectContaining({ state: 'running' }));
    expect(actions.apiUpdate).toHaveBeenCalledWith({
      type: 'perpsOperationUpdated',
      operation: expect.objectContaining({ state: 'partial' }),
    });
  });
});

describe('the withdrawal from the Hyperliquid balance', () => {
  const quote = {
    id: 'withdrawal-1',
    accountId: ACCOUNT_ID,
    balance: '1.5',
    amount: '1.47',
    bridgeFee: '0.2',
    receiveAmount: '1.27',
    destination: '0x1',
    expiresAt: Date.now() + 60_000,
  };

  function buildWithdrawalActions() {
    return { ...buildActions(), preparePerpsBalanceWithdrawal: jest.fn(), showError: jest.fn() };
  }

  it('shows a toast instead of the review when there is nothing to withdraw', async () => {
    setTrade({ step: 'balanceWithdrawal', kind: undefined });
    (callApiWithThrow as jest.Mock).mockRejectedValue(new Error('PerpsNothingToWithdraw'));
    const actions = buildWithdrawalActions();

    await getHandler('preparePerpsBalanceWithdrawal')(currentGlobal, actions);

    expect(currentGlobal.perps.trade).toBeUndefined();
    expect(actions.showError).toHaveBeenCalled();
  });

  it('asks to confirm a refreshed quote again', async () => {
    setTrade({ step: 'balanceWithdrawal', kind: undefined, balanceWithdrawal: { ...quote, expiresAt: 0 } });
    (callApiWithThrow as jest.Mock).mockResolvedValue({ ...quote, id: 'withdrawal-2' });

    await getHandler('preparePerpsBalanceWithdrawal')(currentGlobal, buildWithdrawalActions());

    expect(currentGlobal.perps.trade).toMatchObject({
      step: 'balanceWithdrawal',
      reviewNotice: 'PerpsBalanceWithdrawalUpdated',
      balanceWithdrawal: { id: 'withdrawal-2' },
    });
  });

  it('shows the status once Hyperliquid accepts the withdrawal', async () => {
    setTrade({ step: 'balanceWithdrawalPassword', kind: undefined, balanceWithdrawal: quote });
    (callApiWithThrow as jest.Mock).mockImplementation((_, ...args: string[]) => Promise.resolve(
      buildOperation({ id: args[3], assetId: 'USDC', kind: 'withdraw', state: 'completed' }),
    ));

    const actions = buildWithdrawalActions();

    await getHandler('submitPerpsBalanceWithdrawal')(currentGlobal, actions, { enclaveToken: 'token' });

    expect(callApiWithThrow).toHaveBeenCalledWith(
      'perpsExecuteBalanceWithdrawal', ACCOUNT_ID, 'token', quote.id, expect.any(String),
    );
    expect(currentGlobal.perps.trade?.step).toBe('status');
  });

  it('reviews a new quote when the balance changed before signing', async () => {
    setTrade({ step: 'balanceWithdrawalPassword', kind: undefined, balanceWithdrawal: quote });
    (callApiWithThrow as jest.Mock).mockImplementation((_, ...args: string[]) => Promise.resolve(
      buildOperation({ id: args[3], assetId: 'USDC', kind: 'withdraw', state: 'failed', error: 'PerpsReviewChanged' }),
    ));
    const actions = buildWithdrawalActions();

    await getHandler('submitPerpsBalanceWithdrawal')(currentGlobal, actions, { enclaveToken: 'token' });

    expect(currentGlobal.perps.trade?.step).toBe('balanceWithdrawal');
    expect(actions.preparePerpsBalanceWithdrawal).toHaveBeenCalled();
  });
});

describe('late SDK replies', () => {
  it('do not reach a trade started after the request', async () => {
    setTrade({ step: 'review', kind: 'close' });
    let resolveQuote: (quote: ApiPerpsQuote) => void = () => undefined;
    (callApiWithThrow as jest.Mock).mockReturnValue(new Promise((resolve) => {
      resolveQuote = resolve;
    }));

    const preparing = getHandler('preparePerpsTrade')(currentGlobal, buildActions());
    currentGlobal = {
      ...currentGlobal,
      perps: {
        ...currentGlobal.perps,
        trade: { ...currentGlobal.perps.trade!, id: 'trade-2', assetId: 'hyperliquid:hl:ETH', step: 'form' },
      },
    };
    resolveQuote(buildQuote({ kind: 'close' }));
    await preparing;

    expect(currentGlobal.perps.trade).toMatchObject({ id: 'trade-2', step: 'form' });
    expect(currentGlobal.perps.trade?.quote).toBeUndefined();
  });

  it('do not change the trade of another account after the switch', async () => {
    setTrade({ quote: buildQuote() });
    (persistPerpsSubmission as jest.Mock).mockImplementation(() => undefined);
    let resolveOperation: (value: unknown) => void = () => undefined;
    (callApiWithThrow as jest.Mock).mockReturnValue(new Promise((resolve) => {
      resolveOperation = resolve;
    }));
    const actions = buildActions();

    const submitting = getHandler('submitPerpsTrade')(currentGlobal, actions, { enclaveToken: 'token' });
    currentGlobal = {
      ...currentGlobal,
      currentAccountId: '1-mainnet',
      perps: { ...currentGlobal.perps, trade: { ...currentGlobal.perps.trade!, id: 'trade-2', step: 'form' } },
    };
    resolveOperation({ id: 'op', accountId: ACCOUNT_ID, state: 'completed' });
    await submitting;

    expect(currentGlobal.perps.trade).toMatchObject({ id: 'trade-2', step: 'form' });
    expect(actions.loadPerpsSnapshot).not.toHaveBeenCalled();
  });
});

describe('reconcilePerpsOperations', () => {
  it('reads back every unfinished operation except those running in this session', async () => {
    setTrade({});
    const earlier = buildOperation({ id: 'earlier', createdAt: 1 });
    const unknown = buildOperation({ id: 'unknown', state: 'unknown', createdAt: Date.now() + 60_000 });
    const running = buildOperation({ id: 'running', createdAt: Date.now() + 60_000 });
    const completed = buildOperation({ id: 'completed', state: 'completed' });
    setOperations('1-mainnet', [earlier, unknown, running, completed]);
    (callApi as jest.Mock).mockImplementation((_, __, operation: ApiPerpsOperation) => Promise.resolve(operation));

    await getHandler('reconcilePerpsOperations')(currentGlobal, buildActions());
    await getHandler('reconcilePerpsOperations')(currentGlobal, buildActions());

    expect(callApi).toHaveBeenCalledTimes(4);
    expect((callApi as jest.Mock).mock.calls.map(([, , operation]) => operation.id))
      .toEqual(['earlier', 'unknown', 'earlier', 'unknown']);
  });

  it('runs once while the previous run is in progress', async () => {
    setTrade({});
    setOperations('2-mainnet', [buildOperation({ id: 'earlier', state: 'unknown', createdAt: 1 })]);
    let resolve: (value?: unknown) => void = () => undefined;
    (callApi as jest.Mock).mockReturnValue(new Promise((done) => {
      resolve = done;
    }));

    const first = getHandler('reconcilePerpsOperations')(currentGlobal, buildActions());
    const second = getHandler('reconcilePerpsOperations')(currentGlobal, buildActions());
    resolve();
    await Promise.all([first, second]);

    expect(callApi).toHaveBeenCalledTimes(1);
  });
});

describe('switchPerpsTradeAccount', () => {
  const OTHER_ACCOUNT_ID = '1-mainnet';
  const PERPS_ACCOUNT = { type: 'mnemonic', byChain: { arbitrum: { address: '0x2' } } } as Account;

  function setSwitchTrade(trade: Partial<PerpsTradeState> = {}, otherAccount = PERPS_ACCOUNT) {
    setTrade({ step: 'selectAccount', ...trade });
    const accounts = currentGlobal.accounts!;
    currentGlobal = {
      ...currentGlobal,
      accounts: { ...accounts, byId: { ...accounts.byId, [OTHER_ACCOUNT_ID]: otherAccount } },
    };
  }

  // The chosen wallet becomes current, and its snapshot has not loaded yet
  function mockSwitch(cb?: NoneToVoidFunction) {
    (switchAccount as jest.Mock).mockImplementation((_, accountId: string) => {
      cb?.();
      currentGlobal = { ...currentGlobal, currentAccountId: accountId };
    });
  }

  it('moves the open form to the chosen wallet before the switch and starts it over', async () => {
    setSwitchTrade({ amount: '50' });
    let accountIdDuringSwitch: string | undefined;
    mockSwitch(() => {
      accountIdDuringSwitch = currentGlobal.perps.trade?.accountId;
    });
    const actions = buildActions();

    await getHandler('switchPerpsTradeAccount')(currentGlobal, actions, { accountId: OTHER_ACCOUNT_ID });

    expect(accountIdDuringSwitch).toBe(OTHER_ACCOUNT_ID);
    expect(currentGlobal.perps.trade).toMatchObject({
      accountId: OTHER_ACCOUNT_ID, kind: 'open', step: 'form', amount: '', assetId: 'hyperliquid:hl:BTC', side: 'long',
    });
    expect(currentGlobal.perps.trade?.id).not.toBe('trade-1');
    expect(actions.loadPerpsFundingRequirements).toHaveBeenCalledTimes(1);
  });

  it('leaves alone a form the user closed during the switch', async () => {
    setSwitchTrade();
    mockSwitch(() => {
      currentGlobal = { ...currentGlobal, perps: { ...currentGlobal.perps, trade: undefined } };
    });
    const actions = buildActions();

    await getHandler('switchPerpsTradeAccount')(currentGlobal, actions, { accountId: OTHER_ACCOUNT_ID });

    expect(currentGlobal.perps.trade).toBeUndefined();
    expect(actions.loadPerpsFundingRequirements).not.toHaveBeenCalled();
  });

  it('ignores another wallet while a switch is in progress', async () => {
    setSwitchTrade({ accountId: OTHER_ACCOUNT_ID });

    await getHandler('switchPerpsTradeAccount')(currentGlobal, buildActions(), { accountId: '2-mainnet' });

    expect(switchAccount).not.toHaveBeenCalled();
    expect(currentGlobal.perps.trade?.accountId).toBe(OTHER_ACCOUNT_ID);
  });

  it('ignores a trade other than a new position', async () => {
    setSwitchTrade({ kind: 'edit' });
    const trade = currentGlobal.perps.trade;

    await getHandler('switchPerpsTradeAccount')(currentGlobal, buildActions(), { accountId: OTHER_ACCOUNT_ID });

    expect(switchAccount).not.toHaveBeenCalled();
    expect(currentGlobal.perps.trade).toBe(trade);
  });

  it.each([
    ['a view-only wallet', OTHER_ACCOUNT_ID, { ...PERPS_ACCOUNT, type: 'view' }],
    ['a wallet without an Arbitrum address', OTHER_ACCOUNT_ID, { ...PERPS_ACCOUNT, byChain: {} }],
    ['a wallet that does not exist', '2-mainnet', PERPS_ACCOUNT],
  ] as const)('refuses %s', async (_, accountId, otherAccount) => {
    setSwitchTrade({}, otherAccount as Account);
    const trade = currentGlobal.perps.trade;

    await getHandler('switchPerpsTradeAccount')(currentGlobal, buildActions(), { accountId });

    expect(switchAccount).not.toHaveBeenCalled();
    expect(currentGlobal.perps.trade).toBe(trade);
  });

  it('goes back to the form with its values when the user picks the current wallet', async () => {
    setSwitchTrade({ amount: '50', leverage: 5 });

    await getHandler('switchPerpsTradeAccount')(currentGlobal, buildActions(), { accountId: ACCOUNT_ID });

    expect(switchAccount).not.toHaveBeenCalled();
    expect(currentGlobal.perps.trade).toMatchObject({ id: 'trade-1', step: 'form', amount: '50', leverage: 5 });
  });

  it('opens the status of an operation that blocks the new wallet', async () => {
    setSwitchTrade();
    currentGlobal = {
      ...currentGlobal,
      byAccountId: {
        ...currentGlobal.byAccountId,
        [OTHER_ACCOUNT_ID]: { perpsOperations: { 'op-1': buildOperation({ accountId: OTHER_ACCOUNT_ID }) } },
      },
    };
    mockSwitch();
    const actions = buildActions();

    await getHandler('switchPerpsTradeAccount')(currentGlobal, actions, { accountId: OTHER_ACCOUNT_ID });

    expect(actions.openPerpsOperation).toHaveBeenCalledWith({ operationId: 'op-1' });
    expect(actions.loadPerpsFundingRequirements).not.toHaveBeenCalled();
  });

  it('keeps the Back button of the wallet list away from the form that moved to another wallet', () => {
    setSwitchTrade({ accountId: OTHER_ACCOUNT_ID });

    expect(getHandler('setPerpsTradeStep')(currentGlobal, buildActions(), { step: 'form' })).toBeUndefined();
  });
});

describe('startPerpsTrade', () => {
  it('closes a position while a filled close of another market waits for its withdrawal', () => {
    setTrade({});
    const position = {
      id: `${ACCOUNT_ID}/hyperliquid:hl:BTC`,
      assetId: 'hyperliquid:hl:BTC',
      side: 'long',
      collateral: '10',
      raw: { leverage: { value: 3 } },
    } as unknown as ApiPerpsAccountPosition;
    const withoutTrade = { ...currentGlobal, perps: { ...currentGlobal.perps, trade: undefined } };
    currentGlobal = updatePerpsSnapshot(withoutTrade, ACCOUNT_ID, {
      ...currentGlobal.byAccountId[ACCOUNT_ID].perps!.snapshot!,
      ...buildPerpsMarketFixture(),
      positions: [position],
    });
    setOperations(ACCOUNT_ID, [buildOperation({
      kind: 'close', assetId: 'hyperliquid:hl:ETH', state: 'partial', orderStatus: 'filled', orderId: 1,
    })]);
    const actions = buildActions();

    getHandler('startPerpsTrade')(currentGlobal, actions, { assetId: 'hyperliquid:hl:BTC', kind: 'close' });

    expect(actions.openPerpsOperation).not.toHaveBeenCalled();
    expect(currentGlobal.perps.trade).toMatchObject({ kind: 'close', step: 'review' });
    expect(actions.preparePerpsTrade).toHaveBeenCalled();
  });
});

describe('loadPerpsHistory', () => {
  it.each([
    ['remembers that the account has never traded', undefined, false, false],
    ['remembers that the account has traded', undefined, true, true],
    ['keeps past trades after a page without them', true, false, true],
  ])('%s', async (_, hasActivityHistory, hasActivity, expected) => {
    setTrade({});
    currentGlobal = updateAccountPerps(currentGlobal, ACCOUNT_ID, { hasActivityHistory });
    (callApi as jest.Mock).mockResolvedValue({ fills: [], hasActivity });

    await getHandler('loadPerpsHistory')(currentGlobal, buildActions());

    expect(currentGlobal.byAccountId[ACCOUNT_ID].perps?.hasActivityHistory).toBe(expected);
  });

  it('keeps the next page that arrives during a refresh', async () => {
    setTrade({});
    const newer = { activityId: 'newer', time: 2 } as ApiPerpsFill;
    const older = { activityId: 'older', time: 1 } as ApiPerpsFill;
    currentGlobal = updateAccountPerps(currentGlobal, ACCOUNT_ID, {
      history: { fills: [newer], nextCursor: 'cursor-1', fetchedAt: 1 },
    });
    const nextPage = new Deferred<unknown>();
    const refresh = new Deferred<unknown>();
    (callApi as jest.Mock).mockImplementation((_, __, options?: { cursor: string }) => (
      options ? nextPage.promise : refresh.promise
    ));

    const loadingNextPage = getHandler('loadPerpsHistory')(currentGlobal, buildActions(), { isNextPage: true });
    const refreshing = getHandler('loadPerpsHistory')(currentGlobal, buildActions());
    nextPage.resolve({ fills: [older], nextCursor: 'cursor-2' });
    refresh.resolve({ fills: [newer], nextCursor: 'cursor-1' });
    await Promise.all([loadingNextPage, refreshing]);

    expect(currentGlobal.byAccountId[ACCOUNT_ID].perps?.history).toMatchObject({
      fills: [newer, older], nextCursor: 'cursor-2',
    });
  });

  it('ends the loading of the previous account after a switch', async () => {
    setTrade({});
    const otherAccountId = '1-mainnet';
    currentGlobal = {
      ...updateAccountPerps(currentGlobal, ACCOUNT_ID, { history: { fills: [], fetchedAt: 1 } }),
      accounts: {
        ...currentGlobal.accounts!,
        byId: {
          ...currentGlobal.accounts!.byId,
          [otherAccountId]: { type: 'mnemonic', byChain: { arbitrum: { address: '0x2' } } },
        },
      },
    };
    const reply = new Deferred<unknown>();
    (callApi as jest.Mock).mockReturnValueOnce(reply.promise).mockResolvedValueOnce({ fills: [] });

    const loadingPrevious = getHandler('loadPerpsHistory')(currentGlobal, buildActions());
    currentGlobal = { ...currentGlobal, currentAccountId: otherAccountId };
    await getHandler('loadPerpsHistory')(currentGlobal, buildActions());
    reply.resolve({ fills: [] });
    await loadingPrevious;

    expect(currentGlobal.byAccountId[ACCOUNT_ID].perps?.history?.isLoading).toBeUndefined();
  });
});

describe('loadPerpsMarketDetail', () => {
  const BTC_ID = 'hyperliquid:hl:BTC';

  function buildDetail(markPx: string) {
    return { asset: { id: BTC_ID, context: { markPx } }, history: { fills: [] } };
  }

  it('puts the market of the first detail into the catalogue, and a refresh leaves the catalogue alone', async () => {
    setTrade({});
    (callApi as jest.Mock).mockResolvedValueOnce(buildDetail('101')).mockResolvedValueOnce(buildDetail('102'));

    await getHandler('loadPerpsMarketDetail')(currentGlobal, buildActions(), { assetId: BTC_ID });
    const { market } = currentGlobal.perps;
    await getHandler('loadPerpsMarketDetail')(currentGlobal, buildActions(), { assetId: BTC_ID });

    expect(market?.assets[0]).toMatchObject({ context: { markPx: '101' } });
    expect(currentGlobal.perps.market).toBe(market);
    expect(currentGlobal.byAccountId[ACCOUNT_ID].perps?.marketDetailById?.[BTC_ID]?.asset)
      .toMatchObject({ context: { markPx: '102' } });
  });
});

describe('updatePerpsAssets', () => {
  it.each([
    ['rebuilds the market from a newer catalogue', 'en', 2, true],
    ['skips the catalogue the market is built from', 'en', 1, false],
    ['skips a catalogue of another language', 'ru', 2, false],
  ])('%s', (_, langCode, fetchedAt, shouldLoad) => {
    setTrade({});
    currentGlobal = updatePerpsMarket(currentGlobal, buildPerpsMarketFixture(), 'en');
    const actions = buildActions();

    getHandler('apiUpdate')(currentGlobal, actions, {
      type: 'updatePerpsAssets', assets: { assetsByChain: {}, sections: [] }, langCode, fetchedAt,
    });

    expect(actions.loadPerpsMarket).toHaveBeenCalledTimes(shouldLoad ? 1 : 0);
  });
});

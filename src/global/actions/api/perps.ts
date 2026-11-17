import type {
  ApiPerpsDraftRequest,
  ApiPerpsMarketAsset,
  ApiPerpsOperation,
  ApiPerpsOperationKind,
  ApiPerpsPositionSide,
  ApiPerpsQuote,
} from '../../../api/types';
import type { PerpsLeverageEstimate, PerpsTradeState, PerpsTradeStep } from '../../types';

import { IS_PERPS_SUPPORTED } from '../../../config';
import { Big } from '../../../lib/big.js';
import { areDeepEqual } from '../../../util/areDeepEqual';
import { MINUTE } from '../../../util/dateFormat';
import generateUniqueId from '../../../util/generateUniqueId';
import { pick } from '../../../util/iteratees';
import { getTranslation } from '../../../util/langProvider';
import { callApi, callApiWithThrow } from '../../../api';
import { PERPS_BALANCE_WITHDRAWAL_ASSET_ID } from '../../../api/common/perps';
import { withEnclaveSessionRelease } from '../../helpers/enclave';
import {
  buildPerpsDraft,
  findPerpsOperationFill,
  findPerpsReceiptPosition,
  getIsPerpsAccountDisabled,
  getPerpsErrorCode,
  getPerpsErrorDetails,
  getPerpsErrorKey,
  isPerpsAmountEqual,
  PERPS_AMOUNT_DECIMALS,
  PERPS_DEFAULT_LEVERAGE,
} from '../../helpers/perps';
import { getPerpsOperationAfterSubmissionError, persistPerpsSubmission } from '../../helpers/perpsSubmission';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import {
  addPerpsReceipt,
  clearPerpsTrade,
  MARKET_SNAPSHOT_KEYS,
  markPerpsMarketLoadFailed,
  markPerpsSnapshotLoadFailed,
  mergePerpsHistory,
  prunePerpsReceipts,
  setPerpsTrade,
  updateAccountPerps,
  updatePerpsAssetChart,
  updatePerpsAssetDetail,
  updatePerpsChart,
  updatePerpsMarket,
  updatePerpsMarketAsset,
  updatePerpsMarketDetail,
  updatePerpsReceipt,
  updatePerpsSnapshot,
  updatePerpsTrade,
} from '../../reducers';
import {
  isPerpsChartStale,
  isPerpsOperationBlocking,
  selectAccountPerpsOperation,
  selectAccountState,
  selectCanReadPerps,
  selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountPerps,
  selectCurrentAccountPerpsOperation,
  selectCurrentAccountPerpsPosition,
  selectCurrentAccountState,
  selectNetworkAccounts,
  selectPerpsBlockingOperation,
  selectPerpsMarketAsset,
  selectPerpsTradeBlockReason,
} from '../../selectors';
import { switchAccount } from './auth';

// As often as the iOS app refreshes the catalogue
const PERPS_MARKET_REFRESH_INTERVAL = MINUTE;
const OUTDATED_QUOTE_ERRORS = ['PerpsQuoteExpired', 'PerpsReviewChanged'];

let marketRequestId = 0;
let snapshotRequestId = 0;
let previewRequestId = 0;
let fundingRequestId = 0;
let prepareRequestId = 0;
const chartRequestIds = new Map<string, number>();
// Keyed by the account and the page, so a refresh of the first page never drops the next page or another account
const historyRequestIds = new Map<string, number>();
const detailRequestIds = new Map<string, number>();
// The asset page of Perps Lab reads its market apart from the Futures screens
const assetDetailRequestIds = new Map<string, number>();
const assetChartRequestIds = new Map<string, number>();
const leverageRequestIds = new Map<number, number>();
const reconcilingAccountIds = new Set<string>();
const acknowledgingOperationIds = new Set<string>();
// Withdrawals of earlier operations that this session retries
const executingOperationIds = new Set<string>();
// The inputs of the last receipt details by operation, since the snapshot refreshes far more often than they change
const receiptDetailsInputs = new Map<string, unknown[]>();
const SESSION_STARTED_AT = Date.now();

addActionHandler('loadPerpsMarket', async (global, _, payload) => {
  if (!IS_PERPS_SUPPORTED) return;

  // The SDK fetches the catalogue on its own when its cache holds another language
  const { langCode } = global.settings;
  const requestId = ++marketRequestId;

  const market = await callApi('perpsGetMarketSnapshot', langCode, payload?.force ? { force: true } : undefined);
  if (requestId !== marketRequestId) return;

  global = getGlobal();
  setGlobal(market ? updatePerpsMarket(global, market, langCode) : markPerpsMarketLoadFailed(global));
});

addActionHandler('loadPerpsSnapshot', async (global) => {
  const accountId = selectCurrentAccountId(global);
  if (!accountId || !selectCanReadPerps(global)) return;

  // The positions take mark prices and liquidation warnings from the catalogue, which the SDK keeps until a refresh
  const { market } = global.perps;
  const isMarketOutdated = market && Date.now() - market.assetsFetchedAt >= PERPS_MARKET_REFRESH_INTERVAL;

  const { langCode } = global.settings;
  const requestId = ++snapshotRequestId;
  const snapshot = await callApi(
    'perpsGetSnapshot', accountId, langCode, isMarketOutdated ? { forceAssets: true } : undefined,
  );
  if (requestId !== snapshotRequestId) return;

  global = getGlobal();
  if (!snapshot) {
    setGlobal(markPerpsSnapshotLoadFailed(global, accountId));
    return;
  }

  global = updatePerpsSnapshot(global, accountId, snapshot);
  if (!global.perps.market || snapshot.assetsFetchedAt > global.perps.market.assetsFetchedAt) {
    global = updatePerpsMarket(
      global,
      pick(snapshot, MARKET_SNAPSHOT_KEYS),
      langCode,
    );
  }
  setGlobal(global);
});

addActionHandler('loadPerpsCandles', async (global, _, { assetId, period }) => {
  if (!isPerpsChartStale(global.perps.chartsByAssetId[assetId]?.[period])) return;

  const requestKey = `${assetId}:${period}`;
  const requestId = (chartRequestIds.get(requestKey) ?? 0) + 1;
  chartRequestIds.set(requestKey, requestId);

  const points = await callApi('perpsGetCandles', assetId, period);
  if (chartRequestIds.get(requestKey) !== requestId) return;

  global = getGlobal();
  // `perpsGetCandles` throws unless every point is a pair of a time and a price, so `map` only types them as pairs
  setGlobal(updatePerpsChart(global, assetId, period, points
    ? { points: points.map(([time, price]) => [time, price]), fetchedAt: Date.now() }
    : { ...global.perps.chartsByAssetId[assetId]?.[period], hasError: true }));
});

addActionHandler('loadPerpsMarketDetail', async (global, _, { assetId, isNextPage }) => {
  const accountId = selectCurrentAccountId(global);
  if (!accountId || !selectCanReadPerps(global)) return;

  const current = selectCurrentAccountPerps(global)?.marketDetailById?.[assetId];
  const cursor = current?.history?.nextCursor;
  if (isNextPage && (!cursor || current?.history?.isLoading)) return;

  const requestKey = `${accountId}:${assetId}:${Boolean(isNextPage)}`;
  const requestId = (detailRequestIds.get(requestKey) ?? 0) + 1;
  detailRequestIds.set(requestKey, requestId);

  if (current?.history) {
    setGlobal(updatePerpsMarketDetail(global, accountId, assetId, {
      history: { ...current.history, isLoading: true },
    }));
  }

  const detail = await callApi('perpsGetAssetDetail', accountId, assetId, isNextPage ? { cursor } : undefined);
  if (detailRequestIds.get(requestKey) !== requestId) return;

  global = getGlobal();
  const loaded = selectAccountState(global, accountId)?.perps?.marketDetailById?.[assetId];
  if (!detail) {
    setGlobal(updatePerpsMarketDetail(global, accountId, assetId, {
      hasError: true,
      history: loaded?.history && { ...loaded.history, isLoading: undefined },
    }));
    return;
  }

  // The detail brings fresher prices and funding than the catalogue. Only the first load puts them there, since the
  // screen polls the detail every 20 seconds, and each new catalogue rebuilds everything derived from it.
  if (!isNextPage && !loaded?.asset) {
    global = updatePerpsMarketAsset(global, detail.asset);
  }
  global = updatePerpsMarketDetail(global, accountId, assetId, {
    asset: detail.asset,
    history: mergePerpsHistory(detail.history, loaded?.history, isNextPage),
    hasError: undefined,
  });
  setGlobal(global);
});

addActionHandler('loadPerpsHistory', async (global, _, payload) => {
  const accountId = selectCurrentAccountId(global);
  if (!accountId || !selectCanReadPerps(global)) return;

  const isNextPage = payload?.isNextPage;
  const current = selectCurrentAccountPerps(global)?.history;
  const cursor = current?.nextCursor;
  if (isNextPage && (!cursor || current?.isLoading)) return;

  const requestKey = `${accountId}:${Boolean(isNextPage)}`;
  const requestId = (historyRequestIds.get(requestKey) ?? 0) + 1;
  historyRequestIds.set(requestKey, requestId);

  if (current) {
    setGlobal(updateAccountPerps(global, accountId, { history: { ...current, isLoading: true } }));
  }

  const page = await callApi('perpsGetActivityHistory', accountId, isNextPage ? { cursor } : undefined);
  if (historyRequestIds.get(requestKey) !== requestId) return;

  global = getGlobal();
  const accountPerps = selectAccountState(global, accountId)?.perps;
  const loaded = accountPerps?.history;
  if (!page) {
    setGlobal(updateAccountPerps(global, accountId, {
      history: loaded
        ? { ...loaded, isLoading: undefined, hasError: true }
        : { fills: [], hasError: true },
    }));
    return;
  }

  setGlobal(updateAccountPerps(global, accountId, {
    history: mergePerpsHistory(page, loaded, isNextPage),
    // Past trades are never forgotten, so a page without them cannot bring the onboarding back
    hasActivityHistory: accountPerps?.hasActivityHistory || page.hasActivity,
  }));
});

/**
 * Reads the outcome of unfinished operations back from the SDK. A running operation of this session is executing,
 * and the SDK reports it on its own. If this action read such an operation before the SDK registers it, the operation
 * would get an unknown outcome and its order would never be sent.
 */
addActionHandler('reconcilePerpsOperations', async (global, actions) => {
  const accountId = selectCurrentAccountId(global);
  if (!accountId || reconcilingAccountIds.has(accountId)) return;

  const operations = Object.values(selectCurrentAccountState(global)?.perpsOperations ?? {}).filter((operation) => (
    operation.state !== 'completed'
    && operation.state !== 'failed'
    && !(operation.state === 'running' && operation.createdAt >= SESSION_STARTED_AT)
    && !executingOperationIds.has(operation.id)
  ));
  if (!operations.length) return;

  reconcilingAccountIds.add(accountId);
  try {
    for (const operation of operations) {
      // The SDK reads a running operation it does not execute as unknown. In the extension it may still execute one
      // that an earlier popup started, so the state changes only with its answer.
      let restored = await callApi('perpsReconcileOperation', accountId, operation);
      // Without the answer, an operation that an earlier session left running has an unknown outcome
      if (!restored && operation.state === 'running') restored = { ...operation, state: 'unknown' };
      // The user may have changed the operation meanwhile, and that change wins
      const current = selectAccountPerpsOperation(getGlobal(), accountId, operation.id);
      if (
        restored && current === operation && isSameOperation(restored, operation) && !areDeepEqual(restored, operation)
      ) {
        actions.apiUpdate({ type: 'perpsOperationUpdated', operation: restored });
      }
    }
  } finally {
    reconcilingAccountIds.delete(accountId);
  }
});

addActionHandler('startPerpsTrade', (global, actions, payload) => {
  const accountId = selectCurrentAccountId(global);
  const { assetId } = payload;
  const asset = selectPerpsMarketAsset(global, assetId);

  // A running operation keeps its modal until the result arrives
  if (!accountId || !asset || global.perps.trade?.step === 'progress') return;

  const position = selectCurrentAccountPerpsPosition(global, assetId);
  if (payload.kind === 'open' && position) {
    actions.openFuturesPosition({ assetId });
    return;
  }

  // An edit passes the check as a reduce, since a filled close of another market does not block a reduce.
  // Confirmation checks the kind of the actual quote, so an increase still waits for that close.
  const orderKind = payload.kind === 'edit' ? 'reduce' : payload.kind;
  const blockingOperation = selectPerpsBlockingOperation(global, assetId, orderKind);
  if (blockingOperation) {
    actions.openPerpsOperation({ operationId: blockingOperation.id });
    return;
  }

  if (selectPerpsTradeBlockReason(global, assetId, orderKind) !== undefined) return;

  if (payload.kind === 'open') {
    setGlobal(setPerpsTrade(global, buildOpenTrade(accountId, asset, payload.side, 'form')));
    actions.loadPerpsFundingRequirements();
    return;
  }

  if (!position) return;

  const leverage = position.raw.leverage.value;

  if (payload.kind === 'close') {
    setGlobal(setPerpsTrade(global, {
      id: generateUniqueId(),
      accountId,
      kind: 'close',
      step: 'review',
      assetId,
      side: position.side,
      amount: '0',
      leverage,
    }));
    actions.preparePerpsTrade();
    return;
  }

  const currentAmount = Big(position.collateral).round(PERPS_AMOUNT_DECIMALS, Big.roundDown).toFixed();

  setGlobal(setPerpsTrade(global, {
    id: generateUniqueId(),
    accountId,
    kind: 'edit',
    step: 'form',
    assetId,
    side: position.side,
    amount: currentAmount,
    currentAmount,
    currentCollateral: position.collateral,
    leverage,
  }));
  actions.loadPerpsFundingRequirements();
});

addActionHandler('switchPerpsTradeAccount', async (global, actions, { accountId }) => {
  const { trade } = global.perps;
  // The trade already belongs to another wallet while a switch is in progress
  if (
    trade?.kind !== 'open'
    || trade.step !== 'selectAccount'
    || trade.accountId !== selectCurrentAccountId(global)
  ) {
    return;
  }

  if (accountId === trade.accountId) {
    setGlobal(updatePerpsTrade(global, { step: 'form' }));
    return;
  }

  const account = selectNetworkAccounts(global)?.[accountId];
  const asset = selectPerpsMarketAsset(global, trade.assetId);
  if (!account || getIsPerpsAccountDisabled(account) || !asset) return;

  // The form moves first, so `resetPerpsAccountScreens` leaves it open. The amount and the leverage start over, as on
  // iOS, because they were chosen against the balance of the previous wallet.
  const movedTrade = buildOpenTrade(accountId, asset, trade.side, 'selectAccount');
  setGlobal(setPerpsTrade(global, movedTrade));

  await switchAccount(getGlobal(), accountId);

  global = getGlobal();
  if (global.perps.trade?.id !== movedTrade.id) return;

  const blockingOperation = selectPerpsBlockingOperation(global, trade.assetId, 'open');
  if (blockingOperation) {
    actions.openPerpsOperation({ operationId: blockingOperation.id });
    return;
  }

  // The snapshot of the new wallet usually loads after the switch, and until then the reason is an empty string. The
  // form stays open meanwhile, since Futures loads the snapshot of the new wallet on its own.
  if (selectPerpsTradeBlockReason(global, trade.assetId, 'open')) {
    setGlobal(clearPerpsTrade(global));
    return;
  }

  setGlobal(updatePerpsTrade(global, { step: 'form' }));
  actions.loadPerpsFundingRequirements();
});

addActionHandler('openPerpsOperation', (global, _, { operationId }) => {
  const accountId = selectCurrentAccountId(global);
  const operation = selectCurrentAccountPerpsOperation(global, operationId);
  if (!accountId || !operation || global.perps.trade?.step === 'progress') return;

  const position = selectCurrentAccountPerpsPosition(global, operation.assetId);

  setGlobal(setPerpsTrade(global, {
    id: generateUniqueId(),
    accountId,
    step: 'status',
    assetId: operation.assetId,
    // The status screen reads only the operation, so without a position the side and the leverage are placeholders
    side: position?.side ?? 'long',
    amount: '',
    leverage: position?.raw.leverage.value ?? PERPS_DEFAULT_LEVERAGE,
    operationId,
  }));
});

addActionHandler('loadPerpsTradePreview', async (global, actions) => {
  const { trade } = global.perps;
  if (!trade?.kind || trade.step !== 'form') return;

  const isUnchangedEdit = trade.kind === 'edit' && isPerpsAmountEqual(trade.amount, trade.currentAmount);
  const requestId = ++previewRequestId;

  if (!trade.amount || Big(trade.amount).lte(0) || isUnchangedEdit) {
    setGlobal(updatePerpsTrade(global, { preview: undefined, isPreviewLoading: undefined, error: undefined }));
    return;
  }

  setGlobal(updatePerpsTrade(global, { isPreviewLoading: true }));

  const draft = buildPerpsDraft(trade);

  try {
    const preview = await callApiWithThrow('perpsPreviewOrder', trade.accountId, draft);
    // A change of the draft schedules a new estimate, which ends the loading
    if (requestId !== previewRequestId || !isCurrentDraft(trade.id, draft)) return;
    if (!preview || !isQuoteOfTrade(preview, trade)) throw new Error('PerpsUnavailable');

    // The market or a pending operation may forbid the change the quote turned out to be, so the form tells it now
    // rather than after the Review screen
    const blockReason = preview.kind !== 'unchanged'
      ? selectPerpsTradeBlockReason(getGlobal(), trade.assetId, preview.kind)
      : undefined;

    updateCurrentTrade(trade.id, {
      preview,
      isPreviewLoading: undefined,
      error: blockReason,
      ...(preview.fundingRequirements && { funding: preview.fundingRequirements }),
    });
  } catch (err) {
    if (requestId !== previewRequestId || !isCurrentDraft(trade.id, draft)) return;

    const error = getPerpsErrorCode(err);
    updateCurrentTrade(trade.id, {
      preview: undefined, isPreviewLoading: undefined, error, errorDetails: getPerpsErrorDetails(err),
    });
    // The requirements tell what to buy, so the form shows the notice with a purchase instead of the error
    if (error.startsWith('PerpsInsufficient')) actions.loadPerpsFundingRequirements();
  }
});

addActionHandler('resetPerpsTradeAmount', (global, actions) => {
  const { trade } = global.perps;
  if (trade?.kind !== 'edit') return;

  setGlobal(updatePerpsTrade(global, {
    amount: trade.currentAmount!,
    fraction: undefined,
    preview: undefined,
    error: undefined,
  }));
  actions.loadPerpsFundingRequirements();
});

addActionHandler('loadPerpsFundingRequirements', async (global) => {
  const { trade } = global.perps;
  if (!trade?.kind || trade.kind === 'close') return;

  const requestId = ++fundingRequestId;
  const draft = buildPerpsDraft(trade);

  try {
    const funding = await callApiWithThrow('perpsGetFundingRequirements', trade.accountId, draft);
    // An estimate of the new amount brings its own requirements, which a late reply for the old amount must not
    // replace with a payment notice
    if (requestId !== fundingRequestId || !isCurrentDraft(trade.id, draft)) return;
    if (!funding) throw new Error('PerpsUnavailable');

    updateCurrentTrade(trade.id, { funding, fundingError: undefined });
  } catch (err) {
    if (requestId !== fundingRequestId || !isCurrentDraft(trade.id, draft)) return;

    updateCurrentTrade(trade.id, { fundingError: getPerpsErrorCode(err) });
  }
});

addActionHandler('loadPerpsLeverageEstimate', async (global, _, { leverage }) => {
  const { trade } = global.perps;
  if (!trade?.kind) return;

  const requestId = (leverageRequestIds.get(leverage) ?? 0) + 1;
  leverageRequestIds.set(leverage, requestId);

  const draft = buildPerpsDraft(trade, { leverage });
  let estimate: PerpsLeverageEstimate;

  try {
    const result = await callApiWithThrow('perpsGetLeverageEstimate', trade.accountId, draft);
    estimate = { liquidationPrice: result?.liquidationPrice };
  } catch {
    // The sheet keeps a dash instead of the values
    return;
  }

  // A new amount, share or funding source clears the estimates, which a reply for the old draft must not restore
  if (leverageRequestIds.get(leverage) !== requestId || !isCurrentDraft(trade.id, draft, leverage)) return;

  const current = getGlobal().perps.trade!;
  updateCurrentTrade(trade.id, {
    leverageEstimates: { ...current.leverageEstimates, [leverage]: estimate },
  });
});

addActionHandler('preparePerpsTrade', async (global, actions) => {
  const { trade } = global.perps;
  if (!trade?.kind) return;

  const requestId = ++prepareRequestId;
  // A quote the Review screen already shows is replaced, so the screen tells the user once the new one arrives
  const isRefresh = trade.step === 'review' && Boolean(trade.quote);
  setGlobal(updatePerpsTrade(global, { isPreparing: true, error: undefined }));

  const draft = buildPerpsDraft(trade);

  try {
    const quote = await callApiWithThrow('perpsPrepareOrder', trade.accountId, draft);
    if (requestId !== prepareRequestId) return;
    // The user changed the draft meanwhile, so the Review screen waits for another tap with the new one
    if (!isCurrentDraft(trade.id, draft)) {
      updateCurrentTrade(trade.id, { isPreparing: undefined });
      return;
    }
    if (!quote || !isQuoteOfTrade(quote, trade)) throw new Error('PerpsUnavailable');

    if (quote.kind === 'unchanged') {
      updateCurrentTrade(trade.id, { isPreparing: undefined, error: 'PerpsUnchanged' });
      return;
    }

    // The Review screen confirms exactly the change it shows, so a position that now needs another change goes back
    // to the form
    if (isRefresh && quote.kind !== trade.quote!.kind) {
      updateCurrentTrade(trade.id, { isPreparing: undefined, error: 'PerpsPositionChanged' });
      return;
    }

    // The user went back to the form or opened the wallet list meanwhile, so the quote is dropped. Only the Review
    // screen that a new tap opens lets the user confirm a quote.
    if (getGlobal().perps.trade?.step !== trade.step) {
      updateCurrentTrade(trade.id, { isPreparing: undefined });
      return;
    }

    updateCurrentTrade(trade.id, {
      step: 'review',
      quote,
      isPreparing: undefined,
      reviewNotice: isRefresh ? 'PerpsReviewUpdated' : undefined,
      ...(quote.fundingRequirements && { funding: quote.fundingRequirements }),
    });
  } catch (err) {
    if (requestId !== prepareRequestId) return;
    if (!isCurrentDraft(trade.id, draft)) {
      updateCurrentTrade(trade.id, { isPreparing: undefined });
      return;
    }

    const error = getPerpsErrorCode(err);
    // A close opens its Review screen with the first quote, so a failure before it is a toast on the position screen
    if (trade.kind === 'close' && !trade.quote) {
      setGlobal(clearPerpsTrade(getGlobal()));
      actions.showError({ error: getTranslation(getPerpsErrorKey(error)) });
      return;
    }

    updateCurrentTrade(trade.id, { isPreparing: undefined, error, errorDetails: getPerpsErrorDetails(err) });
  }
});

addActionHandler('confirmPerpsTrade', (global, actions) => {
  const { trade } = global.perps;
  if (trade?.step !== 'review' || !trade.quote || trade.isPreparing) return;
  if (!isQuoteOfTrade(trade.quote, trade)) return;

  const { kind } = trade.quote;
  const blockReason = selectPerpsTradeBlockReason(global, trade.assetId, kind === 'unchanged' ? undefined : kind);
  if (blockReason !== undefined) {
    setGlobal(updatePerpsTrade(global, { error: blockReason }));
    return;
  }

  // The password authorizes exactly the quote on screen, so an expired one is reviewed again first
  if (trade.quote.expiresAt <= Date.now()) {
    actions.preparePerpsTrade();
    return;
  }

  setGlobal(updatePerpsTrade(global, { step: 'password', reviewNotice: undefined, error: undefined }));
});

addActionHandler('submitPerpsTrade', withEnclaveSessionRelease(async (global, actions, { enclaveToken }) => {
  const { trade } = global.perps;
  const quote = trade?.quote;

  // The trade leaves the password screen when its operation starts, so a repeated confirmation does nothing
  if (trade?.step !== 'password' || !quote || quote.kind === 'unchanged' || !isQuoteOfTrade(quote, trade)) return;

  // The password authorized exactly this quote, so one that expired meanwhile goes back to the Review screen
  if (quote.expiresAt <= Date.now()) {
    setGlobal(updatePerpsTrade(global, { step: 'review' }));
    actions.preparePerpsTrade();
    return;
  }

  const { id: tradeId, accountId } = trade;
  const operation = buildInitialOperation(accountId, quote, quote.kind);

  // The receipt shows the signed quote after a restart too, so the quote is saved together with the operation
  setGlobal(addPerpsReceipt(global, accountId, operation.id, quote));
  try {
    persistPerpsSubmission(operation);
  } catch (err) {
    setGlobal(prunePerpsReceipts(getGlobal(), accountId));
    updateCurrentTrade(tradeId, { step: 'review', error: getPerpsErrorCode(err) });
    return;
  }

  updateCurrentTrade(tradeId, { step: 'progress', operationId: operation.id, error: undefined });

  let result: ApiPerpsOperation | undefined;
  try {
    result = await callApiWithThrow('perpsExecuteReviewedOrder', accountId, enclaveToken, quote.id, operation.id);
    if (!result || !isSameOperation(result, operation)) throw new Error('PerpsExecutionUnknown');
  } catch (err) {
    const saved = selectAccountPerpsOperation(getGlobal(), accountId, operation.id) ?? operation;
    result = getPerpsOperationAfterSubmissionError(saved, getPerpsErrorCode(err), false);
  }

  // The handler that stores the operation saves the cache, which may throw, and the progress must still end
  try {
    actions.apiUpdate({ type: 'perpsOperationUpdated', operation: result });
  } finally {
    // The SDK sends nothing for a quote the market or the position outdated, so the Review screen shows a new quote
    if (result.state === 'failed' && OUTDATED_QUOTE_ERRORS.some((code) => result.error?.includes(code))) {
      if (updateProgressTrade(tradeId, { step: 'review', operationId: undefined })) {
        actions.preparePerpsTrade();
      }
    } else {
      // A rejected quote is spent, so the Review screen keeps its figures with the reason, and the user goes back
      updateProgressTrade(tradeId, result.state === 'failed'
        ? { step: 'review', operationId: undefined, error: result.error ?? 'PerpsOrderRejected' }
        : { step: 'receipt' });
    }
  }

  if (selectCurrentAccountId(getGlobal()) === accountId) {
    actions.loadPerpsSnapshot();
    actions.loadPerpsHistory();
  }
}));

addActionHandler('loadPerpsReceiptDetails', async (global, _, { operationId }) => {
  const accountId = selectCurrentAccountId(global);
  const accountState = selectCurrentAccountState(global);
  const operation = accountState?.perpsOperations?.[operationId];
  const receipt = accountState?.perpsReceipts?.[operationId];
  if (!accountId || !operation || !receipt) return;

  const fill = findPerpsOperationFill(operation, accountState?.perps?.history?.fills);
  const position = receipt.position
    ?? findPerpsReceiptPosition(operation, receipt.quote, accountState?.perps?.snapshot, fill);
  if (position !== receipt.position) {
    setGlobal(updatePerpsReceipt(global, accountId, operationId, { position }));
  }

  // The inputs are compared by content, since each reload of the history and the snapshot brings new objects
  const inputs = [operation, position, fill];
  if (receipt.details && areDeepEqual(receiptDetailsInputs.get(operationId), inputs)) return;

  const details = await callApi('perpsGetReceiptDetails', {
    quote: receipt.quote,
    operation,
    position,
    fill,
  });
  if (!details) return;

  receiptDetailsInputs.set(operationId, inputs);
  setGlobal(updatePerpsReceipt(getGlobal(), accountId, operationId, { details }));
});

addActionHandler('acknowledgePerpsOperation', async (global, actions, { operationId }) => {
  const accountId = selectCurrentAccountId(global);
  const operation = accountId && selectAccountPerpsOperation(global, accountId, operationId);
  if (!accountId || !operation || acknowledgingOperationIds.has(operationId)) return;

  const tradeId = global.perps.trade?.id;
  acknowledgingOperationIds.add(operationId);
  if (tradeId) updateCurrentTrade(tradeId, { isPreparing: true, error: undefined });

  try {
    const acknowledged = await callApiWithThrow('perpsAcknowledgeOperation', accountId, operation);
    if (!acknowledged || !isSameOperation(acknowledged, operation) || isPerpsOperationBlocking(acknowledged)) {
      throw new Error('PerpsUnavailable');
    }

    // A reconciliation may have resolved the operation meanwhile, and its result is newer
    const current = selectAccountPerpsOperation(getGlobal(), accountId, operationId);
    if (current === operation) {
      actions.apiUpdate({ type: 'perpsOperationUpdated', operation: acknowledged });
    } else if (current && isPerpsOperationBlocking(current)) {
      throw new Error('PerpsOperationPending');
    }
    // New orders are allowed again, so the status has nothing more to show
    if (tradeId && getGlobal().perps.trade?.id === tradeId) setGlobal(clearPerpsTrade(getGlobal()));
  } catch (err) {
    const error = getPerpsErrorCode(err);
    if (!tradeId || !updateCurrentTrade(tradeId, { isPreparing: undefined, error })) {
      actions.showError({ error: getTranslation(getPerpsErrorKey(error)) });
    }
  } finally {
    acknowledgingOperationIds.delete(operationId);
  }
});

addActionHandler('preparePerpsWithdrawal', async (global, _, { operationId }) => {
  const accountId = selectCurrentAccountId(global);
  const { trade } = global.perps;
  if (!accountId || trade?.step !== 'status' || trade.accountId !== accountId || trade.isPreparing) return;

  // The withdrawal is signed like an order, so it needs trading to be available
  const availability = selectCurrentAccountPerps(global)?.snapshot?.tradingAvailability;
  if (!availability?.isAvailable) {
    setGlobal(updatePerpsTrade(global, { error: availability?.reason ?? 'PerpsUnavailable' }));
    return;
  }

  setGlobal(updatePerpsTrade(global, { isPreparing: true, error: undefined }));

  try {
    const withdrawalAmount = await callApiWithThrow('perpsPrepareWithdrawal', accountId, operationId);
    if (!withdrawalAmount) throw new Error('PerpsUnavailable');

    updateCurrentTrade(trade.id, {
      step: 'withdrawal',
      operationId,
      withdrawalAmount,
      isPreparing: undefined,
    });
  } catch (err) {
    updateCurrentTrade(trade.id, { isPreparing: undefined, error: getPerpsErrorCode(err) });
  }
});

addActionHandler('submitPerpsWithdrawal', withEnclaveSessionRelease(async (
  global, actions, { operationId, enclaveToken },
) => {
  const accountId = selectCurrentAccountId(global);
  const { trade } = global.perps;
  const saved = accountId && selectAccountPerpsOperation(global, accountId, operationId);
  if (!accountId || !saved || trade?.step !== 'withdrawalPassword' || trade.accountId !== accountId) return;

  const operation: ApiPerpsOperation = { ...saved, state: 'running', stage: 'preparing' };

  try {
    persistPerpsSubmission(operation);
  } catch (err) {
    updateCurrentTrade(trade.id, { step: 'withdrawal', error: getPerpsErrorCode(err) });
    return;
  }

  updateCurrentTrade(trade.id, { step: 'progress', error: undefined });

  let result: ApiPerpsOperation;
  executingOperationIds.add(operationId);
  try {
    const retried = await callApiWithThrow('perpsRetryWithdrawal', accountId, enclaveToken, operationId);
    if (!retried) throw new Error('PerpsExecutionUnknown');
    result = retried;
  } catch (err) {
    const current = selectAccountPerpsOperation(getGlobal(), accountId, operationId) ?? operation;
    result = getPerpsOperationAfterSubmissionError(current, getPerpsErrorCode(err), true);
  }

  // The handler that stores the operation saves the cache, which may throw, and the retry must still end
  try {
    actions.apiUpdate({ type: 'perpsOperationUpdated', operation: result });
  } finally {
    executingOperationIds.delete(operationId);
    updateCurrentTrade(trade.id, { step: 'status' });
  }

  if (selectCurrentAccountId(getGlobal()) === accountId) {
    actions.loadPerpsSnapshot();
  }
}));

addActionHandler('startPerpsBalanceWithdrawal', (global, actions) => {
  const accountId = selectCurrentAccountId(global);
  if (!accountId || global.perps.trade?.step === 'progress') return;

  // An unresolved operation holds the balance, so the tap opens its status instead
  const blockingOperation = selectPerpsBlockingOperation(global);
  if (blockingOperation) {
    actions.openPerpsOperation({ operationId: blockingOperation.id });
    return;
  }

  if (!selectCurrentAccountPerps(global)?.snapshot?.tradingAvailability?.isAvailable) return;

  setGlobal(setPerpsTrade(global, {
    id: generateUniqueId(),
    accountId,
    step: 'balanceWithdrawal',
    // A withdrawal involves no market, so the side and the leverage are placeholders
    assetId: PERPS_BALANCE_WITHDRAWAL_ASSET_ID,
    side: 'long',
    amount: '',
    leverage: PERPS_DEFAULT_LEVERAGE,
  }));
  actions.preparePerpsBalanceWithdrawal();
});

// The review opens with the first quote, so a failure before it is a toast
addActionHandler('preparePerpsBalanceWithdrawal', async (global, actions) => {
  const { trade } = global.perps;
  if (trade?.step !== 'balanceWithdrawal' || trade.isPreparing) return;

  const isRefresh = Boolean(trade.balanceWithdrawal);
  setGlobal(updatePerpsTrade(global, { isPreparing: true, error: undefined }));

  try {
    const quote = await callApiWithThrow('perpsPrepareBalanceWithdrawal', trade.accountId);
    if (!quote || quote.accountId !== trade.accountId) throw new Error('PerpsUnavailable');

    // An operation that started meanwhile holds the balance, so the review does not open
    if (!isRefresh && selectPerpsBlockingOperation(getGlobal())) {
      if (getGlobal().perps.trade?.id === trade.id) setGlobal(clearPerpsTrade(getGlobal()));
      return;
    }

    updateCurrentTrade(trade.id, {
      balanceWithdrawal: quote,
      isPreparing: undefined,
      reviewNotice: isRefresh ? 'PerpsBalanceWithdrawalUpdated' : undefined,
    });
  } catch (err) {
    const error = getPerpsErrorCode(err);
    if (isRefresh) {
      updateCurrentTrade(trade.id, { isPreparing: undefined, error });
    } else if (getGlobal().perps.trade?.id === trade.id) {
      setGlobal(clearPerpsTrade(getGlobal()));
      actions.showError({ error: getTranslation(getPerpsErrorKey(error)) });
    }
  }
});

addActionHandler('confirmPerpsBalanceWithdrawal', (global, actions) => {
  const { trade } = global.perps;
  const quote = trade?.balanceWithdrawal;
  if (trade?.step !== 'balanceWithdrawal' || !quote || trade.isPreparing) return;

  const availability = selectCurrentAccountPerps(global)?.snapshot?.tradingAvailability;
  if (!availability?.isAvailable || selectPerpsBlockingOperation(global)) {
    setGlobal(updatePerpsTrade(global, { error: availability?.reason ?? 'PerpsOperationPending' }));
    return;
  }

  // The password authorizes exactly the withdrawal on screen, and the SDK holds a quote for a minute only
  if (quote.expiresAt <= Date.now()) {
    actions.preparePerpsBalanceWithdrawal();
    return;
  }

  setGlobal(updatePerpsTrade(global, { step: 'balanceWithdrawalPassword', reviewNotice: undefined, error: undefined }));
});

addActionHandler('submitPerpsBalanceWithdrawal', withEnclaveSessionRelease(async (
  global, actions, { enclaveToken },
) => {
  const { trade } = global.perps;
  const quote = trade?.balanceWithdrawal;

  // The trade leaves the password screen when its operation starts, so a repeated confirmation does nothing
  if (trade?.step !== 'balanceWithdrawalPassword' || !quote) return;

  if (quote.expiresAt <= Date.now()) {
    setGlobal(updatePerpsTrade(global, { step: 'balanceWithdrawal' }));
    actions.preparePerpsBalanceWithdrawal();
    return;
  }

  const { id: tradeId, accountId } = trade;
  const operation: ApiPerpsOperation = {
    id: generateUniqueId(),
    accountId,
    assetId: PERPS_BALANCE_WITHDRAWAL_ASSET_ID,
    kind: 'withdraw',
    state: 'running',
    stage: 'preparing',
    createdAt: Date.now(),
    withdrawalAmount: quote.amount,
    balanceWithdrawal: quote,
  };

  try {
    persistPerpsSubmission(operation);
  } catch (err) {
    updateCurrentTrade(tradeId, { step: 'balanceWithdrawal', error: getPerpsErrorCode(err) });
    return;
  }

  updateCurrentTrade(tradeId, { step: 'progress', operationId: operation.id, error: undefined });

  let result: ApiPerpsOperation | undefined;
  try {
    result = await callApiWithThrow('perpsExecuteBalanceWithdrawal', accountId, enclaveToken, quote.id, operation.id);
    if (!result || !isSameOperation(result, operation)) throw new Error('PerpsExecutionUnknown');
  } catch (err) {
    const saved = selectAccountPerpsOperation(getGlobal(), accountId, operation.id) ?? operation;
    result = getPerpsOperationAfterSubmissionError(saved, getPerpsErrorCode(err), false);
  }

  // The handler that stores the operation saves the cache, which may throw, and the progress must still end
  try {
    actions.apiUpdate({ type: 'perpsOperationUpdated', operation: result });
  } finally {
    // Nothing was signed for an outdated quote, so the review shows a new one
    if (result.state === 'failed' && OUTDATED_QUOTE_ERRORS.some((code) => result.error?.includes(code))) {
      if (updateProgressTrade(tradeId, { step: 'balanceWithdrawal', operationId: undefined })) {
        actions.preparePerpsBalanceWithdrawal();
      }
    } else {
      // A rejected withdrawal moved nothing, so the review shows why, and the user can close it
      updateProgressTrade(tradeId, result.state === 'failed'
        ? { step: 'balanceWithdrawal', operationId: undefined, error: result.error ?? 'PerpsWithdrawalRejected' }
        : { step: 'status' });
    }
  }

  if (selectCurrentAccountId(getGlobal()) === accountId) {
    actions.loadPerpsSnapshot();
  }
}));

addActionHandler('loadPerpsAsset', async (global, _actions, { assetId }) => {
  const accountId = selectCurrentAccountId(global);
  const address = selectCurrentAccount(global)?.byChain.arbitrum?.address;
  if (!accountId || !address) return;

  const requestKey = `${accountId}:${assetId}`;
  const requestId = (assetDetailRequestIds.get(requestKey) ?? 0) + 1;
  assetDetailRequestIds.set(requestKey, requestId);

  const result = await callApi('perpsGetAsset', {
    address,
    asset: assetId,
    chain: 'hyperliquid',
  });

  if (assetDetailRequestIds.get(requestKey) !== requestId) return;

  global = getGlobal();
  if (selectCurrentAccountId(global) !== accountId) return;

  setGlobal(updatePerpsAssetDetail(
    global,
    accountId,
    assetId,
    result
      ? { data: result, hasError: undefined, fetchedAt: Date.now() }
      : { hasError: true },
  ));
});

addActionHandler('loadPerpsAssetChart', async (global, _actions, { assetId, period }) => {
  const requestKey = `${assetId}:${period}`;
  const requestId = (assetChartRequestIds.get(requestKey) ?? 0) + 1;
  assetChartRequestIds.set(requestKey, requestId);

  const history = await callApi('perpsGetAssetChart', {
    asset: assetId,
    chain: 'hyperliquid',
    period,
  });

  if (assetChartRequestIds.get(requestKey) !== requestId) return;

  global = getGlobal();
  if (!history) {
    if (!global.perpsAssetChart?.byAssetId[assetId]?.[period]) {
      setGlobal(updatePerpsAssetChart(global, assetId, { [period]: [] }));
    }

    return;
  }

  setGlobal(updatePerpsAssetChart(global, assetId, { [period]: history }));
});

function buildOpenTrade(
  accountId: string,
  asset: ApiPerpsMarketAsset,
  side: ApiPerpsPositionSide,
  step: PerpsTradeStep,
): PerpsTradeState {
  return {
    id: generateUniqueId(),
    accountId,
    kind: 'open',
    step,
    assetId: asset.id,
    side,
    amount: '',
    leverage: Math.min(PERPS_DEFAULT_LEVERAGE, asset.maxLeverage),
  };
}

/** Applies a late result only to the trade that requested it. The user may have closed it or started another. */
function updateCurrentTrade(tradeId: string, update: Partial<PerpsTradeState>) {
  const global = getGlobal();
  if (global.perps.trade?.id !== tradeId) return false;

  setGlobal(updatePerpsTrade(global, update));
  return true;
}

/** Applies the result of an execution while its progress is on screen. Its receipt or status may have replaced it. */
function updateProgressTrade(tradeId: string, update: Partial<PerpsTradeState>) {
  const { trade } = getGlobal().perps;
  if (trade?.id !== tradeId || trade.step !== 'progress') return false;

  return updateCurrentTrade(tradeId, update);
}

/** The trade is still open with the inputs of `draft`, so a reply for that draft belongs to it */
function isCurrentDraft(tradeId: string, draft: ApiPerpsDraftRequest, leverage?: number) {
  const current = getGlobal().perps.trade;

  return current?.id === tradeId && areDeepEqual(buildPerpsDraft(current, { leverage }), draft);
}

function isQuoteOfTrade(quote: ApiPerpsQuote, { accountId, assetId }: PerpsTradeState) {
  return quote.accountId === accountId && quote.assetId === assetId;
}

function isSameOperation(operation: ApiPerpsOperation, other: ApiPerpsOperation) {
  return operation.id === other.id
    && operation.accountId === other.accountId
    && operation.assetId === other.assetId
    && operation.kind === other.kind;
}

function buildInitialOperation(
  accountId: string,
  quote: ApiPerpsQuote,
  kind: ApiPerpsOperationKind,
): ApiPerpsOperation {
  return {
    id: generateUniqueId(),
    accountId,
    assetId: quote.assetId,
    kind,
    state: 'running',
    stage: 'preparing',
    createdAt: Date.now(),
    withdrawalRequestedAmount: quote.kind === 'reduce' && quote.modify?.depositAmount !== undefined
      ? String(quote.modify.depositAmount)
      : undefined,
  };
}

import React, { memo, useEffect, useRef, useState } from '../../lib/teact/teact';
import { getActions, getGlobal, withGlobal } from '../../global';

import type {
  ApiPerpsActivitiesSnapshot,
  ApiPerpsAssetsSnapshot,
  ApiPerpsClearinghouseState,
  ApiPerpsListedAsset,
  ApiPerpsOperation,
  ApiPerpsPositionSide,
  ApiPerpsQuote,
  ApiPerpsTradeActivity,
  ApiPerpsTradeIntent,
} from '../../api/types';
import type { GlobalPerpsAssets, PerpsBalanceDepositProgress } from '../../global/types';

import { getPerpsOperationAfterSubmissionError, persistPerpsSubmission } from '../../global/helpers/perps';
import buildClassName from '../../util/buildClassName';
import { callApi, callApiWithThrow } from '../../api';
import {
  getPerpsCctpCreditedAmountUsdc,
  PERPS_CCTP_FORWARD_FEE_USDC,
} from '../../api/common/perps';
import usePerpsModifyEstimate from './usePerpsModifyEstimate';
import usePerpsOpenEstimate from './usePerpsOpenEstimate';

import useFlag from '../../hooks/useFlag';
import useLastCallback from '../../hooks/useLastCallback';

import Button from '../ui/Button';
import Input from '../ui/Input';
import Modal from '../ui/Modal';
import PasswordForm from '../ui/PasswordForm';
import PerpsAssetPage from './PerpsAssetPage';

import styles from './PerpsLabModal.module.scss';

interface OwnProps {
  isOpen: boolean;
  onClose: NoneToVoidFunction;
}

interface StateProps {
  accountId?: string;
  arbAddress?: string;
  perpsOperations?: Record<string, ApiPerpsOperation>;
  perpsBalanceDeposit?: PerpsBalanceDepositProgress;
  perpsAssets?: GlobalPerpsAssets;
  currentPerpsAssetId?: string;
}

type LabStep = 'main' | 'password-order' | 'password-withdrawal' | 'password-balance';
type ModifyMode = 'add' | 'reduce' | 'leverage';
type BalanceAction = 'deposit' | 'withdraw' | 'open';

function isPositionOpen(szi: string): boolean {
  const size = Number.parseFloat(szi);
  return Number.isFinite(size) && size !== 0;
}

const DEFAULT_ASSET = 'hyperliquid:hl:BTC';

const PERPS_LAB_ACTIVITIES_PREVIEW_LIMIT = 40;
const DEFAULT_DEPOSIT = '10';
const DEFAULT_LEVERAGE = '10';
const DEFAULT_MODIFY_NOTIONAL = '10.2';
const DEFAULT_BALANCE_AMOUNT = '10.2';

function appendLog(prev: string, line: string) {
  const stamp = new Date().toISOString().slice(11, 19);
  return prev ? `${prev}\n[${stamp}] ${line}` : `[${stamp}] ${line}`;
}

function getListedAssets(snapshot: ApiPerpsAssetsSnapshot): ApiPerpsListedAsset[] {
  return snapshot.filter((entry) => !entry.isDelisted);
}

function countListedAssets(snapshot?: ApiPerpsAssetsSnapshot): number {
  if (!snapshot) {
    return 0;
  }
  return getListedAssets(snapshot).length;
}

function countDexBooks(snapshot: ApiPerpsAssetsSnapshot): number {
  return new Set(snapshot.map((entry) => entry.dex)).size;
}

function formatDexBadge(dex: string): string {
  return dex || 'HL';
}

function formatPerpsActivityTime(timeMs: number): string {
  if (!timeMs) {
    return '—';
  }

  return new Date(timeMs).toLocaleString();
}

function formatPerpsActivitySummary(item: ApiPerpsTradeActivity): string {
  const range = item.positionSizeBefore !== undefined && item.positionSizeAfter !== undefined
    ? `${item.positionSizeBefore} → ${item.positionSizeAfter}`
    : undefined;
  return [item.side, item.size, range, item.transferredAmount && `${item.transferredAmount} USDC`]
    .filter(Boolean)
    .join(' · ');
}

function findListedAssetById(
  snapshot: ApiPerpsAssetsSnapshot | undefined,
  assetId: string,
): ApiPerpsListedAsset | undefined {
  if (!snapshot) {
    return undefined;
  }

  return snapshot.find((entry) => entry.id === assetId);
}

function parseLeverageInput(value: string): number {
  const trimmed = value.trim();
  if (!trimmed) {
    return Number.NaN;
  }

  const leverage = Number(trimmed);
  if (!Number.isFinite(leverage) || !Number.isInteger(leverage) || leverage < 1) {
    return Number.NaN;
  }

  return leverage;
}

function parsePerpsLimit(value: string | undefined): number | undefined {
  if (value === undefined) return undefined;

  const amount = Number(value);
  return Number.isFinite(amount) && amount >= 0 ? amount : undefined;
}

function parseUsdcAmount(value: string): number {
  const amount = Number(value.trim());
  return Number.isFinite(amount) ? amount : Number.NaN;
}

function balancePasswordCopy(
  action: BalanceAction,
  amount: string,
  assetId: string,
  openSide: ApiPerpsPositionSide,
  leverage: number,
  isCrossMargin: boolean,
) {
  if (action === 'deposit') {
    return {
      title: `Deposit ${amount} USDC to the perps balance`,
      submitLabel: 'Deposit',
      notice: 'USDC leaves Arbitrum. No position is opened.',
    };
  }
  if (action === 'withdraw') {
    return {
      title: `Withdraw ${amount} USDC to this wallet`,
      submitLabel: 'Withdraw',
      notice: 'USDC returns to this wallet. No position is changed.',
    };
  }
  return {
    title: `Open ${openSide} ${assetId} · ${leverage}x ${isCrossMargin ? 'cross' : 'isolated'} · ${amount} USDC margin`,
    submitLabel: 'Open',
    notice: 'Margin is taken from the perps balance. No Arbitrum deposit is sent.',
  };
}

function formatPerpsDepositGas(estimate: ApiPerpsQuote) {
  if (estimate.estimatedNetworkFeeUsdc !== undefined) {
    return `${estimate.estimatedNetworkFeeUsdc} USDC`;
  }
  if (estimate.estimatedNetworkFeeEth !== undefined) {
    return `${estimate.estimatedNetworkFeeEth} ETH`;
  }
  return undefined;
}

function renderPerpsDepositGas(estimate: ApiPerpsQuote) {
  const gas = formatPerpsDepositGas(estimate);
  if (!gas) return undefined;

  return (
    <div>
      <div className={styles.summaryLabel}>Network fee</div>
      <div>{gas}</div>
    </div>
  );
}

function PerpsEstimateCard({ title, estimate }: { title: string; estimate: ApiPerpsQuote }) {
  return (
    <div className={styles.summary}>
      <div className={styles.summaryTitle}>{title}</div>
      <div>
        <div className={styles.summaryLabel}>Position value</div>
        <div>{estimate.notional} USDC</div>
      </div>
      <div>
        <div className={styles.summaryLabel}>Size</div>
        <div>{estimate.size}</div>
      </div>
      {estimate.estimatedCollateral !== undefined && (
        <div>
          <div className={styles.summaryLabel}>Estimated invested</div>
          <div>{estimate.estimatedCollateral} USDC</div>
        </div>
      )}
      <div>
        <div className={styles.summaryLabel}>Liquidation price</div>
        <div>{estimate.estimatedLiquidationPrice ?? '—'}</div>
      </div>
      {renderPerpsDepositGas(estimate)}
    </div>
  );
}

const PerpsListedAssetIcon = memo(({ symbol, image }: { symbol: string; image: string | null }) => {
  const [isImageError, markImageError] = useFlag(false);
  const letter = symbol.slice(0, 1) || '?';
  const showImage = Boolean(image) && !isImageError;

  if (showImage && image) {
    return (
      <img
        src={image}
        alt=""
        className={styles.assetIcon}
        draggable={false}
        onError={markImageError}
      />
    );
  }

  return (
    <div className={buildClassName(styles.assetIcon, styles.assetIconFallback)} aria-hidden>
      {letter}
    </div>
  );
});

function PerpsLabModal({
  isOpen,
  onClose,
  accountId,
  arbAddress,
  perpsOperations,
  perpsBalanceDeposit,
  perpsAssets,
  currentPerpsAssetId,
}: OwnProps & StateProps) {
  const { apiUpdate, closePerpsAsset, openPerpsAsset } = getActions();
  const [step, setStep] = useState<LabStep>('main');
  const activeAccountRef = useRef<string | undefined>();
  activeAccountRef.current = isOpen ? accountId : undefined;
  const [positionsState, setPositionsState] = useState<ApiPerpsClearinghouseState | undefined>();
  const [activitiesSnapshot, setActivitiesSnapshot] = useState<ApiPerpsActivitiesSnapshot | undefined>();
  const [assetsSnapshot, setAssetsSnapshot] = useState<ApiPerpsAssetsSnapshot | undefined>();
  const [isLoadingPositions, markLoadingPositions, unmarkLoadingPositions] = useFlag(false);
  const [isLoadingActivities, markLoadingActivities, unmarkLoadingActivities] = useFlag(false);
  const [isLoadingAssets, markLoadingAssets, unmarkLoadingAssets] = useFlag(false);
  const [isPreparing, markPreparing, unmarkPreparing] = useFlag(false);
  const [isSubmitting, markSubmitting, unmarkSubmitting] = useFlag(false);
  const [restoredAccountId, setRestoredAccountId] = useState<string | undefined>();
  const [reviewedQuote, setReviewedQuote] = useState<ApiPerpsQuote | undefined>();
  const [operationId, setOperationId] = useState<string | undefined>();
  const [submittedOperationId, setSubmittedOperationId] = useState<string | undefined>();
  const [withdrawalAmount, setWithdrawalAmount] = useState<string | undefined>();
  const [error, setError] = useState<string | undefined>();
  const [log, setLog] = useState('');
  const isBusy = isPreparing || isSubmitting || restoredAccountId !== accountId;

  const [asset, setAsset] = useState(DEFAULT_ASSET);
  const [side, setSide] = useState<ApiPerpsPositionSide>('long');
  const [depositAmount, setDepositAmount] = useState(DEFAULT_DEPOSIT);
  const [leverageAmount, setLeverageAmount] = useState(DEFAULT_LEVERAGE);
  const [modifyNotional, setModifyNotional] = useState(DEFAULT_MODIFY_NOTIONAL);
  const [balanceAmount, setBalanceAmount] = useState(DEFAULT_BALANCE_AMOUNT);
  const [balanceAction, setBalanceAction] = useState<BalanceAction | undefined>();
  const [isCross, setIsCross] = useState(false);

  const depositGross = Number(depositAmount);
  const modifyNotionalUsd = Number(modifyNotional);
  const positionNotionalUsd = Number.isFinite(depositGross)
    ? getPerpsCctpCreditedAmountUsdc(depositGross)
    : undefined;

  useEffect(() => {
    if (!isOpen) {
      setStep('main');
      setError(undefined);
      setLog('');
      setPositionsState(undefined);
      setActivitiesSnapshot(undefined);
      setAssetsSnapshot(undefined);
      setReviewedQuote(undefined);
      setOperationId(undefined);
      setSubmittedOperationId(undefined);
      setWithdrawalAmount(undefined);
      setBalanceAction(undefined);
      if (currentPerpsAssetId) closePerpsAsset();
    }
  }, [isOpen, closePerpsAsset, currentPerpsAssetId]);

  const fetchAssets = useLastCallback(async () => {
    setError(undefined);
    markLoadingAssets();

    try {
      // This client does not poll the catalogue, so every load replaces the SDK's copy.
      const result = await callApi('perpsGetAssets', getGlobal().settings.langCode, { force: true });

      if (!result) {
        setError('Failed to load perps assets (transport error).');
        return;
      }

      const snapshot = result.assetsByChain.hyperliquid;
      setAssetsSnapshot(snapshot);
      setLog((prev) => appendLog(prev, snapshot?.length
        ? `Loaded ${countListedAssets(snapshot)} listed asset(s) across ${countDexBooks(snapshot)} DEX book(s)`
        : 'No Hyperliquid assets snapshot returned'));
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      unmarkLoadingAssets();
    }
  });

  const fetchPositions = useLastCallback(async () => {
    if (!arbAddress) {
      setError('Arbitrum wallet address is required for Hyperliquid perps.');
      return;
    }

    setError(undefined);
    markLoadingPositions();

    try {
      const result = await callApi('perpsGetPositions', {
        addressByChain: { hyperliquid: arbAddress },
      });

      if (!result) {
        setError('Failed to load positions (transport error).');
        return;
      }

      const state = result.positionsByChain.hyperliquid;
      setPositionsState(state);
      setLog((prev) => appendLog(prev, state
        ? [
          `Loaded ${state.assetPositions.length} position(s)`,
          `Spot USDC total ${state.spotUsdcTotal ?? '0'}`,
          `Spot USDC available ${state.spotUsdcAvailable ?? '0'}`,
        ].join(', ')
        : 'No Hyperliquid clearinghouse state returned'));
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      unmarkLoadingPositions();
    }
  });

  const fetchActivities = useLastCallback(async () => {
    if (!arbAddress) {
      setError('Arbitrum wallet address is required for Hyperliquid perps.');
      return;
    }

    setError(undefined);
    markLoadingActivities();

    try {
      const result = await callApi('perpsGetActivities', {
        addressByChain: { hyperliquid: arbAddress },
      });

      if (!result) {
        setError('Failed to load activities (transport error).');
        return;
      }

      const snapshot = result.activitiesByChain.hyperliquid;
      setActivitiesSnapshot(snapshot);
      setLog((prev) => appendLog(prev, snapshot
        ? `Loaded ${snapshot.activities.length} Hyperliquid activity row(s) from /perps/activities`
        : 'No Hyperliquid activities snapshot returned'));
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      unmarkLoadingActivities();
    }
  });

  useEffect(() => {
    if (isOpen) {
      void fetchAssets();
      if (arbAddress) {
        void fetchPositions();
        void fetchActivities();
      }
    }
  }, [isOpen, arbAddress, fetchAssets, fetchPositions, fetchActivities]);

  const depositOpenedAtRef = useRef(0);
  useEffect(() => {
    if (isOpen) depositOpenedAtRef.current = Date.now();
  }, [isOpen]);

  useEffect(() => {
    if (!isOpen || !perpsBalanceDeposit || perpsBalanceDeposit.at < depositOpenedAtRef.current) return;
    const hash = perpsBalanceDeposit.depositTxHash ? ` · tx ${perpsBalanceDeposit.depositTxHash}` : '';
    const line = perpsBalanceDeposit.phase === 'failed'
      ? `Deposit to balance · ${perpsBalanceDeposit.error ?? 'failed'}${hash}`
      : perpsBalanceDeposit.phase === 'complete'
        ? `Deposit to balance · ${perpsBalanceDeposit.status ?? 'ok'}${hash}`
        : `Deposit to balance · bridge transaction sent${hash}`;
    setLog((prev) => appendLog(prev, line));
    if (perpsBalanceDeposit.phase === 'failed') setError(perpsBalanceDeposit.error);
    if (perpsBalanceDeposit.phase !== 'submitted' && arbAddress) {
      void fetchPositions();
      void fetchActivities();
    }
  }, [isOpen, perpsBalanceDeposit, arbAddress, fetchPositions, fetchActivities]);

  const restoreOperations = useLastCallback(async () => {
    if (!accountId) return false;
    setRestoredAccountId(undefined);
    const saved = getGlobal().byAccountId[accountId]?.perpsOperations;
    try {
      for (const operation of Object.values(saved ?? {})) {
        const restored = await callApiWithThrow('perpsReconcileOperation', accountId, operation);
        if (!restored) throw new Error('Could not restore the previous operation. Refresh before trading.');
        apiUpdate({ type: 'perpsOperationUpdated', operation: restored });
      }
      if (activeAccountRef.current !== accountId) return false;
      setRestoredAccountId(accountId);
      return true;
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      return false;
    }
  });

  useEffect(() => {
    setStep('main');
    setReviewedQuote(undefined);
    setOperationId(undefined);
    setSubmittedOperationId(undefined);
    setWithdrawalAmount(undefined);
    setBalanceAction(undefined);
    if (isOpen) void restoreOperations();
  }, [isOpen, accountId, restoreOperations]);

  const operation = submittedOperationId ? perpsOperations?.[submittedOperationId] : undefined;
  useEffect(() => {
    if (!isOpen || !operation || operation.accountId !== accountId) return;
    if (operation.stage !== 'preparing' || operation.state !== 'running') {
      setStep('main');
      unmarkSubmitting();
    }
    setLog((prev) => appendLog(prev, [
      `${operation.kind} ${operation.assetId}: ${operation.state} (${operation.stage})`,
      operation.depositTxHash && `Deposit: ${operation.depositTxHash}`,
      operation.orderId !== undefined && `Order: ${operation.orderId}`,
      operation.error,
    ].filter(Boolean).join(' · ')));
    if (operation.state !== 'running') {
      void fetchPositions();
      void fetchActivities();
    }
  }, [isOpen, accountId, operation, fetchPositions, fetchActivities, unmarkSubmitting]);

  const listedCatalogue = perpsAssets?.assetsByChain.hyperliquid ?? assetsSnapshot;
  const hyperliquidLimits = perpsAssets?.limitsByChain?.hyperliquid;
  const minOpenDepositUsdc = parsePerpsLimit(hyperliquidLimits?.minOpenDepositUsdc);
  const minIncreaseDepositUsdc = parsePerpsLimit(hyperliquidLimits?.minIncreaseDepositUsdc);
  const minPositionMarginUsdc = parsePerpsLimit(hyperliquidLimits?.minPositionMarginUsdc);
  const selectedListedAsset = findListedAssetById(listedCatalogue, asset);
  const assetHasPosition = Boolean(
    selectedListedAsset
    && positionsState?.assetPositions.some((entry) => (
      entry.position.coin === selectedListedAsset.name && isPositionOpen(entry.position.szi)
    )),
  );
  const maxLeverage = selectedListedAsset?.maxLeverage;
  const parsedLeverage = parseLeverageInput(leverageAmount);
  const {
    estimate: openEstimate,
    error: openEstimateError,
    isEstimating: isEstimatingOpen,
  } = usePerpsOpenEstimate({
    isActive: isOpen && step === 'main',
    accountId,
    asset,
    side,
    depositAmount,
    leverage: parsedLeverage,
  });
  const {
    add: addEstimate,
    addError,
    reduce: reduceEstimate,
    reduceError,
    leverageDeposit,
    leverageEstimate,
    leverageError,
    isEstimating: isEstimatingModify,
  } = usePerpsModifyEstimate({
    isActive: isOpen && step === 'main' && assetHasPosition,
    accountId,
    asset,
    depositAmount: modifyNotional,
    leverage: parsedLeverage,
    maxLeverage,
  });
  const balanceUsd = parseUsdcAmount(balanceAmount);
  const canMoveBalance = Number.isFinite(balanceUsd) && balanceUsd > PERPS_CCTP_FORWARD_FEE_USDC;
  const canOpenFromBalance = Number.isFinite(balanceUsd)
    && balanceUsd > 0
    && Boolean(selectedListedAsset)
    && !assetHasPosition
    && Number.isFinite(parsedLeverage)
    && (maxLeverage === undefined || parsedLeverage <= maxLeverage);

  const prepareOrder = useLastCallback(async (intent: ApiPerpsTradeIntent) => {
    if (!accountId || isBusy) return;
    markPreparing();
    setError(undefined);
    setReviewedQuote(undefined);
    setSubmittedOperationId(undefined);
    try {
      if (!await restoreOperations()) return;
      const quote = await callApiWithThrow('perpsPrepareOrder', accountId, intent);
      if (!quote) throw new Error('Review unavailable. Please try again.');
      if (activeAccountRef.current !== accountId) return;
      if (quote.kind === 'unchanged') throw new Error('The position is unchanged.');
      setReviewedQuote(quote);
      setOperationId(crypto.randomUUID());
      setStep('password-order');
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      unmarkPreparing();
    }
  });

  const handleOpenClick = useLastCallback(() => prepareOrder({
    kind: 'open', assetId: asset.trim(), side, depositAmount, leverage: parsedLeverage,
  }));

  const handleOpenFromAsset = useLastCallback((entry: ApiPerpsListedAsset, openSide: ApiPerpsPositionSide) => {
    setAsset(entry.id);
    setSide(openSide);
    void prepareOrder({ kind: 'open', assetId: entry.id, side: openSide, depositAmount, leverage: parsedLeverage });
  });

  const handleCloseClick = useLastCallback((assetId: string) => prepareOrder({ kind: 'close', assetId }));

  const handleModifyClick = useLastCallback((assetId: string, mode: ModifyMode) => prepareOrder(mode === 'leverage'
    ? { kind: 'leverage', assetId, leverage: parsedLeverage }
    : { kind: mode === 'add' ? 'increase' : 'reduce', assetId, amount: modifyNotional }));

  const handlePasswordBack = useLastCallback(() => {
    setReviewedQuote(undefined);
    setWithdrawalAmount(undefined);
    setBalanceAction(undefined);
    setStep('main');
  });

  const handleBalanceClick = useLastCallback(async (action: BalanceAction) => {
    if (!accountId || isBusy) return;
    markPreparing();
    setError(undefined);
    setReviewedQuote(undefined);
    setSubmittedOperationId(undefined);
    try {
      if (!await restoreOperations()) return;
      if (activeAccountRef.current !== accountId) return;
      setBalanceAction(action);
      setStep('password-balance');
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      unmarkPreparing();
    }
  });

  const submitBalanceAction = useLastCallback(async (enclaveToken: string) => {
    if (!accountId || !balanceAction || isSubmitting) return;
    const amount = balanceAmount.trim();
    markSubmitting();
    setError(undefined);
    try {
      const result = balanceAction === 'deposit'
        ? await callApiWithThrow('perpsDepositMargin', accountId, enclaveToken, amount)
        : balanceAction === 'withdraw'
          ? await callApiWithThrow('perpsWithdrawMargin', accountId, enclaveToken, amount)
          : await callApiWithThrow('perpsOpenFromBalance', accountId, enclaveToken, {
            assetId: asset.trim(),
            side,
            amount,
            leverage: parsedLeverage,
            isCross,
          });
      if (!result) throw new Error('The request may still be running. Refresh before trying again.');
      if ('error' in result) throw new Error(result.error);
      if ('submitted' in result) {
        setLog((prev) => appendLog(prev, 'Deposit to balance · sending the bridge transaction'));
        setBalanceAction(undefined);
        setStep('main');
        return;
      }
      if (activeAccountRef.current !== accountId) return;
      const balanceLabel = balanceAction === 'deposit'
        ? 'Deposit to balance'
        : balanceAction === 'withdraw' ? 'Withdraw from balance' : 'Open from balance';
      const depositTxHash = 'depositTxHash' in result && typeof result.depositTxHash === 'string'
        ? result.depositTxHash
        : undefined;
      const detail = [
        balanceLabel,
        result.status,
        depositTxHash && `tx ${depositTxHash}`,
        result.oid !== undefined && `order ${result.oid}`,
        result.filledSize && `filled ${result.filledSize}`,
        result.avgPrice && `@ ${result.avgPrice}`,
      ].filter(Boolean).join(' · ');
      setLog((prev) => appendLog(prev, detail));
      if (result.status.startsWith('error') || result.status.endsWith('Rejected')) throw new Error(result.status);
      setBalanceAction(undefined);
      setStep('main');
      void fetchPositions();
      void fetchActivities();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      unmarkSubmitting();
    }
  });

  const handleAuthorize = useLastCallback(async (enclaveToken: string) => {
    if (step === 'password-balance') {
      await submitBalanceAction(enclaveToken);
      return;
    }
    if (!accountId || !operationId || isSubmitting) return;
    if (step === 'password-order' && reviewedQuote?.accountId !== accountId) return;
    markSubmitting();
    setError(undefined);
    if (!await restoreOperations()) {
      unmarkSubmitting();
      return;
    }
    const saved = getGlobal().byAccountId[accountId]?.perpsOperations?.[operationId];
    const initial: ApiPerpsOperation | undefined = step === 'password-withdrawal'
      ? saved && { ...saved, state: 'running', stage: 'preparing' }
      : reviewedQuote && reviewedQuote.kind !== 'unchanged' ? {
        id: operationId,
        accountId,
        assetId: reviewedQuote.assetId,
        kind: reviewedQuote.kind,
        state: 'running',
        stage: 'preparing',
        createdAt: Date.now(),
        withdrawalRequestedAmount: reviewedQuote.kind === 'reduce'
          && reviewedQuote.modify?.depositAmount !== undefined ? String(reviewedQuote.modify.depositAmount) : undefined,
      } : undefined;
    if (!initial) {
      unmarkSubmitting();
      return;
    }
    try {
      persistPerpsSubmission(initial);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      unmarkSubmitting();
      return;
    }
    setSubmittedOperationId(initial.id);
    try {
      const result = step === 'password-withdrawal'
        ? await callApiWithThrow('perpsRetryWithdrawal', accountId, enclaveToken, operationId)
        : await callApiWithThrow('perpsExecuteReviewedOrder', accountId, enclaveToken, reviewedQuote!.id, operationId);
      if (!result) throw new Error('The request may still be running. Check the operation status before retrying.');
      apiUpdate({ type: 'perpsOperationUpdated', operation: result });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      const current = getGlobal().byAccountId[accountId]?.perpsOperations?.[operationId] ?? initial;
      apiUpdate({ type: 'perpsOperationUpdated', operation: getPerpsOperationAfterSubmissionError(
        current, message, step === 'password-withdrawal',
      ) });
      setError(message);
    } finally {
      unmarkSubmitting();
    }
  });

  const handlePrepareWithdrawal = useLastCallback(async (saved: ApiPerpsOperation) => {
    if (!accountId || isBusy) return;
    markPreparing();
    setError(undefined);
    setSubmittedOperationId(undefined);
    try {
      const amount = await callApiWithThrow('perpsPrepareWithdrawal', accountId, saved.id);
      if (!amount) throw new Error('Withdrawal unavailable. Refresh and try again.');
      if (activeAccountRef.current !== accountId) return;
      setOperationId(saved.id);
      setWithdrawalAmount(amount);
      setStep('password-withdrawal');
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      unmarkPreparing();
    }
  });

  const handleAcknowledge = useLastCallback(async (saved: ApiPerpsOperation) => {
    if (!accountId || isBusy) return;
    markPreparing();
    setError(undefined);
    try {
      const acknowledged = await callApiWithThrow('perpsAcknowledgeOperation', accountId, saved);
      if (!acknowledged) throw new Error('Could not acknowledge this operation. Please try again.');
      apiUpdate({ type: 'perpsOperationUpdated', operation: acknowledged });
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      unmarkPreparing();
    }
  });

  const renderAssets = () => {
    if (!listedCatalogue) {
      return (
        <div className={styles.hint}>
          {isLoadingAssets ? 'Loading listed perps…' : 'No market list yet. Refresh to load /perps/assets.'}
        </div>
      );
    }

    const assets = getListedAssets(listedCatalogue);

    if (assets.length === 0) {
      return <div className={styles.hint}>No listed assets returned.</div>;
    }

    return (
      <div className={styles.assetSection}>
        <div className={styles.assetSectionTitle}>Open from market list</div>
        <div className={styles.assetList}>
          {assets.map((entry) => {
            const isSelected = asset.trim() === entry.id;
            const mark = entry.context.markPx || entry.context.midPx || entry.context.oraclePx;
            const showCoinId = entry.name !== entry.symbol;

            return (
              <div
                key={entry.id}
                className={buildClassName(styles.assetRow, isSelected && styles.assetRowSelected)}
                role="button"
                tabIndex={0}
                onClick={() => {
                  setAsset(entry.id);
                  openPerpsAsset({ assetId: entry.id });
                }}
              >
                <PerpsListedAssetIcon symbol={entry.symbol} image={entry.image} />
                <div className={styles.assetIdentity}>
                  <div className={styles.assetTitleRow}>
                    <span className={styles.assetName}>{entry.symbol}</span>
                    <span className={styles.dexBadge} title={entry.dex || 'Hyperliquid native perps'}>
                      {formatDexBadge(entry.dex)}
                    </span>
                  </div>
                  {showCoinId && (
                    <span className={styles.assetCoinId}>{entry.name}</span>
                  )}
                  <span className={styles.assetCoinId}>{entry.id}</span>
                </div>
                <span className={styles.assetMeta}>
                  {mark ? `$${mark}` : '—'} · {entry.maxLeverage}x max
                </span>
                <div className={styles.assetOpenActions}>
                  <Button
                    isSmall
                    isPrimary={isSelected && side === 'long'}
                    isSecondary={!(isSelected && side === 'long')}
                    isDisabled={isBusy || !arbAddress}
                    shouldStopPropagation
                    onClick={() => handleOpenFromAsset(entry, 'long')}
                  >
                    Long
                  </Button>
                  <Button
                    isSmall
                    isPrimary={isSelected && side === 'short'}
                    isSecondary={!(isSelected && side === 'short')}
                    isDisabled={isBusy || !arbAddress}
                    shouldStopPropagation
                    onClick={() => handleOpenFromAsset(entry, 'short')}
                  >
                    Short
                  </Button>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    );
  };

  const renderPositions = () => {
    if (!positionsState) {
      return <div className={styles.hint}>No position data yet. Refresh to load from backend.</div>;
    }

    const {
      assetPositions,
      spotUsdcTotal,
      spotUsdcAvailable,
    } = positionsState;

    return (
      <>
        <div className={styles.summary}>
          <div>
            <div className={styles.summaryLabel}>USDC total</div>
            <div>{spotUsdcTotal ?? '0'} USDC</div>
          </div>
          <div>
            <div className={styles.summaryLabel}>USDC available</div>
            <div>{spotUsdcAvailable ?? '0'} USDC</div>
          </div>
        </div>

        <div className={styles.positions}>
          {assetPositions.length === 0 && (
            <div className={styles.hint}>No open positions.</div>
          )}
          {assetPositions.map(({ position }) => {
            const listedAsset = listedCatalogue?.find((entry) => entry.name === position.coin);

            return (
              <div key={position.coin} className={styles.positionRow}>
                <div className={styles.positionMain}>
                  <div className={styles.positionTitle}>
                    {listedAsset?.symbol ?? position.coin}
                  </div>
                  <div>Size {position.szi} · Entry {position.entryPx ?? '—'}</div>
                  <div>PnL {position.unrealizedPnl} · Lev {position.leverage.value}x</div>
                  {listedAsset && (
                    <div className={styles.assetCoinId}>{listedAsset.id}</div>
                  )}
                </div>
                {isPositionOpen(position.szi) && listedAsset && (
                  <div className={styles.positionActions}>
                    <Button
                      isSecondary
                      isSmall
                      isDisabled={isBusy}
                      onClick={() => handleModifyClick(listedAsset.id, 'add')}
                    >
                      Add size
                    </Button>
                    <Button
                      isSecondary
                      isSmall
                      isDisabled={isBusy}
                      onClick={() => handleModifyClick(listedAsset.id, 'reduce')}
                    >
                      Reduce
                    </Button>
                    <Button
                      isSecondary
                      isSmall
                      isDisabled={isBusy}
                      onClick={() => handleModifyClick(listedAsset.id, 'leverage')}
                    >
                      Set leverage
                    </Button>
                    <Button
                      isSecondary
                      isSmall
                      isDisabled={isBusy}
                      onClick={() => handleCloseClick(listedAsset.id)}
                    >
                      Close & withdraw
                    </Button>
                  </div>
                )}
                {isPositionOpen(position.szi) && !listedAsset && (
                  <div className={styles.hint}>Refresh market list to close this position.</div>
                )}
              </div>
            );
          })}
        </div>
      </>
    );
  };

  const renderActivities = () => {
    const activities = activitiesSnapshot?.activities;

    if (!activities) {
      return (
        <div className={styles.hint}>
          No activity data yet. Refresh to load from POST /perps/activities.
        </div>
      );
    }

    if (activities.length === 0) {
      return <div className={styles.hint}>No Hyperliquid trades.</div>;
    }

    const preview = activities.slice(0, PERPS_LAB_ACTIVITIES_PREVIEW_LIMIT);
    const hiddenCount = activities.length - preview.length;

    return (
      <div className={styles.activitiesSection}>
        <div className={styles.assetSectionTitle}>
          Hyperliquid activities ({activities.length})
        </div>
        <div className={styles.activityList}>
          {preview.map((item) => (
            <div
              key={item.id}
              className={styles.activityRow}
            >
              <div className={styles.activityHeader}>
                <span className={styles.activityKind}>{item.kind}</span>
                <span className={styles.dexBadge} title={item.dex || 'Hyperliquid native perps'}>
                  {formatDexBadge(item.dex)}
                </span>
                <span className={styles.activityTime}>{formatPerpsActivityTime(item.timestamp)}</span>
              </div>
              <div>{formatPerpsActivitySummary(item)}</div>
              {item.assetId && (
                <div className={styles.assetCoinId}>{item.assetId}</div>
              )}
            </div>
          ))}
        </div>
        {hiddenCount > 0 && (
          <div className={styles.hint}>
            Showing first {PERPS_LAB_ACTIVITIES_PREVIEW_LIMIT} of {activities.length} rows (newest first).
          </div>
        )}
      </div>
    );
  };

  if (step !== 'main') {
    const isWithdrawal = step === 'password-withdrawal';
    const isBalance = step === 'password-balance' && balanceAction !== undefined;
    const balanceCopy = isBalance
      ? balancePasswordCopy(balanceAction, balanceAmount.trim(), asset.trim(), side, parsedLeverage, isCross)
      : undefined;
    const quote = reviewedQuote;
    const depositGas = quote ? formatPerpsDepositGas(quote) : undefined;
    return (
      <Modal isOpen={isOpen} onClose={onClose} isCompact title="Perps Lab">
        {!isWithdrawal && !isBalance && quote && (
          <div className={styles.summary}>
            <div>{quote.assetId} · {quote.leverage}x {quote.side}</div>
            <div>Position size: {quote.size}</div>
            {quote.estimatedCollateral !== undefined && <div>Estimated invested: {quote.estimatedCollateral} USDC</div>}
            {Number(quote.paymentAmount) > 0 && <div>Pay: {quote.paymentAmount} USDC</div>}
            {quote.kind === 'reduce' && <div>Release: {quote.modify?.depositAmount} USDC before withdrawal fees</div>}
            <div>Estimated fees: {quote.estimatedFees?.total ?? '—'} USDC</div>
            {depositGas !== undefined && <div>Network fee: {depositGas}</div>}
            <div>Estimated liquidation price: {quote.estimatedLiquidationPrice ?? '—'}</div>
            {quote.switchesToUnified && <div>Also switches this Hyperliquid account to Unified</div>}
          </div>
        )}
        {isBalance && (
          <div className={styles.summary}>
            <div>{balanceCopy?.title}</div>
            <div className={styles.hint}>{balanceCopy?.notice}</div>
          </div>
        )}
        <PasswordForm
          isActive
          isLoading={isSubmitting}
          operationType="transfer"
          operationTitle={isWithdrawal
            ? `Withdraw ${withdrawalAmount} USDC to Arbitrum`
            : balanceCopy?.title ?? `Confirm ${quote?.kind}`}
          submitLabel={isWithdrawal ? 'Withdraw' : balanceCopy?.submitLabel ?? 'Confirm order'}
          cancelLabel="Back"
          footerNotice={isWithdrawal
            ? 'This retries only the withdrawal. The completed trade will not be submitted again.'
            : (balanceCopy?.notice
              ?? 'The operation continues in the background after submission. Its status appears in the operation list.'
            )}
          extraAuthUsages={0}
          error={error}
          onAuthorize={handleAuthorize}
          onCancel={handlePasswordBack}
          onUpdate={() => setError(undefined)}
        />
      </Modal>
    );
  }

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Perps Lab (dev)">
      {currentPerpsAssetId ? (
        <PerpsAssetPage isActive={isOpen} />
      ) : (
        <div className={styles.root}>
          <p className={styles.hint}>
            One USDC deposit on Arbitrum. After the {PERPS_CCTP_FORWARD_FEE_USDC} USDC CCTP fee, the credit is
            the margin and the order notional is that margin times leverage. EIP-7702 batch adds Alchemy
            delegate when needed.
          </p>

          {!arbAddress ? (
            <p className={styles.error}>
              Add an Arbitrum account to this wallet to use perps (same EVM address as Hyperliquid).
            </p>
          ) : (
            <p className={styles.address}>{arbAddress}</p>
          )}

          {Object.values(perpsOperations ?? {}).sort((a, b) => b.createdAt - a.createdAt).map((saved) => (
            <div key={saved.id} className={styles.summary}>
              <div>{saved.assetId} · {saved.kind} · {saved.state} ({saved.stage})</div>
              {saved.error && <div className={styles.error}>{saved.error}</div>}
              {saved.state === 'partial' && (
                <Button isSecondary isDisabled={isBusy} onClick={() => handlePrepareWithdrawal(saved)}>
                  Retry withdrawal
                </Button>
              )}
              {saved.state === 'unknown' && saved.acknowledgedAt === undefined && (
                <>
                  <div className={styles.hint}>
                    The original request may still complete. Check your activity and balances before continuing.
                    Acknowledging does not cancel or retry it.
                  </div>
                  <Button isSecondary isDisabled={isBusy} onClick={() => handleAcknowledge(saved)}>
                    I checked my activity and understand
                  </Button>
                </>
              )}
            </div>
          ))}

          {renderAssets()}

          {renderPositions()}

          {renderActivities()}

          <div className={styles.actions}>
            <Button
              isSecondary
              isLoading={isLoadingAssets || isLoadingPositions || isLoadingActivities}
              onClick={() => {
                void restoreOperations();
                void fetchAssets();
                if (arbAddress) {
                  void fetchPositions();
                  void fetchActivities();
                }
              }}
            >
              Refresh market, positions & activities
            </Button>
          </div>

          <div className={styles.form}>
            <Input
              label="Perps asset id (from /perps/assets)"
              value={asset}
              onInput={setAsset}
            />
            <div className={styles.sideRow}>
              <Button
                className={styles.sideButton}
                isPrimary={side === 'long'}
                isSecondary={side !== 'long'}
                onClick={() => setSide('long')}
              >
                Long
              </Button>
              <Button
                className={styles.sideButton}
                isPrimary={side === 'short'}
                isSecondary={side !== 'short'}
                onClick={() => setSide('short')}
              >
                Short
              </Button>
            </div>
            <Input
              label="Deposit (USDC on Arbitrum, gross)"
              value={depositAmount}
              inputMode="numeric"
              onInput={setDepositAmount}
            />
            <Input
              label={maxLeverage !== undefined
                ? `Leverage (isolated, max ${maxLeverage}x)`
                : 'Leverage (isolated)'}
              value={leverageAmount}
              inputMode="numeric"
              onInput={setLeverageAmount}
            />
            {minOpenDepositUsdc !== undefined
              && Number.isFinite(depositGross)
              && depositGross > 0
              && depositGross < minOpenDepositUsdc && (
              <p className={styles.hint}>
                Min deposit {hyperliquidLimits?.minOpenDepositUsdc} USDC.
              </p>
            )}
            {openEstimate && (
              <div className={styles.summary}>
                <div>
                  <div className={styles.summaryLabel}>Position value</div>
                  <div>{openEstimate.notional} USDC</div>
                </div>
                <div>
                  <div className={styles.summaryLabel}>Size</div>
                  <div>{openEstimate.size}</div>
                </div>
                {openEstimate.estimatedCollateral !== undefined && (
                  <div>
                    <div className={styles.summaryLabel}>Estimated invested</div>
                    <div>{openEstimate.estimatedCollateral} USDC</div>
                  </div>
                )}
                <div>
                  <div className={styles.summaryLabel}>Liquidation price</div>
                  <div>{openEstimate.estimatedLiquidationPrice ?? '—'}</div>
                </div>
                {renderPerpsDepositGas(openEstimate)}
              </div>
            )}
            {isEstimatingOpen && !openEstimate && (
              <p className={styles.hint}>Estimating position…</p>
            )}
            {openEstimateError && <div className={styles.error}>{openEstimateError}</div>}
            {leverageDeposit !== undefined && (
              <div className={styles.summary}>
                <div className={styles.summaryTitle}>Leverage change</div>
                <div>
                  <div className={styles.summaryLabel}>Deposit</div>
                  <div>{leverageDeposit} USDC</div>
                </div>
                {leverageEstimate && renderPerpsDepositGas(leverageEstimate)}
              </div>
            )}
            {leverageDeposit === '0' && (
              <p className={styles.hint}>Increasing leverage needs no extra deposit.</p>
            )}
            {leverageDeposit !== undefined && Number(leverageDeposit) > 0 && (
              <p className={styles.hint}>
                Decreasing leverage deposits {leverageDeposit} USDC from Arbitrum before the update.
              </p>
            )}
            {leverageError && <div className={styles.error}>{leverageError}</div>}
            <Input
              label="Modify deposit (USDC). Add: gross CCTP. Reduce: margin to release"
              value={modifyNotional}
              inputMode="numeric"
              onInput={setModifyNotional}
            />
            {Number.isFinite(modifyNotionalUsd) && modifyNotionalUsd > 0 && (
              <p className={styles.hint}>
                Add burns {modifyNotionalUsd} USDC on Arbitrum
                {minIncreaseDepositUsdc !== undefined && modifyNotionalUsd > minIncreaseDepositUsdc
                  ? ` (HyperCore credits ${getPerpsCctpCreditedAmountUsdc(modifyNotionalUsd).toFixed(2)})`
                  : minIncreaseDepositUsdc !== undefined
                    ? ` (must exceed ${hyperliquidLimits?.minIncreaseDepositUsdc} USDC)`
                    : ''}
                . Reduce releases {modifyNotionalUsd} USDC of margin and withdraws that gross.
                {minPositionMarginUsdc !== undefined
                  ? ` The position must keep at least ${hyperliquidLimits?.minPositionMarginUsdc} USDC.`
                  : ''}
              </p>
            )}
            {addEstimate && <PerpsEstimateCard title="Add" estimate={addEstimate} />}
            {addError && <div className={styles.error}>{addError}</div>}
            {reduceEstimate && <PerpsEstimateCard title="Reduce" estimate={reduceEstimate} />}
            {reduceError && <div className={styles.error}>{reduceError}</div>}
            {isEstimatingModify && !addEstimate && !reduceEstimate && leverageDeposit === undefined && (
              <p className={styles.hint}>Estimating modify…</p>
            )}
          </div>

          {error && <div className={styles.error}>{error}</div>}

          <Button
            isPrimary
            isDisabled={
              isBusy
              || !arbAddress
              || !accountId
              || !asset.trim()
              || !depositAmount
              || !Number.isFinite(depositGross)
              || minOpenDepositUsdc === undefined
              || depositGross < minOpenDepositUsdc
              || (positionNotionalUsd ?? 0) <= 0
              || !Number.isFinite(parsedLeverage)
              || (maxLeverage !== undefined && parsedLeverage > maxLeverage)
              || !selectedListedAsset
            }
            onClick={handleOpenClick}
          >
            Open position
          </Button>

          <div className={styles.form}>
            <div className={styles.assetSectionTitle}>Perps balance</div>
            <p className={styles.hint}>
              Deposit and withdraw move USDC without changing a position and must exceed {PERPS_CCTP_FORWARD_FEE_USDC}
              {' '}USDC. Open uses the asset, side and leverage above, takes this amount as margin from the perps
              balance, and does not send an Arbitrum deposit. Isolated or cross applies only to that open.
            </p>
            <Input
              label="Balance amount (USDC)"
              value={balanceAmount}
              inputMode="numeric"
              onInput={setBalanceAmount}
            />
            <div className={styles.sideRow}>
              <Button
                className={styles.sideButton}
                isPrimary={!isCross}
                isSecondary={isCross}
                onClick={() => setIsCross(false)}
              >
                Isolated
              </Button>
              <Button
                className={styles.sideButton}
                isPrimary={isCross}
                isSecondary={!isCross}
                onClick={() => setIsCross(true)}
              >
                Cross
              </Button>
            </div>
            {assetHasPosition && (
              <p className={styles.hint}>This asset already has a position. Open from balance only starts a new one.</p>
            )}
          </div>
          <div className={styles.actions}>
            <Button
              isSecondary
              isDisabled={isBusy || !arbAddress || !accountId || !canMoveBalance}
              onClick={() => handleBalanceClick('deposit')}
            >
              Deposit to balance
            </Button>
            <Button
              isSecondary
              isDisabled={isBusy || !arbAddress || !accountId || !canMoveBalance}
              onClick={() => handleBalanceClick('withdraw')}
            >
              Withdraw to wallet
            </Button>
            <Button
              isPrimary
              isDisabled={isBusy || !arbAddress || !accountId || !canOpenFromBalance}
              onClick={() => handleBalanceClick('open')}
            >
              Open from balance
            </Button>
          </div>

          {log && <pre className={buildClassName(styles.log)}>{log}</pre>}
        </div>
      )}
    </Modal>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accountId = global.currentAccountId;
  const account = accountId ? global.accounts?.byId?.[accountId] : undefined;
  const accountState = accountId ? global.byAccountId[accountId] : undefined;

  return {
    accountId,
    arbAddress: account?.byChain?.arbitrum?.address,
    perpsOperations: accountState?.perpsOperations,
    perpsBalanceDeposit: accountState?.perpsBalanceDeposit,
    perpsAssets: global.perpsAssets,
    currentPerpsAssetId: accountState?.currentPerpsAssetId,
  };
})(PerpsLabModal));

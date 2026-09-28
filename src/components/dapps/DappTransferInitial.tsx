import React, { memo, useEffect, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { StoredDappConnection } from '../../api/dappProtocols/storage';
import type {
  ApiActivity,
  ApiBaseCurrency,
  ApiChain,
  ApiCurrencyRates,
  ApiDappTransfer,
  ApiEmulationResult,
  ApiNft,
  ApiStakingState,
  ApiSwapAsset,
  ApiTokenWithPrice,
} from '../../api/types';
import type { Account, SavedAddress, Theme } from '../../global/types';

import { DEFAULT_CHAIN, TONCOIN, UNKNOWN_TOKEN } from '../../config';
import renderText from '../../global/helpers/renderText';
import {
  selectAccountStakingStatesByPool,
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectCurrentDappTransferTotalInBaseCurrency,
  selectCurrentDappTransferTotals,
  selectDappTransferInsufficientTokens,
  selectNetworkAccounts,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { getChainConfig } from '../../util/chain';
import { toBig, toDecimal } from '../../util/decimals';
import { formatCurrency, getIsCurrencySymbolAtStart, getShortCurrencySymbol } from '../../util/formatNumber';
import { shortenAddress } from '../../util/shortenAddress';
import { isNftTransferPayload, isTokenTransferPayload } from '../../util/ton/transfer';

import useAppTheme from '../../hooks/useAppTheme';
import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useTimeout from '../../hooks/useTimeout';

import ActivityPreview from '../common/ActivityPreview';
import HeroAmount from '../common/HeroAmount';
import Button from '../ui/Button';
import Transition from '../ui/Transition';
import DappFeeDetailsModal from './DappFeeDetailsModal';
import DappInfoWithAccount from './DappInfoWithAccount';
import DappSkeletonWithContent, { type DappSkeletonRow } from './DappSkeletonWithContent';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Dapp.module.scss';

import scamImg from '../../assets/scam.svg';

interface OwnProps {
  isActive?: boolean;
  onClose?: NoneToVoidFunction;
}

interface StateProps {
  transactions?: ApiDappTransfer[];
  totalAmountsBySlug: Record<string, bigint>;
  totalAmountInBaseCurrency?: string;
  emulation?: Pick<ApiEmulationResult, 'activities' | 'realFee'>;
  isScam: boolean;
  isDangerous: boolean;
  dapp?: StoredDappConnection;
  isLoading?: boolean;
  tokensBySlug: Record<string, ApiTokenWithPrice>;
  swapTokensBySlug?: Record<string, ApiSwapAsset>;
  theme: Theme;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  nftsByAddress?: Record<string, ApiNft>;
  currentAccountId: string;
  stakingStateByPool: Record<string, ApiStakingState>;
  savedAddresses?: SavedAddress[];
  accounts?: Record<string, Account>;
  insufficientTokens?: string;
  balancesBySlug?: Record<string, bigint>;
  chain: ApiChain | undefined;
  shouldHideTransfers: boolean;
  isWaitingForRequest?: boolean;
  returnUrl?: string;
  isSensitiveDataHidden?: true;
}

interface SortedDappTransfer extends ApiDappTransfer {
  index: number;
  sortingCost: number;
}

const NFT_FAKE_COST_USD = 1_000_000_000;
const NOT_RESPONDING_DELAY_MS = 7000;
const TOTAL_AMOUNT_FRACTION_DIGITS = 2;

const skeletonRows: DappSkeletonRow[] = [
  { isLarge: false, hasFee: false },
  { isLarge: true, hasFee: true },
];

function DappTransferInitial({
  transactions,
  totalAmountsBySlug,
  totalAmountInBaseCurrency,
  emulation,
  isScam,
  isDangerous,
  dapp,
  isLoading,
  tokensBySlug,
  swapTokensBySlug,
  theme,
  baseCurrency,
  currencyRates,
  nftsByAddress,
  currentAccountId,
  stakingStateByPool,
  savedAddresses,
  accounts,
  insufficientTokens,
  balancesBySlug,
  isActive,
  onClose,
  chain,
  shouldHideTransfers,
  isWaitingForRequest,
  returnUrl,
  isSensitiveDataHidden,
}: OwnProps & StateProps) {
  const { showDappTransferTransaction, submitDappTransferConfirm, showDialog } = getActions();

  const lang = useLang();
  const appTheme = useAppTheme(theme);
  const [isFeeDetailsOpen, openFeeDetails, closeFeeDetails] = useFlag();
  const renderingTransactions = useCurrentOrPrev(transactions, true);
  const sortedTransactions = useMemo(
    () => sortTransactions(renderingTransactions, tokensBySlug),
    [renderingTransactions, tokensBySlug],
  );
  const isDappLoading = dapp === undefined;
  const hasSufficientBalance = !insufficientTokens;
  const canSubmit = !isDappLoading && !isLoading && !isScam && hasSufficientBalance;

  const handleEnter = useLastCallback((e: KeyboardEvent) => {
    // Enter on a focused control, such as Cancel or the fee line, activates that control instead of confirming
    if ((e.target as HTMLElement).closest('button, [role="button"]')) return;

    submitDappTransferConfirm();
  });

  useEffect(() => (
    isActive && canSubmit
      ? captureKeyboardListeners({ onEnter: { handler: handleEnter, noStopPropagation: true } })
      : undefined
  ), [isActive, canSubmit, handleEnter]);

  // Placeholder modal (opened by a wake deeplink): warn if the request event never arrives.
  useTimeout(
    () => {
      showDialog({
        title: 'Dapp Not Responding',
        message: 'You may need to reconnect your wallet from the dapp if this keeps happening.',
        buttons: {
          confirm: { title: 'OK', action: returnUrl ? 'openReturnUrl' : undefined },
          ...(returnUrl && { cancel: { title: 'Cancel' } }),
        },
        ...(returnUrl && { entities: { url: returnUrl } }),
      });
    },
    isDappLoading && isWaitingForRequest ? NOT_RESPONDING_DELAY_MS : undefined,
    [isDappLoading, isWaitingForRequest],
  );

  const tokenToDisplay = useMemo(() => (
    calculateTokenToDisplay(chain || DEFAULT_CHAIN, totalAmountsBySlug, balancesBySlug, tokensBySlug)
  ), [chain, totalAmountsBySlug, balancesBySlug, tokensBySlug]);

  const excess = useMemo(() => calculateExcess(emulation?.activities), [emulation]);

  function renderContent() {
    return (
      <div className={buildClassName(modalStyles.transitionContent, styles.skeletonBackground)}>
        <DappInfoWithAccount
          chain={chain}
          dapp={dapp}
          customTokenBalance={tokenToDisplay.balance}
          customTokenSymbol={tokenToDisplay.symbol}
          customTokenDecimals={tokenToDisplay.decimals}
        />
        {renderTotalAmount()}
        {isDangerous && (
          <div className={buildClassName(styles.transferWarning, styles.warning)}>
            {renderText(lang('$hardware_payload_warning'))}
          </div>
        )}
        {renderTransactions()}
        {renderEmulation()}
        {renderFeeDetailsModal()}
        {renderFooter()}
      </div>
    );
  }

  // The loading state has no modal header either, so Cancel is the only way to leave a request that never arrives
  function renderSkeleton() {
    return (
      <div className={buildClassName(modalStyles.transitionContent, styles.skeletonBackground)}>
        <DappSkeletonWithContent rows={skeletonRows} shouldRenderHeroAmount />
        {renderFooter()}
      </div>
    );
  }

  function renderTotalAmount() {
    if (totalAmountInBaseCurrency === undefined) {
      return undefined;
    }

    const currencySymbol = getShortCurrencySymbol(baseCurrency);
    const isSymbolAtStart = getIsCurrencySymbolAtStart(currencySymbol);

    return (
      <div className={styles.totalAmount}>
        <HeroAmount
          value={totalAmountInBaseCurrency}
          decimals={TOTAL_AMOUNT_FRACTION_DIGITS}
          prefix={isSymbolAtStart ? currencySymbol : undefined}
          suffix={isSymbolAtStart ? undefined : currencySymbol}
          isSensitiveDataHidden={isSensitiveDataHidden}
        />
      </div>
    );
  }

  function renderFooter() {
    return (
      <div className={styles.footer}>
        {!hasSufficientBalance && (
          <div className={styles.balanceError}>
            {lang('Not Enough %symbol%', { symbol: insufficientTokens })}
          </div>
        )}
        <div className={buildClassName(modalStyles.buttons, styles.transferButtons)}>
          <Button className={modalStyles.button} onClick={onClose}>{lang('Cancel')}</Button>
          <Button
            isPrimary
            isLoading={isLoading}
            isDisabled={isDappLoading || isScam || !hasSufficientBalance}
            className={modalStyles.button}
            onClick={canSubmit ? submitDappTransferConfirm : undefined}
          >
            {lang('Send')}
          </Button>
        </div>
      </div>
    );
  }

  function renderTransactionRow(transaction: SortedDappTransfer) {
    const { payload } = transaction;

    const amountText: string[] = [];
    if (isNftTransferPayload(payload)) {
      amountText.push('1 NFT');
    } else if (isTokenTransferPayload(payload)) {
      const { slug: tokenSlug, amount } = payload;
      const { decimals, symbol } = tokensBySlug[tokenSlug] ?? UNKNOWN_TOKEN;
      amountText.push(formatCurrency(toDecimal(amount, decimals), symbol));
    }

    amountText.push(formatCurrency(toDecimal(transaction.amount + transaction.networkFee), TONCOIN.symbol));

    return (
      <div
        key={transaction.index}
        className={styles.transactionRow}
        onClick={() => showDappTransferTransaction({ transactionIdx: transaction.index })}
      >
        {transaction.isScam && <img src={scamImg} alt={lang('Scam')} className={styles.scamImage} />}
        <span className={buildClassName(styles.transactionRowAmount, transaction.isScam && styles.scam)}>
          {amountText.join(' + ')}
        </span>
        {' '}
        <span className={buildClassName(styles.transactionRowAddress, transaction.isScam && styles.scam)}>
          {lang('$transaction_to', {
            address: shortenAddress(transaction.displayedToAddress),
          })}
        </span>
        <i className={buildClassName(styles.transactionRowChevron, 'icon-chevron-right')} aria-hidden />
      </div>
    );
  }

  function renderTransactions() {
    if (!renderingTransactions || shouldHideTransfers) {
      return undefined;
    }

    return (
      <>
        <p className={styles.label}>{lang('$many_transactions', renderingTransactions.length, 'i')}</p>
        <div className={styles.transactionList}>
          {sortedTransactions?.map(renderTransactionRow)}
        </div>
      </>
    );
  }

  function renderEmulation() {
    if (!emulation?.activities?.length) {
      return (
        <div className={styles.previewUnavailable}>{lang('Preview is currently unavailable.')}</div>
      );
    }

    return (
      <ActivityPreview
        activities={emulation.activities}
        realFee={emulation.realFee}
        feeToken={getChainConfig(chain || DEFAULT_CHAIN).nativeToken}
        tokensBySlug={tokensBySlug}
        swapTokensBySlug={swapTokensBySlug}
        appTheme={appTheme}
        nftsByAddress={nftsByAddress}
        currentAccountId={currentAccountId}
        stakingStateByPool={stakingStateByPool}
        savedAddresses={savedAddresses}
        accounts={accounts}
        baseCurrency={baseCurrency}
        currencyRates={currencyRates}
        onFeeDetailsClick={excess === undefined ? undefined : openFeeDetails}
      />
    );
  }

  function renderFeeDetailsModal() {
    if (!emulation || excess === undefined) {
      return undefined;
    }

    return (
      <DappFeeDetailsModal
        isOpen={isFeeDetailsOpen}
        chain={chain || DEFAULT_CHAIN}
        realFee={emulation.realFee}
        excess={excess}
        onClose={closeFeeDetails}
      />
    );
  }

  return (
    <Transition name="semiFade" activeKey={isDappLoading ? 0 : 1} slideClassName={styles.skeletonTransitionWrapper}>
      {isDappLoading ? renderSkeleton() : renderContent()}
    </Transition>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const {
    isLoading, dapp, transactions, emulation, operationChain, shouldHideTransfers, isWaitingForRequest, returnUrl,
  } = global.currentDappTransfer;

  const accountId = selectCurrentAccountId(global)!;
  const accountState = selectCurrentAccountState(global);
  const accounts = selectNetworkAccounts(global);

  const { amountsBySlug: totalAmountsBySlug, isScam, isDangerous } = selectCurrentDappTransferTotals(global);

  return {
    transactions,
    totalAmountsBySlug,
    totalAmountInBaseCurrency: selectCurrentDappTransferTotalInBaseCurrency(global),
    emulation,
    isScam,
    isDangerous,
    dapp,
    isLoading,
    tokensBySlug: global.tokenInfo.bySlug,
    swapTokensBySlug: global.swapTokenInfo?.bySlug,
    theme: global.settings.theme,
    baseCurrency: global.settings.baseCurrency,
    currencyRates: global.currencyRates,
    nftsByAddress: accountState?.nfts?.byAddress,
    currentAccountId: accountId,
    stakingStateByPool: selectAccountStakingStatesByPool(global, accountId),
    savedAddresses: accountState?.savedAddresses,
    accounts,
    insufficientTokens: selectDappTransferInsufficientTokens(global),
    balancesBySlug: accountState?.balances?.bySlug,
    chain: operationChain,
    shouldHideTransfers: !!shouldHideTransfers,
    isWaitingForRequest,
    returnUrl,
    isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
  };
})(DappTransferInitial));

function calculateExcess(activities?: ApiActivity[]) {
  let excess = 0n;

  for (const activity of activities ?? []) {
    if (activity.kind === 'transaction' && activity.type === 'excess') {
      excess += activity.amount;
    }
  }

  return excess > 0n ? excess : undefined;
}

interface TokenDisplayInfo {
  balance: bigint;
  symbol: string;
  decimals: number;
}

function calculateTokenToDisplay(
  chain: ApiChain,
  totalAmountsBySlug?: Record<string, bigint>,
  balancesBySlug?: Record<string, bigint>,
  tokensBySlug?: Record<string, ApiTokenWithPrice>,
): TokenDisplayInfo {
  const nativeToken = getChainConfig(chain || DEFAULT_CHAIN).nativeToken;
  // Default to this operation native coin if no data
  if (!totalAmountsBySlug || !balancesBySlug || !tokensBySlug) {
    return {
      balance: balancesBySlug?.[nativeToken.slug] ?? 0n,
      symbol: nativeToken.symbol,
      decimals: nativeToken.decimals,
    };
  }

  const insufficientTokens: Array<{
    slug: string;
    insufficientUsdValue: number;
    balance: bigint;
    symbol: string;
    decimals: number;
  }> = [];

  const sufficientTokens: Array<{
    slug: string;
    transactionUsdValue: number;
    balance: bigint;
    symbol: string;
    decimals: number;
  }> = [];

  // Analyze each token in the transaction
  for (const [slug, requiredAmount] of Object.entries(totalAmountsBySlug)) {
    const availableBalance = balancesBySlug[slug] ?? 0n;
    const token = tokensBySlug[slug];

    if (!token) continue;

    const { symbol, decimals, priceUsd = 0 } = token;

    if (availableBalance < requiredAmount) {
      // Token is insufficient
      const insufficientAmount = requiredAmount - availableBalance;
      const insufficientUsdValue = toBig(insufficientAmount, decimals).toNumber() * priceUsd;

      insufficientTokens.push({
        slug,
        insufficientUsdValue,
        balance: availableBalance,
        symbol,
        decimals,
      });
    } else {
      // Token is sufficient
      const transactionUsdValue = toBig(requiredAmount, decimals).toNumber() * priceUsd;

      sufficientTokens.push({
        slug,
        transactionUsdValue,
        balance: availableBalance,
        symbol,
        decimals,
      });
    }
  }

  // If some tokens are insufficient, show the one with maximum insufficient USD value
  if (insufficientTokens.length > 0) {
    const maxInsufficientToken = insufficientTokens.reduce((max, current) =>
      current.insufficientUsdValue > max.insufficientUsdValue ? current : max,
    );

    return {
      balance: maxInsufficientToken.balance,
      symbol: maxInsufficientToken.symbol,
      decimals: maxInsufficientToken.decimals,
    };
  }

  // If all tokens are sufficient, show the one with maximum transaction USD value
  if (sufficientTokens.length > 0) {
    const maxTransactionToken = sufficientTokens.reduce((max, current) =>
      current.transactionUsdValue > max.transactionUsdValue ? current : max,
    );

    return {
      balance: maxTransactionToken.balance,
      symbol: maxTransactionToken.symbol,
      decimals: maxTransactionToken.decimals,
    };
  }

  // Fallback to TON
  return {
    balance: balancesBySlug[nativeToken.slug] ?? 0n,
    symbol: nativeToken.symbol,
    decimals: nativeToken.decimals,
  };
}

function sortTransactions(
  transactions: readonly ApiDappTransfer[] | undefined,
  tokensBySlug: Record<string, ApiTokenWithPrice>,
) {
  if (!transactions) {
    return transactions;
  }

  return transactions
    .map((transaction, index): SortedDappTransfer => ({
      ...transaction,
      index,
      sortingCost: getTransactionCostForSorting(transaction, tokensBySlug),
    }))
    .sort((transaction0, transaction1) => transaction1.sortingCost - transaction0.sortingCost);
}

function getTransactionCostForSorting(transaction: ApiDappTransfer, tokensBySlug: Record<string, ApiTokenWithPrice>) {
  const tonAmount = toBig(transaction.amount + transaction.networkFee, TONCOIN.decimals).toNumber();
  let cost = tokensBySlug[TONCOIN.slug].priceUsd * tonAmount;

  if (isTokenTransferPayload(transaction.payload)) {
    const { amount, slug } = transaction.payload;
    const token = tokensBySlug[slug];
    if (token) {
      cost += token.priceUsd * toBig(amount, token.decimals).toNumber();
    }
  } else if (isNftTransferPayload(transaction.payload)) {
    // Simple way to display NFT at top of list
    cost += NFT_FAKE_COST_USD;
  }

  return cost;
}

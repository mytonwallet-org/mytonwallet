import React, { memo, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { StoredDappConnection } from '../../api/dappProtocols/storage';
import type {
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
  selectAccountStakingStatesBySlug,
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectCurrentDappTransferTotals,
  selectDappTransferInsufficientTokens,
  selectNetworkAccounts,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getChainConfig } from '../../util/chain';
import { toBig, toDecimal } from '../../util/decimals';
import { formatCurrency } from '../../util/formatNumber';
import isEmptyObject from '../../util/isEmptyObject';
import { shortenAddress } from '../../util/shortenAddress';
import { isNftTransferPayload, isTokenTransferPayload } from '../../util/ton/transfer';

import useAppTheme from '../../hooks/useAppTheme';
import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useLang from '../../hooks/useLang';

import Activity from '../main/sections/Content/Activity';
import Button from '../ui/Button';
import FeeLine from '../ui/FeeLine';
import IconWithTooltip from '../ui/IconWithTooltip';
import ModalHeader from '../ui/ModalHeader';
import Transition from '../ui/Transition';
import DappAmountField from './DappAmountField';
import DappInfoWithAccount from './DappInfoWithAccount';
import DappSkeletonWithContent, { type DappSkeletonRow } from './DappSkeletonWithContent';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Dapp.module.scss';

import scamImg from '../../assets/scam.svg';

interface OwnProps {
  onClose?: NoneToVoidFunction;
}

interface StateProps {
  transactions?: ApiDappTransfer[];
  totalAmountsBySlug: Record<string, bigint>;
  emulation?: Pick<ApiEmulationResult, 'activities' | 'realFee'>;
  isScam: boolean;
  isDangerous: boolean;
  nftCount: number;
  dapp?: StoredDappConnection;
  isLoading?: boolean;
  tokensBySlug: Record<string, ApiTokenWithPrice>;
  swapTokensBySlug?: Record<string, ApiSwapAsset>;
  theme: Theme;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  nftsByAddress?: Record<string, ApiNft>;
  currentAccountId: string;
  stakingStateBySlug: Record<string, ApiStakingState>;
  savedAddresses?: SavedAddress[];
  accounts?: Record<string, Account>;
  insufficientTokens?: string;
  balancesBySlug?: Record<string, bigint>;
  chain: ApiChain | undefined;
  shouldHideTransfers: boolean;
}

interface SortedDappTransfer extends ApiDappTransfer {
  index: number;
  sortingCost: number;
}

const NFT_FAKE_COST_USD = 1_000_000_000;

const skeletonRows: DappSkeletonRow[] = [
  { isLarge: false, hasFee: false },
  { isLarge: true, hasFee: true },
];

function DappTransferInitial({
  transactions,
  totalAmountsBySlug,
  emulation,
  isScam,
  isDangerous,
  nftCount,
  dapp,
  isLoading,
  tokensBySlug,
  swapTokensBySlug,
  theme,
  baseCurrency,
  currencyRates,
  nftsByAddress,
  currentAccountId,
  stakingStateBySlug,
  savedAddresses,
  accounts,
  insufficientTokens,
  balancesBySlug,
  onClose,
  chain,
  shouldHideTransfers,
}: OwnProps & StateProps) {
  const { closeDappTransfer, showDappTransferTransaction, submitDappTransferConfirm } = getActions();

  const lang = useLang();
  const appTheme = useAppTheme(theme);
  const renderingTransactions = useCurrentOrPrev(transactions, true);
  const sortedTransactions = useMemo(
    () => sortTransactions(renderingTransactions, tokensBySlug),
    [renderingTransactions, tokensBySlug],
  );
  const isDappLoading = dapp === undefined;
  const hasSufficientBalance = !insufficientTokens;

  const tokenToDisplay = useMemo(() => (
    calculateTokenToDisplay(chain || DEFAULT_CHAIN, totalAmountsBySlug, balancesBySlug, tokensBySlug)
  ), [chain, totalAmountsBySlug, balancesBySlug, tokensBySlug]);

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
        {isDangerous && (
          <div className={buildClassName(styles.transferWarning, styles.warningForPayload)}>
            {renderText(lang('$hardware_payload_warning'))}
          </div>
        )}
        {renderTransactions()}
        {renderEmulation()}

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
              isSubmit
              isLoading={isLoading}
              isDisabled={isScam || !hasSufficientBalance}
              className={modalStyles.button}
              onClick={!isScam && hasSufficientBalance ? submitDappTransferConfirm : undefined}
            >
              {lang('Send')}
            </Button>
          </div>
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
    if (!renderingTransactions) {
      return undefined;
    }

    const hasAmount = nftCount > 0 || !isEmptyObject(totalAmountsBySlug);

    return (
      <>
        {!shouldHideTransfers && (
          <p className={styles.label}>{lang('$many_transactions', renderingTransactions.length, 'i')}</p>
        )}
        {!shouldHideTransfers && (
          <div className={styles.transactionList}>
            {sortedTransactions?.map(renderTransactionRow)}
          </div>
        )}
        {renderingTransactions.length > 1 && hasAmount && (
          <DappAmountField label={lang('Total Amount')} amountsBySlug={totalAmountsBySlug} nftCount={nftCount} />
        )}
      </>
    );
  }

  function renderEmulation() {
    if (!emulation?.activities?.length) {
      return undefined;
    }

    const { activities, realFee } = emulation;

    const visibleActivities = activities.filter((activity) => !activity.shouldHide);

    return (
      <>
        <p className={styles.label}>
          {lang('Preview')}
          {' '}
          <IconWithTooltip message={renderText(lang('$preview_not_guaranteed'))} type="warning" size="small" />
        </p>
        <div className={buildClassName(styles.transactionList, styles.emulation)}>
          {visibleActivities.map((activity, index) => (
            <Activity
              key={activity.id}
              activity={activity}
              isFuture
              isLast={index === visibleActivities.length - 1}
              tokensBySlug={tokensBySlug}
              swapTokensBySlug={swapTokensBySlug}
              appTheme={appTheme}
              nftsByAddress={nftsByAddress}
              currentAccountId={currentAccountId}
              stakingStateBySlug={stakingStateBySlug}
              savedAddresses={savedAddresses}
              accounts={accounts}
              baseCurrency={baseCurrency}
              currencyRates={currencyRates}
            />
          ))}
        </div>
        {realFee !== 0n && (
          <FeeLine
            terms={{ native: realFee }}
            token={getChainConfig(chain || DEFAULT_CHAIN).nativeToken}
            precision="approximate"
            className={styles.emulationFee}
          />
        )}
      </>
    );
  }

  return (
    <Transition name="semiFade" activeKey={isDappLoading ? 0 : 1} slideClassName={styles.skeletonTransitionWrapper}>
      <ModalHeader
        title={lang(
          isNftTransferPayload(renderingTransactions?.[0]?.payload)
            ? 'Send NFT'
            : (renderingTransactions?.length ?? 0) > 1
              ? '$classic_confirm_actions'
              : 'Confirm Action',
        )}
        onClose={closeDappTransfer}
      />
      {isDappLoading ? <DappSkeletonWithContent rows={skeletonRows} /> : renderContent()}
    </Transition>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const { isLoading, dapp, transactions, emulation, operationChain, shouldHideTransfers } = global.currentDappTransfer;

  const accountId = selectCurrentAccountId(global)!;
  const accountState = selectCurrentAccountState(global);
  const accounts = selectNetworkAccounts(global);

  const {
    amountsBySlug: totalAmountsBySlug,
    isScam,
    isDangerous,
    nftCount,
  } = selectCurrentDappTransferTotals(global);

  return {
    transactions,
    totalAmountsBySlug,
    emulation,
    isScam,
    isDangerous,
    nftCount,
    dapp,
    isLoading,
    tokensBySlug: global.tokenInfo.bySlug,
    swapTokensBySlug: global.swapTokenInfo?.bySlug,
    theme: global.settings.theme,
    baseCurrency: global.settings.baseCurrency,
    currencyRates: global.currencyRates,
    nftsByAddress: accountState?.nfts?.byAddress,
    currentAccountId: accountId,
    stakingStateBySlug: selectAccountStakingStatesBySlug(global, accountId),
    savedAddresses: accountState?.savedAddresses,
    accounts,
    insufficientTokens: selectDappTransferInsufficientTokens(global),
    balancesBySlug: accountState?.balances?.bySlug,
    chain: operationChain,
    shouldHideTransfers: !!shouldHideTransfers,
  };
})(DappTransferInitial));

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

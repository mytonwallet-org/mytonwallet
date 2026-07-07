import React, { memo, useMemo } from '../../lib/teact/teact';

import type { ApiChain, ApiSwapActivity, ApiSwapAsset } from '../../api/types';

import { TONCOIN } from '../../config';
import { Big } from '../../lib/big.js';
import { resolveSwapAsset } from '../../global/helpers';
import { getIsActivityPendingForUser } from '../../util/activities';
import { getSwapTransactionIdRows } from '../../util/swap/transactionIds';
import { getExplorerTransactionUrl } from '../../util/url';

import useLang from '../../hooks/useLang';

import InteractiveTextField from '../ui/InteractiveTextField';
import SwapTokensInfo from './SwapTokensInfo';
import TransactionFee from './TransactionFee';

import styles from './SwapActivityInfo.module.scss';

interface OwnProps {
  activity: ApiSwapActivity;
  tokensBySlug?: Record<string, ApiSwapAsset>;
  isSensitiveDataHidden?: boolean;
  selectedExplorerIds?: Partial<Record<ApiChain, string>>;
}

const ONCHAIN_ERROR_STATUSES = new Set(['expired', 'failed']);

function SwapActivityInfo({
  activity,
  tokensBySlug,
  isSensitiveDataHidden,
  selectedExplorerIds,
}: OwnProps) {
  const lang = useLang();

  const {
    from,
    fromAmount,
    to,
    toAmount,
    status,
    networkFee = '0',
    ourFee = '0',
    ourFeeMode,
    shouldLoadDetails,
    cex,
  } = activity;

  const fromToken = useMemo(() => {
    if (!from || !tokensBySlug) return undefined;
    return resolveSwapAsset(tokensBySlug, from);
  }, [from, tokensBySlug]);

  const toToken = useMemo(() => {
    if (!to || !tokensBySlug) return undefined;
    return resolveSwapAsset(tokensBySlug, to);
  }, [to, tokensBySlug]);

  const isFromToncoin = from === TONCOIN.slug;
  const isPending = getIsActivityPendingForUser(activity);
  const isError = ONCHAIN_ERROR_STATUSES.has(status) || (cex && status === 'failed');

  const transactionIdRows = getSwapTransactionIdRows(activity);

  function renderFee() {
    if (!(Number(networkFee) || shouldLoadDetails) || !fromToken) {
      return undefined;
    }

    const isOurFeeIncluded = ourFeeMode === 'included';
    const terms = isFromToncoin ? {
      native: isOurFeeIncluded ? networkFee : Big(networkFee).add(ourFee).toString(),
    } : {
      native: networkFee,
      token: isOurFeeIncluded ? undefined : ourFee,
    };

    return (
      <TransactionFee
        terms={terms}
        token={fromToken}
        precision={isPending ? 'approximate' : 'exact'}
        isLoading={shouldLoadDetails}
      />
    );
  }

  function renderTransactionIds() {
    if (!transactionIdRows.length) return undefined;

    return transactionIdRows.map(({ label, hash, chain }) => (
      <div key={`${label}-${hash}`} className={styles.textFieldWrapper}>
        <span className={styles.textFieldLabel}>
          {lang(label)}
        </span>
        <InteractiveTextField
          noSavedAddress
          chain={chain}
          address={hash}
          addressUrl={getExplorerTransactionUrl(chain, hash, undefined, selectedExplorerIds?.[chain])}
          isTransaction
          copyNotification={lang('Transaction ID Copied')}
        />
      </div>
    ));
  }

  return (
    <div className={styles.root}>
      <SwapTokensInfo
        tokenIn={fromToken}
        amountIn={fromAmount}
        tokenOut={toToken}
        amountOut={toAmount}
        isError={isError}
        isSensitiveDataHidden={isSensitiveDataHidden || undefined}
      />

      <div className={styles.infoBlock}>
        {renderFee()}
        {renderTransactionIds()}
      </div>
    </div>
  );
}

export default memo(SwapActivityInfo);

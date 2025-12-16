import React, { memo, useMemo } from '../../lib/teact/teact';

import type { ApiSwapActivity, ApiSwapAsset } from '../../api/types';

import { TONCOIN } from '../../config';
import { Big } from '../../lib/big.js';
import { resolveSwapAsset } from '../../global/helpers';
import { getIsActivityPendingForUser, parseTxId } from '../../util/activities';
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
}

const ONCHAIN_ERROR_STATUSES = new Set(['expired', 'failed']);

function SwapActivityInfo({
  activity,
  tokensBySlug,
  isSensitiveDataHidden,
}: OwnProps) {
  const lang = useLang();

  const {
    id,
    hashes,
    from,
    fromAmount,
    to,
    toAmount,
    status,
    networkFee = '0',
    ourFee = '0',
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

  const isCex = Boolean(cex);
  const isFromToncoin = from === TONCOIN.slug;
  const isPending = getIsActivityPendingForUser(activity);
  const isError = ONCHAIN_ERROR_STATUSES.has(status) || (cex && status === 'failed');

  const transactionHash = id ? (isCex ? hashes?.[0] : parseTxId(id).hash) : undefined;
  const transactionUrl = transactionHash ? getExplorerTransactionUrl('ton', transactionHash) : undefined;

  function renderFee() {
    if (!(Number(networkFee) || shouldLoadDetails) || !fromToken) {
      return undefined;
    }

    const terms = isFromToncoin ? {
      native: Big(networkFee).add(ourFee).toString(),
    } : {
      native: networkFee,
      token: ourFee,
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

  function renderTransactionId() {
    if (!transactionHash) return undefined;

    return (
      <div className={styles.textFieldWrapper}>
        <span className={styles.textFieldLabel}>
          {lang('Transaction ID')}
        </span>
        <InteractiveTextField
          noSavedAddress
          chain="ton"
          address={transactionHash}
          addressUrl={transactionUrl}
          isTransaction
          copyNotification={lang('Transaction ID was copied!')}
        />
      </div>
    );
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
        {renderTransactionId()}
      </div>
    </div>
  );
}

export default memo(SwapActivityInfo);

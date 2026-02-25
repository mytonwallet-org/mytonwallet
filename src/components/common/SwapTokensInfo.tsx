import React, { memo } from '../../lib/teact/teact';

import type { ApiSwapAsset, ApiToken } from '../../api/types';
import type { UserSwapToken } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import { formatCurrencyExtended } from '../../util/formatNumber';
import getChainNetworkName from '../../util/swap/getChainNetworkName';
import getSwapRate from '../../util/swap/getSwapRate';

import SensitiveData from '../ui/SensitiveData';
import TokenIcon from './TokenIcon';

import styles from './SwapTokensInfo.module.scss';

interface OwnProps {
  isSensitiveDataHidden?: true;
  tokenIn?: UserSwapToken | ApiSwapAsset | ApiToken;
  amountIn?: string;
  tokenOut?: UserSwapToken | ApiSwapAsset | ApiToken;
  amountOut?: string;
  isError?: boolean;
  onTokenClick?: (slug: string) => void;
}

function SwapTokensInfo({
  isSensitiveDataHidden, tokenIn, amountIn, tokenOut, amountOut, isError = false, onTokenClick,
}: OwnProps) {
  function handleTokenClick(token?: UserSwapToken | ApiSwapAsset | ApiToken) {
    if (onTokenClick && token?.slug) {
      onTokenClick(token.slug);
    }
  }

  function renderTokenInfo(
    seed: string,
    token?: UserSwapToken | ApiSwapAsset | ApiToken,
    amount = '0',
    isReceived = false,
  ) {
    const amountWithSign = isReceived ? amount : `-${Math.abs(Number(amount)).toString()}`;
    const withLabel = Boolean(token && token.label);
    const isClickable = Boolean(onTokenClick && token?.slug);

    return (
      <div
        className={buildClassName(
          styles.infoRow,
          !token && styles.noIcon,
          isReceived && styles.noCurrency,
          isClickable && styles.clickable,
        )}
        onClick={isClickable ? () => handleTokenClick(token) : undefined}
      >
        {Boolean(token) && (
          <TokenIcon
            token={token}
            withChainIcon
            className={styles.infoRowIcon}
          />
        )}

        <span className={styles.infoRowToken}>
          {token?.name}
          {withLabel && (
            <span className={buildClassName(styles.label, styles.chainLabel)}>{token!.label}</span>
          )}
        </span>
        <SensitiveData
          isActive={isSensitiveDataHidden}
          min={5}
          max={13}
          seed={seed}
          rows={2}
          cellSize={8}
          align="right"
          className={buildClassName(
            styles.infoRowAmount,
            isReceived && styles.infoRowAmountGreen,
            isError && styles.infoRowAmountError,
          )}
        >
          {formatCurrencyExtended(amountWithSign, token?.symbol ?? '')}
        </SensitiveData>
        <span className={styles.infoRowChain}>{getChainNetworkName(token?.chain)}</span>
        {!isReceived && renderCurrency(
          Math.abs(Number(amountIn)).toString(),
          Math.abs(Number(amountOut)).toString(),
          tokenIn,
          tokenOut,
        )}
      </div>
    );
  }

  return (
    <div className={styles.infoBlock}>
      {renderTokenInfo(amountIn ?? '', tokenIn, amountIn)}
      <div className={styles.infoSeparator}>
        <i
          className={buildClassName(
            styles.infoSeparatorIcon,
            isError && styles.infoSeparatorIconError,
            isError ? 'icon-close' : 'icon-arrow-down',
          )}
          aria-hidden
        />
      </div>
      {renderTokenInfo(amountOut ?? '', tokenOut, amountOut, true)}
    </div>
  );
}

export default memo(SwapTokensInfo);

function renderCurrency(
  amountIn?: string,
  amountOut?: string,
  fromToken?: ApiSwapAsset | ApiToken,
  toToken?: ApiSwapAsset | ApiToken,
) {
  const rate = getSwapRate(amountIn, amountOut, fromToken, toToken);
  if (!rate) return undefined;

  return (
    <span className={styles.infoRowCurrency}>
      {rate.firstCurrencySymbol} ≈
      <span className={styles.infoRowCurrencyValue}>
        {rate.price}{' '}{rate.secondCurrencySymbol}
      </span>
    </span>
  );
}

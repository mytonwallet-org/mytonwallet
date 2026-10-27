import React, { memo } from '../../lib/teact/teact';

import type { ApiSwapCexLabel, ApiSwapRouteType } from '../../api/types';
import type { UserSwapToken } from '../../global/types';
import { SwapType } from '../../global/types';

import buildClassName from '../../util/buildClassName';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';

import SwapResult from '../common/SwapResult';
import Button from '../ui/Button';
import ModalHeader from '../ui/ModalHeader';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Swap.module.scss';

interface OwnProps {
  isActive: boolean;
  tokenIn?: UserSwapToken;
  tokenOut?: UserSwapToken;
  amountIn?: string;
  amountOut?: string;
  swapType?: SwapType;
  swapRoute?: ApiSwapRouteType;
  cexLabel?: ApiSwapCexLabel;
  toAddress?: string;
  onInfoClick: NoneToVoidFunction;
  onStartSwap: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
  isDetailsDisabled?: boolean;
}

function SwapComplete({
  isActive,
  tokenIn,
  tokenOut,
  amountIn,
  amountOut,
  swapType,
  swapRoute,
  cexLabel,
  toAddress,
  onInfoClick,
  onStartSwap,
  onClose,
  isDetailsDisabled,
}: OwnProps) {
  const lang = useLang();
  const isDex = (swapRoute ?? (swapType === SwapType.OnChain ? 'dex' : 'cex')) === 'dex';
  const title = lang(isDex ? 'Swapped' : 'Swap Placed');

  useHistoryBack({
    isActive,
    onBack: onClose,
  });

  return (
    <>
      <ModalHeader title={title} onClose={onClose} />

      <div className={buildClassName(styles.scrollContent, 'custom-scroll')}>
        <SwapResult
          tokenIn={tokenIn}
          amountIn={amountIn}
          tokenOut={tokenOut}
          amountOut={amountOut}
          swapType={swapType}
          swapRoute={swapRoute}
          cexLabel={cexLabel}
          toAddress={toAddress}
          playAnimation={isActive}
          firstButtonText={lang('Details')}
          secondButtonText={lang('Repeat')}
          onFirstButtonClick={onInfoClick}
          onSecondButtonClick={onStartSwap}
          isFirstButtonDisabled={isDetailsDisabled}
        />

        <div className={modalStyles.buttons}>
          <Button onClick={onClose} isPrimary>{lang('Close')}</Button>
        </div>
      </div>
    </>
  );
}

export default memo(SwapComplete);

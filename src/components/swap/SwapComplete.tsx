import React, { memo } from '../../lib/teact/teact';

import type { ApiSwapCexLabel } from '../../api/types';
import type { SwapType, UserSwapToken } from '../../global/types';

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
  cexLabel,
  toAddress,
  onInfoClick,
  onStartSwap,
  onClose,
  isDetailsDisabled,
}: OwnProps) {
  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack: onClose,
  });

  return (
    <>
      <ModalHeader title={lang('Swap Placed')} onClose={onClose} />

      <div className={buildClassName(styles.scrollContent, 'custom-scroll')}>
        <SwapResult
          tokenIn={tokenIn}
          amountIn={amountIn}
          tokenOut={tokenOut}
          amountOut={amountOut}
          swapType={swapType}
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

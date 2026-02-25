import React, { memo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { Account, UserSwapToken } from '../../global/types';
import { SwapType } from '../../global/types';

import { selectCurrentAccount } from '../../global/selectors';
import { getChainTitle, getIsSupportedChain } from '../../util/chain';
import getChainNetworkName from '../../util/swap/getChainNetworkName';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useLang from '../../hooks/useLang';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import InteractiveTextField from '../ui/InteractiveTextField';
import SwapTokensInfo from './SwapTokensInfo';

import styles from './SwapResult.module.scss';

interface OwnProps {
  tokenIn?: UserSwapToken;
  tokenOut?: UserSwapToken;
  amountIn?: string;
  amountOut?: string;
  playAnimation?: boolean;
  firstButtonText?: string;
  secondButtonText?: string;
  swapType?: SwapType;
  toAddress?: string;
  onFirstButtonClick?: NoneToVoidFunction;
  onSecondButtonClick?: NoneToVoidFunction;
  isFirstButtonDisabled?: boolean;
}

interface StateProps {
  accountChains?: Account['byChain'];
  isSensitiveDataHidden?: true;
}

function SwapResult({
  tokenIn,
  tokenOut,
  amountIn,
  amountOut,
  playAnimation,
  firstButtonText,
  secondButtonText,
  swapType,
  toAddress = '',
  isSensitiveDataHidden,
  onFirstButtonClick,
  onSecondButtonClick,
  isFirstButtonDisabled,
}: OwnProps & StateProps) {
  const lang = useLang();

  function renderButtons() {
    if (!firstButtonText && !secondButtonText) {
      return undefined;
    }

    return (
      <div className={styles.buttons}>
        {firstButtonText && (
          <Button
            className={styles.button}
            onClick={onFirstButtonClick}
            isDisabled={isFirstButtonDisabled}
          >
            {firstButtonText}
          </Button>
        )}
        {secondButtonText && (
          <Button className={styles.button} onClick={onSecondButtonClick}>{secondButtonText}</Button>
        )}
      </div>
    );
  }

  function renderSticker() {
    if (swapType === SwapType.CrosschainFromWallet) return undefined;

    return (
      <AnimatedIconWithPreview
        play={playAnimation}
        noLoop={false}
        nonInteractive
        className={styles.sticker}
        tgsUrl={ANIMATED_STICKERS_PATHS.thumbUp}
        previewUrl={ANIMATED_STICKERS_PATHS.thumbUpPreview}
      />
    );
  }

  function renderTimeWarning() {
    return (
      <div className={styles.changellyInfoBlock}>
        <span className={styles.changellyDescription}>
          {lang('Please note that it may take up to a few hours for tokens to appear in your wallet.')}
        </span>
      </div>
    );
  }

  function renderChangellyInfo() {
    if (swapType !== SwapType.CrosschainFromWallet) {
      return undefined;
    }
    const chain = getIsSupportedChain(tokenOut?.chain) ? tokenOut.chain : undefined;

    return (
      <div className={styles.changellyInfoBlock}>
        <span className={styles.changellyDescription}>
          {
            lang('$swap_changelly_from_wallet_description', {
              blockchain: (
                <span className={styles.changellyDescriptionBold}>
                  {getChainNetworkName(tokenOut?.chain)}
                </span>
              ),
            })
          }
        </span>
        <InteractiveTextField
          chain={chain}
          address={toAddress}
          copyNotification={lang('%chain% Address Copied', { chain: chain ? getChainTitle(chain) : '' }) as string}
          noSavedAddress
          noExplorer
          className={styles.changellyTextField}
        />
      </div>
    );
  }

  return (
    <>
      {renderSticker()}

      <SwapTokensInfo
        isSensitiveDataHidden={isSensitiveDataHidden}
        tokenIn={tokenIn}
        amountIn={amountIn}
        tokenOut={tokenOut}
        amountOut={amountOut}
      />

      {swapType !== SwapType.OnChain && renderTimeWarning()}
      {renderChangellyInfo()}

      {renderButtons()}
    </>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    accountChains: selectCurrentAccount(global)?.byChain,
    isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
  };
})(SwapResult));

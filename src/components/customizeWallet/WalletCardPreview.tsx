import React, {
  memo, useLayoutEffect, useMemo, useRef,
} from '../../lib/teact/teact';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiNft } from '../../api/types';
import type { Account, UserToken } from '../../global/types';

import { IS_GRAM_WALLET } from '../../config';
import buildClassName from '../../util/buildClassName';
import { calculateFullBalance } from '../../util/calculateFullBalance';
import { getShortCurrencySymbol } from '../../util/formatNumber';
import { IS_IOS, IS_SAFARI } from '../../util/windowEnvironment';

import useCardArtwork from '../../hooks/useCardArtwork';
import useCardController from '../../hooks/useCardController';
import useCardCustomization from '../../hooks/useCardCustomization';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useWindowSize from '../../hooks/useWindowSize';
import useFontScalePreview from './hooks/useFontScalePreview';

import CardAddress from '../main/sections/Card/CardAddress';
import CardSurface from '../main/sections/Card/CardSurface';
import AnimatedCounter from '../ui/AnimatedCounter';
import CardTilt from '../ui/CardTilt';
import CardArtwork from './CardArtwork';

import styles from './WalletCardPreview.module.scss';

interface OwnProps {
  account?: Account;
  tokens?: UserToken[];
  baseCurrency?: ApiBaseCurrency;
  currencyRates?: ApiCurrencyRates;
  previewCardNft?: ApiNft;
  isDark?: boolean;
  isAnimationDisabled?: boolean;
  isTiltDisabled?: boolean;
  variant: 'left' | 'right' | 'middle';
}

function WalletCardPreview({
  account,
  tokens,
  baseCurrency = 'USD',
  currencyRates,
  previewCardNft,
  isDark,
  isAnimationDisabled,
  isTiltDisabled,
  variant,
}: OwnProps) {
  const amountRef = useRef<HTMLDivElement>();
  const { cardRef, controller, handleMotionFrame } = useCardController();
  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);
  const { nft: shownCardNft, imageUrl: cardImageUrl } = useCardArtwork(previewCardNft, IS_GRAM_WALLET);
  const { classNames: customCardClassName, withTextGradient } = useCardCustomization(shownCardNft);

  const { isPortrait } = useDeviceScreen();
  const { width: screenWidth } = useWindowSize();
  const { updateFontScale } = useFontScalePreview(amountRef, '--font-size-scale-preview');
  const screenWidthDep = isPortrait ? screenWidth : 0;

  const values = useMemo(() => {
    if (!tokens || !currencyRates) return undefined;
    return calculateFullBalance(tokens, undefined, currencyRates[baseCurrency]);
  }, [tokens, currencyRates, baseCurrency]);

  const accountTitle = account?.title || 'My Wallet';

  const { primaryValue, primaryWholePart, primaryFractionPart } = values || {};

  useLayoutEffect(() => {
    if (primaryValue !== undefined) {
      updateFontScale();
    }
  }, [primaryFractionPart, primaryValue, primaryWholePart, shortBaseSymbol, updateFontScale, screenWidthDep]);

  function renderBalance() {
    const noAnimationCounter = IS_SAFARI || IS_IOS;

    return (
      <>
        <div className={styles.walletName}>{accountTitle}</div>
        <div ref={amountRef} className={buildClassName(styles.primaryValue, 'rounded-font')}>
          <span className={buildClassName(styles.currencySwitcher, withTextGradient && 'gradientText')}>
            {shortBaseSymbol.length === 1 && <span className={styles.currencySymbol}>{shortBaseSymbol}</span>}
            <AnimatedCounter isDisabled={noAnimationCounter} text={primaryWholePart ?? ''} />
            {primaryFractionPart && (
              <span className={styles.primaryFractionPart}>
                <AnimatedCounter isDisabled={noAnimationCounter} text={`.${primaryFractionPart}`} />
              </span>
            )}
            {shortBaseSymbol.length > 1 && (
              <span className={styles.primaryFractionPart}>&nbsp;{shortBaseSymbol}</span>
            )}
          </span>
        </div>
        <CardAddress isMinimized withTextGradient={withTextGradient} />
      </>
    );
  }

  const isMiddle = variant === 'middle';
  const card = (
    <div ref={cardRef} className={buildClassName(styles.container, customCardClassName, styles[variant])}>
      {isMiddle ? (
        <CardSurface
          nft={shownCardNft}
          imageUrl={cardImageUrl}
          isGram={IS_GRAM_WALLET}
          isDark={Boolean(isDark)}
          isDisabled={Boolean(isTiltDisabled)}
          noSwitchAnimation={isAnimationDisabled}
          noDepth
          controller={controller}
        />
      ) : (
        <CardArtwork />
      )}

      <div className={buildClassName(styles.containerInner, customCardClassName)}>
        {values ? renderBalance() : (
          <div className={styles.walletName}>{accountTitle}</div>
        )}
      </div>
    </div>
  );

  if (!isMiddle) return card;

  return (
    <CardTilt isDisabled={isTiltDisabled} className={styles.tilt} onMotionFrame={handleMotionFrame}>
      {card}
    </CardTilt>
  );
}

export default memo(WalletCardPreview);

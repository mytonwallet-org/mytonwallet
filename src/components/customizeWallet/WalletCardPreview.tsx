import React, {
  memo, useLayoutEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiNft } from '../../api/types';
import type { Account, UserToken } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import { getShortCurrencySymbol } from '../../util/formatNumber';
import { IS_IOS, IS_SAFARI } from '../../util/windowEnvironment';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLastCallback from '../../hooks/useLastCallback';
import useWindowSize from '../../hooks/useWindowSize';
import useFontScalePreview from './hooks/useFontScalePreview';

import CardAddress from '../main/sections/Card/CardAddress';
import CustomCardManager from '../main/sections/Card/CustomCardManager';
import { calculateFullBalance } from '../main/sections/Card/helpers/calculateFullBalance';
import AnimatedCounter from '../ui/AnimatedCounter';

import styles from './WalletCardPreview.module.scss';

interface OwnProps {
  account?: Account;
  tokens?: UserToken[];
  baseCurrency?: ApiBaseCurrency;
  currencyRates?: ApiCurrencyRates;
  previewCardNft?: ApiNft;
  variant: 'left' | 'right' | 'middle';
}

function WalletCardPreview({
  account,
  tokens,
  baseCurrency = 'USD',
  currencyRates,
  previewCardNft,
  variant,
}: OwnProps) {
  const amountRef = useRef<HTMLDivElement>();
  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);
  const [customCardClassName, setCustomCardClassName] = useState<string | undefined>(undefined);
  const [withTextGradient, setWithTextGradient] = useState<boolean>(false);

  const { isPortrait } = useDeviceScreen();
  const { width: screenWidth } = useWindowSize();
  const { updateFontScale } = useFontScalePreview(amountRef, '--font-size-scale-preview');
  const screenWidthDep = isPortrait ? screenWidth : 0;

  const values = useMemo(() => {
    if (!tokens || !currencyRates) return undefined;
    return calculateFullBalance(tokens, undefined, currencyRates[baseCurrency]);
  }, [tokens, currencyRates, baseCurrency]);

  const accountTitle = account?.title || 'MyTonWallet';

  const handleCardChange = useLastCallback((hasGradient: boolean, className?: string) => {
    setCustomCardClassName(className);
    setWithTextGradient(hasGradient);
  });

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

  return (
    <div className={buildClassName(styles.container, customCardClassName, styles[variant])}>
      <CustomCardManager nft={previewCardNft} onCardChange={handleCardChange} className={styles.customCardManager} />

      <div className={buildClassName(styles.containerInner, customCardClassName)}>
        {values ? renderBalance() : (
          <div className={styles.walletName}>{accountTitle}</div>
        )}
      </div>
    </div>
  );
}

export default memo(WalletCardPreview);

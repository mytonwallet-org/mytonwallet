import React, {
  memo, useLayoutEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiNft } from '../../api/types';
import type { UserToken } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import { getShortCurrencySymbol } from '../../util/formatNumber';
import { DEFAULT_CARD_ADDRESS } from './constants';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLastCallback from '../../hooks/useLastCallback';
import useWindowSize from '../../hooks/useWindowSize';
import useFontScalePreview from './hooks/useFontScalePreview';

import CustomCardManager from '../main/sections/Card/CustomCardManager';
import { calculateFullBalance } from '../main/sections/Card/helpers/calculateFullBalance';

import styles from './NftCardItem.module.scss';

interface OwnProps {
  card?: ApiNft;
  isSelected: boolean;
  tokens?: UserToken[];
  baseCurrency?: ApiBaseCurrency;
  currencyRates?: ApiCurrencyRates;
  onClick: (address: string) => void;
}

function NftCardItem({
  card, isSelected, tokens, baseCurrency = 'USD', currencyRates, onClick,
}: OwnProps) {
  const balanceRef = useRef<HTMLDivElement>();
  const [customCardClassName, setCustomCardClassName] = useState<string | undefined>(undefined);
  const [withTextGradient, setWithTextGradient] = useState<boolean>(false);

  const { isPortrait } = useDeviceScreen();
  const { width: screenWidth } = useWindowSize();
  const { updateFontScale } = useFontScalePreview(balanceRef, '--font-size-scale-mini');
  const screenWidthDep = isPortrait ? screenWidth : 0;

  const balance = useMemo(() => {
    if (!tokens || !currencyRates) return undefined;
    return calculateFullBalance(tokens, undefined, currencyRates[baseCurrency]);
  }, [tokens, currencyRates, baseCurrency]);

  const { primaryValue, primaryWholePart, primaryFractionPart } = balance || {};
  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);

  useLayoutEffect(() => {
    if (primaryValue !== undefined) {
      updateFontScale();
    }
  }, [primaryFractionPart, primaryValue, primaryWholePart, shortBaseSymbol, updateFontScale, screenWidthDep]);

  const handleClick = useLastCallback(() => {
    onClick(card?.address ?? DEFAULT_CARD_ADDRESS);
  });

  const handleCardChange = useLastCallback((hasGradient: boolean, className?: string) => {
    setCustomCardClassName(className);
    setWithTextGradient(hasGradient);
  });

  return (
    <div
      className={buildClassName(
        styles.cardWrapper,
        isSelected && styles.selected,
      )}
      onClick={handleClick}
      role="button"
      tabIndex={0}
    >
      <div className={buildClassName(styles.card, customCardClassName, 'rounded-font')}>
        <CustomCardManager
          nft={card}
          onCardChange={handleCardChange}
          className={styles.customCardManager}
          shadowClassName={styles.customCardShadow}
        />
        <div className={buildClassName(styles.cardContent, customCardClassName)}>
          <div
            ref={balanceRef}
            className={buildClassName(styles.balance, withTextGradient && 'gradientText')}
          >
            {primaryWholePart !== undefined ? (
              <>
                {shortBaseSymbol.length === 1 && (
                  <span className={styles.balanceSymbol}>{shortBaseSymbol}</span>
                )}
                <span className={styles.balanceWhole}>{primaryWholePart}</span>
                {primaryFractionPart && (
                  <span className={styles.balanceFraction}>.{primaryFractionPart}</span>
                )}
                {shortBaseSymbol.length > 1 && (
                  <span className={styles.balanceFraction}>&nbsp;{shortBaseSymbol}</span>
                )}
              </>
            ) : (
              <span className={styles.balanceWhole}>—</span>
            )}
          </div>
          <div className={buildClassName(styles.bar, withTextGradient && 'gradientText')} />
        </div>
      </div>
    </div>
  );
}

export default memo(NftCardItem);

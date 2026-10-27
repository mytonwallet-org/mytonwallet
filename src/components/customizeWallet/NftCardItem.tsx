import React, {
  memo, useLayoutEffect, useMemo, useRef,
} from '../../lib/teact/teact';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiNft } from '../../api/types';
import type { UserToken } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import { calculateFullBalance } from '../../util/calculateFullBalance';
import { getShortCurrencySymbol } from '../../util/formatNumber';
import { DEFAULT_CARD_ADDRESS } from './constants';

import useCardCustomization from '../../hooks/useCardCustomization';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLastCallback from '../../hooks/useLastCallback';
import useWindowSize from '../../hooks/useWindowSize';
import useFontScalePreview from './hooks/useFontScalePreview';

import CardArtwork from './CardArtwork';

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
  const { classNames: customCardClassName, withTextGradient } = useCardCustomization(card);

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
        <CardArtwork nft={card} />
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

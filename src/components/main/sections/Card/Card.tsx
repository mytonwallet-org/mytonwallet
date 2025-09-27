import React, {
  type ElementRef,
  memo, useEffect, useLayoutEffect, useMemo, useRef, useState,
} from '../../../../lib/teact/teact';
import { withGlobal } from '../../../../global';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiNft, ApiStakingState } from '../../../../api/types';
import type { IAnchorPosition, UserToken } from '../../../../global/types';

import { IS_CORE_WALLET } from '../../../../config';
import {
  selectAccountStakingStates,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectCurrentAccountTokens,
  selectIsCurrentAccountViewMode,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import captureEscKeyListener from '../../../../util/captureEscKeyListener';
import { formatCurrency, getShortCurrencySymbol } from '../../../../util/formatNumber';
import { IS_IOS, IS_SAFARI } from '../../../../util/windowEnvironment';
import { calculateFullBalance } from './helpers/calculateFullBalance';
import getSensitiveDataMaskSkinFromCardNft from './helpers/getSensitiveDataMaskSkinFromCardNft';

import useCurrentOrPrev from '../../../../hooks/useCurrentOrPrev';
import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useFontScale from '../../../../hooks/useFontScale';
import useHistoryBack from '../../../../hooks/useHistoryBack';
import useLastCallback from '../../../../hooks/useLastCallback';
import useShowTransition from '../../../../hooks/useShowTransition';
import useUpdateIndicator from '../../../../hooks/useUpdateIndicator';
import useWindowSize from '../../../../hooks/useWindowSize';

import MintCardButton from '../../../mintCard/MintCardButton';
import AnimatedCounter from '../../../ui/AnimatedCounter';
import LoadingDots from '../../../ui/LoadingDots';
import SensitiveData from '../../../ui/SensitiveData';
import Spinner from '../../../ui/Spinner';
import Transition from '../../../ui/Transition';
import CardAddress from './CardAddress';
import CurrencySwitcherMenu from './CurrencySwitcherMenu';
import CustomCardManager from './CustomCardManager';
import TokenCard from './TokenCard';

import styles from './Card.module.scss';

interface OwnProps {
  ref?: ElementRef<HTMLDivElement>;
  onTokenCardClose: NoneToVoidFunction;
  onYieldClick: (stakingId?: string) => void;
}

interface StateProps {
  tokens?: UserToken[];
  currentTokenSlug?: string;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  stakingStates?: ApiStakingState[];
  cardNft?: ApiNft;
  isSensitiveDataHidden?: true;
  isNftBuyingDisabled: boolean;
  isViewMode: boolean;
}

function Card({
  ref,
  tokens,
  currentTokenSlug,
  onTokenCardClose,
  onYieldClick,
  baseCurrency,
  currencyRates,
  stakingStates,
  isSensitiveDataHidden,
  isNftBuyingDisabled,
  cardNft,
  isViewMode,
}: OwnProps & StateProps) {
  const amountRef = useRef<HTMLDivElement>();
  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);
  const [customCardClassName, setCustomCardClassName] = useState<string | undefined>(undefined);
  const [withTextGradient, setWithTextGradient] = useState<boolean>(false);

  const { isPortrait } = useDeviceScreen();
  const { width: screenWidth } = useWindowSize();
  const isUpdating = useUpdateIndicator('balanceUpdateStartedAt');
  const { updateFontScale } = useFontScale(amountRef);
  // Screen width affects font size only in portrait orientation
  const screenWidthDep = isPortrait ? screenWidth : 0;

  const [currencyMenuAnchor, setCurrencyMenuAnchor] = useState<IAnchorPosition>();
  const currentToken = useMemo(() => {
    return tokens ? tokens.find((token) => token.slug === currentTokenSlug) : undefined;
  }, [currentTokenSlug, tokens]);
  const renderedToken = useCurrentOrPrev(currentToken, true);
  const {
    shouldRender: shouldRenderTokenCard,
    ref: tokenCardRef,
  } = useShowTransition({
    isOpen: Boolean(currentTokenSlug),
    noMountTransition: true,
    withShouldRender: true,
  });
  const sensitiveDataMaskSkin = getSensitiveDataMaskSkinFromCardNft(cardNft);

  const openCurrencyMenu = () => {
    const { left, width, bottom: y } = amountRef.current!.getBoundingClientRect();
    setCurrencyMenuAnchor({ x: left + width / 2, y });
  };

  const closeCurrencyMenu = useLastCallback(() => {
    setCurrencyMenuAnchor(undefined);
  });

  const handleCardChange = useLastCallback((hasGradient: boolean, className?: string) => {
    setCustomCardClassName(className);
    setWithTextGradient(hasGradient);
  });

  const values = useMemo(() => {
    return tokens ? calculateFullBalance(tokens, stakingStates, currencyRates[baseCurrency]) : undefined;
  }, [tokens, stakingStates, currencyRates, baseCurrency]);

  useHistoryBack({
    isActive: Boolean(currentTokenSlug),
    onBack: onTokenCardClose,
  });

  useEffect(
    () => (shouldRenderTokenCard ? captureEscKeyListener(onTokenCardClose) : undefined),
    [shouldRenderTokenCard, onTokenCardClose],
  );

  const {
    primaryValue, primaryWholePart, primaryFractionPart, changePrefix, changePercent, changeValue,
  } = values || {};

  useLayoutEffect(() => {
    if (primaryValue !== undefined) {
      updateFontScale();
    }
  }, [primaryFractionPart, primaryValue, primaryWholePart, shortBaseSymbol, updateFontScale, screenWidthDep]);

  function renderLoader() {
    return (
      <div className={buildClassName(styles.isLoading)}>
        <Spinner color="white" className={styles.center} />
      </div>
    );
  }

  function renderBalance() {
    const iconCaretClassNames = buildClassName(
      'icon',
      'icon-caret-down',
      primaryFractionPart || shortBaseSymbol.length > 1 ? styles.iconCaretFraction : styles.iconCaret,
    );
    const noAnimationCounter = !isUpdating || IS_SAFARI || IS_IOS;
    return (
      <>
        <Transition
          ref={amountRef}
          activeKey={isUpdating && !isSensitiveDataHidden ? 1 : 0}
          name="fade"
          shouldCleanup
          className={styles.balanceTransition}
          slideClassName={styles.balanceSlide}
        >
          <SensitiveData
            isActive={isSensitiveDataHidden}
            maskSkin={sensitiveDataMaskSkin}
            rows={4}
            cols={14}
            cellSize={13}
            align="center"
            maskClassName={styles.blurred}
          >
            <div className={buildClassName(styles.primaryValue, 'rounded-font')}>
              <span
                className={buildClassName(
                  styles.currencySwitcher,
                  isUpdating && 'glare-text',
                  !isUpdating && withTextGradient && 'gradientText',
                )}
                role="button"
                tabIndex={0}
                onClick={!isSensitiveDataHidden ? openCurrencyMenu : undefined}
              >
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
                <i className={iconCaretClassNames} aria-hidden />
              </span>
            </div>
          </SensitiveData>
        </Transition>
        <CurrencySwitcherMenu
          isOpen={Boolean(currencyMenuAnchor)}
          triggerRef={amountRef}
          anchor={currencyMenuAnchor}
          className={styles.currencySwitcherMenu}
          onClose={closeCurrencyMenu}
        />
        {primaryValue !== '0' && (
          <SensitiveData
            isActive={isSensitiveDataHidden}
            maskSkin={sensitiveDataMaskSkin}
            rows={2}
            cols={11}
            align="center"
            cellSize={14}
            className={styles.changeSpoiler}
            maskClassName={styles.blurred}
          >
            <div className={buildClassName(styles.change, 'rounded-font')}>
              {!!changePrefix && (
                <>
                  <i
                    className={buildClassName(
                      styles.changePrefix,
                      changePrefix === 'up' ? 'icon-arrow-up' : 'icon-arrow-down',
                    )}
                    aria-hidden
                  />
                  <AnimatedCounter text={`${Math.abs(changePercent!)}%`} />
                  {' · '}
                </>
              )}
              <AnimatedCounter text={formatCurrency(Math.abs(changeValue!), shortBaseSymbol)} />
            </div>
          </SensitiveData>
        )}
      </>
    );
  }

  return (
    <div ref={ref} className={styles.containerWrapper}>
      <Transition activeKey={isUpdating ? 1 : 0} name="fade" shouldCleanup className={styles.loadingDotsContainer}>
        {isUpdating ? <LoadingDots isActive isDoubled /> : undefined}
      </Transition>

      <div className={buildClassName(styles.container, currentTokenSlug && styles.backstage, customCardClassName)}>
        <CustomCardManager nft={cardNft} onCardChange={handleCardChange} />

        <div className={buildClassName(styles.containerInner, customCardClassName)}>
          {values ? renderBalance() : renderLoader()}
          <CardAddress withTextGradient={withTextGradient} />
          {!IS_CORE_WALLET && !isNftBuyingDisabled && !isViewMode && <MintCardButton />}
        </div>
      </div>

      {shouldRenderTokenCard && (
        <TokenCard
          token={renderedToken!}
          ref={tokenCardRef}
          isUpdating={isUpdating}
          onYieldClick={isViewMode ? undefined : onYieldClick}
          onClose={onTokenCardClose}
        />
      )}
    </div>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const accountState = selectCurrentAccountState(global);
      const stakingStates = selectAccountStakingStates(global, global.currentAccountId!);
      const { cardBackgroundNft: cardNft } = selectCurrentAccountSettings(global) || {};

      return {
        isViewMode: selectIsCurrentAccountViewMode(global),
        tokens: selectCurrentAccountTokens(global),
        currentTokenSlug: accountState?.currentTokenSlug,
        baseCurrency: global.settings.baseCurrency,
        currencyRates: global.currencyRates,
        stakingStates,
        cardNft,
        isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
        isNftBuyingDisabled: global.restrictions.isNftBuyingDisabled,
      };
    },
    (global, _, stickToFirst) => stickToFirst(global.currentAccountId),
  )(Card),
);

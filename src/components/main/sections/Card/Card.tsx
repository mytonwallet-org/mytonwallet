import React, {
  type ElementRef,
  memo, useEffect, useLayoutEffect, useMemo, useRef, useState,
} from '../../../../lib/teact/teact';
import { getActions, getGlobal, withGlobal } from '../../../../global';

import type {
  ApiBaseCurrency, ApiCurrencyRates, ApiNft, ApiPriceHistoryPeriod, ApiStakingState,
} from '../../../../api/types';
import type { ApiBackendConfig } from '../../../../api/types/backend';
import type { ApiPromotion } from '../../../../api/types/backend';
import type {
  IAnchorPosition,
  PortfolioPnlChange,
  Theme,
  UserToken,
} from '../../../../global/types';
import type { LangFn } from '../../../../hooks/useLang';
import type { DropdownItem } from '../../../ui/Dropdown';

import { ANIMATION_LEVEL_MIN, IS_GRAM_WALLET } from '../../../../config';
import {
  selectAccountStakingStates, selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectCurrentAccountTokens,
  selectIs3dCardDisabled,
  selectIsCurrentAccountViewMode,
  selectPortfolioHistoryBundle,
  selectPortfolioMainnetWalletKeys,
  selectSeasonalTheme,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import { calculateFullBalance } from '../../../../util/calculateFullBalance';
import { getCardTextPalette } from '../../../../util/card/surfaceProfile';
import { formatCurrency, formatCurrencyExtended, getShortCurrencySymbol } from '../../../../util/formatNumber';
import { round } from '../../../../util/math';
import { toNativeDigits } from '../../../../util/nativeDigits';
import { DEFAULT_PORTFOLIO_TIME_RANGE } from '../../../../util/portfolio/timeRange';
import { preloadedImageUrls } from '../../../../util/preloadImage';
import { IS_IOS, IS_SAFARI } from '../../../../util/windowEnvironment';

import useAppTheme from '../../../../hooks/useAppTheme';
import useCardArtwork, { preloadCardArtworks } from '../../../../hooks/useCardArtwork';
import useCardBalanceGesture from '../../../../hooks/useCardBalanceGesture';
import useCardController from '../../../../hooks/useCardController';
import useCardCustomization from '../../../../hooks/useCardCustomization';
import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useEffectOnce from '../../../../hooks/useEffectOnce';
import useFontScale from '../../../../hooks/useFontScale';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import { useMediaQuery } from '../../../../hooks/useMediaQuery';
import useSyncEffect from '../../../../hooks/useSyncEffect';
import useUniqueId from '../../../../hooks/useUniqueId';
import useUpdateIndicator from '../../../../hooks/useUpdateIndicator';
import useWindowSize from '../../../../hooks/useWindowSize';

import MintCardButton from '../../../mintCard/MintCardButton';
import AnimatedCounter from '../../../ui/AnimatedCounter';
import CardTilt from '../../../ui/CardTilt';
import Image from '../../../ui/Image';
import LoadingDots from '../../../ui/LoadingDots';
import Spinner from '../../../ui/Spinner';
import Transition from '../../../ui/Transition';
import CardAddress from './CardAddress';
import CardPrivacy from './CardPrivacy';
import CardSurface from './CardSurface';
import CurrencySwitcherMenu from './CurrencySwitcherMenu';
import SeasonalTheming from './SeasonalTheming';

import styles from './Card.module.scss';

import promoBgMaskUrl from '../../../../assets/cards/promo_card_bg.png';
import promoOverlayMaskUrl from '../../../../assets/cards/promo_card_overlay.png';

interface OwnProps {
  ref?: ElementRef<HTMLDivElement>;
  onYieldClick: (stakingId?: string) => void;
}

interface StateProps {
  theme: Theme;
  currentAccountId: string;
  isTemporaryAccount?: boolean;
  tokens?: UserToken[];
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  stakingStates?: ApiStakingState[];
  cardNft?: ApiNft;
  isSensitiveDataHidden?: true;
  isNftBuyingDisabled: boolean;
  isViewMode: boolean;
  animationLevel: number;
  is3dCardDisabled: boolean;
  isSeasonalThemingDisabled?: boolean;
  seasonalTheme?: ApiBackendConfig['seasonalTheme'];
  activePromotion?: ApiPromotion;
  portfolioActiveRange?: ApiPriceHistoryPeriod;
  portfolioPnlChange?: PortfolioPnlChange;
  isPnlChangeUpdating?: boolean;
  isPortfolioOpen?: boolean;
}

let mainKey = 0;

function useSeasonalTheming({
  toggleSeasonalTheming,
  lang,
  showToast,
}: {
  toggleSeasonalTheming: (options: { isEnabled: boolean }) => void;
  lang: LangFn;
  showToast: (options: { message: string }) => void;
}) {
  const handleDisableSeasonalTheming = useLastCallback(() => {
    toggleSeasonalTheming({ isEnabled: false });
    showToast({
      message: lang('You can always enable seasonal theming again in the appearance settings.'),
    });
  });

  const seasonalContextMenuItems = useMemo<DropdownItem<'disable'>[]>(() => ([
    {
      value: 'disable',
      name: lang('Disable Seasonal Theming'),
      fontIcon: 'eye-closed',
    },
  ]), [lang]);

  return {
    seasonalContextMenuItems,
    handleDisableSeasonalTheming,
  };
}

const CARD_PORTRAIT_WIDTH = 378;
const CARD_PORTRAIT_HEIGHT = 220;
const CARD_LANDSCAPE_WIDTH = 328;
const CARD_LANDSCAPE_HEIGHT = 200;

function Card({
  ref,
  theme,
  currentAccountId,
  isTemporaryAccount,
  tokens,
  onYieldClick,
  baseCurrency,
  currencyRates,
  stakingStates,
  isSensitiveDataHidden,
  isNftBuyingDisabled,
  cardNft,
  isViewMode,
  animationLevel,
  is3dCardDisabled,
  isSeasonalThemingDisabled,
  seasonalTheme,
  activePromotion,
  portfolioActiveRange,
  portfolioPnlChange,
  isPnlChangeUpdating,
  isPortfolioOpen,
}: OwnProps & StateProps) {
  const {
    toggleSeasonalTheming, showToast, openPromotionModal, openMintCardModal, switchToPortfolio,
    loadPortfolioPnlChange, setIsSensitiveDataHidden,
  } = getActions();
  const lang = useLang();
  const appTheme = useAppTheme(theme);
  const amountRef = useRef<HTMLDivElement>();
  const fontScaleSignatureRef = useRef<string>();
  const balanceHitRef = useRef<HTMLSpanElement>();
  const balanceActionId = useUniqueId('balance-action-');
  const { cardRef: surfaceRef, controller, handleMotionFrame } = useCardController();
  const hasReducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)') ?? false;
  const isMotionDisabled = animationLevel === ANIMATION_LEVEL_MIN || hasReducedMotion;
  const isTiltDisabled = is3dCardDisabled || isMotionDisabled;
  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);
  const { nft: shownCardNft, imageUrl: cardImageUrl } = useCardArtwork(cardNft, IS_GRAM_WALLET);
  const { classNames: customCardClassName, withTextGradient } = useCardCustomization(shownCardNft);
  const textPalette = getCardTextPalette(shownCardNft);
  const balanceTextColor = shownCardNft?.metadata.mtwCardTextType === 'dark' ? '#000000' : '#FFFFFF';
  const balancePalette: [string, string] = withTextGradient ? textPalette : [balanceTextColor, balanceTextColor];
  const hasCustomCard = Boolean(shownCardNft);

  const { isPortrait } = useDeviceScreen();
  const { width: screenWidth } = useWindowSize();
  const isUpdating = useUpdateIndicator('balanceUpdateStartedAt');
  const { updateFontScale } = useFontScale(amountRef);
  // Screen width affects font size only in portrait orientation
  const screenWidthDep = isPortrait ? screenWidth : 0;

  useSyncEffect(() => {
    if (currentAccountId) {
      mainKey += 1;
    }
  }, [currentAccountId, isTemporaryAccount]);

  const [currencyMenuAnchor, setCurrencyMenuAnchor] = useState<IAnchorPosition>();

  const openCurrencyMenu = useLastCallback(() => {
    if (isSensitiveDataHidden || !balanceHitRef.current) return;

    const { left, width, bottom: y } = balanceHitRef.current.getBoundingClientRect();
    setCurrencyMenuAnchor({ x: left + width / 2, y });
  });

  const closeCurrencyMenu = useLastCallback(() => {
    setCurrencyMenuAnchor(undefined);
  });

  const toggleBalance = useLastCallback(() => {
    const pointer = controller.motion?.pointer;
    const card = surfaceRef.current;

    controller.origin = pointer && card
      ? [((pointer[0] + 1) * card.clientWidth) / 2, ((pointer[1] + 1) * card.clientHeight) / 2]
      : undefined;

    closeCurrencyMenu();
    setIsSensitiveDataHidden({ isHidden: !isSensitiveDataHidden });
  });

  const balanceGestureHandlers = useCardBalanceGesture({
    isHidden: Boolean(isSensitiveDataHidden),
    onToggle: toggleBalance,
    onMenu: openCurrencyMenu,
  });

  useEffect(() => {
    if (isSensitiveDataHidden) closeCurrencyMenu();
  }, [isSensitiveDataHidden]);

  // The card remounts when the wallet changes; other wallets' cards are decoded ahead of time, so the new
  // card never starts with the default artwork
  useEffectOnce(() => {
    const nfts = Object.values(getGlobal().settings.byAccountId)
      .map(({ cardBackgroundNft }) => cardBackgroundNft)
      .filter((nft): nft is ApiNft => Boolean(nft));
    preloadCardArtworks(nfts);
  });

  const { seasonalContextMenuItems, handleDisableSeasonalTheming } = useSeasonalTheming({
    toggleSeasonalTheming,
    lang,
    showToast,
  });

  const {
    shouldRenderPromo,
    promoMascotStyle,
    isPromoImagesLoaded,
    handlePromoBgLoad,
    handlePromoOverlayLoad,
    handlePromoClick,
    mascotIcon,
  } = usePromotionModal({
    activePromotion,
    promoBgMaskUrl,
    promoOverlayMaskUrl,
    openPromotionModal,
    openMintCardModal,
    isPortrait,
  });

  const values = useMemo(() => {
    return tokens ? calculateFullBalance(tokens, stakingStates, currencyRates[baseCurrency]) : undefined;
  }, [tokens, stakingStates, currencyRates, baseCurrency]);

  // Refresh the card's range change while the Portfolio screen is closed (it keeps it updated on its own
  // while open), and whenever the total balance changes, so the value tracks the live net worth
  useEffect(() => {
    if (portfolioActiveRange && !isPortfolioOpen) {
      loadPortfolioPnlChange();
    }
  }, [currentAccountId, baseCurrency, portfolioActiveRange, isPortfolioOpen, values?.primaryValue]);

  const { primaryValue, primaryWholePart, primaryFractionPart } = values || {};

  const changeValue = portfolioPnlChange ? portfolioPnlChange.amount : values?.changeValue;
  const changePercent = portfolioPnlChange
    ? (portfolioPnlChange.percent !== undefined ? round(portfolioPnlChange.percent, 2) : undefined)
    : values?.changePercent;
  const changePrefix = portfolioPnlChange
    ? (portfolioPnlChange.amount > 0 ? 'up' : portfolioPnlChange.amount < 0 ? 'down' : undefined)
    : values?.changePrefix;
  const hasChangePercent = !!changePrefix && changePercent !== undefined;
  const isChangePositive = !hasCustomCard && changePrefix === 'up';

  // Re-fit the balance font only when something width-affecting changes: the rendered text, the currency
  // symbol or the available width. Re-renders that touch none of them (e.g. a sub-cent price tick that
  // leaves the displayed value intact) are skipped.
  const fitBalanceFont = useLastCallback(() => {
    const signature = `${primaryWholePart}.${primaryFractionPart ?? ''}|${shortBaseSymbol}|${screenWidthDep}`;
    if (fontScaleSignatureRef.current === signature) return;
    fontScaleSignatureRef.current = signature;

    updateFontScale();
  });

  useLayoutEffect(() => {
    // The balance node is unmounted while the loader shows, so its inline scale is gone on remount
    if (primaryValue === undefined) {
      fontScaleSignatureRef.current = undefined;
      return;
    }

    fitBalanceFont();
  }, [primaryFractionPart, primaryValue, primaryWholePart, shortBaseSymbol, screenWidthDep, fitBalanceFont]);

  function renderLoader() {
    return (
      <div className={buildClassName(styles.isLoading)}>
        <Spinner color="white" className={styles.center} />
      </div>
    );
  }

  function renderBalance() {
    const noAnimationCounter = !isUpdating || IS_SAFARI || IS_IOS || isSensitiveDataHidden;

    return (
      <>
        <div ref={amountRef} className={buildClassName(styles.balanceTransition, styles.balanceSlide)}>
          <div className={buildClassName(styles.primaryValue, 'rounded-font')}>
            <span
              ref={balanceHitRef}
              className={styles.balanceHit}
              role="button"
              tabIndex={0}
              data-card-play-allowed={isSensitiveDataHidden || undefined}
              // The amount names the button. While it is hidden from screen readers, the label replaces it.
              aria-label={isSensitiveDataHidden ? lang('Tap to reveal') : undefined}
              aria-describedby={balanceActionId}
              {...balanceGestureHandlers}
            >
              <CardPrivacy
                isBalance
                isHidden={Boolean(isSensitiveDataHidden)}
                isDisabled={isMotionDisabled}
                palette={balancePalette}
                controller={controller}
                revision={shownCardNft?.address ?? 'default'}
              >
                <span
                  className={buildClassName(
                    styles.currencySwitcher,
                    isUpdating && 'glare-mask',
                    !isUpdating && withTextGradient && 'gradientText',
                  )}
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
                </span>
              </CardPrivacy>
            </span>
            {/* Outside the button, so the description does not become a part of the button name */}
            <span id={balanceActionId} className="visually-hidden">
              {lang(isSensitiveDataHidden ? 'Show Sensitive Data' : 'Hide Sensitive Data')}
            </span>
          </div>
        </div>
        <CurrencySwitcherMenu
          isOpen={Boolean(currencyMenuAnchor)}
          triggerRef={amountRef}
          anchor={currencyMenuAnchor}
          className={styles.currencySwitcherMenu}
          bubbleClassName={styles.currencySwitcherMenuBubble}
          onClose={closeCurrencyMenu}
        />
        {primaryValue !== '0' && (
          <CardPrivacy
            isHidden={Boolean(isSensitiveDataHidden)}
            isDisabled={isMotionDisabled}
            palette={textPalette}
            controller={controller}
            revision={`${shownCardNft?.address ?? 'default'}:${isChangePositive}`}
            className={styles.changeSpoiler}
            onClick={isSensitiveDataHidden ? toggleBalance : undefined}
          >
            <div
              className={buildClassName(
                styles.change,
                isChangePositive && styles.positive,
                'rounded-font',
              )}
              role="button"
              tabIndex={0}
              onClick={!isSensitiveDataHidden ? () => switchToPortfolio() : undefined}
            >
              <span className={buildClassName(styles.changeValue, isPnlChangeUpdating && 'glare-mask')}>
                {hasChangePercent && (
                  <>
                    <i
                      className={buildClassName(
                        styles.changePrefix,
                        changePrefix === 'up' ? 'icon-arrow-up' : 'icon-arrow-down',
                      )}
                      aria-hidden
                    />
                    <AnimatedCounter text={toNativeDigits(`${Math.abs(changePercent)}%`)} className="custom-font" />
                    {' · '}
                  </>
                )}

                <AnimatedCounter text={hasChangePercent
                  ? formatCurrency(Math.abs(changeValue!), shortBaseSymbol)
                  : formatCurrencyExtended(changeValue!, shortBaseSymbol)}
                />
                <i className={buildClassName(styles.changeChevron, 'icon-chevron-right')} aria-hidden />
              </span>
            </div>
          </CardPrivacy>
        )}
      </>
    );
  }

  return (
    <div ref={ref} className={styles.containerWrapper}>
      <Transition activeKey={isUpdating ? 1 : 0} name="fade" shouldCleanup className={styles.loadingDotsContainer}>
        {isUpdating ? <LoadingDots isActive isDoubled /> : undefined}
      </Transition>

      <CardTilt
        isDisabled={isTiltDisabled}
        className={styles.tiltArea}
        onMotionFrame={handleMotionFrame}
      >
        <div
          ref={surfaceRef}
          className={buildClassName(styles.container, customCardClassName)}
        >
          <CardSurface
            nft={shownCardNft}
            imageUrl={cardImageUrl}
            isGram={IS_GRAM_WALLET}
            isDark={appTheme === 'dark'}
            isDisabled={isTiltDisabled}
            noSwitchAnimation={isMotionDisabled}
            controller={controller}
          />
          <SeasonalTheming
            animationLevel={animationLevel}
            seasonalTheme={seasonalTheme}
            isSeasonalThemingDisabled={isSeasonalThemingDisabled}
            seasonalContextMenuItems={seasonalContextMenuItems}
            onDisableSeasonalTheming={handleDisableSeasonalTheming}
          />

          {shouldRenderPromo && (
            <div className={styles.promoLayer}>
              <Image
                url={promoBgMaskUrl}
                alt=""
                className={styles.promoBg}
                imageClassName={styles.promoBg_img}
                isSlow
                loading="eager"
                onLoad={handlePromoBgLoad}
              />
              <Image
                url={promoOverlayMaskUrl}
                alt=""
                className={styles.promoOverlay}
                imageClassName={styles.promoOverlay_img}
                isSlow
                loading="eager"
                onLoad={handlePromoOverlayLoad}
              />
              <div
                // This class name should be applied only once. When the mascot is present, it should be applied to the image instead.
                className={!(mascotIcon && isPromoImagesLoaded) ? styles.promoMascot : undefined}
                style={promoMascotStyle}
                role="button"
                tabIndex={0}
                onClick={handlePromoClick}
              >
                {mascotIcon && isPromoImagesLoaded && (
                  <Image url={mascotIcon.url} alt="" loading="eager" className={styles.promoMascot} />
                )}
              </div>
            </div>
          )}

          <div className={buildClassName(styles.containerInner, customCardClassName)}>
            {values ? renderBalance() : renderLoader()}
            <Transition
              activeKey={mainKey}
              name="fade"
              className={styles.cardAddressContainer}
              slideClassName={styles.cardAddressSlide}
            >
              <CardAddress withTextGradient={withTextGradient} />
            </Transition>
            {!isNftBuyingDisabled && !isViewMode && (
              <MintCardButton />
            )}
          </div>
        </div>
      </CardTilt>

    </div>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const currentAccountId = selectCurrentAccountId(global)!;
      const accountState = selectCurrentAccountState(global);
      const stakingStates = selectAccountStakingStates(global, currentAccountId);
      const { cardBackgroundNft: cardNft } = selectCurrentAccountSettings(global) || {};

      const { baseCurrency } = global.settings;
      // Portfolio history exists only for `mainnet` account
      const isPortfolioSupported = selectPortfolioMainnetWalletKeys(global).length > 0;
      const portfolioActiveRange = isPortfolioSupported ? global.portfolio?.activeRange : DEFAULT_PORTFOLIO_TIME_RANGE;
      const rangePnlChange = portfolioActiveRange
        ? selectPortfolioHistoryBundle(global, currentAccountId, baseCurrency, portfolioActiveRange)?.pnlChange
        : undefined;
      // The cached PnL is reused only while it matches the current range and currency
      const cachedPnlChange = global.portfolio?.pnlChangeByAccountId?.[currentAccountId];
      const isSlotMatch = cachedPnlChange?.baseCurrency === baseCurrency
        && cachedPnlChange?.range === portfolioActiveRange;
      const isPortfolioLoading = Boolean(global.portfolio?.isLoading || global.portfolio?.isRefreshing);
      const freshPnlChange = rangePnlChange ?? (isSlotMatch ? cachedPnlChange : undefined);
      // Show the up-to-date range value, or keep the previous value while a new range is still loading
      const portfolioPnlChange = freshPnlChange
        ?? (isPortfolioLoading && cachedPnlChange?.baseCurrency === baseCurrency ? cachedPnlChange : undefined);
      const isPnlChangeUpdating = isPortfolioLoading
        && (portfolioPnlChange === undefined || portfolioPnlChange !== freshPnlChange);

      return {
        theme: global.settings.theme,
        currentAccountId,
        isTemporaryAccount: selectCurrentAccount(global)?.isTemporary,
        isViewMode: selectIsCurrentAccountViewMode(global),
        tokens: selectCurrentAccountTokens(global),
        baseCurrency,
        currencyRates: global.currencyRates,
        stakingStates,
        cardNft,
        isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
        isNftBuyingDisabled: global.restrictions.isNftBuyingDisabled,
        animationLevel: global.settings.animationLevel,
        is3dCardDisabled: selectIs3dCardDisabled(global),
        isSeasonalThemingDisabled: global.settings.isSeasonalThemingDisabled,
        seasonalTheme: selectSeasonalTheme(global),
        activePromotion: accountState?.config?.activePromotion,
        portfolioActiveRange,
        portfolioPnlChange,
        isPnlChangeUpdating,
        isPortfolioOpen: global.isPortfolioOpen,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(Card),
);

function usePromotionModal({
  activePromotion,
  promoBgMaskUrl: promoBgMaskUrlParam,
  promoOverlayMaskUrl: promoOverlayMaskUrlParam,
  openPromotionModal,
  openMintCardModal,
  isPortrait,
}: {
  activePromotion?: ApiPromotion;
  promoBgMaskUrl: string;
  promoOverlayMaskUrl: string;
  openPromotionModal: NoneToVoidFunction;
  openMintCardModal: NoneToVoidFunction;
  isPortrait: boolean;
}) {
  const shouldRenderPromo = Boolean(activePromotion?.kind === 'cardOverlay');
  const mascotIcon = activePromotion?.cardOverlay?.mascotIcon;

  const cardWidth = isPortrait ? CARD_PORTRAIT_WIDTH : CARD_LANDSCAPE_WIDTH;
  const cardHeight = isPortrait ? CARD_PORTRAIT_HEIGHT : CARD_LANDSCAPE_HEIGHT;

  const promoMascotStyle = useMemo(() => (mascotIcon
    ? `--promo-mascot-top: ${mascotIcon.top}px; `
    + `--promo-mascot-right: ${mascotIcon.right}px; `
    + `--promo-mascot-height: ${mascotIcon.height / cardHeight * 100}%;`
    + `--promo-mascot-width: ${mascotIcon.width / cardWidth * 100}%;`
    + `--promo-mascot-rotation: ${mascotIcon.rotation}deg;`
    : undefined), [mascotIcon, cardWidth, cardHeight]);

  // Mascot image should appear only after the card overlay is loaded
  const [isPromoBgLoaded, setIsPromoBgLoaded] = useState(preloadedImageUrls.has(promoBgMaskUrlParam));
  const [isPromoOverlayLoaded, setIsPromoOverlayLoaded] = useState(preloadedImageUrls.has(promoOverlayMaskUrlParam));
  const isPromoImagesLoaded = isPromoBgLoaded && isPromoOverlayLoaded;
  const handlePromoBgLoad = useLastCallback(() => setIsPromoBgLoaded(true));
  const handlePromoOverlayLoad = useLastCallback(() => setIsPromoOverlayLoaded(true));

  const handlePromoClick = useLastCallback(() => {
    const { onClickAction } = activePromotion?.cardOverlay || {};
    switch (onClickAction) {
      case 'openPromotionModal':
        openPromotionModal();
        break;
      case 'openMintCardModal':
        openMintCardModal();
        break;
      default:
        break;
    }
  });

  return {
    shouldRenderPromo,
    promoMascotStyle,
    isPromoImagesLoaded,
    mascotIcon,
    handlePromoBgLoad,
    handlePromoOverlayLoad,
    handlePromoClick,
  };
}

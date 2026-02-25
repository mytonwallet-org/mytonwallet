import React, {
  type ElementRef,
  memo, useEffect, useLayoutEffect, useMemo, useRef, useState,
} from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiBaseCurrency, ApiCurrencyRates, ApiNft, ApiStakingState } from '../../../../api/types';
import type { ApiBackendConfig } from '../../../../api/types/backend';
import type { ApiPromotion } from '../../../../api/types/backend';
import type {
  IAnchorPosition,
  TokenChartMode,
  UserToken,
} from '../../../../global/types';
import type { LangFn } from '../../../../hooks/useLang';
import type { DropdownItem } from '../../../ui/Dropdown';

import { IS_CORE_WALLET } from '../../../../config';
import {
  selectAccountStakingStates, selectCurrentAccount,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectCurrentAccountTokens,
  selectIsCurrentAccountViewMode,
  selectSeasonalTheme,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import captureEscKeyListener from '../../../../util/captureEscKeyListener';
import { openDeeplinkOrUrl } from '../../../../util/deeplink';
import { formatCurrency, getShortCurrencySymbol } from '../../../../util/formatNumber';
import { preloadedImageUrls } from '../../../../util/preloadImage';
import { IS_IOS, IS_SAFARI } from '../../../../util/windowEnvironment';
import { calculateFullBalance } from './helpers/calculateFullBalance';
import getSensitiveDataMaskSkinFromCardNft from './helpers/getSensitiveDataMaskSkinFromCardNft';

import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useFontScale from '../../../../hooks/useFontScale';
import useHistoryBack from '../../../../hooks/useHistoryBack';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useShowTransition from '../../../../hooks/useShowTransition';
import useSyncEffect from '../../../../hooks/useSyncEffect';
import useUpdateIndicator from '../../../../hooks/useUpdateIndicator';
import useWindowSize from '../../../../hooks/useWindowSize';

import MintCardButton from '../../../mintCard/MintCardButton';
import AnimatedCounter from '../../../ui/AnimatedCounter';
import Image from '../../../ui/Image';
import LoadingDots from '../../../ui/LoadingDots';
import SensitiveData from '../../../ui/SensitiveData';
import Spinner from '../../../ui/Spinner';
import Transition from '../../../ui/Transition';
import CardAddress from './CardAddress';
import ChartCard from './ChartCard';
import CurrencySwitcherMenu from './CurrencySwitcherMenu';
import CustomCardManager from './CustomCardManager';
import SeasonalTheming from './SeasonalTheming';

import styles from './Card.module.scss';

import promoBgMaskUrl from '../../../../assets/cards/promo_card_bg.png';
import promoOverlayMaskUrl from '../../../../assets/cards/promo_card_overlay.png';

interface OwnProps {
  ref?: ElementRef<HTMLDivElement>;
  onChartCardClose: NoneToVoidFunction;
  tokenChartMode: TokenChartMode;
  onYieldClick: (stakingId?: string) => void;
}

interface StateProps {
  currentAccountId: string;
  isTemporaryAccount?: boolean;
  tokens?: UserToken[];
  currentTokenSlug?: string;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  stakingStates?: ApiStakingState[];
  cardNft?: ApiNft;
  isSensitiveDataHidden?: true;
  isNftBuyingDisabled: boolean;
  isViewMode: boolean;
  animationLevel: number;
  isSeasonalThemingDisabled?: boolean;
  seasonalTheme?: ApiBackendConfig['seasonalTheme'];
  activePromotion?: ApiPromotion;
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

function usePromotionModal({
  activePromotion,
  promoBgMaskUrl: promoBgMaskUrlParam,
  promoOverlayMaskUrl: promoOverlayMaskUrlParam,
  openPromotionModal,
  openMintCardModal,
}: {
  activePromotion?: ApiPromotion;
  promoBgMaskUrl: string;
  promoOverlayMaskUrl: string;
  openPromotionModal: NoneToVoidFunction;
  openMintCardModal: NoneToVoidFunction;
}) {
  const shouldRenderPromo = Boolean(activePromotion?.kind === 'cardOverlay');
  const mascotIcon = activePromotion?.cardOverlay?.mascotIcon;

  const promoMascotStyle = useMemo(() => (mascotIcon
    ? `--promo-mascot-top: ${mascotIcon.top}px; `
    + `--promo-mascot-right: ${mascotIcon.right}px; `
    + `--promo-mascot-height: ${mascotIcon.height / 200 * 100}%;`
    + `--promo-mascot-width: ${mascotIcon.width / 345 * 100}%;`
    + `--promo-mascot-rotation: ${mascotIcon.rotation}deg;`
    : undefined), [mascotIcon]);

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

function Card({
  ref,
  currentAccountId,
  isTemporaryAccount,
  tokens,
  currentTokenSlug,
  onChartCardClose,
  tokenChartMode,
  onYieldClick,
  baseCurrency,
  currencyRates,
  stakingStates,
  isSensitiveDataHidden,
  isNftBuyingDisabled,
  cardNft,
  isViewMode,
  animationLevel,
  isSeasonalThemingDisabled,
  seasonalTheme,
  activePromotion,
}: OwnProps & StateProps) {
  const { toggleSeasonalTheming, showToast, openPromotionModal, openMintCardModal } = getActions();
  const lang = useLang();
  const amountRef = useRef<HTMLDivElement>();
  const cardRef = useRef<HTMLDivElement>();
  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);
  const [customCardClassName, setCustomCardClassName] = useState<string | undefined>(undefined);
  const [withTextGradient, setWithTextGradient] = useState<boolean>(false);

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

  const {
    shouldRender: shouldRenderChartCard,
    ref: chartCardRef,
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
  });

  const values = useMemo(() => {
    return tokens ? calculateFullBalance(tokens, stakingStates, currencyRates[baseCurrency]) : undefined;
  }, [tokens, stakingStates, currencyRates, baseCurrency]);

  useHistoryBack({
    isActive: Boolean(currentTokenSlug),
    onBack: onChartCardClose,
  });

  useEffect(
    () => (shouldRenderChartCard ? captureEscKeyListener(onChartCardClose) : undefined),
    [shouldRenderChartCard, onChartCardClose],
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
      'icon-expand',
      primaryFractionPart || shortBaseSymbol.length > 1 ? styles.iconCaretFraction : styles.iconCaret,
    );
    const noAnimationCounter = !isUpdating || IS_SAFARI || IS_IOS || isSensitiveDataHidden;
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
            className={styles.sensitiveData}
            contentClassName={styles.sensitiveDataContent}
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
          bubbleClassName={styles.currencySwitcherMenuBubble}
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
            contentClassName={styles.sensitiveDataContent}
            maskClassName={styles.blurred}
          >
            <div
              className={buildClassName(styles.change, 'rounded-font')}
              role="button"
              tabIndex={0}
              onClick={() => openDeeplinkOrUrl('mtw://explore/portfolio.mytonwallet.io')}
            >
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
              <i className={buildClassName(styles.changeChevron, 'icon-chevron-right')} aria-hidden />
            </div>
          </SensitiveData>
        )}
      </>
    );
  }

  return (
    <div
      ref={(el) => {
        cardRef.current = el || undefined;
        if (ref) {
          ref.current = el;
        }
      }}
      className={styles.containerWrapper}
    >
      <Transition activeKey={isUpdating ? 1 : 0} name="fade" shouldCleanup className={styles.loadingDotsContainer}>
        {isUpdating ? <LoadingDots isActive isDoubled /> : undefined}
      </Transition>

      <div className={buildClassName(styles.container, currentTokenSlug && styles.backstage, customCardClassName)}>
        <CustomCardManager nft={cardNft} onCardChange={handleCardChange} />
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
          {!IS_CORE_WALLET && !isNftBuyingDisabled && !isViewMode && (
            <MintCardButton />
          )}
        </div>
      </div>

      {shouldRenderPromo && (
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
      )}

      {shouldRenderChartCard && (
        <ChartCard
          tokenSlug={currentTokenSlug}
          ref={chartCardRef}
          isUpdating={isUpdating}
          tokenChartMode={tokenChartMode}
          onYieldClick={isViewMode ? undefined : onYieldClick}
        />
      )}
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

      return {
        currentAccountId,
        isTemporaryAccount: selectCurrentAccount(global)?.isTemporary,
        isViewMode: selectIsCurrentAccountViewMode(global),
        tokens: selectCurrentAccountTokens(global),
        currentTokenSlug: accountState?.currentTokenSlug,
        baseCurrency: global.settings.baseCurrency,
        currencyRates: global.currencyRates,
        stakingStates,
        cardNft,
        isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
        isNftBuyingDisabled: global.restrictions.isNftBuyingDisabled,
        animationLevel: global.settings.animationLevel,
        isSeasonalThemingDisabled: global.settings.isSeasonalThemingDisabled,
        seasonalTheme: selectSeasonalTheme(global),
        activePromotion: accountState?.config?.activePromotion,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(Card),
);

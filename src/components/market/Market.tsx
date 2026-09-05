import { onFullyIdle } from '../../lib/teact/heavyAnimation';
import React, { memo, useEffect, useMemo, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type {
  ApiBaseCurrency,
  ApiCurrencyRates,
  ApiMarketAssetsResponseWithSlug,
  ApiTokenWithPrice,
} from '../../api/types';

import { selectCurrentAccountState } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { buildMarketSections } from './helpers/buildMarketSections';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TokenInfo from '../tokenInfo/TokenInfo';
import Transition from '../ui/Transition';
import Search from './Search';
import Section from './Section';
import SectionList from './SectionList';
import ShowcaseSkeleton from './ShowcaseSkeleton';

import styles from './Market.module.scss';

interface OwnProps {
  isActive?: boolean;
}

interface StateProps {
  marketData?: ApiMarketAssetsResponseWithSlug;
  tokenBySlug: Record<string, ApiTokenWithPrice>;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  areTokenNamesLocalized?: boolean;
  currentTokenSlug?: string;
  marketTokenSlug?: string;
  isMarketOpen?: boolean;
}

const enum SLIDES {
  showcase,
  section,
  token,
}

function Market({
  isActive,
  marketData,
  tokenBySlug,
  baseCurrency,
  currencyRates,
  areTokenNamesLocalized,
  currentTokenSlug,
  marketTokenSlug,
  isMarketOpen,
}: OwnProps & StateProps) {
  const {
    loadMarketAssets, openMarketToken, selectToken, closeTokenActivity, switchToWallet,
  } = getActions();

  const lang = useLang();
  const { isPortrait, isLandscape } = useDeviceScreen();
  const [openedSectionId, setOpenedSectionId] = useState<string>();
  // Only a token opened from the market belongs here, the wallet has its own token screen
  const isMarketTokenOpen = Boolean(currentTokenSlug) && currentTokenSlug === marketTokenSlug;
  // In portrait that screen is a separate app state on top of the market, so only landscape shows it inside
  const isTokenOpen = isLandscape && isMarketTokenOpen;

  // The wallet shows its own token screen for `currentTokenSlug`, so the market's token is deselected once
  // the market is closed. The reset waits for the section switch to end, so the hidden slide changes unseen
  useEffect(() => {
    if (isMarketOpen || !isMarketTokenOpen) return undefined;

    let isCancelled = false;
    onFullyIdle(() => {
      if (!isCancelled) selectToken({ slug: undefined });
    });

    return () => {
      isCancelled = true;
    };
  }, [isMarketOpen, isMarketTokenOpen]);

  useEffect(() => {
    if (!isActive) return;

    loadMarketAssets();
  }, [isActive, lang.code]);

  const buildOptions = useMemo(() => ({
    tokenBySlug,
    baseCurrency,
    currencyRates,
    areTokenNamesLocalized,
  }), [areTokenNamesLocalized, baseCurrency, currencyRates, tokenBySlug]);

  const sections = useMemo(
    () => (marketData ? buildMarketSections(lang, marketData, buildOptions) : undefined),
    [buildOptions, lang, marketData],
  );

  const openedSection = sections?.find(({ id }) => id === openedSectionId);

  const handleTokenClick = useLastCallback((slug: string) => {
    // The token screen opens on top of the market, so the wallet tab stays as it is
    openMarketToken({ slug });
  });

  const handleShowAllClick = useLastCallback((sectionId: string) => {
    setOpenedSectionId(sectionId);
  });

  const handleCloseSection = useLastCallback(() => {
    setOpenedSectionId(undefined);
  });

  const handleBack = useLastCallback(() => {
    if (isTokenOpen) {
      closeTokenActivity();
    } else if (openedSectionId) {
      handleCloseSection();
    } else {
      switchToWallet();
    }
  });

  useHistoryBack({
    isActive,
    onBack: handleBack,
  });

  function getActiveKey() {
    if (isTokenOpen) return SLIDES.token;
    if (openedSection) return SLIDES.section;

    return SLIDES.showcase;
  }

  function renderShowcase() {
    const search = <Search buildOptions={buildOptions} onTokenClick={handleTokenClick} />;

    return (
      <div className={buildClassName(styles.slideWrapper, styles.panel)}>
        <Transition name="semiFade" activeKey={sections ? 1 : 0} shouldCleanup>
          <div className={buildClassName(styles.slide, 'custom-scroll')}>
            {!isPortrait && search}
            {sections ? sections.map((section) => (
              <Section
                key={section.id}
                section={section}
                onTokenClick={handleTokenClick}
                onShowAllClick={handleShowAllClick}
              />
            )) : <ShowcaseSkeleton />}
          </div>
        </Transition>
        {isPortrait && search}
      </div>
    );
  }

  function renderContent(isSlideActive: boolean, _isFrom: boolean, currentKey: SLIDES) {
    if (currentKey === SLIDES.token) {
      return <TokenInfo isActive={isSlideActive} />;
    }

    if (currentKey === SLIDES.section && openedSection) {
      return (
        <SectionList
          section={openedSection}
          onTokenClick={handleTokenClick}
          onBackClick={handleCloseSection}
        />
      );
    }

    return renderShowcase();
  }

  return (
    <Transition
      // A hidden market switches its slides instantly, so nothing animates behind the wallet column
      name={isActive ? resolveSlideTransitionName() : 'none'}
      activeKey={getActiveKey()}
      withSwipeControl
      className={styles.root}
    >
      {renderContent}
    </Transition>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const { marketData } = global;

  return {
    // A showcase in another language counts as not loaded, so the tab requests it again when opened
    marketData: marketData?.langCode === global.settings.langCode ? marketData : undefined,
    tokenBySlug: global.tokenInfo.bySlug,
    baseCurrency: global.settings.baseCurrency,
    currencyRates: global.currencyRates,
    areTokenNamesLocalized: global.settings.areTokenNamesLocalized,
    currentTokenSlug: selectCurrentAccountState(global)?.currentTokenSlug,
    marketTokenSlug: global.marketTokenSlug,
    isMarketOpen: global.isMarketOpen,
  };
})(Market));

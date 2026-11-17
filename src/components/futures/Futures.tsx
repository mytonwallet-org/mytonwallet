import React, { memo, useEffect } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { PerpsNavigation } from '../../global/types';

import {
  selectCanReadPerps, selectCurrentAccountPerps, selectCurrentAccountPerpsPosition,
} from '../../global/selectors';
import captureEscKeyListener from '../../util/captureEscKeyListener';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import usePerpsPolling, { PERPS_REFRESH_INTERVAL } from './hooks/usePerpsPolling';
import usePerpsSnapshotPolling from './hooks/usePerpsSnapshotPolling';

import Transition from '../ui/Transition';
import Home from './Home';
import MarketCard from './MarketCard';
import PositionCard from './PositionCard';
import SectionList from './SectionList';

import styles from './Futures.module.scss';

interface OwnProps {
  isActive?: boolean;
}

interface StateProps {
  screen: PerpsNavigation['screen'];
  assetId?: string;
  sectionId?: string;
  canRead: boolean;
  hasSnapshot: boolean;
  hasPosition: boolean;
}

// Deeper screens get larger keys, so the slide transition plays forward when the user goes deeper
const enum Slide {
  Home,
  Section,
  Market,
  Position,
}

const SLIDE_BY_SCREEN: Record<PerpsNavigation['screen'], Slide> = {
  home: Slide.Home,
  section: Slide.Section,
  market: Slide.Market,
  position: Slide.Position,
};

function Futures({
  isActive, screen, assetId, sectionId, canRead, hasSnapshot, hasPosition,
}: OwnProps & StateProps) {
  const {
    closeFuturesScreen, switchToWallet, loadPerpsMarket, loadPerpsHistory, reconcilePerpsOperations,
    openFuturesPosition, openFuturesMarket,
  } = getActions();

  const lang = useLang();
  const isHomeScreen = screen === 'home';
  // The screen being left keeps its market or section while it slides out
  const renderedAssetId = useCurrentOrPrev(assetId, true);
  const renderedSectionId = useCurrentOrPrev(sectionId, true);

  // The positions refresh only while the section is on screen, and the catalogue refreshes together with them
  usePerpsSnapshotPolling(isActive && canRead);

  // Section titles and descriptions come translated from the backend. A wallet without Futures still browses markets.
  usePerpsPolling(loadPerpsMarket, isActive, undefined, [lang.code]);

  // New trades reach the history together with the positions, and unfinished operations are read back from the SDK
  // while the user can see them
  const refreshAccount = useLastCallback(() => {
    loadPerpsHistory();
    reconcilePerpsOperations();
  });

  usePerpsPolling(refreshAccount, isActive && canRead, PERPS_REFRESH_INTERVAL, [lang.code]);

  // The market and the position are two states of one screen, so a position that opens, even on another device, or
  // closes switches between them. The last complete snapshot without the position means it has closed.
  useEffect(() => {
    if (!assetId) return;

    if (screen === 'market' && hasPosition) {
      openFuturesPosition({ assetId });
    } else if (screen === 'position' && hasSnapshot && !hasPosition) {
      openFuturesMarket({ assetId });
    }
  }, [assetId, hasPosition, hasSnapshot, screen]);

  const handleBack = useLastCallback(() => {
    if (isHomeScreen) {
      switchToWallet();
    } else {
      closeFuturesScreen();
    }
  });

  useHistoryBack({ isActive, onBack: switchToWallet });
  useHistoryBack({ isActive: isActive && !isHomeScreen, onBack: closeFuturesScreen });
  // A market opened from a section is one level deeper, so Back returns to the section before the home screen
  useHistoryBack({ isActive: isActive && screen !== 'section' && sectionId !== undefined, onBack: closeFuturesScreen });

  useEffect(
    () => (isActive ? captureEscKeyListener(handleBack) : undefined),
    [isActive],
  );

  function renderSlide(isSlideActive: boolean, _: boolean, currentKey: Slide) {
    const isScreenActive = isActive && isSlideActive;

    switch (currentKey) {
      case Slide.Home:
        return <Home onBackClick={handleBack} />;
      case Slide.Section:
        return <SectionList sectionId={renderedSectionId!} isActive={isScreenActive} onBackClick={handleBack} />;
      case Slide.Market:
        return <MarketCard assetId={renderedAssetId!} isActive={isScreenActive} onBackClick={handleBack} />;
      case Slide.Position:
        return <PositionCard assetId={renderedAssetId!} isActive={isScreenActive} onBackClick={handleBack} />;
    }
  }

  return (
    <Transition
      // A hidden section switches its slides instantly, so nothing animates behind another section
      name={isActive ? resolveSlideTransitionName() : 'none'}
      activeKey={SLIDE_BY_SCREEN[screen]}
      className={styles.root}
    >
      {renderSlide}
    </Transition>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const { screen, assetId, sectionId } = global.perps.navigation;

  return {
    screen,
    assetId,
    sectionId,
    canRead: selectCanReadPerps(global),
    hasSnapshot: Boolean(selectCurrentAccountPerps(global)?.snapshot),
    hasPosition: Boolean(assetId && selectCurrentAccountPerpsPosition(global, assetId)),
  };
})(Futures));

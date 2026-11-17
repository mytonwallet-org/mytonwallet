import React, { memo, useEffect, useMemo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiPerpsMarketSection } from '../../api/types';

import { buildPerpsSections, POSITIONS_SECTION_ID } from './helpers/buildPerpsSections';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TokenRow from '../market/TokenRow';
import Spinner from '../ui/Spinner';
import LoadError from './LoadError';
import PositionList from './positions/PositionList';
import Screen from './Screen';

import styles from './Futures.module.scss';

interface OwnProps {
  sectionId: string;
  isActive?: boolean;
  onBackClick: NoneToVoidFunction;
}

interface StateProps {
  marketSections?: ApiPerpsMarketSection[];
  isMarketLoadFailed?: true;
}

function SectionList({
  sectionId, isActive, marketSections, isMarketLoadFailed, onBackClick,
}: OwnProps & StateProps) {
  const { openFuturesMarket, closeFuturesScreen, loadPerpsMarket } = getActions();

  const lang = useLang();
  const { isPortrait } = useDeviceScreen();
  const isPositionsSection = sectionId === POSITIONS_SECTION_ID;

  const section = useMemo(() => {
    if (isPositionsSection || !marketSections) return undefined;

    return buildPerpsSections(lang, marketSections, isPortrait).find(({ id }) => id === sectionId);
  }, [isPortrait, isPositionsSection, lang, marketSections, sectionId]);

  const isSectionGone = Boolean(marketSections) && !isPositionsSection && !section;

  // A catalogue refresh can drop the open section, and the screen then goes back. The check waits for the screen to
  // show, so the slide of a section the user has left does not close the screen that replaced it.
  useEffect(() => {
    if (isActive && isSectionGone) closeFuturesScreen();
  }, [isActive, isSectionGone]);

  const handleMarketClick = useLastCallback((assetId: string) => {
    openFuturesMarket({ assetId });
  });

  const handleMarketRetry = useLastCallback(() => {
    loadPerpsMarket({ force: true });
  });

  if (isPositionsSection) {
    return (
      <Screen title={lang('Open Positions')} onBackClick={onBackClick}>
        <div className={styles.card}>
          <PositionList />
        </div>
      </Screen>
    );
  }

  function renderContent() {
    if (section) {
      return (
        <div className={styles.card}>
          {section.tokens.map((token) => (
            <TokenRow key={token.slug} token={token} onClick={handleMarketClick} />
          ))}
        </div>
      );
    }

    if (marketSections) return undefined;

    return isMarketLoadFailed
      ? <LoadError className={styles.card} onRetry={handleMarketRetry} />
      : <div className={styles.loading}><Spinner /></div>;
  }

  return (
    <Screen title={section?.title ?? ''} onBackClick={onBackClick}>
      {renderContent()}
    </Screen>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    marketSections: global.perps.market?.marketSections,
    isMarketLoadFailed: global.perps.isMarketLoadFailed,
  };
})(SectionList));

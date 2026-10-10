import React, { memo } from '../../../../lib/teact/teact';
import { withGlobal } from '../../../../global';

import { ContentTab } from '../../../../global/types';

import { selectCurrentAccountId } from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';

import Agent from '../../../agent/AgentRuntime';
import Explore from '../../../explore/Explore';
import Market from '../../../market/Market';
import Portfolio from '../../../portfolio/Portfolio';
import Settings from '../../../settings/Settings';
import Transition from '../../../ui/Transition';
import LandscapeContent from '../Content/LandscapeContent';

import styles from './LandscapeLayout.module.scss';

interface OwnProps {
  onStakedTokenClick: NoneToVoidFunction;
}

interface StateProps {
  accountId?: string;
  areSettingsOpen?: boolean;
  isAgentOpen?: boolean;
  isExploreOpen?: boolean;
  isMarketOpen?: boolean;
  isPortfolioOpen?: boolean;
}

function LandscapeLayout({
  accountId, onStakedTokenClick, areSettingsOpen, isAgentOpen, isExploreOpen, isMarketOpen, isPortfolioOpen,
}: OwnProps & StateProps) {
  function renderSlide(isActive: boolean, _isFrom: boolean, currentKey: ContentTab) {
    switch (currentKey) {
      case ContentTab.Agent:
        return (
          <div className={styles.standaloneWrapper}>
            <Agent isActive={isActive} />
          </div>
        );
      case ContentTab.Explore:
        return (
          <div className={styles.standaloneWrapper}>
            <Explore key={accountId} isActive={isActive} />
          </div>
        );
      case ContentTab.Market:
        return (
          <div className={buildClassName(styles.standaloneWrapper, styles.marketWrapper)}>
            <Market key={accountId} isActive={isActive} />
          </div>
        );
      case ContentTab.Settings:
        return (
          <div className={styles.settingsWrapper}>
            <Settings key={accountId} isActive={isActive} />
          </div>
        );
      case ContentTab.Portfolio:
        return (
          <div className={buildClassName(styles.standaloneWrapper, styles.portfolioWrapper)}>
            <Portfolio key={accountId} isActive={isActive} />
          </div>
        );
      default:
        return <LandscapeContent key={accountId} onStakedTokenClick={onStakedTokenClick} />;
    }
  }

  function getActiveKey() {
    if (areSettingsOpen) return ContentTab.Settings;
    if (isAgentOpen) return ContentTab.Agent;
    if (isExploreOpen) return ContentTab.Explore;
    if (isMarketOpen) return ContentTab.Market;
    if (isPortfolioOpen) return ContentTab.Portfolio;

    return ContentTab.Overview;
  }

  const activeKey = getActiveKey();

  return (
    <Transition
      name="semiFade"
      activeKey={activeKey}
      className={styles.transition}
      slideClassName={styles.slide}
    >
      {renderSlide}
    </Transition>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const {
        areSettingsOpen, isAgentOpen, isExploreOpen, isMarketOpen, isPortfolioOpen,
      } = global;

      return {
        accountId: selectCurrentAccountId(global),
        areSettingsOpen, isAgentOpen, isExploreOpen, isMarketOpen, isPortfolioOpen,
      };
    },
  )(LandscapeLayout),
);

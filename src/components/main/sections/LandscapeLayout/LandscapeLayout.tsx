import React, { memo } from '../../../../lib/teact/teact';
import { withGlobal } from '../../../../global';

import { ContentTab } from '../../../../global/types';

import { selectCurrentAccountId } from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';

import Agent from '../../../agent/Agent';
import Explore from '../../../explore/Explore';
import Portfolio from '../../../portfolio/Portfolio';
import Settings from '../../../settings/Settings';
import Transition from '../../../ui/Transition';
import LandscapeContent from '../Content/LandscapeContent';

import styles from './LandscapeLayout.module.scss';

interface OwnProps {
  onStakedTokenClick: NoneToVoidFunction;
}

interface StateProps {
  areSettingsOpen?: boolean;
  isAgentOpen?: boolean;
  isExploreOpen?: boolean;
  isPortfolioOpen?: boolean;
}

function LandscapeLayout({
  onStakedTokenClick, areSettingsOpen, isAgentOpen, isExploreOpen, isPortfolioOpen,
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
            <Explore isActive={isActive} />
          </div>
        );
      case ContentTab.Settings:
        return (
          <div className={styles.settingsWrapper}>
            <Settings isActive={isActive} />
          </div>
        );
      case ContentTab.Portfolio:
        return (
          <div className={buildClassName(styles.standaloneWrapper, styles.portfolioWrapper)}>
            <Portfolio isActive={isActive} />
          </div>
        );
      default:
        return <LandscapeContent onStakedTokenClick={onStakedTokenClick} />;
    }
  }

  function getActiveKey() {
    if (areSettingsOpen) return ContentTab.Settings;
    if (isAgentOpen) return ContentTab.Agent;
    if (isExploreOpen) return ContentTab.Explore;
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
        areSettingsOpen, isAgentOpen, isExploreOpen, isPortfolioOpen,
      } = global;

      return {
        areSettingsOpen, isAgentOpen, isExploreOpen, isPortfolioOpen,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(LandscapeLayout),
);

import type { TeactNode } from '../../../../lib/teact/teact';
import React, { memo } from '../../../../lib/teact/teact';
import { getActions } from '../../../../global';

import { IS_PERPS_SUPPORTED } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';

import useLang from '../../../../hooks/useLang';

import AgentSearchGlyph from '../../../agent/AgentSearchGlyph';
import ListItem from '../../../ui/ListItem';

import styles from './HomeExploreSection.module.scss';

function HomeExploreSection() {
  const {
    switchToMarket, switchToFutures, switchToAgent, switchToExplore,
  } = getActions();

  const lang = useLang();

  return (
    <div className={styles.root}>
      <ListItem
        className={styles.row}
        iconContent={renderIcon(<i className="icon-market" aria-hidden />, styles.iconMarket)}
        label={lang('Market')}
        description={lang('$perps_explore_market')}
        isTextTruncated
        onClick={switchToMarket}
      />
      {IS_PERPS_SUPPORTED && (
        <ListItem
          className={styles.row}
          iconContent={renderIcon(<i className="icon-futures" aria-hidden />, styles.iconFutures)}
          label={lang('Futures')}
          description={lang('$perps_explore_futures')}
          isTextTruncated
          onClick={switchToFutures}
        />
      )}
      <ListItem
        className={styles.row}
        iconContent={renderIcon(<AgentSearchGlyph />, styles.iconAgent)}
        label={lang('Agent')}
        description={lang('PerpsExploreAgentDescription')}
        isTextTruncated
        onClick={switchToAgent}
      />
      <ListItem
        className={styles.row}
        iconContent={renderIcon(<i className="icon-explore" aria-hidden />, styles.iconApps)}
        label={lang('Apps')}
        description={lang('$perps_explore_apps')}
        isTextTruncated
        onClick={switchToExplore}
      />
    </div>
  );
}

export default memo(HomeExploreSection);

function renderIcon(icon: TeactNode, className: string) {
  return <span className={buildClassName(styles.icon, className)}>{icon}</span>;
}

import type { TeactNode } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import { IS_EXPLORER } from '../../config';
import buildClassName from '../../util/buildClassName';
import getDeterministicRandom from '../../util/getDeterministicRandom';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';

import Skeleton from '../ui/Skeleton';

import mainStyles from './Main.module.scss';
import styles from './MainSkeleton.module.scss';
import bottomBarStyles from './sections/Actions/BottomBar.module.scss';

interface OwnProps {
  isViewMode: boolean;
}

interface ActivityItemData {
  id: string;
  isOutgoing?: boolean;
  withComment?: boolean;
}

const ACTIVITY_ITEMS: ActivityItemData[][] = [
  [
    { id: 'first', isOutgoing: true, withComment: true },
    { id: 'second', isOutgoing: true },
    { id: 'third', withComment: true },
  ],
  [
    { id: 'fourth', isOutgoing: true },
    { id: 'fifth', isOutgoing: true },
    { id: 'sixth' },
    { id: 'seventh' },
    { id: 'eighth', isOutgoing: true, withComment: true },
    { id: 'ninth' },
  ],
  [
    { id: 'tenth', isOutgoing: true },
  ],
];

const NAVIGATION_LINKS_COUNT = 4;
const PORTRAIT_ACTIONS_COUNT = 4;
const PORTRAIT_TOKENS_COUNT = 2;
// Sections of `BottomBar` in portrait and `LandscapeNavBar` in landscape
const NAV_ITEMS_COUNT = 5;
const TOP_ACTIONS_COUNT = 6;
const OVERVIEW_TOKENS_COUNT = 5;
const OVERVIEW_NFTS_COUNT = 2;

function sizeVar(min: number, max: number, seed: string) {
  return `--size: ${getDeterministicRandom(min, max, seed)}`;
}

function renderHeader(withOpenLink?: boolean) {
  return (
    <div className={styles.header}>
      <Skeleton className={styles.headerAccount} />
      {withOpenLink && <Skeleton className={styles.headerOpenLink} />}
    </div>
  );
}

function renderCard() {
  return (
    <div className={styles.card}>
      <div className={styles.cardInner}>
        <Skeleton className={styles.cardBalance} />
        <Skeleton className={styles.cardBalanceSecondary} />
        <Skeleton className={styles.cardAddress} />
      </div>
    </div>
  );
}

function renderListItem(index: number, className?: string) {
  return (
    <div key={index} className={buildClassName(styles.listItem, className)}>
      <Skeleton className={styles.listItemIcon} />
      <Skeleton className={styles.listItemLabel} />
    </div>
  );
}

function renderNavBar() {
  return (
    <div className={styles.list}>
      {Array.from({ length: NAV_ITEMS_COUNT }, (_, i) => renderListItem(i))}
    </div>
  );
}

function renderAddWallet() {
  return (
    <div className={styles.list}>
      {renderListItem(0, styles.addWalletItem)}
    </div>
  );
}

function renderOpenInWallet() {
  return (
    <div className={styles.openInWallet}>
      <div className={styles.openInWalletAction}>
        <Skeleton className={styles.openInWalletActionInner} />
      </div>
      <div className={styles.navigation}>
        {Array.from({ length: NAVIGATION_LINKS_COUNT }, (_, i) => (
          <Skeleton key={i} className={styles.navigationLink} />
        ))}
      </div>
    </div>
  );
}

function renderTokenItem(index: number) {
  return (
    <div key={index} className={styles.token}>
      <Skeleton className={styles.tokenIcon} />
      <div className={styles.tokenContent}>
        <Skeleton className={styles.tokenTopLeft} style={sizeVar(2, 8, `${index}tl`)} />
        <Skeleton className={styles.tokenTopRight} style={sizeVar(2, 4, `${index}tr`)} />
        <Skeleton className={styles.tokenBottomLeft} style={sizeVar(2, 5, `${index}b`)} />
        <Skeleton className={styles.tokenBottomRight} style={sizeVar(1, 3, `${index}b`)} />
      </div>
    </div>
  );
}

function renderTokens(count: number) {
  return (
    <div className={styles.tokens}>
      {Array.from({ length: count }, (_, i) => renderTokenItem(i))}
    </div>
  );
}

function renderNfts() {
  return (
    <div className={styles.nfts}>
      {Array.from({ length: OVERVIEW_NFTS_COUNT }, (_, i) => (
        <div key={i}>
          <Skeleton className={styles.nftImage} />
          <Skeleton className={styles.nftTitle} />
        </div>
      ))}
    </div>
  );
}

function renderOverviewCell(content: TeactNode) {
  return (
    <div className={styles.overviewCell}>
      <Skeleton className={styles.overviewCaption} />
      <div className={styles.overviewCard}>
        {content}
        <div className={styles.showAll}>
          <Skeleton className={styles.showAllIcon} />
          <Skeleton className={styles.showAllLabel} />
        </div>
      </div>
    </div>
  );
}

function renderTopActions(isViewMode: boolean) {
  return (
    <div className={styles.topActions}>
      {Array.from({ length: isViewMode ? 1 : TOP_ACTIONS_COUNT }, (_, i) => (
        <div key={i} className={styles.topAction}>
          <Skeleton className={styles.topActionIcon} />
          <Skeleton className={styles.topActionLabel} />
        </div>
      ))}
    </div>
  );
}

function renderActivityItem({ id, isOutgoing, withComment }: ActivityItemData) {
  return (
    <div key={id} className={buildClassName(styles.activityRow, isOutgoing && styles.outgoing)}>
      <div className={styles.activityItem}>
        <Skeleton className={styles.activityIcon} />
        <div className={styles.activityContent}>
          <div className={styles.activityHeader}>
            <Skeleton className={styles.activityName} />
            <Skeleton className={styles.activityAmount} style={sizeVar(4, 6, `${id}amount`)} />
            <Skeleton className={styles.activityToken} />
          </div>
          <div className={styles.activitySubheader}>
            <Skeleton className={styles.activityDate} style={sizeVar(7, 10, `${id}date`)} />
            <Skeleton className={styles.activityValue} style={sizeVar(3, 5, `${id}value`)} />
          </div>
        </div>
      </div>
      {withComment && <Skeleton className={styles.activityComment} />}
    </div>
  );
}

function renderActivityList() {
  return (
    <div className={styles.activityList}>
      {ACTIVITY_ITEMS.map((group, groupIndex) => (
        <React.Fragment key={groupIndex}>
          <Skeleton className={styles.activityListDate} />
          {group.map(renderActivityItem)}
        </React.Fragment>
      ))}
    </div>
  );
}

function renderBottomBar() {
  return (
    <div className={buildClassName(bottomBarStyles.root, styles.bottomBar)} style={`--tab-count: ${NAV_ITEMS_COUNT}`}>
      <div className={bottomBarStyles.capsule}>
        {Array.from({ length: NAV_ITEMS_COUNT }, (_, index) => (
          <div key={index} className={bottomBarStyles.button}>
            <Skeleton className={styles.bottomBarIcon} />
            <Skeleton className={styles.bottomBarLabel} />
          </div>
        ))}
      </div>
    </div>
  );
}

function MainSkeleton({ isViewMode }: OwnProps) {
  const { isPortrait } = useDeviceScreen();

  function renderActions() {
    return (
      <div className={styles.actions}>
        {Array.from({ length: PORTRAIT_ACTIONS_COUNT }, (_, index) => (
          <div key={index} className={styles.actionButton}>
            <Skeleton className={styles.actionIcon} />
            <Skeleton className={styles.actionLabel} />
          </div>
        ))}
      </div>
    );
  }

  function renderTabs() {
    return (
      <div className={styles.tabs}>
        <Skeleton className={styles.tab} />
        <Skeleton className={styles.tab} />
        {!isViewMode && <Skeleton className={styles.tab} />}
      </div>
    );
  }

  if (isPortrait) {
    return (
      <div className={styles.portraitContainer}>
        <div className={styles.head}>
          {renderHeader(IS_EXPLORER)}
          {renderCard()}
          {!isViewMode && renderActions()}
        </div>
        <div className={styles.assets}>
          {renderTokens(PORTRAIT_TOKENS_COUNT)}
        </div>
        <div className={styles.content}>
          <div className={styles.contentInner}>
            {renderTabs()}
            {renderActivityList()}
          </div>
        </div>
        {renderBottomBar()}
      </div>
    );
  }

  return (
    <div className={mainStyles.landscapeContainer}>
      <div className={buildClassName(mainStyles.sidebar, 'custom-scroll')}>
        {renderHeader()}
        {renderCard()}
        {renderNavBar()}
        {renderAddWallet()}
        {IS_EXPLORER && renderOpenInWallet()}
      </div>
      <div className={mainStyles.main}>
        <div className={buildClassName(styles.overview, 'custom-scroll')}>
          {renderTopActions(isViewMode)}
          <div className={styles.overviewRow}>
            {renderOverviewCell(renderTokens(OVERVIEW_TOKENS_COUNT))}
            {renderOverviewCell(renderNfts())}
          </div>
          <div className={styles.activities}>
            {renderActivityList()}
          </div>
        </div>
      </div>
    </div>
  );
}

export default memo(MainSkeleton);

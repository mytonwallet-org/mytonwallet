import React, { memo } from '../../lib/teact/teact';

import { IS_EXPLORER } from '../../config';
import buildClassName from '../../util/buildClassName';
import getPseudoRandomNumber from '../../util/getPseudoRandomNumber';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';

import Skeleton from '../ui/Skeleton';

import mainStyles from './Main.module.scss';
import styles from './MainSkeleton.module.scss';

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
const BOTTOM_BAR_BUTTONS_COUNT = 3;

function sizeVar(min: number, max: number, seed: string) {
  return `--size: ${getPseudoRandomNumber(min, max, seed)}`;
}

function renderHeader() {
  return (
    <div className={styles.header}>
      <Skeleton className={styles.headerAccount} />
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

function renderOpenInWallet() {
  return (
    <div className={styles.openInWallet}>
      <Skeleton className={styles.openInWalletAction} />
      <Skeleton className={styles.openInWalletActionInner} />
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

function renderTokens() {
  return (
    <div className={styles.tokens}>
      {renderTokenItem(0)}
      {renderTokenItem(1)}
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
    <div className={styles.bottomBar}>
      {Array.from({ length: BOTTOM_BAR_BUTTONS_COUNT }, (_, index) => (
        <div key={index} className={styles.bottomBarButton}>
          <Skeleton className={styles.bottomBarIcon} />
          <Skeleton className={styles.bottomBarLabel} />
        </div>
      ))}
    </div>
  );
}

function MainSkeleton({ isViewMode }: OwnProps) {
  const { isPortrait } = useDeviceScreen();

  function renderActions() {
    return (
      <div className={buildClassName(styles.actions, isPortrait && styles.actionsPortrait)}>
        {Array.from({ length: isPortrait ? 4 : 3 }, (_, index) => (
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
      <div className={buildClassName(styles.tabs, isPortrait && styles.tabsPortrait)}>
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
          {renderHeader()}
          {renderCard()}
          {!isViewMode && renderActions()}
        </div>
        <div className={styles.assets}>
          {renderTokens()}
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
    <div className={buildClassName(styles.landscapeContainer, mainStyles.landscapeContainer)}>
      <div className={buildClassName(styles.sidebar, mainStyles.sidebar, 'custom-scroll')}>
        {renderHeader()}
        {renderCard()}
        {IS_EXPLORER && renderOpenInWallet()}
      </div>
      <div className={styles.main}>
        <div className={styles.assets}>
          {renderTokens()}
        </div>
        <div className={styles.content}>
          {renderTabs()}
          {renderActivityList()}
        </div>
      </div>
    </div>
  );
}

export default memo(MainSkeleton);

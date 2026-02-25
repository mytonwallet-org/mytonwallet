import type { TeactNode } from '../../../../lib/teact/teact';
import React, {
  memo, useEffect, useLayoutEffect, useMemo, useRef,
} from '../../../../lib/teact/teact';
import { setExtraStyles } from '../../../../lib/teact/teact-dom';
import { getActions, withGlobal } from '../../../../global';

import type {
  ApiActivity,
  ApiBaseCurrency,
  ApiChain,
  ApiCurrencyRates,
  ApiNft,
  ApiStakingState,
  ApiSwapAsset,
  ApiTokenWithPrice,
} from '../../../../api/types';
import type { Account, SavedAddress, Theme } from '../../../../global/types';
import { ContentTab } from '../../../../global/types';

import {
  ANIMATED_STICKER_BIG_SIZE_PX,
  LANDSCAPE_MIN_ASSETS_TAB_VIEW,
  PORTRAIT_MIN_ASSETS_TAB_VIEW,
} from '../../../../config';
import { forceMeasure } from '../../../../lib/fasterdom/stricterdom';
import { getIsTinyOrScamTransaction } from '../../../../global/helpers';
import {
  selectAccount,
  selectAccounts,
  selectAccountStakingStatesBySlug,
  selectActivityHistoryIds,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectIsHistoryEndReached,
} from '../../../../global/selectors';
import { getActivityIdReplacements } from '../../../../util/activities';
import buildClassName from '../../../../util/buildClassName';
import { formatHumanDay, getDayStartAt } from '../../../../util/dateFormat';
import generateUniqueId from '../../../../util/generateUniqueId';
import { isKeyCountGreater } from '../../../../util/isEmptyObject';
import { compact, swapKeysAndValues } from '../../../../util/iteratees';
import { getIsTransactionWithPoisoning } from '../../../../util/poisoningHash';
import { REM } from '../../../../util/windowEnvironment';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';
import {
  getScrollableContainer,
  getScrollContainerClosestSelector,
} from '../../helpers/scrollableContainer';

import useAppTheme from '../../../../hooks/useAppTheme';
import { getIsPortrait, useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useInfiniteScroll from '../../../../hooks/useInfiniteScroll';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useLayoutEffectWithPrevDeps from '../../../../hooks/useLayoutEffectWithPrevDeps';
import usePrevious from '../../../../hooks/usePrevious';
import useSyncEffectWithPrevDeps from '../../../../hooks/useSyncEffectWithPrevDeps';
import useUpdateIndicator from '../../../../hooks/useUpdateIndicator';

import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';
import InfiniteScroll from '../../../ui/InfiniteScroll';
import LoadingDots from '../../../ui/LoadingDots';
import Spinner from '../../../ui/Spinner';
import Transition from '../../../ui/Transition';
import Activity, { getActivityHeight } from './Activity';
import ActivityListItem from './ActivityListItem';
import NewWalletGreeting from './NewWalletGreeting';

import styles from './Activities.module.scss';

interface OwnProps {
  isActive?: boolean;
  totalTokensAmount: number;
  onScroll?: (e: React.UIEvent<HTMLDivElement>) => void;
}

type StateProps = {
  currentAccountId: string;
  slug?: string;
  accountChains?: Partial<Record<ApiChain, unknown>>;
  areTinyTransfersHidden?: boolean;
  byId?: Record<string, ApiActivity>;
  allActivityIds?: string[];
  tokensBySlug: Record<string, ApiTokenWithPrice>;
  swapTokensBySlug?: Record<string, ApiSwapAsset>;
  currentActivityId?: string;
  savedAddresses?: SavedAddress[];
  isHistoryEndReached: boolean;
  alwaysShownSlugs?: string[];
  theme: Theme;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  isSensitiveDataHidden?: true;
  stakingStateBySlug: Record<string, ApiStakingState>;
  nftsByAddress?: Record<string, ApiNft>;
  accounts?: Record<string, Account>;
};

interface ItemPosition {
  /** In rem */
  top: number;
  /** In rem */
  height: number;
}

const FURTHER_SLICE = 30;

const LIST_TOP_PADDING = 0.5; // rem
const DATE_HEADER_HEIGHT = 2.125; // rem

// After this threshold, the animations of adding new activities (controlled by `useActivityOrderDiff`) won't be visible
// to the user, so the animation is disabled to improve the performance. An important part that makes the additions
// invisible is the `usePreventScrolledListShift` hook.
const SCROLL_THRESHOLD = (LIST_TOP_PADDING + DATE_HEADER_HEIGHT) * REM;

const DATE_ID_PREFIX = 'date:';

const EMPTY_ARRAY = Object.freeze([]);
const EMPTY_DICTIONARY = Object.freeze({});

function Activities({
  isActive,
  currentAccountId,
  accountChains = EMPTY_DICTIONARY,
  slug,
  byId,
  allActivityIds,
  tokensBySlug,
  swapTokensBySlug,
  areTinyTransfersHidden,
  currentActivityId,
  savedAddresses,
  isHistoryEndReached,
  alwaysShownSlugs,
  theme,
  baseCurrency,
  currencyRates,
  isSensitiveDataHidden,
  stakingStateBySlug,
  nftsByAddress,
  accounts,
  onScroll,
}: Omit<OwnProps, 'totalTokensAmount'> & StateProps) {
  const { fetchPastActivities, showActivityInfo } = getActions();

  const lang = useLang();
  const { isLandscape, isPortrait } = useDeviceScreen();

  const containerRef = useRef<HTMLDivElement>();
  const isUpdating = useUpdateIndicator('activitiesUpdateStartedAt');

  const appTheme = useAppTheme(theme);
  const hasUserScrolledRef = useRef(false);

  // As with `allActivityIds`, `undefined` means "not loaded yet" and `[]` means "no activities"
  const listItemIds = useMemo(() => {
    const activityIds = filterActivityIds(
      allActivityIds ?? EMPTY_ARRAY,
      byId ?? EMPTY_DICTIONARY,
      slug,
      tokensBySlug,
      areTinyTransfersHidden,
      alwaysShownSlugs,
    );

    if (!activityIds.length && !isHistoryEndReached) {
      // When all the activities are hidden, the further activities are being loaded, so the spinner should be shown.
      return undefined;
    }

    return addDatesToActivityIds(activityIds, byId);
  }, [areTinyTransfersHidden, byId, alwaysShownSlugs, allActivityIds, slug, tokensBySlug, isHistoryEndReached]);

  const firstListItemId = listItemIds?.[0];

  const loadMore = useLastCallback(() => {
    fetchPastActivities({ slug, shouldLoadWithBudget: true });
  });

  const [viewportIds, getMore, resetScroll] = useInfiniteScroll({
    loadMoreBackwards: loadMore,
    listIds: listItemIds,
    listSlice: FURTHER_SLICE,
    slug,
    isActive,
  });

  const getListItemKey = useListItemKeys(viewportIds ?? EMPTY_ARRAY, byId ?? EMPTY_DICTIONARY);

  // The move animation should remain only for the case when new transactions appear in the feed.
  // At the same time, the smooth feed appearance animation should be kept when the loading is completed.
  const prevSlug = usePrevious(slug);
  const prevIsLoading = usePrevious(listItemIds === undefined);
  const shouldUseAnimations = Boolean(isActive && !hasUserScrolledRef.current && (prevIsLoading || prevSlug === slug));

  const itemPositionById = useMemo(() => {
    const itemPositionById: Record<string, ItemPosition> = {};
    let top = 0;

    listItemIds?.forEach((itemId, index) => {
      const height = itemId.startsWith(DATE_ID_PREFIX)
        ? DATE_HEADER_HEIGHT + (index === 0 ? LIST_TOP_PADDING : 0)
        : getActivityHeight(byId![itemId]);

      itemPositionById[itemId] = { top, height };
      top += height;
    });

    return itemPositionById;
  }, [byId, listItemIds]);

  const currentContainerHeight = useMemo(
    () => {
      if (!viewportIds?.length) return 0;

      const lastViewportId = viewportIds[viewportIds.length - 1];
      const activityOffset = itemPositionById[lastViewportId];

      return activityOffset ? activityOffset.top + activityOffset.height : 0;
    },
    [itemPositionById, viewportIds],
  );

  usePreventScrolledListShift(
    viewportIds ?? EMPTY_ARRAY,
    itemPositionById,
    isPortrait,
    containerRef,
    hasUserScrolledRef,
  );

  useLayoutEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    setExtraStyles(container, { height: isLandscape ? '' : `${currentContainerHeight}rem` });
  }, [isLandscape, currentContainerHeight]);

  // Requests the history when the UI shows a spinner instead of the list.
  // Keeps requesting the history when all the currently loaded activities are hidden.
  useEffect(() => {
    if (!listItemIds?.length) {
      loadMore();
    }
  }, [slug, allActivityIds, listItemIds, loadMore]);

  // Reset scroll and scroll tracking when the tab becomes inactive
  useEffect(() => {
    if (!isActive && !isLandscape) {
      resetScroll?.();
      hasUserScrolledRef.current = false;
    }
  }, [isActive, isLandscape, resetScroll]);

  const handleScroll = useLastCallback((e: React.UIEvent<HTMLDivElement>) => {
    const scrollTop = (e.target as HTMLDivElement).scrollTop;

    hasUserScrolledRef.current = scrollTop >= SCROLL_THRESHOLD;

    onScroll?.(e);
  });

  const handleActivityClick = useLastCallback((id: string) => {
    showActivityInfo({ id });
  });

  if (!currentAccountId) {
    return undefined;
  }

  function renderDate(dateValue: number, isFirst?: boolean) {
    const formattedDate = formatHumanDay(lang, dateValue);
    const date = <div className={styles.date}>{formattedDate}</div>;

    if (!isFirst) {
      return date;
    }

    const dateWithLoader = (
      <div className={buildClassName(styles.date, styles.date_withLoadingDots)}>
        {formattedDate}
        <LoadingDots isActive isDoubled className={styles.loadingDots} />
      </div>
    );

    return (
      <Transition
        name="semiFade"
        activeKey={isUpdating ? 1 : 0}
        className={styles.dateContainer}
        slideClassName={styles.dateSlide}
      >
        {isUpdating ? dateWithLoader : date}
      </Transition>
    );
  }

  function renderHistory() {
    if (!viewportIds) return undefined;

    const isMultichainAccount = isKeyCountGreater(accountChains, 1);

    return viewportIds.map((itemId, index) => {
      const topOffset = itemPositionById[itemId]?.top ?? 0;
      let itemContent: TeactNode;

      if (itemId.startsWith(DATE_ID_PREFIX)) {
        itemContent = renderDate(
          Number(itemId.slice(DATE_ID_PREFIX.length)),
          itemId === firstListItemId,
        );
      } else {
        const activity = byId?.[itemId];
        if (!activity) return undefined;

        const isActivityActive = activity.id === currentActivityId;
        const isLastInDay = index === viewportIds.length - 1 || viewportIds[index + 1].startsWith(DATE_ID_PREFIX);

        itemContent = (
          <Activity
            activity={activity}
            isLast={isLastInDay}
            isActive={isActivityActive}
            tokensBySlug={tokensBySlug}
            swapTokensBySlug={swapTokensBySlug}
            appTheme={appTheme}
            isSensitiveDataHidden={isSensitiveDataHidden}
            nftsByAddress={nftsByAddress}
            currentAccountId={currentAccountId}
            stakingStateBySlug={stakingStateBySlug}
            savedAddresses={savedAddresses}
            withChainIcon={isMultichainAccount}
            accounts={accounts}
            baseCurrency={baseCurrency}
            currencyRates={currencyRates}
            onClick={handleActivityClick}
          />
        );
      }

      return (
        <ActivityListItem key={getListItemKey(itemId)} topOffset={topOffset} withAnimation={shouldUseAnimations}>
          {itemContent}
        </ActivityListItem>
      );
    });
  }

  if (listItemIds === undefined) {
    return (
      <div className={buildClassName(styles.emptyList, styles.emptyListLoading)}>
        <Spinner />
      </div>
    );
  }

  if (!listItemIds.length) {
    if (!slug) {
      return (
        <div className={buildClassName(isLandscape && styles.greeting)}>
          <NewWalletGreeting
            isActive={isActive}
            accountChains={accountChains}
            mode={isLandscape ? 'emptyList' : 'panel'}
          />
        </div>
      );
    } else {
      return (
        <div className={styles.emptyList}>
          <AnimatedIconWithPreview
            play={isActive}
            tgsUrl={ANIMATED_STICKERS_PATHS.noData}
            previewUrl={ANIMATED_STICKERS_PATHS.noDataPreview}
            size={ANIMATED_STICKER_BIG_SIZE_PX}
            className={styles.sticker}
            noLoop={false}
            nonInteractive
          />
          <p className={styles.emptyListTitle}>{lang('No Activity')}</p>
        </div>
      );
    }
  }

  return (
    <InfiniteScroll
      ref={containerRef}
      className={buildClassName('custom-scroll', styles.listGroup)}
      scrollContainerClosest={getScrollContainerClosestSelector(isActive, isPortrait)}
      items={viewportIds}
      preloadBackwards={FURTHER_SLICE}
      withAbsolutePositioning
      maxHeight={`${currentContainerHeight}rem`}
      onLoadMore={getMore}
      onScroll={handleScroll}
    >
      {renderHistory()}
    </InfiniteScroll>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const currentAccountId = selectCurrentAccountId(global)!;
      const accountState = selectCurrentAccountState(global);
      const accountSettings = selectCurrentAccountSettings(global);
      const slug = accountState?.currentTokenSlug;
      const stakingStateBySlug = selectAccountStakingStatesBySlug(global, currentAccountId);
      const { activities } = accountState || {};
      const { byId } = activities || {};
      const { byAddress } = accountState?.nfts || {};
      const accounts = selectAccounts(global);
      const isHistoryEndReached = selectIsHistoryEndReached(global, currentAccountId, slug);
      const allActivityIds = selectActivityHistoryIds(global, currentAccountId, slug);

      return {
        accountChains: selectAccount(global, currentAccountId)?.byChain,
        currentAccountId,
        slug,
        byId,
        allActivityIds,
        tokensBySlug: global.tokenInfo.bySlug,
        swapTokensBySlug: global.swapTokenInfo?.bySlug,
        areTinyTransfersHidden: global.settings.areTinyTransfersHidden,
        savedAddresses: accountState?.savedAddresses,
        isHistoryEndReached,
        currentActivityId: accountState?.currentActivityId,
        alwaysShownSlugs: accountSettings?.alwaysShownSlugs,
        theme: global.settings.theme,
        baseCurrency: global.settings.baseCurrency,
        currencyRates: global.currencyRates,
        stakingStateBySlug,
        isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
        nftsByAddress: byAddress,
        accounts,
      };
    },
    (global, { totalTokensAmount }, stickToFirst) => {
      const accountState = selectCurrentAccountState(global);
      const shouldShowSeparateAssetsPanel = totalTokensAmount <= (
        getIsPortrait() ? PORTRAIT_MIN_ASSETS_TAB_VIEW : LANDSCAPE_MIN_ASSETS_TAB_VIEW
      );

      return stickToFirst((
        accountState?.activeContentTab === ContentTab.Activity
        || (accountState?.activeContentTab === ContentTab.Assets && shouldShowSeparateAssetsPanel)
      ) && selectCurrentAccountId(global));
    },
  )(Activities),
);

function filterActivityIds(
  allActivityIds: readonly string[],
  byId: Record<string, ApiActivity>,
  slug: string | undefined,
  tokensBySlug: Record<string, ApiTokenWithPrice>,
  areTinyTransfersHidden?: boolean,
  alwaysShownSlugs?: string[],
) {
  return allActivityIds.filter((id) => {
    const activity = byId?.[id];
    if (!activity) return false;

    if (activity?.shouldHide) return false;

    if (activity?.kind === 'swap') {
      return !slug || activity.from === slug || activity.to === slug;
    } else {
      return activity?.slug
        && (!slug || activity.slug === slug)
        && (
          !areTinyTransfersHidden
          || (slug && tokensBySlug[activity.slug]?.priceUsd === 0)
          || !getIsTinyOrScamTransaction(activity, tokensBySlug[activity.slug])
          || alwaysShownSlugs?.includes(activity.slug)
        )
        && !getIsTransactionWithPoisoning(activity);
    }
  });
}

function addDatesToActivityIds(activityIds: readonly string[], byId: Record<string, ApiActivity> = {}) {
  let lastActivityDayStart = Infinity;
  const listItemIds: string[] = [];

  // Mix-in the date headers to the list of activity ids
  for (const activityId of activityIds) {
    const activityDayStart = getDayStartAt(byId[activityId].timestamp);

    // The clause is not `activityDayStart !== lastActivityDayStart`, because the days can go backwards, which will
    // cause duplicated date Teact keys. The days can go backwards because the pending activities are on the top
    // regardless of their timestamp.
    const isNewDay = activityDayStart < lastActivityDayStart;

    if (isNewDay) {
      lastActivityDayStart = activityDayStart;
      listItemIds.push(`${DATE_ID_PREFIX}${activityDayStart}`);
    }
    listItemIds.push(activityId);
  }

  return listItemIds;
}

/**
 * Pending activity ids may change. If the ids are used as the list keys, excessive blinking animations occur.
 * This hook creates stable keys for the list items, which prevents the excessive animations.
 */
function useListItemKeys(viewportIds: readonly string[], activityById: Record<string, ApiActivity>) {
  const keyByIdRef = useRef<Record<string, string>>();
  keyByIdRef.current ??= {};

  useSyncEffectWithPrevDeps(([oldViewportIds = [], oldActivityById = {}]) => {
    const keyById = keyByIdRef.current!;
    const oldActivities = compact(oldViewportIds.map((id) => oldActivityById[id]));
    const newActivities = compact(viewportIds.map((id) => activityById[id]));

    // Transfer the keys from the old activities to the new activities. Besides the obvious goal, `swapKeysAndValues`
    // ensures that the `idReplacements` values are unique, which results into unique output keys.
    const idReplacements = swapKeysAndValues(getActivityIdReplacements(oldActivities, newActivities));
    for (const { id: newActivityId } of newActivities) {
      const oldActivityId = idReplacements[newActivityId];
      keyById[newActivityId] = (oldActivityId && keyById[oldActivityId]) ?? generateUniqueId();
    }

    // Clean the memory
    const newActivityIds = new Set(viewportIds);
    for (const itemId of Object.keys(keyById)) {
      if (!newActivityIds.has(itemId)) {
        delete keyById[itemId];
      }
    }
  }, [viewportIds, activityById]);

  return useLastCallback((itemId: string) => keyByIdRef.current?.[itemId] ?? itemId);
}

/**
 * In order to make the list look stationary after it has been scrolled, this hook compensates the scroll position when
 * new items are added and user scrolled content.
 */
function usePreventScrolledListShift(
  viewportIds: readonly string[],
  itemPositionById: Record<string, ItemPosition>,
  isPortrait: boolean,
  containerRef: React.RefObject<HTMLDivElement | undefined>,
  hasUserScrolledRef: React.RefObject<boolean>,
) {
  useLayoutEffectWithPrevDeps(([prevItemPositionById]) => {
    const container = getScrollableContainer(containerRef.current, isPortrait);
    if (!hasUserScrolledRef.current || !container || !prevItemPositionById || !viewportIds.length) return;

    const anchorId = viewportIds[Math.floor(viewportIds.length / 2)];
    const prevTop = prevItemPositionById[anchorId]?.top;
    const nextTop = itemPositionById[anchorId]?.top;

    if (prevTop === undefined || nextTop === undefined || prevTop === nextTop) return;

    forceMeasure(() => {
      container.scrollBy({
        top: (nextTop - prevTop) * REM,
        behavior: 'instant',
      });
    });
  }, [itemPositionById, viewportIds, containerRef, hasUserScrolledRef, isPortrait]);
}

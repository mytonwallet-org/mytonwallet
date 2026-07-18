import React, { memo, useMemo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type {
  ApiBaseCurrency, ApiCurrencyRates, ApiStakingState, ApiTokenWithPrice, ApiVestingInfo,
} from '../../../../api/types';
import type { LoadMoreDirection, Theme, UserSwapToken, UserToken } from '../../../../global/types';
import { SettingsState } from '../../../../global/types';

import { ANIMATED_STICKER_SMALL_SIZE_PX, IS_FEATURE_LIMITED, IS_MY_WALLET_BRAND } from '../../../../config';
import {
  selectAccountStakingStates,
  selectCurrentAccountId,
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectCurrentAccountTokens,
  selectIsCurrentAccountViewMode,
  selectIsMultichainAccount,
  selectIsStakingDisabled,
  selectIsSwapDisabled,
  selectMycoin,
  selectSwapTokens,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import buildStyle from '../../../../util/buildStyle';
import { toDecimal } from '../../../../util/decimals';
import { buildCollectionByKey } from '../../../../util/iteratees';
import { MEMO_EMPTY_ARRAY } from '../../../../util/memo';
import { getIsActiveStakingState, getStakingStateStatus } from '../../../../util/staking';
import { REM } from '../../../../util/windowEnvironment';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';
import { getScrollContainerClosestSelector } from '../../helpers/scrollableContainer';

import useAppTheme from '../../../../hooks/useAppTheme';
import useCurrentOrPrev from '../../../../hooks/useCurrentOrPrev';
import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useInfiniteScroll from '../../../../hooks/useInfiniteScroll';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import usePrevious2 from '../../../../hooks/usePrevious2';
import useTokensWithStaking from '../../../../hooks/useTokensWithStaking';
import useVesting from '../../../../hooks/useVesting';

import InfiniteScroll from '../../../ui/InfiniteScroll';
import Spinner from '../../../ui/Spinner';
import EmptyListPlaceholder from './EmptyListPlaceholder';
import { OVERVIEW_CELL_BODY_CLASS } from './OverviewCell';
import Token from './Token';
import TokenListItem from './TokenListItem';

import styles from './Assets.module.scss';

type OwnProps = {
  isActive?: boolean;
  isSeparatePanel?: boolean;
  isWidget?: boolean;
  onTokenClick: (slug: string) => void;
  onStakedTokenClick: (stakingId?: string) => void;
  onScroll?: (e: React.UIEvent<HTMLDivElement>) => void;
};

interface StateProps {
  tokens?: UserToken[];
  swapTokens?: UserSwapToken[];
  vesting?: ApiVestingInfo[];
  isInvestorViewEnabled?: boolean;
  currentTokenSlug?: string;
  baseCurrency: ApiBaseCurrency;
  theme: Theme;
  mycoin?: ApiTokenWithPrice;
  isSensitiveDataHidden?: true;
  states?: ApiStakingState[];
  isViewMode?: boolean;
  isSwapDisabled?: boolean;
  isMultichainAccount: boolean;
  isStakingDisabled?: boolean;
  pinnedSlugs?: string[];
  alwaysHiddenSlugs?: string[];
  currencyRates?: ApiCurrencyRates;
}

const TOKEN_HEIGHT_REM = 4;

function Assets({
  isActive,
  tokens,
  swapTokens,
  vesting,
  isInvestorViewEnabled,
  isSeparatePanel,
  isWidget,
  currentTokenSlug,
  baseCurrency,
  mycoin,
  isSensitiveDataHidden,
  theme,
  states,
  isMultichainAccount,
  isViewMode,
  isSwapDisabled,
  isStakingDisabled,
  pinnedSlugs = MEMO_EMPTY_ARRAY,
  alwaysHiddenSlugs = MEMO_EMPTY_ARRAY,
  currencyRates,
  onTokenClick,
  onStakedTokenClick,
  onScroll,
}: OwnProps & StateProps) {
  const lang = useLang();
  const { openSettingsWithState } = getActions();

  const renderedTokens = useCurrentOrPrev(tokens, true);
  const renderedMycoin = useCurrentOrPrev(mycoin, true);

  const userMycoin = useMemo(() => {
    if (!renderedTokens || !renderedMycoin) return undefined;

    return renderedTokens.find(({ slug }) => slug === renderedMycoin.slug);
  }, [renderedMycoin, renderedTokens]);

  const { isLandscape, isPortrait } = useDeviceScreen();
  const appTheme = useAppTheme(theme);

  const activeStates = useMemo(() => {
    if (IS_FEATURE_LIMITED) return [];

    return states?.filter(getIsActiveStakingState) ?? [];
  }, [states]);

  // Set of BASE token slugs that have active staking.
  // Used to prevent showing staking info (APY, etc.) on base tokens when a separate staking token exists.
  const stakedTokenSlugs = useMemo(() => {
    return new Set(activeStates.map((state) => state.tokenSlug));
  }, [activeStates]);

  const allTokensWithStaked = useTokensWithStaking({
    tokens: renderedTokens,
    states,
    baseCurrency,
    currencyRates,
    pinnedSlugs,
    alwaysHiddenSlugs,
  });

  const swapTokensBySlug = useMemo(() => {
    return buildCollectionByKey<UserSwapToken>(swapTokens ?? [], 'slug');
  }, [swapTokens]);

  // Vesting is a MYCOIN perk, i.e. a My Wallet product that the Gram brand does not carry
  const {
    ref: vestingTokenRef,
    shouldRender: shouldRenderVestingToken,
    amount: vestingAmount,
    vestingStatus,
    unfreezeEndDate,
    onVestingTokenClick,
  } = useVesting({ vesting, userMycoin, isDisabled: !IS_MY_WALLET_BRAND });

  const tokenSlugs = useMemo(() => (
    allTokensWithStaked
      ?.filter(({ isDisabled }) => !isDisabled)
      .map(({ slug }) => slug)
  ), [allTokensWithStaked]);
  const [viewportSlugs, getMore] = useInfiniteScroll({
    listIds: tokenSlugs,
    isActive,
    withResetOnInactive: isPortrait,
  });

  const viewportIndex = useMemo(() => {
    if (!viewportSlugs) return -1;
    const baseIndex = tokenSlugs!.indexOf(viewportSlugs[0]);
    return shouldRenderVestingToken ? baseIndex + 1 : baseIndex;
  }, [shouldRenderVestingToken, tokenSlugs, viewportSlugs]);

  // Smart jump for widget mode: when `InfiniteScroll` asks to load more after a fast scroll
  // that left the viewport far outside the rendered window, recenter the slice around the
  // current scroll position in a single hop instead of shifting by `listSlice` per cycle
  const widgetContainerRef = useRef<HTMLDivElement>();
  const handleWidgetGetMore = useLastCallback((args: { direction: LoadMoreDirection }) => {
    if (!getMore || !tokenSlugs?.length) return;

    const scrollContainer = widgetContainerRef.current
      ?.closest<HTMLDivElement>(`.${OVERVIEW_CELL_BODY_CLASS}`);
    if (!scrollContainer) {
      getMore(args);
      return;
    }

    const itemHeightPx = TOKEN_HEIGHT_REM * REM;
    const vestingOffsetPx = shouldRenderVestingToken ? itemHeightPx : 0;
    const visibleCenterPx = scrollContainer.scrollTop + scrollContainer.offsetHeight / 2;
    const targetIndex = Math.max(
      0,
      Math.min(tokenSlugs.length - 1, Math.floor((visibleCenterPx - vestingOffsetPx) / itemHeightPx)),
    );
    getMore({ direction: args.direction, offsetId: tokenSlugs[targetIndex] });
  });
  const tokensBySlug = useMemo(() => (
    allTokensWithStaked ? buildCollectionByKey(allTokensWithStaked, 'slug') : undefined
  ), [allTokensWithStaked]);

  const shouldUseAnimations = Boolean(isActive && allTokensWithStaked);

  // Size the container to the rendered window (viewportIndex already includes the vesting row),
  // not the full token list. Avoids a ~8000rem spacer for wallets with thousands of tokens that
  // wrecks scrollbar precision; the height grows progressively as `useInfiniteScroll` advances.
  const currentContainerHeight = useMemo(() => {
    const visibleCount = viewportSlugs?.length ?? 0;
    const renderedRows = visibleCount > 0
      ? viewportIndex + visibleCount
      : (shouldRenderVestingToken ? 1 : 0);
    return renderedRows > 0 ? renderedRows * TOKEN_HEIGHT_REM : undefined;
  }, [viewportIndex, viewportSlugs?.length, shouldRenderVestingToken]);

  const handleOpenTokenSettings = useLastCallback(() => {
    openSettingsWithState({ state: SettingsState.Assets });
  });

  const handleTokenClick = useLastCallback((slug: string) => {
    const token = tokensBySlug?.[slug];
    if (token?.isStaking) {
      onStakedTokenClick(token.stakingId);
    } else {
      onTokenClick(slug);
    }
  });

  const stateByTokenSlug = useMemo(() => {
    return buildCollectionByKey(states ?? [], 'tokenSlug');
  }, [states]);

  const stakingStateById = useMemo(() => {
    return buildCollectionByKey(activeStates, 'id');
  }, [activeStates]);

  const pinnedSlugsSet = useMemo(() => {
    return new Set(pinnedSlugs);
  }, [pinnedSlugs]);

  const prevPinnedSlugs = usePrevious2(pinnedSlugs);
  const prevAllTokensWithStaked = usePrevious2(allTokensWithStaked);

  // Detect which token was just pinned/unpinned
  const pinToggledSlug = useMemo(() => {
    if (!prevPinnedSlugs || prevPinnedSlugs === pinnedSlugs) return undefined;

    const prevSet = new Set(prevPinnedSlugs);
    const currentSet = new Set(pinnedSlugs);

    // Find added slug (pinned)
    for (const slug of currentSet) {
      if (!prevSet.has(slug)) return slug;
    }

    // Find removed slug (unpinned)
    for (const slug of prevSet) {
      if (!currentSet.has(slug)) return slug;
    }

    return undefined;
  }, [prevPinnedSlugs, pinnedSlugs]);

  // Check if pin-toggled token stayed in the same position
  const isPinAnimatable = useMemo(() => {
    if (!pinToggledSlug || !prevAllTokensWithStaked || !allTokensWithStaked) return false;

    const prevIndex = prevAllTokensWithStaked.findIndex((t) => t.slug === pinToggledSlug);
    const currentIndex = allTokensWithStaked.findIndex((t) => t.slug === pinToggledSlug);

    // Token stayed in the same position
    return prevIndex === currentIndex && prevIndex !== -1;
  }, [pinToggledSlug, prevAllTokensWithStaked, allTokensWithStaked]);

  function renderVestingToken() {
    return (
      <TokenListItem
        key="vesting"
        topOffset={0}
        withAnimation={shouldUseAnimations}
      >
        <Token
          ref={vestingTokenRef}
          token={userMycoin!}
          vestingStatus={vestingStatus}
          unfreezeEndDate={unfreezeEndDate}
          amount={vestingAmount}
          isInvestorView={isInvestorViewEnabled}
          baseCurrency={baseCurrency}
          appTheme={appTheme}
          isSensitiveDataHidden={isSensitiveDataHidden}
          tokenClassName={isWidget ? styles.tokenInWidget : undefined}
          onClick={onVestingTokenClick}
        />
      </TokenListItem>
    );
  }

  function renderToken(token: UserToken, indexInViewport: number) {
    const topOffset = (viewportIndex + indexInViewport) * TOKEN_HEIGHT_REM;

    const { stakingId, isStaking, slug, amount, decimals } = token;
    const stakingState = stakingId ? stakingStateById[stakingId] : undefined;

    // For staking tokens use their state, for base tokens use state only if not staked
    const baseTokenState = !isStaking && !stakedTokenSlugs.has(slug)
      ? stateByTokenSlug[slug]
      : undefined;

    const { annualYield, yieldType } = stakingState || baseTokenState || {};
    const stakingStatus = stakingState ? getStakingStateStatus(stakingState) : undefined;
    const isStakingAvailable = Boolean(baseTokenState && !isStakingDisabled);
    const isSwapAvailable = Boolean(swapTokensBySlug[slug]);
    const isPinned = pinnedSlugsSet.has(slug);
    const amountDecimal = isStaking ? toDecimal(amount, decimals) : undefined;
    const isPinToggled = slug === pinToggledSlug;
    const withPinTransition = isPinToggled && isPinAnimatable;

    return (
      <TokenListItem
        key={slug}
        topOffset={topOffset}
        withAnimation={shouldUseAnimations}
        shouldFadeInPlace={isPinToggled}
      >
        <Token
          token={token}
          stakingStatus={stakingStatus}
          stakingState={stakingState}
          annualYield={annualYield}
          yieldType={yieldType}
          amount={amountDecimal}
          isInvestorView={isInvestorViewEnabled}
          isActive={token.slug === currentTokenSlug}
          baseCurrency={baseCurrency}
          withChainIcon={isMultichainAccount}
          appTheme={appTheme}
          isSensitiveDataHidden={isSensitiveDataHidden}
          withContextMenu
          tokenClassName={isWidget ? styles.tokenInWidget : undefined}
          isViewMode={isViewMode}
          isStakingAvailable={isStakingAvailable}
          isSwapDisabled={isSwapDisabled || !isSwapAvailable}
          isPinned={isPinned}
          withPinTransition={withPinTransition}
          onClick={handleTokenClick}
        />
      </TokenListItem>
    );
  }

  const isEmpty = !shouldRenderVestingToken && !tokenSlugs?.length;

  if (isEmpty) {
    return (
      <EmptyListPlaceholder
        stickerTgsUrl={isWidget ? undefined : ANIMATED_STICKERS_PATHS.noData}
        stickerPreviewUrl={isWidget ? undefined : ANIMATED_STICKERS_PATHS.noDataPreview}
        stickerSize={isWidget ? undefined : ANIMATED_STICKER_SMALL_SIZE_PX}
        title={lang('No tokens yet')}
        description={lang('$no_tokens_description')}
        actionText={lang('Add Tokens')}
        className="content-centered"
        onActionClick={handleOpenTokenSettings}
      />
    );
  }

  if (isWidget) {
    const widgetStyle = currentContainerHeight ? `height: ${currentContainerHeight}rem` : undefined;

    return (
      <InfiniteScroll
        ref={widgetContainerRef}
        className={styles.compactWrapper}
        scrollContainerClosest={`.${OVERVIEW_CELL_BODY_CLASS}`}
        items={viewportSlugs}
        itemSelector=".token-list-item"
        withAbsolutePositioning
        maxHeight={currentContainerHeight === undefined ? undefined : `${currentContainerHeight}rem`}
        style={widgetStyle}
        onLoadMore={handleWidgetGetMore}
      >
        {shouldRenderVestingToken && renderVestingToken()}
        {viewportSlugs?.map((tokenSlug, i) => renderToken(tokensBySlug![tokenSlug], i))}
      </InfiniteScroll>
    );
  }

  const style = buildStyle(
    Boolean(currentContainerHeight && (!isLandscape || isSeparatePanel)) && `height: ${currentContainerHeight}rem`,
  );

  return (
    <InfiniteScroll
      className={buildClassName(
        styles.wrapper,
        isSeparatePanel && !renderedTokens && styles.wrapperLoading,
      )}
      scrollContainerClosest={getScrollContainerClosestSelector(isActive, isPortrait)}
      items={viewportSlugs}
      itemSelector=".token-list-item"
      withAbsolutePositioning={Boolean(viewportSlugs)}
      maxHeight={currentContainerHeight === undefined ? undefined : `${currentContainerHeight}rem`}
      style={style}
      onLoadMore={getMore}
      onScroll={onScroll}
    >
      {!renderedTokens && (
        <div key="loading" className={isSeparatePanel ? styles.emptyListSeparate : styles.emptyList}>
          <Spinner />
        </div>
      )}
      {shouldRenderVestingToken && renderVestingToken()}
      {viewportSlugs?.map((tokenSlug, i) => renderToken(tokensBySlug![tokenSlug], i))}
    </InfiniteScroll>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const currentAccountId = selectCurrentAccountId(global)!;
      const tokens = selectCurrentAccountTokens(global);
      const swapTokens = selectSwapTokens(global);
      const accountState = selectCurrentAccountState(global);
      const accountSettings = selectCurrentAccountSettings(global);
      const { isInvestorViewEnabled } = global.settings;

      const states = selectAccountStakingStates(global, currentAccountId);
      const isViewMode = selectIsCurrentAccountViewMode(global);

      return {
        tokens,
        swapTokens,
        vesting: accountState?.vesting?.info,
        isInvestorViewEnabled,
        currentTokenSlug: accountState?.currentTokenSlug,
        baseCurrency: global.settings.baseCurrency,
        mycoin: selectMycoin(global),
        isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
        theme: global.settings.theme,
        states,
        isMultichainAccount: selectIsMultichainAccount(global, currentAccountId),
        isViewMode,
        isSwapDisabled: selectIsSwapDisabled(global),
        isStakingDisabled: selectIsStakingDisabled(global),
        pinnedSlugs: accountSettings?.pinnedSlugs,
        alwaysHiddenSlugs: accountSettings?.alwaysHiddenSlugs,
        currencyRates: global.currencyRates,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(Assets),
);

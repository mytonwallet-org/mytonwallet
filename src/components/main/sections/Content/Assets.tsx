import React, { memo, useMemo } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type {
  ApiBaseCurrency, ApiCurrencyRates, ApiStakingState, ApiTokenWithPrice, ApiVestingInfo,
} from '../../../../api/types';
import type { Theme, UserSwapToken, UserToken } from '../../../../global/types';
import { SettingsState } from '../../../../global/types';

import { ANIMATED_STICKER_SMALL_SIZE_PX, IS_CORE_WALLET } from '../../../../config';
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
import Token from './Token';
import TokenListItem from './TokenListItem';

import styles from './Assets.module.scss';

type OwnProps = {
  isActive?: boolean;
  isSeparatePanel?: boolean;
  isWidget?: boolean;
  compactLimit?: number;
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

export const COMPACT_LIMIT_DEFAULT = 6;

function Assets({
  isActive,
  tokens,
  swapTokens,
  vesting,
  isInvestorViewEnabled,
  isSeparatePanel,
  isWidget,
  compactLimit = COMPACT_LIMIT_DEFAULT,
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
    if (IS_CORE_WALLET) return [];

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

  const {
    ref: vestingTokenRef,
    shouldRender: shouldRenderVestingToken,
    amount: vestingAmount,
    vestingStatus,
    unfreezeEndDate,
    onVestingTokenClick,
  } = useVesting({ vesting, userMycoin, isDisabled: IS_CORE_WALLET });

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

    const index = tokenSlugs!.indexOf(viewportSlugs[0]);
    return shouldRenderVestingToken ? index + 1 : index;
  }, [shouldRenderVestingToken, tokenSlugs, viewportSlugs]);
  const tokensBySlug = useMemo(() => (
    allTokensWithStaked ? buildCollectionByKey(allTokensWithStaked, 'slug') : undefined
  ), [allTokensWithStaked]);

  const shouldUseAnimations = Boolean(isActive && allTokensWithStaked);

  const currentContainerHeight = useMemo(() => {
    const totalItemsCount = (tokenSlugs?.length ?? 0) + (shouldRenderVestingToken ? 1 : 0);
    return totalItemsCount > 0 ? totalItemsCount * TOKEN_HEIGHT_REM : undefined;
  }, [tokenSlugs?.length, shouldRenderVestingToken]);

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
          onClick={onVestingTokenClick}
        />
      </TokenListItem>
    );
  }

  function renderCompactToken(token: UserToken) {
    const { stakingId, isStaking, slug, amount, decimals } = token;
    const stakingState = stakingId ? stakingStateById[stakingId] : undefined;

    const baseTokenState = !isStaking && !stakedTokenSlugs.has(slug)
      ? stateByTokenSlug[slug]
      : undefined;

    const { annualYield, yieldType } = stakingState || baseTokenState || {};
    const stakingStatus = stakingState ? getStakingStateStatus(stakingState) : undefined;
    const isStakingAvailable = Boolean(baseTokenState && !isStakingDisabled);
    const isSwapAvailable = Boolean(swapTokensBySlug[slug]);
    const isPinned = pinnedSlugsSet.has(slug);
    const amountDecimal = isStaking ? toDecimal(amount, decimals) : undefined;

    return (
      <TokenListItem
        key={slug}
        topOffset={0}
        withAnimation={false}
        isWidget
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
          tokenClassName={buildClassName(isWidget && styles.tokenInWidget)}
          isViewMode={isViewMode}
          isStakingAvailable={isStakingAvailable}
          isSwapDisabled={isSwapDisabled || !isSwapAvailable}
          isPinned={isPinned}
          onClick={handleTokenClick}
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
    const shouldFadeInPlace = slug === pinToggledSlug;
    const withPinTransition = isPinAnimatable && slug === pinToggledSlug;

    return (
      <TokenListItem
        key={slug}
        topOffset={topOffset}
        withAnimation={shouldUseAnimations}
        shouldFadeInPlace={shouldFadeInPlace}
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

  if (isWidget) {
    if (isEmpty) {
      return (
        <EmptyListPlaceholder
          title={lang('No tokens yet')}
          description={lang('$no_tokens_description')}
          actionText={lang('Add Tokens')}
          onActionClick={handleOpenTokenSettings}
        />
      );
    }

    const compactTokens = allTokensWithStaked
      ?.filter(({ isDisabled }) => !isDisabled)
      .slice(0, compactLimit) ?? [];

    return (
      <div className={styles.compactWrapper}>
        {compactTokens.map((token) => renderCompactToken(token))}
      </div>
    );
  }

  if (isEmpty) {
    return (
      <EmptyListPlaceholder
        stickerTgsUrl={ANIMATED_STICKERS_PATHS.noData}
        stickerPreviewUrl={ANIMATED_STICKERS_PATHS.noDataPreview}
        stickerSize={ANIMATED_STICKER_SMALL_SIZE_PX}
        title={lang('No tokens yet')}
        description={lang('$no_tokens_description')}
        actionText={lang('Add Tokens')}
        onActionClick={handleOpenTokenSettings}
      />
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

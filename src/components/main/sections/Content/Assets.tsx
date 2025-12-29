import React, { memo, useLayoutEffect, useMemo, useRef } from '../../../../lib/teact/teact';
import { setExtraStyles } from '../../../../lib/teact/teact-dom';
import { getActions, withGlobal } from '../../../../global';

import type { ApiBaseCurrency, ApiStakingState, ApiTokenWithPrice, ApiVestingInfo } from '../../../../api/types';
import type { Theme, UserSwapToken, UserToken } from '../../../../global/types';
import { SettingsState } from '../../../../global/types';

import { ANIMATED_STICKER_SMALL_SIZE_PX, IS_CORE_WALLET } from '../../../../config';
import {
  selectAccountStakingStates,
  selectCurrentAccountId,
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
import { toDecimal } from '../../../../util/decimals';
import { buildCollectionByKey } from '../../../../util/iteratees';
import { getFullStakingBalance, getIsActiveStakingState, getStakingStateStatus } from '../../../../util/staking';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';
import { getScrollContainerClosestSelector } from '../../helpers/scrollableContainer';

import useAppTheme from '../../../../hooks/useAppTheme';
import useCurrentOrPrev from '../../../../hooks/useCurrentOrPrev';
import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useInfiniteScroll from '../../../../hooks/useInfiniteScroll';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useShowTransition from '../../../../hooks/useShowTransition';
import useVesting from '../../../../hooks/useVesting';

import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';
import Button from '../../../ui/Button';
import InfiniteScroll from '../../../ui/InfiniteScroll';
import Spinner from '../../../ui/Spinner';
import Token from './Token';

import styles from './Assets.module.scss';

type OwnProps = {
  isActive?: boolean;
  isSeparatePanel?: boolean;
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
  isMultichainAccount: boolean;
  isSensitiveDataHidden?: true;
  states?: ApiStakingState[];
  isViewMode?: boolean;
  isSwapDisabled?: boolean;
  isStakingDisabled?: boolean;
}

const LIST_SLICE = 30;
const TOKEN_HEIGHT_REM = 4;

function Assets({
  isActive,
  tokens,
  swapTokens,
  vesting,
  isInvestorViewEnabled,
  isSeparatePanel,
  currentTokenSlug,
  onTokenClick,
  onStakedTokenClick,
  baseCurrency,
  mycoin,
  isMultichainAccount,
  isSensitiveDataHidden,
  theme,
  states,
  isViewMode,
  isSwapDisabled,
  isStakingDisabled,
  onScroll,
}: OwnProps & StateProps) {
  const lang = useLang();
  const { openSettingsWithState } = getActions();

  const containerRef = useRef<HTMLDivElement>();
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

  const stakedTokens = useMemo(() => {
    return activeStates.reduce((prevValue, state) => {
      const token = tokens?.find(({ slug }) => slug === state.tokenSlug);
      if (token) {
        prevValue[state.tokenSlug] = { token, state };
      }
      return prevValue;
    }, {} as Record<string, { token: UserToken; state: ApiStakingState }>);
  }, [tokens, activeStates]);

  const swapTokensBySlug = useMemo(() => {
    return buildCollectionByKey<UserSwapToken>(swapTokens ?? [], 'slug');
  }, [swapTokens]);

  const {
    shouldRender: shouldRenderStakedTokens,
  } = useShowTransition({
    isOpen: Boolean(Object.keys(stakedTokens).length),
    withShouldRender: true,
  });

  const {
    ref: vestingTokenRef,
    shouldRender: shouldRenderVestingToken,
    amount: vestingAmount,
    vestingStatus,
    unfreezeEndDate,
    onVestingTokenClick,
  } = useVesting({ vesting, userMycoin, isDisabled: IS_CORE_WALLET });

  const tokenSlugs = useMemo(() => (
    renderedTokens
      ?.filter(({ isDisabled }) => !isDisabled)
      .map(({ slug }) => slug)
  ), [renderedTokens]);
  const [viewportSlugs, getMore] = useInfiniteScroll(
    undefined, tokenSlugs, undefined, undefined, undefined, isActive, isPortrait,
  );
  const viewportIndex = useMemo(() => {
    if (!viewportSlugs) return -1;

    let index = tokenSlugs!.indexOf(viewportSlugs[0]);
    if (shouldRenderStakedTokens) {
      index += Object.keys(stakedTokens).length;
    }
    if (shouldRenderVestingToken) {
      index++;
    }

    return index;
  }, [shouldRenderStakedTokens, shouldRenderVestingToken, tokenSlugs, viewportSlugs, stakedTokens]);
  const tokensBySlug = useMemo(() => (
    renderedTokens ? buildCollectionByKey(renderedTokens, 'slug') : undefined
  ), [renderedTokens]);
  const withAbsolutePositioning = tokenSlugs && tokenSlugs.length > LIST_SLICE;

  const currentContainerHeight = useMemo(() => {
    if (!withAbsolutePositioning || !viewportSlugs?.length || viewportIndex < 0) return undefined;

    return (viewportIndex + viewportSlugs.length) * TOKEN_HEIGHT_REM;
  }, [viewportIndex, viewportSlugs?.length, withAbsolutePositioning]);

  useLayoutEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    setExtraStyles(container, {
      height: currentContainerHeight && !isLandscape ? `${currentContainerHeight}rem` : '',
    });
  }, [isLandscape, currentContainerHeight]);

  const handleOpenTokenSettings = useLastCallback(() => {
    openSettingsWithState({ state: SettingsState.Assets });
  });

  const stateByTokenSlug = buildCollectionByKey(states ?? [], 'tokenSlug');

  function renderVestingToken() {
    return (
      <Token
        ref={vestingTokenRef}
        key="vesting"
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
    );
  }

  function renderStakedTokens() {
    return Object.values(stakedTokens).map(({ state, token }) => {
      const { id, annualYield, yieldType } = state;
      const stakingStatus = getStakingStateStatus(state);
      const stakingBalance = getFullStakingBalance(state);

      return (
        <Token
          key={`staking-${id}`}
          token={token}
          stakingStatus={stakingStatus}
          annualYield={annualYield}
          yieldType={yieldType}
          amount={toDecimal(stakingBalance, token.decimals)}
          isInvestorView={isInvestorViewEnabled}
          baseCurrency={baseCurrency}
          appTheme={appTheme}
          isSensitiveDataHidden={isSensitiveDataHidden}
          withContextMenu
          isViewMode={isViewMode}
          isSwapDisabled={isSwapDisabled}
          stakingState={state}
          onClick={onStakedTokenClick}
        />
      );
    });
  }

  function renderToken(token: UserToken, indexInViewport: number) {
    const style = withAbsolutePositioning
      ? `position: absolute; top: ${(viewportIndex + indexInViewport) * TOKEN_HEIGHT_REM}rem`
      : undefined;

    const {
      annualYield,
      yieldType,
    } = (!(token.slug in stakedTokens) && stateByTokenSlug[token.slug]) || {};
    const isStakingAvailable = Boolean(!isStakingDisabled && stateByTokenSlug[token.slug]);
    const isSwapAvailable = Boolean(swapTokensBySlug[token.slug]);

    return (
      <Token
        classNames="token-list-item"
        style={style}
        key={token.slug}
        token={token}
        annualYield={annualYield}
        yieldType={yieldType}
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
        onClick={onTokenClick}
      />
    );
  }

  const isEmpty = !shouldRenderVestingToken && !shouldRenderStakedTokens && !tokenSlugs?.length;

  if (isEmpty) {
    return (
      <div className={styles.noTokens}>
        <AnimatedIconWithPreview
          tgsUrl={ANIMATED_STICKERS_PATHS.noData}
          previewUrl={ANIMATED_STICKERS_PATHS.noDataPreview}
          size={ANIMATED_STICKER_SMALL_SIZE_PX}
          nonInteractive
          noLoop={false}
          className={styles.sticker}
        />
        <div className={styles.noTokensText}>
          <span className={styles.noTokensHeader}>{lang('No tokens yet')}</span>
          <span className={styles.noTokensDescription}>{lang('$no_tokens_description')}</span>
          <Button
            onClick={handleOpenTokenSettings}
            isPrimary
            isSmall
            className={styles.openSettingsButton}
          >
            {lang('Add Tokens')}
          </Button>
        </div>
      </div>
    );
  }

  return (
    <InfiniteScroll
      ref={containerRef}
      className={buildClassName(
        styles.wrapper,
        isSeparatePanel && !renderedTokens && styles.wrapperLoading,
      )}
      scrollContainerClosest={getScrollContainerClosestSelector(isActive, isPortrait)}
      items={viewportSlugs}
      itemSelector=".token-list-item"
      withAbsolutePositioning={withAbsolutePositioning}
      maxHeight={currentContainerHeight === undefined ? undefined : `${currentContainerHeight}rem`}
      onLoadMore={getMore}
      onScroll={onScroll}
    >
      {!renderedTokens && (
        <div key="loading" className={isSeparatePanel ? styles.emptyListSeparate : styles.emptyList}>
          <Spinner />
        </div>
      )}
      {shouldRenderVestingToken && renderVestingToken()}
      {shouldRenderStakedTokens && renderStakedTokens()}
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
        isMultichainAccount: selectIsMultichainAccount(global, currentAccountId),
        isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
        theme: global.settings.theme,
        states,
        isViewMode,
        isSwapDisabled: selectIsSwapDisabled(global),
        isStakingDisabled: selectIsStakingDisabled(global),
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(Assets),
);

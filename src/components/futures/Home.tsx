import type { TeactNode } from '../../lib/teact/teact';
import React, { memo, useMemo, useRef } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiPerpsMarketAsset, ApiPerpsMarketSection } from '../../api/types';
import type { PerpsAccountSnapshot } from '../../global/types';

import { APP_NAME } from '../../config';
import { PERPS_ONBOARDING_BANNER_ID } from '../../global/helpers/perps';
import {
  isPerpsSnapshotStale,
  selectCurrentAccountId,
  selectCurrentAccountPerps,
  selectIsPerpsMarketStale,
  selectIsPerpsOnboardingExpected,
  selectPerpsMarketAssetsById,
  selectPerpsUnavailableReason,
  selectShouldShowPerpsOnboarding,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { animateContentShift } from '../../util/layoutChangeAnimation';
import { MEMO_EMPTY_ARRAY } from '../../util/memo';
import {
  buildPerpsMarketToken, buildPerpsSections, isListedAsset, POSITIONS_PREVIEW_LIMIT, POSITIONS_SECTION_ID,
} from './helpers/buildPerpsSections';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useFlag from '../../hooks/useFlag';
import useHeightChange from '../../hooks/useHeightChange';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';
import useCataloguePositions from './hooks/useCataloguePositions';
import usePerpsStaleness from './hooks/usePerpsStaleness';

import Search from '../market/Search';
import Section from '../market/Section';
import ShowcaseSkeleton from '../market/ShowcaseSkeleton';
import TradeNotice from '../swap/TradeNotice';
import Skeleton from '../ui/Skeleton';
import AccountActivity from './activity/AccountActivity';
import LoadError from './LoadError';
import OperationBanner from './OperationBanner';
import BalanceRow from './positions/BalanceRow';
import PositionList from './positions/PositionList';
import PositionListSummary from './positions/PositionListSummary';
import Screen from './Screen';
import Stories from './stories/Stories';

import marketStyles from '../market/Market.module.scss';
import futuresStyles from './Futures.module.scss';
import styles from './Home.module.scss';

import onboardingIllustrationUrl from '../../assets/futures/onboardingIllustration.webp';

const SCROLL_CONTAINER_SELECTOR = '.custom-scroll';

interface OwnProps {
  onBackClick: NoneToVoidFunction;
}

interface StateProps {
  accountId?: string;
  unavailableReason?: string;
  assets?: ApiPerpsMarketAsset[];
  assetsById?: Record<string, ApiPerpsMarketAsset>;
  marketSections?: ApiPerpsMarketSection[];
  isMarketLoadFailed?: true;
  isMarketStale: boolean;
  snapshot?: PerpsAccountSnapshot;
  isSnapshotLoadFailed?: true;
  shouldShowOnboarding: boolean;
  isOnboardingExpected: boolean;
}

function Home({
  accountId,
  unavailableReason,
  assets,
  assetsById,
  marketSections,
  isMarketLoadFailed,
  isMarketStale,
  snapshot,
  isSnapshotLoadFailed,
  shouldShowOnboarding,
  isOnboardingExpected,
  onBackClick,
}: OwnProps & StateProps) {
  const {
    loadPerpsMarket, loadPerpsSnapshot, openFuturesMarket, openFuturesSection, dismissHomeBanner,
  } = getActions();

  const lang = useLang();
  const { isPortrait } = useDeviceScreen();
  const [areStoriesOpen, openStories, closeStories] = useFlag();

  const canRead = !unavailableReason;
  // An account without Futures waits for no snapshot, so its notice stays undimmed
  const isPositionsStale = usePerpsStaleness(canRead && isPerpsSnapshotStale(snapshot), Boolean(snapshot));
  const isCatalogueStale = usePerpsStaleness(isMarketStale, Boolean(marketSections));
  // The totals count every position, while the card lists only those the catalogue can open
  const cataloguePositions = useCataloguePositions(snapshot?.positions, assetsById);

  // The onboarding appears once the history loads, so it fades in rather than pops up
  const { ref: onboardingRef, shouldRender: shouldRenderOnboarding } = useShowTransition<HTMLElement>({
    isOpen: shouldShowOnboarding,
    noMountTransition: true,
    withShouldRender: true,
    className: 'slow',
  });

  // The divider titles the markets under the onboarding and its placeholder, and fades out together with the banner
  const { ref: marketDividerRef, shouldRender: shouldRenderMarketDivider } = useShowTransition<HTMLHeadingElement>({
    isOpen: shouldShowOnboarding || (isOnboardingExpected && !snapshot && !isSnapshotLoadFailed),
    noMountTransition: true,
    withShouldRender: true,
    className: 'slow',
  });

  // The showcase trims every section to its limit, while the "See All" screen lists all its markets
  const sections = useMemo(
    () => marketSections && buildPerpsSections(lang, marketSections, isPortrait).map((section) => ({
      ...section,
      tokens: section.tokens.slice(0, section.visibleLimit),
    })),
    [isPortrait, lang, marketSections],
  );

  // The search stays in place while the catalogue loads, so the showcase below it does not jump
  const searchTokens = useMemo(
    () => assets?.filter(isListedAsset).map((asset) => buildPerpsMarketToken(asset))
      ?? MEMO_EMPTY_ARRAY,
    [assets],
  );

  const handleMarketClick = useLastCallback((assetId: string) => {
    openFuturesMarket({ assetId });
  });

  const handleShowAllClick = useLastCallback((sectionId: string) => {
    openFuturesSection({ sectionId });
  });

  const handleShowAllPositionsClick = useLastCallback(() => {
    openFuturesSection({ sectionId: POSITIONS_SECTION_ID });
  });

  const handleMarketRetry = useLastCallback(() => {
    loadPerpsMarket({ force: true });
  });

  const handleOnboardingClose = useLastCallback(() => {
    dismissHomeBanner({ accountId: accountId!, id: PERPS_ONBOARDING_BANNER_ID });
  });

  function renderOnboarding() {
    return (
      <section ref={onboardingRef} className={styles.onboarding}>
        <img src={onboardingIllustrationUrl} alt="" className={styles.onboardingIllustration} />
        <div className={styles.onboardingText}>
          {/* A plain value keeps the line break as text, so the stylesheet applies it only to the narrow banner */}
          <h2 className={styles.onboardingTitle}>{lang('PerpsOnboardingTitle', APP_NAME)}</h2>
          <p className={styles.onboardingDescription}>{lang('PerpsOnboardingDescription')}</p>
        </div>
        <button type="button" className={styles.onboardingButton} onClick={openStories}>
          {lang('PerpsOnboardingOpen')}
        </button>
        <button
          type="button"
          className={styles.onboardingClose}
          aria-label={lang('Close')}
          onClick={handleOnboardingClose}
        >
          <i className="icon-close" aria-hidden />
        </button>
      </section>
    );
  }

  function renderMarketDivider() {
    return shouldRenderMarketDivider && (
      <h2 ref={marketDividerRef} className={styles.marketDivider}>{lang('Futures Market')}</h2>
    );
  }

  function renderBalance() {
    return snapshot?.balanceWithdrawal && (
      <div className={futuresStyles.card}>
        <BalanceRow withdrawal={snapshot.balanceWithdrawal} />
      </div>
    );
  }

  // Futures need a mainnet account with an Arbitrum address, while the markets stay open to everyone
  function renderUnavailableNotice() {
    return unavailableReason && (
      <TradeNotice message={lang(unavailableReason)} isInformational className={styles.unavailable} />
    );
  }

  function renderPositions() {
    // In landscape the notice stands under the market search
    if (unavailableReason) return isPortrait ? renderUnavailableNotice() : undefined;

    if (!snapshot) {
      if (isSnapshotLoadFailed) return <LoadError className={futuresStyles.card} onRetry={loadPerpsSnapshot} />;

      // The placeholder takes the shape of what the snapshot is likely to show, so the block keeps its height
      return isOnboardingExpected
        ? <Skeleton className={styles.onboardingSkeleton} />
        : <PositionListSummary isLoading />;
    }

    if (shouldRenderOnboarding) {
      return (
        <>
          {renderOnboarding()}
          {renderBalance()}
        </>
      );
    }

    // Without positions the summary shows only zeros, so the balance or the markets come first. A book that failed
    // to load may hold positions, and the summary tells that the totals are incomplete.
    const isIncomplete = snapshot.unavailableDexs.length > 0;
    if (!snapshot.positions.length && !isIncomplete) return renderBalance();

    return (
      <>
        <PositionListSummary
          totalEquity={snapshot.totalEquity}
          totalPnl={snapshot.totalPnl}
          totalReturnOnEquity={snapshot.totalReturnOnEquity}
          isIncomplete={isIncomplete}
        />
        {Boolean(cataloguePositions?.length) && (
          <div className={futuresStyles.card}>
            <PositionList limit={POSITIONS_PREVIEW_LIMIT} onShowAllClick={handleShowAllPositionsClick} />
          </div>
        )}
        {renderBalance()}
      </>
    );
  }

  function renderCatalogue() {
    if (!sections) {
      return isMarketLoadFailed
        ? <LoadError onRetry={handleMarketRetry} />
        : <ShowcaseSkeleton />;
    }

    return (
      <>
        {sections.map((section) => (
          <Section
            key={section.id}
            section={section}
            showAllLabel={lang('See All')}
            onTokenClick={handleMarketClick}
            onShowAllClick={handleShowAllClick}
          />
        ))}
      </>
    );
  }

  function renderOperationBanner() {
    return (
      <ResizingBlock className={styles.operationBannerBlock}>
        <OperationBanner className={styles.operationBanner} />
      </ResizingBlock>
    );
  }

  const search = <Search tokens={searchTokens} onTokenClick={handleMarketClick} />;
  const positionsClassName = buildClassName(
    styles.positions, futuresStyles.dimmable, isPositionsStale && futuresStyles.stale,
  );
  const catalogueClassName = buildClassName(futuresStyles.dimmable, isCatalogueStale && futuresStyles.stale);

  if (!isPortrait) {
    return (
      <div className={buildClassName(marketStyles.slideWrapper, futuresStyles.screen)}>
        <div className={buildClassName(marketStyles.slide, 'custom-scroll')}>
          {canRead && renderOperationBanner()}
          <ResizingBlock className={positionsClassName}>
            {renderPositions()}
            {renderMarketDivider()}
          </ResizingBlock>
          <div className={styles.panel}>
            {search}
            {renderUnavailableNotice()}
            <div className={catalogueClassName}>{renderCatalogue()}</div>
          </div>
          {canRead && <AccountActivity />}
        </div>
        <Stories isOpen={areStoriesOpen} onClose={closeStories} />
      </div>
    );
  }

  return (
    <Screen
      title={lang('Futures')}
      bodyClassName={styles.body}
      overlay={search}
      onBackClick={onBackClick}
    >
      {canRead && renderOperationBanner()}
      <ResizingBlock className={positionsClassName}>
        {renderPositions()}
        {renderMarketDivider()}
      </ResizingBlock>
      <div className={buildClassName(styles.catalogue, catalogueClassName)}>{renderCatalogue()}</div>
      {canRead && <AccountActivity />}
      <Stories isOpen={areStoriesOpen} onClose={closeStories} />
    </Screen>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const accountPerps = selectCurrentAccountPerps(global);

  return {
    accountId: selectCurrentAccountId(global),
    unavailableReason: selectPerpsUnavailableReason(global),
    assets: global.perps.market?.assets,
    assetsById: selectPerpsMarketAssetsById(global),
    marketSections: global.perps.market?.marketSections,
    isMarketLoadFailed: global.perps.isMarketLoadFailed,
    isMarketStale: selectIsPerpsMarketStale(global),
    snapshot: accountPerps?.snapshot,
    isSnapshotLoadFailed: accountPerps?.isSnapshotLoadFailed,
    shouldShowOnboarding: selectShouldShowPerpsOnboarding(global),
    isOnboardingExpected: selectIsPerpsOnboardingExpected(global),
  };
})(Home));

// A separate component gets a new element after a rotation, so `useHeightChange` observes the block of the current layout
function ResizingBlock({ className, children }: { className: string; children: TeactNode }) {
  const ref = useRef<HTMLDivElement>();

  // The content below jumps to its new place and slides there from the old one
  const handleHeightChange = useLastCallback((prevHeight: number, nextHeight: number) => {
    for (let element = ref.current!.nextElementSibling; element; element = element.nextElementSibling) {
      animateContentShift(element as HTMLElement, SCROLL_CONTAINER_SELECTOR, prevHeight - nextHeight);
    }
  });

  useHeightChange(ref, handleHeightChange);

  return <div ref={ref} className={className}>{children}</div>;
}

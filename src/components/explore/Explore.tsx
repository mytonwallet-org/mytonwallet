import React, {
  memo, useEffect, useMemo, useRef,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiSite, ApiSiteCategory } from '../../api/types';

import { ANIMATED_STICKER_BIG_SIZE_PX } from '../../config';
import { selectCurrentAccountState } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import captureEscKeyListener from '../../util/captureEscKeyListener';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { captureControlledSwipe } from '../../util/swipeController';
import useTelegramMiniAppSwipeToClose from '../../util/telegram/hooks/useTelegramMiniAppSwipeToClose';
import { IS_ANDROID_APP, IS_IOS_APP, IS_TOUCH_ENV } from '../../util/windowEnvironment';
import { SEC } from '../../api/constants';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';
import {
  filterSites,
  processSites,
} from './helpers/utils';

import useAutoScroll from '../../hooks/useAutoScroll';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';
import usePrevious2 from '../../hooks/usePrevious2';
import useScrolledState from '../../hooks/useScrolledState';
import { useStateRef } from '../../hooks/useStateRef';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Spinner from '../ui/Spinner';
import Transition from '../ui/Transition';
import Category from './Category';
import DappFeed from './DappFeed';
import ExploreSearch from './ExploreSearch';
import SiteFeatured from './SiteFeatured';
import SiteList from './SiteList';

import styles from './Explore.module.scss';

interface OwnProps {
  isActive?: boolean;
  onScroll?: (e: React.UIEvent<HTMLDivElement>) => void;
}

interface StateProps {
  categories?: ApiSiteCategory[];
  sites?: ApiSite[];
  featuredTitle?: string;
  shouldRestrict: boolean;
  currentSiteCategoryId?: number;
}

const enum SLIDES {
  main,
  category,
}

const SLIDE_DURATION = 4 * SEC;

function Explore({
  isActive,
  categories,
  sites: originalSites,
  featuredTitle,
  shouldRestrict,
  currentSiteCategoryId,
  onScroll,
}: OwnProps & StateProps) {
  const {
    loadExploreSites,
    getDapps,
    openSiteCategory,
    closeSiteCategory,
  } = getActions();

  const transitionRef = useRef<HTMLDivElement>();
  const featuredContainerRef = useRef<HTMLDivElement>();

  const lang = useLang();
  const { isLandscape, isPortrait } = useDeviceScreen();

  const { renderingKey } = useModalTransitionKeys(currentSiteCategoryId || 0, !!isActive);
  const prevSiteCategoryIdRef = useStateRef(usePrevious2(renderingKey));
  const { disableSwipeToClose, enableSwipeToClose } = useTelegramMiniAppSwipeToClose(isActive);

  // On desktop should be used external scroll detection via `onScroll` prop
  const {
    handleScroll: handleContentScroll,
    isScrolled,
  } = useScrolledState();

  useEffect(
    () => (renderingKey ? captureEscKeyListener(closeSiteCategory) : undefined),
    [closeSiteCategory, renderingKey],
  );

  const filteredSites = useMemo(() => filterSites(originalSites, shouldRestrict), [originalSites, shouldRestrict]);

  const { featuredSites, allSites } = useMemo(() => processSites(filteredSites), [filteredSites]);

  useEffect(() => {
    if (!IS_TOUCH_ENV || !filteredSites?.length) {
      return undefined;
    }

    return captureControlledSwipe(transitionRef.current!, {
      onSwipeRightStart: () => {
        closeSiteCategory();

        disableSwipeToClose();
      },
      onCancel: () => {
        openSiteCategory({ id: prevSiteCategoryIdRef.current! });

        enableSwipeToClose();
      },
    });
  }, [disableSwipeToClose, enableSwipeToClose, filteredSites?.length, prevSiteCategoryIdRef]);

  useAutoScroll({
    containerRef: featuredContainerRef,
    itemSelector: `.${styles.featuredItem}`,
    interval: SLIDE_DURATION,
    isDisabled: !isActive || featuredSites.length <= 1,
  });

  const filteredCategories = useMemo(() => {
    return categories?.filter((category) => allSites[category.id]?.length > 0);
  }, [categories, allSites]);

  useEffect(() => {
    if (!isActive) return;

    getDapps();
    loadExploreSites({ isLandscape, langCode: lang.code });
  }, [isActive, isLandscape, lang.code]);

  function renderFeatured() {
    return (
      <div className={styles.featuredSection}>
        <h2 className={buildClassName(styles.sectionHeader, styles.sectionHeaderFeatured)}>
          {lang(featuredTitle || 'Trending')}
        </h2>
        <div className={styles.featuredList} ref={featuredContainerRef}>
          {featuredSites.map((site) => (
            <SiteFeatured key={`${site.url}-${site.name}`} site={site} className={styles.featuredItem} />
          ))}
        </div>
      </div>
    );
  }

  function renderContent(isContentActive: boolean, isFrom: boolean, currentKey: SLIDES) {
    switch (currentKey) {
      case SLIDES.main:
        return (
          <div
            className={buildClassName(styles.slide, 'custom-scroll')}
            onScroll={isPortrait ? handleContentScroll : onScroll}
          >
            <ExploreSearch
              shouldShowNotch={isScrolled}
              sites={filteredSites}
            />
            <DappFeed />

            {Boolean(featuredSites.length) && renderFeatured()}

            {Boolean(filteredCategories?.length) && (
              <>
                <h2 className={styles.sectionHeader}>{lang('Popular Apps')}</h2>
                <div className={buildClassName(styles.list, isLandscape && styles.landscapeList)}>
                  {filteredCategories.map((category) => (
                    <Category key={category.id} category={category} sites={allSites[category.id]} />
                  ))}
                </div>
              </>
            )}
          </div>
        );

      case SLIDES.category: {
        const currentSiteCategory = allSites[renderingKey];
        if (!currentSiteCategory) return undefined;

        return (
          <SiteList
            key={renderingKey}
            isActive={isContentActive}
            categoryId={renderingKey}
            sites={currentSiteCategory}
          />
        );
      }
    }
  }

  if (filteredSites === undefined) {
    return (
      <div className={buildClassName(styles.emptyList, styles.emptyListLoading)}>
        <Spinner />
      </div>
    );
  }

  if (filteredSites.length === 0) {
    return (
      <div className={styles.emptyList}>
        <AnimatedIconWithPreview
          play={isActive}
          tgsUrl={ANIMATED_STICKERS_PATHS.happy}
          previewUrl={ANIMATED_STICKERS_PATHS.happyPreview}
          size={ANIMATED_STICKER_BIG_SIZE_PX}
          className={styles.sticker}
          noLoop={false}
          nonInteractive
        />
        <p className={styles.emptyListTitle}>{lang('No partners yet')}</p>
      </div>
    );
  }

  return (
    <Transition
      ref={transitionRef}
      name={resolveSlideTransitionName()}
      activeKey={renderingKey ? SLIDES.category : SLIDES.main}
      withSwipeControl
      className={styles.rootSlide}
    >
      {renderContent}
    </Transition>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const { currentSiteCategoryId } = selectCurrentAccountState(global) || {};
  const { categories, sites, featuredTitle } = global.exploreData || {};

  return {
    sites,
    categories,
    featuredTitle,
    shouldRestrict: global.restrictions.isLimitedRegion && (IS_IOS_APP || IS_ANDROID_APP),
    currentSiteCategoryId,
  };
})(Explore));

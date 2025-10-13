import React, {
  memo, useEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiSite, ApiSiteCategory } from '../../api/types';

import { ANIMATED_STICKER_BIG_SIZE_PX } from '../../config';
import { selectCurrentAccountState } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import captureEscKeyListener from '../../util/captureEscKeyListener';
import { stopEvent } from '../../util/domEvents';
import { vibrate } from '../../util/haptics';
import resolveSlideTransitionName from '../../util/resolveSlideTransitionName';
import { captureControlledSwipe } from '../../util/swipeController';
import useTelegramMiniAppSwipeToClose from '../../util/telegram/hooks/useTelegramMiniAppSwipeToClose';
import {
  IS_ANDROID, IS_ANDROID_APP, IS_IOS_APP, IS_TOUCH_ENV,
} from '../../util/windowEnvironment';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';
import {
  filterSites,
  findSiteByUrl,
  generateSearchSuggestions,
  openSite,
  processSites,
  type SearchSuggestions,
} from './helpers/utils';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useEffectWithPrevDeps from '../../hooks/useEffectWithPrevDeps';
import useFlag from '../../hooks/useFlag';
import useHorizontalScroll from '../../hooks/useHorizontalScroll';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useModalTransitionKeys from '../../hooks/useModalTransitionKeys';
import usePrevious2 from '../../hooks/usePrevious2';
import useScrolledState from '../../hooks/useScrolledState';
import { useStateRef } from '../../hooks/useStateRef';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Spinner from '../ui/Spinner';
import Transition from '../ui/Transition';
import Category from './Category';
import DappFeed from './DappFeed';
import ExploreSearchSuggestions from './ExploreSearchSuggestions';
import Site from './Site';
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
  browserHistory?: string[];
  currentSiteCategoryId?: number;
}

const SUGGESTIONS_OPEN_DELAY = 300;
const enum SLIDES {
  main,
  category,
}

function Explore({
  isActive,
  categories,
  sites: originalSites,
  featuredTitle,
  shouldRestrict,
  browserHistory,
  currentSiteCategoryId,
  onScroll,
}: OwnProps & StateProps) {
  const {
    loadExploreSites,
    getDapps,
    removeSiteFromBrowserHistory,
    openSiteCategory,
    closeSiteCategory,
  } = getActions();

  const inputRef = useRef<HTMLInputElement>();
  const suggestionsTimeoutRef = useRef<number | undefined>(undefined);
  const transitionRef = useRef<HTMLDivElement>();
  const featuredContainerRef = useRef<HTMLDivElement>();

  const lang = useLang();
  const { isLandscape, isPortrait } = useDeviceScreen();
  const [searchValue, setSearchValue] = useState<string>('');
  const [isSearchFocused, markSearchFocused, unmarkSearchFocused] = useFlag(false);
  const [isSuggestionsVisible, showSuggestions, hideSuggestions] = useFlag(false);
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

  const searchSuggestions = useMemo<SearchSuggestions>(
    () => generateSearchSuggestions(searchValue, browserHistory, filteredSites),
    [browserHistory, searchValue, filteredSites],
  );

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

  useHorizontalScroll({
    containerRef: featuredContainerRef,
    isDisabled: IS_TOUCH_ENV || featuredSites.length === 0,
    shouldPreventDefault: true,
    contentSelector: `.${styles.featuredList}`,
  });

  const filteredCategories = useMemo(() => {
    return categories?.filter((category) => allSites[category.id]?.length > 0);
  }, [categories, allSites]);

  useEffect(() => {
    if (!isActive) return;

    getDapps();
    loadExploreSites({ isLandscape, langCode: lang.code });
  }, [isActive, isLandscape, lang.code]);

  const safeShowSuggestions = useLastCallback(() => {
    if (searchSuggestions.isEmpty) return;

    // Simultaneous opening of the virtual keyboard and display of Saved Addresses causes animation degradation
    if (IS_ANDROID) {
      suggestionsTimeoutRef.current = window.setTimeout(showSuggestions, SUGGESTIONS_OPEN_DELAY);
    } else {
      showSuggestions();
    }
  });

  const safeHideSuggestions = useLastCallback(() => {
    if (isSuggestionsVisible) {
      hideSuggestions();
    }
    window.clearTimeout(suggestionsTimeoutRef.current);
  });

  useEffectWithPrevDeps(([prevIsSearchFocused]) => {
    if ((prevIsSearchFocused && !isSearchFocused) || searchSuggestions.isEmpty) {
      safeHideSuggestions();
    }
    if (isSearchFocused && !searchSuggestions.isEmpty) {
      safeShowSuggestions();
    }
  }, [isSearchFocused, searchSuggestions.isEmpty]);

  const handleSiteClick = useLastCallback((
    e: React.SyntheticEvent<HTMLDivElement | HTMLAnchorElement>,
    url: string,
  ) => {
    void vibrate();
    hideSuggestions();
    const site = findSiteByUrl(originalSites, url);
    openSite(url, site?.isExternal, site?.name);
  });

  const handleSiteClear = useLastCallback((e: React.MouseEvent, url: string) => {
    stopEvent(e);

    removeSiteFromBrowserHistory({ url });
  });

  function handleSearchValueChange(e: React.ChangeEvent<HTMLInputElement>) {
    setSearchValue(e.target.value);
  }

  const handleMenuClose = useLastCallback(() => {
    inputRef.current?.blur();
  });

  function handleSearchSubmit(e: React.FormEvent<HTMLFormElement>) {
    stopEvent(e);

    handleMenuClose();

    if (searchValue.length > 0) {
      openSite(searchValue);
      setSearchValue('');
    }
  }

  function renderSearch() {
    return (
      <form action="#" onSubmit={handleSearchSubmit} className={styles.searchContainer} autoComplete="off">
        <i className={buildClassName(styles.searchIcon, 'icon-search')} aria-hidden />
        <input
          name="explore-search"
          className={styles.searchInput}
          placeholder={lang('Search app or enter address')}
          value={searchValue}
          autoCorrect={false}
          autoCapitalize="none"
          spellCheck={false}
          inputMode="url"
          onChange={handleSearchValueChange}
          onFocus={markSearchFocused}
          onBlur={unmarkSearchFocused}
        />
      </form>
    );
  }

  function renderFeatured() {
    return (
      <div ref={featuredContainerRef} className={styles.featuredSection}>
        <h2 className={buildClassName(styles.sectionHeader, styles.sectionHeaderFeatured)}>
          {lang(featuredTitle || 'Trending')}
        </h2>
        <div className={styles.featuredList}>
          {featuredSites.map((site) => (
            <Site key={`${site.url}-${site.name}`} site={site} isFeatured />
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
            <div className={buildClassName(styles.searchWrapper, 'with-notch-on-scroll', isScrolled && 'is-scrolled')}>
              {renderSearch()}
              <ExploreSearchSuggestions
                isSuggestionsVisible={isSuggestionsVisible}
                searchSuggestions={searchSuggestions}
                searchValue={searchValue}
                onSiteClick={handleSiteClick}
                onSiteClear={handleSiteClear}
                onClose={handleMenuClose}
              />
            </div>

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
  const { browserHistory, currentSiteCategoryId } = selectCurrentAccountState(global) || {};
  const { categories, sites, featuredTitle } = global.exploreData || {};

  return {
    sites,
    categories,
    featuredTitle,
    shouldRestrict: global.restrictions.isLimitedRegion && (IS_IOS_APP || IS_ANDROID_APP),
    browserHistory,
    currentSiteCategoryId,
  };
})(Explore));

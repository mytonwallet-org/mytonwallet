import React, { memo, useMemo, useRef, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiSite } from '../../api/types';

import { selectCurrentAccountState } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { stopEvent } from '../../util/domEvents';
import { vibrate } from '../../util/haptics';
import { IS_ANDROID } from '../../util/windowEnvironment';
import { findSiteByUrl, generateSearchSuggestions, openSite, type SearchSuggestions } from './helpers/utils';

import useEffectOnce from '../../hooks/useEffectOnce';
import useEffectWithPrevDeps from '../../hooks/useEffectWithPrevDeps';
import useFlag from '../../hooks/useFlag';
import useKeyboardListNavigation from '../../hooks/useKeyboardListNavigation';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import ExploreSearchSuggestions, { SUGGESTION_ITEM_CLASS_NAME } from './ExploreSearchSuggestions';

import styles from './Explore.module.scss';

interface OwnProps {
  shouldShowNotch: boolean;
  sites: ApiSite[] | undefined;
}

interface StateProps {
  browserHistory?: string[];
  allSites?: ApiSite[];
}

const SUGGESTIONS_OPEN_DELAY = 300;

function ExploreSearch({ shouldShowNotch, sites, allSites, browserHistory }: OwnProps & StateProps) {
  const { removeSiteFromBrowserHistory } = getActions();

  const lang = useLang();
  const inputRef = useRef<HTMLInputElement>();
  const [searchValue, setSearchValue] = useState<string>('');
  const [isSearchFocused, markSearchFocused, unmarkSearchFocused] = useFlag(false);
  const [isSuggestionsVisible, showSuggestions, hideSuggestions] = useFlag(false);
  const suggestionsTimeoutRef = useRef<number | undefined>(undefined);

  const handleMenuClose = useLastCallback(() => {
    inputRef.current?.blur();
  });

  const safeHideSuggestions = useLastCallback(() => {
    if (isSuggestionsVisible) {
      hideSuggestions();
      resetIndex();
    }
    window.clearTimeout(suggestionsTimeoutRef.current);
  });

  useEffectOnce(() => () => {
    window.clearTimeout(suggestionsTimeoutRef.current);
  });

  const handleOpenSite = useLastCallback((url: string) => {
    void vibrate();
    handleMenuClose();

    // Searching our site catalog to get possible information on how to open it and what its title is
    const site = findSiteByUrl(allSites, url);
    openSite(url, site?.isExternal, site?.name);
  });

  const handleSiteClick = useLastCallback((
    e: React.SyntheticEvent<HTMLDivElement | HTMLAnchorElement>,
    url: string,
  ) => {
    handleOpenSite(url);
  });

  const searchSuggestions = useMemo<SearchSuggestions>(
    () => generateSearchSuggestions(searchValue, browserHistory, sites),
    [browserHistory, searchValue, sites],
  );

  const {
    activeIndex,
    listRef: menuRef,
    resetIndex,
    handleKeyDown,
  } = useKeyboardListNavigation(
    isSuggestionsVisible,
    (index) => {
      const result = [
        ...searchSuggestions.history,
        ...searchSuggestions.sites.map(({ url }) => url),
      ];

      const url = result[index];
      if (url) {
        handleOpenSite(url);
      }
    },
    `.${SUGGESTION_ITEM_CLASS_NAME}`,
  );

  const safeShowSuggestions = useLastCallback(() => {
    if (searchSuggestions.isEmpty) return;

    // Simultaneous opening of the virtual keyboard and display of Saved Addresses causes animation degradation
    if (IS_ANDROID) {
      window.clearTimeout(suggestionsTimeoutRef.current);
      suggestionsTimeoutRef.current = window.setTimeout(showSuggestions, SUGGESTIONS_OPEN_DELAY);
    } else {
      showSuggestions();
    }
  });

  useEffectWithPrevDeps(([prevIsSearchFocused]) => {
    if ((prevIsSearchFocused && !isSearchFocused) || searchSuggestions.isEmpty) {
      safeHideSuggestions();
    }
    if (isSearchFocused && !searchSuggestions.isEmpty) {
      safeShowSuggestions();
    }
  }, [isSearchFocused, searchSuggestions.isEmpty]);

  const handleSiteClear = useLastCallback((e: React.MouseEvent, url: string) => {
    stopEvent(e);

    removeSiteFromBrowserHistory({ url });
  });

  function handleSearchValueChange(e: React.ChangeEvent<HTMLInputElement>) {
    setSearchValue(e.target.value);
  }

  function handleSearchSubmit(e: React.FormEvent<HTMLFormElement>) {
    stopEvent(e);

    handleMenuClose();

    if (searchValue.length > 0) {
      openSite(searchValue);
      setSearchValue('');
    }
  }

  return (
    <div className={buildClassName(styles.searchWrapper, 'with-notch-on-scroll', shouldShowNotch && 'is-scrolled')}>
      <form action="#" onSubmit={handleSearchSubmit} className={styles.searchContainer} autoComplete="off">
        <i className={buildClassName(styles.searchIcon, 'icon-search')} aria-hidden />
        <input
          ref={inputRef}
          name="explore-search"
          className={styles.searchInput}
          placeholder={lang('Search app or enter address')}
          value={searchValue}
          autoCorrect={false}
          autoCapitalize="none"
          spellCheck={false}
          inputMode="url"
          onKeyDown={handleKeyDown}
          onChange={handleSearchValueChange}
          onFocus={markSearchFocused}
          onBlur={unmarkSearchFocused}
        />
      </form>

      <ExploreSearchSuggestions
        menuRef={menuRef}
        isSuggestionsVisible={isSuggestionsVisible}
        searchSuggestions={searchSuggestions}
        searchValue={searchValue}
        activeIndex={activeIndex}
        onSiteClick={handleSiteClick}
        onSiteClear={handleSiteClear}
        onClose={handleMenuClose}
      />
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const { browserHistory } = selectCurrentAccountState(global) || {};
  const { sites: allSites } = global.exploreData || {};

  return { browserHistory, allSites };
})(ExploreSearch));

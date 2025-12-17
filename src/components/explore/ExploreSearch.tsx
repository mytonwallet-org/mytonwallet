import React, {
  memo, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { ApiNetwork, ApiSite } from '../../api/types';
import type { SearchSuggestions, WalletSuggestion } from './helpers/utils';

import { selectCurrentAccountState, selectCurrentNetwork } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { DeeplinkCommand, isSelfDeeplink, processSelfDeeplink } from '../../util/deeplink';
import { stopEvent } from '../../util/domEvents';
import { vibrate } from '../../util/haptics';
import { logDebugError } from '../../util/logs';
import { normalizeUrl } from '../../util/url';
import { IS_ANDROID } from '../../util/windowEnvironment';
import { findSiteByUrl, generateSearchSuggestions, openSite } from './helpers/utils';

import useEffectOnce from '../../hooks/useEffectOnce';
import useEffectWithPrevDeps from '../../hooks/useEffectWithPrevDeps';
import useFlag from '../../hooks/useFlag';
import useKeyboardListNavigation from '../../hooks/useKeyboardListNavigation';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';
import useWalletSuggestions from './hooks/useWalletSuggestions';

import Spinner from '../ui/Spinner';
import ExploreSearchSuggestions, { SUGGESTION_ITEM_CLASS_NAME } from './ExploreSearchSuggestions';

import styles from './Explore.module.scss';

type SuggestionItem =
  | { type: 'history'; value: string }
  | { type: 'site'; value: ApiSite }
  | { type: 'wallet'; value: WalletSuggestion };

interface OwnProps {
  shouldShowNotch: boolean;
  sites: ApiSite[] | undefined;
}

interface StateProps {
  browserHistory?: string[];
  allSites?: ApiSite[];
  network: ApiNetwork;
}

const SUGGESTIONS_OPEN_DELAY = 300;

function ExploreSearch({
  shouldShowNotch,
  sites,
  allSites,
  browserHistory,
  network,
}: OwnProps & StateProps) {
  const { removeSiteFromBrowserHistory, openTemporaryViewAccount } = getActions();

  const lang = useLang();
  const inputRef = useRef<HTMLInputElement>();
  const [searchValue, setSearchValue] = useState<string>('');
  const [isSearchFocused, markSearchFocused, unmarkSearchFocused] = useFlag(false);
  const [isSuggestionsVisible, showSuggestions, hideSuggestions] = useFlag(false);
  const suggestionsTimeoutRef = useRef<number | undefined>(undefined);
  const [walletSuggestions, areWalletSuggestionsLoading] = useWalletSuggestions(network, searchValue);

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

  const { ref: spinnerRef, shouldRender: shouldRenderSpinner } = useShowTransition({
    isOpen: areWalletSuggestionsLoading,
    withShouldRender: true,
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

  const handleWalletSelect = useLastCallback((wallet: WalletSuggestion) => {
    void vibrate();
    handleMenuClose();
    setSearchValue('');

    openTemporaryViewAccount({
      addressByChain: {
        [wallet.chain]: wallet.address,
      },
    });
  });

  const baseSuggestions = useMemo<SearchSuggestions>(
    () => generateSearchSuggestions(searchValue, browserHistory, sites),
    [browserHistory, searchValue, sites],
  );

  const suggestions = useMemo<SearchSuggestions>(() => ({
    ...baseSuggestions,
    wallets: walletSuggestions,
    isEmpty: baseSuggestions.isEmpty && walletSuggestions.length === 0,
  }), [baseSuggestions, walletSuggestions]);

  const {
    activeIndex,
    listRef: menuRef,
    resetIndex,
    handleKeyDown,
  } = useKeyboardListNavigation(
    Boolean(isSuggestionsVisible && !suggestions.isEmpty),
    (index) => {
      const items: SuggestionItem[] = [
        ...suggestions.history.map((historyUrl) => ({ type: 'history', value: historyUrl }) as SuggestionItem),
        ...suggestions.sites.map((site) => ({ type: 'site', value: site }) as SuggestionItem),
        ...suggestions.wallets.map((wallet) => ({ type: 'wallet', value: wallet }) as SuggestionItem),
      ];
      const item = items[index];
      if (!item) return;

      switch (item.type) {
        case 'site':
          handleOpenSite(item.value.url);
          break;
        case 'history':
          handleOpenSite(item.value);
          break;
        case 'wallet':
          handleWalletSelect(item.value);
          break;
      }
    },
    `.${SUGGESTION_ITEM_CLASS_NAME}`,
  );

  const safeShowSuggestions = useLastCallback(() => {
    if (suggestions.isEmpty) return;

    // Simultaneous opening of the virtual keyboard and display of Saved Addresses causes animation degradation
    if (IS_ANDROID) {
      window.clearTimeout(suggestionsTimeoutRef.current);
      suggestionsTimeoutRef.current = window.setTimeout(showSuggestions, SUGGESTIONS_OPEN_DELAY);
    } else {
      showSuggestions();
    }
  });

  useEffectWithPrevDeps(([prevIsSearchFocused]) => {
    if ((prevIsSearchFocused && !isSearchFocused) || suggestions.isEmpty) {
      safeHideSuggestions();
    }
    if (isSearchFocused && !suggestions.isEmpty) {
      safeShowSuggestions();
    }
  }, [isSearchFocused, suggestions.isEmpty]);

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
      const normalizedUrl = normalizeUrl(searchValue);

      // Check if it's a self deeplink with `view` command
      if (isSelfDeeplink(normalizedUrl)) {
        try {
          const url = new URL(normalizedUrl);
          const pathname = url.pathname;
          const command = pathname.split('/').find(Boolean);

          if (command === DeeplinkCommand.View) {
            void processSelfDeeplink(normalizedUrl);
            setSearchValue('');
            return;
          }
        } catch (err: any) {
          logDebugError('[ExploreSearch] handleSearchSubmit', err);
        }
      }

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
        {shouldRenderSpinner && <Spinner ref={spinnerRef} className={styles.spinner} />}
      </form>

      <ExploreSearchSuggestions
        menuRef={menuRef}
        isSuggestionsVisible={isSuggestionsVisible}
        searchSuggestions={suggestions}
        searchValue={searchValue}
        activeIndex={activeIndex}
        onSiteClick={handleSiteClick}
        onSiteClear={handleSiteClear}
        onWalletClick={handleWalletSelect}
        onClose={handleMenuClose}
      />
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const { browserHistory } = selectCurrentAccountState(global) || {};
  const { sites: allSites } = global.exploreData || {};

  return {
    browserHistory,
    allSites,
    network: selectCurrentNetwork(global),
  };
})(ExploreSearch));

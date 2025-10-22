import React, { memo, useMemo } from '../../lib/teact/teact';

import type { ApiSite } from '../../api/types';
import type { SearchSuggestions } from './helpers/utils';

import buildClassName from '../../util/buildClassName';
import { stopEvent } from '../../util/domEvents';
import { getHostnameFromUrl } from '../../util/url';

import useLang from '../../hooks/useLang';

import Menu from '../ui/Menu';
import MenuItem from '../ui/MenuItem';
import Site from './Site';

import styles from './Explore.module.scss';

interface OwnProps {
  isSuggestionsVisible: boolean;
  searchSuggestions: SearchSuggestions;
  searchValue: string;
  onSiteClick: (e: React.SyntheticEvent<HTMLDivElement | HTMLAnchorElement>, url: string) => void;
  onSiteClear: (e: React.MouseEvent, url: string) => void;
  onClose: NoneToVoidFunction;
}

type SearchFactors<L extends number> = number[] & { length: L };

function matchLength(candidate: string, searchValue: string, method: 'startsWith' | 'includes') {
  return candidate.toLowerCase()[method](searchValue.toLowerCase()) ? searchValue.length : 0;
}

function commonPrefixLength(a: ApiSite | string, searchValue: string): SearchFactors<3> {
  if (typeof a === 'string') {
    return [matchLength(a, searchValue, 'startsWith'), 0, 0];
  }
  const maxNameLength = matchLength(a.name, searchValue, 'startsWith');
  const maxDescriptionLength = matchLength(a.description, searchValue, 'startsWith');
  const maxUrlLength = matchLength(a.url, searchValue, 'startsWith');

  return [maxNameLength, maxDescriptionLength, maxUrlLength];
}

function intersectionLength(a: ApiSite | string, searchValue: string): SearchFactors<3> {
  if (typeof a === 'string') {
    return [matchLength(a, searchValue, 'includes'), 0, 0];
  }
  const maxNameLength = matchLength(a.name, searchValue, 'includes');
  const maxDescriptionLength = matchLength(a.description, searchValue, 'includes');
  const maxUrlLength = matchLength(a.url, searchValue, 'includes');

  return [maxNameLength, maxDescriptionLength, maxUrlLength];
}

function searchFactorsOf(candidate: ApiSite | string, searchValue: string): SearchFactors<6> {
  return [
    ...commonPrefixLength(candidate, searchValue),
    ...intersectionLength(candidate, searchValue),
  ] as any;
}

function comparator(factorsA: SearchFactors<6>, factorsB: SearchFactors<6>) {
  for (let i = 0; i < 6; i++) {
    if (factorsA[i] !== factorsB[i]) {
      return factorsB[i] - factorsA[i];
    }
  }

  return 0;
}

function ExploreSearchSuggestions({
  isSuggestionsVisible,
  searchSuggestions: searchSuggestionsProp,
  searchValue,
  onSiteClick,
  onSiteClear,
  onClose,
}: OwnProps) {
  const lang = useLang();

  const searchSuggestions = useMemo(() => {
    const factors = {
      history: searchSuggestionsProp.history?.reduce((acc, url) => {
        acc[url] = searchFactorsOf(url, searchValue);
        return acc;
      }, {} as Record<string, SearchFactors<6>>),
      sites: searchSuggestionsProp.sites?.reduce((acc, site) => {
        acc[site.url] = searchFactorsOf(site, searchValue);
        return acc;
      }, {} as Record<string, SearchFactors<6>>),
    };

    return {
      isEmpty: searchSuggestionsProp.isEmpty,
      sites: [
        ...(searchSuggestionsProp.sites ?? []),
      ].sort((a, b) => comparator(factors.sites![a.url], factors.sites![b.url])),
      history: [
        ...(searchSuggestionsProp.history ?? []),
      ].sort((a, b) => comparator(factors.history![a], factors.history![b])),
    };
  }, [searchSuggestionsProp, searchValue]);

  return (
    <Menu
      type="suggestion"
      noBackdrop
      isOpen={Boolean(isSuggestionsVisible && !searchSuggestions.isEmpty)}
      className={styles.suggestions}
      bubbleClassName={styles.suggestionsMenu}
      onClose={onClose}
    >
      {searchSuggestions?.history?.map((url) => (
        <MenuItem key={`history-${url}`} className={styles.suggestion} onClick={onSiteClick} clickArg={url}>
          <i
            className={buildClassName(styles.suggestionIcon, searchValue.length ? 'icon-search' : 'icon-globe')}
            aria-hidden
          />
          <span className={styles.suggestionAddress}>{getHostnameFromUrl(url)}</span>

          <button
            className={styles.clearSuggestion}
            type="button"
            aria-label={lang('Clear')}
            title={lang('Clear')}
            onMouseDown={(e) => onSiteClear(e, url)}
            onClick={stopEvent}
          >
            <i className="icon-close" aria-hidden />
          </button>
        </MenuItem>
      ))}
      {searchSuggestions?.sites?.map((site) => (
        <Site key={`site-${site.url}-${site.name}`} className={styles.suggestion} site={site} />
      ))}
    </Menu>
  );
}

export default memo(ExploreSearchSuggestions);

import type { ElementRef } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

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
  menuRef: ElementRef<HTMLDivElement>;
  isSuggestionsVisible: boolean;
  searchSuggestions: SearchSuggestions;
  searchValue: string;
  activeIndex: number;
  onSiteClick: (e: React.SyntheticEvent<HTMLDivElement | HTMLAnchorElement>, url: string) => void;
  onSiteClear: (e: React.MouseEvent, url: string) => void;
  onClose: NoneToVoidFunction;
}

export const SUGGESTION_ITEM_CLASS_NAME = styles.suggestion;

function ExploreSearchSuggestions({
  menuRef,
  isSuggestionsVisible,
  searchSuggestions,
  searchValue,
  activeIndex,
  onSiteClick,
  onSiteClear,
  onClose,
}: OwnProps) {
  const lang = useLang();

  const historyLength = searchSuggestions?.history?.length ?? 0;

  return (
    <Menu
      noBackdrop
      isOpen={Boolean(isSuggestionsVisible && !searchSuggestions.isEmpty)}
      type="suggestion"
      role="listbox"
      menuRef={menuRef}
      className={styles.suggestions}
      bubbleClassName={styles.suggestionsMenu}
      onClose={onClose}
    >
      {searchSuggestions?.history?.map((url, index) => {
        const isActive = index === activeIndex;

        return (
          <MenuItem
            key={`history-${url}`}
            className={styles.suggestion}
            role="option"
            isSelected={isActive}
            onClick={onSiteClick}
            clickArg={url}
          >
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
        );
      })}
      {searchSuggestions?.sites?.map((site, index) => {
        const isSelected = historyLength + index === activeIndex;

        return (
          <Site
            key={`site-${site.url}-${site.name}`}
            role="option"
            isSelected={isSelected}
            className={styles.suggestion}
            site={site}
          />
        );
      })}
    </Menu>
  );
}

export default memo(ExploreSearchSuggestions);

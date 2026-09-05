import React, { memo, useMemo, useRef, useState } from '../../lib/teact/teact';

import type { BuildOptions } from './helpers/buildMarketSections';

import buildClassName from '../../util/buildClassName';
import { stopEvent } from '../../util/domEvents';
import { searchTokens } from './helpers/searchTokens';

import useDebouncedValue from '../../hooks/useDebouncedValue';
import useFlag from '../../hooks/useFlag';
import useKeyboardListNavigation from '../../hooks/useKeyboardListNavigation';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import TokenIcon from '../common/TokenIcon';
import Menu from '../ui/Menu';
import MenuItem from '../ui/MenuItem';
import TokenChange from './TokenChange';

import styles from './Market.module.scss';

interface OwnProps {
  buildOptions: BuildOptions;
  onTokenClick: (slug: string) => void;
}

const SEARCH_DEBOUNCE_MS = 200;

function Search({ buildOptions, onTokenClick }: OwnProps) {
  const lang = useLang();
  const inputRef = useRef<HTMLInputElement>();
  const [searchValue, setSearchValue] = useState('');
  const [isFocused, markFocused, unmarkFocused] = useFlag(false);

  const debouncedSearchValue = useDebouncedValue(searchValue, SEARCH_DEBOUNCE_MS);

  const results = useMemo(
    () => searchTokens(lang, debouncedSearchValue, buildOptions),
    [buildOptions, debouncedSearchValue, lang],
  );

  const isMenuOpen = isFocused && results.length > 0;

  const handleSelect = useLastCallback((slug: string) => {
    setSearchValue('');
    inputRef.current?.blur();
    onTokenClick(slug);
  });

  const {
    activeIndex,
    listRef,
    handleKeyDown,
  } = useKeyboardListNavigation(isMenuOpen, (index) => {
    const token = results[index];
    if (token) {
      handleSelect(token.slug);
    }
  }, `.${styles.suggestion}`);

  const handleItemClick = useLastCallback((
    e: React.SyntheticEvent<HTMLDivElement | HTMLAnchorElement>,
    slug: string,
  ) => {
    handleSelect(slug);
  });

  const handleClose = useLastCallback(() => {
    inputRef.current?.blur();
  });

  function handleChange(e: React.ChangeEvent<HTMLInputElement>) {
    setSearchValue(e.target.value);
  }

  return (
    <div className={styles.searchWrapper}>
      <form action="#" className={styles.searchContainer} autoComplete="off" onSubmit={stopEvent}>
        <i className={buildClassName(styles.searchIcon, 'icon-search')} aria-hidden />
        <input
          ref={inputRef}
          name="market-search"
          className={styles.searchInput}
          placeholder={lang('Search token or stock')}
          value={searchValue}
          autoCorrect={false}
          autoCapitalize="none"
          spellCheck={false}
          onKeyDown={handleKeyDown}
          onChange={handleChange}
          onFocus={markFocused}
          onBlur={unmarkFocused}
        />
      </form>

      <Menu
        noBackdrop
        isOpen={isMenuOpen}
        type="suggestion"
        role="listbox"
        menuRef={listRef}
        className={styles.suggestions}
        bubbleClassName={styles.suggestionsMenu}
        onClose={handleClose}
      >
        {results.map((token, index) => (
          <MenuItem<string>
            key={token.slug}
            className={styles.suggestion}
            role="option"
            isSelected={index === activeIndex}
            clickArg={token.slug}
            onClick={handleItemClick}
          >
            <TokenIcon token={token.token} size="middle" withChainIcon className={styles.suggestionIcon} />
            <span className={styles.suggestionName}>{token.name}</span>
            <span className={styles.suggestionPrice}>
              {token.priceText}
              <TokenChange change={token.change} />
            </span>
          </MenuItem>
        ))}
      </Menu>
    </div>
  );
}

export default memo(Search);

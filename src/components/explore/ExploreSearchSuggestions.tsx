import type { ElementRef } from '../../lib/teact/teact';
import React, { memo } from '../../lib/teact/teact';

import type { SearchSuggestions, WalletSuggestion } from './helpers/utils';

import buildClassName from '../../util/buildClassName';
import { stopEvent } from '../../util/domEvents';
import { shortenAddress } from '../../util/shortenAddress';
import { getHostnameFromUrl } from '../../util/url';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Menu from '../ui/Menu';
import MenuItem from '../ui/MenuItem';
import WalletAvatar from '../ui/WalletAvatar';
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
  onWalletClick: (wallet: WalletSuggestion) => void;
}

export const SUGGESTION_ITEM_CLASS_NAME = styles.suggestion;

function ExploreSearchSuggestions({
  menuRef,
  isSuggestionsVisible,
  searchSuggestions,
  searchValue,
  activeIndex,
  onWalletClick,
  onSiteClick,
  onSiteClear,
  onClose,
}: OwnProps) {
  const lang = useLang();

  const historyLength = searchSuggestions?.history?.length ?? 0;
  const sitesLength = searchSuggestions?.sites?.length ?? 0;
  const handleWalletClick = useLastCallback((
    e: React.SyntheticEvent<HTMLDivElement | HTMLAnchorElement>,
    wallet: WalletSuggestion,
  ) => {
    onWalletClick(wallet);
  });

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
          <MenuItem<string>
            key={`history-${url}`}
            className={buildClassName(styles.suggestion, styles.suggestionWithSeparator)}
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
      {searchSuggestions?.wallets?.map((wallet, index) => {
        const walletIndex = historyLength + sitesLength + index;
        const isSelected = walletIndex === activeIndex;
        const { address, chain, title: walletTitle } = wallet;
        const shortenedAddress = shortenAddress(address)!;
        const title = walletTitle ?? shortenedAddress;
        const description = walletTitle ? shortenedAddress : undefined;

        return (
          <MenuItem<WalletSuggestion>
            key={`wallet-${chain}-${address}-${walletTitle ?? ''}`}
            className={buildClassName(
              styles.suggestion,
              styles.suggestionWithSeparator,
              index === 0 && sitesLength + historyLength > 0 && styles.suggestionWithSeparatorFullWidth,
            )}
            role="option"
            isSelected={isSelected}
            onClick={handleWalletClick}
            clickArg={wallet}
          >
            <div className={styles.walletSuggestion}>
              <WalletAvatar title={title} className={styles.walletSuggestionAvatar} />
              <div className={styles.walletSuggestionInfo}>
                <span className={styles.walletSuggestionTitle}>{title}</span>
                {description && <span className={styles.walletSuggestionSubtitle}>{description}</span>}
              </div>
            </div>
          </MenuItem>
        );
      })}
    </Menu>
  );
}

export default memo(ExploreSearchSuggestions);

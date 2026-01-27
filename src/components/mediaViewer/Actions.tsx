import React, { memo, useMemo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import type { ApiNft } from '../../api/types';
import type { NftMenuHandler } from './hooks/useNftMenu';
import { MediaType } from '../../global/types';

import {
  selectCurrentAccountSettings,
  selectCurrentAccountState,
  selectIsCurrentAccountViewMode,
  selectTonDnsLinkedAddress,
} from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { getCountDaysToDate } from '../../util/dateFormat';
import { getDnsExpirationDate } from '../../util/dns';

import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import { usePrevDuringAnimationSimple } from '../../hooks/usePrevDuringAnimationSimple';
import useNftMenu from './hooks/useNftMenu';

import DropdownMenu from '../ui/DropdownMenu';
import { ANIMATION_DURATION } from '../ui/Menu';

import styles from './MediaViewer.module.scss';

type OwnProps = {
  mediaId?: string;
  onClose: NoneToVoidFunction;
};

type StateProps = {
  nft?: ApiNft;
  tonDnsExpiration?: number;
  linkedAddress?: string;
  blacklistedNftAddresses?: string[];
  whitelistedNftAddresses?: string[];
  cardBackgroundNft?: ApiNft;
  accentColorNft?: ApiNft;
  isViewMode: boolean;
  isTestnet?: boolean;
};

const SHOULD_CLOSE_VIEWER_HANDLERS: NftMenuHandler[] = [
  'send',
  'renew',
  'burn',
  'collection',
  'select',
  'linkDomain',
];

function Actions({
  nft,
  tonDnsExpiration,
  linkedAddress,
  blacklistedNftAddresses,
  whitelistedNftAddresses,
  cardBackgroundNft,
  accentColorNft,
  isViewMode,
  isTestnet,
  onClose,
}: StateProps & OwnProps) {
  const lang = useLang();
  const [isMenuOpen, openMenu, closeMenu] = useFlag();

  const dnsExpireInDays = tonDnsExpiration ? getCountDaysToDate(tonDnsExpiration) : undefined;
  const isNftBlacklisted = useMemo(() => {
    return blacklistedNftAddresses?.includes(nft!.address);
  }, [nft, blacklistedNftAddresses]);
  const isNftWhitelisted = useMemo(() => {
    return whitelistedNftAddresses?.includes(nft!.address);
  }, [nft, whitelistedNftAddresses]);
  const isNftInstalled = usePrevDuringAnimationSimple(
    nft && nft.address === cardBackgroundNft?.address, ANIMATION_DURATION,
  );
  const isNftAccentColorInstalled = usePrevDuringAnimationSimple(
    nft && nft.address === accentColorNft?.address, ANIMATION_DURATION,
  );

  const { menuItems, handleMenuItemSelect } = useNftMenu({
    nft,
    isViewMode,
    dnsExpireInDays,
    linkedAddress,
    isNftBlacklisted,
    isNftWhitelisted,
    isNftInstalled,
    isNftAccentColorInstalled,
    isTestnet,
  });

  const handleSelect = useLastCallback((value: NftMenuHandler) => {
    if (SHOULD_CLOSE_VIEWER_HANDLERS.includes(value)) {
      onClose();
    }

    handleMenuItemSelect(value);
  });

  return (
    <div className={styles.actions}>
      <button
        type="button"
        aria-label={lang('More actions')}
        className={buildClassName(styles.actionButton, styles.menuButton, isMenuOpen && styles.menuButton_active)}
        onClick={openMenu}
      >
        <i className="icon icon-more" aria-hidden />
      </button>
      <DropdownMenu
        isOpen={isMenuOpen}
        items={menuItems}
        menuPositionY="top"
        menuPositionX="right"
        shouldTranslateOptions
        onClose={closeMenu}
        className="component-theme-dark"
        buttonClassName={styles.menuItem}
        onSelect={handleSelect}
      />

      <button
        type="button"
        aria-label={lang('Close')}
        className={styles.actionButton}
        onClick={onClose}
      >
        <i className={buildClassName('icon-windows-close', styles.actionIcon)} aria-hidden />
      </button>
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global, { mediaId }): StateProps => {
  const { mediaType = MediaType.Nft } = global.mediaViewer || {};
  const isViewMode = selectIsCurrentAccountViewMode(global);

  if (!mediaId || mediaType !== MediaType.Nft) return { isViewMode };

  const { byAddress, dnsExpiration } = selectCurrentAccountState(global)?.nfts || {};
  const nft = byAddress?.[mediaId];
  if (!nft) return { isViewMode };

  const { blacklistedNftAddresses, whitelistedNftAddresses } = selectCurrentAccountState(global) || {};
  const { cardBackgroundNft, accentColorNft } = selectCurrentAccountSettings(global) || {};
  const tonDnsExpiration = getDnsExpirationDate(nft, dnsExpiration);
  const linkedAddress = selectTonDnsLinkedAddress(global, nft);

  return {
    nft,
    tonDnsExpiration,
    blacklistedNftAddresses,
    whitelistedNftAddresses,
    cardBackgroundNft,
    accentColorNft,
    isViewMode,
    isTestnet: global.settings.isTestnet,
    linkedAddress,
  };
})(Actions));

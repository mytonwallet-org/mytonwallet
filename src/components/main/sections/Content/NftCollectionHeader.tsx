import React, { memo, useEffect, useMemo, useRef, useState } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiNft } from '../../../../api/types';
import type { IAnchorPosition } from '../../../../global/types';
import type { DropdownItem } from '../../../ui/Dropdown';

import {
  GETGEMS_BASE_MAINNET_URL,
  GETGEMS_BASE_TESTNET_URL,
  IS_CORE_WALLET,
  NFT_FRAGMENT_COLLECTIONS,
  RENEWABLE_TON_DNS_COLLECTIONS,
  TELEGRAM_GIFTS_SUPER_COLLECTION,
} from '../../../../config';
import { selectCurrentAccountState, selectIsCurrentAccountViewMode } from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import captureEscKeyListener from '../../../../util/captureEscKeyListener';
import { getCountDaysToDate } from '../../../../util/dateFormat';
import { getDomainsExpirationDate } from '../../../../util/dns';
import { compact } from '../../../../util/iteratees';
import { openUrl } from '../../../../util/openUrl';
import { getExplorerName, getExplorerNftCollectionUrl } from '../../../../util/url';

import { getIsPortrait } from '../../../../hooks/useDeviceScreen';
import useHistoryBack from '../../../../hooks/useHistoryBack';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';

import Button from '../../../ui/Button';
import DropdownMenu from '../../../ui/DropdownMenu';

import styles from './NftCollectionHeader.module.scss';

type MenuHandler = 'sendAll' | 'fragment' | 'getgems' | 'tonExplorer' | 'hideAll' | 'burnAll' | 'selectAll'
  | 'removeTab' | 'addTab' | 'renew';

interface StateProps {
  currentCollectionAddress?: string;
  nfts?: Record<string, ApiNft>;
  isTestnet?: boolean;
  isViewMode?: boolean;
  collectionTabs?: string[];
  dnsExpiration?: Record<string, number>;
}

function NftCollectionHeader({
  currentCollectionAddress,
  nfts,
  isTestnet,
  isViewMode,
  collectionTabs,
  dnsExpiration,
}: StateProps) {
  const {
    closeNftCollection,
    selectNfts,
    startTransfer,
    burnNfts,
    openHideNftModal,
    addCollectionTab,
    removeCollectionTab,
    openDomainRenewalModal,
  } = getActions();

  const lang = useLang();
  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition>();
  const isMenuOpen = Boolean(menuAnchor);
  const ref = useRef<HTMLButtonElement>();
  const menuRef = useRef<HTMLDivElement>();

  const isTelegramGifts = currentCollectionAddress === TELEGRAM_GIFTS_SUPER_COLLECTION;

  const collectionNfts = useMemo(() => {
    if (!currentCollectionAddress || !nfts) {
      return [];
    }

    return Object.values(nfts).filter((nft) => {
      return (isTelegramGifts && nft.isTelegramGift) || nft.collectionAddress === currentCollectionAddress;
    });
  }, [currentCollectionAddress, isTelegramGifts, nfts]);

  const dnsExpireInDays = useMemo(() => {
    if (!RENEWABLE_TON_DNS_COLLECTIONS.has(currentCollectionAddress!)) return undefined;
    const date = getDomainsExpirationDate(collectionNfts, undefined, dnsExpiration);

    return date ? getCountDaysToDate(date) : undefined;
  }, [collectionNfts, currentCollectionAddress, dnsExpiration]);

  const collectionName = isTelegramGifts
    ? lang('Telegram Gifts')
    : collectionNfts[0]?.collectionName ?? lang('Unnamed Collection');

  const menuItems: DropdownItem<MenuHandler>[] = useMemo(() => {
    const isInTabs = collectionTabs?.includes(currentCollectionAddress!);

    return compact([
      !isViewMode && {
        name: 'Send All',
        value: 'sendAll',
      } satisfies DropdownItem<MenuHandler>,
      collectionNfts[0]?.isOnFragment && {
        name: 'Fragment',
        value: 'fragment',
        fontIcon: 'external',
      } satisfies DropdownItem<MenuHandler>,
      {
        name: 'Getgems',
        value: 'getgems',
        fontIcon: 'external',
      },
      !isTelegramGifts && {
        name: getExplorerName('ton'),
        value: 'tonExplorer',
        fontIcon: 'external',
      },
      !isViewMode && RENEWABLE_TON_DNS_COLLECTIONS.has(currentCollectionAddress!) && {
        name: collectionNfts.length > 1 ? 'Renew All' : 'Renew',
        value: 'renew',
        description: dnsExpireInDays && dnsExpireInDays < 0
          ? (collectionNfts.length > 1 ? '$expired_many' : 'Expired')
          : lang('$expires_in %days%', {
            days: lang('$in_days', dnsExpireInDays),
          }, undefined, collectionNfts.length) as string,
      } satisfies DropdownItem<MenuHandler>,
      !IS_CORE_WALLET && {
        name: 'Hide All',
        value: 'hideAll',
      } satisfies DropdownItem<MenuHandler>,
      !isViewMode && {
        name: 'Burn All',
        value: 'burnAll',
        isDangerous: true,
      } satisfies DropdownItem<MenuHandler>, {
        name: 'Select All',
        value: 'selectAll',
        withDelimiter: true,
      },
      {
        name: isInTabs ? lang('Remove Tab') : lang('Add Tab'),
        value: isInTabs ? 'removeTab' : 'addTab',
      },
    ]);
  }, [collectionNfts, collectionTabs, currentCollectionAddress, dnsExpireInDays, isTelegramGifts, isViewMode, lang]);

  useHistoryBack({
    isActive: true,
    onBack: closeNftCollection,
  });

  useEffect(() => captureEscKeyListener(closeNftCollection), []);

  const getTriggerElement = useLastCallback(() => ref.current);
  const getRootElement = useLastCallback(() => document.body);
  const getMenuElement = useLastCallback(() => menuRef.current);
  const getLayout = useLastCallback(() => ({ withPortal: true }));

  const handleMenuItemClick = useLastCallback((value: MenuHandler) => {
    switch (value) {
      case 'sendAll': {
        startTransfer({
          nfts: collectionNfts.filter(({ isOnSale }) => !isOnSale),
          isPortrait: getIsPortrait(),
        });

        break;
      }

      case 'getgems': {
        const getgemsBaseUrl = isTestnet ? GETGEMS_BASE_TESTNET_URL : GETGEMS_BASE_MAINNET_URL;
        void openUrl(
          isTelegramGifts ? `${getgemsBaseUrl}top-gifts` : `${getgemsBaseUrl}collection/${currentCollectionAddress}`,
        );

        break;
      }

      case 'tonExplorer': {
        const url = getExplorerNftCollectionUrl(currentCollectionAddress, isTestnet);
        if (url) {
          void openUrl(url);
        }

        break;
      }

      case 'fragment': {
        if (isTelegramGifts) {
          void openUrl('https://fragment.com/gifts');
        } else if (currentCollectionAddress === NFT_FRAGMENT_COLLECTIONS[0]) {
          void openUrl('https://fragment.com/numbers');
        } else if (currentCollectionAddress === NFT_FRAGMENT_COLLECTIONS[1]) {
          void openUrl('https://fragment.com');
        } else {
          const collectionSlug = collectionName.toLowerCase().replace(/\W/g, '').replace(/s$/, '');
          void openUrl(`https://fragment.com/gifts/${collectionSlug}`);
        }

        break;
      }

      case 'selectAll': {
        selectNfts({
          addresses: collectionNfts
            .filter(({ isOnSale }) => !isOnSale)
            .map(({ address }) => address),
        });

        break;
      }

      case 'burnAll': {
        burnNfts({ nfts: collectionNfts.filter(({ isOnSale }) => !isOnSale) });

        break;
      }

      case 'hideAll': {
        openHideNftModal({ addresses: collectionNfts.map((nft) => nft.address), isCollection: true });

        break;
      }

      case 'addTab': {
        addCollectionTab({ collectionAddress: currentCollectionAddress! });

        break;
      }

      case 'removeTab': {
        closeNftCollection();
        removeCollectionTab({ collectionAddress: currentCollectionAddress! });

        break;
      }

      case 'renew': {
        openDomainRenewalModal({ addresses: collectionNfts.map((nft) => nft.address) });
        break;
      }
    }
  });

  const handleMenuOpen = useLastCallback(() => {
    const { right: x, bottom: y } = ref.current!.getBoundingClientRect();
    setMenuAnchor({ x, y });
  });

  const handleMenuClose = useLastCallback(() => {
    setMenuAnchor(undefined);
  });

  return (
    <div className={styles.root}>
      <Button
        isSimple
        isText
        ariaLabel={lang('Back')}
        className={styles.backButton}
        onClick={closeNftCollection}
      >
        <i className={buildClassName(styles.backIcon, 'icon-chevron-left')} aria-hidden />
      </Button>

      <div className={styles.content}>
        <div className={styles.title}>{collectionName}</div>
        <div className={styles.amount}>
          {collectionNfts.length > 1 ? lang('%amount% NFTs', { amount: collectionNfts.length }) : lang('1 NFT')}
        </div>
      </div>

      <Button isSimple ref={ref} className={styles.menuButton} onClick={handleMenuOpen} ariaLabel={lang('Open Menu')}>
        <i className="icon-menu-dots" aria-hidden />
      </Button>
      <DropdownMenu
        isOpen={isMenuOpen}
        ref={menuRef}
        withPortal
        shouldTranslateOptions
        menuPositionX="right"
        menuAnchor={menuAnchor}
        getTriggerElement={getTriggerElement}
        getRootElement={getRootElement}
        getMenuElement={getMenuElement}
        getLayout={getLayout}
        buttonClassName={styles.menuItem}
        bubbleClassName={styles.menu}
        itemDescriptionClassName={styles.menuItemDescription}
        items={menuItems}
        onSelect={handleMenuItemClick}
        onClose={handleMenuClose}
      />
    </div>
  );
}

export default memo(withGlobal((global): StateProps => {
  const {
    byAddress: nfts,
    currentCollectionAddress,
    collectionTabs,
    dnsExpiration,
  } = selectCurrentAccountState(global)?.nfts || {};

  return {
    currentCollectionAddress,
    nfts,
    isTestnet: global.settings.isTestnet,
    isViewMode: selectIsCurrentAccountViewMode(global),
    collectionTabs,
    dnsExpiration,
  };
}, (global, ownProps, stickToFirst) => {
  const {
    currentCollectionAddress,
  } = selectCurrentAccountState(global)?.nfts || {};

  return stickToFirst(currentCollectionAddress);
})(NftCollectionHeader));

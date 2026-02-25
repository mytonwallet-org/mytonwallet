import React, { memo, useEffect, useMemo, useRef, useState } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiChain, ApiNft, ApiNftCollection } from '../../../../api/types';
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
import {
  getExplorerName,
  getExplorerNftCollectionUrl,
  getMarketplaceName,
  getMarketplaceNftCollectionUrl,
} from '../../../../util/url';

import { getIsPortrait } from '../../../../hooks/useDeviceScreen';
import useHistoryBack from '../../../../hooks/useHistoryBack';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';

import Button from '../../../ui/Button';
import DropdownMenu from '../../../ui/DropdownMenu';

import styles from './NftCollectionHeader.module.scss';

type MenuHandler = 'sendAll' | 'fragment' | 'marketplace' | 'explorer' | 'hideAll' | 'burnAll' | 'selectAll'
  | 'removeTab' | 'addTab' | 'renew';

interface StateProps {
  currentCollection?: ApiNftCollection;
  nfts?: Record<string, ApiNft>;
  isTestnet?: boolean;
  isViewMode?: boolean;
  collectionTabs?: ApiNftCollection[];
  dnsExpiration?: Record<string, number>;
  selectedExplorerIds?: Partial<Record<ApiChain, string>>;
}

function NftCollectionHeader({
  currentCollection,
  nfts,
  isTestnet,
  isViewMode,
  collectionTabs,
  dnsExpiration,
  selectedExplorerIds,
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

  const isTelegramGifts = currentCollection?.address === TELEGRAM_GIFTS_SUPER_COLLECTION;

  const collectionNfts = useMemo(() => {
    if (!currentCollection || !nfts) {
      return [];
    }

    return Object.values(nfts).filter((nft) => {
      return (isTelegramGifts && nft.isTelegramGift)
        || (nft.collectionAddress === currentCollection.address
          && nft.chain === currentCollection.chain);
    });
  }, [currentCollection, isTelegramGifts, nfts]);

  const dnsExpireInDays = useMemo(() => {
    if (!RENEWABLE_TON_DNS_COLLECTIONS.has(currentCollection?.address || '')) return undefined;
    const date = getDomainsExpirationDate(collectionNfts, undefined, dnsExpiration);

    return date ? getCountDaysToDate(date) : undefined;
  }, [collectionNfts, currentCollection, dnsExpiration]);

  const collectionName = isTelegramGifts
    ? lang('Telegram Gifts')
    : collectionNfts?.[0]?.collectionName ?? lang('Unnamed Collection');

  const menuItems: DropdownItem<MenuHandler>[] = useMemo(() => {
    const isInTabs = currentCollection && collectionTabs?.some((e) =>
      e.address === currentCollection.address && e.chain === currentCollection.chain,
    );

    return compact([
      !isViewMode && {
        name: 'Send All',
        value: 'sendAll',
      } satisfies DropdownItem<MenuHandler>,
      collectionNfts?.[0]?.isOnFragment && {
        name: 'Fragment',
        value: 'fragment',
        fontIcon: 'external',
      } satisfies DropdownItem<MenuHandler>,
      getMarketplaceNftCollectionUrl(currentCollection?.chain, currentCollection?.address) && {
        name: getMarketplaceName(currentCollection?.chain, currentCollection?.address),
        value: 'marketplace',
        fontIcon: 'external',
      },
      !isTelegramGifts && {
        name: getExplorerName(currentCollection?.chain),
        value: 'explorer',
        fontIcon: 'external',
      },
      !isViewMode && currentCollection && RENEWABLE_TON_DNS_COLLECTIONS.has(currentCollection.address) && {
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
  }, [collectionNfts, collectionTabs, currentCollection, dnsExpireInDays, isTelegramGifts, isViewMode, lang]);

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

      case 'marketplace': {
        if (isTelegramGifts) {
          const getgemsBaseUrl = isTestnet ? GETGEMS_BASE_TESTNET_URL : GETGEMS_BASE_MAINNET_URL;
          void openUrl(`${getgemsBaseUrl}top-gifts`);
          break;
        }
        const url = getMarketplaceNftCollectionUrl(
          currentCollection?.chain,
          currentCollection?.address,
          isTestnet,
          selectedExplorerIds?.ton,
        );
        if (url) {
          void openUrl(url);
        }

        break;
      }

      case 'explorer': {
        const url = getExplorerNftCollectionUrl(
          currentCollection?.chain,
          currentCollection?.address,
          isTestnet,
          selectedExplorerIds?.ton,
        );
        if (url) {
          void openUrl(url);
        }

        break;
      }

      case 'fragment': {
        if (isTelegramGifts) {
          void openUrl('https://fragment.com/gifts');
        } else if (currentCollection?.address === NFT_FRAGMENT_COLLECTIONS[0]) {
          void openUrl('https://fragment.com/numbers');
        } else if (currentCollection?.address === NFT_FRAGMENT_COLLECTIONS[1]) {
          void openUrl('https://fragment.com');
        } else {
          const collectionSlug = collectionName.toLowerCase().replace(/\W/g, '').replace(/s$/, '');
          void openUrl(`https://fragment.com/gifts/${collectionSlug}`);
        }

        break;
      }

      case 'selectAll': {
        selectNfts({
          nfts: collectionNfts
            .filter(({ isOnSale }) => !isOnSale),
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
        addCollectionTab({ collection: currentCollection! });

        break;
      }

      case 'removeTab': {
        closeNftCollection();
        removeCollectionTab({ collection: currentCollection! });

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
    currentCollection,
    collectionTabs,
    dnsExpiration,
  } = selectCurrentAccountState(global)?.nfts || {};

  return {
    currentCollection,
    nfts,
    isTestnet: global.settings.isTestnet,
    isViewMode: selectIsCurrentAccountViewMode(global),
    collectionTabs,
    dnsExpiration,
    selectedExplorerIds: global.settings.selectedExplorerIds,
  };
}, (global, ownProps, stickToFirst) => {
  const {
    currentCollection,
  } = selectCurrentAccountState(global)?.nfts || {};

  return stickToFirst(currentCollection?.address);
})(NftCollectionHeader));

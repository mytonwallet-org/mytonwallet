import React, { memo, useEffect, useMemo, useRef, useState } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiChain, ApiNft, ApiNftCollection, ApiUpdateNfts } from '../../../../api/types';
import type { IAnchorPosition } from '../../../../global/types';
import type { DropdownItem } from '../../../ui/Dropdown';

import {
  GETGEMS_BASE_MAINNET_URL,
  GETGEMS_BASE_TESTNET_URL,
  NFT_FRAGMENT_COLLECTIONS,
  RENEWABLE_TON_DNS_COLLECTIONS,
  TELEGRAM_GIFTS_SUPER_COLLECTION,
} from '../../../../config';
import { getIsNftVisible } from '../../../../global/helpers/nfts';
import { buildTelegramGiftCatalog } from '../../../../global/helpers/telegramGiftCatalog';
import { selectCurrentAccountState, selectIsCurrentAccountViewMode } from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import captureEscKeyListener from '../../../../util/captureEscKeyListener';
import { formatRelativeDays, getCountDaysToDate } from '../../../../util/dateFormat';
import { getDomainsExpirationDate } from '../../../../util/dns';
import { compact } from '../../../../util/iteratees';
import { openUrl } from '../../../../util/openUrl';
import {
  getExplorerName,
  getExplorerNftCollectionUrl,
  getMarketplaceName,
  getMarketplaceNftCollectionUrl,
} from '../../../../util/url';

import useHistoryBack from '../../../../hooks/useHistoryBack';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';

import Button from '../../../ui/Button';
import DropdownMenu from '../../../ui/DropdownMenu';

import styles from './NftCollectionHeader.module.scss';

type MenuHandler = 'sendAll' | 'fragment' | 'marketplace' | 'explorer' | 'hideAll' | 'burnAll' | 'selectAll'
  | 'removeTab' | 'addTab' | 'renew';

interface OwnProps {
  collection: ApiNftCollection;
}

interface StateProps {
  blacklistedNftAddresses?: string[];
  whitelistedNftAddresses?: string[];
  areUnverifiedNftsHidden?: boolean;
  tonInventoryStatus?: ApiUpdateNfts['inventoryStatus'];
  nfts?: Record<string, ApiNft>;
  isTestnet?: boolean;
  isViewMode?: boolean;
  collectionTabs?: ApiNftCollection[];
  dnsExpiration?: Record<string, number>;
  selectedExplorerIds?: Partial<Record<ApiChain, string>>;
}

function NftCollectionHeader({
  collection,
  nfts,
  isTestnet,
  isViewMode,
  collectionTabs,
  dnsExpiration,
  selectedExplorerIds,
  tonInventoryStatus,
  blacklistedNftAddresses,
  whitelistedNftAddresses,
  areUnverifiedNftsHidden,
}: OwnProps & StateProps) {
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

  const isTelegramGifts = collection.address === TELEGRAM_GIFTS_SUPER_COLLECTION;

  const collectionNfts = useMemo(() => {
    if (!nfts) {
      return [];
    }

    return Object.values(nfts).filter((nft) => {
      return (isTelegramGifts && nft.isTelegramGift)
        || (nft.collectionAddress === collection.address
          && nft.chain === collection.chain);
    });
  }, [collection, isTelegramGifts, nfts]);

  const isGiftCollection = collection.chain === 'ton' && collectionNfts.some((nft) => nft.isTelegramGift);
  const isGiftCountPending = collection.chain === 'ton'
    && (isTelegramGifts || isGiftCollection)
    && tonInventoryStatus !== 'complete';

  const giftCollectionName = useMemo(() => {
    if (isTelegramGifts || !isGiftCollection) return undefined;
    const blacklisted = new Set(blacklistedNftAddresses);
    const whitelisted = new Set(whitelistedNftAddresses);
    const visible = new Set(collectionNfts.filter((nft) => (
      getIsNftVisible(nft, blacklisted, whitelisted, areUnverifiedNftsHidden)
    )).map((nft) => nft.address));
    return buildTelegramGiftCatalog(collectionNfts, visible).collections[0]?.name;
  }, [isTelegramGifts, isGiftCollection, collectionNfts,
    blacklistedNftAddresses, whitelistedNftAddresses, areUnverifiedNftsHidden]);

  const dnsExpireInDays = useMemo(() => {
    if (!RENEWABLE_TON_DNS_COLLECTIONS.has(collection.address)) return undefined;
    const date = getDomainsExpirationDate(collectionNfts, undefined, dnsExpiration);

    return date ? getCountDaysToDate(date) : undefined;
  }, [collectionNfts, collection, dnsExpiration]);

  const collectionName = isTelegramGifts
    ? lang('Telegram Gifts')
    : (isGiftCollection ? giftCollectionName : collectionNfts?.[0]?.collectionName) || lang('Unnamed Collection');

  const selectedExplorerId = selectedExplorerIds?.[collection.chain];

  const menuItems: DropdownItem<MenuHandler>[] = useMemo(() => {
    const isInTabs = collectionTabs?.some((e) =>
      e.address === collection.address && e.chain === collection.chain,
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
      getMarketplaceNftCollectionUrl(collection.chain, collection.address) && {
        name: getMarketplaceName(collection.chain),
        value: 'marketplace',
        fontIcon: 'external',
      },
      !isTelegramGifts && {
        name: getExplorerName(collection.chain, selectedExplorerId),
        value: 'explorer',
        fontIcon: 'external',
      },
      !isViewMode && RENEWABLE_TON_DNS_COLLECTIONS.has(collection.address) && {
        name: collectionNfts.length > 1 ? 'Renew All' : 'Renew',
        value: 'renew',
        description: dnsExpireInDays && dnsExpireInDays < 0
          ? (collectionNfts.length > 1 ? '$expired_many' : 'Expired')
          : lang(collectionNfts.length > 1 ? '$multiple_domains_expire %days%' : '$one_domain_expires %days%', {
            days: formatRelativeDays(lang, dnsExpireInDays!),
          }) as string,
      } satisfies DropdownItem<MenuHandler>,
      {
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
  }, [
    collectionNfts, collectionTabs, collection, dnsExpireInDays, isTelegramGifts, isViewMode, lang, selectedExplorerId,
  ]);

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
          collection.chain,
          collection.address,
          isTestnet,
        );
        if (url) {
          void openUrl(url);
        }

        break;
      }

      case 'explorer': {
        const url = getExplorerNftCollectionUrl(
          collection.chain,
          collection.address,
          isTestnet,
          selectedExplorerId,
        );
        if (url) {
          void openUrl(url);
        }

        break;
      }

      case 'fragment': {
        if (isTelegramGifts) {
          void openUrl('https://fragment.com/gifts');
        } else if (collection.address === NFT_FRAGMENT_COLLECTIONS[0]) {
          void openUrl('https://fragment.com/numbers');
        } else if (collection.address === NFT_FRAGMENT_COLLECTIONS[1]) {
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
        addCollectionTab({ collection });

        break;
      }

      case 'removeTab': {
        closeNftCollection();
        removeCollectionTab({ collection });

        break;
      }

      case 'renew': {
        openDomainRenewalModal({ addresses: collectionNfts.map((nft) => nft.address) });
        break;
      }
    }
  });

  const handleMenuOpen = useLastCallback(() => {
    const { left, right, bottom: y } = ref.current!.getBoundingClientRect();
    // RTL: mirror the anchor edge
    const x = lang.isRtl ? left : right;
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
          {isGiftCountPending ? '…' : lang('%amount% NFTs', collectionNfts.length, 'i')}
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

export default memo(withGlobal<OwnProps>((global): StateProps => {
  const {
    byAddress: nfts,
    collectionTabs,
    dnsExpiration,
    inventoryStatusByChain,
  } = selectCurrentAccountState(global)?.nfts || {};
  const { blacklistedNftAddresses, whitelistedNftAddresses } = selectCurrentAccountState(global) || {};

  return {
    blacklistedNftAddresses,
    whitelistedNftAddresses,
    areUnverifiedNftsHidden: global.settings.areUnverifiedNftsHidden,
    nfts,
    tonInventoryStatus: inventoryStatusByChain?.ton,
    isTestnet: global.settings.isTestnet,
    isViewMode: selectIsCurrentAccountViewMode(global),
    collectionTabs,
    dnsExpiration,
    selectedExplorerIds: global.settings.selectedExplorerIds,
  };
})(NftCollectionHeader));

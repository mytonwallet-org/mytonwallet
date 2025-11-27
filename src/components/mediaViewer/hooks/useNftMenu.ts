import type React from '../../../lib/teact/teact';
import { useMemo } from '../../../lib/teact/teact';
import { getActions, getGlobal } from '../../../global';

import type { ApiNft } from '../../../api/types';
import type { DropdownItem } from '../../ui/Dropdown';

import {
  GETGEMS_BASE_MAINNET_URL,
  GETGEMS_BASE_TESTNET_URL,
  IS_CORE_WALLET,
  MTW_CARDS_COLLECTION,
} from '../../../config';
import { isDotTonDomainNft, isLinkableDnsNft, isRenewableDnsNft } from '../../../util/dns';
import { compact } from '../../../util/iteratees';
import { openUrl } from '../../../util/openUrl';
import { getExplorerName, getExplorerNftUrl } from '../../../util/url';

import { getIsPortrait } from '../../../hooks/useDeviceScreen';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

export type NftMenuHandler = 'send' | 'tondns' | 'fragment' | 'getgems' | 'tonExplorer' | 'collection' | 'hide'
  | 'unhide' | 'not_scam' | 'burn' | 'select' | 'installCard' | 'resetCard' | 'installAccentColor' | 'resetAccentColor'
  | 'renew' | 'linkDomain';

const ON_SALE_ITEM: DropdownItem<NftMenuHandler> = {
  name: 'Cannot be sent',
  value: 'send',
  description: 'NFT is for sale',
  isDisabled: true,
};
const TON_DOMAIN_ITEM: DropdownItem<NftMenuHandler> = {
  name: 'Configure DNS',
  value: 'tondns',
  fontIcon: 'external',
};
const SEND_ITEM: DropdownItem<NftMenuHandler> = {
  name: 'Send',
  value: 'send',
};
const FRAGMENT_ITEM: DropdownItem<NftMenuHandler> = {
  name: 'Fragment',
  value: 'fragment',
  fontIcon: 'external',
};
const GETGEMS_ITEM: DropdownItem<NftMenuHandler> = {
  name: 'Getgems',
  value: 'getgems',
  fontIcon: 'external',
};
const TON_EXPLORER_ITEM: DropdownItem<NftMenuHandler> = {
  name: getExplorerName('ton'),
  value: 'tonExplorer',
  fontIcon: 'external',
};
const COLLECTION_ITEM: DropdownItem<NftMenuHandler> = {
  name: 'Collection',
  value: 'collection',
};
const HIDE_ITEM: DropdownItem<NftMenuHandler> = {
  name: 'Hide',
  value: 'hide',
};
const RENEW_ITEM: DropdownItem<NftMenuHandler> = {
  name: 'Renew',
  value: 'renew',
};
const NOT_SCAM: DropdownItem<NftMenuHandler> = {
  name: 'Not Scam',
  value: 'not_scam',
};
const UNHIDE: DropdownItem<NftMenuHandler> = {
  name: 'Unhide',
  value: 'unhide',
};
const BURN_ITEM: DropdownItem<NftMenuHandler> = {
  name: 'Burn',
  value: 'burn',
  isDangerous: true,
};
const SELECT_ITEM: DropdownItem<NftMenuHandler> = {
  name: 'Select',
  value: 'select',
  withDelimiter: true,
};
const INSTALL_CARD: DropdownItem<NftMenuHandler> = {
  name: 'Install Card',
  value: 'installCard',
};
const RESET_CARD: DropdownItem<NftMenuHandler> = {
  name: 'Reset Card',
  value: 'resetCard',
};
const INSTALL_ACCENT_COLOR: DropdownItem<NftMenuHandler> = {
  name: 'Apply Palette',
  value: 'installAccentColor',
};
const RESET_ACCENT_COLOR: DropdownItem<NftMenuHandler> = {
  name: 'Reset Palette',
  value: 'resetAccentColor',
};
const LINK_TO_ADDRESS: DropdownItem<NftMenuHandler> = {
  name: 'Link to Wallet',
  value: 'linkDomain',
};
const CHANGE_LINKED_ADDRESS: DropdownItem<NftMenuHandler> = {
  name: 'Change Wallet',
  value: 'linkDomain',
};

export default function useNftMenu({
  nft,
  isViewMode,
  dnsExpireInDays,
  linkedAddress,
  isNftBlacklisted,
  isNftWhitelisted,
  isNftInstalled,
  isNftAccentColorInstalled,
}: {
  nft?: ApiNft;
  isViewMode: boolean;
  dnsExpireInDays?: number;
  linkedAddress?: string;
  isNftBlacklisted?: boolean;
  isNftWhitelisted?: boolean;
  isNftInstalled?: boolean;
  isNftAccentColorInstalled?: boolean;
}) {
  const {
    startTransfer,
    selectNfts,
    openNftCollection,
    burnNfts,
    addNftsToBlacklist,
    addNftsToWhitelist,
    closeMediaViewer,
    closeNftAttributesModal,
    openUnhideNftModal,
    setCardBackgroundNft,
    clearCardBackgroundNft,
    installAccentColorFromNft,
    clearAccentColorFromNft,
    openDomainRenewalModal,
    openDomainLinkingModal,
  } = getActions();

  const lang = useLang();

  function closeOverlays() {
    closeMediaViewer();
    closeNftAttributesModal();
  }

  const handleMenuItemSelect = useLastCallback((
    value: NftMenuHandler,
    e?: React.MouseEvent,
  ) => {
    const { isTestnet } = getGlobal().settings;
    const isExternal = e?.shiftKey || e?.ctrlKey || e?.metaKey;

    switch (value) {
      case 'send': {
        startTransfer({
          isPortrait: getIsPortrait(),
          nfts: [nft!],
        });
        closeOverlays();

        break;
      }

      case 'tonExplorer': {
        const url = getExplorerNftUrl(nft!.address, isTestnet)!;

        void openUrl(url, { isExternal });
        break;
      }

      case 'getgems': {
        const getgemsBaseUrl = isTestnet ? GETGEMS_BASE_TESTNET_URL : GETGEMS_BASE_MAINNET_URL;
        const getgemsUrl = nft!.collectionAddress
          ? `${getgemsBaseUrl}collection/${nft!.collectionAddress}/${nft!.address}`
          : `${getgemsBaseUrl}nft/${nft!.address}`;

        void openUrl(getgemsUrl, { isExternal });
        break;
      }

      case 'tondns': {
        const url = `https://dns.ton.org/#${(nft!.name || '').replace(/\.ton$/i, '')}`;

        void openUrl(url, { isExternal });
        break;
      }

      case 'installCard': {
        setCardBackgroundNft({ nft: nft! });
        installAccentColorFromNft({ nft: nft! });
        break;
      }

      case 'resetCard': {
        clearCardBackgroundNft();
        clearAccentColorFromNft();
        break;
      }

      case 'installAccentColor': {
        installAccentColorFromNft({ nft: nft! });
        break;
      }

      case 'resetAccentColor': {
        clearAccentColorFromNft();
        break;
      }

      case 'fragment': {
        let url: string;
        const { collectionName, name, metadata: { fragmentUrl } } = nft!;

        if (fragmentUrl) {
          url = fragmentUrl;
        } else if (collectionName?.toLowerCase().includes('numbers')) {
          url = `https://fragment.com/number/${name?.replace(/[^0-9]/g, '')}`;
        } else {
          url = `https://fragment.com/username/${encodeURIComponent(name?.substring(1) || '')}`;
        }

        void openUrl(url, { isExternal });
        break;
      }

      case 'collection': {
        openNftCollection({ address: nft!.collectionAddress! }, { forceOnHeavyAnimation: true });
        closeOverlays();

        break;
      }

      case 'hide': {
        addNftsToBlacklist({ addresses: [nft!.address] });
        closeOverlays();

        break;
      }

      case 'not_scam': {
        openUnhideNftModal({ address: nft!.address, name: nft!.name });

        break;
      }

      case 'unhide': {
        addNftsToWhitelist({ addresses: [nft!.address] });
        closeOverlays();

        break;
      }

      case 'burn': {
        burnNfts({ nfts: [nft!] });
        closeOverlays();

        break;
      }

      case 'select': {
        selectNfts({ addresses: [nft!.address] });
        break;
      }

      case 'renew': {
        openDomainRenewalModal({ addresses: [nft!.address] });
        break;
      }

      case 'linkDomain': {
        openDomainLinkingModal({ address: nft!.address });
        break;
      }
    }
  });

  const menuItems: DropdownItem<NftMenuHandler>[] = useMemo(() => {
    if (!nft) return [];

    const {
      collectionAddress, isOnSale, isOnFragment, isScam,
    } = nft;
    const isDotTon = isDotTonDomainNft(nft);
    const isRenewable = isRenewableDnsNft(nft);
    const isLinkable = isLinkableDnsNft(nft);
    const isCard = !IS_CORE_WALLET && nft.collectionAddress === MTW_CARDS_COLLECTION;

    return compact([
      !isViewMode && (isOnSale ? ON_SALE_ITEM : SEND_ITEM),
      !isViewMode && isRenewable && !isOnSale && dnsExpireInDays !== undefined && {
        ...RENEW_ITEM,
        description: dnsExpireInDays < 0
          ? 'Expired'
          : lang('$expires_in %days%', { days: lang('$in_days', dnsExpireInDays) }, undefined, 1),
      },
      !isViewMode && isLinkable && !isOnSale && (linkedAddress ? CHANGE_LINKED_ADDRESS : LINK_TO_ADDRESS),
      !IS_CORE_WALLET && ((!isScam && !isNftBlacklisted) || isNftWhitelisted) && HIDE_ITEM,
      !IS_CORE_WALLET && isScam && !isNftWhitelisted && NOT_SCAM,
      !IS_CORE_WALLET && !isScam && isNftBlacklisted && UNHIDE,
      ...(!isOnSale && !isViewMode ? [
        BURN_ITEM,
        SELECT_ITEM,
      ] : []),
      collectionAddress && COLLECTION_ITEM,
      isDotTon && !isViewMode && TON_DOMAIN_ITEM,
      ...(isCard ? [!isNftInstalled ? INSTALL_CARD : RESET_CARD] : []),
      ...(isCard ? [!isNftAccentColorInstalled ? INSTALL_ACCENT_COLOR : RESET_ACCENT_COLOR] : []),

      isOnFragment && FRAGMENT_ITEM,
      GETGEMS_ITEM,
      TON_EXPLORER_ITEM,
    ]);
  }, [
    nft, isViewMode, dnsExpireInDays, lang, linkedAddress, isNftBlacklisted,
    isNftWhitelisted, isNftInstalled, isNftAccentColorInstalled,
  ]);

  return { menuItems, handleMenuItemSelect };
}

import type React from '../../../lib/teact/teact';
import { useMemo } from '../../../lib/teact/teact';
import { getActions, getGlobal } from '../../../global';

import type { ApiChain, ApiNft } from '../../../api/types';
import type { DropdownItem } from '../../ui/Dropdown';

import {
  IS_CORE_WALLET,
  MTW_CARDS_COLLECTION,
} from '../../../config';
import { isDotTonDomainNft, isLinkableDnsNft, isRenewableDnsNft } from '../../../util/dns';
import { compact } from '../../../util/iteratees';
import { openUrl } from '../../../util/openUrl';
import { getShareIcon, shareUrl } from '../../../util/share';
import {
  getExplorerName,
  getExplorerNftUrl,
  getMarketplaceName,
  getMarketplaceNftUrl,
  getViewNftUrl,
} from '../../../util/url';

import { getIsPortrait } from '../../../hooks/useDeviceScreen';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

export type NftMenuHandler = 'send' | 'tondns' | 'fragment' | 'marketplace' | 'explorer' | 'collection' | 'hide'
  | 'unhide' | 'not_scam' | 'burn' | 'select' | 'installCard' | 'resetCard' | 'installAccentColor' | 'resetAccentColor'
  | 'renew' | 'linkDomain' | 'shareLink';

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
  withDelimiter: true,
};
const FRAGMENT_ITEM: DropdownItem<NftMenuHandler> = {
  name: 'Fragment',
  value: 'fragment',
  fontIcon: 'external',
};
const getMarketplaceItem = (chain: ApiChain): DropdownItem<NftMenuHandler> => ({
  name: getMarketplaceName(chain),
  value: 'marketplace',
  fontIcon: 'external',
});
const getExplorerItem = (chain: ApiChain): DropdownItem<NftMenuHandler> => ({
  name: getExplorerName(chain),
  value: 'explorer',
  fontIcon: 'external',
});
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
const SHARE_LINK_ITEM: DropdownItem<NftMenuHandler> = {
  name: 'Share Link',
  value: 'shareLink',
  fontIcon: getShareIcon(),
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
  isTestnet,
}: {
  nft?: ApiNft;
  isViewMode: boolean;
  dnsExpireInDays?: number;
  linkedAddress?: string;
  isNftBlacklisted?: boolean;
  isNftWhitelisted?: boolean;
  isNftInstalled?: boolean;
  isNftAccentColorInstalled?: boolean;
  isTestnet?: boolean;
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
    const { isTestnet, selectedExplorerIds } = getGlobal().settings;
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

      case 'explorer': {
        const url = getExplorerNftUrl(
          nft!.chain,
          nft!.address,
          isTestnet,
          selectedExplorerIds?.ton,
        )!;

        void openUrl(url, { isExternal });
        break;
      }

      case 'marketplace': {
        const url = getMarketplaceNftUrl(
          nft?.chain,
          nft?.address,
          isTestnet,
        );
        if (url) {
          void openUrl(url);
        }
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
        openNftCollection({ chain: nft!.chain, address: nft!.collectionAddress! }, { forceOnHeavyAnimation: true });
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
        selectNfts({ nfts: [nft!] });
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

      case 'shareLink': {
        void shareUrl(getViewNftUrl(nft!.address, isTestnet));
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
      ...(isCard ? [!isNftInstalled ? INSTALL_CARD : RESET_CARD] : []),
      ...(isCard ? [!isNftAccentColorInstalled ? INSTALL_ACCENT_COLOR : RESET_ACCENT_COLOR] : []),
      isOnFragment && FRAGMENT_ITEM,
      !isViewMode && (isOnSale ? ON_SALE_ITEM : SEND_ITEM),
      !isViewMode && isLinkable && !isOnSale && (linkedAddress ? CHANGE_LINKED_ADDRESS : LINK_TO_ADDRESS),
      isDotTon && !isViewMode && TON_DOMAIN_ITEM,
      !isViewMode && isRenewable && !isOnSale && dnsExpireInDays !== undefined && {
        ...RENEW_ITEM,
        description: dnsExpireInDays < 0
          ? 'Expired'
          : lang('$expires_in %days%', { days: lang('$in_days', dnsExpireInDays) }, undefined, 1),
      },
      getMarketplaceItem(nft.chain),
      getExplorerItem(nft.chain),
      SHARE_LINK_ITEM,
      collectionAddress && COLLECTION_ITEM,
      !IS_CORE_WALLET && ((!isScam && !isNftBlacklisted) || isNftWhitelisted) && HIDE_ITEM,
      !IS_CORE_WALLET && isScam && !isNftWhitelisted && NOT_SCAM,
      !IS_CORE_WALLET && !isScam && isNftBlacklisted && UNHIDE,
      ...(!isOnSale && !isViewMode ? [
        BURN_ITEM,
        SELECT_ITEM,
      ] : []),
    ]);
  }, [
    nft, isViewMode, dnsExpireInDays, lang, linkedAddress, isNftBlacklisted,
    isNftWhitelisted, isNftInstalled, isNftAccentColorInstalled,
  ]);

  return { menuItems, handleMenuItemSelect };
}

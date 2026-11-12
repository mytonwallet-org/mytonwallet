import React, { memo, useEffect, useMemo, useRef, useState } from '../../../../lib/teact/teact';
import { getActions, getGlobal, withGlobal } from '../../../../global';

import type { ApiNft, ApiNftCollection, ApiUpdateNfts } from '../../../../api/types';
import type { Theme } from '../../../../global/types';

import {
  ANIMATED_STICKER_BIG_SIZE_PX,
  ANIMATED_STICKER_SMALL_SIZE_PX,
  ANIMATION_LEVEL_MIN,
  IS_GRAM_WALLET,
  NFT_MARKETPLACE_TITLE,
  NFT_MARKETPLACE_TITLES,
  NFT_MARKETPLACE_URL,
  TELEGRAM_GIFTS_SUPER_COLLECTION,
  TON_NFT_MARKETPLACE_TITLE,
  TON_NFT_MARKETPLACE_URL,
} from '../../../../config';
import { getIsNftVisible } from '../../../../global/helpers/nfts';
import renderText from '../../../../global/helpers/renderText';
import { buildTelegramGiftCatalog } from '../../../../global/helpers/telegramGiftCatalog';
import {
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectHasAccountAddresses,
  selectIsCurrentAccountViewMode,
  selectIsMultichainAccount,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import captureEscKeyListener from '../../../../util/captureEscKeyListener';
import { openUrl } from '../../../../util/openUrl';
import { getHostnameFromUrl } from '../../../../util/url';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';

import useAppTheme from '../../../../hooks/useAppTheme';
import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import { usePrevDuringAnimationSimple } from '../../../../hooks/usePrevDuringAnimationSimple';
import useScrolledState from '../../../../hooks/useScrolledState';

import Spinner from '../../../ui/Spinner';
import EmptyListPlaceholder from './EmptyListPlaceholder';
import NftList from './NftList';
import TelegramGiftCatalog from './TelegramGiftCatalog';

import styles from './Nft.module.scss';
import catalogStyles from './TelegramGiftCatalog.module.scss';

const SLIDE_TRANSITION_DURATION_MS = 300;

function getNftEmptyStateMarketplace(isMultichainAccount?: boolean) {
  if (IS_GRAM_WALLET) {
    return {
      title: NFT_MARKETPLACE_TITLES.fragment,
      url: 'https://fragment.com/',
    };
  }

  return isMultichainAccount
    ? {
      title: NFT_MARKETPLACE_TITLE,
      url: NFT_MARKETPLACE_URL,
    }
    : {
      title: TON_NFT_MARKETPLACE_TITLE,
      url: TON_NFT_MARKETPLACE_URL,
    };
}

interface OwnProps {
  isActive?: boolean;
  isWidget?: boolean;
  isStretched?: boolean;
  collection?: ApiNftCollection;
  scrollContainerSelector?: string;
}

interface StateProps {
  accountId?: string;
  orderedAddresses?: string[];
  selectedNfts?: ApiNft[];
  byAddress?: Record<string, ApiNft>;
  blacklistedNftAddresses?: string[];
  whitelistedNftAddresses?: string[];
  areUnverifiedNftsHidden?: boolean;
  isNftBuyingDisabled?: boolean;
  dnsExpiration?: Record<string, number>;
  isViewAccount?: boolean;
  isMultichainAccount?: boolean;
  hasAddresses: boolean;
  isLoading?: boolean;
  tonInventoryStatus?: ApiUpdateNfts['inventoryStatus'];
  theme: Theme;
  animationDuration: number;
}

function Nfts({
  accountId,
  isActive,
  isWidget,
  isStretched,
  scrollContainerSelector,
  orderedAddresses,
  selectedNfts,
  byAddress,
  collection,
  dnsExpiration,
  isNftBuyingDisabled,
  blacklistedNftAddresses,
  whitelistedNftAddresses,
  areUnverifiedNftsHidden,
  isViewAccount,
  isMultichainAccount,
  hasAddresses,
  isLoading,
  tonInventoryStatus,
  theme,
  animationDuration,
}: OwnProps & StateProps) {
  const { fetchNftsFromCollection, clearNftsSelection, openNftCollection } = getActions();

  const lang = useLang();
  const contentRef = useRef<HTMLDivElement>();
  const [isListLayout, setIsListLayout] = useState(false);
  const { isPortrait, isLandscape } = useDeviceScreen();
  const realIsActive = usePrevDuringAnimationSimple(isActive, animationDuration);
  const appTheme = useAppTheme(theme);

  const hasSelection = Boolean(selectedNfts?.length);
  const nftMarketplace = getNftEmptyStateMarketplace(isMultichainAccount);

  // In compact mode (`LandscapeWalletOverview`) NFTs are already in global state - no need to fetch
  useEffect(() => {
    if (!isWidget && collection && collection.address !== TELEGRAM_GIFTS_SUPER_COLLECTION) {
      fetchNftsFromCollection({ collection });
    }
  }, [collection, isWidget]);

  // Selection and `Esc` listener are also skipped since compact mode has no selection UI
  useEffect(() => {
    if (!isWidget) clearNftsSelection();
  }, [isActive, isWidget, collection?.address, collection?.chain]);

  useEffect(() => (hasSelection && !isWidget
    ? captureEscKeyListener(clearNftsSelection)
    : undefined), [hasSelection, isWidget]);

  const {
    handleScroll: handleContentScroll,
    isScrolled,
    update: updateScrolledState,
  } = useScrolledState();

  useEffect(() => {
    if (isActive && contentRef.current) {
      updateScrolledState(contentRef.current);
    }
  }, [isActive, updateScrolledState]);

  const nftAddresses = useMemo(() => {
    if (!orderedAddresses || !byAddress) {
      return undefined;
    }

    const blacklistedNftAddressesSet = new Set(blacklistedNftAddresses);
    const whitelistedNftAddressesSet = new Set(whitelistedNftAddresses);

    return orderedAddresses.filter((address) => {
      const nft = byAddress[address];
      if (!nft) return false;

      const matchesCollection = !collection?.address
        || (nft.collectionAddress === collection.address && nft.chain === collection.chain)
        || (collection.address === TELEGRAM_GIFTS_SUPER_COLLECTION && nft.isTelegramGift);

      return matchesCollection
        && getIsNftVisible(nft, blacklistedNftAddressesSet, whitelistedNftAddressesSet, areUnverifiedNftsHidden);
    });
  }, [
    byAddress, collection?.address, collection?.chain, orderedAddresses,
    blacklistedNftAddresses, whitelistedNftAddresses, areUnverifiedNftsHidden,
  ]);

  const isGiftCatalog = collection?.address === TELEGRAM_GIFTS_SUPER_COLLECTION;
  const giftCatalog = useMemo(() => buildTelegramGiftCatalog(
    !isWidget && collection
      ? (isGiftCatalog ? Object.values(byAddress || {}) : (nftAddresses || []).map((address) => byAddress![address]))
      : [],
    new Set(nftAddresses),
  ), [nftAddresses, byAddress, isWidget, collection, isGiftCatalog]);
  const isGiftCollection = !isGiftCatalog && Boolean(collection && giftCatalog.count);

  const openGiftCollection = useLastCallback((address: string) => {
    if (!accountId || selectCurrentAccountId(getGlobal()) !== accountId) return;
    openNftCollection({ address, chain: 'ton' });
  });

  const changeLayout = useLastCallback((asList: boolean) => {
    setIsListLayout(asList);
    const host = isLandscape ? contentRef.current : contentRef.current?.closest('.app-slide-content');
    if (host) host.scrollTop = 0;
  });

  const handleNftMarketplaceClick = useLastCallback(() => {
    void openUrl(nftMarketplace.url, {
      title: nftMarketplace.title,
      subtitle: getHostnameFromUrl(nftMarketplace.url),
    });
  });

  const fullDescription = useMemo(
    () => (isNftBuyingDisabled
      ? undefined
      : renderText(lang('$nft_explore_offer'), isPortrait ? ['simple_markdown'] : undefined)),
    [isNftBuyingDisabled, isPortrait, lang],
  );

  if (nftAddresses === undefined || (!isWidget && !isGiftCatalog && nftAddresses.length === 0 && isLoading)) {
    return <div className={buildClassName(styles.loading, 'content-centered')}><Spinner /></div>;
  }

  if (nftAddresses.length === 0 && !(isGiftCatalog && !isWidget)) {
    return (
      <EmptyListPlaceholder
        stickerTgsUrl={isWidget ? undefined : ANIMATED_STICKERS_PATHS.happy}
        stickerPreviewUrl={isWidget ? undefined : ANIMATED_STICKERS_PATHS.happyPreview}
        stickerSize={isWidget
          ? undefined
          : (isPortrait ? ANIMATED_STICKER_SMALL_SIZE_PX : ANIMATED_STICKER_BIG_SIZE_PX)}
        isStickerActive={isWidget ? undefined : isActive}
        title={lang('No collectibles yet')}
        description={isWidget
          ? (!isNftBuyingDisabled ? lang('$nft_explore_offer') : undefined)
          : fullDescription}
        className="content-centered"
        actionText={!isNftBuyingDisabled && hasAddresses
          ? lang('Open %nft_marketplace%', { nft_marketplace: nftMarketplace.title })
          : undefined}
        onActionClick={!isNftBuyingDisabled ? handleNftMarketplaceClick : undefined}
      />
    );
  }

  if (isWidget) {
    return (
      <NftList
        isWidget
        isWidgetStretched={isStretched}
        isActive={isActive}
        scrollContainerSelector={scrollContainerSelector}
        addresses={nftAddresses}
        appTheme={appTheme}
        dnsExpiration={dnsExpiration}
        isViewAccount={isViewAccount}
        isMultichainAccount={isMultichainAccount}
        nftsByAddresses={byAddress!}
        selectedNfts={selectedNfts}
      />
    );
  }

  return (
    <div
      ref={contentRef}
      className={buildClassName(
        styles.listContainer,
        isLandscape && 'custom-scroll nfts-container',
        isLandscape && isScrolled && styles.listContainerScrolled,
      )}
      onScroll={isLandscape ? handleContentScroll : undefined}
    >
      {isGiftCatalog ? (
        <TelegramGiftCatalog
          catalog={giftCatalog}
          inventoryStatus={tonInventoryStatus}
          onSelectCollection={openGiftCollection}
        />
      ) : (
        <>
          {isGiftCollection && (
            <div className={catalogStyles.toolbar}>
              <button
                type="button"
                onClick={() => openGiftCollection(TELEGRAM_GIFTS_SUPER_COLLECTION)}
              >
                {lang('Back')} · {lang('Telegram Gifts')}
              </button>
              <button type="button" aria-pressed={!isListLayout} onClick={() => changeLayout(false)}>
                {lang('Gift Grid')}
              </button>
              <button type="button" aria-pressed={isListLayout} onClick={() => changeLayout(true)}>
                {lang('Gift List')}
              </button>
            </div>
          )}
          <NftList
            key={`${collection ? `${collection.address}_${collection.chain}` : 'nft-list'}_${isListLayout}`}
            isListLayout={isGiftCollection && isListLayout}
            isActive={realIsActive}
            isLoading={isLoading}
            scrollContainerSelector={scrollContainerSelector}
            appTheme={appTheme}
            addresses={nftAddresses}
            dnsExpiration={dnsExpiration}
            isViewAccount={isViewAccount}
            isMultichainAccount={isMultichainAccount}
            nftsByAddresses={byAddress!}
            selectedNfts={selectedNfts}
          />
        </>
      )}
    </div>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      const {
        orderedAddresses,
        byAddress,
        selectedNfts,
        dnsExpiration,
        isFullLoadingByChain,
        inventoryStatusByChain,
      } = selectCurrentAccountState(global)?.nfts || {};
      const { isNftBuyingDisabled } = global.restrictions;

      const {
        blacklistedNftAddresses,
        whitelistedNftAddresses,
      } = selectCurrentAccountState(global) || {};

      const animationLevel = global.settings.animationLevel;
      const animationDuration = animationLevel === ANIMATION_LEVEL_MIN ? 0 : SLIDE_TRANSITION_DURATION_MS;

      const accountId = selectCurrentAccountId(global);

      return {
        accountId,
        orderedAddresses,
        selectedNfts,
        byAddress,
        blacklistedNftAddresses,
        whitelistedNftAddresses,
        areUnverifiedNftsHidden: global.settings.areUnverifiedNftsHidden,
        isNftBuyingDisabled,
        dnsExpiration,
        isViewAccount: selectIsCurrentAccountViewMode(global),
        isMultichainAccount: accountId ? selectIsMultichainAccount(global, accountId) : undefined,
        hasAddresses: accountId ? selectHasAccountAddresses(global, accountId) : false,
        isLoading: isFullLoadingByChain ? Object.values(isFullLoadingByChain).some(Boolean) : undefined,
        tonInventoryStatus: inventoryStatusByChain?.ton,
        theme: global.settings.theme,
        animationDuration,
      };
    },
    // A container sticks to the first truthy key it sees and only reactivates when the live key
    // returns to that value, so a key built from volatile global state (e.g. `nfts.currentCollection`)
    // freezes this widget whenever it mounts while a collection is open: the key never returns to the
    // opened-collection value once the collection closes. Keying on the account id avoids that, because
    // the id only changes together with a remount. The displayed collection is an own prop, and slides
    // remount via `key` when it changes.
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(Nfts),
);

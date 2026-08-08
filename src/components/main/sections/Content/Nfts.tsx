import React, { memo, useEffect, useMemo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiNft, ApiNftCollection } from '../../../../api/types';
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
import {
  selectCurrentAccountId,
  selectCurrentAccountState,
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

import styles from './Nft.module.scss';

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
}

interface StateProps {
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
  isLoading?: boolean;
  theme: Theme;
  animationDuration: number;
}

function Nfts({
  isActive,
  isWidget,
  isStretched,
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
  isLoading,
  theme,
  animationDuration,
}: OwnProps & StateProps) {
  const { fetchNftsFromCollection, clearNftsSelection } = getActions();

  const lang = useLang();
  const contentRef = useRef<HTMLDivElement>();
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

  if (nftAddresses === undefined || (!isWidget && nftAddresses.length === 0 && isLoading)) {
    return <div className={buildClassName(styles.loading, 'content-centered')}><Spinner /></div>;
  }

  if (nftAddresses.length === 0) {
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
        actionText={!isNftBuyingDisabled
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
      <NftList
        key={collection ? `${collection.address}_${collection.chain}` : 'nft-list'}
        isActive={realIsActive}
        isLoading={isLoading}
        appTheme={appTheme}
        addresses={nftAddresses}
        dnsExpiration={dnsExpiration}
        isViewAccount={isViewAccount}
        isMultichainAccount={isMultichainAccount}
        nftsByAddresses={byAddress!}
        selectedNfts={selectedNfts}
      />
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
        isLoading: isFullLoadingByChain ? Object.values(isFullLoadingByChain).some(Boolean) : undefined,
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

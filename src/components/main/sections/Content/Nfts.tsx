import React, { memo, useEffect, useMemo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiNft, ApiNftCollection } from '../../../../api/types';
import type { Theme } from '../../../../global/types';

import {
  ANIMATED_STICKER_BIG_SIZE_PX,
  ANIMATED_STICKER_SMALL_SIZE_PX,
  ANIMATION_LEVEL_MIN,
  NFT_MARKETPLACE_TITLE,
  NFT_MARKETPLACE_URL,
  TELEGRAM_GIFTS_SUPER_COLLECTION,
  TON_NFT_MARKETPLACE_TITLE,
  TON_NFT_MARKETPLACE_URL,
} from '../../../../config';
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

interface OwnProps {
  isActive?: boolean;
  isWidget?: boolean;
  collection?: ApiNftCollection;
}

interface StateProps {
  orderedAddresses?: string[];
  selectedNfts?: ApiNft[];
  byAddress?: Record<string, ApiNft>;
  collection?: ApiNftCollection;
  blacklistedNftAddresses?: string[];
  whitelistedNftAddresses?: string[];
  isNftBuyingDisabled?: boolean;
  dnsExpiration?: Record<string, number>;
  isViewAccount?: boolean;
  isMultichainAccount?: boolean;
  isLoading?: boolean;
  theme: Theme;
  animationDuration: number;
}

const COMPACT_GRID_LIMIT = 9;

function Nfts({
  isActive,
  isWidget,
  orderedAddresses,
  selectedNfts,
  byAddress,
  collection,
  dnsExpiration,
  isNftBuyingDisabled,
  blacklistedNftAddresses,
  whitelistedNftAddresses,
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
  const nftMarketplaceTitle = isMultichainAccount ? NFT_MARKETPLACE_TITLE : TON_NFT_MARKETPLACE_TITLE;
  const nftMarketplaceUrl = isMultichainAccount ? NFT_MARKETPLACE_URL : TON_NFT_MARKETPLACE_URL;

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

      const isVisible = (
        !nft.isHidden || whitelistedNftAddressesSet.has(nft.address)
      ) && !blacklistedNftAddressesSet.has(nft.address);

      return matchesCollection && isVisible;
    });
  }, [
    byAddress, collection?.address, collection?.chain, orderedAddresses,
    blacklistedNftAddresses, whitelistedNftAddresses,
  ]);

  const handleNftMarketplaceClick = useLastCallback(() => {
    void openUrl(nftMarketplaceUrl, {
      title: nftMarketplaceTitle,
      subtitle: getHostnameFromUrl(nftMarketplaceUrl),
    });
  });

  const fullDescription = useMemo(
    () => (isNftBuyingDisabled
      ? undefined
      : renderText(lang('$nft_explore_offer'), isPortrait ? ['simple_markdown'] : undefined)),
    [isNftBuyingDisabled, isPortrait, lang],
  );

  if (isWidget) {
    if (nftAddresses === undefined) {
      return <div className={styles.loading}><Spinner /></div>;
    }

    if (nftAddresses.length === 0) {
      return (
        <EmptyListPlaceholder
          title={lang('No collectibles yet')}
          description={!isNftBuyingDisabled ? lang('$nft_explore_offer') : undefined}
          actionText={
            !isNftBuyingDisabled
              ? lang('Open %nft_marketplace%', { nft_marketplace: nftMarketplaceTitle })
              : undefined
          }
          onActionClick={!isNftBuyingDisabled ? handleNftMarketplaceClick : undefined}
        />
      );
    }

    return (
      <NftList
        isWidget
        addresses={nftAddresses.slice(0, COMPACT_GRID_LIMIT)}
        appTheme={appTheme}
        dnsExpiration={dnsExpiration}
        isViewAccount={isViewAccount}
        isMultichainAccount={isMultichainAccount}
        nftsByAddresses={byAddress!}
        selectedNfts={selectedNfts}
      />
    );
  }

  if (nftAddresses === undefined || (nftAddresses.length === 0 && isLoading)) {
    return <div className={styles.loading}><Spinner /></div>;
  }

  if (nftAddresses.length === 0) {
    return (
      <EmptyListPlaceholder
        stickerTgsUrl={ANIMATED_STICKERS_PATHS.happy}
        stickerPreviewUrl={ANIMATED_STICKERS_PATHS.happyPreview}
        stickerSize={isPortrait ? ANIMATED_STICKER_SMALL_SIZE_PX : ANIMATED_STICKER_BIG_SIZE_PX}
        isStickerActive={isActive}
        title={lang('No collectibles yet')}
        description={fullDescription}
        actionText={
          !isNftBuyingDisabled
            ? lang('Open %nft_marketplace%', { nft_marketplace: nftMarketplaceTitle })
            : undefined
        }
        onActionClick={!isNftBuyingDisabled ? handleNftMarketplaceClick : undefined}
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
    (global, { collection: ownCollection }): StateProps => {
      const {
        orderedAddresses,
        byAddress,
        currentCollection,
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
        collection: ownCollection ?? currentCollection,
        blacklistedNftAddresses,
        whitelistedNftAddresses,
        isNftBuyingDisabled,
        dnsExpiration,
        isViewAccount: selectIsCurrentAccountViewMode(global),
        isMultichainAccount: accountId ? selectIsMultichainAccount(global, accountId) : undefined,
        isLoading: isFullLoadingByChain ? Object.values(isFullLoadingByChain).some(Boolean) : undefined,
        theme: global.settings.theme,
        animationDuration,
      };
    },
    (global, { collection: ownCollection }, stickToFirst) => {
      const collection = ownCollection
        ?? selectCurrentAccountState(global)?.nfts?.currentCollection;

      return stickToFirst(
        `${selectCurrentAccountId(global)}_${collection
          ? `${collection.address}_${collection.chain}`
          : 'all'}`,
      );
    },
  )(Nfts),
);

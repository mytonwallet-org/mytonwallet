import React, { memo, useEffect, useMemo, useRef } from '../../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../../global';

import type { ApiChain, ApiNft, ApiNftCollection } from '../../../../api/types';
import type { Theme } from '../../../../global/types';

import {
  ANIMATED_STICKER_BIG_SIZE_PX,
  ANIMATED_STICKER_SMALL_SIZE_PX,
  ANIMATION_LEVEL_MIN,
  NFT_MARKETPLACE_TITLE,
  NFT_MARKETPLACE_URL,
  TELEGRAM_GIFTS_SUPER_COLLECTION,
} from '../../../../config';
import renderText from '../../../../global/helpers/renderText';
import {
  selectAccount,
  selectCurrentAccountId,
  selectCurrentAccountState,
  selectIsCurrentAccountViewMode,
} from '../../../../global/selectors';
import buildClassName from '../../../../util/buildClassName';
import captureEscKeyListener from '../../../../util/captureEscKeyListener';
import { stopEvent } from '../../../../util/domEvents';
import { isKeyCountGreater } from '../../../../util/isEmptyObject';
import { openUrl } from '../../../../util/openUrl';
import { getHostnameFromUrl } from '../../../../util/url';
import { ANIMATED_STICKERS_PATHS } from '../../../ui/helpers/animatedAssets';

import useAppTheme from '../../../../hooks/useAppTheme';
import { useDeviceScreen } from '../../../../hooks/useDeviceScreen';
import useLang from '../../../../hooks/useLang';
import { usePrevDuringAnimationSimple } from '../../../../hooks/usePrevDuringAnimationSimple';
import useScrolledState from '../../../../hooks/useScrolledState';

import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';
import Spinner from '../../../ui/Spinner';
import NftList from './NftList';

import styles from './Nft.module.scss';

const SLIDE_TRANSITION_DURATION_MS = 300;

interface OwnProps {
  isActive?: boolean;
}

interface StateProps {
  orderedAddresses?: string[];
  selectedNfts?: ApiNft[];
  accountChains?: Partial<Record<ApiChain, unknown>>;
  byAddress?: Record<string, ApiNft>;
  currentCollection?: ApiNftCollection;
  blacklistedNftAddresses?: string[];
  whitelistedNftAddresses?: string[];
  isNftBuyingDisabled?: boolean;
  dnsExpiration?: Record<string, number>;
  isViewAccount?: boolean;
  isLoading?: boolean;
  theme: Theme;
  animationDuration: number;
}

const EMPTY_DICTIONARY = Object.freeze({});

function Nfts({
  accountChains = EMPTY_DICTIONARY,
  isActive,
  orderedAddresses,
  selectedNfts,
  byAddress,
  currentCollection,
  dnsExpiration,
  isNftBuyingDisabled,
  blacklistedNftAddresses,
  whitelistedNftAddresses,
  isViewAccount,
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
  const isMultichainAccount = isKeyCountGreater(accountChains, 1);

  useEffect(() => {
    if (currentCollection && currentCollection.address !== TELEGRAM_GIFTS_SUPER_COLLECTION) {
      fetchNftsFromCollection({ collection: currentCollection });
    }
  }, [currentCollection]);

  useEffect(clearNftsSelection, [clearNftsSelection, isActive, currentCollection?.address]);
  useEffect(() => (hasSelection ? captureEscKeyListener(clearNftsSelection) : undefined), [hasSelection]);

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

      const matchesCollection = !currentCollection?.address
        || (nft.collectionAddress === currentCollection.address && nft.chain === currentCollection.chain)
        || (currentCollection.address === TELEGRAM_GIFTS_SUPER_COLLECTION && nft.isTelegramGift);

      const isVisible = (
        !nft.isHidden || whitelistedNftAddressesSet.has(nft.address)
      ) && !blacklistedNftAddressesSet.has(nft.address);

      return matchesCollection && isVisible;
    });
  }, [
    byAddress, currentCollection?.address, currentCollection?.chain, orderedAddresses,
    blacklistedNftAddresses, whitelistedNftAddresses,
  ]);

  function handleNftMarketplaceClick(e: React.MouseEvent<HTMLButtonElement, MouseEvent>) {
    stopEvent(e);

    void openUrl(NFT_MARKETPLACE_URL, {
      title: NFT_MARKETPLACE_TITLE,
      subtitle: getHostnameFromUrl(NFT_MARKETPLACE_URL),
    });
  }

  if (nftAddresses === undefined || (nftAddresses.length === 0 && isLoading)) {
    return (
      <div className={buildClassName(styles.emptyList, styles.emptyListLoading)}>
        <Spinner />
      </div>
    );
  }

  if (nftAddresses.length === 0) {
    return (
      <div className={styles.emptyList}>
        <AnimatedIconWithPreview
          play={isActive}
          tgsUrl={ANIMATED_STICKERS_PATHS.happy}
          previewUrl={ANIMATED_STICKERS_PATHS.happyPreview}
          size={isPortrait ? ANIMATED_STICKER_SMALL_SIZE_PX : ANIMATED_STICKER_BIG_SIZE_PX}
          className={styles.sticker}
          noLoop={false}
          nonInteractive
        />
        <div className={styles.emptyListContent}>
          <p className={styles.emptyListTitle}>{lang('No NFTs yet')}</p>
          {!isNftBuyingDisabled && (
            <>
              <p className={styles.emptyListText}>
                {renderText(lang('$nft_explore_offer'), isPortrait ? ['simple_markdown'] : undefined)}
              </p>
              <button type="button" className={styles.emptyListButton} onClick={handleNftMarketplaceClick}>
                {lang('Open %nft_marketplace%', { nft_marketplace: NFT_MARKETPLACE_TITLE })}
              </button>
            </>
          )}
        </div>
      </div>
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
        key={currentCollection ? `${currentCollection.address}_${currentCollection.chain}` : 'nft-list'}
        isActive={realIsActive}
        isLoading={isLoading}
        appTheme={appTheme}
        addresses={nftAddresses}
        dnsExpiration={dnsExpiration}
        isViewAccount={isViewAccount}
        nftsByAddresses={byAddress!}
        selectedNfts={selectedNfts}
        withChainIcon={isMultichainAccount}
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

      const currentAccountId = selectCurrentAccountId(global)!;
      const animationLevel = global.settings.animationLevel;
      const animationDuration = animationLevel === ANIMATION_LEVEL_MIN ? 0 : SLIDE_TRANSITION_DURATION_MS;

      return {
        accountChains: selectAccount(global, currentAccountId)?.byChain,
        orderedAddresses,
        selectedNfts,
        byAddress,
        currentCollection,
        blacklistedNftAddresses,
        whitelistedNftAddresses,
        isNftBuyingDisabled,
        dnsExpiration,
        isViewAccount: selectIsCurrentAccountViewMode(global),
        isLoading: isFullLoadingByChain ? Object.values(isFullLoadingByChain).some(Boolean) : undefined,
        theme: global.settings.theme,
        animationDuration,
      };
    },
    (global, _, stickToFirst) => {
      const {
        currentCollection,
      } = selectCurrentAccountState(global)?.nfts || {};

      const isCollectionSelected = !!currentCollection;

      return stickToFirst(
        `${selectCurrentAccountId(global)}_${isCollectionSelected
          ? `${currentCollection.address}_${currentCollection.chain}`
          : 'all'}`,
      );
    },
  )(Nfts),
);

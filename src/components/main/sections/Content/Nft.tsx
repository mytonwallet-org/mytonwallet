import React, {
  memo, useEffect, useMemo, useRef, useState,
} from '../../../../lib/teact/teact';
import { getActions } from '../../../../global';

import type { ApiNft } from '../../../../api/types';
import type { AppTheme } from '../../../../global/types';
import { type IAnchorPosition } from '../../../../global/types';

import { TON_DNS_RENEWAL_NFT_WARNING_DAYS } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';
import { getChainTitle } from '../../../../util/chain';
import { getCountDaysToDate } from '../../../../util/dateFormat';
import { stopEvent } from '../../../../util/domEvents';
import { vibrate } from '../../../../util/haptics';
import { shortenAddress } from '../../../../util/shortenAddress';
import { IS_ANDROID, IS_IOS } from '../../../../util/windowEnvironment';

import useContextMenuHandlers from '../../../../hooks/useContextMenuHandlers';
import useFlag from '../../../../hooks/useFlag';
import useLang from '../../../../hooks/useLang';
import useLastCallback from '../../../../hooks/useLastCallback';
import useShowTransition from '../../../../hooks/useShowTransition';
import useSyncEffect from '../../../../hooks/useSyncEffect';

import AnimatedIconWithPreview from '../../../ui/AnimatedIconWithPreview';
import Image from '../../../ui/Image';
import Radio from '../../../ui/Radio';
import NftMenu from './NftMenu';

import styles from './Nft.module.scss';

import noImageSrcDark from '../../../../assets/nftNoImageDark.svg';
import noImageSrcLight from '../../../../assets/nftNoImageLight.svg';

interface OwnProps {
  nft: ApiNft;
  appTheme: AppTheme;
  selectedNfts?: ApiNft[];
  tonDnsExpiration?: number;
  isViewAccount?: boolean;
  withChainIcon: boolean;
  style: string;
}

interface UseLottieReturnType {
  isLottie: boolean;
  shouldPlay?: boolean;
  noLoop?: boolean;
  markHover?: NoneToVoidFunction;
  unmarkHover?: NoneToVoidFunction;
}

function Nft({
  nft,
  appTheme,
  selectedNfts,
  tonDnsExpiration,
  isViewAccount,
  withChainIcon,
  style,
}: OwnProps) {
  const { selectNfts, clearNftSelection, openDomainRenewalModal, openNftAttributesModal } = getActions();

  const lang = useLang();
  const ref = useRef<HTMLDivElement>();
  const { isLottie, shouldPlay, noLoop, markHover, unmarkHover } = useLottie(nft);
  const [hasImage, markHasImage, unmarkHasImage] = useFlag(Boolean(nft.thumbnail));
  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition>();
  const isSelected = useMemo(() => selectedNfts?.some((e) => e.address === nft.address), [selectedNfts, nft.address]);

  const isMenuOpen = Boolean(menuAnchor);
  const dnsExpireInDays = tonDnsExpiration ? getCountDaysToDate(tonDnsExpiration) : undefined;
  const isDnsExpireSoon = dnsExpireInDays !== undefined ? dnsExpireInDays <= TON_DNS_RENEWAL_NFT_WARNING_DAYS : false;
  const isSelectionEnabled = !!selectedNfts && selectedNfts.length > 0;
  const isSelectionEnabledForCurrentNft = isSelectionEnabled && selectedNfts[0].chain === nft.chain;
  const isCrossChainBlocked = isSelectionEnabled && !isSelectionEnabledForCurrentNft;
  const { shouldRender: shouldRenderWarning, ref: warningRef } = useShowTransition({
    isOpen: isSelectionEnabled && nft.isOnSale && !isCrossChainBlocked,
    withShouldRender: true,
  });
  const { shouldRender: shouldRenderCrossChainWarning, ref: crossChainWarningRef } = useShowTransition({
    isOpen: isCrossChainBlocked,
    withShouldRender: true,
  });
  const hasCollectionName = Boolean(nft.collectionName);

  useEffect(() => {
    if (nft.thumbnail) {
      markHasImage();
    }
  }, [nft.thumbnail]);

  const {
    isContextMenuOpen,
    contextMenuAnchor,
    handleBeforeContextMenu,
    handleContextMenu,
    handleContextMenuHide,
    handleContextMenuClose,
  } = useContextMenuHandlers({
    elementRef: ref,
  });

  const fullClassName = buildClassName(
    styles.item,
    !isSelectionEnabled && nft.isOnSale && styles.item_onSale,
    isMenuOpen && styles.itemWithMenu,
    (isCrossChainBlocked || (isSelectionEnabled && nft.isOnSale)) && styles.nonInteractive,
  );

  function handleClick() {
    if (isSelectionEnabledForCurrentNft) {
      if (isSelected) {
        clearNftSelection({ address: nft.address });
      } else {
        selectNfts({ nfts: [nft] });
      }
      return;
    }

    void vibrate();
    openNftAttributesModal({ nft });
  }

  function handleRenewDomainClick(e: React.MouseEvent) {
    stopEvent(e);

    openDomainRenewalModal({ addresses: [nft.address] });
  }

  const handleOpenContextMenu = useLastCallback(() => {
    setMenuAnchor(contextMenuAnchor);
  });

  const handleOpenMenu = useLastCallback(() => {
    const { right: x, y } = ref.current!.getBoundingClientRect();
    setMenuAnchor({ x, y });
  });

  const handleCloseMenu = useLastCallback(() => {
    setMenuAnchor(undefined);
    handleContextMenuClose();
  });

  useSyncEffect(() => {
    if (isContextMenuOpen) {
      handleOpenContextMenu();
    } else {
      handleCloseMenu();
    }
  }, [isContextMenuOpen]);

  function renderVisualContent() {
    if (!hasImage) {
      return (
        <div className={buildClassName(styles.imageWrapper, styles.imageWrapperNoData, 'rounded-font')}>
          <img src={appTheme === 'dark' ? noImageSrcDark : noImageSrcLight} alt="" className={styles.noImage} />
          <span className={styles.noImageText}>{lang('No Image')}</span>
        </div>
      );
    }

    return (
      isLottie ? (
        <div className={styles.imageWrapper}>
          <AnimatedIconWithPreview
            shouldStretch
            play={shouldPlay}
            noLoop={noLoop}
            tgsUrl={nft.metadata.lottie}
            previewUrl={nft.thumbnail}
            noPreviewTransition
            className={buildClassName(
              styles.image,
              isSelected && styles.imageSelected,
            )}
          />
          {isDnsExpireSoon && renderDnsExpireWarning()}
        </div>
      ) : (
        <Image
          url={nft.thumbnail}
          className={styles.imageWrapper}
          imageClassName={buildClassName(
            styles.image,
            isSelected && styles.imageSelected,
          )}
          onError={unmarkHasImage}
        >
          {isDnsExpireSoon && renderDnsExpireWarning()}
        </Image>
      )
    );
  }

  function renderChainIcon() {
    return (
      <i
        className={buildClassName(styles.chainIcon, `icon-chain-${nft.chain.toLowerCase()}`)}
        aria-label={getChainTitle(nft.chain)}
      />
    );
  }

  function renderDnsExpireWarning() {
    return (
      <button
        type="button"
        className={buildClassName(styles.warningBlock, isViewAccount && styles.nonInteractive)}
        onClick={!isViewAccount ? handleRenewDomainClick : undefined}
      >
        {dnsExpireInDays! < 0
          ? 'Expired'
          : lang('$expires_in %days%', { days: lang('$in_days', dnsExpireInDays) }, undefined, 1)}
      </button>
    );
  }

  return (
    <div
      key={nft.address}
      ref={ref}
      style={style}
      className={fullClassName}
      onMouseEnter={isSelectionEnabledForCurrentNft ? markHover : undefined}
      onMouseLeave={isSelectionEnabledForCurrentNft ? unmarkHover : undefined}
      onClick={!(isSelectionEnabledForCurrentNft) || !nft.isOnSale ? handleClick : undefined}
      onMouseDown={handleBeforeContextMenu}
      onContextMenu={handleContextMenu}
    >
      {isSelectionEnabled && isSelectionEnabledForCurrentNft && !nft.isOnSale && (
        <Radio isChecked={isSelected} name="nft" value={nft.address} className={styles.radio} />
      )}
      {!isSelectionEnabled && !isSelectionEnabledForCurrentNft && (
        <NftMenu
          nft={nft}
          isContextMenuMode={Boolean(contextMenuAnchor)}
          dnsExpireInDays={dnsExpireInDays}
          menuAnchor={menuAnchor}
          onOpen={handleOpenMenu}
          onClose={handleCloseMenu}
          onCloseAnimationEnd={handleContextMenuHide}
        />
      )}
      {renderVisualContent()}
      {shouldRenderWarning && (
        <div ref={warningRef} className={styles.warning}>
          {lang('For sale. Cannot be sent and burned')}
        </div>
      )}
      {shouldRenderCrossChainWarning && (
        <div ref={crossChainWarningRef} className={styles.warning}>
          {lang('Different blockchain. Cannot be selected')}
        </div>
      )}
      <div className={styles.infoWrapper} title={nft.name}>
        {!hasCollectionName && renderChainIcon()}
        <b className={styles.title}>{nft.name || shortenAddress(nft.address, 4)}</b>
      </div>
      {hasCollectionName && (
        <div className={styles.collection}>
          {withChainIcon && renderChainIcon()}
          {nft.collectionName}
        </div>
      )}
    </div>
  );
}

export default memo(Nft);

function useLottie(nft: ApiNft): UseLottieReturnType {
  const isLottie = Boolean(nft.metadata?.lottie);

  const [isHover, markHover, unmarkHover] = useFlag();

  if (!isLottie) {
    return { isLottie };
  }

  const shouldPlay = isHover;
  const noLoop = !isHover;

  return {
    isLottie,
    shouldPlay,
    noLoop,
    ...(!(IS_IOS || IS_ANDROID) && {
      markHover,
      unmarkHover,
    }),
  };
}

import React, { memo, useMemo, useRef, useState } from '../../../../lib/teact/teact';
import { getActions } from '../../../../global';

import type { ApiNft } from '../../../../api/types';
import { type IAnchorPosition } from '../../../../global/types';

import { TON_DNS_RENEWAL_NFT_WARNING_DAYS } from '../../../../config';
import buildClassName from '../../../../util/buildClassName';
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

interface OwnProps {
  nft: ApiNft;
  selectedAddresses?: string[];
  tonDnsExpiration?: number;
  isViewAccount?: boolean;
}

interface UseLottieReturnType {
  isLottie: boolean;
  shouldPlay?: boolean;
  noLoop?: boolean;
  markHover?: NoneToVoidFunction;
  unmarkHover?: NoneToVoidFunction;
}

function Nft({ nft, selectedAddresses, tonDnsExpiration, isViewAccount }: OwnProps) {
  const { selectNfts, clearNftSelection, openDomainRenewalModal, openNftAttributesModal } = getActions();

  const lang = useLang();

  const ref = useRef<HTMLDivElement>();

  const { isLottie, shouldPlay, noLoop, markHover, unmarkHover } = useLottie(nft);

  const [menuAnchor, setMenuAnchor] = useState<IAnchorPosition>();
  const isSelectionEnabled = !!selectedAddresses && selectedAddresses.length > 0;
  const isSelected = useMemo(() => selectedAddresses?.includes(nft.address), [selectedAddresses, nft.address]);
  const isMenuOpen = Boolean(menuAnchor);
  const dnsExpireInDays = tonDnsExpiration ? getCountDaysToDate(tonDnsExpiration) : undefined;
  const isDnsExpireSoon = dnsExpireInDays !== undefined ? dnsExpireInDays <= TON_DNS_RENEWAL_NFT_WARNING_DAYS : false;
  const { shouldRender: shouldRenderWarning, ref: warningRef } = useShowTransition({
    isOpen: isSelectionEnabled && nft.isOnSale,
    withShouldRender: true,
  });

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
    isSelectionEnabled && nft.isOnSale && styles.nonInteractive,
  );

  function handleClick() {
    if (isSelectionEnabled) {
      if (isSelected) {
        clearNftSelection({ address: nft.address });
      } else {
        selectNfts({ addresses: [nft.address] });
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
      className={fullClassName}
      onMouseEnter={markHover}
      onMouseLeave={unmarkHover}
      onClick={!isSelectionEnabled || !nft.isOnSale ? handleClick : undefined}
      onMouseDown={handleBeforeContextMenu}
      onContextMenu={handleContextMenu}
    >
      {isSelectionEnabled && !nft.isOnSale && (
        <Radio isChecked={isSelected} name="nft" value={nft.address} className={styles.radio} />
      )}
      {!isSelectionEnabled && (
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
      {isLottie ? (
        <div className={styles.imageWrapper}>
          <AnimatedIconWithPreview
            shouldStretch
            play={shouldPlay}
            noLoop={noLoop}
            tgsUrl={nft.metadata.lottie}
            previewUrl={nft.thumbnail}
            noPreviewTransition
            className={buildClassName(styles.image, isSelected && styles.imageSelected)}
          />
          {isDnsExpireSoon && renderDnsExpireWarning()}
        </div>
      ) : (
        <Image
          url={nft.thumbnail}
          className={styles.imageWrapper}
          imageClassName={buildClassName(styles.image, isSelected && styles.imageSelected)}
        >
          {isDnsExpireSoon && renderDnsExpireWarning()}
        </Image>
      )}
      {shouldRenderWarning && (
        <div ref={warningRef} className={styles.warning}>
          {lang('For sale. Cannot be sent and burned')}
        </div>
      )}
      <div className={styles.infoWrapper}>
        <b className={styles.title}>{nft.name || shortenAddress(nft.address, 4)}</b>
      </div>
      <div className={styles.collection}>{nft.collectionName}</div>
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

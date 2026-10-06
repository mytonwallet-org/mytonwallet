import { memo } from '../../../lib/teact/teact';
import React from '../../../lib/teact/teactn';
import { getActions } from '../../../global';

import { type ApiNft } from '../../../api/types';
import { MediaType } from '../../../global/types';

import { stopEvent } from '../../../util/domEvents';

import useFlag from '../../../hooks/useFlag';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useShowTransition from '../../../hooks/useShowTransition';

import NftImage from '../../common/NftImage';
import Button from '../../ui/Button';

import styles from '../Settings.module.scss';

interface OwnProps {
  nft: ApiNft;
  style?: string;
}

function HiddenByUserNft({ nft, style }: OwnProps) {
  const { openMediaViewer, removeNftSpecialStatus } = getActions();
  const lang = useLang();

  const [isNftHidden, , unmarkNftHidden] = useFlag(true);

  const handleUnhide = useLastCallback(() => {
    removeNftSpecialStatus({ address: nft.address });
  });

  const { ref } = useShowTransition({
    isOpen: isNftHidden,
    onCloseAnimationEnd: handleUnhide,
  });

  function handleNftClick() {
    openMediaViewer({
      mediaId: nft.address, mediaType: MediaType.Nft, hiddenNfts: 'user',
    });
  }

  // The unhide button inside the row is focusable on its own, and its own Space press must not open the viewer
  const handleNftKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    if ((e.code !== 'Enter' && e.code !== 'Space') || e.target !== e.currentTarget) return;

    stopEvent(e);
    handleNftClick();
  });

  return (
    <div
      ref={ref}
      className={styles.item}
      style={style}
      onClick={handleNftClick}
      onKeyDown={handleNftKeyDown}
      key={nft.address}
      role="button"
      tabIndex={0}
      data-nft-address={nft.address}
    >
      <NftImage url={nft.thumbnail} className={styles.nftImage} />
      <div className={styles.nftPrimaryCell}>
        <span className={styles.nftName}>{nft.name || lang('Untitled')}</span>
        {
          nft.collectionName && <span className={styles.nftCollection}>{nft.collectionName}</span>
        }
      </div>

      <Button
        isSmall
        isPrimary
        isText
        className={styles.nftButtonUnhide}
        onClick={unmarkNftHidden}
        shouldStopPropagation
      >
        {lang('Unhide')}
      </Button>
    </div>
  );
}

export default memo(HiddenByUserNft);

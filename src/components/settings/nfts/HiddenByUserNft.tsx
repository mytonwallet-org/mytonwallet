import { memo } from '../../../lib/teact/teact';
import React from '../../../lib/teact/teactn';
import { getActions } from '../../../global';

import { type ApiNft } from '../../../api/types';
import { MediaType } from '../../../global/types';

import useFlag from '../../../hooks/useFlag';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';
import useShowTransition from '../../../hooks/useShowTransition';

import Button from '../../ui/Button';

import styles from '../Settings.module.scss';

interface OwnProps {
  nft: ApiNft;
}

function HiddenByUserNft({ nft }: OwnProps) {
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

  return (
    <div
      ref={ref}
      className={styles.item}
      onClick={handleNftClick}
      key={nft.address}
      role="button"
      tabIndex={0}
      data-nft-address={nft.address}
    >
      <img className={styles.nftImage} src={nft.image} alt={nft.name} />
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

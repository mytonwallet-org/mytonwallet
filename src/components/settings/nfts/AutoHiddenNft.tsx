import { memo } from '../../../lib/teact/teact';
import React from '../../../lib/teact/teactn';
import { getActions } from '../../../global';

import { type ApiNft } from '../../../api/types';
import { type HiddenNftsSection, MediaType } from '../../../global/types';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import Switcher from '../../ui/Switcher';

import styles from '../Settings.module.scss';

interface OwnProps {
  nft: ApiNft;
  section: HiddenNftsSection;
  isWhitelisted?: boolean;
  shouldConfirmUnhide?: boolean;
}

function AutoHiddenNft({
  nft, section, isWhitelisted, shouldConfirmUnhide,
}: OwnProps) {
  const {
    openMediaViewer, removeNftSpecialStatus, openUnhideNftModal, addNftsToWhitelist,
  } = getActions();
  const lang = useLang();

  const handleNftClick = useLastCallback(() => {
    openMediaViewer({
      mediaId: nft.address, mediaType: MediaType.Nft, hiddenNfts: section,
    });
  });

  const handleSwitcherClick = useLastCallback((e: React.ChangeEvent) => {
    e.stopPropagation();
    if (isWhitelisted) {
      removeNftSpecialStatus({ address: nft.address });
    } else if (shouldConfirmUnhide) {
      openUnhideNftModal({ address: nft.address, name: nft.name! });
    } else {
      addNftsToWhitelist({ addresses: [nft.address] });
    }
  });

  return (
    <div
      className={styles.item}
      onClick={handleNftClick}
      key={nft.address}
      role="button"
      tabIndex={0}
      data-nft-address={nft.address}
    >
      <img className={styles.nftImage} src={nft.image ?? nft.thumbnail} alt={nft.name} />
      <div className={styles.nftPrimaryCell}>
        <span className={styles.nftName}>{nft.name}</span>
        {nft.collectionName && <span className={styles.nftCollection}>{nft.collectionName}</span>}
      </div>

      <Switcher
        className={styles.menuSwitcher}
        label={lang('Show')}
        checked={isWhitelisted}
        onChange={handleSwitcherClick}
        shouldStopPropagation
      />
    </div>
  );
}

export default memo(AutoHiddenNft);

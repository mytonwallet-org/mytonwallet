import { memo } from '../../../lib/teact/teact';
import React from '../../../lib/teact/teactn';
import { getActions } from '../../../global';

import { type ApiNft } from '../../../api/types';
import { type HiddenNftsSection, MediaType } from '../../../global/types';

import { stopEvent } from '../../../util/domEvents';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import NftImage from '../../common/NftImage';
import Switcher from '../../ui/Switcher';

import styles from '../Settings.module.scss';

interface OwnProps {
  nft: ApiNft;
  section: HiddenNftsSection;
  isWhitelisted?: boolean;
  shouldConfirmUnhide?: boolean;
  style?: string;
}

function AutoHiddenNft({
  nft, section, isWhitelisted, shouldConfirmUnhide, style,
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

  // The switcher inside the row is focusable on its own, and its own Space press must not open the viewer
  const handleNftKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    if ((e.code !== 'Enter' && e.code !== 'Space') || e.target !== e.currentTarget) return;

    stopEvent(e);
    handleNftClick();
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

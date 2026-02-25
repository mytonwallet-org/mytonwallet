import { memo } from '../../../lib/teact/teact';
import React from '../../../lib/teact/teactn';
import { getActions } from '../../../global';

import { type ApiNft } from '../../../api/types';
import { MediaType } from '../../../global/types';

import { IS_ELECTRON } from '../../../util/windowEnvironment';

import { useDeviceScreen } from '../../../hooks/useDeviceScreen';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import Switcher from '../../ui/Switcher';

import styles from '../Settings.module.scss';

interface OwnProps {
  nft: ApiNft;
  isWhitelisted?: boolean;
}

function ProbablyScamNft({ nft, isWhitelisted }: OwnProps) {
  const { openMediaViewer, removeNftSpecialStatus, openUnhideNftModal } = getActions();
  const lang = useLang();

  const { isPortrait } = useDeviceScreen();
  const areSettingsInModal = !isPortrait || IS_ELECTRON;

  const handleNftClick = useLastCallback(() => {
    openMediaViewer({
      mediaId: nft.address, mediaType: MediaType.Nft, noGhostAnimation: areSettingsInModal, hiddenNfts: 'scam',
    });
  });

  const handleSwitcherClick = useLastCallback((e: React.ChangeEvent) => {
    e.stopPropagation();
    if (isWhitelisted) {
      removeNftSpecialStatus({ address: nft.address });
    } else {
      openUnhideNftModal({ address: nft.address, name: nft.name! });
    }
  });

  return (
    <div
      className={styles.item}
      onClick={handleNftClick}
      key={nft.address}
      role="button"
      tabIndex={0}
      data-nft-address={!areSettingsInModal && nft.address}
    >
      <img className={styles.nftImage} src={nft.image} alt={nft.name} />
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

export default memo(ProbablyScamNft);

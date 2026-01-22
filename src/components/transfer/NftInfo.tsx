import React, { memo, useMemo } from '../../lib/teact/teact';
import { getActions, getGlobal } from '../../global';

import { MediaType, type NftTransfer } from '../../global/types';

import { ANIMATED_STICKER_TINY_SIZE_PX } from '../../config';
import buildClassName from '../../util/buildClassName';
import { openUrl } from '../../util/openUrl';
import { shortenAddress } from '../../util/shortenAddress';
import { getExplorerName, getExplorerNftUrl } from '../../util/url';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';

import styles from './NftInfo.module.scss';

interface OwnProps {
  nft?: NftTransfer;
  isStatic?: boolean;
  withTonExplorer?: boolean;
  // Currently, MediaViewer can only display NFTs that are owned by the user
  withMediaViewer?: boolean;
}

function NftInfo({
  nft, isStatic, withTonExplorer, withMediaViewer,
}: OwnProps) {
  const { openMediaViewer } = getActions();
  const lang = useLang();

  const tonExplorerTitle = useMemo(() => {
    return (lang('Open on %explorer_name%', {
      explorer_name: getExplorerName(),
    }) as string[]
    ).join('');
  }, [lang]);

  const handleClickInfo = (event: React.MouseEvent) => {
    event.stopPropagation();
    const global = getGlobal();
    const url = getExplorerNftUrl(
      undefined,
      nft!.address,
      global.settings.isTestnet,
      global.settings.selectedExplorerIds?.ton,
    )!;

    void openUrl(url);
  };

  const handleClick = useLastCallback(() => {
    openMediaViewer({ mediaId: nft!.address, mediaType: MediaType.Nft });
  });

  if (!nft) {
    return (
      <div className={buildClassName(styles.root, isStatic && styles.rootStatic)}>
        <AnimatedIconWithPreview
          play
          noLoop={false}
          nonInteractive
          size={ANIMATED_STICKER_TINY_SIZE_PX}
          className={styles.thumbnail}
          tgsUrl={ANIMATED_STICKERS_PATHS.wait}
          previewUrl={ANIMATED_STICKERS_PATHS.waitPreview}
        />

        <div className={styles.info}>
          <div className={styles.title}>NFT</div>
          <div className={styles.description}>
            {lang('Name and collection are not available. Please check back later.')}
          </div>
        </div>
      </div>
    );
  }

  const name = nft.name || shortenAddress(nft.address);

  function renderContent() {
    return (
      <>
        <img src={nft!.thumbnail} alt={name} className={styles.thumbnail} />

        <div className={styles.info}>
          <div className={styles.title}>
            {name}
            {
              withTonExplorer && (
                <i
                  className={buildClassName(styles.icon, 'icon-tonexplorer-small')}
                  onClick={handleClickInfo}
                  title={tonExplorerTitle}
                  aria-label={tonExplorerTitle}
                  role="button"
                  tabIndex={0}
                />
              )
            }
          </div>
          <div className={styles.description}>{nft!.collectionName}</div>
        </div>
      </>
    );
  }

  if (!withMediaViewer) {
    return (
      <div className={buildClassName(styles.root, isStatic && styles.rootStatic)}>
        {renderContent()}
      </div>
    );
  }

  return (
    <div
      role="button"
      tabIndex={0}
      aria-label={lang('NFT')}
      className={buildClassName(styles.root, styles.interactive, isStatic && styles.rootStatic)}
      onClick={handleClick}
    >
      {renderContent()}
    </div>
  );
}

export default memo(NftInfo);

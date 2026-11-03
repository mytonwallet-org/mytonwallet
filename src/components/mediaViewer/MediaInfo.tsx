import React, { memo } from '../../lib/teact/teact';
import { withGlobal } from '../../global';

import { MediaType } from '../../global/types';

import { GETGEMS_BASE_MAINNET_URL, GETGEMS_BASE_TESTNET_URL } from '../../config';
import { selectCurrentAccountState } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { handleUrlClick } from '../../util/openUrl';
import { shortenAddress } from '../../util/shortenAddress';

import useLang from '../../hooks/useLang';

import styles from './MediaViewer.module.scss';

type OwnProps = {

  mediaId?: string;
};

type StateProps = {
  title?: string;
  description?: string;
  descriptionUrl?: string;
};

function MediaInfo({ title, description, descriptionUrl }: OwnProps & StateProps) {
  const lang = useLang();

  return (
    <div className={styles.mediaInfo}>
      <span className={styles.mediaInfoTitle}>{title}</span>
      {descriptionUrl && (
        <a
          href={descriptionUrl}
          target="_blank"
          aria-label={lang('Open NFT Collection')}
          className={styles.mediaInfoDescription}
          rel="noreferrer"
          onClick={handleUrlClick}
        >
          <span className={styles.descriptionText}>{description}</span>
          <i className={buildClassName('icon-tooltip', styles.tooltip)} aria-hidden />
        </a>
      )}
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global, { mediaId }): StateProps => {
  const { mediaType = MediaType.Nft } = global.mediaViewer || {};

  // A picture always has news, which `PictureInfo` shows in place of this header
  if (!mediaId || mediaType !== MediaType.Nft) return {};

  const isTestnet = global.settings.isTestnet;

  const getgemsBaseUrl = isTestnet ? GETGEMS_BASE_TESTNET_URL : GETGEMS_BASE_MAINNET_URL;

  const { byAddress } = selectCurrentAccountState(global)?.nfts || {};
  const nft = byAddress?.[mediaId];
  if (!nft) return {};

  return {
    title: nft.name || shortenAddress(nft.address, 4),
    description: nft.collectionName,
    descriptionUrl: `${getgemsBaseUrl}collection/${nft.collectionAddress}`,
  };
})(MediaInfo));

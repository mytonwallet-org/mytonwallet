import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import Image from '../ui/Image';

import styles from './NftImage.module.scss';

interface OwnProps {
  url?: string;
  alt?: string;
  /** Sets the size, the shape and the background shown while the image loads */
  className?: string;
}

function NftImage({ url, alt, className }: OwnProps) {
  return (
    <div className={buildClassName(styles.root, className)}>
      <Image
        url={url}
        alt={alt}
        className={styles.fill}
        imageClassName={styles.image}
        fallbackClassName={styles.noImage}
      />
    </div>
  );
}

export default memo(NftImage);

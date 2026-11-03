import React, {
  memo, useLayoutEffect, useRef, useState,
} from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useLastCallback from '../../hooks/useLastCallback';

import styles from './AgentThreadList.module.scss';

interface OwnProps {
  url: string;
}

// As large as a line of the preview, as in Telegram's chat list
const THUMBNAIL_SIZE = 20; // 1.25 rem

/**
 * The picture of a row's latest content, leading its preview as a photo leads a message in Telegram's chat list.
 * Its place is kept while it loads and if it fails, empty, so the text never moves.
 */
function AgentThreadThumbnail({ url }: OwnProps) {
  const ref = useRef<HTMLImageElement>();
  const [isLoaded, setIsLoaded] = useState(false);

  const handleLoad = useLastCallback(() => {
    setIsLoaded(true);
  });

  // A picture from the cache can be complete before its `load` is listened to
  useLayoutEffect(() => {
    const image = ref.current;
    setIsLoaded(Boolean(image?.complete && image.naturalWidth));
  }, [url]);

  return (
    <img
      ref={ref}
      className={buildClassName(styles.previewThumbnail, isLoaded && styles.previewThumbnailLoaded)}
      src={url}
      alt=""
      width={THUMBNAIL_SIZE}
      height={THUMBNAIL_SIZE}
      loading="lazy"
      decoding="async"
      draggable={false}
      onLoad={handleLoad}
    />
  );
}

export default memo(AgentThreadThumbnail);

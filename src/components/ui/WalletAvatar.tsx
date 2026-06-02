import React, { memo, useEffect, useState } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import buildStyle from '../../util/buildStyle';
import { setCancellableTimeout } from '../../util/schedulers';
import { getAvatarGradientColors } from './helpers/getAvatarGradientColor';
import { getAvatarInitials } from './helpers/getAvatarInitials';

import Image from './Image';

import styles from './WalletAvatar.module.scss';

type OwnProps = {
  title?: string;
  accountId?: string;
  className?: string;
  imageUrl?: string;
};

type ImageState = {
  status: 'idle' | 'loaded' | 'failed' | 'unavailable';
  url?: string;
  retryKey: number;
};

const IMAGE_RETRY_DELAY_MS = 10000;

const WalletAvatar = ({ title, accountId, className, imageUrl }: OwnProps) => {
  const [imageState, setImageState] = useState<ImageState>({ status: 'idle', retryKey: 0 });
  const gradientSource = accountId ?? title ?? '';
  const [startColor, endColor] = getAvatarGradientColors(gradientSource);
  const initials = getAvatarInitials(title);
  const shouldShowImage = Boolean(imageUrl && imageState.url === imageUrl && imageState.status === 'loaded');
  const isCurrentImageUnavailable = imageState.url === imageUrl && imageState.status === 'unavailable';
  const isCurrentImageFailed = imageState.url === imageUrl && imageState.status === 'failed';
  const shouldRenderImage = Boolean(imageUrl && !isCurrentImageUnavailable && !isCurrentImageFailed);

  useEffect(() => {
    setImageState((currentImageState) => {
      if (currentImageState.url === imageUrl) {
        return currentImageState;
      }

      return {
        status: 'idle',
        url: imageUrl,
        retryKey: currentImageState.retryKey + 1,
      };
    });
  }, [imageUrl]);

  useEffect(() => {
    if (!imageUrl || imageState.url !== imageUrl || imageState.status !== 'failed') {
      return undefined;
    }

    const retryImageLoad = () => {
      setImageState((currentImageState) => {
        if (currentImageState.url !== imageUrl || currentImageState.status !== 'failed') {
          return currentImageState;
        }

        return {
          status: 'idle',
          url: imageUrl,
          retryKey: currentImageState.retryKey + 1,
        };
      });
    };

    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') {
        retryImageLoad();
      }
    };

    const clearRetryTimeout = setCancellableTimeout(IMAGE_RETRY_DELAY_MS, retryImageLoad);

    window.addEventListener('focus', retryImageLoad);
    window.addEventListener('online', retryImageLoad);
    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      clearRetryTimeout();
      window.removeEventListener('focus', retryImageLoad);
      window.removeEventListener('online', retryImageLoad);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [imageUrl, imageState]);

  function handleImageLoad(img: HTMLImageElement, requestUrl: string, requestRetryKey: number) {
    const nextStatus = img.naturalWidth <= 1 && img.naturalHeight <= 1 ? 'unavailable' : 'loaded';

    setImageState((currentImageState) => {
      if (currentImageState.url !== requestUrl || currentImageState.retryKey !== requestRetryKey) {
        return currentImageState;
      }

      return { status: nextStatus, url: requestUrl, retryKey: requestRetryKey };
    });
  }

  function handleImageError(requestUrl: string, requestRetryKey: number) {
    setImageState((currentImageState) => {
      if (currentImageState.url !== requestUrl || currentImageState.retryKey !== requestRetryKey) {
        return currentImageState;
      }

      return { status: 'failed', url: requestUrl, retryKey: requestRetryKey };
    });
  }

  return (
    <div
      className={buildClassName(styles.avatar, className, 'rounded-font')}
      style={buildStyle(`--start-color: ${startColor}; --end-color: ${endColor}`)}
    >
      {shouldRenderImage && (
        <Image
          key={`${imageUrl}:${imageState.retryKey}`}
          url={imageUrl}
          alt=""
          className={styles.imageWrapper}
          imageClassName={styles.image}
          loading="eager"
          onLoad={(img) => handleImageLoad(img, imageUrl!, imageState.retryKey)}
          onError={() => handleImageError(imageUrl!, imageState.retryKey)}
        />
      )}
      {!shouldShowImage && initials}
    </div>
  );
};

export default memo(WalletAvatar);

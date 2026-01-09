import React, { memo, useRef } from '../../lib/teact/teact';

import { preloadedImageUrls } from '../../util/preloadImage';

import useFlag from '../../hooks/useFlag';
import useMediaTransition from '../../hooks/useMediaTransition';

interface OwnProps {
  url?: string;
  alt?: string;
  loading?: 'lazy' | 'eager';
  isSlow?: boolean;
  className?: string;
  imageClassName?: string;
  children?: TeactJsx;
  fallback?: TeactJsx;
  onLoad?: NoneToVoidFunction;
}

function ImageComponent({
  url,
  alt = '',
  loading,
  isSlow,
  className,
  imageClassName,
  children,
  fallback,
  onLoad,
}: OwnProps) {
  const ref = useRef<HTMLImageElement>();
  const [isLoaded, markIsLoaded] = useFlag(preloadedImageUrls.has(url));
  const [hasError, markHasError] = useFlag();

  const handleLoad = () => {
    markIsLoaded();
    preloadedImageUrls.add(url);
    onLoad?.();
  };

  const shouldShowFallback = (hasError || !url) && !!fallback;

  const divRef = useMediaTransition(isLoaded || shouldShowFallback);

  return (
    <div ref={divRef} className={className} style={isSlow ? 'transition-duration: 0.5s;' : undefined}>
      {!shouldShowFallback ? (
        <img
          ref={ref}
          src={url}
          alt={alt}
          loading={loading}
          className={imageClassName}
          style="width: 100%;"
          draggable={false}
          referrerPolicy="same-origin"
          onLoad={!isLoaded ? handleLoad : undefined}
          onError={markHasError}
        />
      ) : fallback}
      {children}
    </div>
  );
}

export default memo(ImageComponent);

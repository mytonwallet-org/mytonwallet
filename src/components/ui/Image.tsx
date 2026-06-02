import React, { memo, useCallback, useEffect, useRef } from '../../lib/teact/teact';

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
  forceLoaded?: boolean;
  onLoad?: (img: HTMLImageElement) => void;
  onError?: NoneToVoidFunction;
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
  forceLoaded,
  onLoad,
  onError,
}: OwnProps) {
  const ref = useRef<HTMLImageElement>();
  const notifiedLoadUrlRef = useRef<string>();
  const [isLoaded, markIsLoaded] = useFlag(preloadedImageUrls.has(url));
  const [hasError, markHasError] = useFlag();

  const notifyLoaded = useCallback(async (img: HTMLImageElement) => {
    const loadedUrl = url;
    if (!loadedUrl || notifiedLoadUrlRef.current === loadedUrl) return;

    try {
      await img.decode();
    } catch {
      if (!img.complete || !img.naturalWidth) {
        return;
      }
    }

    if (ref.current !== img || img.getAttribute('src') !== loadedUrl) return;

    markIsLoaded();
    preloadedImageUrls.add(loadedUrl);

    if (notifiedLoadUrlRef.current === loadedUrl) return;
    notifiedLoadUrlRef.current = loadedUrl;
    onLoad?.(img);
  }, [markIsLoaded, onLoad, url]);

  function handleLoad() {
    if (!ref.current) return;

    void notifyLoaded(ref.current);
  }

  function handleError() {
    markHasError();
    onError?.();
  }

  const shouldShowFallback = (hasError || !url) && !!fallback;

  const divRef = useMediaTransition(forceLoaded || isLoaded || shouldShowFallback);

  useEffect(() => {
    const img = ref.current;
    if (!img?.complete || !img.naturalWidth) return;

    void notifyLoaded(img);
  }, [notifyLoaded, url]);

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
          onLoad={handleLoad}
          onError={handleError}
        />
      ) : fallback}
      {children}
    </div>
  );
}

export default memo(ImageComponent);

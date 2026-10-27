import { useEffect, useState } from '../lib/teact/teact';

import type { ApiNft } from '../api/types';

import { getDefaultCardImageUrl } from '../util/card/defaultArtwork';
import { getCachedImageUrl } from '../util/getCachedImageUrl';
import { logDebugError } from '../util/logs';
import { onIdle } from '../util/schedulers';
import { getCardNftImageUrl } from '../util/url';
import useLastCallback from './useLastCallback';

interface CardArtwork {
  nft?: ApiNft;
  imageUrl?: string;
}

// A card that remounts reads the URL during render, before its effects retain it. The pause keeps the URL
// alive across such a remount.
const RELEASE_DELAY_MS = 1000;

// URLs of NFT artwork that has loaded and decoded once, so a remounted card shows it from the first frame. Each
// one is a blob URL that keeps the image file in memory. It is revoked once no mounted card retains it, except for
// the cards of the accounts, which stay ready for a wallet switch.
const readyUrlBySrc = new Map<string, string>();
const loadingBySrc = new Map<string, Promise<string>>();
const retainCountBySrc = new Map<string, number>();
const accountCardSrcs = new Set<string>();

// Nothing is drawn under the card face, so the hook keeps the last loaded artwork until the next one is ready
export default function useCardArtwork(nft?: ApiNft, isGram = false) {
  const defaultImageUrl = getDefaultCardImageUrl(isGram);
  const imageSrc = nft ? getCardNftImageUrl(nft) : defaultImageUrl;
  const [artwork, setArtwork] = useState<CardArtwork>(() => {
    const readyUrl = nft && readyUrlBySrc.get(imageSrc);
    return readyUrl ? { nft, imageUrl: readyUrl } : { imageUrl: defaultImageUrl };
  });
  const getNft = useLastCallback(() => nft);
  const shownSrc = artwork.nft && getCardNftImageUrl(artwork.nft);

  // The requested artwork is retained while it loads, and the shown one until it is replaced
  useRetainCardArtwork(nft && imageSrc);
  useRetainCardArtwork(shownSrc);

  useEffect(() => {
    const nextNft = getNft();
    let isCancelled = false;

    void loadCardArtwork(imageSrc, Boolean(nextNft)).then((imageUrl) => {
      if (isCancelled) return;

      setArtwork((current) => (
        current.nft === nextNft && current.imageUrl === imageUrl ? current : { nft: nextNft, imageUrl }
      ));
    }, (error: unknown) => {
      if (isCancelled) return;

      logDebugError('useCardArtwork', error);
      setArtwork({ imageUrl: defaultImageUrl });
    });

    return () => {
      isCancelled = true;
    };
  }, [imageSrc, defaultImageUrl, getNft]);

  const isRefreshedNft = Boolean(nft && artwork.nft && nft !== artwork.nft
    && artwork.nft.address === nft.address && shownSrc === imageSrc);

  return isRefreshedNft ? { nft, imageUrl: artwork.imageUrl } : artwork;
}

/** The artwork URL for a still card picture. It is shared with `useCardArtwork`, so each image is in memory once. */
export function useCardArtworkUrl(nft?: ApiNft) {
  const src = nft && getCardNftImageUrl(nft);
  const [imageUrl, setImageUrl] = useState(src && readyUrlBySrc.get(src));

  useRetainCardArtwork(src);

  useEffect(() => {
    if (!src) return undefined;

    let isCancelled = false;

    void loadCardArtwork(src, true).then((url) => {
      if (!isCancelled) setImageUrl(url);
    }, (error: unknown) => {
      logDebugError('useCardArtworkUrl', error);
    });

    return () => {
      isCancelled = true;
    };
  }, [src]);

  return src ? imageUrl : undefined;
}

export function preloadCardArtworks(nfts: ApiNft[]) {
  const [nft, ...rest] = nfts;
  if (!nft) return;

  const src = getCardNftImageUrl(nft);
  accountCardSrcs.add(src);

  onIdle(() => {
    void loadCardArtwork(src, true)
      .catch(() => undefined)
      .finally(() => preloadCardArtworks(rest));
  });
}

function useRetainCardArtwork(src?: string) {
  useEffect(() => {
    if (!src) return undefined;

    retainCountBySrc.set(src, (retainCountBySrc.get(src) ?? 0) + 1);

    return () => {
      const count = retainCountBySrc.get(src)! - 1;

      if (count) {
        retainCountBySrc.set(src, count);
      } else {
        retainCountBySrc.delete(src);
        window.setTimeout(() => releaseCardArtwork(src), RELEASE_DELAY_MS);
      }
    };
  }, [src]);
}

function loadCardArtwork(src: string, isNft: boolean) {
  const readyUrl = readyUrlBySrc.get(src);
  if (readyUrl) return Promise.resolve(readyUrl);

  let loading = loadingBySrc.get(src);

  if (!loading) {
    loading = loadCardImage(src, isNft).then((imageUrl) => {
      if (!isNft) return imageUrl;

      readyUrlBySrc.set(src, imageUrl);

      // The cards that asked for it may be gone by now
      releaseCardArtwork(src);

      return imageUrl;
    }).finally(() => {
      loadingBySrc.delete(src);
    });

    loadingBySrc.set(src, loading);
  }

  return loading;
}

function releaseCardArtwork(src: string) {
  const readyUrl = readyUrlBySrc.get(src);
  if (!readyUrl || retainCountBySrc.has(src) || accountCardSrcs.has(src)) return;

  readyUrlBySrc.delete(src);
  URL.revokeObjectURL(readyUrl);
}

async function loadCardImage(src: string, isNft: boolean) {
  const imageUrl = isNft ? await getCachedImageUrl(src) : src;
  const image = new Image();
  image.src = imageUrl;

  try {
    await image.decode();
  } catch (error) {
    if (isNft) URL.revokeObjectURL(imageUrl);
    throw error;
  }

  return imageUrl;
}

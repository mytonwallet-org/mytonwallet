import React, {
  memo,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from '../../../../lib/teact/teact';

import type { ApiNft } from '../../../../api/types';
import type { CardSurfaceLoop } from '../../../../util/card/surfaceLoop';
import type { CardController } from '../../../../util/card/types';

import { forceMutation, requestForcedReflow, requestMutation } from '../../../../lib/fasterdom/fasterdom';
import buildClassName from '../../../../util/buildClassName';
import { loadDefaultCardArtwork } from '../../../../util/card/defaultArtwork';
import { getCardEdgeMasks } from '../../../../util/card/edgeMask';
import { startCardSurface } from '../../../../util/card/surfaceLoop';
import { getCardBorder, getCardSurfaceProfile } from '../../../../util/card/surfaceProfile';
import { loadCardArtworkLayers } from '../../../../util/card/svgLayers';
import { preloadImage } from '../../../../util/preloadImage';

import useLastCallback from '../../../../hooks/useLastCallback';
import useSyncEffect from '../../../../hooks/useSyncEffect';

import styles from './CardSurface.module.scss';

const SWITCH_FADE_MS = 300;

interface OwnProps {
  nft?: ApiNft;
  /** Already decoded artwork of `nft`, or the default artwork without it */
  imageUrl?: string;
  isGram: boolean;
  isDark: boolean;
  isDisabled: boolean;
  noSwitchAnimation?: boolean;
  /** Skips the `--card-depth-*` and `--card-glass-angle` variables where no style reads them */
  noDepth?: boolean;
  controller: CardController;
}

function CardSurface({
  nft,
  imageUrl,
  isGram,
  isDark,
  isDisabled,
  noSwitchAnimation,
  noDepth,
  controller,
}: OwnProps) {
  const artworkRef = useRef<HTMLImageElement>();
  const canvasRef = useRef<HTMLCanvasElement>();
  const switchSnapshotRef = useRef<HTMLCanvasElement>();
  const highlightRef = useRef<HTMLDivElement>();
  const borderBaseRef = useRef<HTMLDivElement>();
  const loopRef = useRef<CardSurfaceLoop>();
  const presentedKeyRef = useRef<string>();
  const [readyArtworkKey, setReadyArtworkKey] = useState<string>();
  const border = useMemo(() => nft && getCardBorder(nft, isDark), [nft, isDark]);
  const profile = useMemo(() => getCardSurfaceProfile(nft, isGram), [nft, isGram]);
  const isBlack = nft?.metadata.mtwCardType === 'black';
  const artworkKey = `${nft?.address ?? 'default'}:${imageUrl ?? ''}:${JSON.stringify(profile)}`;
  const getArtwork = useLastCallback(() => ({ nft, imageUrl, profile, isGram }));
  const getIsDisabled = useLastCallback(() => isDisabled);

  const getBackdrop = useLastCallback(() => {
    if (loopRef.current?.isPresented) return canvasRef.current!;

    const artwork = artworkRef.current;

    return artwork?.complete && artwork.naturalWidth ? artwork : undefined;
  });

  const handlePresent = useLastCallback((tilt: readonly number[], width: number, height: number) => {
    // NFT and Gram cards keep drawing at rest with the same tilt, and every write restyles the whole card
    const key = `${tilt[0]}:${tilt[1]}:${width}:${height}`;
    if (key === presentedKeyRef.current) return;

    presentedKeyRef.current = key;

    const card = controller.cardRef.current!;
    const highlight = border?.angle !== undefined ? highlightRef.current : undefined;
    if (noDepth && !highlight) return;

    forceMutation(() => {
      if (!noDepth) {
        card.style.setProperty('--card-depth-x', `${tilt[0] * 3.5}px`);
        card.style.setProperty('--card-depth-y', `${tilt[1] * 3.5}px`);

        card.style.setProperty(
          '--card-glass-angle',
          `${180 - (Math.atan2(0.65 * tilt[0], 1 + 0.65 * tilt[1]) * 180) / Math.PI}deg`,
        );
      }

      if (!highlight) return;

      const influence = Math.min(1, Math.hypot(tilt[0], tilt[1]));
      const angle = (border!.angle! * Math.PI) / 180;
      const x = Math.cos(angle) * width * 0.5 * (1 - influence) + tilt[0] * width * 0.55;
      const y = Math.sin(angle) * width * 0.5 * (1 - influence) + tilt[1] * height * 0.72;

      highlight.style.transform = `translate(${x}px,${y}px)`
        + ` rotate(${Math.hypot(x, y) > 0.001 ? Math.atan2(y, x) : angle}rad)`
        + ` scale(${isBlack ? '.6,1.3' : '1,.5'})`;
    }, highlight ? [card, highlight] : card);
  });

  // A new artwork key remounts the canvas. This runs during render, while the old canvas is still
  // in the DOM, so its last frame can fade out over the new card.
  useSyncEffect(([prevArtworkKey]) => {
    const snapshot = switchSnapshotRef.current;
    if (!prevArtworkKey || prevArtworkKey === artworkKey || noSwitchAnimation || !snapshot) return;

    const source = getBackdrop();
    if (!source) return;

    copyImage(snapshot, source);
    snapshot.getAnimations().forEach((animation) => animation.cancel());

    snapshot.animate([{ opacity: 1 }, { opacity: 0 }], { duration: SWITCH_FADE_MS, easing: 'ease-in-out' })
      .onfinish = () => {
        requestMutation(() => {
          snapshot.width = 0;
        });
      };
  }, [artworkKey, noSwitchAnimation]);

  useEffect(() => {
    const { nft, imageUrl, profile, isGram } = getArtwork();
    if (!imageUrl) return undefined;

    const layers = nft
      ? loadCardArtworkLayers(imageUrl).then(async (split) => split ?? {
        base: await preloadImage(imageUrl),
        spots: [],
        contrastColor: -1,
        contrastOpacity: 0,
      })
      : loadDefaultCardArtwork(isGram);
    const loop = startCardSurface({
      canvas: canvasRef.current!,
      card: controller.cardRef.current!,
      profile,
      layers,
      controller,
      getIsDisabled,
      onPresent: handlePresent,
      onReadyChange: (isReady) => setReadyArtworkKey(isReady ? artworkKey : undefined),
    });
    loopRef.current = loop;
    controller.wakeSurface = loop.wake;
    controller.getBackdrop = getBackdrop;

    return () => {
      loop.stop();
      loopRef.current = undefined;
      controller.wakeSurface = undefined;
      controller.getBackdrop = undefined;
    };
  }, [artworkKey, controller, getArtwork, getBackdrop, getIsDisabled, handlePresent]);

  useEffect(() => {
    // A border change mounts a new highlight element without a transform. `handlePresent` skips a frame
    // with the same tilt, so the key is reset to let the next frame write the transform.
    presentedKeyRef.current = undefined;
    loopRef.current?.refresh();
  }, [isDisabled, border]);

  useLayoutEffect(() => {
    const card = controller.cardRef.current!;
    let appliedGeometry = '';

    // Masks are large data URLs, and even reassigning the same one restyles the card
    function measure() {
      const width = card.clientWidth;
      const height = card.clientHeight;
      if (!width || !height) return undefined;

      const radius = parseFloat(getComputedStyle(card).borderTopLeftRadius) || 0;
      const geometry = `${width}:${height}:${radius}:${devicePixelRatio}`;
      if (geometry === appliedGeometry) return undefined;

      appliedGeometry = geometry;

      const masks = getCardEdgeMasks(width, height, radius, isBlack ? 2 : 1.333, devicePixelRatio);

      return () => {
        card.style.setProperty('--card-face-mask', masks.face);
        card.style.setProperty('--card-rim-mask', masks.rim);
        card.style.setProperty('--card-physical-pixel', `${1 / (devicePixelRatio || 1)}px`);

        if (border && borderBaseRef.current) {
          borderBaseRef.current.style.backgroundImage = border.backgroundForSize(width, height, 1);
        }
      };
    }

    function update() {
      const write = measure();
      if (write) forceMutation(write, borderBaseRef.current ? [card, borderBaseRef.current] : card);
    }

    // Without masks the artwork has square corners, since the card does not clip its content. A just mounted
    // card gets them in the same frame, before it is painted.
    requestForcedReflow(measure);

    const observer = new ResizeObserver(update);
    observer.observe(card);
    window.addEventListener('resize', update);

    return () => {
      observer.disconnect();
      window.removeEventListener('resize', update);
    };
  }, [border, controller, isBlack]);

  const isSurfaceReady = readyArtworkKey === artworkKey;

  return (
    <>
      <img
        ref={artworkRef}
        className={buildClassName(styles.artwork, isSurfaceReady && styles.fallbackCovered)}
        src={imageUrl}
        alt=""
        aria-hidden
      />
      <canvas
        key={artworkKey}
        ref={canvasRef}
        aria-hidden
        className={buildClassName(
          styles.artwork,
          styles.surface,
          isDisabled && styles.noMotion,
          isSurfaceReady && styles.ready,
        )}
      />
      <canvas ref={switchSnapshotRef} className={buildClassName(styles.artwork, styles.switchSnapshot)} aria-hidden />
      {border && (
        <div className={styles.border} aria-hidden>
          <div ref={borderBaseRef} className={styles.borderBase} />
          {border.angle !== undefined && (
            <div
              ref={highlightRef}
              className={buildClassName(styles.borderLight, isBlack && styles.borderLightBlack)}
            />
          )}
        </div>
      )}
    </>
  );
}

export default memo(CardSurface);

// The copy keeps the source resolution; `object-fit: cover` fits it to the card like the source itself
function copyImage(canvas: HTMLCanvasElement, source: HTMLCanvasElement | HTMLImageElement) {
  canvas.width = source instanceof HTMLImageElement ? source.naturalWidth : source.width;
  canvas.height = source instanceof HTMLImageElement ? source.naturalHeight : source.height;
  canvas.getContext('2d')!.drawImage(source, 0, 0);
}

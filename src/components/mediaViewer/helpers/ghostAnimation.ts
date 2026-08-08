import type { HiddenNftsSection } from '../../../global/types';
import { MediaType } from '../../../global/types';

import { ANIMATION_END_DELAY, MOBILE_SCREEN_MAX_WIDTH } from '../../../config';
import { requestMutation } from '../../../lib/fasterdom/fasterdom';
import { applyStyles } from '../../../util/animation';
import { stopEvent } from '../../../util/domEvents';
import { isElementInViewport } from '../../../util/isElementInViewport';
import { REM } from '../../../util/windowEnvironment';
import windowSize from '../../../util/windowSize';

import styles from '../MediaViewer.module.scss';

export const ANIMATION_DURATION = 200;

// Header height + bottom padding, keep in sync with styles.image max-height
const OCCUPIED_HEIGHT = 14 * REM;

export function animateOpening(
  type: MediaType, mediaId: string, mediaUrl?: string, txId?: string, hiddenNfts?: HiddenNftsSection,
) {
  const { image: fromImage } = getNode(type, mediaId, txId, hiddenNfts);
  if (!fromImage || !mediaUrl) {
    return;
  }

  requestMutation(async () => {
    document.body.classList.add('ghost-animating');

    const { width: windowWidth, height: windowHeight } = windowSize.get();
    const { width: mediaWidth, height: mediaHeight } = await getImageDimension(mediaUrl);

    const availableHeight = windowHeight - OCCUPIED_HEIGHT;
    const offsetTop = (windowWidth <= MOBILE_SCREEN_MAX_WIDTH ? 8 : 7) * REM;

    const { width: toWidth, height: toHeight } = calculateDimensions(
      windowWidth,
      availableHeight,
      mediaWidth,
      mediaHeight,
    );

    const toLeft = (windowWidth - toWidth) / 2;
    const toTop = offsetTop + (availableHeight - toHeight) / 2;

    const {
      top: fromTop, left: fromLeft, width: fromWidth, height: fromHeight,
    } = fromImage.getBoundingClientRect();

    const fromTranslateX = (fromLeft + fromWidth / 2) - (toLeft + toWidth / 2);
    const fromTranslateY = (fromTop + fromHeight / 2) - (toTop + toHeight / 2);
    const fromScaleX = fromWidth / toWidth;
    const fromScaleY = fromHeight / toHeight;

    requestMutation(() => {
      const ghost = createGhost(fromImage);
      applyShape(ghost, type, true);
      applyStyles(ghost, {
        top: `${toTop}px`,
        left: `${toLeft}px`,
        width: `${toWidth}px`,
        height: `${toHeight}px`,
        transform: `translate3d(${fromTranslateX}px, ${fromTranslateY}px, 0) scale(${fromScaleX}, ${fromScaleY})`,
      });

      document.body.appendChild(ghost);

      requestMutation(() => {
        ghost.style.transform = '';
        clearShape(ghost, type, true);

        setTimeout(() => {
          requestMutation(() => {
            if (document.body.contains(ghost)) {
              document.body.removeChild(ghost);
            }
            document.body.classList.remove('ghost-animating');
          });
        }, ANIMATION_DURATION + ANIMATION_END_DELAY);
      });
    });
  });
}

export function animateClosing(type: MediaType, mediaId: string, txId?: string, hiddenNfts?: HiddenNftsSection) {
  const { container, image: toImage } = getNode(type, mediaId, txId, hiddenNfts);
  const fromImage = document.querySelector<HTMLImageElement>(
    `.${styles.slide_active} img, .${styles.slide_active} canvas`,
  );
  if (!fromImage || !toImage) {
    return;
  }

  const {
    top: fromTop, left: fromLeft, width: fromWidth, height: fromHeight,
  } = fromImage.getBoundingClientRect();
  const {
    top: targetTop, left: toLeft, width: toWidth, height: toHeight,
  } = toImage.getBoundingClientRect();

  let toTop = targetTop;
  if (!isElementInViewport(toImage)) {
    const { height: windowHeight } = windowSize.get();
    toTop = targetTop < fromTop ? -toHeight : windowHeight;
  }

  const fromTranslateX = (fromLeft + fromWidth / 2) - (toLeft + toWidth / 2);
  const fromTranslateY = (fromTop + fromHeight / 2) - (toTop + toHeight / 2);
  const fromScaleX = fromWidth / toWidth;
  const fromScaleY = fromHeight / toHeight;

  const existingGhost = document.querySelector<HTMLDivElement>(`.${styles.ghost}`);
  const ghost = existingGhost || createGhost(fromImage);

  let ghostStyles: Record<string, string>;
  if (existingGhost) {
    const {
      top, left, width, height,
    } = existingGhost.getBoundingClientRect();
    const scaleX = width / toWidth;
    const scaleY = height / toHeight;

    ghostStyles = {
      transition: 'none',
      top: `${toTop}px`,
      left: `${toLeft}px`,
      transformOrigin: 'top left',
      transform: `translate3d(${left - toLeft}px, ${top - toTop}px, 0) scale(${scaleX}, ${scaleY})`,
      width: `${toWidth}px`,
      height: `${toHeight}px`,
    };
  } else {
    ghostStyles = {
      top: `${toTop}px`,
      left: `${toLeft}px`,
      width: `${toWidth}px`,
      height: `${toHeight}px`,
      transform: `translate3d(${fromTranslateX}px, ${fromTranslateY}px, 0) scale(${fromScaleX}, ${fromScaleY})`,
    };
  }

  requestMutation(() => {
    applyShape(ghost, type);
    applyStyles(ghost, ghostStyles);
    if (!existingGhost) document.body.appendChild(ghost);
    document.body.classList.add('ghost-animating');
    if (container) {
      container.classList.add('ghost-target');
    }

    requestMutation(() => {
      if (existingGhost) {
        existingGhost.style.transition = '';
      }

      ghost.style.transform = '';

      setTimeout(() => {
        requestMutation(() => {
          if (document.body.contains(ghost)) {
            document.body.removeChild(ghost);
          }
          document.body.classList.remove('ghost-animating');
          if (container) {
            container.classList.remove('ghost-target');
          }
        });
      }, ANIMATION_DURATION + ANIMATION_END_DELAY);
    });
  });
}

function getNode(type: MediaType, mediaId: string, txId?: string, hiddenNfts?: HiddenNftsSection) {
  let image: HTMLImageElement | HTMLCanvasElement | undefined;
  let container: HTMLElement | undefined;
  if (type === MediaType.Nft) {
    container = document.querySelector(
      txId
        ? `.transaction-nft[data-tx-id="${txId}"][data-nft-address="${mediaId}"]`
        : hiddenNfts
          ? `.hidden-nfts-${hiddenNfts} [data-nft-address="${mediaId}"]`
          : `.nft-container[data-nft-address="${mediaId}"]`,
    ) as HTMLElement;
    image = container?.querySelector('img, canvas') as HTMLImageElement | HTMLCanvasElement;
  }
  return { container, image };
}

function createGhost(source: HTMLImageElement | HTMLCanvasElement) {
  const ghost = document.createElement('div');
  ghost.classList.add(styles.ghost);

  const img = new Image();
  img.classList.add(styles.ghostImage);
  img.draggable = false;
  img.oncontextmenu = stopEvent;
  img.src = source instanceof HTMLImageElement
    ? source.src
    : source.parentElement?.parentElement?.dataset.previewUrl || '';

  ghost.appendChild(img);

  return ghost;
}

function calculateDimensions(
  availableWidth: number,
  availableHeight: number,
  mediaWidth: number,
  mediaHeight: number,
) {
  const aspectRatio = mediaHeight / mediaWidth;
  const calculatedWidth = Math.min(mediaWidth, availableWidth);
  const calculatedHeight = Math.round(calculatedWidth * aspectRatio);

  if (calculatedHeight > availableHeight) {
    return {
      width: Math.round(availableHeight / aspectRatio),
      height: availableHeight,
    };
  }

  return {
    width: calculatedWidth,
    height: Math.round(calculatedWidth * aspectRatio),
  };
}

function applyShape(ghost: HTMLDivElement, type: MediaType, isOpening = false) {
  if (type === MediaType.Nft) {
    ghost.classList.add(isOpening ? styles.ghost_roundedOpening : styles.ghost_roundedClosing);
  }
}

function clearShape(ghost: HTMLDivElement, type: MediaType, isOpening = false) {
  if (type === MediaType.Nft) {
    ghost.classList.remove(isOpening ? styles.ghost_roundedOpening : styles.ghost_roundedClosing);
  }
}

async function getImageDimension(url: string) {
  const img = new Image();
  img.src = url;
  await new Promise((resolve) => {
    img.onload = resolve;
  });
  return { width: img.width, height: img.height };
}

import type { HiddenNftsSection } from '../../../global/types';
import { MediaType } from '../../../global/types';

import { ANIMATION_END_DELAY, MOBILE_SCREEN_MAX_WIDTH } from '../../../config';
import { requestMutation } from '../../../lib/fasterdom/fasterdom';
import { applyStyles } from '../../../util/animation';
import { stopEvent } from '../../../util/domEvents';
import { isElementInViewport } from '../../../util/isElementInViewport';
import { IS_TOUCH_ENV, REM } from '../../../util/windowEnvironment';
import windowSize from '../../../util/windowSize';
import getAgentHeaderBottom from '../../agent/helpers/getAgentHeaderBottom';

import styles from '../MediaViewer.module.scss';

export const ANIMATION_DURATION = 200;
// The attribute that ties a picture on the page to its id in the viewer, so the viewer opens from it and closes to it
const MEDIA_VIEWER_PICTURE_ID_ATTRIBUTE = 'data-media-viewer-picture-id';

// Header height + bottom padding, keep in sync with styles.image max-height
const OCCUPIED_HEIGHT = 14 * REM;
// The height a picture leaves to the viewer's header and caption, as Telegram's media viewer does for a photo; keep in
// sync with `styles.picture` and `styles.picture_withCaption`
const PICTURE_OCCUPIED_HEIGHT = 8.25 * REM;
const PICTURE_WITH_CAPTION_OCCUPIED_HEIGHT = 12.5 * REM;
const PICTURE_WITH_CAPTION_SHORT_OCCUPIED_HEIGHT = 10 * REM;
const SHORT_WINDOW_HEIGHT = 640;

export function animateOpening(
  type: MediaType,
  mediaId: string,
  mediaUrl?: string,
  txId?: string,
  hiddenNfts?: HiddenNftsSection,
  hasCaption = false,
) {
  const { image: fromImage } = getNode(type, mediaId, txId, hiddenNfts);
  if (!fromImage || !mediaUrl) {
    return;
  }

  requestMutation(async () => {
    document.body.classList.add('ghost-animating');

    const { width: windowWidth, height: windowHeight } = windowSize.get();
    const { width: mediaWidth, height: mediaHeight } = await getImageDimension(mediaUrl);

    // A picture stands in the middle of the window; an NFT stands under the header, over its description
    const isPicture = type !== MediaType.Nft;
    const occupiedHeight = isPicture ? getPictureOccupiedHeight(windowHeight, hasCaption) : OCCUPIED_HEIGHT;
    const availableHeight = windowHeight - occupiedHeight;
    const offsetTop = (windowWidth <= MOBILE_SCREEN_MAX_WIDTH ? 8 : 7) * REM;

    const { width: toWidth, height: toHeight } = calculateDimensions(
      windowWidth,
      availableHeight,
      mediaWidth,
      mediaHeight,
    );

    const toLeft = (windowWidth - toWidth) / 2;
    const toTop = isPicture ? (windowHeight - toHeight) / 2 : offsetTop + (availableHeight - toHeight) / 2;

    const {
      top: fromTop, left: fromLeft, width: fromWidth, height: fromHeight,
    } = fromImage.getBoundingClientRect();

    const fromTranslateX = (fromLeft + fromWidth / 2) - (toLeft + toWidth / 2);
    const fromTranslateY = (fromTop + fromHeight / 2) - (toTop + toHeight / 2);
    const fromScaleX = fromWidth / toWidth;
    const fromScaleY = fromHeight / toHeight;
    const clipTop = isPicture ? getAgentHeaderBottom(fromLeft, fromLeft + fromWidth) : undefined;

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

      appendGhost(ghost, clipTop);

      requestMutation(() => {
        ghost.style.transform = '';
        clearShape(ghost, type, true);

        setTimeout(() => {
          requestMutation(() => {
            removeGhost(ghost);
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
  const clipTop = type !== MediaType.Nft ? getAgentHeaderBottom(toLeft, toLeft + toWidth) : undefined;

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
    if (existingGhost) {
      clipGhost(existingGhost, clipTop);
    } else {
      appendGhost(ghost, clipTop);
    }
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
          removeGhost(ghost);
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
  } else {
    // A picture given to the viewer is found by its id, which the picture on the page carries
    image = document.querySelector<HTMLImageElement>(`img[${MEDIA_VIEWER_PICTURE_ID_ATTRIBUTE}="${mediaId}"]`)
      ?? undefined;
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

// A picture from the Agent flies to and from the viewer under the Agent's header, which stays over the feed and the
// discussion
function appendGhost(ghost: HTMLElement, clipTop?: number) {
  if (!clipTop) {
    document.body.appendChild(ghost);
    return;
  }

  const host = document.createElement('div');
  host.classList.add(styles.ghostHost);
  host.appendChild(ghost);
  document.body.appendChild(host);
  clipGhost(ghost, clipTop);
}

function clipGhost(ghost: HTMLElement, clipTop?: number) {
  const host = ghost.parentElement;
  if (host?.classList.contains(styles.ghostHost)) host.style.clipPath = clipTop ? `inset(${clipTop}px 0 0 0)` : '';
}

function removeGhost(ghost: HTMLElement) {
  const host = ghost.parentElement;
  (host?.classList.contains(styles.ghostHost) ? host : ghost).remove();
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

// A caption takes room under the picture on a desktop and lies over it on a touch screen
function getPictureOccupiedHeight(windowHeight: number, hasCaption: boolean) {
  if (!hasCaption || IS_TOUCH_ENV) return PICTURE_OCCUPIED_HEIGHT;

  return windowHeight <= SHORT_WINDOW_HEIGHT
    ? PICTURE_WITH_CAPTION_SHORT_OCCUPIED_HEIGHT
    : PICTURE_WITH_CAPTION_OCCUPIED_HEIGHT;
}

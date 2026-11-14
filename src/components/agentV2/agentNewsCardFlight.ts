import { addExtraClass, removeExtraClass } from '../../lib/teact/teact-dom';

import { requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import { animate } from '../../util/animation';
import { clamp } from '../../util/math';
import getAgentHeaderBottom from '../agent/helpers/getAgentHeaderBottom';

import styles from './AgentNews.module.scss';

interface Frame {
  left: number;
  top: number;
  width: number;
  height: number;
}

/**
 * The flying card. `frame`, `shadow` and `tail` keep the card's size and are scaled to the current one, and `layers`
 * and the tail's shape are scaled back, so that the copies inside keep their own size while the frame clips them, and
 * the bubble's tail at the frame's corner keeps its own.
 */
interface FlightElements {
  root: HTMLElement;
  frame: HTMLElement;
  shadow: HTMLElement;
  tail: HTMLElement;
  layers: HTMLElement[];
  from: Frame;
  /** The frame's corner radius, read once its styles apply */
  radius?: number;
}

/** The picture of a bubble that its copy draws, with the size the bubble shows it at */
interface Picture {
  /** A loaded picture of the same address, which is the bubble's own or the card's */
  source: HTMLImageElement;
  width: number;
  height: number;
}

/** The window's height and the edges of the Agent's header and composer, which the flight passes under */
interface ChromeEdges {
  top: number;
  bottom: number;
  viewportHeight: number;
}

/** The edges the flight is clipped to, which are written again only when they change */
interface ChromeClip {
  edges?: ChromeEdges;
}

// The card waits where it was until the chat lays out the post, and dissolves if the post never shows
const HOLD_TIMEOUT = 2000;
// A post whose row reloads keeps its last place as the target for a while
const LOST_TARGET_TIMEOUT = 500;
const DISSOLVE_DURATION = 250;
// The lift peaks halfway through its 0.42 s, the same span over which the card turns into the post
const LIFT_DURATION = 0.42;
const LIFT_SCALE = 0.08;
const MAX_PITCH_DEG = 16;
const MAX_YAW_DEG = 8;
const PITCH_DISTANCE = 120;
const YAW_DISTANCE = 160;
const PERSPECTIVE = 900;
const SHADOW_OPACITY = 0.22;
// Shares of the turn: the card fades into the post's stand-in over its middle, and the stand-in shows from early on
const CARD_FADE_START = 0.3;
const CARD_FADE_END = 0.7;
const STAND_IN_FADE_START = 0.05;
const STAND_IN_FADE_END = 0.4;
// `GlassSpring(dampingRatio: 0.7, response: 0.55)` of the mobile app, at rest once it is this close
const SPRING_DAMPING_RATIO = 0.7;
const SPRING_RESPONSE = 0.55;
const SPRING_REST_DISTANCE = 0.01;
const TARGET_REST_DISTANCE = 0.5;
const SPRING_ANGULAR_FREQUENCY = (2 * Math.PI) / SPRING_RESPONSE;
const SPRING_DECAY = SPRING_DAMPING_RATIO * SPRING_ANGULAR_FREQUENCY;
const SPRING_DAMPED_FREQUENCY = SPRING_ANGULAR_FREQUENCY * Math.sqrt(1 - SPRING_DAMPING_RATIO ** 2);
// The flying card fades out over these distances, in px, as it passes under the header and over the composer
const HEADER_FADE_DISTANCE = 18;
const COMPOSER_FADE_DISTANCE = 28;

// The posts whose cards are on their way, with what waits for them to land
const landingWaitersByPostKey = new Map<string, Set<NoneToVoidFunction>>();

/** Names a discussion's post, the news item's or the digest's, which its card in the feed flies into */
export function getAgentNewsPostKey(post: { eventId: number } | { id: string }) {
  return 'eventId' in post ? `news-${post.eventId}` : `digest-${post.id}`;
}

/**
 * Telegram's message flight: the card of a news item or a digest lifts off the feed and lands in the chat that opens
 * to discuss it, turning into the post on the way, while the chat slides in. The post's suggestions then come in, as
 * an answer's do.
 */
export function startAgentNewsCardFlight(card: HTMLElement, postKey: string) {
  // A card still on its way lands in the post of the chat that opened last, so the same post does not fly twice
  if (landingWaitersByPostKey.has(postKey)) return;

  landingWaitersByPostKey.set(postKey, new Set());
  requestMeasure(() => {
    const rect = card.getBoundingClientRect();
    const from: Frame = {
      left: rect.left, top: rect.top, width: rect.width, height: rect.height,
    };
    const chromeEdges = measureChromeEdges(rect.left, rect.right);
    const picture = measurePicture(card, card);

    requestMutation(() => {
      const root = document.createElement('div');
      root.className = styles.flight;
      root.setAttribute('aria-hidden', 'true');
      const shadow = document.createElement('div');
      shadow.className = styles.flightShadow;
      const frame = document.createElement('div');
      frame.className = styles.flightFrame;
      const tail = document.createElement('div');
      tail.className = styles.flightTail;
      [shadow, frame, tail].forEach((element) => {
        element.style.width = `${from.width}px`;
        element.style.height = `${from.height}px`;
      });
      const cardLayer = createLayer(card, from.width, picture);
      frame.appendChild(cardLayer);
      root.append(shadow, frame, tail);
      const clip: ChromeClip = {};
      clipUnderChrome(root, clip, chromeEdges);
      document.body.appendChild(root);
      const elements: FlightElements = {
        root, frame, shadow, tail, layers: [cardLayer], from,
      };
      applyFrame(elements, from, 0, 0, 0);
      addExtraClass(card, styles.flightSource);

      fly({
        card, postKey, elements, cardLayer, clip,
      });
    });
  });
}

function fly({
  card, postKey, elements, cardLayer, clip,
}: {
  card: HTMLElement;
  postKey: string;
  elements: FlightElements;
  cardLayer: HTMLElement;
  clip: ChromeClip;
}) {
  const { root, frame, from } = elements;
  const startedAt = Date.now();
  let takeoffAt: number | undefined;
  let postMessage: HTMLElement | undefined;
  let standInLayer: HTMLElement | undefined;
  let target: Frame | undefined;
  let targetSeenAt = startedAt;

  animate(() => {
    const now = Date.now();
    elements.radius ??= parseFloat(getComputedStyle(frame).borderTopLeftRadius) || 0;
    const found = findPost(postKey);
    if (found) {
      const rect = found.bubble.getBoundingClientRect();
      if (rect.width && rect.height) {
        target = {
          left: rect.left, top: rect.top, width: rect.width, height: rect.height,
        };
        targetSeenAt = now;
        if (!postMessage) {
          postMessage = found.message;
          takeoffAt = now;
          const bubble = found.bubble;
          const width = rect.width;
          const picture = measurePicture(bubble, card);
          requestMutation(() => {
            addExtraClass(postMessage!, styles.flightTarget);
            standInLayer = createLayer(bubble, width, picture);
            standInLayer.style.opacity = '0';
            frame.appendChild(standInLayer);
            elements.layers.push(standInLayer);
          });
        }
      }
    }

    if (takeoffAt === undefined || !target) {
      if (now - startedAt < HOLD_TIMEOUT) {
        const chromeEdges = measureChromeEdges(from.left, from.left + from.width);
        requestMutation(() => clipUnderChrome(root, clip, chromeEdges));
        return true;
      }
      dissolve(postKey, root, card, postMessage);
      return false;
    }

    if (now - targetSeenAt > LOST_TARGET_TIMEOUT) {
      dissolve(postKey, root, card, postMessage);
      return false;
    }

    const time = (now - takeoffAt) / 1000;
    const progress = getSpringProgress(time);
    const current = interpolateFrame(from, target, progress);
    const lift = time < LIFT_DURATION ? Math.sin((Math.PI * time) / LIFT_DURATION) : 0;
    const distanceX = target.left - from.left;
    const distanceY = target.top - from.top;
    // The edge it flies toward dips away
    const pitch = -Math.sign(distanceY) * MAX_PITCH_DEG * lift * Math.min(1, Math.abs(distanceY) / PITCH_DISTANCE);
    const yaw = MAX_YAW_DEG * lift * clamp(distanceX / YAW_DISTANCE, -1, 1);
    const turn = Math.min(1, time / LIFT_DURATION);
    const chromeEdges = measureChromeEdges(current.left, current.left + current.width);
    const isLanded = time >= LIFT_DURATION
      && Math.abs(1 - progress) < SPRING_REST_DISTANCE
      && Math.abs(current.left - target.left) < TARGET_REST_DISTANCE
      && Math.abs(current.top - target.top) < TARGET_REST_DISTANCE;

    requestMutation(() => {
      if (isLanded) {
        land(postKey, root, card, postMessage!);
        return;
      }

      clipUnderChrome(root, clip, chromeEdges);
      applyFrame(elements, current, lift, pitch, yaw);
      cardLayer.style.opacity = String(1 - interpolateSmoothly(CARD_FADE_START, CARD_FADE_END, turn));
      if (standInLayer) {
        standInLayer.style.opacity = String(interpolateSmoothly(STAND_IN_FADE_START, STAND_IN_FADE_END, turn));
      }
    });

    return !isLanded;
  }, requestMeasure);
}

// The flight is clipped in window coordinates, so the clip stays put while both screens slide underneath it
function clipUnderChrome(root: HTMLElement, clip: ChromeClip, edges: ChromeEdges) {
  const { top, bottom, viewportHeight } = edges;
  if (
    clip.edges?.top === top && clip.edges.bottom === bottom && clip.edges.viewportHeight === viewportHeight
  ) {
    return;
  }

  clip.edges = edges;
  const headerFadeEnd = top + HEADER_FADE_DISTANCE;
  root.style.clipPath = `inset(${top}px 0 ${Math.max(0, viewportHeight - bottom)}px 0)`;
  root.style.maskImage = `linear-gradient(to bottom, transparent ${top}px, black ${headerFadeEnd}px,`
    + ` black ${Math.max(headerFadeEnd, bottom - COMPOSER_FADE_DISTANCE)}px, transparent ${bottom}px)`;
}

// Runs in a measure phase
function measureChromeEdges(left: number, right: number): ChromeEdges {
  const viewportHeight = window.innerHeight;

  return {
    top: getAgentHeaderBottom(left, right) ?? 0,
    bottom: getComposerTop(viewportHeight),
    viewportHeight,
  };
}

// The last composer on the screen is the chat coming in
function getComposerTop(viewportHeight: number) {
  const composers = document.querySelectorAll<HTMLElement>('[data-agent-composer]');
  for (let index = composers.length - 1; index >= 0; index--) {
    const rect = composers[index].getBoundingClientRect();
    if (rect.width > 0 && rect.bottom > 0 && rect.top < viewportHeight) return rect.top;
  }

  return viewportHeight;
}

// Runs in a measure phase. The post's picture may still be loading while the card shows the same one.
function measurePicture(bubble: HTMLElement, card: HTMLElement): Picture | undefined {
  const image = bubble.querySelector('img');
  if (!image) return undefined;

  const source = [image, card.querySelector('img')].find((candidate) => (
    candidate?.src === image.src && candidate.complete && candidate.naturalWidth > 0
  ));
  if (!source || image.clientWidth <= 0 || image.clientHeight <= 0) return undefined;

  return { source, width: image.clientWidth, height: image.clientHeight };
}

/**
 * A copy of the bubble, at its own width, without the tail, which the flight draws at the frame's corner. Its picture
 * is drawn from one already shown, since a new `img` may load and decode the picture again first, with the placeholder
 * in its place.
 */
function createLayer(source: HTMLElement, width: number, picture?: Picture) {
  const layer = source.cloneNode(true) as HTMLElement;
  layer.removeAttribute('data-agent-news-event-id');
  layer.removeAttribute('data-agent-news-digest-id');
  layer.classList.add(styles.flightLayer);
  layer.style.width = `${width}px`;
  const image = layer.querySelector('img');
  const canvas = picture && image ? drawPicture(picture, image.className) : undefined;
  if (canvas) image!.replaceWith(canvas);
  return layer;
}

// The loaded picture, drawn at once, as `object-fit: cover` lays it out; without a 2D context the copy keeps its `img`
function drawPicture({ source, width, height }: Picture, className: string) {
  const canvas = document.createElement('canvas');
  canvas.className = className;
  canvas.width = Math.round(width * window.devicePixelRatio);
  canvas.height = Math.round(height * window.devicePixelRatio);
  const scale = Math.max(canvas.width / source.naturalWidth, canvas.height / source.naturalHeight);
  const drawnWidth = source.naturalWidth * scale;
  const drawnHeight = source.naturalHeight * scale;
  const context = canvas.getContext('2d');
  if (!context) return undefined;

  context.imageSmoothingQuality = 'high';
  context.drawImage(
    source, (canvas.width - drawnWidth) / 2, (canvas.height - drawnHeight) / 2, drawnWidth, drawnHeight,
  );
  return canvas;
}

// The frame turns about its centre, as it would at the current size, and its corners are scaled back to stay round
function applyFrame(
  {
    frame, shadow, tail, layers, from, radius,
  }: FlightElements,
  {
    left, top, width, height,
  }: Frame,
  lift: number,
  pitch: number,
  yaw: number,
) {
  const scaleX = width / from.width;
  const scaleY = height / from.height;
  const liftScale = 1 + LIFT_SCALE * lift;
  const transform = `translate3d(${left + (width - from.width) / 2}px, ${top + (height - from.height) / 2}px, 0) `
    + `perspective(${PERSPECTIVE}px) rotateX(${pitch}deg) rotateY(${yaw}deg) `
    + `scale(${scaleX * liftScale}, ${scaleY * liftScale})`;

  frame.style.transform = transform;
  shadow.style.transform = transform;
  shadow.style.opacity = String(SHADOW_OPACITY * lift);
  tail.style.transform = transform;
  tail.style.setProperty('--flight-tail-scale', `${1 / scaleX} ${1 / scaleY}`);
  if (radius) frame.style.setProperty('--flight-frame-radius', `${radius / scaleX}px / ${radius / scaleY}px`);
  layers.forEach((layer) => {
    layer.style.transform = `scale(${1 / scaleX}, ${1 / scaleY})`;
  });
}

/** Calls `onLanded` once the card flying to the post has turned into it, or at once when none is flying */
export function waitForAgentNewsCardLanding(postKey: string, onLanded: NoneToVoidFunction) {
  const waiters = landingWaitersByPostKey.get(postKey);
  if (!waiters) {
    onLanded();
    return undefined;
  }

  waiters.add(onLanded);
  return () => {
    waiters.delete(onLanded);
  };
}

export function getIsAgentNewsCardFlying(postKey: string) {
  return landingWaitersByPostKey.has(postKey);
}

// The post shows at once under the card that turned into it
function land(postKey: string, root: HTMLElement, card: HTMLElement, postMessage: HTMLElement) {
  root.remove();
  removeExtraClass(postMessage, styles.flightTarget);
  removeExtraClass(card, styles.flightSource);
  finishFlight(postKey);
}

function dissolve(postKey: string, root: HTMLElement, card: HTMLElement, postMessage?: HTMLElement) {
  requestMutation(() => {
    addExtraClass(root, styles.flightDissolving);
    if (postMessage) removeExtraClass(postMessage, styles.flightTarget);
    finishFlight(postKey);
  });
  window.setTimeout(() => {
    requestMutation(() => {
      root.remove();
      removeExtraClass(card, styles.flightSource);
    });
  }, DISSOLVE_DURATION);
}

function finishFlight(postKey: string) {
  const waiters = landingWaitersByPostKey.get(postKey);
  landingWaitersByPostKey.delete(postKey);
  waiters?.forEach((onLanded) => onLanded());
}

// The last copy is the chat coming in, should the one going out still show the same post
function findPost(postKey: string) {
  const messages = document.querySelectorAll<HTMLElement>(`[data-agent-news-post-key="${CSS.escape(postKey)}"]`);
  const message = messages[messages.length - 1];
  const bubble = message?.querySelector<HTMLElement>('[data-agent-news-post-bubble]');
  return message && bubble ? { message, bubble } : undefined;
}

function getSpringProgress(time: number) {
  const oscillation = Math.cos(SPRING_DAMPED_FREQUENCY * time)
    + (SPRING_DECAY / SPRING_DAMPED_FREQUENCY) * Math.sin(SPRING_DAMPED_FREQUENCY * time);
  return 1 - Math.exp(-SPRING_DECAY * time) * oscillation;
}

function interpolateFrame(from: Frame, to: Frame, progress: number): Frame {
  return {
    left: from.left + (to.left - from.left) * progress,
    top: from.top + (to.top - from.top) * progress,
    width: from.width + (to.width - from.width) * progress,
    height: from.height + (to.height - from.height) * progress,
  };
}

function interpolateSmoothly(edgeStart: number, edgeEnd: number, value: number) {
  const progress = clamp((value - edgeStart) / (edgeEnd - edgeStart), 0, 1);
  return progress * progress * (3 - 2 * progress);
}

import { addExtraClass, removeExtraClass } from '../../lib/teact/teact-dom';

import { requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import { animate } from '../../util/animation';
import getAgentHeaderBottom from '../agent/helpers/getAgentHeaderBottom';

import styles from './AgentNews.module.scss';

interface Frame {
  left: number;
  top: number;
  width: number;
  height: number;
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

// The news whose cards are on their way, with what waits for them to land
const landingWaitersByEventId = new Map<number, Set<NoneToVoidFunction>>();

/**
 * Telegram's message flight: the card lifts off the feed and lands in the chat that opens to discuss it, turning into
 * the post on the way, while the chat slides in. The post's suggestions then come in, as an answer's do.
 */
export function startAgentNewsCardFlight(card: HTMLElement, eventId: number) {
  // A card still on its way lands in the post of the chat that opened last, so the same news does not fly twice
  if (landingWaitersByEventId.has(eventId)) return;

  landingWaitersByEventId.set(eventId, new Set());
  requestMeasure(() => {
    const rect = card.getBoundingClientRect();
    const from: Frame = {
      left: rect.left, top: rect.top, width: rect.width, height: rect.height,
    };
    const clipTop = getAgentHeaderBottom(rect.left, rect.right);

    requestMutation(() => {
      const root = document.createElement('div');
      root.className = styles.flight;
      root.setAttribute('aria-hidden', 'true');
      const frame = document.createElement('div');
      frame.className = styles.flightFrame;
      const cardLayer = createLayer(card, from.width);
      frame.appendChild(cardLayer);
      root.appendChild(frame);
      clipUnderChrome(root, clipTop, getComposerTop());
      document.body.appendChild(root);
      applyFrame(frame, from, 0, 0, 0);
      addExtraClass(card, styles.flightSource);

      fly({
        card, eventId, root, frame, cardLayer, from,
      });
    });
  });
}

function fly({
  card, eventId, root, frame, cardLayer, from,
}: {
  card: HTMLElement;
  eventId: number;
  root: HTMLElement;
  frame: HTMLElement;
  cardLayer: HTMLElement;
  from: Frame;
}) {
  const startedAt = Date.now();
  let takeoffAt: number | undefined;
  let postMessage: HTMLElement | undefined;
  let standInLayer: HTMLElement | undefined;
  let target: Frame | undefined;
  let targetSeenAt = startedAt;

  animate(() => {
    const now = Date.now();
    const found = findPost(eventId);
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
          requestMutation(() => {
            addExtraClass(postMessage!, styles.flightTarget);
            standInLayer = createLayer(bubble, width);
            standInLayer.style.opacity = '0';
            frame.appendChild(standInLayer);
          });
        }
      }
    }

    if (takeoffAt === undefined || !target) {
      if (now - startedAt < HOLD_TIMEOUT) {
        const top = getAgentHeaderBottom(from.left, from.left + from.width);
        const bottom = getComposerTop();
        requestMutation(() => clipUnderChrome(root, top, bottom));
        return true;
      }
      dissolve(eventId, root, card, postMessage);
      return false;
    }

    if (now - targetSeenAt > LOST_TARGET_TIMEOUT) {
      dissolve(eventId, root, card, postMessage);
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
    const clipTop = getAgentHeaderBottom(current.left, current.left + current.width);
    const clipBottom = getComposerTop();
    const isLanded = time >= LIFT_DURATION
      && Math.abs(1 - progress) < SPRING_REST_DISTANCE
      && Math.abs(current.left - target.left) < TARGET_REST_DISTANCE
      && Math.abs(current.top - target.top) < TARGET_REST_DISTANCE;

    requestMutation(() => {
      if (isLanded) {
        land(eventId, root, card, postMessage!);
        return;
      }

      clipUnderChrome(root, clipTop, clipBottom);
      applyFrame(frame, current, lift, pitch, yaw);
      cardLayer.style.opacity = String(1 - interpolateSmoothly(CARD_FADE_START, CARD_FADE_END, turn));
      if (standInLayer) {
        standInLayer.style.opacity = String(interpolateSmoothly(STAND_IN_FADE_START, STAND_IN_FADE_END, turn));
      }
    });

    return !isLanded;
  }, requestMeasure);
}

// The flight is clipped in window coordinates, so the clip stays put while both screens slide underneath it
function clipUnderChrome(root: HTMLElement, top = 0, bottom = window.innerHeight) {
  const height = window.innerHeight;
  const headerFadeEnd = top + HEADER_FADE_DISTANCE;
  root.style.clipPath = `inset(${top}px 0 ${Math.max(0, height - bottom)}px 0)`;
  root.style.maskImage = `linear-gradient(to bottom, transparent ${top}px, black ${headerFadeEnd}px,`
    + ` black ${Math.max(headerFadeEnd, bottom - COMPOSER_FADE_DISTANCE)}px, transparent ${bottom}px)`;
}

function getComposerTop() {
  const composers = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-composer]'));
  const rect = composers.reverse().find((element) => {
    const frame = element.getBoundingClientRect();
    return frame.width > 0 && frame.bottom > 0 && frame.top < window.innerHeight;
  })?.getBoundingClientRect();
  return rect?.top ?? window.innerHeight;
}

/** A copy of the bubble, at its own width, without the tail, which the flying frame clips */
function createLayer(source: HTMLElement, width: number) {
  const layer = source.cloneNode(true) as HTMLElement;
  layer.removeAttribute('data-agent-news-event-id');
  layer.classList.add(styles.flightLayer);
  layer.style.width = `${width}px`;
  return layer;
}

function applyFrame(
  frame: HTMLElement, { left, top, width, height }: Frame, lift: number, pitch: number, yaw: number,
) {
  frame.style.width = `${width}px`;
  frame.style.height = `${height}px`;
  frame.style.transform = `translate3d(${left}px, ${top}px, 0) perspective(${PERSPECTIVE}px) `
    + `rotateX(${pitch}deg) rotateY(${yaw}deg) scale(${1 + LIFT_SCALE * lift})`;
  frame.style.boxShadow = `0 0.625rem 1.125rem rgba(0, 0, 0, ${SHADOW_OPACITY * lift})`;
}

/** Calls `onLanded` once the news card flying to the post has turned into it, or at once when none is flying */
export function waitForAgentNewsCardLanding(eventId: number, onLanded: NoneToVoidFunction) {
  const waiters = landingWaitersByEventId.get(eventId);
  if (!waiters) {
    onLanded();
    return undefined;
  }

  waiters.add(onLanded);
  return () => {
    waiters.delete(onLanded);
  };
}

export function getIsAgentNewsCardFlying(eventId: number) {
  return landingWaitersByEventId.has(eventId);
}

// The post shows at once under the card that turned into it
function land(eventId: number, root: HTMLElement, card: HTMLElement, postMessage: HTMLElement) {
  root.remove();
  removeExtraClass(postMessage, styles.flightTarget);
  removeExtraClass(card, styles.flightSource);
  finishFlight(eventId);
}

function dissolve(eventId: number, root: HTMLElement, card: HTMLElement, postMessage?: HTMLElement) {
  requestMutation(() => {
    addExtraClass(root, styles.flightDissolving);
    if (postMessage) removeExtraClass(postMessage, styles.flightTarget);
    finishFlight(eventId);
  });
  window.setTimeout(() => {
    requestMutation(() => {
      root.remove();
      removeExtraClass(card, styles.flightSource);
    });
  }, DISSOLVE_DURATION);
}

function finishFlight(eventId: number) {
  const waiters = landingWaitersByEventId.get(eventId);
  landingWaitersByEventId.delete(eventId);
  waiters?.forEach((onLanded) => onLanded());
}

// The last copy is the chat coming in, should the one going out still show the same news
function findPost(eventId: number) {
  const messages = document.querySelectorAll<HTMLElement>(`[data-agent-news-post-event-id="${eventId}"]`);
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

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

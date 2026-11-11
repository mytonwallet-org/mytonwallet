import { requestMutation } from '../../../lib/fasterdom/fasterdom';
import generateUniqueId from '../../../util/generateUniqueId';
import {
  IS_ANDROID, IS_FIREFOX, IS_IOS, IS_SAFARI,
} from '../../../util/windowEnvironment';

import styles from '../SnapEffect.module.scss';

/** How a removed message or chat leaves: as dust, or fading out where dust is not drawn or motion is reduced */
export type SnapEffectKind = 'dust' | 'fade';

// Telegram Web A turns deleted messages to dust with an SVG filter over a copy of the message. It leaves Firefox
// (https://bugzilla.mozilla.org/show_bug.cgi?id=1896504), Safari and phones out, where the message fades out instead.
const IS_SNAP_EFFECT_SUPPORTED = !IS_IOS && !IS_ANDROID && !IS_FIREFOX && !IS_SAFARI;

const SNAP_EFFECT_DURATION = 1000;
const SNAP_FADE_DURATION = 350;
// The place a removed message or chat leaves closes once its dust has mostly drifted off, as Telegram Web A removes a
// message after its snap, or once it has faded out
const SNAP_GAP_CLOSE_DELAY = 600;

// A ghost whose animation end never comes is still removed
const GHOST_REMOVAL_MARGIN = 500;

const LAYER_ID = 'agent-snap-effect-layer';

const SVG_NAMESPACE = 'http://www.w3.org/2000/svg';
// Inherited colors that follow the text color by default. Copied onto the copy as the element's resolved color, they
// would paint the text of everything inside in that one color, as a gradient label or a colored suggestion.
const CURRENT_COLOR_PROPERTIES = new Set([
  '-webkit-text-fill-color', '-webkit-text-stroke-color', 'text-emphasis-color', 'caret-color',
]);
// Telegram Web A's dust: a fine noise eats the copy away while two noises, a broad drift and a grain, scatter it as far
// as three times its shorter side
const DUST_NOISE_FREQUENCY = 0.5;
const DUST_ALPHA_SLOPES = [5, 2, 1, 0];
const DRIFT_NOISE_FREQUENCY = 0.015;
const GRAIN_NOISE_FREQUENCY = 1;
const GRAIN_NOISE_OCTAVES = 2;
const DUST_SPREAD = 3;

export function getSnapEffectKind(shouldAnimate: boolean): SnapEffectKind {
  if (!shouldAnimate) return 'fade';
  return IS_SNAP_EFFECT_SUPPORTED ? 'dust' : 'fade';
}

/**
 * The layer ghosts turn to dust in. It covers the window over everything, as Telegram Web A's does, so the dust drifts
 * past the list it leaves instead of being cut at its edges.
 */
export function getSnapEffectLayer() {
  let layer = document.getElementById(LAYER_ID);
  if (!layer) {
    layer = document.createElement('div');
    layer.id = LAYER_ID;
    layer.classList.add(styles.layer);
    layer.setAttribute('aria-hidden', 'true');
    document.body.appendChild(layer);
  }
  return layer;
}

/**
 * Copies the element into a ghost standing over it in the snap layer, which turns to dust or fades away and
 * then removes itself. It reads the layout, so it is called in a measure phase and the ghost is added to
 * `getSnapEffectLayer()` in a mutation.
 */
export function createSnapGhost(element: HTMLElement, kind: SnapEffectKind) {
  const { left, top, width, height } = element.getBoundingClientRect();
  const copy = copyElement(element);

  let ghost: HTMLElement | SVGSVGElement;
  if (kind === 'dust') {
    const filterId = `agent-snap-${generateUniqueId()}`;
    const seed = Math.floor(Date.now() / 1000);

    const foreignObject = createSvgElement('foreignObject', { width, height });
    foreignObject.classList.add(styles.copyContainer);
    foreignObject.appendChild(copy);

    const group = createSvgElement('g', { filter: `url(#${filterId})` });
    group.appendChild(foreignObject);

    const defs = createSvgElement('defs');
    defs.appendChild(createDustFilter(filterId, Math.min(width, height), seed));

    ghost = createSvgElement('svg', { width, height, viewBox: `0 0 ${width} ${height}` });
    ghost.append(defs, group);
  } else {
    ghost = document.createElement('div');
    ghost.appendChild(copy);
    ghost.style.width = `${width}px`;
    ghost.style.height = `${height}px`;
  }

  ghost.classList.add(
    styles.ghost,
    kind === 'dust' ? styles.dust : styles.fading,
  );
  ghost.style.left = `${left}px`;
  ghost.style.top = `${top}px`;

  function removeGhost() {
    requestMutation(() => ghost.remove());
  }

  // The copy's own animations end inside it too
  ghost.addEventListener('animationend', (e) => {
    if (e.target === ghost) removeGhost();
  });
  window.setTimeout(removeGhost, getSnapEffectDuration(kind) + GHOST_REMOVAL_MARGIN);

  return ghost;
}

/** How long the place of what leaves holds before the rest closes it, so they don't run into its dust */
export function getSnapGapCloseDelay(kind: SnapEffectKind) {
  return kind === 'dust' ? SNAP_GAP_CLOSE_DELAY : SNAP_FADE_DURATION;
}

// The copy takes the element's computed look, so that it stays the same out of the list, as in Web A
function copyElement(element: HTMLElement) {
  const copy = element.cloneNode(true) as HTMLElement;

  // Inline styles are copied through the style object, which the app's CSP allows where it refuses `style` attributes
  const sourceElements = element.getElementsByTagName('*');
  const copyElements = copy.getElementsByTagName('*');
  for (let i = 0; i < sourceElements.length; i++) {
    const source = sourceElements[i] as HTMLElement | SVGElement;
    if (source.hasAttribute('style')) {
      (copyElements[i] as HTMLElement | SVGElement).style.cssText = source.style.cssText;
    }
    if (source instanceof HTMLCanvasElement) {
      copyCanvas(source, copyElements[i] as HTMLCanvasElement);
    }
  }

  // The Agent's status under its answer carries on with the next answer, so it does not turn to dust
  copy.querySelectorAll<HTMLElement>('[role="status"]').forEach((status) => {
    status.style.setProperty('visibility', 'hidden', 'important');
  });

  const computedStyle = window.getComputedStyle(element);
  const { color } = computedStyle;
  Array.from(computedStyle).forEach((key) => {
    const value = computedStyle.getPropertyValue(key);
    if (CURRENT_COLOR_PROPERTIES.has(key) && value === color) return;
    copy.style.setProperty(key, value, 'important');
  });
  // The copy stands where the ghost is, as the element had settled
  copy.style.setProperty('margin', '0', 'important');
  copy.style.setProperty('transform', 'none', 'important');
  copy.style.setProperty('animation', 'none', 'important');
  copy.style.setProperty('transition', 'none', 'important');
  copy.classList.add(styles.copy);
  copy.removeAttribute('id');
  copy.setAttribute('aria-hidden', 'true');

  return copy;
}

function copyCanvas(source: HTMLCanvasElement, copy: HTMLCanvasElement) {
  try {
    copy.getContext('2d')?.drawImage(source, 0, 0);
  } catch {
    // A canvas that cannot be read stays empty in the copy
  }
}

function getSnapEffectDuration(kind: SnapEffectKind) {
  return kind === 'dust' ? SNAP_EFFECT_DURATION : SNAP_FADE_DURATION;
}

function createDustFilter(id: string, smallestSide: number, seed: number) {
  const filter = createSvgElement('filter', {
    id,
    x: '-150%',
    y: '-150%',
    width: '400%',
    height: '400%',
    'color-interpolation-filters': 'sRGB',
  });

  filter.append(
    createSvgElement('feTurbulence', {
      type: 'fractalNoise', baseFrequency: DUST_NOISE_FREQUENCY, numOctaves: 1, result: 'dustNoise', seed,
    }),
    createSvgElement('feComponentTransfer', { in: 'dustNoise', result: 'dustNoiseMask' }, [
      createSvgElement('feFuncA', { type: 'linear', slope: DUST_ALPHA_SLOPES[0], intercept: 0 }, [
        createSvgElement('animate', {
          attributeName: 'slope',
          values: DUST_ALPHA_SLOPES.join('; '),
          dur: `${SNAP_EFFECT_DURATION}ms`,
          fill: 'freeze',
        }),
      ]),
    ]),
    createSvgElement('feComposite', {
      in: 'SourceGraphic', in2: 'dustNoiseMask', operator: 'in', result: 'dustySource',
    }),
    createSvgElement('feTurbulence', {
      type: 'fractalNoise',
      baseFrequency: DRIFT_NOISE_FREQUENCY,
      numOctaves: 1,
      result: 'displacementNoise1',
      seed: seed + 1,
    }),
    createSvgElement('feTurbulence', {
      type: 'fractalNoise',
      baseFrequency: GRAIN_NOISE_FREQUENCY,
      numOctaves: GRAIN_NOISE_OCTAVES,
      result: 'displacementNoise2',
      seed: seed + 2,
    }),
    createSvgElement('feMerge', { result: 'combinedNoise' }, [
      createSvgElement('feMergeNode', { in: 'displacementNoise1' }),
      createSvgElement('feMergeNode', { in: 'displacementNoise2' }),
    ]),
    createSvgElement('feDisplacementMap', {
      in: 'dustySource', in2: 'combinedNoise', scale: 0, xChannelSelector: 'R', yChannelSelector: 'G',
    }, [
      createSvgElement('animate', {
        attributeName: 'scale',
        values: `0; ${smallestSide * DUST_SPREAD}`,
        dur: `${SNAP_EFFECT_DURATION}ms`,
        fill: 'freeze',
      }),
    ]),
  );

  return filter;
}

function createSvgElement<K extends keyof SVGElementTagNameMap>(
  tagName: K,
  attributes: Record<string, string | number> = {},
  children: SVGElement[] = [],
) {
  const element = document.createElementNS(SVG_NAMESPACE, tagName);
  Object.entries(attributes).forEach(([name, value]) => element.setAttribute(name, String(value)));
  element.append(...children);
  return element;
}

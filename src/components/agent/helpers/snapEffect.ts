import { requestMutation } from '../../../lib/fasterdom/fasterdom';
import generateUniqueId from '../../../util/generateUniqueId';
import {
  IS_ANDROID, IS_FIREFOX, IS_IOS, IS_SAFARI,
} from '../../../util/windowEnvironment';

import styles from '../SnapEffect.module.scss';

/** How a removed message leaves: as dust, shrinking where dust is not drawn, or only fading where motion is reduced */
export type SnapEffectKind = 'dust' | 'shrink' | 'fade';

// Telegram Web A turns deleted messages to dust with an SVG filter over a copy of the message. It leaves Firefox
// (https://bugzilla.mozilla.org/show_bug.cgi?id=1896504), Safari and phones out and shrinks the message there instead.
const IS_SNAP_EFFECT_SUPPORTED = !IS_IOS && !IS_ANDROID && !IS_FIREFOX && !IS_SAFARI;

const SNAP_EFFECT_DURATION = 1000;
const SNAP_SHRINK_DURATION = 200;
const SNAP_FADE_DURATION = 200;

// A ghost whose animation end never comes is still removed
const GHOST_REMOVAL_MARGIN = 500;

const SVG_NAMESPACE = 'http://www.w3.org/2000/svg';
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
  return IS_SNAP_EFFECT_SUPPORTED ? 'dust' : 'shrink';
}

/**
 * Copies the element into a ghost standing over it in the layer, which turns to dust, shrinks or fades away and
 * then removes itself. It reads the layout, so it is called in a measure phase and the ghost is added in a mutation.
 */
export function createSnapGhost(element: HTMLElement, layerRect: DOMRect, kind: SnapEffectKind) {
  const rect = element.getBoundingClientRect();
  const left = rect.left - layerRect.left;
  const top = rect.top - layerRect.top;
  const { width, height } = rect;
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
    kind === 'dust' ? styles.dust : kind === 'shrink' ? styles.shrinking : styles.fading,
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
  Array.from(computedStyle).forEach((key) => {
    copy.style.setProperty(key, computedStyle.getPropertyValue(key), 'important');
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

export function getSnapEffectDuration(kind: SnapEffectKind) {
  return kind === 'dust' ? SNAP_EFFECT_DURATION : kind === 'shrink' ? SNAP_SHRINK_DURATION : SNAP_FADE_DURATION;
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

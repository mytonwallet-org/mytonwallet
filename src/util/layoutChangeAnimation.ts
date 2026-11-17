import { getGlobal } from '../global';

import { ANIMATION_LEVEL_MIN } from '../config';

// Larger than half of any capsule height, so the clip keeps the fully rounded ends at every width
const CAPSULE_CLIP_RADIUS = '6.25rem';

// Layout properties are not animated (see `plugin/no-low-performance-animation-properties` and
// `plugin/no-layout-animation-properties` in `.stylelintrc.json`), so the layout jumps to its final state
// and `clip-path` and `transform` play the change out

export function animateHeightReveal(element: HTMLElement, fromHeight: number, toHeight: number) {
  if (getIsAnimationDisabled()) return;

  const { borderRadius } = getComputedStyle(element);

  element.animate([
    { clipPath: `inset(0 0 ${toHeight - fromHeight}px round ${borderRadius})` },
    { clipPath: `inset(0 round ${borderRadius})` },
  ], getSlideTiming(element));
}

export function animateFadeIn(element: HTMLElement) {
  if (getIsAnimationDisabled()) return;

  element.animate([{ opacity: 0 }, { opacity: 1 }], getSlideTiming(element));
}

export function animateContentShift(element: HTMLElement, scrollContainerSelector: string, offset: number) {
  if (getIsAnimationDisabled()) return;

  // A change above the viewport makes Chrome keep the visible content in place (scroll anchoring),
  // so the content did not move on screen
  const scrollContainer = element.closest<HTMLElement>(scrollContainerSelector)!;
  if (element.getBoundingClientRect().top + offset < scrollContainer.getBoundingClientRect().top) return;

  animateShift(element, 0, offset);
}

// The element has already moved to its new position, and it starts `x` and `y` pixels away from it.
// Without `duration`, the timing comes from `--slide-transition`. Reading it measures the element,
// so a caller in the mutation phase (a layout effect) passes `duration`.
export function animateShift(element: HTMLElement, x: number, y: number, duration?: number) {
  if (getIsAnimationDisabled()) return;

  element.animate([
    { transform: `translate(${x}px, ${y}px)` },
    { transform: 'none' },
  ], {
    ...(duration ? { duration, easing: 'ease' } : getSlideTiming(element)),
    // A shift that starts while another one runs continues from where the element is, without a jump
    composite: 'add',
  });
}

// Plays out a width change of a capsule whose fill is its `::before` layer. The element already has its new width
// and only one `edge` moved. A capsule that became narrower must start wider than its own box, so the layer is
// extended by that difference for the duration of the animation.
export function animateCapsuleWidth(
  element: HTMLElement,
  edge: 'start' | 'end',
  widthChange: number,
  duration: number,
  isRtl?: boolean,
) {
  if (getIsAnimationDisabled()) return;

  const overflow = Math.max(0, -widthChange);
  const isLeftEdge = (edge === 'start') !== Boolean(isRtl);
  const buildClipPath = (inset: number) => (
    `inset(${isLeftEdge ? `0 0 0 ${inset}px` : `0 ${inset}px 0 0`} round ${CAPSULE_CLIP_RADIUS})`
  );
  const position = { [edge === 'start' ? 'insetInlineStart' : 'insetInlineEnd']: `${-overflow}px` };

  element.animate([
    { ...position, clipPath: buildClipPath(Math.max(0, widthChange)) },
    { ...position, clipPath: buildClipPath(overflow) },
  ], { duration, easing: 'ease', pseudoElement: '::before' });
}

function getIsAnimationDisabled() {
  return getGlobal().settings.animationLevel === ANIMATION_LEVEL_MIN;
}

// Platforms override `--slide-transition`, so the timing is read from it rather than hardcoded
function getSlideTiming(element: HTMLElement) {
  const value = getComputedStyle(element).getPropertyValue('--slide-transition').trim();

  return {
    duration: parseFloat(value),
    easing: value.slice(value.indexOf(' ') + 1),
  };
}

import { useRef } from '../lib/teact/teact';

import { requestMutation } from '../lib/fasterdom/fasterdom';
import useLayoutEffectWithPrevDeps from './useLayoutEffectWithPrevDeps';

const ANIMATION_DURATION = 200;
const ANIMATION_END_DELAY = 50;

interface AnimationStyles {
  animateOpacity: string;
  animateTransform: string;
}

export default function useListItemAnimation(
  styles: AnimationStyles,
  withAnimation: boolean,
  topOffset: number, // rem
  shouldFadeInAnimate?: boolean,
) {
  const ref = useRef<HTMLDivElement>();

  useLayoutEffectWithPrevDeps(([prevTopOffset]) => {
    const element = ref.current;

    if (!withAnimation || !element) {
      return;
    }

    let shouldAnimate = false;

    if (prevTopOffset === undefined) {
      animateOpacity(element, styles);
      shouldAnimate = true;
    } else if (topOffset !== prevTopOffset) {
      if (shouldFadeInAnimate) {
        animateOpacity(element, styles);
      } else {
        animateMove(element, topOffset - prevTopOffset, styles);
      }
      shouldAnimate = true;
    }

    if (shouldAnimate) {
      cleanupAnimation(element, styles);
    }
  }, [topOffset, withAnimation, styles, shouldFadeInAnimate]);

  return { ref };
}

function animateOpacity(element: HTMLElement, styles: AnimationStyles) {
  element.style.opacity = '0';

  requestMutation(() => {
    element.classList.add(styles.animateOpacity);
    element.style.opacity = '1';
  });
}

function animateMove(element: HTMLElement, offsetY: number, styles: AnimationStyles) {
  element.style.transform = `translate3d(0, ${-offsetY}rem, 0)`;

  requestMutation(() => {
    element.classList.add(styles.animateTransform);
    element.style.transform = '';
  });
}

function cleanupAnimation(element: HTMLElement, styles: AnimationStyles) {
  setTimeout(() => {
    requestMutation(() => {
      element.classList.remove(styles.animateOpacity, styles.animateTransform);
      element.style.opacity = '';
      element.style.transform = '';
    });
  }, ANIMATION_DURATION + ANIMATION_END_DELAY);
}

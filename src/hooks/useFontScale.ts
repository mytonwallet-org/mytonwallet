import { type ElementRef, useRef } from '../lib/teact/teact';

import { suppressStrict } from '../lib/fasterdom/stricterdom';
import buildClassName from '../util/buildClassName';
import useLastCallback from './useLastCallback';

const MIN_SIZE_SCALE = 0.25; // 12px
const SCALE_STEP = 0.05;
/** The scale is quantized into `SCALE_STEP` steps: step 0 is `MIN_SIZE_SCALE`, `FULL_SIZE_STEP` is the unscaled font */
const FULL_SIZE_STEP = Math.round((1 - MIN_SIZE_SCALE) / SCALE_STEP);

function useFontScale(inputRef: ElementRef<HTMLElement>, shouldGetParentWidth?: boolean) {
  const isFontChangedRef = useRef(false);
  const measureEl = useRef(document.createElement('div'));

  const updateFontScale = useLastCallback(() => {
    const input = inputRef.current;

    suppressStrict(() => {
      if (!input?.offsetParent) return;

      let { clientWidth: width } = shouldGetParentWidth ? input.parentElement! : input;

      if (shouldGetParentWidth) {
        const { paddingLeft, paddingRight } = getComputedStyle(input);
        width -= parseFloat(paddingLeft) + parseFloat(paddingRight);
      }
      measureEl.current.className = buildClassName(input.className, 'measure-hidden');
      measureEl.current.style.width = `${width}px`;
      measureEl.current.innerHTML = ''; // `measureEl.current.innerHTML = input.innerHTML` is not used, because it violates the CSP
      measureEl.current.append(...input.cloneNode(true).childNodes);
      document.body.appendChild(measureEl.current);

      // Every `scrollWidth` read below forces a synchronous layout, so the largest fitting step is found by
      // halving the range instead of stepping down from the full size. Most values fit unscaled, so that step
      // is tried first. When even step 1 overflows, the scale falls back to `MIN_SIZE_SCALE` without measuring.
      let bestStep = 0;

      if (getIsFittingAtStep(FULL_SIZE_STEP)) {
        bestStep = FULL_SIZE_STEP;
      } else {
        let lowStep = 1;
        let highStep = FULL_SIZE_STEP - 1;

        while (lowStep <= highStep) {
          const middleStep = Math.floor((lowStep + highStep) / 2);

          if (getIsFittingAtStep(middleStep)) {
            bestStep = middleStep;
            lowStep = middleStep + 1;
          } else {
            highStep = middleStep - 1;
          }
        }
      }

      const scale = getScaleAtStep(bestStep);
      isFontChangedRef.current = scale < 1;
      document.body.removeChild(measureEl.current);
      measureEl.current.className = '';
      input.style.setProperty('--font-size-scale', scale.toString());

      function getIsFittingAtStep(step: number) {
        measureEl.current.style.setProperty('--font-size-scale', getScaleAtStep(step).toString());
        return measureEl.current.scrollWidth <= width;
      }
    });
  });

  return { updateFontScale, isFontChangedRef };
}

export default useFontScale;

function getScaleAtStep(step: number) {
  return 1 - (FULL_SIZE_STEP - step) * SCALE_STEP;
}

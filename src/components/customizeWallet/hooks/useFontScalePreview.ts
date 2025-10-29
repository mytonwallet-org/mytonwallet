import { type ElementRef, useRef } from '../../../lib/teact/teact';

import { suppressStrict } from '../../../lib/fasterdom/stricterdom';
import buildClassName from '../../../util/buildClassName';

import useLastCallback from '../../../hooks/useLastCallback';

const MIN_SIZE_SCALE = 0.25; // 12px

function useFontScalePreview(inputRef: ElementRef<HTMLElement>, cssVarName = '--font-size-scale-preview') {
  const isFontChangedRef = useRef(false);
  const measureEl = useRef(document.createElement('div'));

  const updateFontScale = useLastCallback(() => {
    const input = inputRef.current;

    suppressStrict(() => {
      if (!input?.offsetParent) return;

      const { clientWidth: width } = input.parentElement!;
      const { paddingLeft, paddingRight } = getComputedStyle(input.parentElement!);
      const availableWidth = width - parseFloat(paddingLeft) - parseFloat(paddingRight);

      measureEl.current.className = buildClassName(input.className, 'measure-hidden');
      measureEl.current.style.width = `${availableWidth}px`;
      measureEl.current.innerHTML = '';
      measureEl.current.append(...input.cloneNode(true).childNodes);
      document.body.appendChild(measureEl.current);

      let scale = 1;

      while (scale > MIN_SIZE_SCALE) {
        measureEl.current.style.setProperty(cssVarName, scale.toString());

        if (measureEl.current.scrollWidth <= availableWidth) break;
        scale -= 0.05;
      }

      isFontChangedRef.current = scale < 1;
      document.body.removeChild(measureEl.current);
      measureEl.current.className = '';
      input.style.setProperty(cssVarName, scale.toString());
    });
  });

  return { updateFontScale, isFontChangedRef };
}

export default useFontScalePreview;

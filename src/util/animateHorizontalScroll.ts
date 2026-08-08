import { requestMutation } from '../lib/fasterdom/fasterdom';
import { animate } from './animation';

const DEFAULT_DURATION = 300;

const stopById = new Map<string, VoidFunction>();

export default function animateHorizontalScroll(container: HTMLElement, left: number, duration = DEFAULT_DURATION) {
  // Use the computed direction, not the `dir` attribute: scroll containers inherit RTL from `<html>`
  // and rarely set `dir` on themselves
  const isRtl = getComputedStyle(container).direction === 'rtl';
  const {
    scrollLeft, offsetWidth: containerWidth, scrollWidth, dataset: { scrollId },
  } = container;

  // In RTL (modern "negative" model) `scrollLeft` ranges over `[containerWidth - scrollWidth, 0]`
  const minScrollLeft = isRtl ? containerWidth - scrollWidth : 0;
  const maxScrollLeft = isRtl ? 0 : scrollWidth - containerWidth;

  let path = left - scrollLeft;

  if (path < 0) {
    path = Math.max(path, minScrollLeft - scrollLeft);
  } else if (path > 0) {
    path = Math.min(path, maxScrollLeft - scrollLeft);
  }

  if (path === 0) {
    return Promise.resolve();
  }

  if (scrollId && stopById.has(scrollId)) {
    stopById.get(scrollId)!();
  }

  const target = scrollLeft + path;

  return new Promise<void>((resolve) => {
    requestMutation(() => {
      if (duration === 0) {
        container.scrollLeft = target;
        resolve();
        return;
      }

      let isStopped = false;
      const id = Math.random().toString();
      container.dataset.scrollId = id;
      stopById.set(id, () => {
        isStopped = true;
      });

      container.style.scrollSnapType = 'none';

      const startAt = Date.now();

      animate(() => {
        if (isStopped) return false;

        const t = Math.min((Date.now() - startAt) / duration, 1);

        const currentPath = path * (1 - transition(t));
        container.scrollLeft = Math.round(target - currentPath);

        if (t >= 1) {
          container.style.scrollSnapType = '';
          delete container.dataset.scrollId;
          stopById.delete(id);
          resolve();
        }

        return t < 1;
      }, requestMutation);
    });
  });
}

function transition(t: number) {
  return 1 - ((1 - t) ** 3.5);
}

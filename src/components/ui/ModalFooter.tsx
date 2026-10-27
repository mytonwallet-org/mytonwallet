import type { TeactNode } from '../../lib/teact/teact';
import React, { useEffect, useRef } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useScrolledState from '../../hooks/useScrolledState';

import modalStyles from './Modal.module.scss';

type OwnProps = {
  isFrosted?: boolean;
  children: TeactNode;
};

/**
 * Keeps the modal actions at the bottom of the scroll container. Place it as the last child of
 * `modalStyles.transitionContent`.
 *
 * While there is more content below, the footer turns translucent and gets a top separator, because the content
 * scrolls under it. With `isFrosted`, the footer is frosted glass at all times, and its top edge dissolves into
 * the content instead of the separator.
 */
function ModalFooter({ isFrosted, children }: OwnProps) {
  const ref = useRef<HTMLDivElement>();
  const { isAtEnd, update } = useScrolledState();

  useEffect(() => {
    // The frosted footer looks the same at any scroll position
    if (isFrosted) return undefined;

    const footer = ref.current!;
    const scrollContainer = footer.closest<HTMLElement>('.custom-scroll');
    if (!scrollContainer) return undefined;

    const updateScrollState = () => update(scrollContainer);

    // Loaded content changes the scroll height without firing `scroll`, so the sizes are watched as well
    const resizeObserver = new ResizeObserver(updateScrollState);
    resizeObserver.observe(scrollContainer);
    resizeObserver.observe(footer.parentElement!);
    scrollContainer.addEventListener('scroll', updateScrollState, { passive: true });

    return () => {
      scrollContainer.removeEventListener('scroll', updateScrollState);
      resizeObserver.disconnect();
    };
  }, [isFrosted, update]);

  return (
    <div
      ref={ref}
      className={buildClassName(
        modalStyles.footer,
        isFrosted ? modalStyles.footer_frosted : !isAtEnd && modalStyles.footer_separated,
      )}
    >
      {children}
    </div>
  );
}

export default ModalFooter;

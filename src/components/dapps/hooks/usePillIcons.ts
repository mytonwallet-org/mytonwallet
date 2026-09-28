import { useEffect, useLayoutEffect, useRef } from '../../../lib/teact/teact';

import { requestForcedReflow, requestMeasure, requestMutation } from '../../../lib/fasterdom/fasterdom';
import { REM } from '../../../util/windowEnvironment';

import useLastCallback from '../../../hooks/useLastCallback';

import styles from '../Dapp.module.scss';

// The width a pill gains from its icon: the icon, the gap after it, minus the pull towards the pill edge
const ICON_SPACE = (2 + 0.375 - 0.5) * REM;
const LINK_MIN_WIDTH = REM;
// `scrollWidth` and `clientWidth` are rounded separately, so a text that fits exactly may differ by a pixel
const TRUNCATION_TOLERANCE = 1;

/**
 * Both pill icons are hidden as soon as any text in the pills gets truncated, which gives the text the room the
 * icons took and lets the pills shrink to their content.
 *
 * Hidden icons come back only when the dashed link has spare room for both of them. So showing them cannot truncate
 * the text again, and the icons never flicker between the two states.
 *
 * The state lives in a class on the header rather than in the component state: a state update renders only on the
 * next frame, so the header would first appear with the icons and then drop them. The first decision is made in the
 * same update pass, before the header is painted. Later ones follow resizes: the pills change size whenever their
 * content changes or the text gets truncated, and the link changes size when the header gains spare room.
 */
export default function usePillIcons() {
  const headerRef = useRef<HTMLDivElement>();
  const accountPillRef = useRef<HTMLDivElement>();
  const dappPillRef = useRef<HTMLDivElement>();
  const linkRef = useRef<HTMLElement>();
  const walletNameRef = useRef<HTMLSpanElement>();
  const dappNameRef = useRef<HTMLSpanElement>();
  const dappHostRef = useRef<HTMLSpanElement>();

  const getShouldHideIcons = useLastCallback((header: HTMLElement) => {
    if (header.classList.contains(styles.requestHeader_noIcons)) {
      return linkRef.current!.clientWidth - LINK_MIN_WIDTH < 2 * ICON_SPACE;
    }

    return [walletNameRef, dappNameRef, dappHostRef].some(({ current }) => current && getIsTruncated(current));
  });

  useLayoutEffect(() => {
    const header = headerRef.current!;

    requestForcedReflow(() => {
      const shouldHideIcons = getShouldHideIcons(header);

      return () => {
        header.classList.toggle(styles.requestHeader_noIcons, shouldHideIcons);
      };
    });
  }, [getShouldHideIcons]);

  useEffect(() => {
    const header = headerRef.current!;

    const observer = new ResizeObserver(() => {
      requestMeasure(() => {
        const shouldHideIcons = getShouldHideIcons(header);

        requestMutation(() => {
          header.classList.toggle(styles.requestHeader_noIcons, shouldHideIcons);
        });
      });
    });

    for (const { current } of [accountPillRef, dappPillRef, linkRef]) {
      observer.observe(current!);
    }

    return () => observer.disconnect();
  }, [getShouldHideIcons]);

  return {
    headerRef, accountPillRef, dappPillRef, linkRef, walletNameRef, dappNameRef, dappHostRef,
  };
}

/**
 * A single-line text is truncated when it overflows sideways. The wallet name wraps under a one-line clamp instead,
 * so it is truncated when a second line appears below.
 *
 * The vertical check needs half a line of margin: the glyphs are taller than the 1rem line height, and Chrome counts
 * the protruding part in `scrollHeight`. With a small tolerance, every single-line text would look truncated, and the
 * icons would keep hiding and coming back.
 */
function getIsTruncated(element: HTMLElement) {
  const { scrollWidth, clientWidth, scrollHeight, clientHeight } = element;

  return scrollWidth - clientWidth > TRUNCATION_TOLERANCE || scrollHeight - clientHeight > clientHeight / 2;
}

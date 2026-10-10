import { useEffect, useRef } from '../../../lib/teact/teact';

import useLastCallback from '../../../hooks/useLastCallback';

export default function useScrollToBottomOnReveal(
  getShouldFollow: () => boolean,
  scrollToBottom: NoneToVoidFunction,
) {
  const frameRef = useRef<number>();

  const handleTextRevealProgress = useLastCallback(() => {
    if (!getShouldFollow() || frameRef.current !== undefined) return;

    frameRef.current = requestAnimationFrame(() => {
      frameRef.current = undefined;
      if (getShouldFollow()) {
        scrollToBottom();
      }
    });
  });

  useEffect(() => {
    return () => {
      if (frameRef.current !== undefined) {
        cancelAnimationFrame(frameRef.current);
      }
    };
  }, []);

  return handleTextRevealProgress;
}

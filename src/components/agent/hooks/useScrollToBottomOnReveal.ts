import { useEffect, useRef } from '../../../lib/teact/teact';

import useLastCallback from '../../../hooks/useLastCallback';

export default function useScrollToBottomOnReveal(
  isAtBottomRef: React.RefObject<boolean>,
  scrollToBottom: NoneToVoidFunction,
) {
  const frameRef = useRef<number>();

  const handleTextRevealProgress = useLastCallback(() => {
    if (!isAtBottomRef.current || frameRef.current !== undefined) return;

    frameRef.current = requestAnimationFrame(() => {
      frameRef.current = undefined;
      if (isAtBottomRef.current) {
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

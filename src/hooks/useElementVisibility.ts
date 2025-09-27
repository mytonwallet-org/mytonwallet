import type { ElementRef } from '../lib/teact/teact';
import { useEffect, useState } from '../lib/teact/teact';

interface OwnProps {
  rootMargin: string;
  threshold?: number[];
  isDisabled?: boolean;
  targetRef?: ElementRef<HTMLDivElement | undefined>;
  cb?: (entry: IntersectionObserverEntry) => void;
}

export default function useElementVisibility(options: OwnProps) {
  const {
    rootMargin,
    threshold = [0],
    isDisabled,
    targetRef,
    cb,
  } = options;

  const [isVisible, setIsVisible] = useState(true);

  useEffect(() => {
    const element = targetRef?.current;
    if (isDisabled || !element) return undefined;

    const observer = new IntersectionObserver((entries) => {
      const entry = entries[0];

      setIsVisible(entry.isIntersecting);
      cb?.(entry);
    }, {
      rootMargin,
      threshold,
    });

    observer.observe(element);

    return () => {
      observer.disconnect();
    };
  }, [rootMargin, threshold, isDisabled, targetRef, cb]);

  return { isVisible };
}

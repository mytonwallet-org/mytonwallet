import { useLayoutEffect } from '../lib/teact/teact';
import { addExtraClass, removeExtraClass } from '../lib/teact/teact-dom';

interface Options {
  className: string;
  isActive?: boolean;
  element?: HTMLElement | Document;
}

const refCounts = new WeakMap<object, Map<string, number>>();

function incrementRefCount(element: object, className: string) {
  let classMap = refCounts.get(element);
  if (!classMap) {
    classMap = new Map();
    refCounts.set(element, classMap);
  }
  classMap.set(className, (classMap.get(className) ?? 0) + 1);
}

function decrementRefCount(element: object, className: string): boolean {
  const classMap = refCounts.get(element);
  if (!classMap) return true;

  const count = (classMap.get(className) ?? 0) - 1;
  if (count <= 0) {
    classMap.delete(className);
    if (classMap.size === 0) {
      refCounts.delete(element);
    }
    return true;
  }

  classMap.set(className, count);
  return false;
}

export default function useToggleClass({
  className,
  isActive,
  element = document.documentElement,
}: Options): void {
  useLayoutEffect(() => {
    if (!isActive) return;

    incrementRefCount(element, className);
    addExtraClass(element as HTMLElement, className);

    return () => {
      if (decrementRefCount(element, className)) {
        removeExtraClass(element as HTMLElement, className);
      }
    };
  }, [className, isActive, element]);
}

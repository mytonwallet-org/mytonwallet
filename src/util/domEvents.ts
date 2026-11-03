import type React from '../lib/teact/teact';

// The key code browsers give a key press that an input method handles
const IME_KEY_CODE = 229;

export const stopEvent = (e: React.UIEvent | Event | React.FormEvent) => {
  e.stopPropagation();
  e.preventDefault();
};

/**
 * Whether the key press belongs to an input method composing text, as for Chinese or Japanese, rather than to the
 * field. Safari sends the Enter that confirms a word after `compositionend`, with `isComposing` already false, so its
 * key code tells it.
 */
export function getIsInputMethodKey(e: React.KeyboardEvent | KeyboardEvent) {
  return e.isComposing || e.keyCode === IME_KEY_CODE;
}

export function listenOnce<T extends Event = Event>(
  target: Pick<EventTarget, 'addEventListener' | 'removeEventListener'>,
  name: string,
  handler: (event: T) => void,
) {
  const handleEvent = (event: Event) => {
    target.removeEventListener(name, handleEvent);
    handler(event as T);
  };
  target.addEventListener(name, handleEvent);
}

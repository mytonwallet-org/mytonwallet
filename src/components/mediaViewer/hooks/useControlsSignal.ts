import { createSignal } from '../../../util/signals';

// Whether a picture's header and caption show. A tap on a touch screen toggles them and a swipe down hides them, as in
// Telegram.
const [getAreControlsVisible, setAreControlsVisible] = createSignal(true);
// A zoomed-in picture covers its caption until it is back to its size
const [getIsZoomed, setIsZoomed] = createSignal(false);

export default function useControlsSignal() {
  return {
    getAreControlsVisible, setAreControlsVisible, getIsZoomed, setIsZoomed,
  } as const;
}

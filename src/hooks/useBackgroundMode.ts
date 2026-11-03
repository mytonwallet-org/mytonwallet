import { useEffect } from '../lib/teact/teact';

import { getIsInBackground } from '../util/backgroundMode';
import useLastCallback from './useLastCallback';

export default function useBackgroundMode(
  onBlur?: AnyToVoidFunction,
  onFocus?: AnyToVoidFunction,
  isDisabled = false,
) {
  const lastOnBlur = useLastCallback(onBlur);
  const lastOnFocus = useLastCallback(onFocus);

  useEffect(() => {
    if (isDisabled) {
      return undefined;
    }

    if (getIsInBackground()) {
      lastOnBlur();
    }

    return getIsInBackground.subscribe(() => {
      if (getIsInBackground()) {
        lastOnBlur();
      } else {
        lastOnFocus();
      }
    });
  }, [isDisabled, lastOnBlur, lastOnFocus]);
}

export function isBackgroundModeActive() {
  return getIsInBackground();
}

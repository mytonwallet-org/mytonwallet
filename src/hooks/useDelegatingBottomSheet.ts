import type { BottomSheetKeys } from '@mytonwallet/native-bottom-sheet';
import { BottomSheet } from '@mytonwallet/native-bottom-sheet';
import { useEffect } from '../lib/teact/teact';
import { forceOnHeavyAnimationOnce } from '../lib/teact/teactn';
import { getGlobal } from '../global';

import { pause } from '../util/schedulers';
import { IS_DELEGATING_BOTTOM_SHEET } from '../util/windowEnvironment';
import useEffectWithPrevDeps from './useEffectWithPrevDeps';

const RACE_TIMEOUT = 1000;
const CLOSING_DURATION = 100;

const controlledByNative = new Map<BottomSheetKeys, NoneToVoidFunction>();

if (IS_DELEGATING_BOTTOM_SHEET) {
  void BottomSheet.prepare();

  void BottomSheet.addListener(
    'openInMain',
    ({ key }: { key: BottomSheetKeys }) => {
      controlledByNative.get(key)?.();
    },
  );
}

let lastOpenCall = Promise.resolve();
let closeCurrent: NoneToVoidFunction | undefined;

export function useDelegatingBottomSheet(
  key: BottomSheetKeys | undefined,
  isPortrait: boolean | undefined,
  isOpen: boolean | undefined,
  onClose: AnyToVoidFunction,
) {
  const isDelegating = IS_DELEGATING_BOTTOM_SHEET && key;
  const shouldOpen = isOpen && isPortrait;

  useEffectWithPrevDeps(([prevShouldOpen]) => {
    if (!isDelegating) return;

    if (shouldOpen) {
      closeCurrent?.();

      const closeNext = () => {
        forceOnHeavyAnimationOnce();
        onClose();
      };

      closeCurrent = closeNext;

      // Wait until previous call resolves to get an up-to-date global
      lastOpenCall = Promise.race([
        lastOpenCall,
        pause(RACE_TIMEOUT), // Sometimes the last open call is stuck for some unknown reason
      ])
        .then(() => {
          return BottomSheet.delegate({
            key,
            globalJson: JSON.stringify(getGlobal()),
          });
        })
        .then(() => {
          if (closeCurrent === closeNext) {
            closeCurrent();
            closeCurrent = undefined;
          }
        })
        .then(() => pause(CLOSING_DURATION));
    } else if (prevShouldOpen) {
      void BottomSheet.release({ key });
    }
  }, [shouldOpen, isDelegating, key, onClose]);

  return isDelegating && isPortrait;
}

export function useOpenFromNativeBottomSheet(
  key: BottomSheetKeys,
  open: NoneToVoidFunction,
) {
  useEffect(() => {
    if (!IS_DELEGATING_BOTTOM_SHEET) return undefined;

    controlledByNative.set(key, open);

    return () => {
      if (controlledByNative.get(key) === open) {
        controlledByNative.delete(key);
      }
    };
  }, [key, open]);
}

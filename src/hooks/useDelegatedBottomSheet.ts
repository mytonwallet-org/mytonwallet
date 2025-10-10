import type { HTMLInputTypeAttribute } from 'react';
import type { BottomSheetKeys } from '@mytonwallet/native-bottom-sheet';
import { BottomSheet } from '@mytonwallet/native-bottom-sheet';
import type { SafeAreaInsets } from 'capacitor-plugin-safe-area';
import { SafeArea } from 'capacitor-plugin-safe-area';
import { type ElementRef, useEffect, useLayoutEffect, useState } from '../lib/teact/teact';
import { forceOnHeavyAnimationOnce } from '../lib/teact/teactn';
import { setGlobal } from '../global';

import type { GlobalState } from '../global/types';

import { bigintReviver } from '../util/bigint';
import cssColorToHex from '../util/cssColorToHex';
import { setStatusBarStyle } from '../util/switchTheme';
import { IS_DELEGATED_BOTTOM_SHEET } from '../util/windowEnvironment';
import { useDeviceScreen } from './useDeviceScreen';
import useEffectWithPrevDeps from './useEffectWithPrevDeps';

const BLUR_TIMEOUT = 50;
const COMPACT_MODAL_CSS_SELECTOR = '.is-compact-modal';

const controlledByMain = new Map<BottomSheetKeys, NoneToVoidFunction>();

const textInputTypes = new Set<HTMLInputTypeAttribute>([
  'color', 'date', 'datetime-local', 'email', 'month', 'number',
  'password', 'search', 'tel', 'text', 'time', 'url', 'week',
]);

let safeAreaCache: SafeAreaInsets['insets'] | undefined;
const safeAreaPromise = SafeArea.getSafeAreaInsets().then(({ insets }) => {
  safeAreaCache = insets;
  return safeAreaCache;
});

let currentKey: BottomSheetKeys | undefined;

if (IS_DELEGATED_BOTTOM_SHEET) {
  void BottomSheet.addListener('delegate', ({ key, globalJson }: { key: BottomSheetKeys; globalJson: string }) => {
    currentKey = key;
    controlledByMain.get(key)?.();

    const incomingGlobal = sanitizeGlobalForBottomSheet(globalJson);
    setGlobal(
      incomingGlobal,
      { forceOutdated: true, forceSyncOnIOs: true },
    );
  });

  void BottomSheet.addListener('move', () => {
    window.dispatchEvent(new Event('viewportmove'));
  });
}

let isForcedFullSize: boolean;

export function getIsForcedFullSize() {
  return isForcedFullSize;
}

export function useDelegatedBottomSheet(
  key: BottomSheetKeys | undefined,
  isOpen: boolean | undefined,
  onClose: AnyToVoidFunction,
  dialogRef: ElementRef<HTMLDivElement>,
  forceFullNative = false,
  noResetHeightOnBlur = false,
) {
  useEffectWithPrevDeps(([prevIsOpen]) => {
    if (!IS_DELEGATED_BOTTOM_SHEET || !key || key !== currentKey) return;

    if (isOpen) {
      const dialogEl = dialogRef.current!;

      void BottomSheet.openSelf({
        key,
        height: String(dialogEl.offsetHeight),
        backgroundColor: cssColorToHex(getComputedStyle(dialogEl).backgroundColor),
      }).then(() => {
        forceOnHeavyAnimationOnce();
        onClose();
      });
    } else if (prevIsOpen) {
      void BottomSheet.closeSelf({ key });
      setStatusBarStyle({
        forceDarkBackground: false,
      });
    }
  }, [isOpen, dialogRef, key, onClose]);

  const isDelegatedAndOpen = IS_DELEGATED_BOTTOM_SHEET && key && isOpen;

  const { screenHeight } = useDeviceScreen();
  const [safeArea, setSafeArea] = useState(safeAreaCache);
  void safeAreaPromise.then(setSafeArea);
  // We use Safe Area plugin instead of CSS `env()` function as it does not depend on modal position
  const maxHeight = screenHeight - (safeArea?.top || 0);

  useLayoutEffect(() => {
    if (!isDelegatedAndOpen) return;

    dialogRef.current!.style[forceFullNative ? 'maxHeight' : 'height'] = '';
    dialogRef.current!.style[forceFullNative ? 'height' : 'maxHeight'] = `${maxHeight}px`;
  }, [dialogRef, forceFullNative, isDelegatedAndOpen, maxHeight]);

  useEffectWithPrevDeps(([prevForceFullNative]) => {
    if (!isDelegatedAndOpen) return;

    isForcedFullSize = forceFullNative;

    // Skip initial opening
    if (forceFullNative !== undefined && prevForceFullNative === undefined) return;

    void BottomSheet.toggleSelfFullSize({ isFullSize: forceFullNative });
  }, [forceFullNative, isDelegatedAndOpen]);

  useLayoutEffect(() => {
    if (!isDelegatedAndOpen) return undefined;

    const dialogEl = dialogRef.current!;
    let blurTimeout: number | undefined;

    function onFocus(e: FocusEvent) {
      if (!isInput(e.target)) {
        return;
      }

      if (blurTimeout) {
        clearTimeout(blurTimeout);
        blurTimeout = undefined;
        return;
      }

      preventScrollOnFocus(dialogEl);

      void BottomSheet.toggleSelfFullSize({ isFullSize: true });
    }

    function onBlur(e: FocusEvent) {
      if (!isInput(e.target) || noResetHeightOnBlur || forceFullNative || isInCompactModal(e.target)) {
        return;
      }

      blurTimeout = window.setTimeout(() => {
        blurTimeout = undefined;
        void BottomSheet.toggleSelfFullSize({ isFullSize: false });
      }, BLUR_TIMEOUT);
    }

    document.addEventListener('focusin', onFocus);
    document.addEventListener('focusout', onBlur);

    return () => {
      document.removeEventListener('focusout', onBlur);
      document.removeEventListener('focusin', onFocus);
    };
  }, [dialogRef, forceFullNative, isDelegatedAndOpen, noResetHeightOnBlur]);
}

export function useOpenFromMainBottomSheet(
  key: BottomSheetKeys,
  open: NoneToVoidFunction,
) {
  useEffect(() => {
    if (!IS_DELEGATED_BOTTOM_SHEET) return undefined;

    controlledByMain.set(key, open);

    if (currentKey === key) {
      open();
    }

    return () => {
      if (controlledByMain.get(key) === open) {
        controlledByMain.delete(key);
      }
    };
  }, [key, open]);
}

export function openInMain(key: BottomSheetKeys) {
  void BottomSheet.openInMain({ key });
}

function isInput(el?: EventTarget | null) {
  if (!el || !(el instanceof HTMLElement)) return false;

  return (el.tagName === 'INPUT' && textInputTypes.has((el as HTMLInputElement).type))
    || el.tagName === 'TEXTAREA'
    || (el.tagName === 'DIV' && el.isContentEditable);
}

function isInCompactModal(el?: EventTarget | null) {
  if (!el || !(el instanceof HTMLElement)) return false;

  return el.matches(COMPACT_MODAL_CSS_SELECTOR) || !!el.closest('.is-compact-modal');
}

function preventScrollOnFocus(el: HTMLDivElement) {
  el.style.opacity = '0';
  setTimeout(() => {
    el.style.opacity = '1';
  });

  document.documentElement.scrollTop = 0;
}

function sanitizeGlobalForBottomSheet(globalJson: string) {
  const global = JSON.parse(globalJson, bigintReviver) as GlobalState;

  // When the application is unlocked, the global state is copied from the main application to NBS.
  // This also copies the isPinAccepted state, which causes an error in the modals.
  // Therefore, we reset the isPinAccepted state when opening a modal in NBS.
  if (global.isPinAccepted) {
    global.isPinAccepted = undefined;
  }

  return global;
}

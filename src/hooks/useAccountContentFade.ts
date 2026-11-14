import { useEffect, useLayoutEffect, useRef } from '../lib/teact/teact';
import { addCallback } from '../lib/teact/teactn';

import type { GlobalState } from '../global/types';

import { ANIMATION_LEVEL_MIN } from '../config';
import { requestForcedReflow } from '../lib/fasterdom/fasterdom';
import { selectCurrentAccountId } from '../global/selectors';
import {
  alignAccountContent,
  captureAccountContent,
  playAccountContentTransition,
  registerAccountContent,
} from '../util/accountContentTransition';
import safeExec from '../util/safeExec';
import { useMediaQuery } from './useMediaQuery';

let lastAccountId: string | undefined;

// Teact patches the DOM in a later frame, so the previous account and its palette are still on screen here.
// `safeExec` keeps a failed snapshot from stopping the other global callbacks.
addCallback((global: GlobalState) => {
  const accountId = selectCurrentAccountId(global);
  if (accountId === lastAccountId) return;

  lastAccountId = accountId;
  if (global.settings.animationLevel !== ANIMATION_LEVEL_MIN) safeExec(captureAccountContent);
});

/** Crossfades a frozen copy of the previous account over the live region, so the region does not remount */
export default function useAccountContentFade(accountId?: string, isDisabled = false) {
  const ref = useRef<HTMLDivElement>();
  const registered = useRef<HTMLElement>();
  const unregister = useRef<NoneToVoidFunction>();
  const hasReducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)');

  useLayoutEffect(() => {
    const node = isDisabled || hasReducedMotion ? undefined : ref.current;
    if (registered.current === node) return;

    unregister.current?.();
    registered.current = node;
    unregister.current = node ? registerAccountContent(node) : undefined;
  });

  useLayoutEffect(() => () => unregister.current?.(), []);

  // `useEffect` runs a frame after the new account is painted, which is too late to align the outgoing view
  useLayoutEffect(() => {
    const node = ref.current;

    if (node) requestForcedReflow(() => alignAccountContent(node));
  }, [accountId]);

  useEffect(() => {
    if (ref.current) playAccountContentTransition(ref.current);
  }, [accountId]);

  return ref;
}

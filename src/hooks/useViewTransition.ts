import {
  useEffect,
  useRef,
  useState,
} from '../lib/teact/teact';

import { VIEW_TRANSITION_CLASS_NAME } from '../config';
import { requestMutation, requestNextMutation } from '../lib/fasterdom/fasterdom';
import Deferred from '../util/Deferred';
import { logDebugError } from '../util/logs';
import { IS_VIEW_TRANSITION_SUPPORTED } from '../util/windowEnvironment';

type TransitionFunction = () => Promise<void> | void;

type TransitionState = 'idle' | 'capturing-old' | 'capturing-new' | 'animating' | 'skipped';
interface ViewTransitionController {
  transitionState: TransitionState;
  shouldApplyVtn?: boolean;
  startViewTransition: (domUpdateCallback?: TransitionFunction) => PromiseLike<void> | void;
}

let hasActiveTransition = false;
export function hasActiveViewTransition(): boolean {
  return hasActiveTransition;
}

/**
 * Hook to orchestrate UI updates with the View Transitions API.
 *
 * What it does:
 * - Wraps DOM/state updates in `document.startViewTransition`,
 *   falling back to an immediate update if the API is not supported.
 * - Exposes fine‑grained `transitionState` and a convenience boolean `shouldApplyVtn`
 *   to conditionally attach view‑transition attributes/classes during capture/animation.
 * - Adds/removes `VIEW_TRANSITION_CLASS_NAME` on `<body>` while a transition is active,
 *   allowing global CSS to tweak styles for smoother transitions.
 *
 * Usage example:
 * ```tsx
 * const { startViewTransition, shouldApplyVtn } = useViewTransition();
 * const vtnStyle = shouldApplyVtn ? 'view-transition-name: list' : undefined; // Teact style is a string
 *
 * const handleNavigate = () => {
 *   startViewTransition(() => {
 *     // Put all state changes that affect layout/paint here
 *     setRoute(nextRoute);
 *   });
 * };
 *
 * return (
 *   <div className={styles.container} style={vtnStyle} />
 * );
 * ```
 *
 * ```scss
 * .container::view-transition-group(list),
 * .container::view-transition-new(list),
 * .container::view-transition-old(list) {
 *   contain: paint;
 *   overflow: clip;
 *   border-radius: var(--border-radius-default);
 * }
 * ```
 *
 * While a transition is active, `<body>` gets `VIEW_TRANSITION_CLASS_NAME` (see `config.ts`) for optional global tweaks.
 *
 * Notes:
 * - Provide all layout/paint‑affecting updates inside the callback. The callback may be async
 *   and will be awaited before the animation starts.
 * - `hasActiveViewTransition()` can be used outside of components to know if a transition is in flight.
 */
export function useViewTransition(): ViewTransitionController {
  const domUpdaterFn = useRef<TransitionFunction>();
  const [transitionState, setTransitionState] = useState<TransitionState>('idle');

  useEffect(() => {
    if (transitionState !== 'capturing-old') return;

    const transition = document.startViewTransition(async () => {
      setTransitionState('capturing-new');
      if (domUpdaterFn.current) await domUpdaterFn.current();
      const deferred = new Deferred<void>();
      requestNextMutation(() => {
        deferred.resolve();
      });
      return deferred.promise;
    });

    void transition.finished
      .then(() => {
        setTransitionState('idle');
        requestMutation(() => {
          document.body.classList.remove(VIEW_TRANSITION_CLASS_NAME);
        });
        hasActiveTransition = false;
      })
      .catch((e: any) => {
        logDebugError('useViewTransition finished error', e);

        setTransitionState('skipped');
        requestMutation(() => {
          document.body.classList.remove(VIEW_TRANSITION_CLASS_NAME);
        });
        hasActiveTransition = false;
      });

    transition.ready
      .then(() => {
        setTransitionState('animating');
      })
      .catch((e: any) => {
        logDebugError('useViewTransition ready error', e);

        setTransitionState('skipped');
        requestMutation(() => {
          document.body.classList.remove(VIEW_TRANSITION_CLASS_NAME);
        });
        hasActiveTransition = false;
      });
  }, [transitionState]);

  function startViewTransition(updateCallback?: TransitionFunction): PromiseLike<void> | void {
    // Fallback: simply run the callback immediately if view transitions aren't supported.
    if (!IS_VIEW_TRANSITION_SUPPORTED) {
      if (updateCallback) void updateCallback();
      return;
    }

    domUpdaterFn.current = updateCallback;
    setTransitionState('capturing-old');
    requestMutation(() => {
      document.body.classList.add(VIEW_TRANSITION_CLASS_NAME);
    });
    hasActiveTransition = true;
  }

  return {
    shouldApplyVtn: transitionState === 'capturing-old'
      || transitionState === 'capturing-new' || transitionState === 'animating',
    transitionState,
    startViewTransition,
  };
}

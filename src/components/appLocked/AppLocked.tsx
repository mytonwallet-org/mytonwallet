import React, { memo, useEffect, useMemo, useRef, useState } from '../../lib/teact/teact';
import { getActions, getGlobal, withGlobal } from '../../global';

import type { AutolockValueType, Theme } from '../../global/types';

import { AUTOLOCK_OPTIONS_LIST, DEBUG, IS_TELEGRAM_APP } from '../../config';
import {
  selectIsBiometricAuthEnabled,
  selectIsNativeBiometricAuthEnabled,
  selectIsPasswordPresent,
} from '../../global/selectors';
import { getDoesUsePinPad } from '../../util/biometrics';
import buildClassName from '../../util/buildClassName';
import { stopEvent } from '../../util/domEvents';
import { vibrate } from '../../util/haptics';
import { IS_ELECTRON } from '../../util/windowEnvironment';

import useBackgroundMode, { isBackgroundModeActive } from '../../hooks/useBackgroundMode';
import useEffectOnce from '../../hooks/useEffectOnce';
import useFlag from '../../hooks/useFlag';
import useForceUpdate from '../../hooks/useForceUpdate';
import { useHotkeys } from '../../hooks/useHotkeys';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';
import useThrottledCallback from '../../hooks/useThrottledCallback';
import useWindowSize from '../../hooks/useWindowSize';

import { getInAppBrowser } from '../ui/InAppBrowser';
import { triggerPasswordFormHandleBiometrics } from '../ui/PasswordForm';
import Transition from '../ui/Transition';
import PasswordFormSlide from './PasswordFormSlide';
import UnlockButtonSlide from './UnlockButtonSlide';

import styles from './AppLocked.module.scss';

const WINDOW_EVENTS_LATENCY = 5000;
const INTERVAL_CHECK_PERIOD = 5000;
const ACTIVATION_EVENT_NAMES = [
  'focus', // For Web
  'mousemove', // For Web
  'touch', // For Capacitor
  'wheel',
  'keydown',
];
// `capture: true` is necessary because otherwise a `stopPropagation` call inside the main UI will prevent the event
// from getting to the listeners inside `AppLocked`.
const ACTIVATION_EVENT_OPTIONS = { capture: true };

interface StateProps {
  isNonNativeBiometricAuthEnabled: boolean;
  autolockValue?: AutolockValueType;
  theme: Theme;
  isManualLockActive?: boolean;
  isAppLockEnabled?: boolean;
  shouldHideBiometrics?: boolean;
  canRender: boolean;
}

const enum SLIDES {
  button,
  passwordForm,
}

function useAppLockState(autolockValue: AutolockValueType, isManualLockActive: boolean, canRender: boolean) {
  const isFirstRunRef = useRef(true);
  const isLockedRef = useRef(autolockValue !== 'never' || isManualLockActive);
  const lockReasonRef = useRef<'autolock' | 'manual'>();
  const forceUpdate = useForceUpdate();

  // For cases when `canRender` changes from `true` -> `false`, e.g. when all accounts are deleted
  if (isLockedRef.current && !canRender) {
    isLockedRef.current = false;
  }

  const lock = useLastCallback(() => {
    isLockedRef.current = true;
    forceUpdate();
  });

  const unlock = useLastCallback(() => {
    isLockedRef.current = false;
    lockReasonRef.current = undefined;
    forceUpdate();
  });

  // For case when on cold start the app was manually locked at the previous session, this should be treated as a auto lock.
  lockReasonRef.current = isManualLockActive && !(isFirstRunRef.current && autolockValue !== 'never')
    ? 'manual'
    : 'autolock';
  isFirstRunRef.current = false;

  return [!!isLockedRef.current, lock, unlock, lockReasonRef.current] as const;
}

function useContentSlide(
  isNonNativeBiometricAuthEnabled: boolean, isLocked: boolean, lockReason?: 'autolock' | 'manual',
) {
  const ref = useRef<HTMLDivElement>();

  function getDefaultSlideForBiometricAuth() {
    return (
      (isBackgroundModeActive() || lockReason === 'manual')
      && isNonNativeBiometricAuthEnabled ? SLIDES.button : SLIDES.passwordForm
    );
  }

  const [slideForBiometricAuth, setSlideForBiometricAuth] = useState(getDefaultSlideForBiometricAuth());

  // After the first rendering of the password form, it is necessary to remember the `top` position
  // so that when changing the height of the container, there is no shift in content.
  // This logic is only applicable to the two-slides mode except for TMA as it has a pin pad.
  const [innerContentTopPosition, setInnerContentTopPosition] = useState<number>();
  const isFixedState = innerContentTopPosition !== undefined;

  const isFixingSlideEnv = !getDoesUsePinPad() && isNonNativeBiometricAuthEnabled;

  function fixSlide(force?: boolean) {
    const innerContent = ref.current;

    if (innerContent && (!isFixedState || force) && isLocked && isFixingSlideEnv) {
      const top = innerContent.getBoundingClientRect().top;

      setInnerContentTopPosition(top);
    }
  }

  function unfixSlide() {
    setInnerContentTopPosition(undefined);
  }

  function refixSlide() {
    unfixSlide();
    requestAnimationFrame(() => fixSlide(true));
  }

  useEffect(() => {
    fixSlide();
    // eslint-disable-next-line react-hooks-static-deps/exhaustive-deps
  }, [isLocked]);

  const { height } = useWindowSize();

  useEffect(() => {
    if (!isFixingSlideEnv) return;

    refixSlide();
    // eslint-disable-next-line react-hooks-static-deps/exhaustive-deps
  }, [height]);

  return {
    ref,
    innerContentTopPosition,
    unfixSlide,
    slideForBiometricAuth,
    setSlideForBiometricAuth,
    getDefaultSlideForBiometricAuth,
  };
}

function AppLocked({
  isNonNativeBiometricAuthEnabled,
  autolockValue = 'never',
  theme,
  isManualLockActive,
  isAppLockEnabled,
  shouldHideBiometrics,
  canRender,
}: StateProps): TeactJsx {
  const {
    clearIsPinAccepted, setIsManualLockActive, setIsAppLockActive,
  } = getActions();

  const [isLocked, lock, unlock, lockReason] = useAppLockState(autolockValue, !!isManualLockActive, canRender);
  const [shouldRenderUi, showUi, hideUi] = useFlag(isLocked);
  const lastActivityTime = useRef(Date.now());

  const {
    ref,
    innerContentTopPosition,
    unfixSlide,
    slideForBiometricAuth,
    setSlideForBiometricAuth,
    getDefaultSlideForBiometricAuth,
  } = useContentSlide(isNonNativeBiometricAuthEnabled, isLocked, lockReason);

  const handleActivity = useLastCallback(() => {
    lastActivityTime.current = Date.now();
  });

  const handleActivityThrottled = useThrottledCallback(handleActivity, [handleActivity], WINDOW_EVENTS_LATENCY);

  const afterUnlockCallback = useLastCallback(() => {
    hideUi();
    setSlideForBiometricAuth(getDefaultSlideForBiometricAuth());
    getInAppBrowser()?.show();
    clearIsPinAccepted();
    handleActivity();
    setIsManualLockActive({ isActive: undefined, shouldHideBiometrics: undefined });
    unfixSlide();
    setIsAppLockActive({ isActive: false });
    void vibrate();
  });

  const autolockPeriod = useMemo(
    () => AUTOLOCK_OPTIONS_LIST.find((option) => option.value === autolockValue)!.period, [autolockValue],
  );

  const { ref: transitionRef } = useShowTransition({
    isOpen: isLocked,
    noMountTransition: true,
    className: 'slow',
    onCloseAnimationEnd: afterUnlockCallback,
  });

  useEffect(() => {
    if (isLocked !== getGlobal().isAppLockActive) {
      setIsAppLockActive({ isActive: !!isLocked });
    }
  }, [isLocked]);

  const forceLockApp = useLastCallback(() => {
    lock();
    showUi();
    if (document.activeElement) {
      (document.activeElement as HTMLElement).blur();
    }
    void getInAppBrowser()?.hide();
    setSlideForBiometricAuth(getDefaultSlideForBiometricAuth());
    setIsAppLockActive({ isActive: true });
  });

  const handleLock = useLastCallback(() => {
    if ((autolockValue !== 'never' || isManualLockActive) && canRender) forceLockApp();
  });

  if (DEBUG) (window as any).lock = handleLock;

  if (isManualLockActive && !isLocked && !shouldRenderUi) handleLock();

  const handleChangeSlideForBiometricAuth = useLastCallback(() => {
    setSlideForBiometricAuth(SLIDES.passwordForm);
  });

  useEffectOnce(() => {
    for (const eventName of ACTIVATION_EVENT_NAMES) {
      window.addEventListener(eventName, handleActivityThrottled, ACTIVATION_EVENT_OPTIONS);
    }

    return () => {
      for (const eventName of ACTIVATION_EVENT_NAMES) {
        window.removeEventListener(eventName, handleActivityThrottled, ACTIVATION_EVENT_OPTIONS);
      }
    };
  });

  const handleLockScreenHotkey = useLastCallback((e: KeyboardEvent) => {
    stopEvent(e);
    setIsManualLockActive({ isActive: true, shouldHideBiometrics: true });
  });

  useHotkeys(useMemo(() => (isAppLockEnabled && !isLocked ? {
    'Ctrl+Shift+L': handleLockScreenHotkey,
    'Alt+Shift+L': handleLockScreenHotkey,
    'Meta+Shift+L': handleLockScreenHotkey,
    ...(IS_ELECTRON && { 'Mod+L': handleLockScreenHotkey }),
  } : undefined), [isAppLockEnabled, isLocked]));

  useEffect(() => {
    const interval = setInterval(() => {
      if (isAppLockEnabled && !isLocked && Date.now() - lastActivityTime.current > autolockPeriod) {
        handleLock();
      }
    }, INTERVAL_CHECK_PERIOD);
    return () => clearInterval(interval);
  }, [isLocked, autolockPeriod, handleLock, isAppLockEnabled]);

  useBackgroundMode(undefined, handleChangeSlideForBiometricAuth);

  function renderTransitionContent(isActive: boolean) {
    return (
      <div
        className={buildClassName(
          styles.appLocked,
          innerContentTopPosition !== undefined && styles.appLockedFixed,
          getDoesUsePinPad() && slideForBiometricAuth === SLIDES.passwordForm && styles.withPinPad,
        )}
      >
        {
          slideForBiometricAuth === SLIDES.button && isNonNativeBiometricAuthEnabled
            ? (
              <UnlockButtonSlide
                ref={ref}
                theme={theme}
                innerContentTopPosition={innerContentTopPosition}
                handleChangeSlideForBiometricAuth={handleChangeSlideForBiometricAuth}
              />
            )
            : (
              <PasswordFormSlide
                ref={ref}
                isActive={isActive}
                theme={theme}
                innerContentTopPosition={innerContentTopPosition}
                shouldHideBiometrics={!!shouldHideBiometrics}
                onSubmit={unlock}
              />
            )
        }
      </div>
    );
  }

  const transitionKey = Number(slideForBiometricAuth === SLIDES.passwordForm) + Number(shouldRenderUi) * 2;

  const handleUnlockIntent = isNonNativeBiometricAuthEnabled
    ? slideForBiometricAuth === SLIDES.passwordForm
      ? (!IS_TELEGRAM_APP ? triggerPasswordFormHandleBiometrics : undefined)
      : handleChangeSlideForBiometricAuth
    : undefined;

  useHotkeys(useMemo(() => (isAppLockEnabled && isLocked && handleUnlockIntent ? {
    Space: handleUnlockIntent,
    Enter: handleUnlockIntent,
    Escape: handleUnlockIntent,
  } : undefined), [isAppLockEnabled, isLocked, handleUnlockIntent]));

  return (
    <Transition
      ref={transitionRef}
      name={isNonNativeBiometricAuthEnabled && IS_TELEGRAM_APP ? 'slideFade' : 'semiFade'}
      onContainerClick={handleUnlockIntent}
      activeKey={transitionKey}
      className={styles.appLockedWrapper}
      shouldCleanup
    >
      {shouldRenderUi ? renderTransitionContent : undefined}
    </Transition>
  );
}

export default memo(withGlobal((global): StateProps => {
  const { autolockValue, isAppLockEnabled } = global.settings;

  const isPasswordPresent = selectIsPasswordPresent(global);

  const isBiometricAuthEnabled = selectIsBiometricAuthEnabled(global);
  const isNativeBiometricAuthEnabled = selectIsNativeBiometricAuthEnabled(global);
  const isNonNativeBiometricAuthEnabled = isBiometricAuthEnabled && (!isNativeBiometricAuthEnabled || IS_TELEGRAM_APP);

  return {
    isNonNativeBiometricAuthEnabled,
    autolockValue,
    canRender: Boolean(isAppLockEnabled && isPasswordPresent),
    isAppLockEnabled,
    theme: global.settings.theme,
    isManualLockActive: global.isManualLockActive,
    shouldHideBiometrics: global.appLockHideBiometrics,
  };
})(AppLocked));

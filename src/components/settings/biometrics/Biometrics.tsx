import React, { memo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import { BiometricsState } from '../../../global/types';

import BiometricsTurnOff from './TurnOff';
import BiometricsTurnOffWarning from './TurnOffWarning';
import BiometricsTurnOn from './TurnOn';

interface StateProps {
  state: BiometricsState;
  error?: string;
  isLoading?: boolean;
}

function Biometrics({
  state, error, isLoading,
}: StateProps) {
  const { closeBiometricSettings } = getActions();

  const isTurnOnBiometricsOpened = state === BiometricsState.TurnOnPasswordConfirmation
    || state === BiometricsState.TurnOnRegistration
    || state === BiometricsState.TurnOnVerification
    || state === BiometricsState.TurnOnComplete;
  const isTurnOffBiometricsOpened = state === BiometricsState.TurnOffBiometricConfirmation
    || state === BiometricsState.TurnOffCreatePassword
    || state === BiometricsState.TurnOffComplete;
  const isTurnOffBiometricsWarningOpened = state === BiometricsState.TurnOffWarning;

  return (
    <>
      <BiometricsTurnOn
        isOpen={isTurnOnBiometricsOpened}
        isLoading={isLoading}
        state={state}
        error={error}
        onClose={closeBiometricSettings}
      />
      <BiometricsTurnOff
        isOpen={isTurnOffBiometricsOpened}
        isLoading={isLoading}
        state={state}
        error={error}
        onClose={closeBiometricSettings}
      />
      <BiometricsTurnOffWarning isOpen={isTurnOffBiometricsWarningOpened} onClose={closeBiometricSettings} />
    </>
  );
}

export default memo(withGlobal((global) => {
  const { biometrics: { state, error } } = global;

  return {
    state,
    error,
    isLoading: global.auth.isLoading,
  };
})(Biometrics));

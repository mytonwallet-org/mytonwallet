import React, { memo, useRef, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { GlobalState, Theme } from '../../global/types';
import { AuthState } from '../../global/types';

import { selectIsBiometricAuthEnabled } from '../../global/selectors';
import { pick } from '../../util/iteratees';
import { IS_ANDROID } from '../../util/windowEnvironment';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLastCallback from '../../hooks/useLastCallback';

import SettingsAbout from '../settings/SettingsAbout';
import Transition from '../ui/Transition';
import AuthCheckPassword from './AuthCheckPassword';
import AuthCheckWords from './AuthCheckWords';
import AuthConfirmBiometrics from './AuthConfirmBiometrics';
import AuthConfirmPin from './AuthConfirmPin';
import AuthCongratulations from './AuthCongratulations';
import AuthCreateBiometrics from './AuthCreateBiometrics';
import AuthCreateNativeBiometrics from './AuthCreateNativeBiometrics';
import AuthCreatePassword from './AuthCreatePassword';
import AuthCreatePin from './AuthCreatePin';
import AuthCreatingWallet from './AuthCreatingWallet';
import AuthDisclaimer from './AuthDisclaimer';
import AuthImportMnemonic from './AuthImportMnemonic';
import AuthImportViewAccount from './AuthImportViewAccount';
import AuthSafetyRules from './AuthSafetyRules';
import AuthSecretWords from './AuthSecretWords';
import AuthStart from './AuthStart';

import styles from './Auth.module.scss';

type StateProps = Pick<GlobalState['auth'], (
  'state' | 'biometricsStep' | 'error' | 'mnemonic' | 'mnemonicCheckIndexes' | 'isLoading' | 'method'
  | 'hardwareSelectedIndices'
)> & { theme: Theme; isBiometricAuthEnabled?: boolean };

const RENDER_COUNT = Object.keys(AuthState).length / 2;

const Auth = ({
  state,
  biometricsStep,
  error,
  isLoading,
  mnemonic,
  mnemonicCheckIndexes,
  hardwareSelectedIndices,
  method,
  theme,
  isBiometricAuthEnabled,
}: StateProps) => {
  const {
    closeAbout,
    closeImportViewAccount,
  } = getActions();

  const containerRef = useRef<HTMLDivElement>();
  const { isPortrait } = useDeviceScreen();

  // Transitioning to ready state is done in another component
  const renderingAuthState = useCurrentOrPrev(
    state === AuthState.ready ? undefined : state,
    true,
  ) ?? -1;

  const [prevKey, setPrevKey] = useState<AuthState | undefined>(undefined);
  const [nextKey, setNextKey] = useState(renderingAuthState + 1);
  const updateRenderingKeys = useLastCallback(() => {
    setNextKey(renderingAuthState + 1);
    setPrevKey(renderingAuthState === AuthState.confirmPin ? AuthState.createPin : undefined);
  });

  function renderAuthScreen(isActive: boolean, isFrom: boolean, currentKey: AuthState) {
    switch (currentKey) {
      case AuthState.none:
        return <AuthStart isActive={isActive} />;
      case AuthState.createWallet:
        return <AuthCreatingWallet isActive={isActive} />;
      case AuthState.checkPassword:
        return (
          <AuthCheckPassword
            isActive={isActive}
            isLoading={isLoading}
            method="createAccount"
            isBiometricAuthEnabled={isBiometricAuthEnabled}
            error={error}
          />
        );
      case AuthState.createPin:
        return <AuthCreatePin isActive={isActive} method="createAccount" />;
      case AuthState.confirmPin:
        return <AuthConfirmPin isActive={isActive} method="createAccount" />;
      case AuthState.createBiometrics:
        return <AuthCreateBiometrics isActive={isActive} method="createAccount" />;
      case AuthState.confirmBiometrics:
        return (
          <AuthConfirmBiometrics
            isActive={isActive}
            isLoading={isLoading}
            error={error}
            biometricsStep={biometricsStep}
          />
        );
      case AuthState.createNativeBiometrics:
        return (
          <AuthCreateNativeBiometrics isActive={isActive} isLoading={isLoading} />
        );
      case AuthState.createPassword:
        return <AuthCreatePassword isActive={isActive} isLoading={isLoading} method="createAccount" />;
      case AuthState.disclaimerAndBackup:
        return (
          <AuthDisclaimer key="create" isActive={isActive} />
        );
      case AuthState.importWallet:
        return <AuthImportMnemonic isActive={isActive} />;
      case AuthState.importWalletCreatePin:
        return <AuthCreatePin isActive={isActive} method="importMnemonic" />;
      case AuthState.importWalletConfirmPin:
        return <AuthConfirmPin isActive={isActive} method="importMnemonic" />;
      case AuthState.importWalletCheckPassword:
        return (
          <AuthCheckPassword
            isActive={isActive}
            isLoading={isLoading}
            method="importMnemonic"
            isBiometricAuthEnabled={isBiometricAuthEnabled}
            error={error}
          />
        );
      case AuthState.disclaimer:
        return (
          <AuthDisclaimer
            key="import"
            isActive={isActive}
          />
        );
      case AuthState.importWalletCreateNativeBiometrics:
        return (
          <AuthCreateNativeBiometrics isActive={isActive} isLoading={isLoading} />
        );
      case AuthState.importWalletCreatePassword:
        return <AuthCreatePassword isActive={isActive} isLoading={isLoading} method={method} />;
      case AuthState.importWalletCreateBiometrics:
        return <AuthCreateBiometrics isActive={isActive} method={method} />;
      case AuthState.importWalletConfirmBiometrics:
        return (
          <AuthConfirmBiometrics
            isActive={isActive}
            isLoading={isLoading}
            error={error}
            biometricsStep={biometricsStep}
          />
        );
      case AuthState.about:
        return (
          <SettingsAbout
            isActive={isActive}
            theme={theme}
            slideClassName={styles.aboutSlide}
            handleBackClick={closeAbout}
          />
        );
      case AuthState.safetyRules:
        return <AuthSafetyRules isActive={isActive} />;
      case AuthState.mnemonicPage:
        return <AuthSecretWords isActive={isActive} mnemonic={mnemonic} />;
      case AuthState.checkWords:
        return <AuthCheckWords isActive={isActive} mnemonic={mnemonic} checkIndexes={mnemonicCheckIndexes} />;
      case AuthState.importViewAccount:
        return (
          <AuthImportViewAccount
            isActive={isActive}
            isLoading={isLoading}
            onCancel={closeImportViewAccount}
          />
        );
      case AuthState.congratulations:
        return (
          <AuthCongratulations
            isActive={isActive}
            hardwareWalletsAmount={hardwareSelectedIndices?.length}
            isImporting={Boolean(hardwareSelectedIndices?.length)}
          />
        );
      case AuthState.importCongratulations:
        return <AuthCongratulations isActive={isActive} isImporting />;
    }
  }

  return (
    <Transition
      ref={containerRef}
      name={isPortrait ? (IS_ANDROID ? 'slideFade' : 'slideLayers') : 'semiFade'}
      activeKey={renderingAuthState}
      renderCount={RENDER_COUNT}
      shouldCleanup
      shouldWrap
      className={styles.transitionContainer}
      slideClassName={styles.transitionSlide}
      prevKey={prevKey}
      nextKey={nextKey}
      onStop={updateRenderingKeys}
    >
      {renderAuthScreen}
    </Transition>
  );
};

export default memo(withGlobal((global): StateProps => {
  const authProps = pick(global.auth, [
    'state', 'biometricsStep', 'error', 'mnemonic', 'mnemonicCheckIndexes', 'isLoading', 'method',
    'hardwareSelectedIndices',
  ]);
  const isBiometricAuthEnabled = selectIsBiometricAuthEnabled(global);
  return {
    ...authProps,
    theme: global.settings.theme,
    isBiometricAuthEnabled,
  };
})(Auth));

import React, { memo, useRef, useState } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { GlobalState } from '../../global/types';
import { AuthState } from '../../global/types';

import { IS_EXPLORER, IS_GRAM_WALLET } from '../../config';
import { selectIsBiometricAuthEnabled } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { pick } from '../../util/iteratees';
import { CAN_AUTHENTICATE_WITH_BIOMETRIC_ONLY, IS_ANDROID, IS_WEB } from '../../util/windowEnvironment';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLastCallback from '../../hooks/useLastCallback';

import SettingsAbout from '../settings/SettingsAbout';
import Transition from '../ui/Transition';
import AuthCheckPassword from './AuthCheckPassword';
import AuthCheckWords from './AuthCheckWords';
import AuthChooseProtection from './AuthChooseProtection';
import AuthConfirmPin from './AuthConfirmPin';
import AuthCongratulations from './AuthCongratulations';
import AuthCreateBiometrics from './AuthCreateBiometrics';
import AuthCreatePassword from './AuthCreatePassword';
import AuthCreatePin from './AuthCreatePin';
import AuthCreatingWallet from './AuthCreatingWallet';
import AuthImportMnemonic from './AuthImportMnemonic';
import AuthImportViewAccount from './AuthImportViewAccount';
import AuthSafetyRules from './AuthSafetyRules';
import AuthSecretWords from './AuthSecretWords';
import AuthStart from './AuthStart';
import GramAuthStart from './GramAuthStart';

import styles from './Auth.module.scss';

type StateProps = Pick<GlobalState['auth'], (
  'state' | 'error' | 'mnemonic' | 'mnemonicCheckIndexes' | 'isLoading' | 'method'
  | 'hardwareSelectedIndices'
)> & { isBiometricAuthEnabled?: boolean };

const RENDER_COUNT = Object.keys(AuthState).length / 2;
const IS_GRAM_WEB = IS_GRAM_WALLET && IS_WEB && !IS_EXPLORER;

const Auth = ({
  state,
  error,
  isLoading,
  mnemonic,
  mnemonicCheckIndexes,
  hardwareSelectedIndices,
  method,
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
        return IS_GRAM_WEB
          ? <GramAuthStart isActive={isActive} />
          : <AuthStart isActive={isActive} />;
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
        return <AuthCreatePin isActive={isActive} method="createAccount" error={error} />;
      case AuthState.confirmPin:
        return <AuthConfirmPin isActive={isActive} method="createAccount" />;
      case AuthState.createBiometrics:
        return CAN_AUTHENTICATE_WITH_BIOMETRIC_ONLY
          ? <AuthChooseProtection isActive={isActive} isLoading={isLoading} error={error} />
          : <AuthCreateBiometrics isActive={isActive} isLoading={isLoading} error={error} />;
      case AuthState.createPassword:
        return <AuthCreatePassword isActive={isActive} isLoading={isLoading} method="createAccount" />;
      case AuthState.importWallet:
        return <AuthImportMnemonic isActive={isActive} />;
      case AuthState.importWalletCreatePin:
        return <AuthCreatePin isActive={isActive} method="importMnemonic" error={error} />;
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
      case AuthState.importWalletCreateBiometrics:
        return CAN_AUTHENTICATE_WITH_BIOMETRIC_ONLY
          ? <AuthChooseProtection isActive={isActive} isLoading={isLoading} isImporting error={error} />
          : <AuthCreateBiometrics isActive={isActive} isLoading={isLoading} error={error} />;
      case AuthState.importWalletCreatePassword:
        return <AuthCreatePassword isActive={isActive} isLoading={isLoading} method={method} />;
      case AuthState.about:
        return (
          <SettingsAbout
            isActive={isActive}
            slideClassName={IS_GRAM_WEB ? styles.gramAboutSlide : undefined}
            onBackClick={closeAbout}
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
      cleanupExceptionKey={IS_GRAM_WEB ? AuthState.none : undefined}
      shouldWrap
      className={buildClassName(styles.transitionContainer,
        IS_GRAM_WEB && styles.gramWelcome)}
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
    'state', 'error', 'mnemonic', 'mnemonicCheckIndexes', 'isLoading', 'method',
    'hardwareSelectedIndices',
  ]);
  const isBiometricAuthEnabled = selectIsBiometricAuthEnabled(global);
  return {
    ...authProps,
    isBiometricAuthEnabled,
  };
})(Auth));

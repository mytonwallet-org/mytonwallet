import { IS_TELEGRAM_APP } from '../../../config';
import { CHANNEL_NAME } from '../../config';
import { createPostMessageInterface } from '../../../util/createPostMessageInterface';
import { IS_ELECTRON } from '../../../util/windowEnvironment';
import * as enclaveApi from '../../enclave';
import * as legacyMigrationApi from '../../legacyMigration';
import idbStorage from '../../storage/idb';

const enclaveRpcApi = { ...enclaveApi, ...legacyMigrationApi };

createPostMessageInterface(enclaveRpcApi, CHANNEL_NAME, window, true, window.location.origin);

void enclaveApi.setupStorage(idbStorage);

void (async () => {
  const { default: BiometricAuthClass } = IS_TELEGRAM_APP
    ? await import('../../auth/TelegramAuth')
    : (IS_ELECTRON
      ? await import('../../auth/ElectronAuth')
      : await import('../../auth/WebAuthnAuth')
    );

  void enclaveApi.setupBiometricAuthClass(BiometricAuthClass);
})();

import { AppState, AuthState } from '../../types';

import { addActionHandler, setGlobal } from '../../index';
import { resetAuthToStartScreen, resetHardware, updateAuth } from '../../reducers';
import { selectCurrentAccountId } from '../../selectors';

addActionHandler('openAbout', (global) => {
  setGlobal(updateAuth(global, { state: AuthState.about, error: undefined }));
});

addActionHandler('closeAbout', (global) => {
  return resetAuthToStartScreen(global);
});

addActionHandler('openDisclaimer', (global) => {
  setGlobal(updateAuth(global, { state: AuthState.disclaimer, error: undefined }));
});

addActionHandler('closeDisclaimer', (global) => {
  return resetAuthToStartScreen(global);
});

addActionHandler('startImportViewAccount', (global) => {
  setGlobal(updateAuth(global, { state: AuthState.importViewAccount, error: undefined }));
});

addActionHandler('closeImportViewAccount', (global) => {
  return resetAuthToStartScreen(global);
});

addActionHandler('cancelCheckPassword', (global) => {
  global = resetAuthToStartScreen(global);

  // The screen is shown inside the auth flow even for a signed-in user adding a wallet, so backing out
  // of it has to return them to their wallet rather than to the sign-in intro
  return selectCurrentAccountId(global)
    ? { ...global, appState: AppState.Main }
    : global;
});

addActionHandler('openAuthImportWalletModal', (global) => {
  global = updateAuth(global, { isImportModalOpen: true });
  setGlobal(global);
});

addActionHandler('closeAuthImportWalletModal', (global) => {
  global = updateAuth(global, { isImportModalOpen: undefined });
  setGlobal(global);
});

addActionHandler('cleanAuthError', (global) => {
  setGlobal(updateAuth(global, { error: undefined }));
});

addActionHandler('openHardwareWalletModal', (global, actions, { chain }) => {
  global = resetHardware(global, chain, true);

  return { ...global, isHardwareModalOpen: true };
});

addActionHandler('closeHardwareWalletModal', (global) => {
  return { ...global, isHardwareModalOpen: false };
});

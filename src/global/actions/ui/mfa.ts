import { addActionHandler, setGlobal } from '../..';
import { updateInstallMfa, updateRemoveMfa } from '../../reducers';

addActionHandler('clearInstallMfaError', (global) => {
  // The disconnection screen shares the password form and has no install request. Writing to it there would
  // create an empty request, and the screen would switch to installation.
  if (!global.settings.installMfa?.error) return;

  global = updateInstallMfa(global, { error: undefined });
  setGlobal(global);
});

addActionHandler('clearRemoveMfaError', (global) => {
  global = updateRemoveMfa(global, { error: undefined });
  setGlobal(global);
});

import { addActionHandler, setGlobal } from '../..';
import { updateInstallMfa, updateRemoveMfa } from '../../reducers';

addActionHandler('clearInstallMfaError', (global) => {
  global = updateInstallMfa(global, { error: undefined });
  setGlobal(global);
});

addActionHandler('clearRemoveMfaError', (global) => {
  global = updateRemoveMfa(global, { error: undefined });
  setGlobal(global);
});

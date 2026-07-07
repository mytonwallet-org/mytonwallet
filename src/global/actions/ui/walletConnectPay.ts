import { addActionHandler, setGlobal } from '../../index';
import { updateCurrentWalletConnectPay } from '../../reducers';

addActionHandler('clearWalletConnectPayError', (global) => {
  global = updateCurrentWalletConnectPay(global, { error: undefined });
  setGlobal(global);
});

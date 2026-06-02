import { MFA_BOT_URL } from '../../../config';
import { buildMfaStartParam } from '../../../util/mfa';
import { callApi } from '../../../api';
import { openSite } from '../../../components/explore/helpers/utils';
import { addActionHandler, getGlobal, setGlobal } from '../..';
import { updateAccount, updateInstallMfa, updateRemoveMfa, updateSettings } from '../../reducers';
import { selectCurrentAccount, selectCurrentAccountId } from '../../selectors';

addActionHandler('updateInstallMfaRequest', async (global) => {
  const reqId = global.settings.installMfa?.requestId;
  if (!reqId) return;

  const result = await callApi('fetchInstallMfaRequest', reqId);
  global = getGlobal();

  if (result?.user && !global.settings.installMfa?.user) {
    global = updateInstallMfa(global, { user: result.user });
    setGlobal(global);
  }
});

addActionHandler('submitInstallMfa', async (global, actions, { password }) => {
  const accountId = selectCurrentAccountId(global)!;
  const account = selectCurrentAccount(global)!;
  const { user } = global.settings.installMfa!;

  if (!user) return;

  global = updateSettings(global, { installMfa: undefined });
  setGlobal(global);

  const result = await callApi('installMfaFromRequest', accountId, user, password);
  if (typeof result === 'object' && 'error' in result) return;

  global = getGlobal();
  global = updateAccount(
    global,
    accountId,
    {
      byChain: {
        ...account.byChain,
        ton: { ...account.byChain.ton!, mfa: {
          address: result!,
          user,
        } },
      },
    },
  );
  setGlobal(global);
});

addActionHandler('clearMfaRequests', (global) => {
  global = updateSettings(global, { installMfa: undefined, removeMfa: undefined });
  setGlobal(global);
});

addActionHandler('submitRemoveMfa', async (global, _, { password }) => {
  const accountId = selectCurrentAccountId(global)!;

  const result = await callApi('publishRemoveMfaRequest', accountId, password);
  if (!result || 'error' in result) return;

  global = getGlobal();
  global = updateRemoveMfa(global, { requestId: result.reqId });
  setGlobal(global);

  const url = new URL(MFA_BOT_URL);
  url.searchParams.set('startapp', buildMfaStartParam(result.reqId));
  openSite(url.toString(), true);
});

addActionHandler('updateRemoveMfaRequest', async (global) => {
  const accountId = selectCurrentAccountId(global)!;
  const account = selectCurrentAccount(global)!;

  const { requestId } = global.settings.removeMfa!;
  if (!requestId) return;

  const result = await callApi('fetchMfaRequest', requestId);
  global = getGlobal();

  if (result?.isConfirmed && global.settings.removeMfa) {
    global = updateSettings(global, { removeMfa: undefined });
    global = updateAccount(
      global,
      accountId,
      {
        byChain: {
          ...account.byChain,
          ton: { ...account.byChain.ton!, mfa: undefined },
        },
      },
    );
    setGlobal(global);

    await callApi('confirmMfaRemovalRequest', accountId);
  }
});

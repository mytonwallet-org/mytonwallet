import { MFA_BOT_URL } from '../../../config';
import { buildMfaStartParam } from '../../../util/mfa';
import { callApi } from '../../../api';
import { openSite } from '../../../components/explore/helpers/utils';
import { addActionHandler, getGlobal, setGlobal } from '../..';
import { withEnclaveSessionRelease } from '../../helpers/enclave';
import { errorCodeToMessage } from '../../helpers/errors';
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

addActionHandler('submitInstallMfa', withEnclaveSessionRelease(async (global, actions, { enclaveToken }) => {
  const accountId = selectCurrentAccountId(global)!;
  const { requestId, user } = global.settings.installMfa!;

  if (!user) return;

  setGlobal(updateInstallMfa(global, { error: undefined }));

  // On success the API saves the extension to the account and sends `updateAccount` itself, so the account
  // is not updated here
  const result = await callApi('installMfaFromRequest', accountId, user, enclaveToken);

  // While the extension was being installed, the user may have left the screen, which clears the request,
  // or started a new one. Either way this result is outdated, so it is ignored.
  global = getGlobal();
  const { installMfa } = global.settings;
  if (installMfa?.requestId !== requestId) return;

  if (typeof result !== 'string') {
    setGlobal(updateInstallMfa(global, {
      error: errorCodeToMessage(result?.error),
      failedAttemptCount: (installMfa.failedAttemptCount ?? 0) + 1,
    }));
    return;
  }

  setGlobal(updateSettings(global, { installMfa: undefined }));
}));

addActionHandler('clearMfaRequests', (global) => {
  global = updateSettings(global, { installMfa: undefined, removeMfa: undefined });
  setGlobal(global);
});

addActionHandler('submitRemoveMfa', withEnclaveSessionRelease(async (global, _, { enclaveToken }) => {
  const accountId = selectCurrentAccountId(global)!;

  const result = await callApi('publishRemoveMfaRequest', accountId, enclaveToken);
  if (!result || 'error' in result) return;

  global = getGlobal();
  global = updateRemoveMfa(global, { requestId: result.reqId });
  setGlobal(global);

  const url = new URL(MFA_BOT_URL);
  url.searchParams.set('startapp', buildMfaStartParam(result.reqId));
  openSite(url.toString(), true);
}));

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

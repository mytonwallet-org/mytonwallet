import { MFA_BOT_URL } from '../../../config';
import { buildMfaStartParam } from '../../../util/mfa';
import { callApi } from '../../../api';
import { openSite } from '../../../components/explore/helpers/utils';
import { addActionHandler, getGlobal, setGlobal } from '../..';
import { updateSettings } from '../../reducers';
import { selectCurrentAccountId } from '../../selectors';

addActionHandler('createInstallMfaRequest', async (global) => {
  const accountId = selectCurrentAccountId(global)!;
  const result = await callApi('publishInstallMfaRequest', accountId);

  global = getGlobal();
  global = updateSettings(global, { installMfa: { requestId: result!.reqId } });
  setGlobal(global);

  const url = new URL(MFA_BOT_URL);
  url.searchParams.set('startapp', buildMfaStartParam(`i-${result!.reqId}`));
  openSite(url.toString(), true);
});

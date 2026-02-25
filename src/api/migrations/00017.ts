import type { StoredDappConnection } from '../dappProtocols/storage';

import { getDappConnectionUniqueId } from '../../util/getDappConnectionUniqueId';
import { storage } from '../storages';

export async function start() {
  // Previous schema: Record<accountId, Record<url, ApiDapp>>
  // New schema:     Record<accountId, Record<url, Record<uniqueId, ApiDapp>>>
  // just use new type bc it has backawards compat w/ old one
  const oldState: Record<string, Record<string, StoredDappConnection>> | undefined = await storage.getItem('dapps');

  if (!oldState) return;

  const newState: Record<string, Record<string, Record<string, StoredDappConnection>>> = {};

  for (const [accountId, byUrl] of Object.entries(oldState)) {
    newState[accountId] = {};

    for (const [url, dapp] of Object.entries(byUrl)) {
      const uniqueId = getDappConnectionUniqueId(dapp);
      newState[accountId][url] = { [uniqueId]: dapp };
    }
  }

  await storage.setItem('dapps', newState);
}

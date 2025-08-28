import { randomBytes } from '../../util/random';
import { storage } from '../storages';

let clientId: string | undefined;
let referrer: string | undefined;

export async function getClientId() {
  if (!clientId) {
    [clientId, referrer] = await Promise.all([
      storage.getItem('clientId'),
      storage.getItem('referrer'),
    ]);
  }

  if (clientId) {
    const parts = clientId.split(':', 1);
    if (!parts[1] && referrer) {
      clientId = `${parts[0]}:${referrer}`;
      void storage.setItem('clientId', clientId);
    }
  } else {
    const hex = Buffer.from(randomBytes(10)).toString('hex');
    clientId = `${hex}:${referrer ?? ''}`;
    void storage.setItem('clientId', clientId);
  }

  return clientId;
}

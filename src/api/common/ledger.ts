import Transport from '@ledgerhq/hw-transport';

import { IS_AIR_APP } from '../../config';
import { callWindow } from '../../util/windowProvider/connector';

/**
 * Serialization format differs between web/capacitor and native apps:
 *  - Native (AIR) apps: Use hex format (expected by native Ledger library implementations)
 *  - Web/Capacitor apps: Use base64 format (more efficient for browser message passing)
 */
const serializationFormat = IS_AIR_APP ? 'hex' : 'base64';

/**
 * A Ledger's Transport implementation that passes the data to the actual transfer object in the main browser thread
 * (src/util/ledger/index.ts) via postMessage (because actual Ledger transports don't work in worker threads).
 */
export class WindowTransport extends Transport {
  async exchange(apdu: Buffer) {
    const response = await callWindow('exchangeWithLedger', apdu.toString(serializationFormat));
    return Buffer.from(response, serializationFormat);
  }
}

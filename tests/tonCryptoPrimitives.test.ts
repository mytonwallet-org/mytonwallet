import { createHmac, pbkdf2Sync } from 'node:crypto';
import { Worker } from 'node:worker_threads';

const WORKER_SOURCE = `
  const { parentPort, workerData } = require('node:worker_threads');
  const { webcrypto } = require('node:crypto');
  Object.defineProperty(globalThis, 'crypto', { value: webcrypto });
  const primitives = require(workerData);

  (async () => {
    parentPort.postMessage({
      hasWindow: typeof window !== 'undefined',
      randomByteCount: primitives.getSecureRandomBytes(32).length,
      randomWordCount: primitives.getSecureRandomWords(24).length,
      hmac: (await primitives.hmac_sha512('key', 'message')).toString('hex'),
      seed: (await primitives.pbkdf2_sha512('password', 'salt', 2, 64)).toString('hex'),
    });
  })().catch((error) => { throw error; });
`;

it('runs the browser TON crypto primitives in a worker without window', async () => {
  const worker = new Worker(WORKER_SOURCE, {
    eval: true,
    workerData: require.resolve('@ton/crypto-primitives/dist/browser'),
  });

  try {
    const result = await new Promise((resolve, reject) => {
      worker.once('message', resolve);
      worker.once('error', reject);
      worker.once('exit', (code) => reject(new Error(`Crypto worker exited before returning a result: ${code}`)));
    });

    expect(result).toEqual({
      hasWindow: false,
      randomByteCount: 32,
      randomWordCount: 24,
      hmac: createHmac('sha512', 'key').update('message').digest('hex'),
      seed: pbkdf2Sync('password', 'salt', 2, 64, 'sha512').toString('hex'),
    });
  } finally {
    await worker.terminate();
  }
});

import { deriveKeyFromRandom } from './deriveKey';

describe('deriveKeyFromRandom', () => {
  it('imports key material of the full size', async () => {
    const key = await deriveKeyFromRandom(new ArrayBuffer(32));

    expect(key.algorithm).toEqual({ name: 'AES-GCM', length: 256 });
  });

  // `importKey` would accept these as AES-128 and AES-192 and say nothing
  it.each([16, 24])('refuses %d bytes of key material', async (byteLength) => {
    await expect(deriveKeyFromRandom(new ArrayBuffer(byteLength)))
      .rejects.toThrow(`Key material is ${byteLength} bytes, expected 32`);
  });

  it('refuses an empty buffer', async () => {
    await expect(deriveKeyFromRandom(new ArrayBuffer(0))).rejects.toThrow('expected 32');
  });
});

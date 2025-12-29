import { getWalletFromPrivateKey } from './auth';

describe('getWalletFromPrivateKey', () => {
  it('produces proper address and public key', () => {
    const privateKey = '28633b060aaec177c4808112dbab1f23984dd3ffa427f79a217ad4fdc39e995c';
    const publicKey = '04ccf3d5b64c4e1c6d59818d84456bb5692292416d0405dc2cb599a8af8385c1602eef13e26ac0015064abca5c818a845cd7568cb104b99b3333ae5282485e1e32'; // eslint-disable-line @stylistic/max-len
    const address = 'TXYfcZv45Km5DdP5oRZyn5recuh8XeG7LT';

    expect(getWalletFromPrivateKey('mainnet', privateKey)).toMatchObject({ address, publicKey });
  });
});

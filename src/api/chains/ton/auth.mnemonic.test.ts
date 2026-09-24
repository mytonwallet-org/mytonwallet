import { wordlists } from 'bip39';
import nacl from 'tweetnacl';
import { WalletContractV4 } from '@ton/ton/dist/wallets/WalletContractV4';

import type { ApiTonAccount } from '../../types';

import { deriveMnemonicKeyPair } from '../../../../dev/mfa/mnemonic';
import { TON_MNEMONIC_VECTORS } from '../../../../tests/fixtures/tonMnemonic';
import { validateBip39Mnemonic } from '../../common/mnemonic';
import { getMnemonicWordList } from '../../methods/wallet';
import { generateMnemonic, getKeyPairFromStoredMnemonic, validateMnemonic } from './auth';

const ACCOUNT: ApiTonAccount = { type: 'ton', byChain: {} };
const SIGNING_MESSAGE = new TextEncoder().encode('TON mnemonic migration test');

describe('TON mnemonic compatibility', () => {
  it.each(TON_MNEMONIC_VECTORS)('preserves keys, address and signature for $address', async (vector) => {
    const mnemonic = vector.mnemonic.split(' ');
    const keyPair = await getKeyPairFromStoredMnemonic(mnemonic, ACCOUNT);

    expect(await deriveMnemonicKeyPair(mnemonic)).toEqual(keyPair);
    expect(await validateMnemonic(mnemonic)).toBe(true);
    expect(Buffer.from(keyPair.publicKey).toString('hex')).toBe(vector.publicKey);
    expect(Buffer.from(keyPair.secretKey).toString('hex')).toBe(vector.secretKey);
    expect(Buffer.isBuffer(keyPair.publicKey)).toBe(false);
    expect(Buffer.isBuffer(keyPair.secretKey)).toBe(false);
    expect(WalletContractV4.create({ workchain: 0, publicKey: Buffer.from(keyPair.publicKey) }).address.toRawString())
      .toBe(vector.address);
    expect(Buffer.from(nacl.sign.detached(SIGNING_MESSAGE, keyPair.secretKey)).toString('hex')).toBe(vector.signature);
  });

  it.each(TON_MNEMONIC_VECTORS)('does not normalize stored words for $address', async (vector) => {
    const words = vector.mnemonic.split(' ');
    const uppercase = words.map((word) => word.toUpperCase());
    const padded = words.map((word) => ` ${word} `);

    expect(Buffer.from((await deriveMnemonicKeyPair(uppercase)).publicKey).toString('hex'))
      .toBe(vector.uppercasePublicKey);
    expect(Buffer.from((await deriveMnemonicKeyPair(padded)).publicKey).toString('hex'))
      .toBe(vector.paddedPublicKey);
    expect(await validateMnemonic(uppercase)).toBe(false);
    expect(await validateMnemonic(padded)).toBe(false);
    expect(Buffer.from((await getKeyPairFromStoredMnemonic(uppercase, ACCOUNT)).publicKey).toString('hex'))
      .toBe(vector.uppercasePublicKey);
    expect(Buffer.from((await getKeyPairFromStoredMnemonic(padded, ACCOUNT)).publicKey).toString('hex'))
      .toBe(vector.paddedPublicKey);
  });

  it.each([
    [],
    Array(24).fill('abandon'),
    [...TON_MNEMONIC_VECTORS[0].mnemonic.split(' ').slice(0, 23), 'notaword'],
  ])('rejects invalid mnemonic %#', async (...mnemonic) => {
    expect(await validateMnemonic(mnemonic)).toBe(false);
  });

  it('preserves the ordered English recovery word list', () => {
    expect(getMnemonicWordList()).toHaveLength(2048);
    expect(getMnemonicWordList()).toEqual(wordlists.english);
  });

  it('generates 24 TON words that cannot be interpreted as BIP39', async () => {
    const mnemonic = await generateMnemonic();

    expect(mnemonic).toHaveLength(24);
    expect(await validateMnemonic(mnemonic)).toBe(true);
    expect(validateBip39Mnemonic(mnemonic)).toBe(false);
  });
});

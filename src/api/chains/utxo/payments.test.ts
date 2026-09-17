import { HDKey } from '@scure/bip32';
import { Transaction } from '@scure/btc-signer';
import * as bip39 from 'bip39';

import { getUtxoDerivationPaths } from './constants';
import {
  createUtxoPayment,
  getAddressTypeFromAddress,
  getAddressTypeFromPathTemplate,
  getUtxoLockingScripts,
} from './payment';

const BIP39_VECTOR_MNEMONIC = (
  'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about'
).split(' ');

function deriveChild(path: string): { publicKey: Uint8Array; privateKey: Uint8Array } {
  const seed = new Uint8Array(bip39.mnemonicToSeedSync(BIP39_VECTOR_MNEMONIC.join(' ')));
  const child = HDKey.fromMasterSeed(seed).derive(path);

  if (!child.publicKey || !child.privateKey) {
    throw new Error('Failed to derive test key');
  }

  return {
    publicKey: child.publicKey,
    privateKey: child.privateKey,
  };
}

describe('UTXO wrapped segwit', () => {
  it('uses BIP49 paths for bitcoin and litecoin only', () => {
    expect(getUtxoDerivationPaths('bitcoin')['wrapped-segwit']).toBe(`m/49'/0'/0'/0/{index}`);
    expect(getUtxoDerivationPaths('litecoin')['wrapped-segwit']).toBe(`m/49'/2'/0'/0/{index}`);
    expect(getUtxoDerivationPaths('bitcoincash')['wrapped-segwit']).toBeUndefined();
    expect(getUtxoDerivationPaths('dogecoin')['wrapped-segwit']).toBeUndefined();
  });

  it('detects wrapped segwit from BIP49 paths and P2SH prefixes', () => {
    expect(getAddressTypeFromPathTemplate(`m/49'/0'/0'/0/{index}`)).toBe('wrapped-segwit');
    expect(getAddressTypeFromPathTemplate(`m/49'/2'/0'/0/0`)).toBe('wrapped-segwit');
    expect(getAddressTypeFromPathTemplate(`m/84'/0'/0'/0/0`)).toBe('segwit');
    expect(getAddressTypeFromPathTemplate(`m/44'/0'/0'/0/0`)).toBe('legacy');

    expect(getAddressTypeFromAddress('37VucYSaXLCAsxYyAPfbSi9eh4iEcbShgf')).toBe('wrapped-segwit');
    expect(getAddressTypeFromAddress('2Mww8dCYPUpKHofjgcXcBCEGmniw9CoaiD2')).toBe('wrapped-segwit');
    expect(getAddressTypeFromAddress('M8T1B2Z97gVdvmfkQcAtYbEepune1tzGua')).toBe('wrapped-segwit');
    expect(getAddressTypeFromAddress('1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu')).toBe('legacy');
  });

  it('derives the BIP49 bitcoin address', () => {
    const child = deriveChild(`m/49'/0'/0'/0/0`);
    const payment = createUtxoPayment('bitcoin', 'mainnet', child.publicKey, child.privateKey, 'wrapped-segwit');

    expect(payment.address).toBe('37VucYSaXLCAsxYyAPfbSi9eh4iEcbShgf');
    expect(payment.addressType).toBe('wrapped-segwit');
  });

  it('derives the BIP49 bitcoin testnet address', () => {
    const child = deriveChild(`m/49'/1'/0'/0/0`);
    const payment = createUtxoPayment('bitcoin', 'testnet', child.publicKey, child.privateKey, 'wrapped-segwit');

    expect(payment.address).toBe('2Mww8dCYPUpKHofjgcXcBCEGmniw9CoaiD2');
  });

  it('signs a P2SH-P2WPKH input with the redeem script', () => {
    const child = deriveChild(`m/49'/0'/0'/0/0`);
    const payment = createUtxoPayment('bitcoin', 'mainnet', child.publicKey, child.privateKey, 'wrapped-segwit');
    const lockingScripts = getUtxoLockingScripts(
      'bitcoin',
      'mainnet',
      payment.publicKey,
      'wrapped-segwit',
    );

    expect(lockingScripts.redeemScript).toBeDefined();

    const tx = new Transaction();
    tx.addInput({
      txid: '11'.repeat(32),
      index: 0,
      witnessUtxo: {
        amount: 100_000n,
        script: lockingScripts.script,
      },
      redeemScript: lockingScripts.redeemScript,
    });
    tx.addOutputAddress(payment.address, 99_000n);
    tx.sign(payment.privateKeyBytes);
    tx.finalize();

    expect(tx.hex.length).toBeGreaterThan(0);
  });
});

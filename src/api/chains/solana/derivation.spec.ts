import nacl from 'tweetnacl';

import { buildWalletFromPublicKey, getAddressFromPublicKey, SOLANA_DERIVATION_VERSION } from './derivation';

// Deterministic ed25519 keypair for a fixed seed.
// Used across tests to avoid network or mnemonic dependencies.
const TEST_SEED = new Uint8Array(32).fill(42);
const TEST_KEYPAIR = nacl.sign.keyPair.fromSeed(TEST_SEED);

// Solana addresses are base58-encoded 32-byte public keys.
const SOLANA_ADDRESS_REGEX = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;

describe('getAddressFromPublicKey', () => {
  it('returns a valid base58 Solana address', () => {
    const address = getAddressFromPublicKey(TEST_KEYPAIR.publicKey);
    expect(address).toMatch(SOLANA_ADDRESS_REGEX);
  });

  it('is deterministic for the same public key', () => {
    const a1 = getAddressFromPublicKey(TEST_KEYPAIR.publicKey);
    const a2 = getAddressFromPublicKey(TEST_KEYPAIR.publicKey);
    expect(a1).toBe(a2);
  });

  it('produces different addresses for different public keys', () => {
    const otherKeypair = nacl.sign.keyPair.fromSeed(new Uint8Array(32).fill(7));
    const a1 = getAddressFromPublicKey(TEST_KEYPAIR.publicKey);
    const a2 = getAddressFromPublicKey(otherKeypair.publicKey);
    expect(a1).not.toBe(a2);
  });
});

describe('buildWalletFromPublicKey', () => {
  const derivation = { path: `m/44'/501'/0'/0'`, index: 0, label: 'phantom' };

  it('produces a wallet entry with address, hex publicKey, index, and derivation', () => {
    const wallet = buildWalletFromPublicKey(TEST_KEYPAIR.publicKey, derivation);

    expect(wallet.address).toMatch(SOLANA_ADDRESS_REGEX);
    expect(wallet.publicKey).toBe(Buffer.from(TEST_KEYPAIR.publicKey).toString('hex'));
    expect(wallet.index).toBe(0);
    expect(wallet.derivation).toEqual(derivation);
  });

  it('uses the same address computation as getAddressFromPublicKey', () => {
    const wallet = buildWalletFromPublicKey(TEST_KEYPAIR.publicKey, derivation);
    expect(wallet.address).toBe(getAddressFromPublicKey(TEST_KEYPAIR.publicKey));
  });

  it('is deterministic for the same public key and derivation', () => {
    const w1 = buildWalletFromPublicKey(TEST_KEYPAIR.publicKey, derivation);
    const w2 = buildWalletFromPublicKey(TEST_KEYPAIR.publicKey, derivation);
    expect(w1).toEqual(w2);
  });

  it('preserves derivation meta including optional label', () => {
    const trustDerivation = { path: `m/44'/501'/7'`, index: 7, label: 'trust' };
    const wallet = buildWalletFromPublicKey(TEST_KEYPAIR.publicKey, trustDerivation);
    expect(wallet.derivation).toEqual(trustDerivation);
  });

  it('handles derivation without a label', () => {
    const noLabel = { path: `m/44'/501'`, index: 0 };
    const wallet = buildWalletFromPublicKey(TEST_KEYPAIR.publicKey, noLabel);
    expect(wallet.derivation).toEqual(noLabel);
    expect(wallet.derivation?.label).toBeUndefined();
  });

  it('stamps the current SOLANA_DERIVATION_VERSION so the detector treats wallet as up-to-date', () => {
    const wallet = buildWalletFromPublicKey(TEST_KEYPAIR.publicKey, derivation);
    expect(wallet.derivationVersion).toBe(SOLANA_DERIVATION_VERSION);
  });
});

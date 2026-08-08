import { WalletContractV5R1 } from '@ton/ton';

import { toBase64Address } from './util/tonCore';
import { WORKCHAIN } from './constants';
import {
  buildWallet, getTonWallet, pickBestWalletVersion, publicKeyToAddress,
} from './wallet';

const PUBLIC_KEY_HEX = '1a4e0b6f3d8c2957e4b1a0d6c3f89e5271b4a8d0e6c2f39571a4e0b6f3d8c2957';
const PUBLIC_KEY = Buffer.from(PUBLIC_KEY_HEX, 'hex');

const MAINNET_GLOBAL_ID = -239;
const TESTNET_GLOBAL_ID = -3;

describe('W5 subwallet ID', () => {
  it('derives the testnet address with the testnet network global id', () => {
    // The same computation an external library performs, which is the comparison TON docs describe
    const reference = WalletContractV5R1.create({
      publicKey: PUBLIC_KEY,
      workchain: WORKCHAIN,
      walletId: { networkGlobalId: TESTNET_GLOBAL_ID },
    });

    expect(publicKeyToAddress('testnet', PUBLIC_KEY, 'W5', true))
      .toEqual(toBase64Address(reference.address, false, 'testnet'));
  });

  it('gives different addresses for the two subwallet ids', () => {
    expect(publicKeyToAddress('testnet', PUBLIC_KEY, 'W5', true))
      .not.toEqual(publicKeyToAddress('testnet', PUBLIC_KEY, 'W5', false));
  });

  it('restores the testnet subwallet id from a stored testnet wallet', () => {
    const address = publicKeyToAddress('testnet', PUBLIC_KEY, 'W5', true);

    const wallet = getTonWallet({
      address, publicKey: PUBLIC_KEY_HEX, version: 'W5', index: 0,
    }) as WalletContractV5R1;

    expect(wallet.walletId.networkGlobalId).toBe(TESTNET_GLOBAL_ID);
  });

  it('restores the mainnet subwallet id for wallets created before the testnet id was supported', () => {
    const legacyAddress = publicKeyToAddress('testnet', PUBLIC_KEY, 'W5', false);

    const wallet = getTonWallet({
      address: legacyAddress, publicKey: PUBLIC_KEY_HEX, version: 'W5', index: 0,
    }) as WalletContractV5R1;

    // Such wallets hold real funds, so their signing must keep using the id their address was derived from
    expect(wallet.walletId.networkGlobalId).toBe(MAINNET_GLOBAL_ID);
    expect(toBase64Address(wallet.address, false, 'testnet')).toEqual(legacyAddress);
  });

  it('uses the testnet subwallet id when wallet discovery is skipped', async () => {
    // This branch never queries the network, so a freshly created wallet has to pick the id on its own
    const { wallet } = await pickBestWalletVersion('testnet', PUBLIC_KEY, true);

    expect((wallet as WalletContractV5R1).walletId.networkGlobalId).toBe(TESTNET_GLOBAL_ID);
  });

  it('leaves versions other than W5 network-independent', () => {
    const v4Address = buildWallet(PUBLIC_KEY, 'v4R2').address;

    expect(toBase64Address(v4Address, false, 'mainnet'))
      .not.toEqual(toBase64Address(v4Address, false, 'testnet'));
    expect(buildWallet(PUBLIC_KEY, 'v4R2', true).address.equals(v4Address)).toBe(true);
  });
});

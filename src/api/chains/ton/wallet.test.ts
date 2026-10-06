import type { Cell } from '@ton/core';
import { internal, SendMode } from '@ton/core';
import { WalletContractV5R1 } from '@ton/ton';

import type {
  TelegramWallet } from './contracts/TelegramWallet';

import { toBase64Address } from './util/tonCore';
import {
  getTelegramWalletTrampolineCode,
  TELEGRAM_WALLET_TRAMPOLINE_CODE_HASH,
} from './contracts/TelegramWallet';
import { WORKCHAIN } from './constants';
import {
  buildWallet, getTonWallet, pickBestWalletVersion, publicKeyToAddress,
} from './wallet';

const PUBLIC_KEY_HEX = '1a4e0b6f3d8c2957e4b1a0d6c3f89e5271b4a8d0e6c2f39571a4e0b6f3d8c2957';
const PUBLIC_KEY = Buffer.from(PUBLIC_KEY_HEX, 'hex');
const TELEGRAM_PUBLIC_KEY_HEX = '1a4e0b6f3d8c2957e4b1a0d6c3f89e5271b4a8d0e6c2f39571a4e0b6f3d8c295';
const TELEGRAM_PUBLIC_KEY = Buffer.from(TELEGRAM_PUBLIC_KEY_HEX, 'hex');

const MAINNET_GLOBAL_ID = -239;
const TESTNET_GLOBAL_ID = -3;
const TELEGRAM_TRAMPOLINE_CODE_HASH = '9149ae51c1e4689710cebf7830297b16acfbadb363a920a537893e7ffeeca768';
const TELEGRAM_MAINNET_SUBWALLET_ID = 0x7FFF7F11;
const TELEGRAM_TESTNET_SUBWALLET_ID = 0x7FFF7FFD;
const TELEGRAM_SEND_ONE_EXTERNAL_OP = 0x63896E75;
const TELEGRAM_SEND_BULK_EXTERNAL_OP = 0x73896E75;

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

describe('wallets with no known version', () => {
  it('refuses to build a contract instead of falling back to the default one', () => {
    // An address whose contract the app cannot name reaches storage without a version, and building it as the
    // default version would hand out the address, state init and version of a contract that is not deployed there.
    expect(() => getTonWallet({
      address: 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ',
      publicKey: PUBLIC_KEY_HEX,
      index: 0,
    })).toThrow('Wallet version is missing');
  });
});

describe('Telegram wallet', () => {
  function buildTelegramBulkTransfer(messageCount: number) {
    const wallet = buildWallet(TELEGRAM_PUBLIC_KEY, 'telegram', false) as TelegramWallet;

    return wallet.createTransfer({
      messages: Array.from({ length: messageCount }, (_, index) => internal({
        to: 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ',
        value: BigInt(index + 1),
      })),
      sendMode: SendMode.PAY_GAS_SEPARATELY + SendMode.IGNORE_ERRORS,
      seqno: 8,
      timeout: 123457,
      secretKey: Buffer.alloc(64),
    });
  }

  function readTelegramBulkChunkSizes(transfer: Cell) {
    const body = transfer.beginParse();
    body.loadBuffer(64);
    expect(body.loadUint(32)).toBe(TELEGRAM_SEND_BULK_EXTERNAL_OP);
    body.loadUint(32);
    body.loadUint(32);
    body.loadUint(32);
    const count = body.loadUint(8);

    let chunk: Cell | null = body.loadMaybeRef();
    const sizes: number[] = [];
    while (chunk) {
      const slice = chunk.beginParse();
      chunk = slice.loadMaybeRef();

      let size = 0;
      while (slice.remainingRefs > 0) {
        slice.loadUint(8);
        slice.loadRef();
        size++;
      }

      slice.endParse();
      sizes.push(size);
    }

    body.endParse();

    return { count, sizes };
  }

  it('pins upstream Telegram contract literals independently', () => {
    expect(TELEGRAM_WALLET_TRAMPOLINE_CODE_HASH).toBe(TELEGRAM_TRAMPOLINE_CODE_HASH);
    expect(getTelegramWalletTrampolineCode().hash().toString('hex')).toBe(TELEGRAM_TRAMPOLINE_CODE_HASH);

    const mainnetWallet = buildWallet(TELEGRAM_PUBLIC_KEY, 'telegram', false) as TelegramWallet;
    const testnetWallet = buildWallet(TELEGRAM_PUBLIC_KEY, 'telegram', true) as TelegramWallet;
    expect(mainnetWallet.subwalletId).toBe(TELEGRAM_MAINNET_SUBWALLET_ID);
    expect(testnetWallet.subwalletId).toBe(TELEGRAM_TESTNET_SUBWALLET_ID);

    const sendOne = mainnetWallet.createTransfer({
      messages: [internal({ to: 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ', value: 1n })],
      sendMode: SendMode.PAY_GAS_SEPARATELY + SendMode.IGNORE_ERRORS,
      seqno: 1,
      timeout: 123456,
      secretKey: Buffer.alloc(64),
    }).beginParse();
    sendOne.loadBuffer(64);
    expect(sendOne.loadUint(32)).toBe(TELEGRAM_SEND_ONE_EXTERNAL_OP);

    const sendBulk = buildTelegramBulkTransfer(2).beginParse();
    sendBulk.loadBuffer(64);
    expect(sendBulk.loadUint(32)).toBe(TELEGRAM_SEND_BULK_EXTERNAL_OP);
  });

  it('builds trampoline state init with Telegram storage layout', () => {
    const wallet = buildWallet(TELEGRAM_PUBLIC_KEY, 'telegram', false) as TelegramWallet;
    const data = wallet.init.data.beginParse();

    expect(data.loadUint(8)).toBe(0);
    expect(data.loadUint(32)).toBe(0);
    expect(data.loadUint(32)).toBe(TELEGRAM_MAINNET_SUBWALLET_ID);
    expect(data.loadBuffer(32).toString('hex')).toBe(TELEGRAM_PUBLIC_KEY_HEX);
    data.endParse();
  });

  it('uses the testnet Telegram subwallet id when requested', () => {
    const wallet = buildWallet(TELEGRAM_PUBLIC_KEY, 'telegram', true) as TelegramWallet;
    const data = wallet.init.data.beginParse();

    data.loadUint(8);
    data.loadUint(32);
    expect(data.loadUint(32)).toBe(TELEGRAM_TESTNET_SUBWALLET_ID);
  });

  it('restores a stored Telegram wallet contract from its address', () => {
    const address = publicKeyToAddress('mainnet', TELEGRAM_PUBLIC_KEY, 'telegram', false);
    const wallet = getTonWallet({
      address, publicKey: TELEGRAM_PUBLIC_KEY_HEX, version: 'telegram', index: 0,
    }) as TelegramWallet;

    expect(toBase64Address(wallet.address, false, 'mainnet')).toBe(address);
    expect(wallet.subwalletId).toBe(TELEGRAM_MAINNET_SUBWALLET_ID);
  });

  it('restores the testnet Telegram subwallet id from a stored testnet wallet', () => {
    const address = publicKeyToAddress('testnet', TELEGRAM_PUBLIC_KEY, 'telegram', true);
    const wallet = getTonWallet({
      address, publicKey: TELEGRAM_PUBLIC_KEY_HEX, version: 'telegram', index: 0,
    }) as TelegramWallet;

    expect(toBase64Address(wallet.address, false, 'testnet')).toBe(address);
    expect(wallet.subwalletId).toBe(TELEGRAM_TESTNET_SUBWALLET_ID);
  });

  it('builds an external send-one signed request as signature plus body', () => {
    const wallet = buildWallet(TELEGRAM_PUBLIC_KEY, 'telegram', false) as TelegramWallet;
    const transfer = wallet.createTransfer({
      messages: [internal({
        to: 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ',
        value: 1n,
      })],
      sendMode: SendMode.PAY_GAS_SEPARATELY + SendMode.IGNORE_ERRORS,
      seqno: 7,
      timeout: 123456,
      secretKey: Buffer.alloc(64),
    });
    const body = transfer.beginParse();

    expect(body.loadBuffer(64).length).toBe(64);
    expect(body.loadUint(32)).toBe(TELEGRAM_SEND_ONE_EXTERNAL_OP);
    expect(body.loadUint(32)).toBe(TELEGRAM_MAINNET_SUBWALLET_ID);
    expect(body.loadUint(32)).toBe(123456);
    expect(body.loadUint(32)).toBe(7);
    expect(body.loadUint(8)).toBe(SendMode.PAY_GAS_SEPARATELY + SendMode.IGNORE_ERRORS);
    expect(body.loadRef().beginParse().loadUint(1)).toBe(0);
    body.endParse();
  });

  it('builds an external bulk signed request with a Tolk message array', () => {
    const transfer = buildTelegramBulkTransfer(2);
    const body = transfer.beginParse();

    body.loadBuffer(64);
    expect(body.loadUint(32)).toBe(TELEGRAM_SEND_BULK_EXTERNAL_OP);
    body.loadUint(32);
    body.loadUint(32);
    body.loadUint(32);
    expect(body.loadUint(8)).toBe(2);

    const chunk = body.loadMaybeRef()!.beginParse();
    expect(chunk.loadMaybeRef()).toBeNull();
    expect(chunk.loadUint(8)).toBe(SendMode.PAY_GAS_SEPARATELY + SendMode.IGNORE_ERRORS);
    expect(chunk.loadRef().beginParse().loadUint(1)).toBe(0);
    expect(chunk.loadUint(8)).toBe(SendMode.PAY_GAS_SEPARATELY + SendMode.IGNORE_ERRORS);
    expect(chunk.loadRef().beginParse().loadUint(1)).toBe(0);
    chunk.endParse();
    body.endParse();
  });

  it.each([
    [4, [4]],
    [5, [1, 4]],
    [8, [1, 3, 4]],
  ])('chunks %s external bulk messages on Telegram boundaries', (messageCount, expectedSizes) => {
    const { count, sizes } = readTelegramBulkChunkSizes(buildTelegramBulkTransfer(messageCount));

    expect(count).toBe(messageCount);
    expect(sizes).toEqual(expectedSizes);
  });
});

import { Address, beginCell, Cell } from '@ton/core';

import type { EmulationResponse } from './toncenter/emulation';
import type { Transaction, TransactionMessage } from './toncenter/types';

import gwTrace from './testData/uranusBuyGWEmulateTrace.json';
import gwMaxTrace from './testData/uranusBuyGWMaxEmulateTrace.json';
import v2Trace from './testData/uranusBuyV2EmulateTrace.json';
import v2MaxTrace from './testData/uranusBuyV2MaxEmulateTrace.json';
import v3Trace from './testData/uranusBuyV3EmulateTrace.json';
import v3MaxTrace from './testData/uranusBuyV3MaxEmulateTrace.json';
import v31Trace from './testData/uranusBuyV31EmulateTrace.json';
import v31MaxTrace from './testData/uranusBuyV31MaxEmulateTrace.json';
import v31Poison10Trace from './testData/uranusBuyV31Poison10EmulateTrace.json';
import v32Trace from './testData/uranusBuyV32EmulateTrace.json';
import v32MaxTrace from './testData/uranusBuyV32MaxEmulateTrace.json';
import { validateUranusBuyEmulation } from './uranusBuyEmulation';

const SIGNER = 'EQDI24m89j6OUi_Qi0Es9DtdOEQgMgKvm6jhPb474bGk_F68';
const OWNER_WALLET = `0:${'a'.repeat(64)}`;
const ATTACKER_WALLET = `0:${'b'.repeat(64)}`;

const MASTERS = [
  ['V2', 'EQAO_1qemostkDtMfhp7XU0nOsAkQ_tLUO5YJeNMrj3dRAaH', 2_858_707_404_613_365n],
  ['V3', 'EQA6dGeKIcHUVQghKGmGe1fEfyfYaYyLC594PkYO5uIbEqT4', 1_389_189_021_048_520n],
  ['V3.1 LEEK', 'EQAmoQqDz6woBJ1dvwFl14PHdD6CE3eVMd58INFRKp3n9Ycw', 659_198_488_073_850n],
  ['V3.2', 'EQBvgReNRyFPokbDMi1ftAK5IvYAc8b0MV1qK280WAl4Qx1P', 833_316_966_349_671n],
] as const;

function raw(address: string) {
  return Address.parse(address).toRawString();
}

function makeMessage(source: string | undefined, destination: string, hash: string, body: string, opcode: string) {
  return {
    hash,
    source: source && raw(source),
    destination: raw(destination),
    bounced: false,
    opcode,
    message_content: { body, hash: 'body-hash' },
  } as TransactionMessage;
}

function makeTransaction(account: string, inMsg: TransactionMessage, outMsgs: TransactionMessage[]) {
  return {
    account: raw(account), in_msg: inMsg, out_msgs: outMsgs,
    description: { type: 'ord', aborted: false, compute_ph: { success: true }, action: { success: true } },
  } as Transaction;
}

function fixture(master: string, out: bigint, input = 1_000_000_000n) {
  const buyPayload = beginCell().storeUint(0x94826557, 32).storeUint(0, 64)
    .storeCoins(input).storeCoins(1n).storeAddress(Address.parse(SIGNER))
    .storeMaybeRef(undefined).storeMaybeRef(undefined).endCell();
  const mintPayload = beginCell().storeUint(0x178d4519, 32).storeUint(0, 64)
    .storeCoins(out).storeAddress(Address.parse(SIGNER)).storeAddress(Address.parse(SIGNER))
    .storeCoins(0).storeBit(0).endCell();
  const buyMessage = makeMessage(SIGNER, master, 'buy-message', buyPayload.toBoc().toString('base64'), '0x94826557');
  const mintMessage = makeMessage(
    master, OWNER_WALLET, 'mint-message', mintPayload.toBoc().toString('base64'), '0x178d4519',
  );
  const trace = {
    trace: {
      tx_hash: 'wallet-tx', in_msg_hash: 'external',
      children: [{ tx_hash: 'master-tx', in_msg_hash: 'buy-message',
        children: [{ tx_hash: 'jetton-wallet-tx', in_msg_hash: 'mint-message', children: [] }] }],
    },
    transactions: {
      'wallet-tx': makeTransaction(SIGNER, makeMessage(undefined, SIGNER, 'external', '', ''), [buyMessage]),
      'master-tx': makeTransaction(master, buyMessage, [mintMessage]),
      'jetton-wallet-tx': makeTransaction(OWNER_WALLET, mintMessage, []),
    },
  } as unknown as EmulationResponse;
  const options = {
    trace, signerAddress: SIGNER, masterAddress: master, ownerJettonWallet: OWNER_WALLET,
    buyPayload, minimalAmountOut: out * 99n / 100n, slippage: 1,
  };
  return options;
}

function realFixture(rawTrace: unknown) {
  const trace = rawTrace as EmulationResponse;
  const masterTx = Object.values(trace.transactions).find((tx) => tx.in_msg.opcode === '0x94826557')!;
  const mint = masterTx.out_msgs.find((message) => message.opcode === '0x178d4519')!;
  const buyPayload = Cell.fromBase64(masterTx.in_msg.message_content.body);
  const buy = buyPayload.beginParse();
  buy.loadUint(32);
  buy.loadUintBig(64);
  buy.loadCoins();
  const minimalAmountOut = buy.loadCoins();
  return {
    trace,
    signerAddress: masterTx.in_msg.source!,
    masterAddress: masterTx.account,
    ownerJettonWallet: mint.destination!,
    buyPayload,
    minimalAmountOut,
    slippage: 1,
  };
}

describe('Uranus buy trace price bound', () => {
  it.each([
    ['V2', v2Trace, MASTERS[0][2]],
    ['V3', v3Trace, MASTERS[1][2]],
    ['V3.1', v31Trace, MASTERS[2][2]],
    ['V3.2', v32Trace, MASTERS[3][2]],
    ['V2 MAX', v2MaxTrace, 11_831_682_925_528_945n],
    ['V3 MAX', v3MaxTrace, 5_775_500_032_314_291n],
    ['V3.1 MAX', v31MaxTrace, 2_745_497_386_608_721n],
    ['V3.2 MAX', v32MaxTrace, 3_469_650_464_660_115n],
    ['V3.1 GW', gwTrace, 991_267_999_647_701n],
    ['V3.1 GW MAX', gwMaxTrace, 4_126_615_728_690_452n],
  ])('accepts a real Toncenter %s buy trace', (_name, trace, amountOut) => {
    expect(validateUranusBuyEmulation(realFixture(trace))).toBe(amountOut);
  });

  it('rejects a real Toncenter trace with a poisoned signed minimum', () => {
    expect(() => validateUranusBuyEmulation(realFixture(v31Poison10Trace)))
      .toThrow('below independent price bound');
  });

  it.each(MASTERS)('accepts a successful %s mint to the signer wallet', (_name, master, out) => {
    expect(validateUranusBuyEmulation(fixture(master, out))).toBe(out);
  });

  it('accepts a MAX buy and a partial fill with an unrelated migration bounce', () => {
    const options = fixture(MASTERS[2][1], 688_990_900_643_326_141n, 1_600_000_000_000n);
    const masterTx = options.trace.transactions['master-tx'];
    const migration = makeMessage(options.masterAddress, SIGNER, 'migration-message', '', '0xde8402ce');
    masterTx.out_msgs.push(migration);
    options.trace.trace.children[0].children.push({
      tx_hash: 'migration-tx', in_msg_hash: migration.hash, children: [],
    });
    options.trace.transactions['migration-tx'] = makeTransaction(SIGNER, migration, []);
    options.trace.transactions['migration-tx'].description.aborted = true;
    expect(validateUranusBuyEmulation(options)).toBe(688_990_900_643_326_141n);
  });

  it('rejects a jointly poisoned backend quote and signed minOut', () => {
    const options = fixture(MASTERS[2][1], MASTERS[2][2]);
    options.minimalAmountOut = MASTERS[2][2] / 10n;
    expect(() => validateUranusBuyEmulation(options)).toThrow('below independent price bound');
  });

  it('rejects a minimum just below the floor after slippage and price drift', () => {
    const options = fixture(MASTERS[2][1], MASTERS[2][2]);
    options.minimalAmountOut = MASTERS[2][2] * 98n / 100n - 1n;
    expect(() => validateUranusBuyEmulation(options)).toThrow('below independent price bound');
  });

  it('rejects a mint for another owner', () => {
    const options = fixture(MASTERS[2][1], MASTERS[2][2]);
    options.trace.transactions['master-tx'].out_msgs[0].destination = raw(ATTACKER_WALLET);
    expect(() => validateUranusBuyEmulation(options)).toThrow('mint does not target');
  });

  it('rejects aborted, bounced, and incomplete master traces', () => {
    const aborted = fixture(MASTERS[2][1], MASTERS[2][2]);
    aborted.trace.transactions['master-tx'].description.aborted = true;
    expect(() => validateUranusBuyEmulation(aborted)).toThrow('master transaction failed');

    const bounced = fixture(MASTERS[2][1], MASTERS[2][2]);
    bounced.trace.transactions['master-tx'].in_msg.bounced = true;
    expect(() => validateUranusBuyEmulation(bounced)).toThrow('master transaction failed');

    const missing = fixture(MASTERS[2][1], MASTERS[2][2]);
    delete missing.trace.transactions['master-tx'];
    expect(() => validateUranusBuyEmulation(missing)).toThrow('trace transaction is missing');
  });

  it('rejects an emulation that does not execute the exact signed buy', () => {
    const options = fixture(MASTERS[2][1], MASTERS[2][2]);
    options.trace.transactions['master-tx'].in_msg.message_content.body = beginCell()
      .endCell().toBoc().toString('base64');
    expect(() => validateUranusBuyEmulation(options)).toThrow('master input differs');
  });
});

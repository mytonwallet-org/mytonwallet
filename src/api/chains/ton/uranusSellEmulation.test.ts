import { Address, beginCell, Cell } from '@ton/core';

import type { EmulationResponse } from './toncenter/emulation';
import type { Transaction, TransactionMessage } from './toncenter/types';

import liveTraces from './testData/uranusSellLiveTraces.json';
import { validateUranusSellEmulation } from './uranusSellEmulation';

const SIGNER = 'EQDI24m89j6OUi_Qi0Es9DtdOEQgMgKvm6jhPb474bGk_F68';
const ATTACKER = 'EQBvgReNRyFPokbDMi1ftAK5IvYAc8b0MV1qK280WAl4Qx1P';
const MASTER = 'EQAmoQqDz6woBJ1dvwFl14PHdD6CE3eVMd58INFRKp3n9Ycw';
const WALLET = 'EQDb1-FIBdd-NQYPhEcb72lNBm-r6jT9IgT1rNKmZEmuAjY5';
const AMOUNT = 1_000_000_000n;
const OUTPUT = 7_430_651n;

function raw(address: string) {
  return Address.parse(address).toRawString();
}

function message(
  source: string | undefined, destination: string | undefined,
  hash: string, opcode: string, body: string, value = '0',
) {
  return {
    hash, source: source && raw(source), destination: destination && raw(destination),
    opcode, value, bounced: false, message_content: { hash: 'body-hash', body },
  } as TransactionMessage;
}

function transaction(account: string, inMsg: TransactionMessage, outMsgs: TransactionMessage[]) {
  return {
    account: raw(account), in_msg: inMsg, out_msgs: outMsgs,
    description: { type: 'ord', aborted: false, compute_ph: { success: true }, action: { success: true } },
  } as Transaction;
}

function fixture() {
  const sellPayload = beginCell().storeUint(0xb7459e2c, 32).storeUint(12n, 64)
    .storeCoins(AMOUNT).storeCoins(7_356_344n).storeAddress(Address.parse(SIGNER))
    .storeMaybeRef(undefined).storeMaybeRef(undefined).endCell();
  const masterPayload = beginCell().storeUint(0x646ad424, 32).storeUint(12n, 64)
    .storeCoins(AMOUNT).storeCoins(7_356_344n).storeAddress(Address.parse(SIGNER))
    .storeAddress(Address.parse(SIGNER)).storeMaybeRef(undefined).storeMaybeRef(undefined).endCell();
  const event = beginCell().storeUint(0x3ab0fccc, 32).storeAddress(Address.parse(SIGNER))
    .storeCoins(AMOUNT).storeCoins(OUTPUT).endCell();
  const signed = message(SIGNER, WALLET, 'signed-sell', '0xb7459e2c', sellPayload.toBoc().toString('base64'));
  const toMaster = message(WALLET, MASTER, 'to-master', '0x646ad424', masterPayload.toBoc().toString('base64'));
  const payout = message(MASTER, SIGNER, 'payout', '0x66c8ad72', '', OUTPUT.toString());
  const trace = {
    trace: { tx_hash: 'signer-tx', in_msg_hash: 'external', children: [
      { tx_hash: 'wallet-tx', in_msg_hash: 'signed-sell', children: [
        { tx_hash: 'master-tx', in_msg_hash: 'to-master', children: [
          { tx_hash: 'payout-tx', in_msg_hash: 'payout', children: [] },
        ] },
      ] },
    ] },
    transactions: {
      'signer-tx': transaction(SIGNER, message(undefined, SIGNER, 'external', '', ''), [signed]),
      'wallet-tx': transaction(WALLET, signed, [toMaster]),
      'master-tx': transaction(MASTER, toMaster, [
        message(MASTER, undefined, 'sell-event', '0x3ab0fccc', event.toBoc().toString('base64')),
        payout,
      ]),
      'payout-tx': transaction(SIGNER, payout, []),
    },
  } as unknown as EmulationResponse;
  return {
    trace, signerAddress: SIGNER, masterAddress: MASTER, ownerJettonWallet: WALLET,
    sellPayload, minimalAmountOut: 7_356_344n, slippage: 1,
  };
}

describe('Uranus sell exact-transfer emulation', () => {
  it.each(['V2', 'V3', 'V31', 'V32'] as const)('accepts the actual successful %s mainnet sell trace', (version) => {
    const record = liveTraces[version];
    const trace = record as unknown as EmulationResponse;
    const walletTx = Object.values(trace.transactions).find((tx) => tx.in_msg.opcode === '0xb7459e2c')!;
    const sellPayload = Cell.fromBase64(walletTx.in_msg.message_content.body);
    const sell = sellPayload.beginParse();
    sell.loadUint(32);
    sell.loadUintBig(64);
    sell.loadCoins();
    const minimalAmountOut = sell.loadCoins();
    const masterTx = trace.transactions[record.masterTransaction];
    expect(validateUranusSellEmulation({
      trace, signerAddress: walletTx.in_msg.source!, masterAddress: masterTx.account,
      ownerJettonWallet: walletTx.account, sellPayload, minimalAmountOut, slippage: 5,
    })).toBeGreaterThan(0n);
  });

  it('accepts a successful sell with the on-chain payout to the signer', () => {
    expect(validateUranusSellEmulation(fixture())).toBe(OUTPUT);
  });

  it('rejects a fully poisoned signed minimum against the independent output', () => {
    const options = fixture();
    options.minimalAmountOut = 1n;
    const sell = beginCell().storeUint(0xb7459e2c, 32).storeUint(12n, 64)
      .storeCoins(AMOUNT).storeCoins(1n).storeAddress(Address.parse(SIGNER))
      .storeMaybeRef(undefined).storeMaybeRef(undefined).endCell();
    options.sellPayload = sell;
    options.trace.transactions['wallet-tx'].in_msg.message_content.body = sell.toBoc().toString('base64');
    options.trace.transactions['master-tx'].in_msg.message_content.body = beginCell()
      .storeUint(0x646ad424, 32).storeUint(12n, 64)
      .storeCoins(AMOUNT).storeCoins(1n).storeAddress(Address.parse(SIGNER))
      .storeAddress(Address.parse(SIGNER)).storeMaybeRef(undefined).storeMaybeRef(undefined)
      .endCell().toBoc().toString('base64');
    expect(() => validateUranusSellEmulation(options)).toThrow('independent price bound');
  });

  it('rejects payout redirection, bounce, failed master, and altered signed payload', () => {
    const redirected = fixture();
    redirected.trace.transactions['master-tx'].out_msgs[1].destination = raw(ATTACKER);
    expect(() => validateUranusSellEmulation(redirected)).toThrow('payout');

    const bounced = fixture();
    bounced.trace.transactions['payout-tx'].in_msg.bounced = true;
    expect(() => validateUranusSellEmulation(bounced)).toThrow('payout does not deliver');

    const failed = fixture();
    failed.trace.transactions['master-tx'].description.aborted = true;
    expect(() => validateUranusSellEmulation(failed)).toThrow('master transaction failed');

    const altered = fixture();
    altered.trace.transactions['wallet-tx'].in_msg.message_content.body = beginCell().storeBit(1)
      .endCell().toBoc().toString('base64');
    expect(() => validateUranusSellEmulation(altered)).toThrow('differs from the signed sell');
  });

  it('rejects a wallet-to-master sell that substitutes the token owner', () => {
    const changedOwner = fixture();
    changedOwner.trace.transactions['master-tx'].in_msg.message_content.body = beginCell()
      .storeUint(0x646ad424, 32).storeUint(12n, 64)
      .storeCoins(AMOUNT).storeCoins(7_356_344n).storeAddress(Address.parse(ATTACKER))
      .storeAddress(Address.parse(SIGNER)).storeMaybeRef(undefined).storeMaybeRef(undefined)
      .endCell().toBoc().toString('base64');
    expect(() => validateUranusSellEmulation(changedOwner)).toThrow('master input');
  });
});

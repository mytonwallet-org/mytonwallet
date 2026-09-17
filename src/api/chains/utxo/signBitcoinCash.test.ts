import { secp256k1 } from '@noble/curves/secp256k1';
import { p2pkh, Transaction } from '@scure/btc-signer';

import { hexToBytes } from '../../common/utils';
import { BITCOIN_CASH_SIGHASH, signBitcoinCashTransaction } from './signBitcoinCash';

const PRIVATE_KEY = hexToBytes('0000000000000000000000000000000000000000000000000000000000000001');
const PUBLIC_KEY = secp256k1.getPublicKey(PRIVATE_KEY, true);
const PAYMENT = p2pkh(PUBLIC_KEY);
const PREV_TXID = '11'.repeat(32);
const INPUT_AMOUNT = 100_000n;
const OUTPUT_AMOUNT = 99_000n;

function buildUnsignedTransfer() {
  const tx = new Transaction({ allowLegacyWitnessUtxo: true });

  tx.addInput({
    txid: PREV_TXID,
    index: 0,
    witnessUtxo: {
      amount: INPUT_AMOUNT,
      script: PAYMENT.script,
    },
  });
  tx.addOutputAddress(PAYMENT.address!, OUTPUT_AMOUNT);

  return tx;
}

describe('signBitcoinCashTransaction', () => {
  it('appends SIGHASH_FORKID and verifies against the BIP143 preimage', () => {
    const tx = buildUnsignedTransfer();

    signBitcoinCashTransaction(tx, PRIVATE_KEY);

    const hash = tx.preimageWitnessV0(0, PAYMENT.script, BITCOIN_CASH_SIGHASH, INPUT_AMOUNT);
    const signature = tx.getInput(0).partialSig![0][1];

    expect(signature[signature.length - 1]).toBe(BITCOIN_CASH_SIGHASH);
    expect(BITCOIN_CASH_SIGHASH).toBe(0x41);
    expect(secp256k1.verify(signature.subarray(0, -1), hash, PUBLIC_KEY, { format: 'der' })).toBe(true);
  });

  it('does not produce a Bitcoin-legacy signature that BCH nodes would reject', () => {
    const bchTx = buildUnsignedTransfer();
    const btcTx = buildUnsignedTransfer();

    signBitcoinCashTransaction(bchTx, PRIVATE_KEY);
    btcTx.sign(PRIVATE_KEY);

    const bchSignature = bchTx.getInput(0).partialSig![0][1];
    const btcSignature = btcTx.getInput(0).partialSig![0][1];

    expect(bchSignature[bchSignature.length - 1]).toBe(0x41);
    expect(btcSignature[btcSignature.length - 1]).toBe(0x01);
    expect(Buffer.from(bchSignature.subarray(0, -1)).equals(Buffer.from(btcSignature.subarray(0, -1))))
      .toBe(false);
  });

  it('finalizes a spendable P2PKH input', () => {
    const tx = buildUnsignedTransfer();

    signBitcoinCashTransaction(tx, PRIVATE_KEY);
    tx.finalize();

    expect(tx.isFinal).toBe(true);
    expect(tx.hex.length).toBeGreaterThan(0);
  });
});

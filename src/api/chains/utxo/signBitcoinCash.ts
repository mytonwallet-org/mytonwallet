import { secp256k1 } from '@noble/curves/secp256k1';
import type { Transaction } from '@scure/btc-signer';
import { getInputType } from '@scure/btc-signer';

const SIGHASH_ALL = 0x01;
const SIGHASH_FORKID = 0x40;

/** BCH UAHF fork id is 0, so nHashType is `SIGHASH_ALL | SIGHASH_FORKID`. */
export const BITCOIN_CASH_SIGHASH = SIGHASH_ALL | SIGHASH_FORKID;

function concatSignature(signature: Uint8Array, sighash: number) {
  const result = new Uint8Array(signature.length + 1);
  result.set(signature);
  result[signature.length] = sighash;

  return result;
}

/**
 * Signs a Bitcoin Cash transaction with BIP143 preimages and SIGHASH_FORKID.
 * `@scure/btc-signer` `Transaction.sign` uses Bitcoin legacy sighash and is rejected by BCH nodes.
 */
export function signBitcoinCashTransaction(tx: Transaction, privateKey: Uint8Array) {
  const publicKey = secp256k1.getPublicKey(privateKey, true);

  for (let i = 0; i < tx.inputsLength; i++) {
    const input = tx.getInput(i);
    const amount = input.witnessUtxo?.amount;

    if (amount === undefined) {
      throw new Error('Bitcoin Cash input is missing amount');
    }

    const { lastScript } = getInputType(input, true);
    const hash = tx.preimageWitnessV0(i, lastScript, BITCOIN_CASH_SIGHASH, amount);
    const signature = secp256k1.sign(hash, privateKey).toDERRawBytes();

    tx.updateInput(i, {
      partialSig: [[publicKey, concatSignature(signature, BITCOIN_CASH_SIGHASH)]],
    }, true);
  }
}

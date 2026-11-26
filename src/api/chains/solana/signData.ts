import type { ReadonlyUint8Array } from '@solana/kit';
import {
  getBase58Encoder,
  getCompiledTransactionMessageDecoder,
  getCompiledTransactionMessageEncoder,
  isSolanaError,
  SOLANA_ERROR__TRANSACTION__VERSION_NUMBER_NOT_SUPPORTED,
  TRANSACTION_SIZE_LIMIT,
} from '@solana/kit';

import type { UnifiedSignDataPayload } from '../../dappProtocols';

const TRANSACTION_MESSAGE_REFUSAL = 'A transaction cannot be signed as a message';
const OFFCHAIN_MESSAGE_MARKER = 0xff;
const V1_VERSION_MARKER = 0x81;
// A v1 transaction message holds 42 bytes of fixed fields and the address of the fee payer
const MIN_V1_MESSAGE_SIZE = 74;
// A transaction message of any version holds a fee payer and a lifetime token, 32 bytes each
const MIN_TRANSACTION_MESSAGE_SIZE = 64;
// The size limit of the largest transaction version, counted with the signatures
const MAX_TRANSACTION_SIZE = 4096;
const SIGNATURE_SIZE = 64;
const SIGNATURE_COUNT_SIZE = 1;
// Base58 takes under two characters per byte, and decoding it takes quadratic time
const MAX_TRANSACTION_BASE58_LENGTH = MAX_TRANSACTION_SIZE * 2;

export function getSignDataRefusal(payload: UnifiedSignDataPayload): string | undefined {
  return payload.type === 'binary' && isTransactionMessage(payload.bytes) ? TRANSACTION_MESSAGE_REFUSAL : undefined;
}

// A transaction signature is the same ed25519 signature over these bytes, so signing them as a message
// would authorize the transaction
function isTransactionMessage(base58Bytes: string) {
  if (base58Bytes.length > MAX_TRANSACTION_BASE58_LENGTH) return false;

  let bytes: ReadonlyUint8Array | undefined;

  try {
    bytes = getBase58Encoder().encode(base58Bytes);
    const message = getCompiledTransactionMessageDecoder().decode(bytes);
    const { numSignerAccounts, numReadonlySignerAccounts, numReadonlyNonSignerAccounts } = message.header;
    const transactionSize = SIGNATURE_COUNT_SIZE + SIGNATURE_SIZE * numSignerAccounts + bytes.length;

    // The network accepts a message with a writable fee payer and a header that fits its accounts,
    // in one encoding only, while the decoder also reads bytes that are not in it
    return numReadonlySignerAccounts < numSignerAccounts
      && numSignerAccounts + numReadonlyNonSignerAccounts <= message.staticAccounts.length
      && transactionSize <= TRANSACTION_SIZE_LIMIT
      && areBytesEqual(getCompiledTransactionMessageEncoder().encode(message), bytes);
  } catch (err) {
    // The marker of a version the decoder cannot read also starts text outside ASCII and off-chain messages
    return isSolanaError(err, SOLANA_ERROR__TRANSACTION__VERSION_NUMBER_NOT_SUPPORTED)
      && bytes!.length > MIN_TRANSACTION_MESSAGE_SIZE
      && (bytes![0] !== V1_VERSION_MARKER || bytes!.length >= MIN_V1_MESSAGE_SIZE)
      && bytes!.length + SIGNATURE_SIZE <= MAX_TRANSACTION_SIZE
      && bytes![0] !== OFFCHAIN_MESSAGE_MARKER
      && !isUtf8(bytes!);
  }
}

function areBytesEqual(a: ReadonlyUint8Array, b: ReadonlyUint8Array) {
  return a.length === b.length && a.every((byte, index) => byte === b[index]);
}

function isUtf8(bytes: ReadonlyUint8Array) {
  try {
    new TextDecoder('utf-8', { fatal: true }).decode(bytes as Uint8Array);

    return true;
  } catch {
    return false;
  }
}

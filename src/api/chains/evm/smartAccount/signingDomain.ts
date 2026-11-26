import { getAddress, getBytes, toUtf8Bytes } from 'ethers';

import type { UnifiedSignDataPayload } from '../../../dappProtocols';

const USER_OPERATION_HASH_LENGTH = 32;
const HEX_USER_OPERATION_HASH_LENGTH = 2 + USER_OPERATION_HASH_LENGTH * 2;

/** The bytes `personal_sign` and `eth_sign` cover: hex is decoded, any other string is taken as UTF-8. */
export function getPersonalSignBytes(message: string): Uint8Array {
  return message.startsWith('0x') ? getBytes(message) : toUtf8Bytes(message);
}

function isAsciiHexDigit(byte: number) {
  return (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x46) || (byte >= 0x61 && byte <= 0x66);
}

/**
 * EIP-191 over 32 bytes is how the account's EIP-7702 delegate expects a user operation hash to be signed.
 * 32 hex digits written as text stay signable: no hash can be searched for among so few byte values.
 */
export function canBeUserOperationHash(message: string): boolean {
  // A longer message cannot decode to 32 bytes, so a dApp's large payload is not decoded for this check
  if (message.length > (message.startsWith('0x') ? HEX_USER_OPERATION_HASH_LENGTH : USER_OPERATION_HASH_LENGTH)) {
    return false;
  }

  try {
    const bytes = getPersonalSignBytes(message);

    return bytes.length === USER_OPERATION_HASH_LENGTH && !bytes.every(isAsciiHexDigit);
  } catch (err) {
    return false;
  }
}

function tryGetAddress(value: string): string | undefined {
  try {
    return getAddress(value);
  } catch (err) {
    return undefined;
  }
}

// Spellings of one address must compare equal, and a wrong checksum must not hide a match
function parseAddress(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;

  return tryGetAddress(value) ?? tryGetAddress(value.toLowerCase());
}

/**
 * The delegate reads typed data of the account's own domain as a deferred action or an ERC-1271 approval.
 * A verifying contract that is not an address cannot be compared, so it counts as the account's own.
 */
export function isOwnTypedDataDomain(domain: Record<string, unknown> | undefined, signerAddress: string): boolean {
  const verifyingContract = domain?.verifyingContract;

  // eslint-disable-next-line no-null/no-null -- ethers omits nullish domain values
  if (verifyingContract === undefined || verifyingContract === null) return false;

  const address = parseAddress(verifyingContract);

  return address === undefined || address === parseAddress(signerAddress);
}

/** Whether a signature over `payload` is also an authorization of the signer's own EIP-7702 smart account. */
export function isSmartAccountAuthorization(payload: UnifiedSignDataPayload, signerAddress: string): boolean {
  if (payload.type === 'binary') {
    return canBeUserOperationHash(payload.bytes);
  }

  if (payload.type === 'eip712') {
    return isOwnTypedDataDomain(payload.domain, signerAddress);
  }

  return false;
}

const MAX_BYTES_IN_FIELD = 31;

/**
 * Pad string to specified length with zero bytes
 * @param str The string to pad
 * @param padLen The target length in bytes
 * @returns Array of byte values
 */
export function padString(str: string, padLen: number): number[] {
  const bytes = Array.from(str, (x) => x.charCodeAt(0));

  if (bytes.length > padLen) {
    throw new Error(`String length ${bytes.length} exceeds padding length ${padLen}`);
  }

  while (bytes.length < padLen) {
    bytes.push(0);
  }

  return bytes;
}

/**
 * Convert bytes to field elements by packing `MAX_BYTES_IN_FIELD` bytes per field
 * @param bytes Array of byte values
 * @returns Array of field elements as bigint
 */
export function bytesToFields(bytes: number[]): bigint[] {
  const fields: bigint[] = [];

  for (let i = 0; i < bytes.length; i += MAX_BYTES_IN_FIELD) {
    let fieldValue = 0n;
    const chunkSize = Math.min(MAX_BYTES_IN_FIELD, bytes.length - i);

    // Pack bytes little-endian style
    for (let j = 0; j < chunkSize; j++) {
      fieldValue += BigInt(bytes[i + j]) << BigInt(j * 8);
    }

    fields.push(fieldValue);
  }

  return fields;
}

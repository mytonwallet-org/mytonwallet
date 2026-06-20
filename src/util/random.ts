export function random(min: number, max: number) {
  return Math.floor(Math.random() * (max - min + 1) + min);
}

export function sample<T>(arr: T[]) {
  return arr[random(0, arr.length - 1)];
}

export function randomBytes(size: number) {
  return self.crypto.getRandomValues(new Uint8Array(size));
}

export function randomBase64(byteSize: number) {
  return Buffer.from(randomBytes(byteSize)).toString('base64');
}

// UUIDv7 layout: 48-bit big-endian Unix-ms timestamp, then version/variant bits, then random
export function generateUuidV7() {
  const bytes = randomBytes(16);
  const timestamp = Date.now();

  bytes[0] = Math.floor(timestamp / 0x10000000000) & 0xFF;
  bytes[1] = Math.floor(timestamp / 0x100000000) & 0xFF;
  bytes[2] = Math.floor(timestamp / 0x1000000) & 0xFF;
  bytes[3] = Math.floor(timestamp / 0x10000) & 0xFF;
  bytes[4] = Math.floor(timestamp / 0x100) & 0xFF;
  bytes[5] = timestamp & 0xFF;
  bytes[6] = (bytes[6] & 0x0F) | 0x70; // Version 7
  bytes[8] = (bytes[8] & 0x3F) | 0x80; // Variant

  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

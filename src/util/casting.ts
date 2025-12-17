export function bigIntFromHex(h: string) {
  return BigInt(`0x${h}`);
}

export function bufferFromHex(h: string) {
  return Buffer.from(h.padStart(h.length + (h.length % 2), '0'), 'hex');
}

export function hexFromBigInt(bi: bigint) {
  return bi.toString(16);
}

export function bufferFromBigInt(bi: bigint) {
  return bufferFromHex(hexFromBigInt(bi));
}

export function hexFromBuffer(b: Buffer) {
  return b.toString('hex');
}

export function bigIntFromBuffer(b: Buffer) {
  return bigIntFromHex(hexFromBuffer(b));
}

export function base64FromBuffer(b: Buffer) {
  return b.toString('base64');
}

export function asciiFromBuffer(b: Buffer) {
  return b.toString('ascii');
}

export function base64FromHex(h: string) {
  return base64FromBuffer(bufferFromHex(h));
}

export function base64FromBigInt(bi: bigint) {
  return base64FromBuffer(bufferFromBigInt(bi));
}

export function asciiFromBigInt(bi: bigint) {
  const hex = hexFromBigInt(bi);
  const paddedHex = hex.padStart((hex.length + 1) & ~1, '0');

  return asciiFromBuffer(bufferFromHex(paddedHex));
}

export function bufferFromBase64(b: string) {
  return Buffer.from(b, 'base64');
}

export function bigIntFromBase64(b: string) {
  return bigIntFromBuffer(bufferFromBase64(b));
}

export function bigIntFromBase64Url(b: string) {
  return bigIntFromBuffer(bufferFromBase64Url(b));
}

export function asciiFromHex(h: string) {
  return asciiFromBuffer(bufferFromHex(h));
}

export function hexFromArrayBuffer(ab: ArrayBuffer) {
  return hexFromBuffer(Buffer.from(ab));
}

export function hexFromByteArray(ba: ArrayLike<number>) {
  return hexFromBuffer(Buffer.from(ba));
}

export function byteArrayFromAscii(a: string) {
  return Buffer.from(a).toJSON().data;
}

export function bigIntFromAscii(a: string) {
  return bigIntFromBuffer(Buffer.from(a));
}

export function base64FromBase64Url(base64Url: string) {
  return base64Url
    .replace(/-/g, '+')
    .replace(/_/g, '/')
    .padEnd(base64Url.length + (4 - base64Url.length % 4) % 4, '=');
}

export function arrayBufferFromBase64(base64: string) {
  return bufferFromBase64(base64).buffer;
}

export function stringFromBase64(base64: string) {
  return bufferFromBase64(base64).toString('utf8');
}

export function asciiFromBase64(base64: string) {
  return bufferFromBase64(base64).toString('ascii');
}

export function bufferFromBase64Url(base64Url: string) {
  return bufferFromBase64(base64FromBase64Url(base64Url));
}

export function stringFromBase64Url(base64Url: string) {
  return stringFromBase64(base64FromBase64Url(base64Url));
}

export function asciiFromBase64Url(base64Url: string) {
  return asciiFromBase64(base64FromBase64Url(base64Url));
}

export function hexFromBase64(base64: string) {
  return hexFromBuffer(bufferFromBase64(base64));
}

export function hexFromBase64Url(base64Url: string) {
  return hexFromBase64(base64FromBase64Url(base64Url));
}

export function base64UrlFromBuffer(b: Buffer) {
  return b.toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

export function base64UrlFromBigInt(bi: bigint) {
  return base64UrlFromBuffer(bufferFromBigInt(bi));
}

export function bigIntLeFromBigInt(bi: bigint) {
  return bigIntFromBuffer(bufferFromBigInt(bi).reverse());
}

import { transformBytesByStream } from './stream';

export async function ungzip(input: BufferSource): Promise<Uint8Array> {
  const decompressionStream = tryCreateDecompressionStream('gzip');
  if (decompressionStream) {
    return transformBytesByStream(input, decompressionStream);
  }

  // Fflate is a polyfill, so we load it only if necessary.
  // Note: it's important to import `gunzipSync` exactly this way, otherwise the tree-shaking won't work.
  const { gunzipSync } = await import('fflate');
  return gunzipSync(bufferSourceToBytes(input));
}

function tryCreateDecompressionStream(format: CompressionFormat) {
  try {
    // If the format or `DecompressionStream` is not supported by the browser, this expression throws
    return new DecompressionStream(format);
  } catch {
    return undefined;
  }
}

function bufferSourceToBytes(source: BufferSource): Uint8Array {
  if (source instanceof ArrayBuffer) {
    return new Uint8Array(source);
  }
  return new Uint8Array(source.buffer, source.byteOffset, source.byteLength);
}

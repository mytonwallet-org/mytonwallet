/**
 * A full stream that failed before yielding a single NFT proves nothing about the wallet's
 * collectibles; emitting the empty final update would render a false "no collectibles"
 * state on cold start. Stay silent - the UI keeps its prior state and the next round retries.
 */
export function shouldEmitNftFullLoadFinal(didFail: boolean, streamedCount: number): boolean {
  return !didFail || streamedCount > 0;
}

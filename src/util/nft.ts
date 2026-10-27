/** EVM NFT keys are case-insensitive; other chains' addresses must retain their casing. */
export function normalizeNftAddress(address: string): string {
  return address.replace(/^0x[\da-f]{40}(?=\/)/i, (contract) => contract.toLowerCase());
}

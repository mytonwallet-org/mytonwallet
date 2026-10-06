const NFT_NUMBER_REGEX = /^(.*\S)\s*([#№][\d\\/]+)$/;

/** Splits a trailing item number off an NFT name, so `Durov's Cap #777` gives `Durov's Cap` and `#777` */
export function splitNftNumber(fullName: string) {
  const name = fullName.trim();
  const match = NFT_NUMBER_REGEX.exec(name);

  return match ? { name: match[1], nftNumber: match[2] } : { name };
}

import type { ApiNetwork, EVMChain } from '../../types';

import { getEvmChainId } from './constants';

const DECIMAL_CHAIN_ID_REGEX = /^\d+$/;
const HEX_CHAIN_ID_REGEX = /^0x[0-9a-f]+$/i;

function parseChainId(value: unknown): bigint | undefined {
  if (typeof value === 'bigint') {
    return value >= 0n ? value : undefined;
  }

  if (typeof value === 'number') {
    return Number.isSafeInteger(value) && value >= 0 ? BigInt(value) : undefined;
  }

  if (typeof value === 'string' && (DECIMAL_CHAIN_ID_REGEX.test(value) || HEX_CHAIN_ID_REGEX.test(value))) {
    return BigInt(value);
  }

  return undefined;
}

/**
 * Whether EIP-712 typed data may be signed for `chain`: its `domain.chainId` is either absent (EIP-712 makes it
 * optional, and ethers leaves a `null` field out of the domain) or equal to the chain's id on `network`.
 * An unparseable `chainId` or a chain without a known id does not match.
 */
export function isTypedDataDomainOnChain(
  domain: Record<string, unknown> | undefined,
  network: ApiNetwork,
  chain: EVMChain,
): boolean {
  const domainChainId = domain?.chainId;

  // eslint-disable-next-line no-null/no-null -- dApps send JSON, and ethers omits a null domain field
  if (domainChainId === undefined || domainChainId === null) {
    return true;
  }

  const expectedChainId = getEvmChainId(network, chain);
  const parsedChainId = parseChainId(domainChainId);

  return expectedChainId !== undefined && parsedChainId !== undefined && parsedChainId === BigInt(expectedChainId);
}

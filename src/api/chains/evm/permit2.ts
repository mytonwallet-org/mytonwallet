import { Interface } from 'ethers';

import type { ApiNetwork, EVMChain } from '../../types';

import { getEvmProvider } from './util/client';
import { normalizeAddress } from './address';

const ERC1271_ABI = ['function isValidSignature(bytes32 hash, bytes signature) view returns (bytes4)'];
const erc1271Interface = new Interface(ERC1271_ABI);

export type Permit2SignatureStrategy = 'raw';

// Throwaway SDK-compatible probe values. The signature is recoverable, but intentionally not for the probed account.
const RAW_ECDSA_PROBE_HASH = `0x${'ab'.repeat(32)}`;
const RAW_ECDSA_PROBE_SIGNATURE
  = '0x997c61aa10e2330c076d6ba7abca1e71703a8f039291db103a62e085c9b2cf0d'
    + '3f7e31ec9028229acc83093fbb722fa700fd6e4ea15d584df1bf384eb0051e0d1c';

export async function getEvmAccountCode(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
): Promise<string | undefined> {
  try {
    const code = await getEvmProvider(network, chain).getCode(normalizeAddress(address));
    return code || '0x';
  } catch {
    return undefined;
  }
}

export async function acceptsRawEcdsaSignature(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
): Promise<boolean> {
  try {
    const data = await getEvmProvider(network, chain).call({
      to: normalizeAddress(address),
      data: erc1271Interface.encodeFunctionData('isValidSignature', [
        RAW_ECDSA_PROBE_HASH,
        RAW_ECDSA_PROBE_SIGNATURE,
      ]),
    });

    return Boolean(data) && data.length >= 66;
  } catch {
    return false;
  }
}

export async function getPermit2SignatureStrategy(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
): Promise<Permit2SignatureStrategy | false> {
  const code = await getEvmAccountCode(chain, network, address);

  if (code === undefined) {
    return false;
  }

  if (code === '0x') {
    return 'raw';
  }

  return await acceptsRawEcdsaSignature(chain, network, address) ? 'raw' : false;
}

export async function canAccountUsePermit2(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
): Promise<boolean> {
  return Boolean(await getPermit2SignatureStrategy(chain, network, address));
}

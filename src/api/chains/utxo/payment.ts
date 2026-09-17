import { secp256k1 } from '@noble/curves/secp256k1';
import { p2pkh, p2sh, p2tr, p2wpkh } from '@scure/btc-signer';

import type { ApiDerivation, ApiNetwork, UTXOChain } from '../../types';

import { bytesToHex, hexToBytes } from '../../common/utils';
import { encodeCashAddressPayload } from './cashaddr';
import { UTXO_ADDRESS_TYPES, type UtxoAddressType } from './constants';
import { getUtxoCashAddrPrefix, getUtxoSignerNetwork } from './network';

export type UtxoPayment = {
  addressType: UtxoAddressType;
  address: string;
  script: Uint8Array;
  publicKey: string;
  tapInternalKey?: string;
  privateKeyBytes: Uint8Array;
};

function negatePrivateKey(privateKey: Uint8Array) {
  const scalar = secp256k1.utils.normPrivateKeyToScalar(privateKey);
  const negated = secp256k1.CURVE.n - scalar;
  const hex = negated.toString(16).padStart(64, '0');

  return hexToBytes(hex);
}

function getTaprootKeys(publicKey: Uint8Array, privateKey: Uint8Array) {
  if (publicKey.length === 32) {
    return { internalKey: publicKey, privateKeyBytes: privateKey };
  }

  const isOddY = publicKey[0] === 0x03;
  const adjustedPrivateKey = isOddY ? negatePrivateKey(privateKey) : privateKey;

  return {
    internalKey: publicKey.slice(1),
    privateKeyBytes: adjustedPrivateKey,
  };
}

function formatLegacyAddress(
  chain: UTXOChain,
  network: ApiNetwork,
  script: Uint8Array,
  legacyAddress: string,
) {
  if (chain !== 'bitcoincash') {
    return legacyAddress;
  }

  return encodeCashAddressPayload(getUtxoCashAddrPrefix(network), 'p2pkh', script.slice(3, 23));
}

export function getAddressTypeFromDerivation(
  derivation?: Pick<ApiDerivation, 'path' | 'label'>,
): UtxoAddressType | undefined {
  if (derivation?.label && UTXO_ADDRESS_TYPES.includes(derivation.label as UtxoAddressType)) {
    return derivation.label as UtxoAddressType;
  }

  const path = derivation?.path;
  if (!path) {
    return undefined;
  }

  return getAddressTypeFromPathTemplate(path);
}

export function getAddressTypeFromPathTemplate(pathTemplate: string): UtxoAddressType {
  if (pathTemplate.startsWith('m/86\'')) {
    return 'taproot';
  }

  if (pathTemplate.startsWith('m/84\'')) {
    return 'segwit';
  }

  if (pathTemplate.startsWith('m/49\'')) {
    return 'wrapped-segwit';
  }

  return 'legacy';
}

export function getAddressTypeFromAddress(address: string): UtxoAddressType {
  if (/^(?:bc1p|tb1p|ltc1p|tltc1p)/i.test(address)) {
    return 'taproot';
  }

  if (/^(?:bc1|tb1|ltc1|tltc1)/i.test(address)) {
    return 'segwit';
  }

  // P2SH prefixes used by BIP49 nested/wrapped segwit: BTC `3`/`2`, LTC `M`/`Q`
  if (/^[23MQ]/.test(address)) {
    return 'wrapped-segwit';
  }

  return 'legacy';
}

export function resolveAddressType(
  address: string,
  derivation?: ApiDerivation,
): UtxoAddressType {
  return getAddressTypeFromDerivation(derivation) ?? getAddressTypeFromAddress(address);
}

export function createUtxoPayment(
  chain: UTXOChain,
  network: ApiNetwork,
  publicKey: Uint8Array,
  privateKey: Uint8Array,
  addressType: UtxoAddressType,
): UtxoPayment {
  const signerNetwork = getUtxoSignerNetwork(chain, network);

  if (addressType === 'legacy') {
    const payment = p2pkh(publicKey, signerNetwork);

    return {
      addressType,
      address: formatLegacyAddress(chain, network, payment.script, payment.address!),
      script: payment.script,
      publicKey: bytesToHex(publicKey),
      privateKeyBytes: privateKey,
    };
  }

  if (addressType === 'wrapped-segwit') {
    const payment = p2sh(p2wpkh(publicKey, signerNetwork), signerNetwork);

    return {
      addressType,
      address: payment.address!,
      script: payment.script,
      publicKey: bytesToHex(publicKey),
      privateKeyBytes: privateKey,
    };
  }

  if (addressType === 'segwit') {
    const payment = p2wpkh(publicKey, signerNetwork);

    return {
      addressType,
      address: payment.address!,
      script: payment.script,
      publicKey: bytesToHex(publicKey),
      privateKeyBytes: privateKey,
    };
  }

  const { internalKey, privateKeyBytes } = getTaprootKeys(publicKey, privateKey);
  const payment = p2tr(internalKey, undefined, signerNetwork);

  return {
    addressType: 'taproot',
    address: payment.address!,
    script: payment.script,
    publicKey: bytesToHex(internalKey),
    tapInternalKey: bytesToHex(internalKey),
    privateKeyBytes,
  };
}

export function getUtxoLockingScripts(
  chain: UTXOChain,
  network: ApiNetwork,
  publicKeyHex: string,
  addressType: UtxoAddressType,
) {
  const publicKey = hexToBytes(publicKeyHex);
  const signerNetwork = getUtxoSignerNetwork(chain, network);

  if (addressType === 'legacy') {
    return { script: p2pkh(publicKey, signerNetwork).script };
  }

  if (addressType === 'wrapped-segwit') {
    const payment = p2sh(p2wpkh(publicKey, signerNetwork), signerNetwork);

    return {
      script: payment.script,
      redeemScript: payment.redeemScript,
    };
  }

  if (addressType === 'segwit') {
    return { script: p2wpkh(publicKey, signerNetwork).script };
  }

  return {
    script: p2tr(publicKey, undefined, signerNetwork).script,
    tapInternalKey: publicKey,
  };
}

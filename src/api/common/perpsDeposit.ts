import { getAddress, hexlify, parseUnits, toUtf8Bytes, TypedDataEncoder, zeroPadValue } from 'ethers';

import type { ApiPerpsCctpDeposit } from '../types';

import { ARBITRUM_USDC_MAINNET } from '../../config';
import { Big } from '../../lib/big.js';
import {
  HYPERLIQUID_BRIDGE_CHAIN_ID,
  PERPS_CCTP_EXTENSION_ADDRESS,
  PERPS_CCTP_FORWARD_FEE_USDC,
  PERPS_CCTP_FORWARD_FEE_USDC_BASE_UNITS,
} from './perps';

const CCTP_FORWARDER = '0xb21D281DEdb17AE5B501F6AA8256fe38C4e45757';
const CCTP_HYPEREVM_DOMAIN = 19;
const CCTP_FAST_FINALITY = 1000;
const RECEIVE_WITH_AUTHORIZATION = [
  { name: 'from', type: 'address' },
  { name: 'to', type: 'address' },
  { name: 'value', type: 'uint256' },
  { name: 'validAfter', type: 'uint256' },
  { name: 'validBefore', type: 'uint256' },
  { name: 'nonce', type: 'bytes32' },
];

/** Bind the signed USDC authorization and CCTP burn to the reviewed amount and the account's HyperCore balance. */
export function assertPerpsCctpDepositIntegrity(
  deposit: ApiPerpsCctpDeposit,
  walletAddress: string,
  expectedAmountUsdc: string,
): void {
  try {
    const wallet = getAddress(walletAddress);
    const amount = parseUnits(expectedAmountUsdc, ARBITRUM_USDC_MAINNET.decimals);
    const { domain, types, values } = deposit.permitData;
    const burn = deposit.burnCall;
    const forwarder = zeroPadValue(CCTP_FORWARDER, 32).toLowerCase();
    // Circle's cctp-forward v0 hook: 24-byte magic, version, data length, wallet, perps DEX (0).
    const hook = `${hexlify(toUtf8Bytes('cctp-forward')).padEnd(50, '0')}0000000000000018`
      + `${wallet.slice(2).toLowerCase()}00000000`;
    // The backend subtracts the fee with JS numbers (e.g. 10.117612000000001).
    // Compare informational credit at USDC precision; signed and burned amounts stay exact below.
    const creditedAmount = Big(deposit.creditedAmountUsdc).round(ARBITRUM_USDC_MAINNET.decimals, Big.roundHalfUp);
    if (
      deposit.requiresPermitSignature !== true
      || amount <= PERPS_CCTP_FORWARD_FEE_USDC_BASE_UNITS
      || !Big(deposit.amountUsdc).eq(expectedAmountUsdc)
      || !Big(deposit.feeUsdc).eq(PERPS_CCTP_FORWARD_FEE_USDC)
      || !creditedAmount.eq(Big(expectedAmountUsdc).minus(PERPS_CCTP_FORWARD_FEE_USDC))
      || BigInt(String(values.value)) !== amount
      || BigInt(burn.amount) !== amount
      || getAddress(String(values.from)) !== wallet
      || getAddress(String(values.to)) !== PERPS_CCTP_EXTENSION_ADDRESS
      || BigInt(String(values.validAfter)) < 0n
      || BigInt(String(values.validBefore)) <= BigInt(String(values.validAfter))
      || burn.destinationDomain !== CCTP_HYPEREVM_DOMAIN
      || burn.mintRecipient.toLowerCase() !== forwarder
      || burn.destinationCaller.toLowerCase() !== forwarder
      || BigInt(burn.maxFee) !== PERPS_CCTP_FORWARD_FEE_USDC_BASE_UNITS
      || burn.minFinalityThreshold !== CCTP_FAST_FINALITY
      || burn.hookData.toLowerCase() !== hook
      || Object.keys(types).length !== 1
      || !types.ReceiveWithAuthorization
    ) throw new Error('Invalid CCTP deposit');

    const expectedDomain = {
      name: 'USD Coin', version: '2', chainId: HYPERLIQUID_BRIDGE_CHAIN_ID,
      verifyingContract: ARBITRUM_USDC_MAINNET.tokenAddress,
    };
    // Comparing against the local schema also rejects a permit for a different action/domain or altered field types.
    const expectedDigest = TypedDataEncoder.hash(
      expectedDomain, { ReceiveWithAuthorization: RECEIVE_WITH_AUTHORIZATION }, {
        from: wallet, to: PERPS_CCTP_EXTENSION_ADDRESS, value: amount,
        validAfter: values.validAfter, validBefore: values.validBefore, nonce: values.nonce,
      },
    );
    const suppliedDigest = TypedDataEncoder.hash(
      domain, types as Record<string, typeof RECEIVE_WITH_AUTHORIZATION>, values,
    );
    if (expectedDigest !== suppliedDigest) throw new Error('Invalid USDC authorization');
  } catch {
    throw new Error('PerpsReviewChanged');
  }
}

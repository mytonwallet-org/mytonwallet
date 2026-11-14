import { Interface, Signature } from 'ethers';

import type {
  ApiAnyDisplayError,
  ApiEvmSwapTransactionRequest,
  ApiNetwork,
  ApiPerpsCctpDeposit,
  ApiPerpsExchangeActionPayload,
  ApiPerpsExchangeBuild,
  ApiPerpsExchangeSignature,
  ApiPerpsExchangeTypedData,
  ApiPerpsPermitData,
  ApiPerpsSignedExchangeAction,
  EVMChain,
} from '../../types';
import type { EvmMetaTransaction } from './smartAccount/types';
import { ApiTransactionError } from '../../types';

import { ARBITRUM_USDC_MAINNET } from '../../../config';
import { Big } from '../../../lib/big.js';
import { parseAccountId } from '../../../util/account';
import { logDebugError } from '../../../util/logs';
import { getEvmProvider } from './util/client';
import {
  buildPerpsCctpDepositTx,
  PERPS_CCTP_DEPOSIT_CHAIN,
  PERPS_CCTP_EXTENSION_ADDRESS,
} from '../../common/perps';
import { assertPerpsCctpDepositIntegrity } from '../../common/perpsDeposit';
import { estimateBatchUserOpFee, submitBatchUserOp, validateEvmSwapCalls } from './smartAccount/batch';
import { resolveBatchDelegation } from './smartAccount/delegation';
import { getEvmDelegationAddress } from './approvals';
import {
  assertHyperliquidExchangeBuildIntegrity,
  assertHyperliquidWithdrawPermitIntegrity,
  type HyperliquidExchangeSignOptions,
} from './hyperliquidPayloadValidation';
import { signEip712WithPrivateKey } from './sign';
import { getWalletBalance } from './wallet';

/** The account's unlocked Arbitrum wallet, resolved once per Perps flow and used for all of its signatures. */
export type PerpsSigner = {
  network: ApiNetwork;
  address: string;
  privateKey: string;
};

function evmTxToMetaTransaction(tx: ApiEvmSwapTransactionRequest): EvmMetaTransaction {
  return {
    to: tx.to,
    value: BigInt(tx.value || '0'),
    data: tx.data,
  };
}

function getPerpsCctpAllowedTargets(): Set<string> {
  return new Set([PERPS_CCTP_EXTENSION_ADDRESS.toLowerCase()]);
}

const erc20BalanceOfInterface = new Interface([
  'function balanceOf(address account) view returns (uint256)',
]);

/** Pimlico simulates execution during `pm_sponsorUserOperation`; CCTP cannot run without a real permit. */
function buildPerpsGasEstimationCalls(address: string): EvmMetaTransaction[] {
  return [{
    to: ARBITRUM_USDC_MAINNET.tokenAddress,
    value: 0n,
    data: erc20BalanceOfInterface.encodeFunctionData('balanceOf', [address]),
  }];
}

function formatUsdcBaseUnitsRoundedUp(value: bigint): string {
  return Big(value.toString())
    .div(Big(10).pow(ARBITRUM_USDC_MAINNET.decimals))
    .round(ARBITRUM_USDC_MAINNET.decimals, Big.roundUp)
    .toFixed();
}

/** Quotes Pimlico paymaster cost for a gasless CCTP deposit batch (simulation-safe calls). */
export async function estimatePerpsCctpDepositGasUsdc(
  accountId: string,
  address: string,
  deposit: ApiPerpsCctpDeposit,
): Promise<{ gasUsdc: string } | { error: ApiAnyDisplayError }> {
  const chain = PERPS_CCTP_DEPOSIT_CHAIN;
  const { network } = parseAccountId(accountId);

  try {
    assertPerpsCctpDepositIntegrity(deposit, address, deposit.amountUsdc);

    const needsGasless = await perpsDepositNeedsGasless(network, address);

    if (!needsGasless) {
      return { gasUsdc: '0' };
    }

    const feeResult = await estimateBatchUserOpFee(
      chain,
      network,
      address,
      buildPerpsGasEstimationCalls(address),
      { needsGasless: true, gasToken: ARBITRUM_USDC_MAINNET.tokenAddress },
    );

    if ('error' in feeResult) {
      return feeResult;
    }

    const paddedMaxCost = feeResult.maxCost;

    return { gasUsdc: formatUsdcBaseUnitsRoundedUp(paddedMaxCost) };
  } catch (err) {
    logDebugError(`evm:${chain}:estimatePerpsCctpDepositGasUsdc`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

function parsePermitSignature(signature: string): ApiPerpsExchangeSignature {
  const { r, s, v } = Signature.from(signature);

  return { r, s, v: Number(v) };
}

async function signVerifiedHyperliquidTypedData(
  signer: PerpsSigner,
  typedData: ApiPerpsExchangeTypedData,
): Promise<ApiPerpsExchangeSignature> {
  const signature = await signEip712WithPrivateKey(signer.network, signer.privateKey, {
    domain: typedData.domain,
    types: typedData.types,
    message: typedData.message,
  });

  return parsePermitSignature(signature);
}

export async function signHyperliquidExchangeBuild(
  signer: PerpsSigner,
  build: ApiPerpsExchangeBuild,
  options?: HyperliquidExchangeSignOptions,
): Promise<ApiPerpsExchangeSignature> {
  const typedData = assertHyperliquidExchangeBuildIntegrity(build, options);

  return signVerifiedHyperliquidTypedData(signer, typedData);
}

export async function signHyperliquidExchangePayload(
  signer: PerpsSigner,
  payload: ApiPerpsExchangeActionPayload,
  options?: HyperliquidExchangeSignOptions,
): Promise<ApiPerpsSignedExchangeAction> {
  const typedData = assertHyperliquidExchangeBuildIntegrity(payload, options);

  return {
    action: payload.action,
    nonce: payload.nonce,
    signature: await signVerifiedHyperliquidTypedData(signer, typedData),
  };
}

/** Signs a withdrawal that pays the signer's own wallet. */
export async function signHyperliquidWithdrawPermit(
  signer: PerpsSigner,
  withdraw: {
    action: Record<string, unknown>;
    nonce: number;
    permitData: ApiPerpsPermitData;
  },
): Promise<ApiPerpsExchangeSignature> {
  const permitData = assertHyperliquidWithdrawPermitIntegrity(withdraw, signer.address);

  const signature = await signEip712WithPrivateKey(signer.network, signer.privateKey, {
    domain: permitData.domain,
    types: permitData.types as Record<string, Array<{ name: string; type: string }>>,
    message: permitData.values,
  });

  return parsePermitSignature(signature);
}

async function buildSignedPerpsCctpBatchCalls(
  signer: PerpsSigner,
  deposit: ApiPerpsCctpDeposit,
): Promise<EvmMetaTransaction[]> {
  const permitData = deposit.permitData;

  const permitSignature = await signEip712WithPrivateKey(signer.network, signer.privateKey, {
    domain: permitData.domain,
    types: permitData.types as Record<string, Array<{ name: string; type: string }>>,
    message: permitData.values,
  });

  const cctpTx = buildPerpsCctpDepositTx({
    from: signer.address,
    deposit,
    permitSignature: parsePermitSignature(permitSignature),
  });

  return [evmTxToMetaTransaction(cctpTx)];
}

/**
 * Gas of one CCTP deposit userOp from a delegated Alchemy 7702 account on Arbitrum. 48 mainnet deposits through this
 * batch path used 248k-313k gas (median 259k, 46 of them at most 300k), apart from one 8.9M-gas userOp submitted
 * while Arbitrum's L1 data fee spiked. 300k is the median plus 16%.
 */
const PERPS_DEPOSIT_USER_OP_GAS = 300_000n;
/** A wallet's first deposit also installs its 7702 delegation: three such userOps used 273k-319k gas. */
const PERPS_DEPOSIT_DELEGATION_GAS = 60_000n;
const PERPS_FEE_DATA_CACHE_MS = 30_000;

const perpsGasPrices = new Map<ApiNetwork, { expiresAt: number; value: Promise<bigint> }>();
const perpsDelegationChecks = new Map<string, { expiresAt: number; value: Promise<boolean> }>();

/** Current Arbitrum `maxFeePerGas`, or the gas price without EIP-1559 data, as EVM swaps price their fee check. */
function getPerpsDepositGasPrice(network: ApiNetwork): Promise<bigint> {
  const cached = perpsGasPrices.get(network);
  if (cached && cached.expiresAt > Date.now()) return cached.value;

  const value = getEvmProvider(network, PERPS_CCTP_DEPOSIT_CHAIN).getFeeData().then(({ maxFeePerGas, gasPrice }) => {
    const price = maxFeePerGas ?? gasPrice;
    if (!price || price <= 0n) throw new Error('Arbitrum gas price is unavailable');
    return price;
  });
  perpsGasPrices.set(network, { expiresAt: Date.now() + PERPS_FEE_DATA_CACHE_MS, value });
  value.catch(() => {
    if (perpsGasPrices.get(network)?.value === value) perpsGasPrices.delete(network);
  });
  return value;
}

/** Whether a deposit from `address` also installs its 7702 delegation, read at most once per cache period. */
function needsPerpsDepositDelegation(network: ApiNetwork, address: string): Promise<boolean> {
  const key = `${network}:${address.toLowerCase()}`;
  const cached = perpsDelegationChecks.get(key);
  if (cached && cached.expiresAt > Date.now()) return cached.value;

  const value = getEvmDelegationAddress(PERPS_CCTP_DEPOSIT_CHAIN, network, address)
    .then((delegate) => resolveBatchDelegation(delegate).shouldDelegate);
  perpsDelegationChecks.set(key, { expiresAt: Date.now() + PERPS_FEE_DATA_CACHE_MS, value });
  return value;
}

/** The deposit pays gas in USDC when its ETH balance does not cover the estimated userOp. */
async function perpsDepositNeedsGasless(network: ApiNetwork, address: string): Promise<boolean> {
  const chain = PERPS_CCTP_DEPOSIT_CHAIN;

  try {
    const [nativeBalance, fee] = await Promise.all([
      getWalletBalance(chain, network, address),
      estimatePerpsDepositNetworkFee(chain, network, address),
    ]);

    return nativeBalance < fee;
  } catch (err) {
    logDebugError(`evm:${chain}:perpsDepositNeedsGasless`, err);

    return true;
  }
}

/** Native token, in wei, that a deposit userOp of `address` is estimated to cost at current fee data. */
export async function estimatePerpsDepositNetworkFee(
  chain: EVMChain, network: ApiNetwork, address: string,
): Promise<bigint> {
  if (chain !== PERPS_CCTP_DEPOSIT_CHAIN) throw new Error(`No Perps deposits on ${chain}`);

  const [gasPrice, needsDelegation] = await Promise.all([
    getPerpsDepositGasPrice(network),
    needsPerpsDepositDelegation(network, address),
  ]);
  const gas = PERPS_DEPOSIT_USER_OP_GAS + (needsDelegation ? PERPS_DEPOSIT_DELEGATION_GAS : 0n);

  return gas * gasPrice;
}

/** Checks the deposit against the signer's wallet and signs its USDC authorization into the CCTP call. */
export async function buildPerpsCctpDepositTransfer(
  signer: PerpsSigner,
  deposit: ApiPerpsCctpDeposit,
): Promise<{ calls: EvmMetaTransaction[] } | { error: ApiAnyDisplayError }> {
  const chain = PERPS_CCTP_DEPOSIT_CHAIN;

  try {
    if (!deposit.requiresPermitSignature || !deposit.permitData) {
      return { error: ApiTransactionError.UnsuccesfulTransfer };
    }

    assertPerpsCctpDepositIntegrity(deposit, signer.address, deposit.amountUsdc);
    const calls = await buildSignedPerpsCctpBatchCalls(signer, deposit);
    const validationError = validateEvmSwapCalls(calls, getPerpsCctpAllowedTargets());

    if (validationError) {
      return { error: validationError };
    }

    const needsGasless = await perpsDepositNeedsGasless(signer.network, signer.address);
    const feeResult = await estimateBatchUserOpFee(chain, signer.network, signer.address, calls, needsGasless
      ? { needsGasless: true, gasToken: ARBITRUM_USDC_MAINNET.tokenAddress }
      : undefined);

    if ('error' in feeResult) {
      return feeResult;
    }

    return { calls };
  } catch (err) {
    logDebugError(`evm:${chain}:buildPerpsCctpDepositTransfer`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

/** Submits the calls of `buildPerpsCctpDepositTransfer` as an EIP-7702 batch. */
export async function submitPerpsCctpDepositTransfer(
  signer: PerpsSigner,
  calls: EvmMetaTransaction[],
): Promise<{ txHash: string } | { error: string }> {
  const chain = PERPS_CCTP_DEPOSIT_CHAIN;

  try {
    const validationError = validateEvmSwapCalls(calls, getPerpsCctpAllowedTargets());

    if (validationError) {
      return { error: validationError };
    }

    const needsGasless = await perpsDepositNeedsGasless(signer.network, signer.address);
    const result = await submitBatchUserOp(
      chain, signer.network, signer.address, signer.privateKey, calls,
      needsGasless
        ? { needsGasless: true, gasToken: ARBITRUM_USDC_MAINNET.tokenAddress }
        : undefined,
    );

    return 'error' in result ? result : { txHash: result.txHash };
  } catch (err) {
    logDebugError(`evm:${chain}:submitPerpsCctpDepositTransfer`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

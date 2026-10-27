import {
  Interface,
  keccak256,
  type TransactionRequest,
  type TypedDataField,
} from 'ethers';

import type {
  ApiAnyDisplayError,
  ApiNetwork,
  ApiSwapActivity,
  EVMChain,
  OnApiUpdate,
} from '../../types';
import type {
  ApiBuildOnchainSwapTransferOptions,
  ApiBuildOnchainSwapTransferResult,
  ApiSubmitOnchainSwapTransferOptions,
  ApiSubmitOnchainSwapTransferResult,
} from '../../types/swap';
import type { EvmMetaTransaction } from './smartAccount/types';
import { ApiCommonError, ApiTransactionError } from '../../types';

import { parseAccountId } from '../../../util/account';
import { bigintMax, bigintMultiplyToNumber } from '../../../util/bigint';
import { unique } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { fetchEvmWallet } from './util/account';
import { getEvmProvider } from './util/client';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { patchSwapItem } from '../../common/swap';
import { callHook } from '../../hooks';
import {
  estimateBatchUserOpFee,
  submitBatchUserOp,
  validateEvmSwapCalls,
} from './smartAccount/batch';
import { isAlchemy7702Delegated } from './smartAccount/delegation';
import { normalizeAddress } from './address';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import { EVM_MAX_TRANSFER_FEE_MULTIPLIER, getEvmChainId, UNISWAP_PERMIT2_ADDRESS } from './constants';
import { getPermit2SignatureStrategy } from './permit2';
import { signEip712WithPrivateKey } from './sign';
import { serializeEvmSwapCalls } from './swapCalls';
import { getWalletBalance } from './wallet';

const erc20ApproveInterface = new Interface(['function approve(address spender, uint256 amount) returns (bool)']);
const permit2AllowanceInterface = new Interface([
  'function approve(address token, address spender, uint160 amount, uint48 expiration)',
]);
const permit2PermitInterface = new Interface([
  // eslint-disable-next-line @stylistic/max-len
  'function permit(address owner, ((address token, uint160 amount, uint48 expiration, uint48 nonce) details, address spender, uint256 sigDeadline) permitSingle, bytes signature)',
]);
const lifiPermit2ProxyInterface = new Interface([
  'function nextNonce(address owner) view returns (uint256)',
  // eslint-disable-next-line @stylistic/max-len
  'function callDiamondWithPermit2(bytes diamondCalldata, ((address token, uint256 amount) permitted, uint256 nonce, uint256 deadline) permit, bytes signature)',
  // eslint-disable-next-line @stylistic/max-len
  'function callDiamondWithPermit2Witness(bytes diamondCalldata, address account, ((address token, uint256 amount) permitted, uint256 nonce, uint256 deadline) permit, bytes signature) payable',
]);

const MAX_PERMIT2_AMOUNT = (1n << 160n) - 1n;
const MAX_PERMIT2_EXPIRATION = (1n << 48n) - 1n;

type UniswapPermitDetails = {
  token: string;
  amount: string;
  expiration: string;
  nonce: string;
};

type UniswapPermitSingleValues = {
  details: UniswapPermitDetails;
  spender: string;
  sigDeadline: string;
};

type UniswapPermitData = {
  domain: Record<string, unknown>;
  types: Record<string, Array<{ name: string; type: string }>>;
  values: UniswapPermitSingleValues;
};

type EvmSwapTransactionRequest = {
  to: string;
  from: string;
  data: string;
  value: string;
  chainId: number;
  gasLimit?: string;
  maxFeePerGas?: string;
  maxPriorityFeePerGas?: string;
  gasPrice?: string;
};

type UniswapTransactionRequest = EvmSwapTransactionRequest;

type EvmSwapTransactionPayload = {
  provider?: 'uniswap' | 'lifi';
  routing?: string;
  swap?: EvmSwapTransactionRequest;
  approval?: EvmSwapTransactionRequest;
  permitData?: UniswapPermitData | null;
  requiresPermitSignature?: boolean;
  lifiPermit2?: {
    token: string;
    amount: string;
    permit2: string;
    permit2Proxy: string;
    deadlineSeconds: number;
    witness?: {
      diamondAddress: string;
    };
    transactionRequest: EvmSwapTransactionRequest;
  };
};

type UniswapEvmTransactionPayload = EvmSwapTransactionPayload & {
  routing: string;
  requiresPermitSignature: boolean;
};

export function parseEvmSwapTransactionPayload(transaction: string): EvmSwapTransactionPayload {
  const payload = JSON.parse(transaction) as EvmSwapTransactionPayload;

  if (
    payload.requiresPermitSignature !== undefined
    && typeof payload.requiresPermitSignature !== 'boolean'
  ) {
    throw new Error('Invalid EVM swap payload');
  }

  return payload;
}

function hasLifiPermit2Data(payload: EvmSwapTransactionPayload): payload is EvmSwapTransactionPayload & {
  provider: 'lifi';
  lifiPermit2: NonNullable<EvmSwapTransactionPayload['lifiPermit2']>;
} {
  return payload.provider === 'lifi'
    && !!payload.lifiPermit2?.token
    && !!payload.lifiPermit2.amount
    && !!payload.lifiPermit2.permit2
    && !!payload.lifiPermit2.permit2Proxy
    && !!payload.lifiPermit2.transactionRequest?.data;
}

export function parseUniswapTransactionPayload(transaction: string): UniswapEvmTransactionPayload {
  const payload = parseEvmSwapTransactionPayload(transaction);

  if (typeof payload.requiresPermitSignature !== 'boolean') {
    throw new Error('Invalid Uniswap swap payload');
  }

  return payload as UniswapEvmTransactionPayload;
}

function evmSwapTxToMetaTransaction(tx: EvmSwapTransactionRequest): EvmMetaTransaction {
  return {
    to: tx.to,
    value: BigInt(tx.value || '0'),
    data: tx.data,
  };
}

function isPermit2Address(address: string): boolean {
  return normalizeAddress(address) === UNISWAP_PERMIT2_ADDRESS;
}

function tryParseErc20ApproveSpender(data: string): string | undefined {
  try {
    const [spender] = erc20ApproveInterface.decodeFunctionData('approve', data);
    return typeof spender === 'string' ? normalizeAddress(spender) : undefined;
  } catch {
    return undefined;
  }
}

export async function resolveSwapNeedsBatch(chain: EVMChain, accountId: string, needsApprove?: boolean) {
  if (needsApprove) return true;

  const { network } = parseAccountId(accountId);
  const { address } = await fetchEvmWallet(accountId, chain);
  return !(await isAlchemy7702Delegated(chain, network, address));
}

export function hasUniswapPermitData(payload: UniswapEvmTransactionPayload): payload is UniswapEvmTransactionPayload & {
  permitData: UniswapPermitData;
} {
  return !!payload.permitData?.domain && !!payload.permitData.types && !!payload.permitData.values;
}

export function shouldBatchUniswapSwap(
  payload: UniswapEvmTransactionPayload,
  options?: { needsBatch?: boolean; needsDelegate?: boolean },
) {
  return !!options?.needsBatch || !!options?.needsDelegate || hasUniswapPermitData(payload);
}

async function resolveShouldBatchUniswapSwap(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  payload: UniswapEvmTransactionPayload,
  needsBatch?: boolean,
) {
  if (shouldBatchUniswapSwap(payload, { needsBatch })) {
    return true;
  }

  const needsDelegate = !(await isAlchemy7702Delegated(chain, network, address));
  return shouldBatchUniswapSwap(payload, { needsDelegate });
}

export function shouldIncludePermit2AllowanceCall(payload: UniswapEvmTransactionPayload) {
  if (hasUniswapPermitData(payload) || !payload.approval || !payload.swap) {
    return false;
  }

  const approvalSpender = tryParseErc20ApproveSpender(payload.approval.data);
  return !!approvalSpender && isPermit2Address(approvalSpender);
}

function shouldApplyUniswapPermit2Rules(payload: EvmSwapTransactionPayload): payload is UniswapEvmTransactionPayload {
  return payload.provider === undefined || payload.provider === 'uniswap';
}

function buildPermit2AllowanceCall(token: string, spender: string): EvmMetaTransaction {
  return {
    to: UNISWAP_PERMIT2_ADDRESS,
    value: 0n,
    data: permit2AllowanceInterface.encodeFunctionData('approve', [
      token,
      spender,
      MAX_PERMIT2_AMOUNT,
      MAX_PERMIT2_EXPIRATION,
    ]),
  };
}

export function buildPermit2PermitCall(
  owner: string,
  permitData: UniswapPermitData,
  signature: string,
): EvmMetaTransaction {
  const { details, spender, sigDeadline } = permitData.values;

  return {
    to: UNISWAP_PERMIT2_ADDRESS,
    value: 0n,
    data: permit2PermitInterface.encodeFunctionData('permit', [
      owner,
      {
        details: {
          token: details.token,
          amount: BigInt(details.amount),
          expiration: Number(details.expiration),
          nonce: Number(details.nonce),
        },
        spender,
        sigDeadline: BigInt(sigDeadline),
      },
      signature,
    ]),
  };
}

export async function signUniswapPermit2(
  network: ApiNetwork,
  privateKey: string,
  permitData: UniswapPermitData,
): Promise<string> {
  return signEip712WithPrivateKey(network, privateKey, {
    domain: permitData.domain,
    types: permitData.types,
    message: permitData.values,
  });
}

function resolveUniswapBatchOwner(payload: UniswapEvmTransactionPayload): string {
  const owner = payload.swap?.from ?? payload.approval?.from;

  if (!owner) {
    throw new Error('Missing swap owner for Permit2 permit');
  }

  return owner;
}

export function buildUniswapBatchCalls(
  payload: UniswapEvmTransactionPayload,
  permitSignature?: string,
): EvmMetaTransaction[] {
  return buildEvmSwapBatchCalls(payload, permitSignature);
}

export function buildEvmSwapBatchCalls(
  payload: EvmSwapTransactionPayload,
  permitSignature?: string,
): EvmMetaTransaction[] {
  const calls: EvmMetaTransaction[] = [];

  if (payload.approval) {
    calls.push(evmSwapTxToMetaTransaction(payload.approval));
  }

  if (shouldApplyUniswapPermit2Rules(payload) && hasUniswapPermitData(payload)) {
    if (!permitSignature) {
      throw new Error('Missing Permit2 EIP-712 signature');
    }

    calls.push(buildPermit2PermitCall(
      resolveUniswapBatchOwner(payload),
      payload.permitData,
      permitSignature,
    ));
  } else if (shouldApplyUniswapPermit2Rules(payload) && shouldIncludePermit2AllowanceCall(payload)) {
    calls.push(buildPermit2AllowanceCall(payload.approval!.to, payload.swap!.to));
  }

  if (payload.swap) {
    calls.push(evmSwapTxToMetaTransaction(payload.swap));
  }

  return calls;
}

async function buildSignedUniswapBatchCalls(
  network: ApiNetwork,
  privateKey: string,
  payload: UniswapEvmTransactionPayload,
): Promise<EvmMetaTransaction[]> {
  let permitSignature: string | undefined;

  if (hasUniswapPermitData(payload)) {
    permitSignature = await signUniswapPermit2(network, privateKey, payload.permitData);
  }

  return buildUniswapBatchCalls(payload, permitSignature);
}

export function getEvmSwapAllowedTargets(payload: EvmSwapTransactionPayload) {
  const targets = new Set<string>();

  if (payload.approval?.to) {
    targets.add(payload.approval.to.toLowerCase());
  }

  if (payload.swap?.to) {
    targets.add(payload.swap.to.toLowerCase());
  }

  if (payload.lifiPermit2?.permit2Proxy) {
    targets.add(payload.lifiPermit2.permit2Proxy.toLowerCase());
  }

  if (
    shouldApplyUniswapPermit2Rules(payload)
    && (hasUniswapPermitData(payload) || shouldIncludePermit2AllowanceCall(payload))
  ) {
    targets.add(UNISWAP_PERMIT2_ADDRESS.toLowerCase());
  }

  return targets;
}

export function getUniswapAllowedTargets(payload: UniswapEvmTransactionPayload) {
  return getEvmSwapAllowedTargets(payload);
}

function errorToString(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

async function fetchSwapHistoryAddress(accountId: string) {
  const { address } = await fetchStoredWallet(accountId, 'ton');
  return address;
}

function assertUniswapPayloadReady(
  payload: EvmSwapTransactionPayload,
): ApiAnyDisplayError | undefined {
  if (hasLifiPermit2Data(payload)) {
    return undefined;
  }

  if (!payload.swap) {
    return ApiTransactionError.UnsuccesfulTransfer;
  }

  if (
    shouldApplyUniswapPermit2Rules(payload)
    && payload.requiresPermitSignature
    && !hasUniswapPermitData(payload)
  ) {
    return ApiTransactionError.UnsuccesfulTransfer;
  }

  return undefined;
}

export function buildLifiPermit2TypedData(
  payload: EvmSwapTransactionPayload & { lifiPermit2: NonNullable<EvmSwapTransactionPayload['lifiPermit2']> },
  nonce: bigint,
  deadline: bigint,
) {
  const isWitness = Boolean(payload.lifiPermit2.witness);
  const tokenPermissions = [
    { name: 'token', type: 'address' },
    { name: 'amount', type: 'uint256' },
  ];
  const types: Record<string, TypedDataField[]> = isWitness ? {
    TokenPermissions: tokenPermissions,
    LiFiCall: [
      { name: 'diamondAddress', type: 'address' },
      { name: 'diamondCalldataHash', type: 'bytes32' },
    ],
    PermitWitnessTransferFrom: [
      { name: 'permitted', type: 'TokenPermissions' },
      { name: 'spender', type: 'address' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' },
      { name: 'witness', type: 'LiFiCall' },
    ],
  } : {
    PermitTransferFrom: [
      { name: 'permitted', type: 'TokenPermissions' },
      { name: 'spender', type: 'address' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' },
    ],
    TokenPermissions: tokenPermissions,
  };

  return {
    domain: {
      name: 'Permit2',
      chainId: payload.lifiPermit2.transactionRequest.chainId,
      verifyingContract: payload.lifiPermit2.permit2,
    },
    types,
    message: {
      permitted: {
        token: payload.lifiPermit2.token,
        amount: payload.lifiPermit2.amount,
      },
      spender: payload.lifiPermit2.permit2Proxy,
      nonce,
      deadline,
      ...(payload.lifiPermit2.witness ? {
        witness: {
          diamondAddress: payload.lifiPermit2.witness.diamondAddress,
          diamondCalldataHash: keccak256(payload.lifiPermit2.transactionRequest.data),
        },
      } : undefined),
    },
  };
}

export function encodeLifiPermit2Call(
  payload: EvmSwapTransactionPayload & { lifiPermit2: NonNullable<EvmSwapTransactionPayload['lifiPermit2']> },
  nonce: bigint,
  deadline: bigint,
  signature: string,
  accountAddress = payload.lifiPermit2.transactionRequest.from,
): string {
  if (payload.lifiPermit2.witness) {
    return lifiPermit2ProxyInterface.encodeFunctionData('callDiamondWithPermit2Witness', [
      payload.lifiPermit2.transactionRequest.data,
      accountAddress,
      [[payload.lifiPermit2.token, BigInt(payload.lifiPermit2.amount)], nonce, deadline],
      signature,
    ]);
  }

  return lifiPermit2ProxyInterface.encodeFunctionData('callDiamondWithPermit2', [
    payload.lifiPermit2.transactionRequest.data,
    [[payload.lifiPermit2.token, BigInt(payload.lifiPermit2.amount)], nonce, deadline],
    signature,
  ]);
}

function getLifiPermit2TypedDataSignature(
  signer: ReturnType<typeof getSignerFromPrivateKey>,
  typedData: ReturnType<typeof buildLifiPermit2TypedData>,
) {
  return signer.signTypedData(typedData.domain, typedData.types, typedData.message);
}

async function getLifiPermit2Signature(
  signer: ReturnType<typeof getSignerFromPrivateKey>,
  typedData: ReturnType<typeof buildLifiPermit2TypedData>,
) {
  return getLifiPermit2TypedDataSignature(signer, typedData);
}

async function readLifiPermit2Nonce(
  provider: ReturnType<typeof getEvmProvider>,
  permit2Proxy: string,
  owner: string,
): Promise<bigint> {
  const result = await provider.call({
    to: permit2Proxy,
    data: lifiPermit2ProxyInterface.encodeFunctionData('nextNonce', [owner]),
  });
  const [nonce] = lifiPermit2ProxyInterface.decodeFunctionResult('nextNonce', result);
  return BigInt(nonce.toString());
}

export async function buildSignedLifiPermit2Transaction(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  privateKey: string,
  payload: EvmSwapTransactionPayload & { lifiPermit2: NonNullable<EvmSwapTransactionPayload['lifiPermit2']> },
): Promise<EvmSwapTransactionRequest | { error: ApiAnyDisplayError }> {
  const expectedChainId = getEvmChainId(network, chain);
  const { transactionRequest } = payload.lifiPermit2;

  if (
    expectedChainId === undefined
    || transactionRequest.chainId !== expectedChainId
    || normalizeAddress(transactionRequest.from) !== normalizeAddress(address)
  ) {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  const permit2SignatureStrategy = await getPermit2SignatureStrategy(chain, network, address);
  if (!permit2SignatureStrategy) {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  const provider = getEvmProvider(network, chain);
  const signer = getSignerFromPrivateKey(network, privateKey);
  const nonce = await readLifiPermit2Nonce(provider, payload.lifiPermit2.permit2Proxy, address);
  const deadline = BigInt(Math.floor(Date.now() / 1000) + payload.lifiPermit2.deadlineSeconds);
  const typedData = buildLifiPermit2TypedData(payload, nonce, deadline);
  const signature = await getLifiPermit2Signature(signer, typedData);
  const data = encodeLifiPermit2Call(payload, nonce, deadline, signature, address);

  return {
    from: address,
    to: payload.lifiPermit2.permit2Proxy,
    chainId: transactionRequest.chainId,
    data,
    value: transactionRequest.value || '0',
  };
}

function toTransactionRequest(
  address: string,
  tx: EvmSwapTransactionRequest,
): TransactionRequest {
  return {
    from: address,
    to: tx.to,
    data: tx.data,
    value: BigInt(tx.value || '0'),
  };
}

function mapTransactionRequest(
  request: NonNullable<ApiBuildOnchainSwapTransferOptions['transactionRequest']>,
): TransactionRequest {
  return {
    from: request.from,
    to: request.to,
    data: request.data,
    value: request.value ? BigInt(request.value) : undefined,
    gasPrice: request.gasPrice ? BigInt(request.gasPrice) : undefined,
    gasLimit: request.gasLimit ? BigInt(request.gasLimit) : undefined,
    maxFeePerGas: request.maxFeePerGas ? BigInt(request.maxFeePerGas) : undefined,
    maxPriorityFeePerGas: request.maxPriorityFeePerGas ? BigInt(request.maxPriorityFeePerGas) : undefined,
    chainId: request.chainId,
  };
}

export function resolveSwapGasLimit(estimatedGasLimit: bigint, backendGasLimit?: string) {
  let gasLimit = bigintMultiplyToNumber(estimatedGasLimit, EVM_MAX_TRANSFER_FEE_MULTIPLIER);

  if (backendGasLimit) {
    gasLimit = bigintMax(gasLimit, BigInt(backendGasLimit));
  }

  return gasLimit;
}

async function estimateRegularSwapFee(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  payload: EvmSwapTransactionPayload,
  useBatching: boolean,
): Promise<{ error: ApiAnyDisplayError } | undefined> {
  const provider = getEvmProvider(network, chain);
  const transactions: Array<{ request: TransactionRequest; backendGasLimit?: string }> = [];

  if (!useBatching && payload.approval) {
    transactions.push({
      request: toTransactionRequest(address, payload.approval),
      backendGasLimit: payload.approval.gasLimit,
    });
  }

  if (payload.swap) {
    transactions.push({
      request: toTransactionRequest(address, payload.swap),
      backendGasLimit: payload.swap.gasLimit,
    });
  }

  let totalFee = 0n;

  const feeData = await provider.getFeeData();
  const gasPrice = feeData.maxFeePerGas ?? feeData.gasPrice ?? 0n;

  for (const { request, backendGasLimit } of transactions) {
    const estimatedGasLimit = await provider.estimateGas(request);
    const gasLimit = resolveSwapGasLimit(estimatedGasLimit, backendGasLimit);
    totalFee += gasLimit * gasPrice;
  }

  const nativeBalance = await getWalletBalance(chain, network, address);
  if (nativeBalance < totalFee) {
    return { error: ApiTransactionError.InsufficientBalance };
  }

  return undefined;
}

async function sendUniswapTransaction(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  privateKey: string,
  tx: UniswapTransactionRequest,
) {
  const provider = getEvmProvider(network, chain);
  const signer = getSignerFromPrivateKey(network, privateKey).connect(provider);
  const transaction = toTransactionRequest(address, tx);
  const estimatedGasLimit = await provider.estimateGas(transaction);
  const gasLimit = resolveSwapGasLimit(estimatedGasLimit, tx.gasLimit);

  const response = await signer.sendTransaction({ ...transaction, gasLimit });

  return response.hash;
}

export async function buildOnchainSwapTransfer(
  chain: EVMChain,
  options: ApiBuildOnchainSwapTransferOptions,
): Promise<ApiBuildOnchainSwapTransferResult | { error: ApiAnyDisplayError }> {
  const { accountId, request, transaction, transactionRequest, swapId, authToken, enclaveToken } = options;
  const { network } = parseAccountId(accountId);

  if (transactionRequest) {
    return {
      id: swapId,
      chain,
      transactionRequest,
    };
  }

  if (!transaction) {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  const historyAddress = await fetchSwapHistoryAddress(accountId);

  try {
    const { address } = await fetchEvmWallet(accountId, chain);
    const payload = parseEvmSwapTransactionPayload(transaction);
    const payloadError = assertUniswapPayloadReady(payload);

    if (payloadError) {
      await patchSwapItem({ address: historyAddress, swapId, authToken, error: payloadError });
      return { error: payloadError };
    }

    if (hasLifiPermit2Data(payload)) {
      return {
        id: swapId,
        chain,
        transaction,
        needsBatch: Boolean(payload.approval),
      };
    }

    if (!shouldApplyUniswapPermit2Rules(payload)) {
      return { error: ApiTransactionError.UnsuccesfulTransfer };
    }

    if (await resolveShouldBatchUniswapSwap(chain, network, address, payload, request.needsBatch)) {
      const account = await fetchStoredChainAccount(accountId, chain);

      if (account.type === 'ledger' || account.type === 'view') {
        return { error: ApiTransactionError.UnsuccesfulTransfer };
      }

      const privateKey = await fetchPrivateKeyString(chain, accountId, enclaveToken, account);

      if (!privateKey) {
        return { error: ApiCommonError.InvalidPassword };
      }

      const calls = await buildSignedUniswapBatchCalls(network, privateKey, payload);

      if (!calls.length) {
        return { error: ApiTransactionError.UnsuccesfulTransfer };
      }

      const feeResult = await estimateBatchUserOpFee(chain, network, address, calls);

      if ('error' in feeResult) {
        await patchSwapItem({ address: historyAddress, swapId, authToken, error: feeResult.error });
        return feeResult;
      }

      return {
        id: swapId,
        chain,
        transaction,
        calls: serializeEvmSwapCalls(calls),
        needsBatch: true,
      };
    }

    const feeError = await estimateRegularSwapFee(chain, network, address, payload, false);

    if (feeError) {
      await patchSwapItem({ address: historyAddress, swapId, authToken, error: feeError.error });
      return feeError;
    }

    return {
      id: swapId,
      chain,
      transaction,
      needsBatch: false,
    };
  } catch (err) {
    await patchSwapItem({
      address: historyAddress, swapId, authToken, error: errorToString(err),
    });

    throw err;
  }
}

async function submitRegularUniswapSwap(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  privateKey: string,
  transaction: string,
  useBatching: boolean,
): Promise<{ txHash: string } | { error: ApiAnyDisplayError }> {
  const payload = parseUniswapTransactionPayload(transaction);
  const payloadError = assertUniswapPayloadReady(payload);

  if (payloadError) {
    return { error: payloadError };
  }

  const transactions: UniswapTransactionRequest[] = [];

  if (!useBatching && payload.approval) {
    transactions.push(payload.approval);
  }

  transactions.push(payload.swap!);

  let lastHash = '';

  try {
    for (const tx of transactions) {
      lastHash = await sendUniswapTransaction(chain, network, address, privateKey, tx);
    }

    return { txHash: lastHash };
  } catch (err) {
    logDebugError(`evm:${chain}:submitRegularUniswapSwap`, err);
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

export async function submitLifiPermit2Swap(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  privateKey: string,
  payload: EvmSwapTransactionPayload & { lifiPermit2: NonNullable<EvmSwapTransactionPayload['lifiPermit2']> },
  useBatching: boolean,
): Promise<{ txHash: string } | { error: ApiAnyDisplayError }> {
  try {
    const signedTransaction = await buildSignedLifiPermit2Transaction(chain, network, address, privateKey, payload);

    if ('error' in signedTransaction) {
      return signedTransaction;
    }

    if (useBatching) {
      if (!payload.approval) {
        return { error: ApiTransactionError.UnsuccesfulTransfer };
      }

      const calls = [
        evmSwapTxToMetaTransaction(payload.approval),
        evmSwapTxToMetaTransaction(signedTransaction),
      ];
      const validationError = validateEvmSwapCalls(calls, getEvmSwapAllowedTargets(payload));

      if (validationError) {
        return { error: validationError };
      }

      const result = await submitBatchUserOp(chain, network, address, privateKey, calls);
      return 'error' in result ? result : { txHash: result.txHash };
    }

    const provider = getEvmProvider(network, chain);
    const signer = getSignerFromPrivateKey(network, privateKey).connect(provider);
    const transaction = toTransactionRequest(address, signedTransaction);
    const estimatedGasLimit = await provider.estimateGas(transaction);
    const gasLimit = resolveSwapGasLimit(estimatedGasLimit, signedTransaction.gasLimit);
    const response = await signer.sendTransaction({ ...transaction, gasLimit });

    return { txHash: response.hash };
  } catch (err) {
    logDebugError(`evm:${chain}:submitLifiPermit2Swap`, err);
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

export async function submitOnchainSwapTransfer(
  chain: EVMChain,
  options: ApiSubmitOnchainSwapTransferOptions,
  onUpdate: OnApiUpdate,
): Promise<ApiSubmitOnchainSwapTransferResult> {
  const {
    accountId,
    enclaveToken,
    authToken,
    localSwap,
    swapId,
    transaction,
    transactionRequest,
    needsBatch,
  } = options;

  const { network } = parseAccountId(accountId);
  const [historyAddress, { address }] = await Promise.all([
    fetchSwapHistoryAddress(accountId),
    fetchEvmWallet(accountId, chain),
  ]);
  const account = await fetchStoredChainAccount(accountId, chain);

  if (account.type === 'ledger' || account.type === 'view') {
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }

  onUpdate({
    type: 'newLocalActivities',
    accountId,
    activities: [localSwap],
  });

  try {
    const privateKey = await fetchPrivateKeyString(chain, accountId, enclaveToken, account);

    if (!privateKey) {
      return { error: ApiCommonError.InvalidPassword };
    }

    let txHash: string;

    if (transactionRequest) {
      if (normalizeAddress(transactionRequest.from) !== normalizeAddress(address)) {
        return { error: ApiTransactionError.UnsuccesfulTransfer };
      }

      const provider = getEvmProvider(network, chain);
      const signer = getSignerFromPrivateKey(network, privateKey).connect(provider);
      const response = await signer.sendTransaction(mapTransactionRequest(transactionRequest));
      txHash = response.hash;
    } else if (transaction) {
      const payload = parseEvmSwapTransactionPayload(transaction);

      if (hasLifiPermit2Data(payload)) {
        const result = await submitLifiPermit2Swap(
          chain, network, address, privateKey, payload, Boolean(payload.approval),
        );

        if ('error' in result) {
          onUpdate({
            type: 'newLocalActivities',
            accountId,
            activities: [{ ...localSwap, status: 'failed' }],
          });

          await patchSwapItem({ address: historyAddress, swapId, authToken, error: result.error });

          return { error: result.error };
        }

        txHash = result.txHash;
      } else if (shouldApplyUniswapPermit2Rules(payload)
        && await resolveShouldBatchUniswapSwap(chain, network, address, payload, needsBatch)) {
        const payloadError = assertUniswapPayloadReady(payload);

        if (payloadError) {
          return { error: payloadError };
        }

        const calls = await buildSignedUniswapBatchCalls(network, privateKey, payload);

        const validationError = validateEvmSwapCalls(calls, getUniswapAllowedTargets(payload));

        if (validationError) {
          return { error: validationError };
        }

        const result = await submitBatchUserOp(chain, network, address, privateKey, calls);

        if ('error' in result) {
          onUpdate({
            type: 'newLocalActivities',
            accountId,
            activities: [{ ...localSwap, status: 'failed' }],
          });

          await patchSwapItem({ address: historyAddress, swapId, authToken, error: result.error });

          return { error: result.error };
        }

        txHash = result.txHash;
      } else if (shouldApplyUniswapPermit2Rules(payload)) {
        const result = await submitRegularUniswapSwap(
          chain, network, address, privateKey, transaction, false,
        );

        if ('error' in result) {
          onUpdate({
            type: 'newLocalActivities',
            accountId,
            activities: [{ ...localSwap, status: 'failed' }],
          });

          await patchSwapItem({ address: historyAddress, swapId, authToken, error: result.error });

          return { error: result.error };
        }

        txHash = result.txHash;
      } else {
        return { error: ApiTransactionError.UnsuccesfulTransfer };
      }
    } else {
      return { error: ApiTransactionError.UnsuccesfulTransfer };
    }

    const updatedSwap: ApiSwapActivity = {
      ...localSwap,
      externalMsgHashNorm: txHash,
      hashes: unique([...localSwap.hashes, txHash]),
      transactionIds: { outgoing: { hash: txHash, chain } },
    };

    onUpdate({
      type: 'newLocalActivities',
      accountId,
      activities: [updatedSwap],
    });

    await patchSwapItem({
      address: historyAddress, swapId, authToken, msgHash: txHash, msgHashNormalized: txHash,
    });

    void callHook('onSwapCreated', accountId, updatedSwap.timestamp - 1);

    return { activityId: updatedSwap.id, submittedHashes: [txHash] };
  } catch (err) {
    logDebugError(`evm:${chain}:submitOnchainSwapTransfer`, err);

    onUpdate({
      type: 'newLocalActivities',
      accountId,
      activities: [{ ...localSwap, status: 'failed' }],
    });

    await patchSwapItem({
      address: historyAddress, swapId, authToken, error: errorToString(err),
    });

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

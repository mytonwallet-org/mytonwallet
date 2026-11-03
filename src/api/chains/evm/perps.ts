import { Signature } from 'ethers';

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
} from '../../types';
import type {
  ApiBuildPerpsCctpDepositTransferResult,
  ApiSubmitPerpsCctpDepositTransferOptions,
  ApiSubmitPerpsCctpDepositTransferResult,
} from '../../types/perps';
import type { EvmMetaTransaction } from './smartAccount/types';
import { ApiCommonError, ApiTransactionError } from '../../types';

import { parseAccountId } from '../../../util/account';
import { logDebugError } from '../../../util/logs';
import { fetchEvmWallet } from './util/account';
import { fetchStoredChainAccount } from '../../common/accounts';
import {
  buildPerpsCctpDepositTx,
  PERPS_CCTP_DEPOSIT_CHAIN,
  PERPS_CCTP_EXTENSION_ADDRESS,
} from '../../common/perps';
import { assertPerpsCctpDepositIntegrity } from '../../common/perpsDeposit';
import { estimateBatchUserOpFee, submitBatchUserOp, validateEvmSwapCalls } from './smartAccount/batch';
import { fetchPrivateKeyString } from './auth';
import {
  assertHyperliquidExchangeBuildIntegrity,
  assertHyperliquidWithdrawPermitIntegrity,
  type HyperliquidExchangeSignOptions,
} from './hyperliquidPayloadValidation';
import { signEip712WithPrivateKey } from './sign';
import { serializeEvmSwapCalls } from './swapCalls';

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

function parsePermitSignature(signature: string): ApiPerpsExchangeSignature {
  const { r, s, v } = Signature.from(signature);

  return { r, s, v: Number(v) };
}

async function signVerifiedHyperliquidTypedData(
  network: ApiNetwork,
  privateKey: string,
  typedData: ApiPerpsExchangeTypedData,
): Promise<ApiPerpsExchangeSignature> {
  const signature = await signEip712WithPrivateKey(network, privateKey, {
    domain: typedData.domain,
    types: typedData.types,
    message: typedData.message,
  });

  return parsePermitSignature(signature);
}

export async function signHyperliquidExchangeBuild(
  network: ApiNetwork,
  privateKey: string,
  build: ApiPerpsExchangeBuild,
  options?: HyperliquidExchangeSignOptions,
): Promise<ApiPerpsExchangeSignature> {
  const typedData = assertHyperliquidExchangeBuildIntegrity(build, options);

  return signVerifiedHyperliquidTypedData(network, privateKey, typedData);
}

export async function signHyperliquidExchangePayload(
  network: ApiNetwork,
  privateKey: string,
  payload: ApiPerpsExchangeActionPayload,
  options?: HyperliquidExchangeSignOptions,
): Promise<ApiPerpsSignedExchangeAction> {
  const typedData = assertHyperliquidExchangeBuildIntegrity(payload, options);

  return {
    action: payload.action,
    nonce: payload.nonce,
    signature: await signVerifiedHyperliquidTypedData(network, privateKey, typedData),
  };
}

export async function signHyperliquidWithdrawPermit(
  network: ApiNetwork,
  privateKey: string,
  withdraw: {
    action: Record<string, unknown>;
    nonce: number;
    permitData: ApiPerpsPermitData;
  },
  expectedWalletRecipient: string,
): Promise<ApiPerpsExchangeSignature> {
  const permitData = assertHyperliquidWithdrawPermitIntegrity(withdraw, expectedWalletRecipient);

  const signature = await signEip712WithPrivateKey(network, privateKey, {
    domain: permitData.domain,
    types: permitData.types as Record<string, Array<{ name: string; type: string }>>,
    message: permitData.values,
  });

  return parsePermitSignature(signature);
}

async function buildSignedPerpsCctpBatchCalls(
  network: ApiNetwork,
  privateKey: string,
  from: string,
  deposit: ApiPerpsCctpDeposit,
): Promise<EvmMetaTransaction[]> {
  const permitData = deposit.permitData;

  const permitSignature = await signEip712WithPrivateKey(network, privateKey, {
    domain: permitData.domain,
    types: permitData.types as Record<string, Array<{ name: string; type: string }>>,
    message: permitData.values,
  });

  const cctpTx = buildPerpsCctpDepositTx({
    from,
    deposit,
    permitSignature: parsePermitSignature(permitSignature),
  });

  return [evmTxToMetaTransaction(cctpTx)];
}

export async function buildPerpsCctpDepositTransferWithPrivateKey(
  accountId: string,
  deposit: ApiPerpsCctpDeposit,
  privateKey: string,
): Promise<ApiBuildPerpsCctpDepositTransferResult | { error: ApiAnyDisplayError }> {
  const chain = PERPS_CCTP_DEPOSIT_CHAIN;
  const { network } = parseAccountId(accountId);

  try {
    const { address } = await fetchEvmWallet(accountId, chain);

    if (!deposit.requiresPermitSignature || !deposit.permitData) {
      return { error: ApiTransactionError.UnsuccesfulTransfer };
    }

    assertPerpsCctpDepositIntegrity(deposit, address, deposit.amountUsdc);
    const calls = await buildSignedPerpsCctpBatchCalls(network, privateKey, address, deposit);
    const validationError = validateEvmSwapCalls(calls, getPerpsCctpAllowedTargets());

    if (validationError) {
      return { error: validationError };
    }

    const feeResult = await estimateBatchUserOpFee(chain, network, address, calls);

    if ('error' in feeResult) {
      return feeResult;
    }

    return {
      chain,
      calls: serializeEvmSwapCalls(calls),
    };
  } catch (err) {
    logDebugError(`evm:${chain}:buildPerpsCctpDepositTransferWithPrivateKey`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

export async function submitPerpsCctpDepositTransfer(
  options: ApiSubmitPerpsCctpDepositTransferOptions,
): Promise<ApiSubmitPerpsCctpDepositTransferResult> {
  const {
    accountId,
    enclaveToken,
    deposit,
    calls,
    privateKey: presetPrivateKey,
  } = options;
  const chain = PERPS_CCTP_DEPOSIT_CHAIN;
  const { network } = parseAccountId(accountId);

  try {
    const { address } = await fetchEvmWallet(accountId, chain);
    const account = await fetchStoredChainAccount(accountId, chain);

    if (account.type === 'ledger' || account.type === 'view') {
      return { error: ApiTransactionError.UnsuccesfulTransfer };
    }

    let privateKey = presetPrivateKey;

    if (!privateKey) {
      privateKey = await fetchPrivateKeyString(chain, accountId, enclaveToken, account);

      if (!privateKey) {
        return { error: ApiCommonError.InvalidPassword };
      }
    }

    assertPerpsCctpDepositIntegrity(deposit, address, deposit.amountUsdc);

    if (!calls?.length) {
      return { error: ApiTransactionError.UnsuccesfulTransfer };
    }

    const metaCalls: EvmMetaTransaction[] = calls.map(({ to, value, data }) => ({
      to,
      value: BigInt(value || '0'),
      data: data ?? '0x',
    }));
    const validationError = validateEvmSwapCalls(metaCalls, getPerpsCctpAllowedTargets());

    if (validationError) {
      return { error: validationError };
    }

    const result = await submitBatchUserOp(chain, network, address, privateKey, metaCalls);

    return 'error' in result ? result : { txHash: result.txHash };
  } catch (err) {
    logDebugError(`evm:${chain}:submitPerpsCctpDepositTransfer`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

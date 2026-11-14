import type { ApiNetwork, EVMChain } from '../../../types';
import type { PimlicoEip7702Auth } from './pimlico';
import type { EvmMetaTransaction } from './types';
import type { UserOperationV07Data } from './userOperation';

import { callBackendPost } from '../../../common/backend';

export type EvmGaslessEstimateResult = {
  userOperation: UserOperationV07Data;
  maxCost: string;
  exchangeRate: string;
  paymaster: string;
  gasTokenAddress: string;
  chainId: string;
};

export type EvmGaslessSendUserOperation = UserOperationV07Data & {
  signature: string;
  eip7702Auth?: PimlicoEip7702Auth | null;
};

export type EvmGaslessSendResult = {
  userOpHash: string;
  success: boolean;
  txHash?: string;
  actualGasCost?: string;
};

function serializeEvmMetaTransactions(calls: EvmMetaTransaction[]) {
  return calls.map(({ to, value = 0n, data = '0x' }) => ({
    to,
    value: value.toString(),
    data,
  }));
}

export function estimateEvmGaslessBatch(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
  calls: EvmMetaTransaction[],
  gasToken: string,
  eip7702Auth?: PimlicoEip7702Auth,
): Promise<EvmGaslessEstimateResult> {
  return callBackendPost('/diesel/evm/estimate', {
    chain,
    network,
    address,
    gasToken,
    calls: serializeEvmMetaTransactions(calls),
    eip7702Auth,
  });
}

export function sendEvmGaslessBatch(
  chain: EVMChain,
  network: ApiNetwork,
  userOperation: EvmGaslessSendUserOperation,
): Promise<EvmGaslessSendResult> {
  return callBackendPost('/diesel/evm/send', {
    chain,
    network,
    userOperation,
  });
}

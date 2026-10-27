import type {
  ApiChain,
  ApiEthenaStakingState,
  ApiForeignStaking,
  ApiForeignStakingResponse,
  ApiForeignUnstakeDraft,
  ApiJettonStakingState,
  ApiStakingHistory,
  ApiStakingState,
} from '../types';
import { ApiCommonError } from '../types';

import { parseAccountId } from '../../util/account';
import { areDeepEqual } from '../../util/areDeepEqual';
import { bigintDivideToNumber } from '../../util/bigint';
import { fromDecimal } from '../../util/decimals';
import { logDebugError } from '../../util/logs';
import { getChainBySlug, getNativeToken } from '../../util/tokens';
import chains from '../chains';
import { doesAccountHaveChain, fetchStoredAccount, fetchStoredWallet } from '../common/accounts';
import { callBackendGet } from '../common/backend';
import { setStakingCommonCache } from '../common/cache';
import { ApiBaseError } from '../errors';
import {
  buildForeignUnstakeTransactionForProvider,
  checkForeignUnstakeTransactionDraft,
  submitForeignUnstakeTransaction,
} from './foreignStakingUnstakeBuilders';
import { publishSignedMfaRequest, registerMfaConfirmationHandler } from './mfa';
import { pollForeignStakingPromotion } from './polling';
import { createLocalTransactions } from './transfer';

export function initStaking() {}

/** The chain a staking state belongs to, and its staking implementation, both keyed by the state's token. */
function resolveStaking(state: ApiStakingState) {
  const chain = getChainBySlug(state.tokenSlug);
  const staking = chains[chain]?.staking;
  if (!staking) {
    throw new Error(`Staking is not supported for ${chain}`);
  }

  return { chain, staking };
}

/**
 * The account's staking chain, for the operations that have no staking state to take it from. The registry
 * scan is unambiguous only while a single chain supports staking.
 */
async function findStakingChain(accountId: string): Promise<ApiChain | undefined> {
  const account = await fetchStoredAccount(accountId);
  return (Object.keys(chains) as ApiChain[]).find(
    (chain) => chains[chain].staking && doesAccountHaveChain(account, chain),
  );
}

export async function checkStakeDraft(accountId: string, amount: bigint, state: ApiStakingState) {
  return resolveStaking(state).staking.checkStakeDraft(accountId, amount, state);
}

export async function checkUnstakeDraft(accountId: string, amount: bigint, state: ApiStakingState) {
  return resolveStaking(state).staking.checkUnstakeDraft(accountId, amount, state);
}

export async function submitStake(
  accountId: string,
  enclaveToken: string | undefined,
  amount: bigint,
  state: ApiStakingState,
  realFee?: bigint,
) {
  const { chain, staking } = resolveStaking(state);
  const { address: fromAddress } = await fetchStoredWallet(accountId, chain);

  const result = await staking.submitStake(accountId, enclaveToken, amount, state);

  if ('error' in result) {
    return result;
  }

  if (result.mfaRequest) {
    const mfaResult = await publishSignedMfaRequest(accountId, chain, result.mfaRequest);
    registerMfaConfirmationHandler(mfaResult.mfaRequestHash, () => staking.poll(accountId));
    return mfaResult;
  }

  if (!result.txId) {
    return { error: ApiCommonError.Unexpected };
  }

  const [localActivity] = createLocalTransactions(accountId, chain, [{
    id: result.txId,
    amount,
    fromAddress,
    fee: realFee ?? 0n,
    type: 'stake',
    slug: state.tokenSlug,
    ...result.localActivityParams,
  }]);
  staking.poll(accountId);

  return {
    activityId: localActivity.id,
  };
}

export async function submitUnstake(
  accountId: string,
  enclaveToken: string | undefined,
  tokenAmount: bigint,
  state: ApiStakingState,
  realFee?: bigint,
) {
  const { chain, staking } = resolveStaking(state);
  const { address: fromAddress } = await fetchStoredWallet(accountId, chain);

  const result = await staking.submitUnstake(accountId, enclaveToken, tokenAmount, state);
  if ('error' in result) {
    return result;
  }

  if (result.mfaRequest) {
    const mfaResult = await publishSignedMfaRequest(accountId, chain, result.mfaRequest);
    registerMfaConfirmationHandler(mfaResult.mfaRequestHash, () => staking.poll(accountId));
    return mfaResult;
  }

  if (!result.txId) {
    return { error: ApiCommonError.Unexpected };
  }

  const [localActivity] = createLocalTransactions(accountId, chain, [{
    id: result.txId,
    amount: 0n, // Always 0, because all the gas send for the unstaking is in the fee
    fromAddress,
    fee: realFee ?? 0n,
    type: 'unstakeRequest',
    ...result.localActivityParams,
  }]);
  staking.poll(accountId);

  return {
    activityId: localActivity.id,
  };
}

export async function getStakingHistory(accountId: string): Promise<ApiStakingHistory> {
  const chain = await findStakingChain(accountId);
  if (!chain) return [];
  const { address } = await fetchStoredWallet(accountId, chain);
  return callBackendGet(`/staking/profits/${address}`);
}

export async function fetchStakingForeign(accountId: string): Promise<ApiForeignStaking> {
  const account = await fetchStoredAccount(accountId);
  const address = account.byChain.ton?.address;
  if (!address || parseAccountId(accountId).network !== 'mainnet') return [];

  const response = await callBackendGet<ApiForeignStakingResponse>('/staking/foreign', { address, live: '1' });

  return response.map((entry) => ({
    chain: entry.chain,
    providers: entry.providers.map((provider) => ({
      name: provider.name,
      provider: provider.provider,
      amount: fromDecimal(provider.amount),
      amountNative: fromDecimal(provider.amountNative),
      apy: provider.apy,
      unstake: {
        ...provider.unstake,
        instantAvailable: provider.unstake.instantAvailable !== undefined
          ? fromDecimal(provider.unstake.instantAvailable)
          : undefined,
      },
    })),
  }));
}

async function resolveForeignUnstakeTransaction(accountId: string, chain: ApiChain, providerName: string) {
  const account = await fetchStoredAccount(accountId);
  if (!doesAccountHaveChain(account, chain) || account.type === 'view'
    || parseAccountId(accountId).network !== 'mainnet') {
    throw new Error('Foreign unstaking is not available for this account');
  }

  const entry = (await fetchStakingForeign(accountId)).find((item) => item.chain === chain);
  if (!entry) return undefined;

  return buildForeignUnstakeTransactionForProvider(accountId, entry, providerName);
}

export async function checkForeignUnstakeDraft(accountId: string, chain: ApiChain, providerName: string) {
  const transaction = await resolveForeignUnstakeTransaction(accountId, chain, providerName);
  if (!transaction) throw new ApiBaseError(ApiCommonError.Unexpected, ApiCommonError.Unexpected);

  const result = await checkForeignUnstakeTransactionDraft(accountId, transaction);
  if ('error' in result) throw new ApiBaseError(result.error, result.error);
  const attachedAmount = transaction.messages.reduce((sum, { amount }) => sum + amount, 0n);
  const fee = result.emulation.networkFee;
  return {
    amountNative: transaction.amountNative,
    transfers: transaction.transfers,
    fee,
    realFee: result.emulation.isFallback ? attachedAmount + fee : result.emulation.realFee,
    isInstant: transaction.isInstant,
  } satisfies ApiForeignUnstakeDraft;
}

export async function submitForeignUnstake(
  accountId: string,
  chain: ApiChain,
  providerName: string,
  draft: ApiForeignUnstakeDraft,
  enclaveToken?: string,
) {
  const transaction = await resolveForeignUnstakeTransaction(accountId, chain, providerName);
  if (!transaction || transaction.amountNative !== draft.amountNative
    || !areDeepEqual(transaction.transfers, draft.transfers)) {
    return { error: ApiCommonError.Unexpected };
  }

  const result = await submitForeignUnstakeTransaction(accountId, transaction, enclaveToken);
  if ('error' in result) return { error: result.error };
  const { address: fromAddress } = await fetchStoredWallet(accountId, chain);
  const createActivities = (txHash: string) => createLocalTransactions(accountId, chain, draft.transfers.map(
    ({ toAddress }) => ({
      id: txHash,
      externalMsgHashNorm: txHash,
      type: 'unstakeRequest',
      amount: 0n,
      fromAddress,
      toAddress,
      slug: getNativeToken(chain).slug,
      fee: bigintDivideToNumber(draft.realFee, draft.transfers.length),
    }),
  ));
  if ('mfaRequest' in result) {
    const { mfaRequestHash } = await publishSignedMfaRequest(accountId, chain, result.mfaRequest);
    registerMfaConfirmationHandler(mfaRequestHash, (txHash) => {
      createActivities(txHash);
      pollForeignStakingPromotion();
    });
    return { mfaRequestHash };
  }
  const activities = createActivities(result.msgHashNormalized);
  pollForeignStakingPromotion();
  return { activityIds: activities.map(({ id }) => id) };
}

export async function tryUpdateStakingCommonData() {
  for (const chain of Object.keys(chains) as ApiChain[]) {
    const staking = chains[chain].staking;
    if (!staking) continue;

    try {
      setStakingCommonCache(chain, await staking.getCommonData());
    } catch (err) {
      logDebugError('tryUpdateStakingCommonData', err);
    }
  }
}

export async function submitStakingClaimOrUnlock(
  accountId: string,
  enclaveToken: string | undefined,
  state: ApiJettonStakingState | ApiEthenaStakingState,
  realFee?: bigint,
) {
  const { chain, staking } = resolveStaking(state);
  const { address: walletAddress } = await fetchStoredWallet(accountId, chain);

  const result = state.type === 'ethena'
    ? await staking.submitUnstakeEthenaLocked(accountId, enclaveToken, state)
    : await staking.submitTokenStakingClaim(accountId, enclaveToken, state);

  if ('error' in result) {
    return result;
  }

  if (result.mfaRequest) {
    const mfaResult = await publishSignedMfaRequest(accountId, chain, result.mfaRequest);
    registerMfaConfirmationHandler(mfaResult.mfaRequestHash, () => staking.poll(accountId));
    return mfaResult;
  }

  if (!result.txId) {
    return { error: ApiCommonError.Unexpected };
  }

  const [localActivity] = createLocalTransactions(accountId, chain, [{
    id: result.txId,
    fromAddress: walletAddress,
    fee: realFee ?? 0n,
    ...result.localActivityParams,
  }]);
  staking.poll(accountId);

  return {
    activityId: localActivity.id,
  };
}

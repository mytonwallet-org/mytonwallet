import { Interface, keccak256, Transaction } from 'ethers';

import type { Storage } from '../../../storages/types';
import type { ApiNetwork, ApiTokenWithPrice, EVMChain, OnApiUpdate } from '../../../types';
import type {
  ApiBuildOnchainSwapTransferOptions,
  ApiSubmitOnchainSwapTransferOptions,
  ApiSubmitOnchainSwapTransferResult,
} from '../../../types/swap';
import type { VtIntent, VtPlan, VtTransaction } from './types';
import { EvmSmartAccountError } from '../../../types';

import { fromDecimal } from '../../../../util/decimals';
import { logDebugError } from '../../../../util/logs';
import { findNativeToken, getChainBySlug } from '../../../../util/tokens';
import { fetchEvmWallet } from '../util/account';
import { getEvmProvider } from '../util/client';
import { fetchStoredChainAccount } from '../../../common/accounts';
import { callBackendPost } from '../../../common/backend';
import { patchSwapItem } from '../../../common/swap';
import { getSwapExecutionQuote } from '../../../common/swapExecutionQuote';
import { getCurrentStorage, storage } from '../../../storages';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from '../auth';
import { estimateBatchUserOpFee, submitBatchUserOp } from '../smartAccount/batch';
import { validateVtPlan, VT_CHAINS, VT_NATIVE_TOKEN } from './validation';

const TOKEN = new Interface([
  'function allowance(address owner,address spender) view returns(uint256)',
  'function approve(address spender,uint256 amount) returns(bool)',
]);
type Journal = {
  intent: VtIntent;
  plan: VtPlan;
  gasSpent: string;
  transactions: { kind: 'reset' | 'approval' | 'bridge'; raw: string; hash: string }[];
  /** Source hash of an approval + bridge account batch; such a swap is never submitted again */
  batchHash?: string;
};
const LOCKS = new Set<string>();
const JOURNAL_WRITES = new WeakMap<Storage, Promise<void>>();

export async function buildVtTransfer(
  chain: EVMChain,
  network: ApiNetwork,
  options: ApiBuildOnchainSwapTransferOptions,
) {
  if (network !== 'mainnet') throw new Error('VT testnet is unsupported');
  const { request, accountId, swapId } = options;
  const executionQuote = getSwapExecutionQuote(accountId, request);
  const destinationChain = executionQuote.destinationToken.chain as EVMChain;
  if (!destinationChain || !VT_CHAINS[destinationChain]) throw new Error('Missing VT destination chain');
  const [{ address: owner }, { address: recipient }] = await Promise.all([
    fetchEvmWallet(accountId, chain),
    fetchEvmWallet(accountId, destinationChain),
  ]);
  if (
    request.fromAddress.toLowerCase() !== owner.toLowerCase()
    || request.toAddress?.toLowerCase() !== recipient.toLowerCase()
  ) {
    throw new Error('VT account intent mismatch');
  }
  const sourceNative = findNativeToken(chain)!;
  const sourceToken = executionQuote.sourceToken;
  const destinationToken = executionQuote.destinationToken;
  if (
    !sourceToken
    || !destinationToken
    || getChainBySlug(sourceToken.slug) !== chain
    || getChainBySlug(destinationToken.slug) !== destinationChain
    || !request.toMinAmount
    || request.ourFee === undefined
  ) {
    throw new Error('Unknown VT intent token, fee or minimum');
  }
  const source = resolveVtToken(sourceToken, chain);
  const destination = resolveVtToken(destinationToken, destinationChain);
  const estimate = fromDecimal(request.networkFee ?? '0', sourceNative.decimals);
  const budget = fromDecimal(executionQuote.nativeFeeBudget, sourceNative.decimals);
  if (estimate <= 0n || budget < estimate || budget > estimate * 4n) {
    throw new Error('Invalid VT execution fee budget');
  }
  const intent: VtIntent = {
    sourceChain: chain,
    destinationChain,
    owner,
    recipient,
    sourceToken: source.address,
    destinationToken: destination.address,
    sourceDecimals: source.decimals,
    destinationDecimals: destination.decimals,
    amount: String(fromDecimal(request.fromAmount, source.decimals)),
    minimum: String(fromDecimal(request.toMinAmount, destination.decimals)),
    feeAmount: String(fromDecimal(request.ourFee, source.decimals)),
    nativeFeeBudget: String(budget),
  };
  const plan = JSON.parse(options.transaction!) as VtPlan;
  validateVtPlan(plan, intent);
  await assertWrapperCode(chain, network);
  const key = `${accountId}:${swapId}`;
  await writeJournal(key, { intent, plan, transactions: [], gasSpent: '0' }, true);
  return { id: swapId, chain, transaction: options.transaction, needsBatch: false };
}

/** Persists signed transactions before broadcast; retry only rebroadcasts the identical transaction */
export async function submitVtTransfer(
  chain: EVMChain,
  network: ApiNetwork,
  options: ApiSubmitOnchainSwapTransferOptions,
  historyAddress: string,
  onUpdate: OnApiUpdate,
): Promise<ApiSubmitOnchainSwapTransferResult> {
  const { accountId, swapId, enclaveToken, authToken, localSwap } = options;
  const lock = `${historyAddress}:${accountId}:${chain}`;
  if (LOCKS.has(lock)) return { error: 'VT transfer is already being submitted' };
  LOCKS.add(lock);
  try {
    if (network !== 'mainnet') throw new Error('VT testnet is unsupported');
    const journal = (await readJournals())[`${accountId}:${swapId}`];
    const { address } = await fetchEvmWallet(accountId, chain);
    if (!journal || journal.intent.owner.toLowerCase() !== address.toLowerCase()) {
      throw new Error('VT intent not found');
    }
    if (journal.batchHash) return { activityId: localSwap.id, submittedHashes: [journal.batchHash] };
    await assertWrapperCode(chain, network);
    const account = await fetchStoredChainAccount(accountId, chain);
    if (account.type === 'ledger' || account.type === 'view') {
      throw new Error('Unsupported VT signing account');
    }
    const privateKey = await fetchPrivateKeyString(chain, accountId, enclaveToken, account);
    if (!privateKey) throw new Error('Unable to unlock VT signing account');
    const provider = getEvmProvider(network, chain);
    const signer = getSignerFromPrivateKey(network, privateKey).connect(provider);
    async function persist() {
      await writeJournal(`${accountId}:${swapId}`, journal);
    }
    async function recordBridge(hash: string) {
      onUpdate({
        type: 'newLocalActivities',
        accountId,
        activities: [
          {
            ...localSwap,
            externalMsgHashNorm: hash,
            hashes: [...new Set([...localSwap.hashes, hash])],
            layerzero: { quoteId: journal.plan.quote.id },
            transactionIds: { outgoing: { hash, chain } },
          },
        ],
      });
      await patchSwapItem({ address: historyAddress, swapId, authToken, msgHash: hash, msgHashNormalized: hash });
    }
    async function refresh() {
      const refreshed = await callBackendPost<VtPlan>(
        `/swap/layerzero/${historyAddress}/${swapId}/refresh`,
        {},
        { authToken },
      );
      validateVtPlan(refreshed, journal.intent);
      journal.plan = refreshed;
      await persist();
    }
    /** Approval and bridge as one atomic account batch. Undefined when the chain has no batch support or the
     * batch exceeds the confirmed fee budget: the swap then uses separate transactions */
    const submitBatch = async (approvals: VtTransaction[]) => {
      // No receipt wait precedes a batched bridge, so the confirmed quote is used unless it is about to expire
      if (journal.plan.expiresAt < Date.now() + 15000) await refresh();
      const bridge = validateVtPlan(journal.plan, journal.intent);
      const calls = [...approvals, bridge].map(({ to, value, data }) => ({ to, value: BigInt(value ?? '0'), data }));
      const maxCostLimit = BigInt(journal.intent.nativeFeeBudget) - BigInt(journal.gasSpent)
        - BigInt(bridge.value ?? '0');
      const estimate = await estimateBatchUserOpFee(chain, network, address, calls);
      if ('error' in estimate || estimate.maxCost > maxCostLimit) {
        return undefined;
      }
      const result = await submitBatchUserOp(
        chain, network, address, privateKey, calls, { needsGasless: false, maxCostLimit },
      );
      if ('error' in result) {
        if (result.error === EvmSmartAccountError.UserOperationMismatch) {
          throw new Error('VT fee increased; a fresh confirmation is required');
        }
        throw new Error(`VT batch failed: ${result.error}`);
      }
      journal.batchHash = result.txHash;
      await persist();
      await recordBridge(result.txHash);
      return result.txHash;
    };
    async function send(kind: 'reset' | 'approval' | 'bridge', transaction: VtTransaction) {
      let entry = journal.transactions.find((item) => item.kind === kind);
      if (!entry) {
        const gas = ((await provider.estimateGas(transaction)) * 3n) / 2n;
        const feeData = await provider.getFeeData();
        const gasPrice = feeData.maxFeePerGas ?? feeData.gasPrice;
        if (!gasPrice) throw new Error('Missing VT gas price');
        const value = BigInt(transaction.value ?? '0');
        const nativeInput
          = kind === 'bridge' && journal.intent.sourceToken === VT_NATIVE_TOKEN
            ? BigInt(journal.intent.amount)
            : 0n;
        const reserved = gas * gasPrice + value - nativeInput;
        if (BigInt(journal.gasSpent) + reserved > BigInt(journal.intent.nativeFeeBudget)) {
          throw new Error('VT fee increased; a fresh confirmation is required');
        }
        const populated = await signer.populateTransaction({
          ...transaction,
          value,
          gasLimit: gas,
          ...(feeData.maxFeePerGas
            ? { maxFeePerGas: gasPrice, maxPriorityFeePerGas: feeData.maxPriorityFeePerGas }
            : { gasPrice }),
        });
        const raw = await signer.signTransaction(populated);
        entry = { kind, raw, hash: Transaction.from(raw).hash! };
        journal.transactions.push(entry);
        journal.gasSpent = String(BigInt(journal.gasSpent) + reserved);
        await persist();
      }
      const saved = Transaction.from(entry.raw);
      if (
        saved.hash !== entry.hash
        || saved.from?.toLowerCase() !== address.toLowerCase()
        || saved.chainId !== BigInt(VT_CHAINS[chain].chainId)
        || saved.to?.toLowerCase() !== transaction.to.toLowerCase()
        || saved.data !== transaction.data
        || saved.value !== BigInt(transaction.value ?? '0')
      ) {
        throw new Error('VT journal transaction mismatch');
      }
      // Save the source identity before broadcast; a lost response can never cause a new principal transfer
      if (kind === 'bridge') await recordBridge(entry.hash);
      const signed = entry;
      const broadcast = async () => {
        if (!(await provider.getTransaction(signed.hash))) await provider.broadcastTransaction(signed.raw);
      };
      if (kind === 'bridge') {
        // A failed broadcast may still have sent the principal; report the signed bridge pending, since an
        // error would let the user confirm again and sign a new bridge under a new swap
        await broadcast().catch((error: unknown) => logDebugError('submitVtTransfer:broadcast', error));
        return entry.hash;
      }
      await broadcast();
      const receipt = await provider.waitForTransaction(entry.hash, 1, 120000);
      if (!receipt || receipt.status !== 1) throw new Error('VT approval pending or reverted');
      return entry.hash;
    }
    const signedBridge = journal.transactions.find((entry) => entry.kind === 'bridge');
    if (!signedBridge) {
      const { intent } = journal;
      if (intent.sourceToken !== VT_NATIVE_TOKEN) {
        const readAllowance = async () => {
          const data = await provider.call({
            to: intent.sourceToken,
            data: TOKEN.encodeFunctionData('allowance', [address, VT_CHAINS[chain].delegate]),
          });
          return TOKEN.decodeFunctionResult('allowance', data)[0] as bigint;
        };
        const allowance = await readAllowance();
        if (allowance < BigInt(intent.amount)) {
          const approval = (amount: string): VtTransaction => ({
            from: address,
            to: intent.sourceToken,
            chainId: VT_CHAINS[chain].chainId,
            value: '0',
            data: TOKEN.encodeFunctionData('approve', [VT_CHAINS[chain].delegate, amount]),
          });
          const batchHash = await submitBatch([...(allowance > 0n ? [approval('0')] : []), approval(intent.amount)]);
          if (batchHash) return { activityId: localSwap.id, submittedHashes: [batchHash] };
          if (allowance > 0n) {
            await send('reset', approval('0'));
            if ((await readAllowance()) !== 0n) throw new Error('VT allowance reset failed');
          }
          await send('approval', approval(intent.amount));
          if ((await readAllowance()) < BigInt(intent.amount)) {
            throw new Error('VT approval did not grant the required allowance');
          }
        }
      }
      await refresh();
    }
    const expected = validateVtPlan(
      signedBridge ? { ...journal.plan, expiresAt: Date.now() + 60000 } : journal.plan,
      journal.intent,
    );
    const hash = await send('bridge', expected);
    return { activityId: localSwap.id, submittedHashes: [hash] };
  } catch (error) {
    // Signed entries remain recoverable after transport errors and are never replaced with a fresh send
    return { error: error instanceof Error ? error.message : 'VT transfer failed' };
  } finally {
    LOCKS.delete(lock);
  }
}

async function assertWrapperCode(chain: EVMChain, network: ApiNetwork) {
  const provider = getEvmProvider(network, chain);
  const [code, delegateCode] = await Promise.all([
    provider.getCode(VT_CHAINS[chain].wrapper),
    provider.getCode(VT_CHAINS[chain].delegate),
  ]);
  if (keccak256(delegateCode) !== VT_CHAINS[chain].delegateCodeHash) {
    throw new Error('Unrecognized VT delegate deployment');
  }
  if (keccak256(code) !== VT_CHAINS[chain].wrapperCodeHash) {
    throw new Error('Unrecognized VT wrapper deployment');
  }
}

async function readJournals(): Promise<Record<string, Journal>> {
  return (await storage.getItem('layerzeroSwaps')) ?? {};
}

function resolveVtToken(token: ApiTokenWithPrice, chain: EVMChain) {
  const config = VT_CHAINS[chain];
  const isNative = token.slug === findNativeToken(chain)!.slug;
  return isNative && config.nativeGasToken
    ? { address: config.nativeGasToken, decimals: config.nativeGasTokenDecimals! }
    : { address: isNative ? VT_NATIVE_TOKEN : token.tokenAddress!, decimals: token.decimals };
}

async function writeJournal(key: string, journal: Journal, shouldCreate = false) {
  const store = getCurrentStorage();
  const previous = JOURNAL_WRITES.get(store) ?? Promise.resolve();
  const write = previous
    .catch(() => undefined)
    .then(async () => {
      function update(stored: Record<string, Journal> | undefined) {
        const current = stored ?? {};
        if (shouldCreate && current[key]) {
          throw new Error('VT swap already built; resume its stored execution');
        }
        return { ...current, [key]: journal };
      }
      if (store.mutateItem) {
        await store.mutateItem('layerzeroSwaps', update);
      } else {
        await store.setItem('layerzeroSwaps', update(await store.getItem('layerzeroSwaps')));
      }
    });
  JOURNAL_WRITES.set(store, write);
  return write;
}

import { Contract, Interface } from 'ethers';

import type { ApiNetwork, ApiRevokeWalletPermissionOptions, ApiWalletPermission, EVMChain } from '../../types';
import type { ApiAnyDisplayError } from '../../types/errors';
import type { ZerionFungibleInfo, ZerionTransaction, ZerionTransactionsResponse } from './types';
import { ApiCommonError, ApiTransactionError } from '../../types';

import { parseAccountId } from '../../../util/account';
import { fetchJson } from '../../../util/fetch';
import { logDebugError } from '../../../util/logs';
import { isUnlimitedEvmAllowance } from './util/allowance';
import { collectZerionApprovals, resolveZerionActMetadata } from './util/approvals';
import { getEvmProvider } from './util/client';
import { updateTokensMetadataByAddress } from './util/metadata';
import { collectZerionTxTokenAddresses, getZerionFungibleImplementation } from './util/tokens';
import { fetchStoredChainAccount } from '../../common/accounts';
import { getKnownAddressInfo } from '../../common/addresses';
import { buildTokenSlug, getTokenBySlug } from '../../common/tokens';
import { normalizeAddress } from './address';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import {
  EVM_DALEGATOR_ADDRESSES,
  getEvmApiUrl,
  getZerionChainByApiChain,
  UNISWAP_PERMIT2_ADDRESS,
  ZERO_ADDRESS,
} from './constants';
import { estimateEvmFee } from './transfer';
import { getWalletBalance } from './wallet';

const ERC20_APPROVE_ABI = ['function approve(address spender, uint256 amount) returns (bool)'];
const PERMIT2_ALLOWANCE_ABI = [
  'function allowance(address owner, address token, address spender) '
  + 'view returns (uint160 amount, uint48 expiration, uint48 nonce)',
  'function approve(address token, address spender, uint160 amount, uint48 expiration)',
];
const erc20ApproveInterface = new Interface(ERC20_APPROVE_ABI);
const permit2AllowanceInterface = new Interface(PERMIT2_ALLOWANCE_ABI);

const EIP7702_DELEGATION_PREFIX = '0xef0100';

const PAGE_SIZE = 100;
const MAX_PAGES = 100;

type ApprovalCandidate = {
  tokenAddress: string;
  fungibleInfo: ZerionFungibleInfo;
  spenderAddress: string;
  spenderName?: string;
  spenderIcon?: string;
};

type DelegationCandidate = {
  delegateAddress: string;
  delegateName?: string;
  delegateIcon?: string;
};

export async function getErc20Allowance(
  chain: EVMChain,
  network: ApiNetwork,
  owner: string,
  tokenAddress: string,
  spender: string,
): Promise<bigint> {
  try {
    const contract = new Contract(
      tokenAddress,
      ['function allowance(address owner, address spender) view returns (uint256)'],
      getEvmProvider(network, chain),
    );
    const result = await contract.allowance(owner, spender);
    return BigInt(result.toString());
  } catch {
    return 0n;
  }
}

export async function getPermit2Allowance(
  chain: EVMChain,
  network: ApiNetwork,
  owner: string,
  tokenAddress: string,
  spender: string,
): Promise<bigint> {
  try {
    const contract = new Contract(
      UNISWAP_PERMIT2_ADDRESS,
      PERMIT2_ALLOWANCE_ABI,
      getEvmProvider(network, chain),
    );
    const result = await contract.allowance(owner, tokenAddress, spender);
    const amount = result?.amount ?? result?.[0] ?? 0;
    return BigInt(amount.toString());
  } catch {
    return 0n;
  }
}

export async function getEvmDelegationAddress(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
): Promise<string | undefined> {
  try {
    const code = await getEvmProvider(network, chain).getCode(normalizeAddress(address));
    if (!code || code.length <= EIP7702_DELEGATION_PREFIX.length) return undefined;
    if (!code.toLowerCase().startsWith(EIP7702_DELEGATION_PREFIX)) return undefined;

    const delegateHex = code.slice(EIP7702_DELEGATION_PREFIX.length);
    if (delegateHex.length !== 40) return undefined;

    return normalizeAddress(`0x${delegateHex}`);
  } catch {
    return undefined;
  }
}

function collectTradeSpenderCandidates(
  tx: ZerionTransaction,
  zerionChain: string,
  pairs: Map<string, ApprovalCandidate>,
) {
  const tradeLikeActs = tx.attributes.acts?.filter(({ type }) => type === 'trade' || type === 'execute') ?? [];
  if (!tradeLikeActs.length && tx.attributes.operation_type !== 'trade' && tx.attributes.operation_type !== 'execute') {
    return;
  }

  const spenderEntries: Array<{ spenderAddress: string; spenderName?: string; spenderIcon?: string }> = [];

  for (const act of tradeLikeActs) {
    const metadata = act.application_metadata ?? tx.attributes.application_metadata;
    if (!metadata?.contract_address) continue;

    spenderEntries.push({
      spenderAddress: normalizeAddress(metadata.contract_address),
      spenderName: metadata.name,
      spenderIcon: metadata.icon?.url,
    });
  }

  if (!spenderEntries.length) {
    const metadata = tx.attributes.application_metadata;
    if (metadata?.contract_address) {
      spenderEntries.push({
        spenderAddress: normalizeAddress(metadata.contract_address),
        spenderName: metadata.name,
        spenderIcon: metadata.icon?.url,
      });
    }
  }

  if (!spenderEntries.length) return;

  for (const transfer of tx.attributes.transfers) {
    if (!('fungible_info' in transfer) || !transfer.fungible_info || transfer.direction !== 'out') continue;

    const impl = getZerionFungibleImplementation(transfer.fungible_info, zerionChain);
    if (!impl?.address) continue;

    const tokenAddress = normalizeAddress(impl.address);

    for (const { spenderAddress, spenderName, spenderIcon } of spenderEntries) {
      const key = `${tokenAddress}:${spenderAddress}`;
      if (pairs.has(key)) continue;

      pairs.set(key, {
        tokenAddress,
        fungibleInfo: transfer.fungible_info,
        spenderAddress,
        spenderName,
        spenderIcon,
      });
    }
  }
}

function findFungibleInfoForToken(
  pairs: Map<string, ApprovalCandidate>,
  tokenAddress: string,
): ZerionFungibleInfo | undefined {
  for (const candidate of pairs.values()) {
    if (candidate.tokenAddress === tokenAddress) {
      return candidate.fungibleInfo;
    }
  }

  return undefined;
}

async function supplementPermit2Erc20ApprovalCandidates(
  chain: EVMChain,
  network: ApiNetwork,
  owner: string,
  tokenAddresses: Set<string>,
  pairs: Map<string, ApprovalCandidate>,
) {
  const permit2Address = normalizeAddress(UNISWAP_PERMIT2_ADDRESS);

  await Promise.all([...tokenAddresses].map(async (tokenAddress) => {
    const allowance = await getErc20Allowance(chain, network, owner, tokenAddress, permit2Address);
    if (allowance === 0n) return;

    const key = `${tokenAddress}:${permit2Address}`;
    if (pairs.has(key)) return;

    const fungibleInfo = findFungibleInfoForToken(pairs, tokenAddress);
    if (!fungibleInfo) return;

    pairs.set(key, {
      tokenAddress,
      spenderAddress: permit2Address,
      fungibleInfo,
    });
  }));
}

function collectApprovalCandidates(
  tx: ZerionTransaction,
  zerionChain: string,
  pairs: Map<string, ApprovalCandidate>,
) {
  for (const approval of collectZerionApprovals(tx, zerionChain)) {
    const key = `${approval.tokenAddress}:${approval.spenderAddress}`;

    if (!pairs.has(key)) {
      pairs.set(key, approval);
    }
  }
}

function collectDelegationCandidates(
  tx: ZerionTransaction,
  zerionChain: string,
  candidates: Map<string, DelegationCandidate>,
) {
  for (const delegation of tx.attributes.delegations ?? []) {
    if (delegation.chain_id && delegation.chain_id !== zerionChain) continue;

    const delegateAddress = normalizeAddress(delegation.address);
    const metadata = resolveZerionActMetadata(tx, delegation.act_id);
    const key = delegateAddress;

    if (!candidates.has(key)) {
      candidates.set(key, {
        delegateAddress,
        delegateName: metadata?.name,
        delegateIcon: metadata?.icon?.url,
      });
    }
  }
}

type ZerionPermissionCandidates = {
  approvalCandidates: Map<string, ApprovalCandidate>;
  delegationCandidates: Map<string, DelegationCandidate>;
  tokenAddresses: Set<string>;
};

async function fetchZerionPermissionCandidates(
  chain: EVMChain,
  network: ApiNetwork,
  checksumAddress: string,
  zerionChain: string,
): Promise<ZerionPermissionCandidates> {
  const approvalCandidates = new Map<string, ApprovalCandidate>();
  const delegationCandidates = new Map<string, DelegationCandidate>();
  const tokenAddresses = new Set<string>();

  const baseUrl = `${getEvmApiUrl(network)}/v1/wallets/${checksumAddress}/transactions/`;
  let afterCursor: string | undefined;
  let page = 0;

  while (page < MAX_PAGES) {
    const params: Record<string, string> = {
      'filter[chain_ids]': zerionChain,
      'page[size]': String(PAGE_SIZE),
    };
    if (afterCursor) {
      params['page[after]'] = afterCursor;
    }

    const response = await fetchJson<ZerionTransactionsResponse>(baseUrl, params);

    for (const tx of response.data) {
      collectApprovalCandidates(tx, zerionChain, approvalCandidates);
      collectDelegationCandidates(tx, zerionChain, delegationCandidates);
      collectZerionTxTokenAddresses(tx, zerionChain, tokenAddresses);
      collectTradeSpenderCandidates(tx, zerionChain, approvalCandidates);
    }

    page++;

    if (response.data.length < PAGE_SIZE) break;

    // Extract cursor from the next link to avoid using a third-party URL directly
    const nextLink = response.links.next;
    if (!nextLink) break;

    try {
      afterCursor = new URL(nextLink).searchParams.get('page[after]') ?? undefined;
    } catch {
      break;
    }
    if (!afterCursor) break;
  }

  return { approvalCandidates, delegationCandidates, tokenAddresses };
}

async function buildApprovalPermissions(
  chain: EVMChain,
  network: ApiNetwork,
  checksumAddress: string,
  zerionChain: string,
  approvalCandidates: Map<string, ApprovalCandidate>,
): Promise<ApiWalletPermission[]> {
  if (!approvalCandidates.size) return [];

  const tokenAddresses = [...new Set([...approvalCandidates.values()].map((pair) => pair.tokenAddress))];
  await updateTokensMetadataByAddress(network, chain, tokenAddresses);

  const results = await Promise.all(
    [...approvalCandidates.values()].map(async (pair) => {
      const {
        tokenAddress,
        fungibleInfo,
        spenderAddress,
        spenderName,
        spenderIcon,
      } = pair;
      const impl = getZerionFungibleImplementation(fungibleInfo, zerionChain);
      if (!impl?.address) return undefined;

      let allowance = await getErc20Allowance(chain, network, checksumAddress, tokenAddress, spenderAddress);
      if (allowance === 0n) {
        allowance = await getPermit2Allowance(chain, network, checksumAddress, tokenAddress, spenderAddress);
      }
      if (allowance === 0n) return undefined;

      const isUnlimited = isUnlimitedEvmAllowance(allowance);
      const knownName = getKnownAddressInfo(spenderAddress)?.name;

      const tokenSlug = buildTokenSlug(chain, tokenAddress);
      const cachedToken = getTokenBySlug(tokenSlug);

      return {
        kind: 'approval',
        chain,
        tokenAddress,
        tokenSlug,
        tokenName: cachedToken?.name ?? fungibleInfo.name,
        tokenSymbol: cachedToken?.symbol ?? fungibleInfo.symbol,
        tokenDecimals: impl.decimals,
        tokenImage: cachedToken?.image ?? fungibleInfo.icon?.url ?? undefined,
        spenderAddress,
        spenderName: knownName ?? (spenderAddress === UNISWAP_PERMIT2_ADDRESS ? 'Permit2' : spenderName),
        spenderIcon,
        allowance: allowance.toString(),
        isUnlimited,
      } satisfies ApiWalletPermission;
    }),
  );

  return results.filter(Boolean) as ApiWalletPermission[];
}

function buildDelegationPermission(
  chain: EVMChain,
  activeDelegateAddress: string,
  delegationCandidates: Map<string, DelegationCandidate>,
): ApiWalletPermission | undefined {
  const candidate = delegationCandidates.get(activeDelegateAddress);

  const knownName = EVM_DALEGATOR_ADDRESSES[activeDelegateAddress];

  return {
    kind: 'delegation',
    chain,
    delegateAddress: activeDelegateAddress,
    delegateName: knownName ?? candidate?.delegateName,
    delegateIcon: candidate?.delegateIcon,
  } satisfies ApiWalletPermission;
}

export async function fetchEvmWalletPermissions(
  chain: EVMChain,
  network: ApiNetwork,
  address: string,
): Promise<ApiWalletPermission[]> {
  const zerionChain = getZerionChainByApiChain(chain);
  const checksumAddress = normalizeAddress(address);

  const { approvalCandidates, delegationCandidates, tokenAddresses } = await fetchZerionPermissionCandidates(
    chain,
    network,
    checksumAddress,
    zerionChain,
  );

  await updateTokensMetadataByAddress(network, chain, [...tokenAddresses]);

  await supplementPermit2Erc20ApprovalCandidates(
    chain,
    network,
    checksumAddress,
    tokenAddresses,
    approvalCandidates,
  );

  const [approvals, activeDelegateAddress] = await Promise.all([
    buildApprovalPermissions(chain, network, checksumAddress, zerionChain, approvalCandidates),
    getEvmDelegationAddress(chain, network, checksumAddress),
  ]);

  const delegation = activeDelegateAddress
    ? buildDelegationPermission(chain, activeDelegateAddress, delegationCandidates)
    : undefined;

  if (!delegation) {
    return approvals;
  }

  return [...approvals, delegation];
}

async function revokeEvmApproval(
  chain: EVMChain,
  options: Extract<ApiRevokeWalletPermissionOptions, { kind: 'approval' }>,
): Promise<{ txId: string } | { error: ApiAnyDisplayError }> {
  const {
    accountId,
    enclaveToken = '',
    tokenAddress,
    spenderAddress,
  } = options;
  const { network } = parseAccountId(accountId);

  try {
    const account = await fetchStoredChainAccount(accountId, chain);

    if (account.type === 'ledger') throw new Error('Not supported by Ledger accounts');
    if (account.type === 'view') throw new Error('Not supported by View accounts');

    const { address } = account.byChain[chain];
    const provider = getEvmProvider(network, chain);
    const normalizedTokenAddress = normalizeAddress(tokenAddress);
    const normalizedSpenderAddress = normalizeAddress(spenderAddress);

    const [erc20Allowance, permit2Allowance] = await Promise.all([
      getErc20Allowance(chain, network, address, normalizedTokenAddress, normalizedSpenderAddress),
      getPermit2Allowance(chain, network, address, normalizedTokenAddress, normalizedSpenderAddress),
    ]);

    if (erc20Allowance === 0n && permit2Allowance === 0n) {
      return { error: ApiTransactionError.UnsuccesfulTransfer };
    }

    const transaction = erc20Allowance > 0n
      ? {
        from: address,
        to: normalizedTokenAddress,
        value: 0n,
        data: erc20ApproveInterface.encodeFunctionData('approve', [
          normalizedSpenderAddress,
          0n,
        ]),
      }
      : {
        from: address,
        to: UNISWAP_PERMIT2_ADDRESS,
        value: 0n,
        data: permit2AllowanceInterface.encodeFunctionData('approve', [
          normalizedTokenAddress,
          normalizedSpenderAddress,
          0,
          0,
        ]),
      };

    const [nativeBalance, fee] = await Promise.all([
      getWalletBalance(chain, network, address),
      estimateEvmFee(provider, transaction),
    ]);

    if (nativeBalance < fee) {
      return { error: ApiTransactionError.InsufficientBalance };
    }

    const privateKey = await fetchPrivateKeyString(chain, accountId, enclaveToken, account);

    if (!privateKey) {
      return { error: ApiCommonError.InvalidPassword };
    }

    const signer = getSignerFromPrivateKey(network, privateKey).connect(provider);
    const response = await signer.sendTransaction(transaction);

    return { txId: response.hash };
  } catch (err) {
    logDebugError(`evm:${chain}:revokeEvmApproval`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

async function revokeEvmDelegation(
  chain: EVMChain,
  options: Extract<ApiRevokeWalletPermissionOptions, { kind: 'delegation' }>,
): Promise<{ txId: string } | { error: ApiAnyDisplayError }> {
  const {
    accountId,
    enclaveToken = '',
    delegateAddress,
  } = options;
  const { network } = parseAccountId(accountId);

  try {
    const account = await fetchStoredChainAccount(accountId, chain);

    if (account.type === 'ledger') throw new Error('Not supported by Ledger accounts');
    if (account.type === 'view') throw new Error('Not supported by View accounts');

    const { address } = account.byChain[chain];
    const provider = getEvmProvider(network, chain);
    const normalizedDelegateAddress = normalizeAddress(delegateAddress);
    const activeDelegateAddress = await getEvmDelegationAddress(chain, network, address);

    if (!activeDelegateAddress || activeDelegateAddress !== normalizedDelegateAddress) {
      return { error: ApiTransactionError.UnsuccesfulTransfer };
    }

    const privateKey = await fetchPrivateKeyString(chain, accountId, enclaveToken, account);

    if (!privateKey) {
      return { error: ApiCommonError.InvalidPassword };
    }

    const signer = getSignerFromPrivateKey(network, privateKey).connect(provider);
    const txNonce = await signer.getNonce('pending');

    const authorization = await signer.authorize({
      address: ZERO_ADDRESS,
      nonce: txNonce + 1,
    });

    const transaction = {
      type: 4,
      from: address,
      to: address,
      value: 0n,
      data: '0x',
      authorizationList: [authorization],
    };

    const [nativeBalance, fee, feeData] = await Promise.all([
      getWalletBalance(chain, network, address),
      estimateEvmFee(provider, transaction),
      provider.getFeeData(),
    ]);

    if (nativeBalance < fee) {
      return { error: ApiTransactionError.InsufficientBalance };
    }

    // Set-code transactions encode EIP-1559 fees; some chains (e.g. BSC) expose only gasPrice.
    const maxFeePerGas = feeData.maxFeePerGas ?? feeData.gasPrice;
    const maxPriorityFeePerGas = feeData.maxPriorityFeePerGas ?? feeData.gasPrice;

    if (!maxFeePerGas || !maxPriorityFeePerGas) {
      return { error: ApiTransactionError.UnsuccesfulTransfer };
    }

    const response = await signer.sendTransaction({
      ...transaction,
      maxFeePerGas,
      maxPriorityFeePerGas,
    });

    return { txId: response.hash };
  } catch (err) {
    logDebugError(`evm:${chain}:revokeEvmDelegation`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

export async function revokeEvmWalletPermission(
  chain: EVMChain,
  options: ApiRevokeWalletPermissionOptions,
): Promise<{ txId: string } | { error: ApiAnyDisplayError }> {
  if (options.kind === 'delegation') {
    return revokeEvmDelegation(chain, options);
  }

  return revokeEvmApproval(chain, options);
}

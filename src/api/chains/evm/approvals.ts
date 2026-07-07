import { authorizationify, Contract, hashAuthorization, Interface } from 'ethers';

import type { ApiNetwork, ApiRevokeWalletPermissionOptions, ApiWalletPermission, EVMChain } from '../../types';
import type { ApiAnyDisplayError } from '../../types/errors';
import type { ZerionFungibleInfo, ZerionTransaction, ZerionTransactionsResponse } from './types';
import { ApiCommonError, ApiTransactionError } from '../../types';

import { parseAccountId } from '../../../util/account';
import { toDecimal } from '../../../util/decimals';
import { fetchJson } from '../../../util/fetch';
import { logDebugError } from '../../../util/logs';
import { getEvmProvider } from './util/client';
import { updateTokensMetadataByAddress } from './util/metadata';
import { getZerionFungibleImplementation } from './util/tokens';
import { fetchStoredChainAccount } from '../../common/accounts';
import { getKnownAddressInfo } from '../../common/addresses';
import { buildTokenSlug } from '../../common/tokens';
import { normalizeAddress } from './address';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import {
  EVM_DALEGATOR_ADDRESSES,
  EVM_MAX_NUMBER,
  getEvmApiUrl,
  getZerionChainByApiChain,
  ZERO_ADDRESS,
} from './constants';
import { estimateEvmFee } from './transfer';
import { getWalletBalance } from './wallet';

const ERC20_APPROVE_ABI = ['function approve(address spender, uint256 amount) returns (bool)'];
const erc20ApproveInterface = new Interface(ERC20_APPROVE_ABI);

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

async function getErc20Allowance(
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

async function getEvmDelegationAddress(
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

function resolveActMetadata(
  tx: ZerionTransaction,
  actId: string,
): ZerionTransaction['attributes']['application_metadata'] | undefined {
  const act = tx.attributes.acts?.find((item) => item.id === actId);
  return act?.application_metadata ?? tx.attributes.application_metadata;
}

function collectApprovalCandidates(
  tx: ZerionTransaction,
  zerionChain: string,
  pairs: Map<string, ApprovalCandidate>,
) {
  for (const approval of tx.attributes.approvals) {
    if (!approval.fungible_info) continue;

    const impl = getZerionFungibleImplementation(approval.fungible_info, zerionChain);
    if (!impl?.address) continue;

    const metadata = resolveActMetadata(tx, approval.act_id);
    const spenderAddress = metadata?.contract_address;
    if (!spenderAddress) continue;

    const tokenAddress = normalizeAddress(impl.address);
    const normalizedSpenderAddress = normalizeAddress(spenderAddress);
    const key = `${tokenAddress}:${normalizedSpenderAddress}`;

    if (!pairs.has(key)) {
      pairs.set(key, {
        tokenAddress,
        fungibleInfo: approval.fungible_info,
        spenderAddress: normalizedSpenderAddress,
        spenderName: metadata?.name,
        spenderIcon: metadata?.icon?.url,
      });
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
    const metadata = resolveActMetadata(tx, delegation.act_id);
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
};

async function fetchZerionPermissionCandidates(
  network: ApiNetwork,
  checksumAddress: string,
  zerionChain: string,
): Promise<ZerionPermissionCandidates> {
  const approvalCandidates = new Map<string, ApprovalCandidate>();
  const delegationCandidates = new Map<string, DelegationCandidate>();

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

  return { approvalCandidates, delegationCandidates };
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

      const allowance = await getErc20Allowance(chain, network, checksumAddress, tokenAddress, spenderAddress);
      if (allowance === 0n) return undefined;

      const isUnlimited = allowance >= EVM_MAX_NUMBER - (EVM_MAX_NUMBER * 10n / 100n);
      const knownName = getKnownAddressInfo(spenderAddress)?.name;

      const tokenSlug = buildTokenSlug(chain, tokenAddress);

      return {
        kind: 'approval',
        chain,
        tokenAddress,
        tokenSlug,
        tokenName: fungibleInfo.name,
        tokenSymbol: fungibleInfo.symbol,
        tokenDecimals: impl.decimals,
        tokenImage: fungibleInfo.icon?.url ?? undefined,
        spenderAddress,
        spenderName: knownName ?? spenderName,
        spenderIcon,
        allowance: toDecimal(allowance, impl.decimals),
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

  const { approvalCandidates, delegationCandidates } = await fetchZerionPermissionCandidates(
    network,
    checksumAddress,
    zerionChain,
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
    password = '',
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

    const transaction = {
      from: address,
      to: normalizeAddress(tokenAddress),
      value: 0n,
      data: erc20ApproveInterface.encodeFunctionData('approve', [
        normalizeAddress(spenderAddress),
        0n,
      ]),
    };

    const [nativeBalance, fee] = await Promise.all([
      getWalletBalance(chain, network, address),
      estimateEvmFee(provider, transaction),
    ]);

    if (nativeBalance < fee) {
      return { error: ApiTransactionError.InsufficientBalance };
    }

    const privateKey = await fetchPrivateKeyString(chain, accountId, password, account);

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
    password = '',
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

    const [nonce, networkInfo] = await Promise.all([
      provider.getTransactionCount(address),
      provider.getNetwork(),
    ]);
    const chainId = networkInfo.chainId ?? undefined;

    if (chainId === undefined) {
      return { error: ApiTransactionError.WrongNetwork };
    }

    const privateKey = await fetchPrivateKeyString(chain, accountId, password, account);

    if (!privateKey) {
      return { error: ApiCommonError.InvalidPassword };
    }

    const signer = getSignerFromPrivateKey(network, privateKey).connect(provider);
    const unsignedAuthorization = {
      chainId,
      address: ZERO_ADDRESS,
      nonce: BigInt(nonce),
    };
    const authorization = authorizationify({
      ...unsignedAuthorization,
      signature: signer.signingKey.sign(hashAuthorization(unsignedAuthorization)),
    });

    const transaction = {
      type: 4,
      from: address,
      to: address,
      value: 0n,
      data: '0x',
      chainId,
      authorizationList: [authorization],
    };

    const [nativeBalance, fee] = await Promise.all([
      getWalletBalance(chain, network, address),
      estimateEvmFee(provider, transaction),
    ]);

    if (nativeBalance < fee) {
      return { error: ApiTransactionError.InsufficientBalance };
    }

    const response = await signer.sendTransaction(transaction);

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

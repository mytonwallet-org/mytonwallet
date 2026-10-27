import {
  Address, beginCell, Cell, toNano,
} from '@ton/core';

import type { TonTransferParams } from '../chains/ton/types';
import type {
  ApiChain,
  ApiForeignStakingByChain,
  ApiForeignStakingProvider,
  ApiForeignStakingUnstakeTransfer,
  ApiForeignUnstakeDraft,
} from '../types';
import { ApiCommonError } from '../types';

import { TONSTAKERS_JETTON } from '../../config';
import { parseAccountId } from '../../util/account';
import { getMaxMessagesInTransaction } from '../../util/ton/transfer';
import { checkMultiTransactionDraft, submitMultiTransferWithMfa } from '../chains/ton/transfer';
import { getSigner } from '../chains/ton/util/signer';
import { areAddressesEqual, resolveTokenWalletAddress } from '../chains/ton/util/tonCore';
import { fetchStoredAddress, fetchStoredChainAccount } from '../common/accounts';

export type ForeignUnstakeTransaction = {
  chain: ApiChain;
  amountNative: bigint;
  transfers: ApiForeignStakingUnstakeTransfer[];
  messages: TonTransferParams[];
  isInstant: boolean;
};

export function canBuildForeignUnstakeTransaction(
  entry: ApiForeignStakingByChain,
  provider: ApiForeignStakingProvider,
) {
  return entry.chain === 'ton'
    && provider.provider === 'ts'
    && provider.unstake.builder === 'ts'
    && provider.unstake.tokenAddress === TONSTAKERS_JETTON
    && provider.amount > 0n
    && provider.amountNative > 0n;
}

export async function buildForeignUnstakeTransactionForProvider(
  accountId: string,
  entry: ApiForeignStakingByChain,
  providerName: string,
): Promise<ForeignUnstakeTransaction | undefined> {
  const provider = entry.providers.find((item) => (
    item.name === providerName && canBuildForeignUnstakeTransaction(entry, item)
  ));
  if (!provider) return undefined;

  const transfers = await buildTonstakersUnstakeTransfers(accountId, provider);

  return {
    chain: entry.chain,
    amountNative: provider.amountNative,
    transfers,
    isInstant: provider.unstake.instantAvailable !== undefined
      && provider.amountNative <= provider.unstake.instantAvailable,
    messages: transfers.map(({ toAddress, amount, payload }) => ({
      toAddress,
      amount,
      payload: payload ? Cell.fromBase64(payload) : undefined,
    })),
  };
}

export async function checkForeignUnstakeTransactionDraft(
  accountId: string,
  transaction: ForeignUnstakeTransaction,
) {
  if (transaction.chain !== 'ton') return { error: ApiCommonError.Unexpected };

  const account = await fetchStoredChainAccount(accountId, transaction.chain);
  if (transaction.messages.length > getMaxMessagesInTransaction(account)) {
    return { error: ApiCommonError.Unexpected };
  }

  return checkMultiTransactionDraft(accountId, transaction.messages);
}

export async function submitForeignUnstakeTransaction(
  accountId: string,
  transaction: ForeignUnstakeTransaction,
  enclaveToken?: string,
) {
  if (transaction.chain !== 'ton') return { error: ApiCommonError.Unexpected };

  const account = await fetchStoredChainAccount(accountId, transaction.chain);
  if (transaction.messages.length > getMaxMessagesInTransaction(account)) {
    return { error: ApiCommonError.Unexpected };
  }

  const checked = await checkMultiTransactionDraft(accountId, transaction.messages);
  if ('error' in checked) return checked;

  return submitMultiTransferWithMfa({
    accountId,
    messages: transaction.messages,
    signer: getSigner(accountId, account, enclaveToken),
  });
}

async function buildTonstakersUnstakeTransfers(
  accountId: string,
  provider: ApiForeignStakingProvider,
): Promise<ApiForeignUnstakeDraft['transfers']> {
  const { network } = parseAccountId(accountId);
  const address = await fetchStoredAddress(accountId, 'ton');
  if (!areAddressesEqual(provider.unstake.ownerAddress, address)) {
    throw new Error('Foreign unstaking owner does not match the wallet');
  }

  const tokenWalletAddress = await resolveTokenWalletAddress(network, address, TONSTAKERS_JETTON);
  const payload = beginCell()
    .storeUint(0x595f07bc, 32)
    .storeUint(0, 64)
    .storeCoins(provider.amount)
    .storeAddress(Address.parse(address))
    .storeMaybeRef(
      beginCell()
        .storeUint(0, 1)
        .storeUint(0, 1)
        .endCell(),
    )
    .endCell();

  return [{
    toAddress: tokenWalletAddress,
    amount: toNano('1.05'),
    payload: payload.toBoc().toString('base64'),
  }];
}

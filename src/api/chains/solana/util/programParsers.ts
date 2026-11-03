import type { Address, TransactionForAccounts } from '@solana/kit';
import { getBase58Encoder, getU32Decoder, getU64Decoder, getUtf8Decoder, isAddress } from '@solana/kit';

import type { ApiNetwork } from '../../../types';
import type {
  SolanaCompiledTransaction,
  SolanaParsedTransaction,
  SolanaTokenOperation,
  SolanaTransaction,
  SolanaTransactionEmulationResult,
  SolanaTransactionEmulationResultRaw,
} from '../types';

import { SOLANA } from '../../../../config';
import {
  ComputeBudgetInstruction,
  identifyComputeBudgetInstruction,
  parseSetComputeUnitLimitInstruction,
  parseSetComputeUnitPriceInstruction,
} from '../../../../lib/solana-program/computeBudget';
import { toDecimal } from '../../../../util/decimals';
import { fetchJson } from '../../../../util/fetch';
import { logDebugError } from '../../../../util/logs';
import { buildTokenSlug, getTokenBySlug } from '../../../common/tokens';
import { ATA_RENT_LAMPORTS, NETWORK_CONFIG, SOLANA_PROGRAM_IDS, WSOL_MINT } from '../constants';
import { updateTokensMetadataByAddress } from './metadata';

export function parseSimpleTransfer(address: string, tx: SolanaTransaction) {
  const { transaction, meta } = tx!;

  const systemProgramIdIndex = transaction.message.accountKeys.findIndex((e) =>
    SOLANA_PROGRAM_IDS.system.includes(e),
  );

  const currentAccountIndex = transaction.message.accountKeys.findIndex((e) => e === address);

  if (currentAccountIndex === undefined) {
    return;
  }

  const simpleTransferInstruction = transaction.message.instructions
    .find((e) => e.programIdIndex === systemProgramIdIndex && e.accounts.includes(currentAccountIndex));

  if (!simpleTransferInstruction) {
    return undefined;
  }

  const fromAddressIndex = simpleTransferInstruction?.accounts[0];
  const toAddressIndex = simpleTransferInstruction?.accounts[1];

  if ((fromAddressIndex === undefined) || (toAddressIndex === undefined)) {
    return undefined;
  }

  const rawAmount = (meta?.postBalances[currentAccountIndex] ?? 0n) - (meta?.preBalances[currentAccountIndex] ?? 0n);
  const amount = BigInt(rawAmount ?? 0);
  const fromAddress = transaction.message.accountKeys[fromAddressIndex];
  const toAddress = transaction.message.accountKeys[toAddressIndex];

  const slug = SOLANA.slug;
  const isIncoming = toAddress === address;
  const normalizedAddress = isIncoming ? fromAddress : toAddress;
  const fee = BigInt(meta?.fee ?? 0);
  const type = undefined;
  const shouldHide = false;

  return {
    amount,
    fromAddress,
    toAddress,
    slug,
    isIncoming,
    normalizedAddress,
    fee,
    type,
    shouldHide,
  };
}

export function parseTxComment(tx: SolanaTransaction | SolanaParsedTransaction) {
  let memoInstruction: { data: string } | undefined = undefined;

  if (!tx) {
    return undefined;
  }

  if ('type' in tx) {
    memoInstruction = tx.instructions
      .find((e) => SOLANA_PROGRAM_IDS.memo.includes(e.programId));
  } else {
    const { transaction } = tx;
    const memoProgramIdIndex = transaction.message.accountKeys.findIndex((e) => SOLANA_PROGRAM_IDS.memo.includes(e));

    memoInstruction = transaction.message.instructions
      .find((e) => memoProgramIdIndex === e.programIdIndex);
  }

  if (memoInstruction) {
    const base58 = getBase58Encoder();
    const utf8 = getUtf8Decoder();

    const rawBytes = base58.encode(memoInstruction.data);
    return utf8.decode(rawBytes);
  }
}

export async function parseTokenOperation(
  network: ApiNetwork,
  tx: NonNullable<TransactionForAccounts<void>['meta']>,
  userAddress: string,
  staticAccountKeys: readonly Address[],
  userPaidRentByAccountIndex: ReadonlyMap<number, bigint> = new Map(),
): Promise<SolanaTokenOperation | undefined> {
  const changes = new Map<string, bigint>();
  const assets: string[] = [];

  const userIndex = staticAccountKeys.findIndex((k) => k.toString() === userAddress);

  let solSwapDirection: 'in' | 'out' | undefined = undefined;

  let solDiff = 0n;
  if (userIndex !== -1) {
    // The fee is shown separately, so it is added back only for the fee payer, which is account 0
    const feePaid = userIndex === 0 ? BigInt(tx.fee) : 0n;
    solDiff = BigInt(tx.postBalances[userIndex] - tx.preBalances[userIndex]) + feePaid;
  }

  if (!tx.postTokenBalances?.length || !tx.preTokenBalances?.length) {
    return undefined;
  }

  let newATACount = 0n;

  tx.postTokenBalances?.filter((b) => b.owner === userAddress)
    .forEach((post) => {
      const pre = tx.preTokenBalances?.find((p) => p.accountIndex === post.accountIndex);

      if (!pre) {
        // instruction may include ATA creating, so add it as additional fee (if exists)
        newATACount++;
      }
    });

  // A token held by the user is summed over the accounts the user owns, so an account leaving by a transfer, a close
  // or a new owner changes it; wrapped SOL is summed into the SOL change, which also decides the swap direction
  let wrappedSolDiff = 0n;
  const addHolding = (mint: string, amount: bigint) => {
    if (mint === WSOL_MINT) {
      solDiff += amount;
      wrappedSolDiff += amount;
    } else {
      changes.set(mint, (changes.get(mint) ?? 0n) + amount);
    }
  };
  tx.preTokenBalances.filter((b) => b.owner === userAddress).forEach(({ mint, uiTokenAmount }) => {
    addHolding(mint, -BigInt(uiTokenAmount.amount));
  });
  tx.postTokenBalances.filter((b) => b.owner === userAddress).forEach(({ mint, uiTokenAmount }) => {
    addHolding(mint, BigInt(uiTokenAmount.amount));
  });
  changes.forEach((change, mint) => {
    if (change !== 0n) assets.push(mint);
  });

  const totalRentPaid = newATACount * ATA_RENT_LAMPORTS;

  // 0 if plain transfer
  // Negative if swap sol/token
  // Positive if swap token/sol
  changes.set(SOLANA.slug, solDiff);

  const sent = new Map<string, bigint>();
  const received = new Map<string, bigint>();

  changes.forEach((change, mint) => {
    if (change < 0n) {
      sent.set(mint, change < 0n ? -change : change);
    }

    if (change > 0n) {
      received.set(mint, change);
    }
  });

  // An approval changes nothing the user holds yet grants it away, and the preview has no row to show that with
  if (!sent.size && !received.size) {
    throw new Error('Transaction changes no holding of the user');
  }

  const isSentOnly = !received.size && sent.size;

  const isReceivedOnly = !sent.size && received.size;

  const isSwap = !isSentOnly && !isReceivedOnly;

  // Set out if swap sol for token
  // Set in if swap token for sol
  // Set undefined if swap between tokens
  if (isSwap) {
    if (solDiff + totalRentPaid < 0n) {
      solSwapDirection = 'out';
    } else if (solDiff + totalRentPaid > 0n) {
      solSwapDirection = 'in';
    }
  }

  if (isSwap) {
    if (!solSwapDirection) {
      // Ignore sol balance diff, because it is always fee and not a part of swap
      sent.delete(SOLANA.slug);
      received.delete(SOLANA.slug);
    }

    if (solSwapDirection === 'out') {
      const sentSol = sent.get(SOLANA.slug) || 0n;
      // Fee paid by sender - should be subtracted from sent sol
      // Swap 1000 lamports to token -> -(1000 + 1 ATA rent + 5000 fee) = -2045280 lamports
      // Fee is added on solDiff, so -2045280 + 5000 fee = -2040280 lamports
      // Need to add `totalRentPaid` because it is treated as fee and not as transfer part -2040280 + 1 ATA = -1000 lamports
      sent.set(SOLANA.slug, sentSol - totalRentPaid);
    }
  }

  if (isSentOnly || isReceivedOnly) {
    // Wrapped SOL moving the same way as the net SOL change is its own row; more of it than that change means part
    // turned to or from native SOL inside the transaction, and one net SOL row is shown instead
    const shown = isSentOnly ? sent : received;
    const wrapped = isSentOnly ? -wrappedSolDiff : wrappedSolDiff;
    const shownSol = shown.get(SOLANA.slug) ?? 0n;
    if (wrapped > 0n && wrapped <= shownSol) {
      if (wrapped === shownSol) {
        shown.delete(SOLANA.slug);
      } else {
        shown.set(SOLANA.slug, shownSol - wrapped);
      }
      shown.set(WSOL_MINT, wrapped);
    }

    // Rent that the user's own ATA instruction pays for an account receiving a shown token goes to the fee,
    // as in the wallet's own transfers, once per token; any other SOL the user spends stays a row
    const sentSol = sent.get(SOLANA.slug) ?? 0n;
    const rentedMints = new Set<string>();
    const rent = tx.postTokenBalances
      .filter((post) => sent.has(post.mint) && BigInt(post.uiTokenAmount.amount) > 0n)
      .reduce((sum, post) => {
        const accountRent = userPaidRentByAccountIndex.get(post.accountIndex);
        if (!accountRent || rentedMints.has(post.mint)) return sum;
        rentedMints.add(post.mint);
        return sum + accountRent;
      }, 0n);
    const rentPaid = rent < sentSol ? rent : sentSol;

    if (rentPaid === sentSol) {
      sent.delete(SOLANA.slug);
    } else {
      sent.set(SOLANA.slug, sentSol - rentPaid);
    }

    // if no from/to address - consider to be mint or burn(?) - use transaction initiator as fallback
    const fromAddress = isSentOnly
      ? userAddress
      : tx.postTokenBalances.find((e) => e.owner !== userAddress)?.owner || staticAccountKeys[0];
    const toAddress = !isSentOnly
      ? userAddress
      : tx.postTokenBalances.find((e) => e.owner !== userAddress)?.owner || staticAccountKeys[0];

    // The fallback above can resolve to the user, so the direction comes from the balance change
    const isIncoming = !isSentOnly;

    return {
      assets,
      isSwap: false,
      networkFee: BigInt(tx.fee) + rentPaid,
      transfers: [...(isSentOnly ? sent : received)]
        .map(([asset, amount]) => ({
          amount,
          fromAddress,
          toAddress,
          slug: asset === SOLANA.slug ? SOLANA.slug : buildTokenSlug(SOLANA.chain, asset),
          isIncoming,
          normalizedAddress: isIncoming ? fromAddress : toAddress,
          fee: tx.fee,
        })),
    };
  }

  // SOL a token swap moves besides its tokens, such as a tip or a refunded rent, is no asset up to one account rent,
  // and the spent part joins the fee; more SOL than that stays an asset
  let solInFee = 0n;
  const solSent = sent.size > 1 ? sent.get(SOLANA.slug) : undefined;
  if (solSent !== undefined && solSent <= ATA_RENT_LAMPORTS) {
    solInFee = solSent;
    sent.delete(SOLANA.slug);
  }
  const solReceived = received.size > 1 ? received.get(SOLANA.slug) : undefined;
  if (solReceived !== undefined && solReceived <= ATA_RENT_LAMPORTS) {
    received.delete(SOLANA.slug);
  }

  // A swap preview names one asset per side, so a swap that moves more is shown as unparsed rather than in part
  if (sent.size > 1 || received.size > 1) {
    return undefined;
  }

  const firstSentAsset = [...sent]?.[0]?.[0] || '';
  const firstReceivedAsset = [...received]?.[0]?.[0] || '';

  await updateTokensMetadataByAddress(
    network,
    [firstSentAsset, firstReceivedAsset].filter((e) => e !== 'sol'),
  );

  const assetTo = firstReceivedAsset === SOLANA.slug
    ? SOLANA
    : getTokenBySlug(buildTokenSlug('solana', firstReceivedAsset));

  const assetFrom = firstSentAsset === SOLANA.slug
    ? SOLANA
    : getTokenBySlug(buildTokenSlug('solana', firstSentAsset));

  return {
    assets,
    isSwap: true,
    swap: {
      fromAddress: userAddress,
      from: assetFrom?.slug || '',
      fromAmount: toDecimal(sent.get([...sent][0][0])!, assetFrom?.decimals || 9),
      to: assetTo?.slug || '',
      toAmount: toDecimal(received.get([...received][0][0])!, assetTo?.decimals || 9),
      networkFee: (BigInt(tx.fee) + totalRentPaid + solInFee).toString(10),
      swapFee: '0',
    },
  };
}

const ATA_CREATE = 0;
const ATA_CREATE_IDEMPOTENT = 1;
const TOKEN_APPROVE = 4;
const TOKEN_SET_AUTHORITY = 6;
const TOKEN_MINT_TO = 7;
const TOKEN_CLOSE_ACCOUNT = 9;
const TOKEN_FREEZE_ACCOUNT = 10;
const TOKEN_APPROVE_CHECKED = 13;
const TOKEN_MINT_TO_CHECKED = 14;
const TOKEN_WITHDRAW_EXCESS_LAMPORTS = 38;
const TOKEN_AUTHORITY_TYPE_CLOSE_ACCOUNT = 3;
const TOKEN_AUTHORITY_ACCOUNT_INDICES: Partial<Record<number, number>> = {
  [TOKEN_APPROVE]: 2,
  [TOKEN_SET_AUTHORITY]: 1,
  [TOKEN_MINT_TO]: 2,
  [TOKEN_CLOSE_ACCOUNT]: 2,
  [TOKEN_FREEZE_ACCOUNT]: 2,
  [TOKEN_APPROVE_CHECKED]: 3,
  [TOKEN_MINT_TO_CHECKED]: 2,
  [TOKEN_WITHDRAW_EXCESS_LAMPORTS]: 2,
};
const TOKEN_AUTHORITY_FIELDS = new Map<string, readonly string[]>([
  ['approve', ['owner', 'multisigOwner']],
  ['approveChecked', ['owner', 'multisigOwner']],
  ['setAuthority', ['authority', 'multisigAuthority']],
  ['closeAccount', ['owner', 'multisigOwner']],
  ['withdrawExcessLamports', ['authority', 'multisigAuthority']],
  ['mintTo', ['mintAuthority', 'multisigMintAuthority']],
  ['mintToChecked', ['mintAuthority', 'multisigMintAuthority']],
  ['freezeAccount', ['freezeAuthority', 'multisigFreezeAuthority']],
]);
const HARMLESS_STAKE_DISCRIMINATORS = new Set([0, 2, 5, 9, 13, 14]);
const HARMLESS_STAKE_TYPES = new Set([
  'initialize', 'delegate', 'deactivate', 'initializeChecked', 'getMinimumDelegation', 'deactivateDelinquent',
]);
// System instruction types as the RPC names them, indexed by the instruction's u32 discriminator
const SYSTEM_INSTRUCTION_TYPES = [
  'createAccount',
  'assign',
  'transfer',
  'createAccountWithSeed',
  'advanceNonce',
  'withdrawFromNonce',
  'initializeNonce',
  'authorizeNonce',
  'allocate',
  'allocateWithSeed',
  'assignWithSeed',
  'transferWithSeed',
  'upgradeNonce',
] as const;

function getClosedTokenAccounts(
  rawTx: SolanaCompiledTransaction,
  innerInstructions: SolanaTransactionEmulationResult['innerInstructions'] | undefined,
) {
  const closedAccounts = new Set<string>();

  rawTx.instructions.forEach((instruction) => {
    const accountIndex = instruction.accountIndices?.[0];
    if (
      SOLANA_PROGRAM_IDS.token.includes(rawTx.staticAccounts[instruction.programAddressIndex])
      && instruction.data?.[0] === TOKEN_CLOSE_ACCOUNT
      && accountIndex !== undefined
    ) {
      closedAccounts.add(rawTx.staticAccounts[accountIndex]);
    }
  });

  // A token instruction the RPC could not parse may be a close, so every account it touches counts as closed
  innerInstructions?.forEach(({ instructions }) => instructions.forEach((inner) => {
    if (!SOLANA_PROGRAM_IDS.token.includes(inner.programId)) return;
    if (!('parsed' in inner)) {
      inner.accounts.forEach((account) => closedAccounts.add(account));
    } else if (inner.parsed.type === 'closeAccount') {
      closedAccounts.add(inner.parsed.info.account);
    }
  }));

  return closedAccounts;
}

export function parseUserPaidTokenAccountRent(
  rawTx: SolanaCompiledTransaction,
  innerInstructions: SolanaTransactionEmulationResult['innerInstructions'] | undefined,
  userAddress: string,
) {
  const rentByAccountIndex = new Map<number, bigint>();
  const closedAccounts = getClosedTokenAccounts(rawTx, innerInstructions);

  rawTx.instructions.forEach((instruction, instructionIndex) => {
    const programId = rawTx.staticAccounts[instruction.programAddressIndex];
    const kind = instruction.data?.[0] ?? ATA_CREATE;
    const accountIndex = instruction.accountIndices?.[1];
    const account = accountIndex === undefined ? undefined : rawTx.staticAccounts[accountIndex];

    // An account closed in the same transaction can be reopened at someone else's expense, so its first funding
    // says nothing about the account that receives the token; one loaded from a lookup table cannot be checked
    if (
      !SOLANA_PROGRAM_IDS.ata.includes(programId)
      || (kind !== ATA_CREATE && kind !== ATA_CREATE_IDEMPOTENT)
      || accountIndex === undefined
      || !account
      || closedAccounts.has(account)
    ) {
      return;
    }

    // The ATA program funds the new account from its payer by System createAccount or transfer
    const rent = (innerInstructions?.find(({ index }) => index === instructionIndex)?.instructions ?? [])
      .reduce((sum, inner) => {
        if (!('parsed' in inner) || !SOLANA_PROGRAM_IDS.system.includes(inner.programId)) return sum;
        const { type, info } = inner.parsed;
        const isFromUser = (type === 'createAccount' || type === 'transfer') && info.source === userAddress;
        return isFromUser ? sum + BigInt(info.lamports ?? 0) : sum;
      }, 0n);

    if (rent > 0n) {
      rentByAccountIndex.set(accountIndex, rent);
    }
  });

  return rentByAccountIndex;
}

// Only the System program reassigns, allocates or takes lamports from a System account or changes a nonce authority,
// and on what the user controls it needs the user's signature, so the user is among the instruction's accounts. Only
// lamports paid from the user's own address or received from accounts the user does not control, accounts created at
// other addresses and nonce upkeep except initializing the user's own account show in the preview. A nonce withdrawal
// or authorization accepts any signer of the instruction as the authority, and a parsed inner instruction does not list
// them all, so such an inner one always counts
export function hasHiddenSystemAccountChanges(
  rawTx: SolanaCompiledTransaction,
  innerInstructions: SolanaTransactionEmulationResult['innerInstructions'] | undefined,
  userAddress: string,
) {
  // Without inner instructions, a System instruction called by another program cannot be checked
  if (!Array.isArray(innerInstructions)) return true;

  function isHiddenChange(
    type: string | undefined,
    accounts: readonly (string | undefined)[],
    newAccount?: string,
    authority?: string,
    nonceAccount?: string,
  ) {
    if (!accounts.includes(userAddress)) return false;

    switch (type) {
      case 'transfer':
      case 'advanceNonce':
      case 'upgradeNonce':
        return false;
      case 'createAccount':
      case 'createAccountWithSeed':
        return newAccount === userAddress;
      case 'initializeNonce':
        return nonceAccount === userAddress;
      case 'transferWithSeed':
        return authority === userAddress;
      default:
        return true;
    }
  }

  const hasHiddenTopLevelChange = rawTx.instructions.some((instruction) => {
    if (!SOLANA_PROGRAM_IDS.system.includes(rawTx.staticAccounts[instruction.programAddressIndex])) return false;

    const accounts = instruction.accountIndices?.map((index) => rawTx.staticAccounts[index]) ?? [];
    const type = instruction.data && instruction.data.length >= 4
      ? SYSTEM_INSTRUCTION_TYPES[getU32Decoder().decode(instruction.data)]
      : undefined;

    return isHiddenChange(type, accounts, accounts[1], accounts[1], accounts[0]);
  });

  return hasHiddenTopLevelChange || innerInstructions.some(({ instructions }) => instructions.some((inner) => {
    if (!SOLANA_PROGRAM_IDS.system.includes(inner.programId)) return false;
    if (!('parsed' in inner)) return inner.accounts.includes(userAddress);

    const { type, info } = inner.parsed;
    if (type === 'withdrawFromNonce' || type === 'authorizeNonce') return true;

    const accounts = Object.values(info).filter((value) => typeof value === 'string');
    return isHiddenChange(type, accounts, info.newAccount, info.sourceBase, info.nonceAccount);
  }));
}

export async function emulateTransaction(
  transaction: string,
  network: ApiNetwork,
  signal?: AbortSignal,
  accountAddresses?: readonly string[],
) {
  const options = {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      id: '1',
      method: 'simulateTransaction',
      params: [
        transaction,
        {
          encoding: 'base64',
          replaceRecentBlockhash: true,
          innerInstructions: true,
          ...(accountAddresses ? { accounts: { addresses: accountAddresses, encoding: 'jsonParsed' } } : {}),
        },
      ],
    }),
  };

  const response = await fetchJson<SolanaTransactionEmulationResultRaw>(
    NETWORK_CONFIG[network].rpcUrl,
    undefined,
    { ...options, signal },
  );

  if ('error' in response) throw new Error('Transaction simulation failed');
  return response.result.value;
}

// Token authority instructions use the fixed authority account or multisig signers after it, which parsed inner
// instructions enumerate. Holdings do not show authority changes, freezes, mints to others or token account rent
// paid to others. Removing close authority returns closing rights to the owner; other renunciations and rent returned
// to the user are harmless. Minting to user-owned accounts is visible only when the user's net increase per mint
// covers all user-authorized issuance.
// Approvals can be spent or revoked in the transaction, so their simulated sources must be closed or parsed token
// accounts with a non-null info object, excluding arrays and any delegate field
export async function hasHiddenTokenAuthorityChanges(
  rawTx: SolanaCompiledTransaction,
  emulation: SolanaTransactionEmulationResult,
  userAddress: string,
  transaction: string,
  network: ApiNetwork,
) {
  const approvalSources = new Set<string>();
  const mintedAmounts = new Map<string, bigint>();

  function hasVisibleMint(account: unknown) {
    if (typeof account !== 'string') return false;
    const accountIndex = rawTx.staticAccounts.findIndex((key) => key === account);
    return accountIndex !== -1 && emulation.postTokenBalances?.some((balance) => (
      balance.accountIndex === accountIndex && balance.owner === userAddress
    ));
  }

  function recordMint(mint: unknown, amount: bigint) {
    if (typeof mint !== 'string' || !isAddress(mint)) return false;
    mintedAmounts.set(mint, (mintedAmounts.get(mint) ?? 0n) + amount);
    return true;
  }

  const hasHiddenTopLevelChange = rawTx.instructions.some((instruction) => {
    if (!SOLANA_PROGRAM_IDS.token.includes(rawTx.staticAccounts[instruction.programAddressIndex])
      || !instruction.data?.length) return false;

    const type = instruction.data[0];
    const authorityIndex = TOKEN_AUTHORITY_ACCOUNT_INDICES[type];
    if (authorityIndex === undefined) return false;

    const accounts = instruction.accountIndices ?? [];
    if (!accounts.slice(authorityIndex).some((index) => rawTx.staticAccounts[index] === userAddress)) return false;

    if (type === TOKEN_APPROVE || type === TOKEN_APPROVE_CHECKED) {
      const source = rawTx.staticAccounts[accounts[0]];
      if (!source) return true;
      approvalSources.add(source);
      return false;
    }
    if (type === TOKEN_SET_AUTHORITY && instruction.data[2] === 0
      && instruction.data[1] !== TOKEN_AUTHORITY_TYPE_CLOSE_ACCOUNT) return false;
    const destination = rawTx.staticAccounts[accounts[1]];
    if ((type === TOKEN_CLOSE_ACCOUNT || type === TOKEN_WITHDRAW_EXCESS_LAMPORTS)
      && destination === userAddress) return false;
    if ((type === TOKEN_MINT_TO || type === TOKEN_MINT_TO_CHECKED) && hasVisibleMint(destination)) {
      if (instruction.data.length < 9) return true;
      return !recordMint(rawTx.staticAccounts[accounts[0]], getU64Decoder().decode(instruction.data.slice(1, 9)));
    }
    return true;
  });

  if (hasHiddenTopLevelChange) return true;

  const hasHiddenInnerChange = emulation.innerInstructions?.some(({ instructions }) => instructions.some((inner) => {
    if (!SOLANA_PROGRAM_IDS.token.includes(inner.programId)) return false;
    if (!('parsed' in inner)) return inner.accounts.includes(userAddress);

    const { type } = inner.parsed;
    const info: Record<string, unknown> = inner.parsed.info;
    const authorityFields = TOKEN_AUTHORITY_FIELDS.get(type);
    if (!authorityFields) return false;
    const isUserAuthority = authorityFields.some((field) => info[field] === userAddress)
      || (Array.isArray(info.signers) && info.signers.includes(userAddress));
    if (!isUserAuthority) return false;

    if (type === 'approve' || type === 'approveChecked') {
      if (typeof info.source !== 'string') return true;
      approvalSources.add(info.source);
      return false;
    }
    // eslint-disable-next-line no-null/no-null -- RPC null removes authority, returning close rights to the owner
    if (type === 'setAuthority' && info.newAuthority === null && info.authorityType !== 'closeAccount') return false;
    if ((type === 'closeAccount' || type === 'withdrawExcessLamports')
      && info.destination === userAddress) return false;
    if ((type === 'mintTo' || type === 'mintToChecked') && hasVisibleMint(info.account)) {
      let amount: unknown = info.amount;
      if (type === 'mintToChecked') {
        const { tokenAmount } = info;
        if (!tokenAmount || typeof tokenAmount !== 'object' || !('amount' in tokenAmount)) return true;
        amount = tokenAmount.amount;
      }
      if (typeof amount !== 'string' || !/^\d+$/.test(amount)) return true;
      return !recordMint(info.mint, BigInt(amount));
    }
    return true;
  }));
  if (hasHiddenInnerChange) return true;

  try {
    for (const [mint, amount] of mintedAmounts) {
      let change = 0n;
      for (const balance of emulation.preTokenBalances ?? []) {
        if (balance.owner === userAddress && balance.mint === mint) change -= BigInt(balance.uiTokenAmount.amount);
      }
      for (const balance of emulation.postTokenBalances ?? []) {
        if (balance.owner === userAddress && balance.mint === mint) change += BigInt(balance.uiTokenAmount.amount);
      }
      if (change < amount) return true;
    }
    if (!approvalSources.size) return false;

    const simulated = await emulateTransaction(transaction, network, undefined, [...approvalSources]);
    // eslint-disable-next-line no-null/no-null -- Successful RPC simulation reports null
    if (simulated?.err !== null || !Array.isArray(simulated.accounts)
      || simulated.accounts.length !== approvalSources.size) return true;

    return simulated.accounts.some((account) => {
      // eslint-disable-next-line no-null/no-null -- RPC null denotes a closed account
      if (account === null) return false;
      const parsed = account?.data?.parsed;
      const info = parsed?.info;
      return parsed?.type !== 'account' || !info || typeof info !== 'object'
        || Array.isArray(info) || 'delegate' in info;
    });
  } catch (err) {
    logDebugError('solana:hasHiddenTokenAuthorityChanges', err);
    return true;
  }
}

// Stake authorize, lockup, split and merge accept any instruction signer, while parsed inner instructions omit some
// signers, so staker, withdrawer and lockup custodian authority comes from the mentioned stake accounts' state. Split
// and merge can carry the user's authority into an account created in the transaction, whose pre-transaction state
// cannot show it. Seed authorization uses a fixed signing base. A top-level instruction lists all accounts, so the
// user's presence decides
export async function hasHiddenStakeAuthorityChanges(
  rawTx: SolanaCompiledTransaction,
  innerInstructions: SolanaTransactionEmulationResult['innerInstructions'] | undefined,
  userAddress: string,
  network: ApiNetwork,
) {
  const hasHiddenTopLevelChange = rawTx.instructions.some((instruction) => {
    if (!SOLANA_PROGRAM_IDS.stake.includes(rawTx.staticAccounts[instruction.programAddressIndex])) return false;
    if (instruction.data && instruction.data.length >= 4
      && HARMLESS_STAKE_DISCRIMINATORS.has(getU32Decoder().decode(instruction.data))) return false;

    return instruction.accountIndices?.some((index) => rawTx.staticAccounts[index] === userAddress);
  });
  if (hasHiddenTopLevelChange) return true;

  const addresses = new Set<string>();
  const hasHiddenInnerChange = innerInstructions?.some(({ instructions }) => instructions.some((inner) => {
    if (!SOLANA_PROGRAM_IDS.stake.includes(inner.programId)) return false;
    if (!('parsed' in inner)) return inner.accounts.includes(userAddress);

    const { type } = inner.parsed;
    const info: Record<string, unknown> = inner.parsed.info;
    if (HARMLESS_STAKE_TYPES.has(type)) return false;
    if ((type === 'authorizeWithSeed' || type === 'authorizeCheckedWithSeed')
      && info.authorityBase === userAddress) return true;

    Object.values(info).forEach((value) => {
      if (typeof value === 'string' && isAddress(value)) addresses.add(value);
    });
    return false;
  }));
  if (hasHiddenInnerChange || addresses.size > 100) return true;
  if (!addresses.size) return false;

  try {
    const options = {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: '1',
        method: 'getMultipleAccounts',
        params: [[...addresses], { encoding: 'jsonParsed' }],
      }),
    };

    const response = await fetchJson<{
      error?: unknown;
      result?: {
        value?: ({
          owner?: unknown;
          data?: {
            parsed?: {
              type?: string;
              info?: { meta?: {
                authorized?: { staker?: string; withdrawer?: string };
                lockup?: { custodian?: string };
              }; };
            };
          };
        } | null)[];
      };
    }>(NETWORK_CONFIG[network].rpcUrl, undefined, options);
    const accounts = response.result?.value;
    if ('error' in response || !Array.isArray(accounts) || accounts.length !== addresses.size) return true;

    return accounts.some((account) => {
      // eslint-disable-next-line no-null/no-null -- RPC null denotes an absent account
      if (account === null) return false;
      if (typeof account?.owner !== 'string') return true;
      if (!SOLANA_PROGRAM_IDS.stake.includes(account.owner)) return false;
      const parsed = account.data?.parsed;
      if (parsed?.type === 'uninitialized') return false;
      if (parsed?.type !== 'initialized' && parsed?.type !== 'delegated') return true;

      const authorized = parsed.info?.meta?.authorized;
      const custodian = parsed.info?.meta?.lockup?.custodian;
      if (typeof authorized?.staker !== 'string' || !isAddress(authorized.staker)
        || typeof authorized.withdrawer !== 'string' || !isAddress(authorized.withdrawer)
        || typeof custodian !== 'string' || !isAddress(custodian)) return true;

      return authorized.staker === userAddress || authorized.withdrawer === userAddress || custodian === userAddress;
    });
  } catch (err) {
    logDebugError('solana:hasHiddenStakeAuthorityChanges', err);
    return true;
  }
}

export function parsePriorityFee(rawTx: SolanaCompiledTransaction) {
  for (const instruction of rawTx.instructions) {
    const programId = rawTx.staticAccounts[instruction.programAddressIndex];

    if (SOLANA_PROGRAM_IDS.computeBudget.includes(programId)) {
      if (!instruction.data) {
        continue;
      }

      const type = identifyComputeBudgetInstruction(instruction.data);

      const instructionForParser = {
        programAddress: programId,
        data: instruction.data,
        accounts: instruction.accountIndices?.map((index) => ({ address: rawTx.staticAccounts[index] })) || [],
      };
      if (type === ComputeBudgetInstruction.SetComputeUnitPrice) {
        const parsed = parseSetComputeUnitPriceInstruction(instructionForParser as any);
        return {
          type: 'price',
          microLamports: parsed.data.microLamports,
        };
      }

      if (type === ComputeBudgetInstruction.SetComputeUnitLimit) {
        const parsed = parseSetComputeUnitLimitInstruction(instructionForParser as any);
        return {
          type: 'limit',
          units: parsed.data.units,
        };
      }
    }
  }
}

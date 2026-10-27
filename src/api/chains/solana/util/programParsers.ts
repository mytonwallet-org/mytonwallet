import type { Address, TransactionForAccounts } from '@solana/kit';
import { getBase58Encoder, getUtf8Decoder } from '@solana/kit';

import type { ApiNetwork } from '../../../types';
import type {
  SolanaCompiledTransaction,
  SolanaParsedTransaction,
  SolanaTokenOperation,
  SolanaTransaction,
  SolanaTransactionEmulationResult,
} from '../types';

import { SOLANA } from '../../../../config';
import {
  ComputeBudgetInstruction,
  identifyComputeBudgetInstruction,
  parseSetComputeUnitLimitInstruction,
  parseSetComputeUnitPriceInstruction,
} from '../../../../lib/solana-program/computeBudget';
import { toDecimal } from '../../../../util/decimals';
import { buildTokenSlug, getTokenBySlug } from '../../../common/tokens';
import { ATA_RENT_LAMPORTS, SOLANA_PROGRAM_IDS, WSOL_MINT } from '../constants';
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

      const preAmount = pre ? BigInt(pre.uiTokenAmount.amount) : 0n;
      const postAmount = BigInt(post.uiTokenAmount.amount);
      const diff = postAmount - preAmount;

      if (diff !== 0n) {
        const mint = post.mint;
        const key = mint === WSOL_MINT ? SOLANA.slug : mint;

        assets.push(key);

        const current = changes.get(key) || 0n;
        changes.set(key, current + diff);
      }
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
      networkFee: (BigInt(tx.fee) + totalRentPaid).toString(10),
      swapFee: '0',
    },
  };
}

const ATA_CREATE = 0;
const ATA_CREATE_IDEMPOTENT = 1;
const TOKEN_CLOSE_ACCOUNT = 9;

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

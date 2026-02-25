import type { Address, TransactionForAccounts } from '@solana/kit';
import { getBase58Encoder, getUtf8Decoder } from '@solana/kit';

import type { ApiNetwork } from '../../../types';
import type {
  SolanaCompiledTransaction,
  SolanaParsedTransaction,
  SolanaTokenOperation,
  SolanaTransaction,
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
import { SOLANA_PROGRAM_IDS, WSOL_MINT } from '../constants';
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

// TODO: switch to actual data fetching
const ATA_RENT_LAMPORTS = 2039280n;

export async function parseTokenOperation(
  network: ApiNetwork,
  tx: NonNullable<TransactionForAccounts<void>['meta']>,
  userAddress: string,
  staticAccountKeys: readonly Address[],
): Promise<SolanaTokenOperation | undefined> {
  const changes = new Map<string, bigint>();
  const assets: string[] = [];

  const userIndex = staticAccountKeys.findIndex((k) => k.toString() === userAddress);

  let solDiff = 0n;
  if (userIndex !== -1) {
    solDiff = BigInt(tx.postBalances[userIndex] - tx.preBalances[userIndex]);
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

  // 0 if plain transfer & not 0 if swap sol/token
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

  const totalRentPaid = newATACount * ATA_RENT_LAMPORTS;

  if (!isReceivedOnly) {
    const solExpenses = received.get(SOLANA.slug) || 0n;

    received.set(SOLANA.slug, solExpenses + BigInt(tx.fee) + totalRentPaid);
  }

  if (isSentOnly || isReceivedOnly) {
    const asset = isSentOnly ? [...sent][0][0] : [...received][0][0];

    let slug = '';
    if (asset === SOLANA.slug) {
      slug = SOLANA.slug;
    } else {
      slug = buildTokenSlug(SOLANA.chain, asset);
    }

    // if no from/to address - consider to be mint or burn(?) - use transaction initiator as fallback
    const fromAddress = isSentOnly
      ? userAddress
      : tx.postTokenBalances.find((e) => e.owner !== userAddress)?.owner || staticAccountKeys[0];
    const toAddress = !isSentOnly
      ? userAddress
      : tx.postTokenBalances.find((e) => e.owner !== userAddress)?.owner || staticAccountKeys[0];
    const amount = isSentOnly ? sent.get(asset) || 0n : received.get(asset) || 0n;

    const isIncoming = toAddress === userAddress;

    return {
      assets,
      isSwap: false,
      transfer: {
        amount,
        fromAddress,
        toAddress,
        slug,
        isIncoming,
        normalizedAddress: isIncoming ? fromAddress : toAddress,
        fee: tx.fee,
      },
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

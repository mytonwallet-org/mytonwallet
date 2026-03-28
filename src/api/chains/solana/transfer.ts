import type {
  Address,
  Base58EncodedBytes,
  Instruction,
  Transaction,
  TransactionSigner,
} from '@solana/kit';
import {
  appendTransactionMessageInstructions,
  compileTransaction,
  createNoopSigner,
  createTransactionMessage,
  getBase58Decoder,
  getBase64Decoder,
  getTransactionEncoder,
  pipe,
  setTransactionMessageFeePayerSigner,
  setTransactionMessageLifetimeUsingBlockhash,
  signTransactionMessageWithSigners,
} from '@solana/kit';

import type { ExplainedTransferFee } from '../../../util/fee/transferFee';
import type {
  ApiAnyDisplayError,
  ApiFetchEstimateDieselResult,
  ApiNetwork,
  ApiNft,
  ApiSubmitGasfullTransferOptions,
  ApiSubmitGasfullTransferResult,
  ApiSubmitGaslessTransferOptions,
  ApiSubmitGaslessTransferResult,
  ApiTransferPayload,
} from '../../types';
import type { SolanaKeyPairSigner } from './types';
import {
  type ApiCheckTransactionDraftOptions,
  type ApiCheckTransactionDraftResult,
  ApiCommonError,
  ApiTransactionDraftError,
  ApiTransactionError,
} from '../../types';

import { SOLANA_GASLESS_PAYER_ADDRESS } from '../../../config';
import { getCanopyDepthFromAccountData } from '../../../lib/solana-program/accountCompression';
import { getAddMemoInstruction } from '../../../lib/solana-program/memo';
import {
  burnCNFT,
  burnLegacyNft,
  burnMPLCoreNft,
  getMplCoreTransferInstruction,
  getPnftTransferInstruction,
  transferCNFT,
} from '../../../lib/solana-program/metaplex';
import { getTransferSolInstruction } from '../../../lib/solana-program/system';
import {
  findAssociatedTokenPda,
  getCreateAssociatedTokenIdempotentInstructionAsync,
  getTransferInstruction,
  TOKEN_PROGRAM_ADDRESS,
} from '../../../lib/solana-program/token';
import {
  findAssociatedToken2022Pda,
  getCreateAssociatedToken2022IdempotentInstructionAsync,
  getTransferCheckedInstruction,
} from '../../../lib/solana-program/token2022';
import { parseAccountId } from '../../../util/account';
import { explainApiTransferFee, getDieselTokenAmount, isDieselAvailable } from '../../../util/fee/transferFee';
import { logDebugError } from '../../../util/logs';
import { getNativeToken } from '../../../util/tokens';
import { getSolanaClient, type SolanaClient } from './util/client';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { callBackendPost } from '../../common/backend';
import { DIESEL_NOT_AVAILABLE } from '../../common/other';
import { buildTokenSlug, getTokenByAddress, getTokenBySlug } from '../../common/tokens';
import { handleServerError } from '../../errors';
import { isValidAddress } from './address';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import { ATA_RENT_LAMPORTS, SOLANA_PROGRAM_IDS } from './constants';
import { emulateTransaction } from './emulation';
import { getAssetProof } from './nfts';
import { signTransfer } from './sign';
import { getTokenBalance, getWalletBalance } from './wallet';

export const FALLBACK_FEE = 5000000n;

const MAX_BALANCE_WITH_CHECK_DIESEL = 3_000_000n; // 0.003 SOL

async function checkTransactionDraftWithGasless({
  draft,
  fee,
  realFee,
  network,
  accountId,
  address,
  tokenAddress,
  payload,
  amount,
  toAddress,
  allowGasless,
  nativeBalance,
}: {
  draft: ApiCheckTransactionDraftResult;
  fee: bigint;
  realFee: bigint;
  network: ApiNetwork;
  accountId: string;
  address: string;
  tokenAddress: string;
  payload?: ApiTransferPayload;
  amount: bigint;
  toAddress: string;
  allowGasless?: boolean;
  nativeBalance: bigint;
}) {
  let isEnoughBalanceForGasless: boolean | undefined;
  const client = getSolanaClient(network);

  const tokenBalance = await getTokenBalance(network, address, tokenAddress);

  draft.diesel = DIESEL_NOT_AVAILABLE;

  // Rebuild the same transaction with gasless flag
  const serializedB64Transaction = await buildTransaction(client, network, {
    type: 'simulation',
    amount: amount ?? 0n,
    tokenAddress,
    source: address,
    destination: toAddress,
    payload,
    isGasless: true,
  });

  if (allowGasless) {
    draft.diesel = await getDiesel({
      transaction: serializedB64Transaction,
      accountId,
      tokenAddress,
      nativeBalance,
      tokenBalance,
    });
  }

  const canTransferGasfully = nativeBalance >= fee;

  if (isDieselAvailable(draft.diesel)) {
    const dieselFee = getDieselTokenAmount(draft.diesel);

    isEnoughBalanceForGasless = tokenBalance >= dieselFee;

    if (isEnoughBalanceForGasless && (amount ?? 0n) + dieselFee > tokenBalance) {
      draft.error = ApiTransactionDraftError.InsufficientBalance;
    }
  } else {
    isEnoughBalanceForGasless = canTransferGasfully && (amount ?? 0n) <= tokenBalance;
  }

  const gaslessExplainedFee: ExplainedTransferFee = {
    isGasless: true,
    canTransferFullBalance: true,
    realFee: {
      precision: 'exact',
      terms: {
        token: draft.diesel.realFee,
        native: 0n,
      },
      nativeSum: 0n,
    },
    fullFee: {
      precision: 'exact',
      terms: {
        token: draft.diesel.realFee,
        native: 0n,
      },
      nativeSum: 0n,
    },
  };

  draft.explainedFee = isEnoughBalanceForGasless && isDieselAvailable(draft.diesel)
    ? gaslessExplainedFee
    : explainApiTransferFee({
      fee,
      realFee,
      diesel: draft.diesel,
      tokenSlug: getNativeToken('solana').slug,
    });

  return {
    draft,
    isEnoughBalanceForGasless,
  };
}

export async function checkTransactionDraft(
  options: ApiCheckTransactionDraftOptions,
): Promise<ApiCheckTransactionDraftResult> {
  const {
    accountId, amount, toAddress, tokenAddress, payload, allowGasless,
  } = options;
  const { network } = parseAccountId(accountId);

  if (payload?.type === 'comment' && payload.shouldEncrypt) {
    throw new Error('Encrypted comments are not supported in Solana');
  }

  const client = getSolanaClient(network);
  const result: ApiCheckTransactionDraftResult = {};

  try {
    if (!isValidAddress(toAddress)) {
      return { error: ApiTransactionDraftError.InvalidToAddress };
    }

    result.resolvedAddress = toAddress;

    const { address } = await fetchStoredWallet(accountId, 'solana');
    const walletBalance = await getWalletBalance(network, address);

    const serializedB64Transaction = await buildTransaction(client, network, {
      type: 'simulation',
      amount: amount ?? 0n,
      tokenAddress,
      source: address,
      destination: toAddress,
      payload,
    });

    const estimationResult = await estimateTransactionFee({ network, serializedB64Transaction });

    if ('error' in estimationResult) {
      if (estimationResult.error === ApiTransactionDraftError.InsufficientBalance) {
        if (tokenAddress) {
          const { draft, isEnoughBalanceForGasless } = await checkTransactionDraftWithGasless({
            draft: result,
            fee: FALLBACK_FEE,
            realFee: FALLBACK_FEE,
            network,
            accountId,
            address,
            tokenAddress,
            payload,
            amount: amount ?? 0n,
            toAddress,
            allowGasless,
            nativeBalance: walletBalance,
          });

          if (isEnoughBalanceForGasless) {
            return draft;
          }
        }
      }

      const fallbackResult: ApiCheckTransactionDraftResult = {
        ...result,
        explainedFee: explainApiTransferFee({
          fee: FALLBACK_FEE,
          realFee: FALLBACK_FEE,
          diesel: DIESEL_NOT_AVAILABLE,
          tokenSlug: getNativeToken('solana').slug,
        }),
      };

      return { ...fallbackResult, error: estimationResult.error };
    }

    const fee = estimationResult.fee;
    result.diesel = DIESEL_NOT_AVAILABLE;

    let isEnoughBalance: boolean;

    if (!tokenAddress) {
      isEnoughBalance = walletBalance >= fee + (amount ?? 0n);
    } else {
      isEnoughBalance = walletBalance >= fee;

      if (!isEnoughBalance) {
        const { draft, isEnoughBalanceForGasless } = await checkTransactionDraftWithGasless({
          draft: result,
          fee,
          realFee: fee,
          network,
          accountId,
          address,
          tokenAddress,
          payload,
          amount: amount ?? 0n,
          toAddress,
          nativeBalance: walletBalance,
          allowGasless,
        });

        if (isEnoughBalanceForGasless) {
          return draft;
        }
      }
    }

    if (!isEnoughBalance) {
      result.error = ApiTransactionDraftError.InsufficientBalance;
    }

    const feeForExplained = fee ?? FALLBACK_FEE;
    const tokenSlug = tokenAddress
      ? getTokenByAddress(tokenAddress, 'solana')!.slug
      : getNativeToken('solana').slug;

    result.explainedFee = explainApiTransferFee({
      fee: feeForExplained,
      realFee: feeForExplained,
      diesel: result.diesel,
      tokenSlug,
    });

    return result;
  } catch (err) {
    logDebugError('solana:checkTransactionDraft', err);
    return {
      ...handleServerError(err),
      ...result,
    };
  }
}

export async function submitGasfullTransfer(
  options: ApiSubmitGasfullTransferOptions,
): Promise<ApiSubmitGasfullTransferResult | { error: string }> {
  const {
    accountId, password = '', toAddress, amount, fee = 0n, tokenAddress, payload, noFeeCheck,
  } = options;
  const { network } = parseAccountId(accountId);

  if (payload?.type === 'comment' && payload.shouldEncrypt) {
    throw new Error('Encrypted comments are not supported in Solana');
  }

  try {
    const client = getSolanaClient(network);

    const account = await fetchStoredChainAccount(accountId, 'solana');
    if (account.type === 'ledger') throw new Error('Not supported by Ledger accounts');
    if (account.type === 'view') throw new Error('Not supported by View accounts');

    const { address } = account.byChain.solana;

    if (!noFeeCheck) {
      const walletBalance = await getWalletBalance(network, address);
      const totalTxAmount = tokenAddress ? fee : fee + amount;
      const isEnoughBalanceWithFee = walletBalance >= totalTxAmount;

      if (!isEnoughBalanceWithFee) {
        return { error: ApiTransactionError.InsufficientBalance };
      }
    }

    const privateKey = (await fetchPrivateKeyString(accountId, password, account))!;
    const signer = getSignerFromPrivateKey(network, privateKey);

    let serializedTransaction: string | undefined = undefined;

    serializedTransaction = await buildTransaction(client, network, {
      type: 'real',
      amount,
      tokenAddress,
      signer,
      destination: toAddress,
      payload,
    });

    const result = await sendSignedTransaction(serializedTransaction as Base58EncodedBytes, network);

    return { txId: result };
  } catch (err: any) {
    logDebugError('submitTransfer', err);
    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

function sendSignedDaslessTransactionToRelyer(
  transaction: string,
) {
  return callBackendPost<{
    signature: string;
  }>('/diesel/solana/signAndSend', {
    transaction,
  });
}

export async function submitGaslessTransfer(
  options: ApiSubmitGaslessTransferOptions,
): Promise<ApiSubmitGaslessTransferResult | { error: string }> {
  try {
    const {
      accountId,
      gaslessTransaction,
      password,
    } = options;

    if (!gaslessTransaction) {
      return { error: ApiTransactionError.UnsuccesfulTransfer };
    }

    const signedTransaction = await signTransfer(accountId, gaslessTransaction, password);

    if ('error' in signedTransaction) {
      return { error: ApiTransactionError.UnsuccesfulTransfer };
    }

    const { signature } = await sendSignedDaslessTransactionToRelyer(signedTransaction[0].payload.signedTx);

    return {
      txId: signature,
      msgHashForCexSwap: signature,
      localActivityParams: {
        externalMsgHashNorm: signature,
      },
    };
  } catch (err) {
    logDebugError('submitTransferWithDiesel', err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

export async function sendSignedTransaction(
  transaction: Base58EncodedBytes,
  network: ApiNetwork,
) {
  // RPC accepts b58, but client wants branded b64
  const result = await getSolanaClient(network).sendTransaction(transaction as any).send();
  return result;
}

export function fetchEstimateDiesel(accountId: string, tokenAddress: string): ApiFetchEstimateDieselResult {
  return DIESEL_NOT_AVAILABLE;
}

/**
 * Decides whether the transfer must be gasless and fetches the diesel estimate from the backend.
 */
async function getDiesel({
  transaction,
  accountId,
  tokenAddress,
  nativeBalance,
  tokenBalance,
}: {
  transaction: string;
  accountId: string;
  tokenAddress: string;
  nativeBalance: bigint;
  tokenBalance: bigint;
}): Promise<ApiFetchEstimateDieselResult> {
  const { network } = parseAccountId(accountId);

  if (network !== 'mainnet') return DIESEL_NOT_AVAILABLE;

  const storedWallet = await fetchStoredWallet(accountId, 'solana');

  const token = getTokenByAddress(tokenAddress, 'solana')!;

  if (!token.isGaslessEnabled) return DIESEL_NOT_AVAILABLE;

  if (nativeBalance >= MAX_BALANCE_WITH_CHECK_DIESEL) return DIESEL_NOT_AVAILABLE;

  try {
    const rawDiesel = await estimateDiesel(
      transaction,
      tokenAddress,
      storedWallet.address,
    );

    const diesel: ApiFetchEstimateDieselResult = {
      status: 'available',
      amount: rawDiesel.fee_in_token === undefined
        ? undefined
        : BigInt(rawDiesel.fee_in_token),
      nativeAmount: 0n,
      remainingFee: 0n,
      realFee: BigInt(rawDiesel.fee_in_token),
      transaction: rawDiesel.transaction_with_payment_instruction,
    };

    const tokenAmount = getDieselTokenAmount(diesel);

    if (tokenAmount === 0n) {
      return diesel;
    }

    const canPayDiesel = tokenBalance >= tokenAmount;

    return canPayDiesel ? diesel : DIESEL_NOT_AVAILABLE;
  } catch (err) {
    logDebugError('solana:getDiesel', err);

    return DIESEL_NOT_AVAILABLE;
  }
}

export async function estimateTransactionFee(options: {
  network: ApiNetwork;
  serializedB64Transaction: string;
}): Promise<{ fee: bigint } | { error: ApiAnyDisplayError }> {
  const emulatedTransaction = await emulateTransaction(options.serializedB64Transaction, options.network);

  // eslint-disable-next-line no-null/no-null
  if (emulatedTransaction && !emulatedTransaction.err && emulatedTransaction.fee !== null) {
    let newATACount = 0n;

    emulatedTransaction.postTokenBalances
      .forEach((post) => {
        const pre = emulatedTransaction.preTokenBalances?.find((p) => p.accountIndex === post.accountIndex);

        if (!pre) {
          // instruction may include ATA creating, so add it as additional fee (if exists)
          newATACount++;
        }
      });

    return { fee: BigInt(emulatedTransaction.fee) + newATACount * ATA_RENT_LAMPORTS };
  }

  const err = emulatedTransaction.err;

  if (err && (
    err['InsufficientFundsForRent']
    || err === 'AccountNotFound'
    || (Array.isArray(err['InstructionError']) && err['InstructionError'].some((error: any) => error.Custom === 1))
  )) {
    return { error: ApiTransactionDraftError.InsufficientBalance };
  }
  logDebugError('solana:estimateTransactionFee', options.serializedB64Transaction, emulatedTransaction.err);

  return { error: ApiCommonError.Unexpected };
}

function estimateDiesel(
  transaction: string,
  feeToken: string,
  sourceWallet: string,
) {
  return callBackendPost<{
    fee_in_lamports: number;
    fee_in_token: number;
    signer_pubkey: string;
    payment_address: string;
    transaction_with_payment_instruction: string;
  }>('/diesel/solana/estimate', {
    transaction,
    fee_token: feeToken,
    source_wallet: sourceWallet,
  });
}

async function getTokenTransferATAs(
  tokenAddress: string,
  source: string,
  destination: string,
  tokenProgram?: Address,
) {
  const findAssociatedTypedTokenPda = tokenProgram === SOLANA_PROGRAM_IDS.token[1]
    ? findAssociatedToken2022Pda
    : findAssociatedTokenPda;

  const [sourceTokenWallet] = await findAssociatedTypedTokenPda({
    mint: tokenAddress as Address,
    owner: source as Address,
    tokenProgram: tokenProgram ?? SOLANA_PROGRAM_IDS.token[0] as Address,
  });

  const [destinationTokenWallet] = await findAssociatedTypedTokenPda({
    mint: tokenAddress as Address,
    owner: destination as Address,
    tokenProgram: tokenProgram ?? SOLANA_PROGRAM_IDS.token[0] as Address,
  });

  return { sourceTokenWallet, destinationTokenWallet };
}

type TransactionOptions<T> = {
  amount: bigint;
  tokenAddress?: string;
  nfts?: ApiNft[];
  destination: string;
  payload: ApiTransferPayload | undefined;
  isNftBurn?: boolean;
  isGasless?: boolean;
} & T;

async function buildTokenTransferInstructions(
  tokenAddress: string,
  amount: bigint,
  signer: TransactionSigner<string>,
  destination: string,
  isGasless?: boolean,
) {
  const payloadInstructions: Instruction[] = [];

  const token = getTokenBySlug(buildTokenSlug('solana', tokenAddress));

  const {
    sourceTokenWallet,
    destinationTokenWallet,
  } = await getTokenTransferATAs(
    tokenAddress,
    signer.address,
    destination,
    token?.type === 'token_2022'
      ? SOLANA_PROGRAM_IDS.token[1] as Address
      : SOLANA_PROGRAM_IDS.token[0] as Address,
  );

  const createATAInstruction = token?.type === 'token_2022'
    ? getCreateAssociatedToken2022IdempotentInstructionAsync
    : getCreateAssociatedTokenIdempotentInstructionAsync;

  payloadInstructions.push(
    await createATAInstruction({
      payer: isGasless ? createNoopSigner(SOLANA_GASLESS_PAYER_ADDRESS as Address) : signer,
      mint: tokenAddress as Address,
      owner: destination as Address,
      tokenProgram: token?.type === 'token_2022'
        ? SOLANA_PROGRAM_IDS.token[1] as Address
        : SOLANA_PROGRAM_IDS.token[0] as Address,
    }),
  );

  if (token?.type === 'token_2022') {
    payloadInstructions.push(
      getTransferCheckedInstruction({
        source: sourceTokenWallet,
        destination: destinationTokenWallet,
        authority: signer,
        amount,
        decimals: token?.decimals ?? 9,
        mint: tokenAddress as Address,
      }),
    );
  } else {
    payloadInstructions.push(
      getTransferInstruction({
        source: sourceTokenWallet,
        destination: destinationTokenWallet,
        authority: signer,
        amount,
      }),
    );
  }

  return payloadInstructions;
}

async function buildNftTransferInstructions(
  network: ApiNetwork,
  nfts: ApiNft[],
  signer: TransactionSigner<string>,
  destination: string,
  isNftBurn?: boolean,
) {
  const payloadInstructions: Instruction[] = [];

  await Promise.all(nfts.map(async (nft) => {
    let transferInstruction: Instruction | undefined = undefined;

    switch (true) {
      case !!nft.compression: {
        const proof = await getAssetProof(network, nft.address);

        const canopyDepth = await getCanopyDepth(network, proof.tree_id);

        if (isNftBurn) {
          transferInstruction = await burnCNFT({
            tree: nft.compression.tree,
            owner: signer.address,
            root: proof.root,
            dataHash: nft.compression.dataHash,
            creatorHash: nft.compression.creatorHash,
            index: nft.compression.leafId,
            proof: proof.proof,
            canopyDepth,
          });
        } else {
          transferInstruction = await transferCNFT({
            tree: nft.compression.tree,
            owner: signer.address,
            newOwner: destination,
            root: proof.root,
            dataHash: nft.compression.dataHash,
            creatorHash: nft.compression.creatorHash,
            index: nft.compression.leafId,
            proof: proof.proof,
            canopyDepth,
          });
        }

        break;
      }
      case nft.interface === 'default': {
        if (isNftBurn) {
          const [sourceTokenWallet] = await findAssociatedTokenPda({
            mint: nft.address as Address,
            owner: signer.address as Address,
            tokenProgram: TOKEN_PROGRAM_ADDRESS,
          });

          transferInstruction = await burnLegacyNft({
            mint: nft.address,
            owner: signer.address,
            ownerTokenAccount: sourceTokenWallet,
            collectionAddress: nft.collectionAddress,
          });
        } else {
          const {
            sourceTokenWallet,
            destinationTokenWallet,
          } = await getTokenTransferATAs(nft.address, signer.address, destination);

          payloadInstructions.push(
            await getCreateAssociatedTokenIdempotentInstructionAsync({
              payer: signer,
              mint: nft.address as Address,
              owner: destination as Address,
            }),
          );

          transferInstruction = await getPnftTransferInstruction({
            mint: nft.address,
            source: signer.address,
            destination,
            sourceToken: sourceTokenWallet,
            destinationToken: destinationTokenWallet,
          });
        }

        break;
      }
      default: {
        if (isNftBurn) {
          transferInstruction = burnMPLCoreNft({
            asset: nft.address,
            owner: signer.address,
            collection: nft.collectionAddress,
          });
        } else {
          transferInstruction = getMplCoreTransferInstruction(
            nft.address,
            signer.address,
            destination,
            nft.collectionAddress,
          );
        }
      }
        break;
    }

    payloadInstructions.push(transferInstruction);
  }));

  return payloadInstructions;
}

export async function getCanopyDepth(network: ApiNetwork, treeAddress: string) {
  // Method for single account doesn't support base64 encoding
  const accountInfo = await (getSolanaClient(network).getMultipleAccounts(
    [treeAddress as Address],
    { encoding: 'base64' },
  )).send();

  if (!accountInfo.value?.length) return 0;

  const data = accountInfo.value[0]?.data;
  const base64String = data?.[0] ?? '';

  return getCanopyDepthFromAccountData(base64String);
}

export async function buildTransaction(
  client: SolanaClient,
  network: ApiNetwork,
  options: TransactionOptions<{
    type: 'real';
    signer: SolanaKeyPairSigner;
  }> | TransactionOptions<{
    type: 'simulation';
    source: string;
  }>,
) {
  // We don't have access to privateKey on simulation step, so we create fake signer by publicKey(address) only
  const signer = options.type === 'simulation' ? createNoopSigner(options.source as Address) : options.signer;

  const { value: latestBlockhash } = await client.getLatestBlockhash().send();

  let payloadInstructions: Instruction[] = [];

  switch (true) {
    case !!options.tokenAddress: {
      const tokenTransferInstructions = await buildTokenTransferInstructions(
        options.tokenAddress,
        options.amount,
        signer,
        options.destination,
        options.isGasless,
      );

      payloadInstructions = [...payloadInstructions, ...tokenTransferInstructions];
      break;
    }

    case !!options.nfts: {
      const nftTransferInstructions = await buildNftTransferInstructions(
        network,
        options.nfts,
        signer,
        options.destination,
        options.isNftBurn,
      );
      payloadInstructions = [...payloadInstructions, ...nftTransferInstructions];

      break;
    }

    default: {
      payloadInstructions.push(
        getTransferSolInstruction({
          source: signer,
          destination: options.destination as Address,
          amount: options.amount,
        }),
      );
      break;
    }
  }

  if (options.payload?.type === 'comment') {
    payloadInstructions.unshift(
      getAddMemoInstruction({
        memo: options.payload.text,
      }),
    );
  }

  const transactionMessage = pipe(
    createTransactionMessage({ version: 0 }),
    (m) => setTransactionMessageFeePayerSigner(
      options.isGasless ? createNoopSigner(SOLANA_GASLESS_PAYER_ADDRESS as Address) : signer,
      m,
    ),
    (m) => setTransactionMessageLifetimeUsingBlockhash(latestBlockhash, m),
    (m) => appendTransactionMessageInstructions(
      payloadInstructions,
      m,
    ),
  );

  let compiledTransaction: Transaction | undefined = undefined;

  if (options.type === 'real') {
    compiledTransaction = await signTransactionMessageWithSigners(transactionMessage);
  } else {
    compiledTransaction = compileTransaction(transactionMessage);
  }

  const signedBytes = getTransactionEncoder().encode(compiledTransaction);

  const decoder = options.type === 'real' ? getBase58Decoder() : getBase64Decoder();

  return decoder.decode(signedBytes);
}

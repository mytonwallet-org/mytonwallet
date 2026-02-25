import type {
  Address,
  Base58EncodedBytes,
  Instruction,
  Transaction,
  TransactionMessageBytesBase64,
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

import type {
  ApiFetchEstimateDieselResult,
  ApiNetwork,
  ApiNft,
  ApiSubmitGasfullTransferOptions,
  ApiSubmitGasfullTransferResult,
  ApiTransferPayload,
} from '../../types';
import type { SolanaKeyPairSigner } from './types';
import {
  type ApiCheckTransactionDraftOptions,
  type ApiCheckTransactionDraftResult,
  ApiTransactionDraftError,
  ApiTransactionError,
} from '../../types';

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
import { logDebugError } from '../../../util/logs';
import { getSolanaClient, type SolanaClient } from './util/client';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { DIESEL_NOT_AVAILABLE } from '../../common/other';
import { buildTokenSlug, getTokenBySlug } from '../../common/tokens';
import { handleServerError } from '../../errors';
import { isValidAddress } from './address';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import { SOLANA_PROGRAM_IDS } from './constants';
import { getAssetProof } from './nfts';
import { getWalletBalance } from './wallet';

export async function checkTransactionDraft(
  options: ApiCheckTransactionDraftOptions,
): Promise<ApiCheckTransactionDraftResult> {
  const {
    accountId, amount, toAddress, tokenAddress, payload,
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

    let serializedB64Transaction: string | undefined = undefined;

    serializedB64Transaction = await buildTransaction(client, network, {
      type: 'simulation',
      amount: amount ?? 0n,
      tokenAddress,
      source: address,
      destination: toAddress,
      payload,
    });

    const fee = await estimateTransactionFee(client, { network, serializedB64Transaction });

    result.fee = fee;
    result.realFee = fee;

    const totalTxAmount = tokenAddress ? fee : (amount ?? 0n) + fee;
    const isEnoughBalanceWithFee = walletBalance >= totalTxAmount;

    if (!isEnoughBalanceWithFee) {
      result.error = ApiTransactionDraftError.InsufficientBalance;
    }

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

export async function estimateTransactionFee(client: SolanaClient, options: {
  network: ApiNetwork;
  serializedB64Transaction: string;
}) {
  const feeResponse = await client.getFeeForMessage(
    options.serializedB64Transaction as TransactionMessageBytesBase64,
  ).send();

  if (feeResponse.value) {
    const feeInLamports = feeResponse.value;
    return BigInt(feeInLamports);
  }

  return 0n;
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
} & T;

async function buildTokenTransferInstructions(
  tokenAddress: string,
  amount: bigint,
  signer: TransactionSigner<string>,
  destination: string,
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
      payer: signer,
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
    (m) => setTransactionMessageFeePayerSigner(signer, m),
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

  let serializedTx = '';

  if (options.type === 'real') {
    // sendTransaction accepts base58 only, but autoencoder returns base64, so encode manually
    const signedBytes = getTransactionEncoder().encode(compiledTransaction);

    const base58Encoder = getBase58Decoder();
    serializedTx = base58Encoder.decode(signedBytes);
  } else {
    // getFeeForMessage accepts only message part (w/o headers) in base64, so encode manually
    serializedTx = getBase64Decoder().decode(compiledTransaction.messageBytes);
  }

  return serializedTx;
}

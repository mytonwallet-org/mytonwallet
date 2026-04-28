import type { TransactionRequest } from 'ethers';
import { Interface } from 'ethers';

import type {
  ApiCheckTransactionDraftOptions,
  ApiCheckTransactionDraftResult,
  ApiNetwork,
  ApiNft,
  ApiSubmitGasfullTransferOptions,
  ApiSubmitGasfullTransferResult,
  ApiTransferPayload,
  EVMChain,
} from '../../types';
import { ApiCommonError, ApiTransactionDraftError, ApiTransactionError } from '../../types';

import { parseAccountId } from '../../../util/account';
import { getChainConfig } from '../../../util/chain';
import { explainApiTransferFee } from '../../../util/fee/transferFee';
import { logDebugError } from '../../../util/logs';
import { type EvmProvider, getEvmProvider } from './util/client';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { handleServerError } from '../../errors';
import { isValidAddress } from './address';
import { fetchPrivateKeyString, getSignerFromPrivateKey } from './auth';
import { getErc20Balance, getWalletBalance } from './wallet';

const ERC20_TRANSFER_ABI = ['function transfer(address to, uint256 amount) returns (bool)'];
const ERC721_TRANSFER_ABI = ['function safeTransferFrom(address from, address to, uint256 tokenId)'];
const ERC1155_TRANSFER_ABI = [
  'function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes data)',
];
const erc20Interface = new Interface(ERC20_TRANSFER_ABI);
const erc721Interface = new Interface(ERC721_TRANSFER_ABI);
const erc1155Interface = new Interface(ERC1155_TRANSFER_ABI);

export async function checkTransactionDraft(
  chain: EVMChain,
  options: ApiCheckTransactionDraftOptions,
): Promise<ApiCheckTransactionDraftResult> {
  const {
    accountId, amount, toAddress, tokenAddress, payload,
  } = options;
  const { network } = parseAccountId(accountId);

  const provider = getEvmProvider(network, chain);
  const result: ApiCheckTransactionDraftResult = {};

  try {
    if (!isValidAddress(toAddress)) {
      return { error: ApiTransactionDraftError.InvalidToAddress };
    }

    result.resolvedAddress = toAddress;

    const { address } = await fetchStoredWallet(accountId, chain);

    const transaction = buildTransaction({
      from: address,
      to: toAddress,
      amount: amount ?? 0n,
      tokenAddress,
      payload,
    });

    const [nativeBalance, fee] = await Promise.all([
      getWalletBalance(chain, network, address),
      estimateEvmFee(provider, transaction),
    ]);

    const nativeTokenSlug = getChainConfig(chain).nativeToken.slug;

    result.explainedFee = explainApiTransferFee({
      fee,
      realFee: fee,
      tokenSlug: nativeTokenSlug,
    });

    if (amount !== undefined) {
      if (tokenAddress) {
        const [tokenBalance] = await Promise.all([
          getErc20Balance(network, chain, address, tokenAddress),
        ]);

        const isEnoughNative = nativeBalance >= fee;
        const isEnoughToken = tokenBalance >= amount;

        if (!isEnoughNative || !isEnoughToken) {
          result.error = ApiTransactionDraftError.InsufficientBalance;
        }
      } else {
        const isEnoughNative = nativeBalance >= amount + fee;

        if (!isEnoughNative) {
          result.error = ApiTransactionDraftError.InsufficientBalance;
        }
      }
    }

    return result;
  } catch (err) {
    logDebugError(`evm:${chain}:checkTransactionDraft`, err);

    return {
      ...handleServerError(err),
      ...result,
    };
  }
}

export function buildTransaction(options: {
  from: string;
  to: string;
  amount: bigint;
  tokenAddress?: string;
  payload?: ApiTransferPayload;
  nft?: ApiNft;
}): TransactionRequest {
  const {
    from, to, amount, tokenAddress, payload, nft,
  } = options;

  if (nft) {
    const [contractAddress, tokenId] = nft.address.split('/');

    if (nft.interface === 'ERC1155') {
      return {
        from,
        to: contractAddress,
        value: 0n,
        data: erc1155Interface.encodeFunctionData('safeTransferFrom', [from, to, BigInt(tokenId), 1n, '0x']),
      };
    }

    return {
      from,
      to: contractAddress,
      value: 0n,
      data: erc721Interface.encodeFunctionData('safeTransferFrom', [from, to, BigInt(tokenId)]),
    };
  }

  if (tokenAddress) {
    const data = erc20Interface.encodeFunctionData('transfer', [to, amount]);

    return {
      from,
      to: tokenAddress,
      value: 0n,
      data,
    };
  }

  const data = encodePayload(payload);

  return {
    from,
    to,
    value: amount,
    ...(data !== undefined && { data }),
  };
}

export async function submitGasfullTransfer(
  chain: EVMChain,
  options: ApiSubmitGasfullTransferOptions,
): Promise<ApiSubmitGasfullTransferResult | { error: string }> {
  const {
    accountId, password = '', toAddress, amount, fee = 0n, tokenAddress, payload, noFeeCheck,
  } = options;

  const { network } = parseAccountId(accountId);

  try {
    const account = await fetchStoredChainAccount(accountId, chain);

    if (account.type === 'ledger') throw new Error('Not supported by Ledger accounts');
    if (account.type === 'view') throw new Error('Not supported by View accounts');

    const { address } = account.byChain[chain];
    const provider = getEvmProvider(network, chain);

    if (!noFeeCheck) {
      const nativeBalance = await getWalletBalance(chain, network, address);
      const requiredNative = tokenAddress ? fee : fee + amount;

      if (nativeBalance < requiredNative) {
        return { error: ApiTransactionError.InsufficientBalance };
      }
    }

    const privateKey = await fetchPrivateKeyString(chain, accountId, password, account);

    if (!privateKey) {
      return { error: ApiCommonError.InvalidPassword };
    }

    const signer = getSignerFromPrivateKey(network, privateKey).connect(provider);

    const transaction = buildTransaction({
      from: address,
      to: toAddress,
      amount,
      tokenAddress,
      payload,
    });

    const response = await signer.sendTransaction(transaction);

    return { txId: response.hash };
  } catch (err) {
    logDebugError(`evm:${chain}:submitGasfullTransfer`, err);

    return { error: ApiTransactionError.UnsuccesfulTransfer };
  }
}

function encodePayload(payload: ApiTransferPayload | undefined): string | undefined {
  if (!payload) return undefined;

  if (payload.type === 'comment') {
    return `0x${Buffer.from(payload.text, 'utf-8').toString('hex')}`;
  }
  if (payload.type === 'binary') {
    return `0x${Buffer.from(payload.data).toString('hex')}`;
  }
  if (payload.type === 'base64') {
    return `0x${Buffer.from(payload.data, 'base64').toString('hex')}`;
  }

  return undefined;
}

export async function estimateEvmFee(provider: EvmProvider, txRequest: TransactionRequest): Promise<bigint> {
  const [gasLimit, feeData] = await Promise.all([
    provider.estimateGas(txRequest),
    provider.getFeeData(),
  ]);

  // Prefer EIP-1559 maxFeePerGas for a conservative upper-bound estimate or use fallback to legacy gasPrice.
  const gasPrice = feeData.maxFeePerGas ?? feeData.gasPrice ?? 0n;

  return gasLimit * gasPrice;
}

export async function sendSignedTransaction(
  chain: EVMChain,
  serializedTransaction: string,
  network: ApiNetwork,
): Promise<string> {
  const provider = getEvmProvider(network, chain);

  const normalized = serializedTransaction.startsWith('0x') ? serializedTransaction : `0x${serializedTransaction}`;

  const response = await provider.broadcastTransaction(normalized);

  return response.hash;
}

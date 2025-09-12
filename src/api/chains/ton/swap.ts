import type {
  ApiNetwork,
  ApiSwapBuildRequest,
  ApiTokensTransferPayload,
} from '../../types';
import type { TonTransferParams } from './types';

import { DIESEL_ADDRESS, SWAP_FEE_ADDRESS, TONCOIN } from '../../../config';
import { assert as originalAssert } from '../../../util/assert';
import { fromDecimal } from '../../../util/decimals';
import { isTokenTransferPayload } from '../../../util/ton/transfer';
import { parsePayloadBase64 } from './util/metadata';
import { resolveTokenWalletAddress, toBase64Address } from './util/tonCore';
import { getTokenByAddress } from '../../common/tokens';
import { getContractInfo } from './wallet';

const FEE_ADDRESSES = [SWAP_FEE_ADDRESS, DIESEL_ADDRESS];
const MAX_NETWORK_FEE = 3600000000n; // 3.6 TON = 0.3 TON * 3 * 4 - when 4 splits with 3 hops per split on Stonfi

export async function validateDexSwapTransfers(
  network: ApiNetwork,
  address: string,
  request: ApiSwapBuildRequest,
  transfers: TonTransferParams[],
) {
  const assert = (condition: boolean, message: string) => {
    originalAssert(condition, message, {
      network, address, request, transfers,
    });
  };

  assert(transfers.length <= 2, 'Too many transfers');

  const [mainTransfer, feeTransfer] = transfers as [TonTransferParams, TonTransferParams | undefined];

  if (request.from === TONCOIN.symbol) {
    const maxAmount = fromDecimal(request.fromAmount) + fromDecimal(request.ourFee) + MAX_NETWORK_FEE;
    const { isSwapAllowed, codeHash } = await getContractInfo(network, mainTransfer.toAddress);

    assert(!!isSwapAllowed, `Not allowed swap contract: ${codeHash}`);
    assert(mainTransfer.amount <= maxAmount, 'Main transfer amount is too big');

    if (feeTransfer) {
      assert(feeTransfer.amount <= mainTransfer.amount, 'Fee transfer amount is too big');
      assert(feeTransfer.amount + mainTransfer.amount < maxAmount, 'Total amount is too big');
      assert(FEE_ADDRESSES.includes(toBase64Address(feeTransfer.toAddress, false)), 'Unexpected fee transfer address');
    }
  } else {
    const token = getTokenByAddress(request.from);
    assert(!!token, 'Unknown "from" token');

    const maxAmount = fromDecimal(request.fromAmount, token.decimals)
      + fromDecimal(request.ourFee ?? 0, token.decimals)
      + fromDecimal(request.dieselFee ?? 0, token.decimals);
    const maxTonAmount = MAX_NETWORK_FEE;

    const walletAddress = await resolveTokenWalletAddress(network, address, token.tokenAddress!);
    const parsedPayload = await parsePayloadBase64(network, mainTransfer.toAddress, mainTransfer.payload as string);

    assert(mainTransfer.toAddress === walletAddress, 'Main transfer address is not the token wallet address');
    assert(isTokenTransferPayload(parsedPayload), 'Main transfer payload is not a token transfer');

    const { amount: tokenAmount, destination } = parsedPayload as ApiTokensTransferPayload;
    assert(tokenAmount <= maxAmount, 'Main transfer token amount is too big');

    assert(mainTransfer.amount < maxTonAmount, 'Main transfer TON amount is too big');

    const { isSwapAllowed } = await getContractInfo(network, destination);

    assert(!!isSwapAllowed, 'Main transfer destination is not a swap smart contract');

    if (feeTransfer) {
      const feePayload = await parsePayloadBase64(network, feeTransfer.toAddress, feeTransfer.payload as string);

      assert(feeTransfer.amount + mainTransfer.amount < maxTonAmount, 'Total TON amount is too big');
      assert(feeTransfer.toAddress === walletAddress, 'Fee transfer address is not the token wallet address');
      assert(isTokenTransferPayload(feePayload), 'Fee transfer payload is not a token transfer');

      const { amount: tokenFeeAmount, destination: feeDestination } = feePayload as ApiTokensTransferPayload;

      assert(tokenAmount + tokenFeeAmount <= maxAmount, 'Total token amount is too big');
      assert(FEE_ADDRESSES.includes(toBase64Address(feeDestination, false)), 'Unexpected fee transfer destination');
    }
  }
}

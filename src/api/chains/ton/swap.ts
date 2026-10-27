import type { Address, Slice } from '@ton/core';
import { Cell } from '@ton/core';

import type {
  ApiAccountWithChain,
  ApiAnyDisplayError,
  ApiNetwork,
  ApiSwapActivity,
  ApiSwapBuildTransactionRequest,
  ApiSwapTransfer,
  ApiTokensTransferPayload,
  OnApiUpdate,
} from '../../types';
import type {
  ApiBuildOnchainSwapTransferOptions,
  ApiBuildOnchainSwapTransferResult,
  ApiSubmitOnchainSwapTransferOptions,
  ApiSubmitOnchainSwapTransferResult,
} from '../../types/swap';
import type { EmulationResponse } from './toncenter/emulation';
import type { TonTransferParams } from './types';
import { URANUS_PRICE_DRIFT_ERROR } from '../../types/swap';

import { DEFAULT_OUR_SWAP_FEE, DIESEL_ADDRESS, SWAP_FEE_ADDRESS } from '../../../config';
import { Big } from '../../../lib/big.js';
import { parseAccountId } from '../../../util/account';
import { assert as originalAssert } from '../../../util/assert';
import { fromDecimal } from '../../../util/decimals';
import { omitUndefined } from '../../../util/iteratees';
import { isSlippageValid } from '../../../util/swap/slippage';
import { getMaxMessagesInTransaction, isTokenTransferPayload } from '../../../util/ton/transfer';
import { parseKnownTokenTransferPayloadSlice } from './util/metadata';
import { getSigner } from './util/signer';
import { areAddressesEqual, resolveTokenWalletAddress, toBase64Address } from './util/tonCore';
import { fetchStoredChainAccount, fetchStoredWallet } from '../../common/accounts';
import { patchSwapItem } from '../../common/swap';
import { getTokenByAddress } from '../../common/tokens';
import { callHook } from '../../hooks';
import { DEFAULT_DECIMALS, OpCode } from './constants';
import { insertMintlessPayload } from './tokens';
import { checkMultiTransactionDraft, submitMultiTransferWithMfa } from './transfer';
import { UranusPriceDriftError, validateUranusBuyEmulation } from './uranusBuyEmulation';
import { validateUranusSellEmulation } from './uranusSellEmulation';
import { getContractInfo } from './wallet';

async function getContractInfos(network: ApiNetwork, addresses: string[]) {
  // Can't be done via Toncenter `/api/v3/accountStates` endpoint because it serializes code cells
  // differently, resulting in `codeHashOld` mismatch
  const result: Record<string, Awaited<ReturnType<typeof getContractInfo>>> = {};
  const infos = await Promise.all(addresses.map((address) => getContractInfo(network, address)));
  for (let i = 0; i < addresses.length; i++) {
    result[addresses[i]] = infos[i];
  }
  return result;
}

const FEE_ADDRESSES = [SWAP_FEE_ADDRESS, DIESEL_ADDRESS];
const MAX_NETWORK_FEE = 3600000000n; // 3.6 TON = 0.3 TON * 3 * 4 - when 4 splits with 3 hops per split on Stonfi
const MAX_SPLITS = 4; // Backend configuration

const DEDUST_URANUS_MEMEPAD_BUY_OPCODE = 0x94826557;
const DEDUST_URANUS_MEMEPAD_BUY_MAX_GAS = 200000000n; // 0.2 TON
const DEDUST_URANUS_MEMEPAD_SELL_OPCODE = 0xb7459e2c;
// Each independently verified master class derives a wallet with its own code version.
const DEDUST_URANUS_MEMEPAD_WALLET_HASHES: Record<string, string> = {
  '722d37be518ee0d4b6714077727ed60724bf379e8f1479c220b853d1af3cf00d':
    '21097ae6d15af88099db08eb49b71df933905c86a09c3823fd5f0e1a8b6acdae',
  '1e4f8fcaabefdbbb9b397372d9f021511c272eda2b492ca2d33b817bc3251afe':
    'e2da88070dcf9d1b2ed4ab9079b8c473625bf320f38423ed86ee03ef5c326858',
  f4ba4ebd2678dde0c750564bd22ee0876aa2f39a1e8d3aacb606ba0c39a71d9a:
    'e2da88070dcf9d1b2ed4ab9079b8c473625bf320f38423ed86ee03ef5c326858',
  '7369f9b9f570e1bf78b0dc9d52cbab7ce21a4f000ee858ea6e81d43232c1a2d6':
    '0621a91b5f2762f0ca34dc73b1b93186542b6e3dd89ab8f71ba91c2c8a17b6f2',
};
const DEDUST_URANUS_MEMEPAD_SELL_MAX_GAS = 100000000n; // Total attachment: live builds use 0.05 TON per message.

type SwapTransferAssert = (condition: boolean, message: string) => void;

function assertPayloadFullyRead(slice: Slice, assert: SwapTransferAssert) {
  assert(slice.remainingBits === 0 && slice.remainingRefs === 0, 'Unexpected extra data in swap payload');
}

function validateDedustUranusMemepadBuyTransfer(
  transfer: TonTransferParams,
  address: string,
  request: ApiSwapBuildTransactionRequest,
  assert: SwapTransferAssert,
) {
  assert(!transfer.stateInit, 'Uranus memepad buy transfer must not have state init');
  assert(!!transfer.payload, 'Uranus memepad buy transfer payload is missing');
  // `to` comes from the token selected in the UI, not the backend's build response or route/pool address.
  assert(areAddressesEqual(transfer.toAddress, request.to), 'Uranus memepad buy destination is not the selected token');
  assert(!!request.toMinAmount, 'Uranus memepad buy minimum amount out is missing');
  assert(!!request.toAmount, 'Uranus memepad buy quoted amount out is missing');
  assert(isSlippageValid(request.slippage), 'Uranus memepad buy slippage is invalid');

  let slice: Slice;
  let opcode: number;
  let amount: bigint;
  let minimalAmountOut: bigint;
  let excessesTo: Address;
  let partnerConfig: Cell | null;
  let referrerConfig: Cell | null;

  try {
    slice = transfer.payload!.beginParse();
    opcode = slice.loadUint(32);
  } catch {
    assert(false, 'Uranus memepad buy transfer payload is invalid');
    return;
  }

  assert(opcode === DEDUST_URANUS_MEMEPAD_BUY_OPCODE, `Unexpected Uranus memepad buy opcode: ${opcode}`);

  try {
    slice.loadUintBig(64); // query_id
    amount = slice.loadCoins();
    minimalAmountOut = slice.loadCoins();
    excessesTo = slice.loadAddress();
    partnerConfig = slice.loadMaybeRef();
    referrerConfig = slice.loadMaybeRef();
  } catch {
    assert(false, 'Uranus memepad buy transfer payload is invalid');
    return;
  }

  assertPayloadFullyRead(slice, assert);

  // The fee transfer is checked separately against the client-owned fee destination.
  // Both transfers together must spend exactly the user's gross swap input.
  assert(transfer.amount >= amount, 'Uranus memepad buy transfer value is smaller than buy amount');
  assert(
    transfer.amount <= amount + DEDUST_URANUS_MEMEPAD_BUY_MAX_GAS,
    'Uranus memepad buy gas amount is too big',
  );
  // The backend supplies both quote amounts. Combine the quote held in UI state with the user's
  // slippage setting so a poisoned toMinAmount alone cannot lower the floor.
  // This cannot establish a fair exchange rate if the backend also poisons the displayed quote.
  const quotedAmountOut = Big(request.toAmount!);
  assert(quotedAmountOut.gt(0), 'Uranus memepad buy quoted amount out must be positive');
  const minOutFromQuote = fromDecimal(
    quotedAmountOut.mul(Big(100).minus(request.slippage!)).div(100).toString(),
    DEFAULT_DECIMALS,
  );
  assert(minOutFromQuote > 0n, 'Uranus memepad buy quoted minimum amount out is too small');
  assert(
    minimalAmountOut >= minOutFromQuote,
    'Uranus memepad buy minimum amount out is below the quoted output and slippage',
  );
  assert(
    minimalAmountOut >= fromDecimal(request.toMinAmount!, DEFAULT_DECIMALS),
    'Uranus memepad buy minimum amount out is too low',
  );
  assert(areAddressesEqual(excessesTo, address), 'Uranus memepad buy excesses address is not the wallet address');
  assert(!partnerConfig, 'Uranus memepad buy partner config is not allowed');
  assert(!referrerConfig, 'Uranus memepad buy referrer config is not allowed');
  return { amount, minimalAmountOut };
}

function validateDedustUranusMemepadSellTransfer(
  transfer: TonTransferParams,
  feeTransfer: TonTransferParams | undefined,
  address: string,
  request: ApiSwapBuildTransactionRequest,
  tokenDecimals: number,
  assert: SwapTransferAssert,
) {
  assert(!transfer.stateInit && !!transfer.payload, 'Uranus sell payload or state init is invalid');
  assert(transfer.amount > 0n && transfer.amount <= DEDUST_URANUS_MEMEPAD_SELL_MAX_GAS,
    'Uranus sell gas amount is invalid');
  assert(transfer.amount + (feeTransfer?.amount ?? 0n) <= DEDUST_URANUS_MEMEPAD_SELL_MAX_GAS,
    'Uranus sell total gas amount is invalid');
  assert(!!request.toAmount && !!request.toMinAmount && isSlippageValid(request.slippage),
    'Uranus sell quote or slippage is invalid');
  let amount: bigint;
  let minimalAmountOut: bigint;
  let excessesTo: Address | null;
  let partnerConfig: Cell | null;
  let referrerConfig: Cell | null;
  try {
    const slice = transfer.payload!.beginParse();
    assert(slice.loadUint(32) === DEDUST_URANUS_MEMEPAD_SELL_OPCODE, 'Uranus sell opcode is invalid');
    slice.loadUintBig(64);
    amount = slice.loadCoins();
    minimalAmountOut = slice.loadCoins();
    excessesTo = slice.loadMaybeAddress();
    partnerConfig = slice.loadMaybeRef();
    referrerConfig = slice.loadMaybeRef();
    assertPayloadFullyRead(slice, assert);
  } catch {
    assert(false, 'Uranus sell payload is invalid');
    return;
  }
  assert(amount > 0n, 'Uranus sell amount must be positive');
  assert(!!excessesTo && areAddressesEqual(excessesTo, address), 'Uranus sell excesses address is invalid');
  assert(!partnerConfig && !referrerConfig, 'Uranus sell attribution config is not allowed');
  assert(Big(request.dieselFee ?? 0).eq(0), 'Uranus sell does not support diesel fee');

  const grossAmount = fromDecimal(request.fromAmount, tokenDecimals);
  const quotedFee = fromDecimal(request.ourFee ?? '0', tokenDecimals);
  const maxFee = BigInt(Big(grossAmount.toString()).mul(DEFAULT_OUR_SWAP_FEE).div(100).round(0, 0).toString());
  assert(quotedFee >= 0n && quotedFee <= maxFee, 'Uranus sell fee exceeds the client cap');
  assert(amount + quotedFee === grossAmount, 'Uranus sell amount plus fee does not match request amount');
  if (quotedFee === 0n) {
    assert(!feeTransfer, 'Uranus zero-fee sell must not have a fee transfer');
  } else {
    assert(!!feeTransfer && !feeTransfer.stateInit && !!feeTransfer.payload,
      'Uranus sell fee transfer is invalid');
    assert(feeTransfer!.amount > 0n && feeTransfer!.amount <= DEDUST_URANUS_MEMEPAD_SELL_MAX_GAS,
      'Uranus sell fee gas amount is invalid');
    try {
      const slice = feeTransfer!.payload!.beginParse();
      assert(slice.loadUint(32) === 0x0f8a7ea5, 'Uranus sell fee opcode is invalid');
      slice.loadUintBig(64);
      assert(slice.loadCoins() === quotedFee, 'Uranus sell fee amount does not match quote');
      assert(areAddressesEqual(slice.loadAddress(), SWAP_FEE_ADDRESS), 'Uranus sell fee destination is invalid');
      assert(areAddressesEqual(slice.loadAddress(), address), 'Uranus sell fee response address is invalid');
      assert(!slice.loadMaybeRef(), 'Uranus sell fee custom payload is not allowed');
      assert(slice.loadCoins() === 1n, 'Uranus sell fee forward amount is invalid');
      assert(slice.loadBit() && slice.remainingRefs === 1, 'Uranus sell fee forward payload is invalid');
      const forward = slice.loadRef().beginParse();
      assert(forward.loadUint(32) === Number(OpCode.OurFee), 'Uranus sell fee payload opcode is invalid');
      assertPayloadFullyRead(forward, assert);
      assertPayloadFullyRead(slice, assert);
    } catch {
      assert(false, 'Uranus sell fee payload is invalid');
    }
  }

  const quoteFloor = fromDecimal(
    Big(request.toAmount!).mul(Big(100).minus(request.slippage!)).div(100).toString(),
  );
  assert(quoteFloor > 0n && minimalAmountOut >= quoteFloor
    && minimalAmountOut >= fromDecimal(request.toMinAmount!),
  'Uranus sell minimum amount out is below the quote');
  return minimalAmountOut;
}

export async function validateDexSwapTransfers(
  network: ApiNetwork,
  address: string,
  request: ApiSwapBuildTransactionRequest,
  transfers: TonTransferParams[],
  account: ApiAccountWithChain<'ton'>,
) {
  let uranusMinimalAmountOut: bigint | undefined;
  let uranusBuyAmount: bigint | undefined;
  const hasFeeTransfer = Big(request.ourFee ?? 0).gt(0) || Big(request.dieselFee ?? 0).gt(0);
  const feeTransfer = hasFeeTransfer ? transfers.at(-1) : undefined;
  const mainTransfers = feeTransfer ? transfers.slice(0, -1) : transfers;
  const maxMessages = getMaxMessagesInTransaction(account);
  const maxSplits = Math.min(maxMessages - (feeTransfer ? 1 : 0), MAX_SPLITS);

  const assert = (condition: boolean, message: string) => {
    originalAssert(condition, message, {
      network, address, request, transfers, maxMessages, maxSplits,
    });
  };

  assert(mainTransfers.length <= maxSplits, 'Too many main transfers');

  // FIXME: TON renaming
  if (request.from === 'TON') {
    const maxAmount = fromDecimal(request.fromAmount) + MAX_NETWORK_FEE;
    let sumAmount = 0n;

    const contractInfos = await getContractInfos(network, mainTransfers.map((transfer) => transfer.toAddress));

    for (let i = 0; i < mainTransfers.length; i++) {
      const mainTransfer = mainTransfers[i];
      sumAmount += mainTransfer.amount;
      const { isSwapAllowed, codeHash, contractInfo } = contractInfos[mainTransfer.toAddress];
      assert(
        !!isSwapAllowed,
        `Main transfer ${i + 1}/${mainTransfers.length} is not to a swap contract: `
        + `toAddress=${mainTransfer.toAddress}, codeHash=${codeHash}`,
      );

      if (contractInfo?.nativeSwapPayload === 'dedustUranusMemepadBuy') {
        assert(mainTransfers.length === 1, 'Uranus memepad buy must have exactly one main transfer');
        const buy = validateDedustUranusMemepadBuyTransfer(mainTransfer, address, request, assert);
        uranusBuyAmount = buy!.amount;
        uranusMinimalAmountOut = buy!.minimalAmountOut;
      }
    }

    assert(sumAmount <= maxAmount, 'Main transfers amount is too big');

    if (feeTransfer) {
      assert(feeTransfer.amount <= sumAmount, 'Fee transfer amount is bigger than main transfers amount');
      assert(feeTransfer.amount + sumAmount < maxAmount, 'Total amount is too big');
      assert(FEE_ADDRESSES.includes(toBase64Address(feeTransfer.toAddress, false)), 'Unexpected fee transfer address');
    }
    if (uranusMinimalAmountOut !== undefined) {
      const grossAmount = fromDecimal(request.fromAmount);
      const quotedFee = fromDecimal(request.ourFee ?? '0');
      // Native Uranus buys have no source-token diesel fee. A third fee would break principal+MTW fee=X.
      assert(Big(request.dieselFee ?? 0).eq(0), 'Uranus memepad buy does not support diesel fee');
      // This is the shipped client's maximum fee policy; backend loyalty discounts may be lower.
      const maxFee = BigInt(Big(grossAmount.toString()).mul(DEFAULT_OUR_SWAP_FEE).div(100).round(0, 0).toString());
      assert(quotedFee >= 0n && quotedFee <= maxFee, 'Uranus memepad fee exceeds the client cap');
      if (quotedFee === 0n) {
        assert(!feeTransfer && transfers.length === 1, 'Uranus zero-fee buy must not have a fee transfer');
      } else {
        assert(!!feeTransfer && transfers.length === 2, 'Uranus memepad buy requires a fee transfer');
        assert(!feeTransfer!.stateInit && !!feeTransfer!.payload, 'Uranus memepad fee transfer payload is invalid');
        const feePayload = feeTransfer!.payload!.beginParse();
        assert(feePayload.remainingBits >= 32 && feePayload.loadUint(32) === Number(OpCode.OurFee),
          'Uranus memepad fee transfer payload is invalid');
        assertPayloadFullyRead(feePayload, assert);
        assert(
          areAddressesEqual(feeTransfer!.toAddress, SWAP_FEE_ADDRESS),
          'Uranus memepad fee destination is invalid',
        );
        assert(feeTransfer!.amount === quotedFee, 'Uranus memepad fee does not match quote');
      }
      assert(uranusBuyAmount! > 0n && uranusBuyAmount! + quotedFee === grossAmount,
        'Uranus memepad buy amount plus fee does not match request amount');
    }
    return uranusMinimalAmountOut;
  } else {
    const token = getTokenByAddress(request.from)!;
    assert(!!token, 'Unknown "from" token');

    const maxAmount = fromDecimal(request.fromAmount, token.decimals);
    const maxTonAmount = MAX_NETWORK_FEE;
    const tokenAddress = token.tokenAddress!;

    const walletAddress = await resolveTokenWalletAddress(network, address, tokenAddress);
    const isDirectUranusSell = request.to === 'TON' && mainTransfers.length === 1
      && !!mainTransfers[0].payload
      && mainTransfers[0].payload.beginParse().remainingBits >= 32
      && mainTransfers[0].payload.beginParse().preloadUint(32) === DEDUST_URANUS_MEMEPAD_SELL_OPCODE;
    if (isDirectUranusSell) {
      assert(transfers.length === (feeTransfer ? 2 : 1), 'Uranus sell has unexpected transfers');
      assert(areAddressesEqual(mainTransfers[0].toAddress, walletAddress),
        'Uranus sell destination is not the signer jetton wallet');
      if (feeTransfer) {
        assert(areAddressesEqual(feeTransfer.toAddress, walletAddress),
          'Uranus sell fee transfer is not to the signer jetton wallet');
      }
      const [masterInfo, walletInfo] = await Promise.all([
        getContractInfo(network, tokenAddress), getContractInfo(network, walletAddress),
      ]);
      assert(!!masterInfo.isInitialized && !!masterInfo.isSwapAllowed
        && masterInfo.contractInfo?.nativeSwapPayload === 'dedustUranusMemepadBuy',
      'Uranus sell master code hash is not trusted');
      assert(!!masterInfo.codeHash
        && !!walletInfo.isInitialized
        && walletInfo.codeHash === DEDUST_URANUS_MEMEPAD_WALLET_HASHES[masterInfo.codeHash],
      'Uranus sell wallet code hash is not trusted');
      return validateDedustUranusMemepadSellTransfer(
        mainTransfers[0], feeTransfer, address, request, token.decimals, assert,
      );
    }
    let sumTokenAmount = 0n;
    let sumTonAmount = 0n;

    mainTransfers.forEach((mainTransfer, index) => {
      assert(
        mainTransfer.toAddress === walletAddress,
        `Main transfer ${index + 1}/${mainTransfers.length} address is not the token wallet address`,
      );
    });

    const parsedPayloads = mainTransfers.map((transfer) => transfer.payload
      && parseKnownTokenTransferPayloadSlice(network, transfer.payload.beginParse(), tokenAddress));
    const contractInfos = await getContractInfos(
      network,
      parsedPayloads.filter(isTokenTransferPayload).map((payload) => payload.destination),
    );
    for (let i = 0; i < mainTransfers.length; i++) {
      const mainTransfer = mainTransfers[i];
      const parsedPayload = parsedPayloads[i];

      assert(
        isTokenTransferPayload(parsedPayload),
        `Main transfer ${i + 1}/${mainTransfers.length} payload is not a token transfer`,
      );

      const { amount: tokenAmount, destination } = parsedPayload as ApiTokensTransferPayload;
      sumTokenAmount += tokenAmount;
      sumTonAmount += mainTransfer.amount;

      const { isSwapAllowed, codeHash } = contractInfos[destination];

      assert(
        isSwapAllowed || FEE_ADDRESSES.includes(toBase64Address(destination, false)),
        `Main transfer ${i + 1}/${mainTransfers.length} destination is not a swap smart contract: `
        + `${destination}, codeHash=${codeHash}`,
      );
    }
    assert(sumTokenAmount <= maxAmount, 'Main transfers token amount is too big');
    assert(sumTonAmount <= maxTonAmount, 'Main transfers TON amount is too big');

    if (feeTransfer) {
      assert(feeTransfer.toAddress === walletAddress, 'Fee transfer address is not the token wallet address');

      const feePayload = feeTransfer.payload
        && parseKnownTokenTransferPayloadSlice(network, feeTransfer.payload.beginParse(), tokenAddress);

      assert(feeTransfer.amount + sumTonAmount < maxTonAmount, 'Total TON amount is too big');
      assert(isTokenTransferPayload(feePayload), 'Fee transfer payload is not a token transfer');

      const { amount: tokenFeeAmount, destination: feeDestination } = feePayload as ApiTokensTransferPayload;

      assert(sumTokenAmount + tokenFeeAmount <= maxAmount, 'Total token amount is too big');
      assert(FEE_ADDRESSES.includes(toBase64Address(feeDestination, false)), 'Unexpected fee transfer destination');
    }
  }
}

export async function buildOnchainSwapTransfer(
  options: ApiBuildOnchainSwapTransferOptions,
): Promise<ApiBuildOnchainSwapTransferResult | { error: ApiAnyDisplayError | typeof URANUS_PRICE_DRIFT_ERROR }> {
  const { accountId, request, transfers, swapId, authToken } = options;

  if (!transfers) {
    throw new Error('Transfers are required');
  }

  const transferList = parseSwapTransfers(transfers);
  const { network } = parseAccountId(accountId);

  const { address } = await fetchStoredWallet(accountId, 'ton');

  try {
    const account = await fetchStoredChainAccount(accountId, 'ton');
    const uranusMinimalAmountOut = await validateDexSwapTransfers(network, address, request, transferList, account);

    let rawTrace: EmulationResponse | undefined;
    const onRawTrace = uranusMinimalAmountOut === undefined ? undefined : (trace: EmulationResponse) => {
      rawTrace = trace;
    };

    const result = await checkMultiTransactionDraft(accountId, transferList, request.shouldTryDiesel, onRawTrace);

    if ('error' in result) {
      await patchSwapItem({
        address, swapId, authToken, error: result.error,
      });
      return result;
    }

    if (uranusMinimalAmountOut !== undefined) {
      if (result.emulation.isFallback || !rawTrace || !transferList[0].payload) {
        throw new Error('Uranus memepad swap requires a complete on-chain emulation');
      }
      const isUranusBuy = request.from === 'TON';
      const masterAddress = isUranusBuy ? request.to : request.from;
      const ownerJettonWallet = await resolveTokenWalletAddress(network, address, masterAddress);
      if (isUranusBuy) {
        validateUranusBuyEmulation({
          trace: rawTrace,
          signerAddress: address,
          masterAddress,
          ownerJettonWallet,
          buyPayload: transferList[0].payload,
          minimalAmountOut: uranusMinimalAmountOut,
          slippage: request.slippage!,
        });
      } else {
        validateUranusSellEmulation({
          trace: rawTrace,
          signerAddress: address,
          masterAddress,
          ownerJettonWallet,
          sellPayload: transferList[0].payload,
          minimalAmountOut: uranusMinimalAmountOut,
          slippage: request.slippage!,
        });
      }
    }

    return { ...result, id: swapId, transfers, chain: 'ton' };
  } catch (err: any) {
    await patchSwapItem({
      address, swapId, authToken, error: errorToString(err),
    });
    if (err instanceof UranusPriceDriftError) {
      return { error: URANUS_PRICE_DRIFT_ERROR };
    }
    throw err;
  }
}

export async function submitOnchainSwapTransfer(
  options: ApiSubmitOnchainSwapTransferOptions,
  onUpdate: OnApiUpdate,
): Promise<ApiSubmitOnchainSwapTransferResult> {
  const {
    accountId,
    enclaveToken,
    transfers,
    historyItem,
    isGasless,
    authToken,
    localSwap,
    swapId,
  } = options;

  if (!transfers) {
    throw new Error('Transfers are required');
  }

  const wallet = await fetchStoredWallet(accountId, 'ton');
  const account = await fetchStoredChainAccount(accountId, 'ton');
  const hasMfa = Boolean(account.byChain.ton.mfa);

  const { address } = wallet;

  // For MFA wallets, the local activity is created only after the request is confirmed
  if (!hasMfa) {
    onUpdate({
      type: 'newLocalActivities',
      accountId,
      activities: [localSwap],
    });
  }

  try {
    const transferList = parseSwapTransfers(transfers);

    if (historyItem.from !== 'TON') {
      transferList[0] = await insertMintlessPayload('mainnet', address, historyItem.from, transferList[0]);
    }

    const result = await submitMultiTransferWithMfa({
      accountId,
      signer: getSigner(accountId, account, enclaveToken),
      messages: transferList,
      isGasless,
    });

    if ('error' in result) {
      if (!hasMfa) {
        // Update local activity to show error state
        onUpdate({
          type: 'newLocalActivities',
          accountId,
          activities: [{ ...localSwap, status: 'failed' }],
        });
      }

      await patchSwapItem({
        address, swapId, authToken, error: result.error,
      });

      return result;
    }

    if ('mfaRequest' in result) {
      return { mfaRequest: result.mfaRequest };
    }

    delete result.messages[0].stateInit;

    const updatedSwap: ApiSwapActivity = {
      ...localSwap,
      externalMsgHashNorm: result.msgHashNormalized,
      extra: omitUndefined({
        ...localSwap.extra,
        withW5Gasless: result.withW5Gasless,
      }),
    };

    onUpdate({
      type: 'newLocalActivities',
      accountId,
      activities: [updatedSwap],
    });

    await patchSwapItem({
      address, swapId, authToken, msgHash: result.msgHash, msgHashNormalized: result.msgHashNormalized,
    });

    void callHook('onSwapCreated', accountId, updatedSwap.timestamp - 1);

    return {
      activityId: updatedSwap.id,
      submittedHashes: [result.msgHash, result.msgHashNormalized],
    };
  } catch (err: any) {
    if (!hasMfa) {
      onUpdate({
        type: 'newLocalActivities',
        accountId,
        activities: [{ ...localSwap, status: 'failed' }],
      });
    }

    await patchSwapItem({
      address, swapId, authToken, error: errorToString(err),
    });
    throw err;
  }
}

function parseSwapTransfers(transfers: ApiSwapTransfer[]): TonTransferParams[] {
  return transfers.map((transfer) => ({
    ...transfer,
    amount: BigInt(transfer.amount),
    payload: Cell.fromBase64(transfer.payload),
  }));
}

function errorToString(err: Error | string) {
  return typeof err === 'string' ? err : err.stack;
}

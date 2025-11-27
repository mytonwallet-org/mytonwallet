import type { OpenedContract, StateInit } from '@ton/core';
import {
  Address, beginCell, Builder, Cell, Dictionary, loadStateInit,
} from '@ton/core';
import { WalletContractV1R1 } from '@ton/ton/dist/wallets/WalletContractV1R1';
import { WalletContractV1R2 } from '@ton/ton/dist/wallets/WalletContractV1R2';
import { WalletContractV1R3 } from '@ton/ton/dist/wallets/WalletContractV1R3';
import { WalletContractV2R1 } from '@ton/ton/dist/wallets/WalletContractV2R1';
import { WalletContractV2R2 } from '@ton/ton/dist/wallets/WalletContractV2R2';
import { WalletContractV3R1 } from '@ton/ton/dist/wallets/WalletContractV3R1';
import { WalletContractV3R2 } from '@ton/ton/dist/wallets/WalletContractV3R2';
import { WalletContractV4 } from '@ton/ton/dist/wallets/WalletContractV4';
import { WalletContractV5R1 } from '@ton/ton/dist/wallets/WalletContractV5R1';

import type { ApiNetwork } from '../../../types';
import type { ApiTonWalletVersion, TokenTransferBodyParams } from '../types';
import { ApiTokenImportError } from '../../../types';
import { ApiCommonError } from '../../../types';

import { DEFAULT_TIMEOUT } from '../../../../config';
import { getDnsZoneByCollection } from '../../../../util/dns';
import { fromKeyValueArrays, mapValues } from '../../../../util/iteratees';
import { logDebugError } from '../../../../util/logs';
import withCache from '../../../../util/withCache';
import withCacheAsync from '../../../../util/withCacheAsync';
import { DnsItem } from '../contracts/DnsItem';
import { JettonMinter } from '../contracts/JettonMaster';
import { JettonStakingOpCodes } from '../contracts/JettonStaking/imports/constants';
import { StakeWallet } from '../contracts/JettonStaking/StakeWallet';
import { StakingPool } from '../contracts/JettonStaking/StakingPool';
import { JettonWallet } from '../contracts/JettonWallet';
import { hexToBytes } from '../../../common/utils';
import { getEnvironment } from '../../../environment';
import { DEFAULT_IS_BOUNCEABLE, JettonOpCode, LiquidStakingOpCode, NETWORK_CONFIG, OpCode } from '../constants';
import { generateQueryId } from './index';

import { TonClient } from './TonClient';

type TonWalletType = typeof WalletContractV1R1
  | typeof WalletContractV1R2
  | typeof WalletContractV1R3
  | typeof WalletContractV2R1
  | typeof WalletContractV2R2
  | typeof WalletContractV3R1
  | typeof WalletContractV3R2
  | typeof WalletContractV4
  | typeof WalletContractV5R1;

export type TonWallet = WalletContractV1R1
  | WalletContractV1R2
  | WalletContractV1R3
  | WalletContractV2R1
  | WalletContractV2R2
  | WalletContractV3R1
  | WalletContractV3R2
  | WalletContractV4
  | WalletContractV5R1;

const TON_MAX_COMMENT_BYTES = 127;

export const walletClassMap: Record<ApiTonWalletVersion, TonWalletType> = {
  simpleR1: WalletContractV1R1,
  simpleR2: WalletContractV1R2,
  simpleR3: WalletContractV1R3,
  v2R1: WalletContractV2R1,
  v2R2: WalletContractV2R2,
  v3R1: WalletContractV3R1,
  v3R2: WalletContractV3R2,
  v4R2: WalletContractV4,
  W5: WalletContractV5R1,
};

export const getTonClient = withCache((network: ApiNetwork) => {
  const { apiHeaders, byNetwork } = getEnvironment();

  return new TonClient({
    endpoint: `${NETWORK_CONFIG[network].toncenterUrl}/api/v2/jsonRPC`,
    timeout: DEFAULT_TIMEOUT,
    apiKey: byNetwork[network].toncenterKey,
    headers: apiHeaders,
  });
});

export const resolveTokenWalletAddress = withCacheAsync(
  async (network: ApiNetwork, address: string, tokenAddress: string) => {
    const minter = getTonClient(network).open(new JettonMinter(Address.parse(tokenAddress)));
    const walletAddress = await minter.getWalletAddress(Address.parse(address));
    return toBase64Address(walletAddress, true, network);
  },
);

export const resolveTokenAddress = withCacheAsync(async (network: ApiNetwork, tokenWalletAddress: string) => {
  const tokenWallet = getTonClient(network).open(new JettonWallet(Address.parse(tokenWalletAddress)));
  const data = await tokenWallet.getWalletData();
  return toBase64Address(data.minter, true, network);
});

export const getWalletPublicKey = withCacheAsync(async (network: ApiNetwork, address: string) => {
  const res = await getTonClient(network).runMethodWithError(Address.parse(address), 'get_public_key');
  if (res.exit_code !== 0) {
    return undefined;
  }

  const bigintKey = res.stack.readBigNumber();
  const hex = bigintKey.toString(16).padStart(64, '0');
  return hexToBytes(hex);
});

export const getJettonPoolStakeWallet = withCacheAsync(async (
  network: ApiNetwork,
  poolAddress: string,
  period: number,
  address: string,
): Promise<OpenedContract<StakeWallet>> => {
  const tonClient = getTonClient(network);
  const pool = tonClient.open(StakingPool.createFromAddress(Address.parse(poolAddress)));
  const walletAddress = (await pool.getWalletAddress(Address.parse(address), period))!;
  return tonClient.open(StakeWallet.createFromAddress(walletAddress));
});

export async function getJettonMinterData(network: ApiNetwork, address: string) {
  let parsedAddress: Address;
  try {
    parsedAddress = Address.parse(address);
  } catch {
    return { error: ApiCommonError.InvalidAddress };
  }

  const contract = getTonClient(network).open(new JettonMinter(parsedAddress));

  try {
    return await contract.getJettonData();
  } catch (err) {
    if (err instanceof Error) {
      if (err.message.includes('exit_code: -13')) {
        return { error: ApiTokenImportError.AddressDoesNotExist };
      }
      if (err.message.includes('exit_code: 11')) {
        return { error: ApiTokenImportError.NotATokenAddress };
      }
    }
    throw err;
  }
}

export function toBase64Address(address: Address | string, isBounceable = DEFAULT_IS_BOUNCEABLE, network?: ApiNetwork) {
  if (typeof address === 'string') {
    address = Address.parse(address);
  }
  return address.toString({
    urlSafe: true,
    bounceable: isBounceable,
    testOnly: network === 'testnet',
  });
}

export function toRawAddress(address: Address | string) {
  if (typeof address === 'string') {
    address = Address.parse(address);
  }
  return address.toRawString();
}

export function areAddressesEqual(address1: Address | string, address2: Address | string) {
  if (address1 === address2) {
    return true;
  }

  if (typeof address1 === 'string') address1 = Address.parse(address1);
  if (typeof address2 === 'string') address2 = Address.parse(address2);

  return address1.equals(address2);
}

export function buildTokenTransferBody(params: TokenTransferBodyParams) {
  const {
    queryId,
    tokenAmount,
    toAddress,
    responseAddress,
    forwardAmount,
    forwardPayload,
    noInlineForwardPayload,
    customPayload,
  } = params;

  let builder = new Builder()
    .storeUint(JettonOpCode.Transfer, 32)
    .storeUint(queryId ?? generateQueryId(), 64)
    .storeCoins(tokenAmount)
    .storeAddress(Address.parse(toAddress))
    .storeAddress(Address.parse(responseAddress))
    .storeMaybeRef(customPayload)
    .storeCoins(forwardAmount ?? 0n);

  builder = storeInlineOrRefCell(builder, forwardPayload, 0, noInlineForwardPayload);

  return builder.endCell();
}

export function parseBase64(base64: string): Cell {
  try {
    return Cell.fromBase64(base64);
  } catch (err) {
    logDebugError('parseBase64', err);
    return packBytesAsSnakeCell(Buffer.from(base64, 'base64'));
  }
}

export function commentToBytes(comment: string): Uint8Array {
  const buffer = Buffer.from(comment);
  const bytes = new Uint8Array(buffer.length + 4);

  const startBuffer = Buffer.alloc(4);
  startBuffer.writeUInt32BE(OpCode.Comment);
  bytes.set(startBuffer, 0);
  bytes.set(buffer, 4);

  return bytes;
}

export function packBytesAsSnakeCell(bytes: Uint8Array): Cell {
  const bytesPerCell = TON_MAX_COMMENT_BYTES;
  const cellCount = Math.ceil(bytes.length / bytesPerCell);
  let headCell: Cell | undefined;

  for (let i = cellCount - 1; i >= 0; i--) {
    const cellOffset = i * bytesPerCell;
    const cellLength = Math.min(bytesPerCell, bytes.length - cellOffset);
    const cellBuffer = Buffer.from(bytes.buffer, bytes.byteOffset + cellOffset, cellLength); // This creates a buffer that references the input bytes instead of copying them

    const nextHeadCell = new Builder().storeBuffer(cellBuffer);
    if (headCell) {
      nextHeadCell.storeRef(headCell);
    }
    headCell = nextHeadCell.endCell();
  }

  return headCell ?? Cell.EMPTY;
}

export function packBytesAsSnakeForEncryptedData(data: Uint8Array): Cell {
  // https://docs.ton.org/v3/documentation/smart-contracts/message-management/internal-messages#encryption-algorithm
  const ROOT_BUILDER_BYTES = 39;
  const MAX_CELLS_AMOUNT = 16;

  if (data.length > ROOT_BUILDER_BYTES + MAX_CELLS_AMOUNT * TON_MAX_COMMENT_BYTES) {
    throw new Error('Input text is too long');
  }

  return new Builder()
    .storeBuffer(Buffer.from(data.subarray(0, ROOT_BUILDER_BYTES)))
    .storeRef(packBytesAsSnakeCell(data.subarray(ROOT_BUILDER_BYTES)))
    .endCell();
}

export function buildLiquidStakingDepositBody(queryId?: number) {
  return new Builder()
    .storeUint(LiquidStakingOpCode.Deposit, 32)
    .storeUint(queryId || 0, 64)
    .asCell();
}

export function buildLiquidStakingWithdrawBody(options: {
  queryId?: number;
  amount: bigint;
  responseAddress: string;
  waitTillRoundEnd?: boolean; // opposite of request_immediate_withdrawal
  fillOrKill?: boolean;
}) {
  const {
    queryId, amount, responseAddress, waitTillRoundEnd, fillOrKill,
  } = options;

  const customPayload = buildLiquidStakingWithdrawCustomPayload(waitTillRoundEnd, fillOrKill);

  return new Builder()
    .storeUint(JettonOpCode.Burn, 32)
    .storeUint(queryId ?? 0, 64)
    .storeCoins(amount)
    .storeAddress(Address.parse(responseAddress))
    .storeBit(1)
    .storeRef(customPayload)
    .asCell();
}

export function buildLiquidStakingWithdrawCustomPayload(waitTillRoundEnd?: boolean, fillOrKill?: boolean) {
  return new Builder()
    .storeUint(Number(waitTillRoundEnd), 1)
    .storeUint(Number(fillOrKill), 1)
    .asCell();
}

export function getTokenBalance(network: ApiNetwork, walletAddress: string) {
  const tokenWallet = getTonClient(network).open(new JettonWallet(Address.parse(walletAddress)));
  return tokenWallet.getJettonBalance();
}

export function parseAddress(address: string): {
  isValid: boolean;
  isRaw?: boolean;
  isUserFriendly?: boolean;
  isBounceable?: boolean;
  isTestOnly?: boolean;
  address?: Address;
} {
  try {
    if (Address.isRaw(address)) {
      return {
        address: Address.parseRaw(address),
        isRaw: true,
        isValid: true,
      };
    } else if (Address.isFriendly(address)) {
      return {
        ...Address.parseFriendly(address),
        isUserFriendly: true,
        isValid: true,
      };
    }
  } catch (err) {
    // Do nothing
  }

  return { isValid: false };
}

export function getIsRawAddress(address: string) {
  return Boolean(parseAddress(address).isRaw);
}

export async function getDnsItemDomain(network: ApiNetwork, address: Address | string) {
  if (typeof address === 'string') address = Address.parse(address);

  const contract = getTonClient(network)
    .open(new DnsItem(address));
  const nftData = await contract.getNftData();
  const collectionAddress = toBase64Address(nftData.collectionAddress, true);

  const zone = getDnsZoneByCollection(collectionAddress);

  const base = zone?.isTelemint
    ? await contract.getTelemintDomain()
    : await contract.getDomain();

  return `${base}.${zone?.suffixes[0]}`;
}

export function buildJettonUnstakePayload(jettonsToUnstake: bigint, forceUnstake?: boolean, queryId?: bigint) {
  return beginCell()
    .storeUint(JettonStakingOpCodes.UNSTAKE_JETTONS, 32)
    .storeUint(queryId ?? 0, 64)
    .storeCoins(jettonsToUnstake)
    .storeBit(forceUnstake ?? false)
    .endCell();
}

export function buildJettonClaimPayload(poolWallets: string[], queryId?: bigint) {
  const rewardsToClaim = Dictionary.empty(Dictionary.Keys.Address(), Dictionary.Values.Bool());

  for (const poolWallet of poolWallets) {
    rewardsToClaim.set(Address.parse(poolWallet), true);
  }

  return beginCell()
    .storeUint(JettonStakingOpCodes.CLAIM_REWARDS, 32)
    .storeUint(queryId ?? 0, 64)
    .storeDict(rewardsToClaim, Dictionary.Keys.Address(), Dictionary.Values.Bool())
    .endCell();
}

// eslint-disable-next-line @typescript-eslint/no-redundant-type-constituents
export function unpackDicts(obj: Record<string, any | Dictionary<any, any>>): AnyLiteral {
  if (!isSimpleObject(obj)) {
    return obj;
  }

  return mapValues(obj, (value) => {
    if (value instanceof Dictionary) {
      return unpackDicts(fromKeyValueArrays(value.keys(), value.values()));
    }
    if (isSimpleObject(value)) {
      return unpackDicts(value);
    }
    return value;
  });
}

function isSimpleObject(obj: any) {
  // eslint-disable-next-line no-null/no-null
  return obj !== null
    && typeof obj === 'object'
    && Object.getPrototypeOf(obj) === Object.prototype;
}

export function getOurFeePayload() {
  return new Builder()
    .storeUint(OpCode.OurFee, 32)
    .endCell();
}

export function parseStateInitCell(stateInit: Cell | undefined): StateInit | undefined {
  return stateInit && loadStateInit(stateInit.asSlice());
}

export function isSeqnoMismatchError(error: string) {
  return error.match(/exitcode=(33|133)\D/);
}

export function isExpiredTransactionError(error: string) {
  return error.match(/exitcode=(35|136)\D/);
}

/**
 * Writes a cell to the builder in the `Either Cell ^Cell` TL-B format.
 *
 * @see https://docs.ton.org/v3/documentation/data-formats/tlb/types#either How Either is stored
 */
export function storeInlineOrRefCell(builder: Builder, cell?: Cell, marginBits = 0, noInline?: boolean) {
  if (
    cell
    && !noInline
    && cell.bits.length <= builder.availableBits - marginBits - 1 // 1 for `storeBit`
    && cell.refs.length <= builder.availableRefs
  ) {
    return builder
      .storeBit(0)
      .storeSlice(cell.beginParse(true));
  }

  return builder.storeMaybeRef(cell);
}

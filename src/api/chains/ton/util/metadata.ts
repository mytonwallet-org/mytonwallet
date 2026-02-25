import type { NftItem } from 'tonapi-sdk-js';
import type { DictionaryValue } from '@ton/core';
import { BitReader } from '@ton/core/dist/boc/BitReader';
import { BitString } from '@ton/core/dist/boc/BitString';
import { Builder } from '@ton/core/dist/boc/Builder';
import { Cell } from '@ton/core/dist/boc/Cell';
import { Slice } from '@ton/core/dist/boc/Slice';
import { Dictionary } from '@ton/core/dist/dict/Dictionary';

import type {
  ApiActivity,
  ApiAnyDisplayError,
  ApiMtwCardBorderShineType,
  ApiMtwCardTextType,
  ApiMtwCardType,
  ApiNetwork,
  ApiNft,
  ApiNftAttribute,
  ApiNftMetadata,
  ApiNftSuperCollection,
  ApiParsedPayload,
} from '../../../types';
import type { JettonMetadata } from '../types';

import {
  DEBUG,
  LIQUID_JETTON,
  MTW_CARDS_COLLECTION,
  NFT_FRAGMENT_COLLECTIONS,
  NFT_FRAGMENT_GIFT_IMAGE_TO_URL_REGEX,
  TELEGRAM_GIFTS_SUPER_COLLECTION,
} from '../../../../config';
import { fetchJsonWithProxy, fixIpfsUrl, getProxiedLottieUrl } from '../../../../util/fetch';
import isEmptyObject from '../../../../util/isEmptyObject';
import { omitUndefined, pick, range } from '../../../../util/iteratees';
import { logDebugError } from '../../../../util/logs';
import {
  checkHasScamLink,
  checkIsTrustedCollection,
  getNftSuperCollectionsByCollectionAddress,
} from '../../../common/addresses';
import { buildTokenSlug } from '../../../common/tokens';
import { base64ToString, sha256 } from '../../../common/utils';
import { DnsCategory, JettonStakingOpCode } from '../constants';
import {
  DNS_CATEGORY_HASH_MAP,
  DnsOpCode,
  JettonOpCode,
  LiquidStakingOpCode,
  NftOpCode,
  OpCode,
  OtherOpCode,
  SingleNominatorOpCode,
  VestingV1OpCode,
} from '../constants';
import { fixAddressFormat } from '../toncenter/other';
import { fetchNftItems } from './tonapiio';
import {
  getDnsItemDomain, getJettonMinterData, resolveTokenAddress, toBase64Address,
} from './tonCore';

type OpCodes = OpCode | JettonOpCode | NftOpCode | LiquidStakingOpCode | VestingV1OpCode | SingleNominatorOpCode
  | DnsOpCode | OtherOpCode | JettonStakingOpCode;

const OFFCHAIN_CONTENT_PREFIX = 0x01;
const SNAKE_PREFIX = 0x00;

export function fixBase64ImageData(data: string) {
  const decodedData = base64ToString(data);
  if (decodedData.includes('<svg')) {
    return `data:image/svg+xml;base64,${data}`;
  }
  return `data:image/png;base64,${data}`;
}

const dictSnakeBufferValue: DictionaryValue<Buffer> = {
  parse: (slice) => {
    const buffer = Buffer.from('');

    const sliceToVal = (s: Slice, v: Buffer, isFirst: boolean) => {
      if (isFirst && s.loadUint(8) !== SNAKE_PREFIX) {
        throw new Error('Only snake format is supported');
      }

      v = Buffer.concat([v, s.loadBuffer(s.remainingBits / 8)]);
      if (s.remainingRefs === 1) {
        v = sliceToVal(s.loadRef().beginParse(), v, false);
      }

      return v;
    };

    return sliceToVal(slice.loadRef().beginParse() as any, buffer, true);
  },
  serialize: () => {
    // pass
  },
};

const jettonOnChainMetadataSpec: {
  [key in keyof JettonMetadata]: 'utf8' | 'ascii' | undefined;
} = {
  uri: 'ascii',
  name: 'utf8',
  description: 'utf8',
  image: 'ascii',
  symbol: 'utf8',
  decimals: 'utf8',
  custom_payload_api_uri: 'ascii',
};

export async function fetchJettonMetadata(
  network: ApiNetwork,
  address: string,
): Promise<JettonMetadata | { error: ApiAnyDisplayError }> {
  const minterData = await getJettonMinterData(network, address);
  if ('error' in minterData) return minterData;

  let metadata: JettonMetadata;

  const slice = minterData.content.asSlice();
  const prefix = slice.loadUint(8);

  if (prefix === OFFCHAIN_CONTENT_PREFIX) {
    const bytes = readSnakeBytes(slice);
    const contentUri = bytes.toString('utf-8');
    metadata = await fetchJettonOffchainMetadata(contentUri);
  } else {
    // On-chain content
    metadata = await parseJettonOnchainMetadata(slice);
    if (metadata.uri) {
      // Semi-chain content
      const offchainMetadata = await fetchJettonOffchainMetadata(metadata.uri);
      metadata = { ...offchainMetadata, ...metadata };
    }
  }

  return metadata;
}

export async function parseJettonOnchainMetadata(slice: Slice): Promise<JettonMetadata> {
  const dict = slice.loadDict(Dictionary.Keys.Buffer(32), dictSnakeBufferValue);

  const res: { [s in keyof JettonMetadata]?: string } = {};

  for (const [key, value] of Object.entries(jettonOnChainMetadataSpec)) {
    const sha256Key = Buffer.from(await sha256(Buffer.from(key, 'ascii')));
    const val = dict.get(sha256Key)?.toString(value);

    if (val) {
      res[key as keyof JettonMetadata] = val;
    }
  }

  return res as JettonMetadata;
}

export async function fetchJettonOffchainMetadata(uri: string): Promise<JettonMetadata> {
  const metadata = await fetchJsonWithProxy(uri);
  return pick(metadata, [
    'name',
    'description',
    'symbol',
    'decimals',
    'image',
    'image_data',
    'custom_payload_api_uri',
  ]);
}

export async function parsePayloadBase64(
  network: ApiNetwork,
  address: string,
  base64: string,
): Promise<ApiParsedPayload> {
  const slice = dataToSlice(base64);
  const result: ApiParsedPayload = { type: 'unknown', base64 };

  if (!slice) return result;

  return await parsePayloadSlice(network, address, slice, true) ?? result;
}

export async function parsePayloadSlice(
  network: ApiNetwork,
  address: string,
  slice: Slice,
  shouldLoadItems?: boolean,
  transactionDebug?: ApiActivity,
): Promise<ApiParsedPayload | undefined> {
  let opCode: OpCodes | undefined;
  try {
    opCode = slice.loadUint(32);

    if (opCode === OpCode.Comment) {
      const buffer = readSnakeBytes(slice);
      const comment = buffer.toString('utf-8');
      return { type: 'comment', comment };
    } else if (opCode === OpCode.Encrypted) {
      const buffer = readSnakeBytes(slice);
      const encryptedComment = buffer.toString('base64');
      return { type: 'encrypted-comment', encryptedComment };
    } else if (slice.remainingBits < 64) {
      return undefined;
    }

    const queryId = slice.loadUintBig(64);

    switch (opCode) {
      case JettonOpCode.Transfer: {
        const tokenAddress = await resolveTokenAddress(network, address).catch(() => '');
        const slug = buildTokenSlug('ton', tokenAddress);

        const amount = slice.loadCoins();
        const destination = slice.loadAddress();
        const responseDestination = slice.loadMaybeAddress();

        if (!responseDestination) {
          return {
            type: 'tokens:transfer-non-standard',
            queryId,
            destination: toBase64Address(destination, undefined, network),
            amount,
            slug,
          };
        }

        const customPayload = slice.loadMaybeRef();
        const forwardAmount = slice.loadCoins();
        let forwardPayload = slice.loadMaybeRef();
        let forwardPayloadOpCode: number | undefined;

        if (!forwardPayload && slice.remainingBits) {
          const builder = new Builder().storeBits(slice.loadBits(slice.remainingBits));
          range(0, slice.remainingRefs).forEach(() => {
            builder.storeRef(slice.loadRef());
          });
          forwardPayload = builder.endCell();
        }

        if (forwardPayload) {
          const forwardPayloadSlice = forwardPayload.beginParse();
          if (forwardPayloadSlice.remainingBits > 32) {
            forwardPayloadOpCode = forwardPayloadSlice.loadUint(32);
          }
        }

        return {
          type: 'tokens:transfer',
          queryId,
          amount,
          destination: toBase64Address(destination, undefined, network),
          responseDestination: toBase64Address(responseDestination, undefined, network),
          customPayload: customPayload?.toBoc().toString('base64'),
          forwardAmount,
          forwardPayload: forwardPayload?.toBoc().toString('base64'),
          forwardPayloadOpCode,
          slug,
          tokenAddress,
        };
      }
      case NftOpCode.TransferOwnership: {
        const newOwner = slice.loadAddress();
        const responseDestination = slice.loadAddress();
        const customPayload = slice.loadMaybeRef();
        const forwardAmount = slice.loadCoins();
        const forwardPayload = readForwardPayloadCell(slice);
        const comment = forwardPayload ? readComment(forwardPayload.asSlice()) : undefined;

        let nft: ApiNft | undefined;
        if (shouldLoadItems) {
          const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();
          const [rawNft] = await fetchNftItems(network, [address]);
          if (rawNft) {
            nft = parseTonapiioNft(network, rawNft, nftSuperCollectionsByCollectionAddress);
          }
        }

        return {
          type: 'nft:transfer',
          queryId,
          newOwner: toBase64Address(newOwner, undefined, network),
          responseDestination: toBase64Address(responseDestination, undefined, network),
          customPayload: customPayload?.toBoc().toString('base64'),
          forwardAmount,
          forwardPayload: forwardPayload?.toBoc().toString('base64'),
          nftAddress: address,
          nftName: nft?.name,
          nft,
          comment,
        };
      }
      case NftOpCode.OwnershipAssigned: {
        const prevOwner = slice.loadAddress();
        const forwardPayload = readForwardPayloadCell(slice);
        const comment = forwardPayload ? readComment(forwardPayload.asSlice()) : undefined;

        let nft: ApiNft | undefined;
        if (shouldLoadItems) {
          const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();
          const [rawNft] = await fetchNftItems(network, [address]);
          if (rawNft) {
            nft = parseTonapiioNft(network, rawNft, nftSuperCollectionsByCollectionAddress);
          }
        }

        return {
          type: 'nft:ownership-assigned',
          queryId,
          prevOwner: toBase64Address(prevOwner, undefined, network),
          comment,
          nftAddress: address,
          nft,
        };
      }
      case JettonOpCode.Burn: {
        const tokenAddress = await resolveTokenAddress(network, address);
        const slug = buildTokenSlug('ton', tokenAddress);

        const amount = slice.loadCoins();
        const addressObj = slice.loadAddress();
        const customPayload = slice.loadMaybeRef();
        const isLiquidUnstakeRequest = tokenAddress === LIQUID_JETTON;

        return {
          type: 'tokens:burn',
          queryId,
          amount,
          address: toBase64Address(addressObj, undefined, network),
          customPayload: customPayload?.toBoc().toString('base64'),
          slug,
          isLiquidUnstakeRequest,
        };
      }
      case LiquidStakingOpCode.DistributedAsset: {
        return {
          type: 'liquid-staking:withdrawal-nft',
          queryId,
        };
      }
      case LiquidStakingOpCode.Withdrawal: {
        return {
          type: 'liquid-staking:withdrawal',
          queryId,
        };
      }
      case LiquidStakingOpCode.Deposit: {
        let appId: bigint | undefined;
        if (slice.remainingBits > 0) {
          appId = slice.loadUintBig(64);
        }
        return {
          type: 'liquid-staking:deposit',
          queryId,
          appId,
        };
      }
      case VestingV1OpCode.AddWhitelist: {
        const toAddress = slice.loadAddress();
        const addressString = shouldLoadItems
          ? await fixAddressFormat(network, toAddress.toRawString())
          : '';

        return {
          type: 'vesting:add-whitelist',
          queryId,
          address: addressString,
        };
      }
      case SingleNominatorOpCode.Withdraw: {
        const amount = slice.loadCoins();
        return {
          type: 'single-nominator:withdraw',
          queryId,
          amount,
        };
      }
      case SingleNominatorOpCode.ChangeValidator: {
        const toAddress = slice.loadAddress();
        const addressString = shouldLoadItems
          ? await fixAddressFormat(network, toAddress.toRawString())
          : '';

        return {
          type: 'single-nominator:change-validator',
          queryId,
          address: addressString,
        };
      }
      case LiquidStakingOpCode.Vote: {
        const votingAddress = slice.loadAddress();
        const expirationDate = slice.loadUint(48);
        const vote = slice.loadBit();
        const needConfirmation = slice.loadBit();

        return {
          type: 'liquid-staking:vote',
          queryId,
          votingAddress: toBase64Address(votingAddress, true),
          expirationDate,
          vote,
          needConfirmation,
        };
      }
      case DnsOpCode.ChangeRecord: {
        const hash = slice.loadBuffer(32).toString('hex');
        const category = Object.entries(DNS_CATEGORY_HASH_MAP)
          .find(([, value]) => hash === value)?.[0] as DnsCategory ?? 'unknown';
        const toAddress = slice.loadAddress();
        const domain = shouldLoadItems
          ? await getDnsItemDomain(network, toAddress)
          : '';

        if (category === DnsCategory.Wallet) {
          if (slice.remainingRefs > 0) {
            const dataSlice = slice.loadRef().beginParse();
            slice.endParse();

            const dataAddress = dataSlice.loadAddress();
            const flags = dataSlice.loadUint(8);

            const addressString = shouldLoadItems
              ? await fixAddressFormat(network, dataAddress.toRawString())
              : '';

            return {
              type: 'dns:change-record',
              queryId,
              record: {
                type: 'wallet',
                value: addressString,
                flags,
              },
              domain,
            };
          } else {
            return {
              type: 'dns:change-record',
              queryId,
              record: {
                type: 'wallet',
                value: undefined,
              },
              domain,
            };
          }
        } else if (slice.remainingRefs > 0) {
          const value = slice.loadRef();
          return {
            type: 'dns:change-record',
            queryId,
            record: category === DnsCategory.Unknown ? {
              type: 'unknown',
              key: hash,
              value: value.toBoc().toString('base64'),
            } : {
              type: category,
              value: value.toBoc().toString('base64'),
            },
            domain,
          };
        } else {
          return {
            type: 'dns:change-record',
            queryId,
            record: category === DnsCategory.Unknown ? {
              type: 'unknown',
              key: hash,
            } : {
              type: category,
            },
            domain,
          };
        }
      }
      case OtherOpCode.TokenBridgePaySwap: {
        const swapId = slice.loadBuffer(32).toString('hex');
        return {
          type: 'token-bridge:pay-swap',
          queryId,
          swapId,
        };
      }
      case JettonStakingOpCode.UnstakeRequest: {
        const amount = slice.loadCoins();
        const isForce = slice.loadBoolean();
        return {
          type: 'jetton-staking:unstake',
          queryId,
          amount,
          isForce,
        };
      }
    }
  } catch (err) {
    if (DEBUG) {
      const debugTxString = transactionDebug
        && `${transactionDebug.id} ${new Date(transactionDebug.timestamp).toISOString()}`;
      const opCodeHex = `0x${opCode?.toString(16).padStart(8, '0')}`;
      logDebugError('parsePayload', opCodeHex, debugTxString, '\n', err);
    }
  }

  return undefined;
}

export function parseBidaskPayload(base64: string) {
  const slice = dataToSlice(base64);
  const _opCode = slice.loadUint(32);
  const queryId = slice.loadUintBig(64);
  const amount = slice.loadCoins();

  return {
    queryId,
    amount,
  };
}

function dataToSlice(data: string | Buffer | Uint8Array): Slice {
  let buffer: Buffer;
  if (typeof data === 'string') {
    buffer = Buffer.from(data, 'base64');
  } else if (data instanceof Buffer) {
    buffer = data;
  } else {
    buffer = Buffer.from(data);
  }

  try {
    return Cell.fromBoc(buffer)[0].beginParse();
  } catch (err: any) {
    if (err?.message !== 'Invalid magic') {
      throw err;
    }
  }

  return new Slice(new BitReader(new BitString(buffer, 0, buffer.length * 8)), []);
}

export function readComment(slice: Slice) {
  if (slice.remainingBits < 32) {
    return undefined;
  }

  const opCode = slice.loadUint(32) as OpCode;
  if (opCode !== OpCode.Comment || (!slice.remainingBits && !slice.remainingRefs)) {
    return undefined;
  }

  const buffer = readSnakeBytes(slice);
  return buffer.toString('utf-8');
}

function readForwardPayloadCell(slice: Slice) {
  let forwardPayload = slice.loadBit() && slice.remainingRefs ? slice.loadRef() : undefined;

  if (!forwardPayload && slice.remainingBits) {
    const builder = new Builder().storeBits(slice.loadBits(slice.remainingBits));
    range(0, slice.remainingRefs).forEach(() => {
      builder.storeRef(slice.loadRef());
    });
    forwardPayload = builder.endCell();
  }

  return forwardPayload ?? undefined;
}

export function readSnakeBytes(slice: Slice) {
  let buffer = Buffer.alloc(0);

  while (slice.remainingBits >= 8) {
    buffer = Buffer.concat([buffer, slice.loadBuffer(slice.remainingBits / 8)]);
    if (slice.remainingRefs) {
      slice = slice.loadRef().beginParse();
    } else {
      break;
    }
  }

  return buffer;
}

export function buildMtwCardsNftMetadata(metadata: {
  image?: string;
  id?: number;
  attributes?: ApiNftAttribute[];
}): ApiNftMetadata | undefined {
  const { id, image, attributes } = metadata;

  let mtwCardType: ApiMtwCardType | undefined;
  let mtwCardTextType: ApiMtwCardTextType | undefined;
  let result: ApiNftMetadata = {};
  if (image) result.imageUrl = image;
  if (id !== undefined) result.mtwCardId = id;

  if (attributes && Array.isArray(attributes) && attributes.length) {
    mtwCardType = attributes
      .find((attribute) => attribute.trait_type === 'Card Type')?.value
      // Clean non-ascii characters with regex
      .replace(/[^\x20-\x7E]/g, '')
      .trim()
      .toLowerCase() as ApiMtwCardType;

    if (mtwCardType) {
      mtwCardTextType = attributes
        .find((attribute) => attribute.trait_type === 'Text')?.value
        .toLowerCase() as ApiMtwCardTextType;

      result.mtwCardType = mtwCardType;
      if (mtwCardType === 'standard') {
        result.mtwCardBorderShineType = attributes
          .find((attribute) => attribute.trait_type === 'Shine')?.value
          .toLowerCase() as ApiMtwCardBorderShineType;
      }

      if (mtwCardTextType === 'dark' || mtwCardType === 'silver') {
        result.mtwCardTextType = 'dark';
      } else {
        result.mtwCardTextType = 'light';
      }

      result = omitUndefined(result);
    }
  }

  return !isEmptyObject(result) ? result : undefined;
}

export function parseTonapiioNft(
  network: ApiNetwork,
  rawNft: NftItem,
  nftSuperCollectionsByCollectionAddress: Record<string, ApiNftSuperCollection>,
): ApiNft | undefined {
  if (!rawNft.metadata) {
    return undefined;
  }

  try {
    const {
      address,
      index,
      collection,
      metadata: rawMetadata,
      previews,
      sale,
      trust,
      owner,
    } = rawNft;

    const {
      name, image, description, render_type: renderType, attributes, lottie,
    } = rawMetadata as {
      name?: string;
      image?: string;
      description?: string;
      render_type?: string;
      attributes?: {
        trait_type: string;
        value: string;
      }[];
      lottie?: string;
    };

    const collectionAddress = collection && toBase64Address(collection.address, true, network);
    let hasScamLink = false;

    if (!collectionAddress || !checkIsTrustedCollection(collectionAddress)) {
      for (const text of [name, description].filter(Boolean)) {
        if (checkHasScamLink(text)) {
          hasScamLink = true;
        }
      }
    }

    // eslint-disable-next-line @typescript-eslint/no-unsafe-enum-comparison
    const isWhitelisted = trust === 'whitelist';
    // eslint-disable-next-line @typescript-eslint/no-unsafe-enum-comparison
    const isScam = hasScamLink || description === 'SCAM' || trust === 'blacklist';
    const isHidden = renderType === 'hidden' || isScam;
    const imageFromPreview = previews!.find((x) => x.resolution === '1500x1500')!.url;
    const isFragmentGift = getIsFragmentGift(nftSuperCollectionsByCollectionAddress, collectionAddress);

    const metadata = {
      ...(Array.isArray(attributes) && { attributes }),
      ...(isWhitelisted && lottie && { lottie: getProxiedLottieUrl(lottie) }),
      ...(collectionAddress === MTW_CARDS_COLLECTION && buildMtwCardsNftMetadata(rawMetadata)),
      ...(isFragmentGift && { fragmentUrl: image!.replace(NFT_FRAGMENT_GIFT_IMAGE_TO_URL_REGEX, 'https://$1') }),
    };

    return omitUndefined<ApiNft>({
      chain: 'ton',
      interface: 'default',
      index,
      name,
      ownerAddress: owner ? toBase64Address(owner.address, false, network) : undefined,
      address: toBase64Address(address, true, network),
      image: fixIpfsUrl(imageFromPreview || image || ''),
      thumbnail: previews!.find((x) => x.resolution === '500x500')!.url,
      isOnSale: Boolean(sale),
      isHidden,
      isScam,
      description,
      ...(collection && {
        collectionAddress,
        collectionName: collection.name,
        isOnFragment: isFragmentGift || NFT_FRAGMENT_COLLECTIONS.includes(collection.address),
        isTelegramGift: isFragmentGift,
      }),
      metadata,
    });
  } catch (err) {
    logDebugError('buildNft', err);
    return undefined;
  }
}

export function getIsFragmentGift(
  nftSuperCollectionsByCollectionAddress: Record<string, ApiNftSuperCollection>,
  collectionAddress?: string,
) {
  return collectionAddress
    ? nftSuperCollectionsByCollectionAddress[collectionAddress]?.id === TELEGRAM_GIFTS_SUPER_COLLECTION
    : false;
}

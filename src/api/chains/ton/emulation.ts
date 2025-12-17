import type { Cell } from '@ton/core';
import { beginCell, external, storeMessage } from '@ton/core';

import type {
  ApiActivity,
  ApiEmulationResult,
  ApiNetwork,
  ApiNftSuperCollection,
  ApiTransactionActivity,
} from '../../types';
import type { EmulationResponse } from './toncenter/emulation';
import type { TonWallet } from './util/tonCore';

import { BURN_ADDRESS, TONCOIN } from '../../../config';
import { toBase64Address } from './util/tonCore';
import { getNftSuperCollectionsByCollectionAddress } from '../../common/addresses';
import { FAKE_TX_ID } from '../../constants';
import { fetchEmulateTrace } from './toncenter/emulation';
import { parseTrace } from './traces';

export async function emulateTransaction(
  network: ApiNetwork,
  wallet: TonWallet,
  transaction: Cell,
  isInitialized?: boolean,
) {
  const boc = buildExternalBoc(wallet, transaction, isInitialized);
  const emulation = await fetchEmulateTrace(network, boc);
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();
  const walletAddress = toBase64Address(wallet.address, false, network);
  return parseEmulation(network, walletAddress, emulation, nftSuperCollectionsByCollectionAddress);
}

export function parseEmulation(
  network: ApiNetwork,
  walletAddress: string,
  emulation: EmulationResponse,
  nftSuperCollectionsByCollectionAddress: Record<string, ApiNftSuperCollection>,
): ApiEmulationResult {
  const parsedTrace = parseTrace({
    network,
    walletAddress,
    actions: emulation.actions,
    traceDetail: emulation.trace,
    addressBook: emulation.address_book,
    metadata: emulation.metadata,
    transactions: emulation.transactions,
    nftSuperCollectionsByCollectionAddress,
  });

  let walletActivities: ApiActivity[] = [];
  let totalRealFee = 0n;
  let totalExcess = 0n;

  for (const traceOutput of parsedTrace.traceOutputs) {
    totalRealFee += traceOutput.realFee;
    totalExcess += traceOutput.excess;
    for (const { activities } of traceOutput.walletActions) {
      walletActivities = walletActivities.concat(activities);
    }
  }

  if (totalExcess) {
    addOrUpdateExcessActivity(walletAddress, walletActivities, totalExcess);
  }

  return {
    networkFee: parsedTrace.totalNetworkFee,
    received: parsedTrace.totalReceived,
    traceOutputs: parsedTrace.traceOutputs,
    activities: walletActivities,
    realFee: totalRealFee,
  };
}

function addOrUpdateExcessActivity(walletAddress: string, activities: ApiActivity[], excess: bigint) {
  const index = activities.findIndex((activity) => {
    return activity.kind === 'transaction' && activity.type === 'excess';
  });

  if (index !== -1) {
    const excessActivity = activities.splice(index, 1)[0] as ApiTransactionActivity;
    activities.push({
      ...excessActivity,
      amount: excess,
    });
  } else {
    const ts = activities.length ? activities[activities.length - 1].timestamp : Date.now();
    activities.push({
      id: FAKE_TX_ID,
      timestamp: ts,
      kind: 'transaction',
      amount: excess,
      slug: TONCOIN.slug,
      normalizedAddress: BURN_ADDRESS,
      fromAddress: BURN_ADDRESS,
      toAddress: walletAddress,
      isIncoming: true,
      fee: 0n,
      type: 'excess',
      status: 'completed',
    });
  }
}

function buildExternalBoc(wallet: TonWallet, body: Cell, isInitialized?: boolean) {
  const externalMessage = external({
    to: wallet.address,
    init: !isInitialized ? {
      code: wallet.init.code,
      data: wallet.init.data,
    } : undefined,
    body,
  });

  return beginCell()
    .store(storeMessage(externalMessage))
    .endCell()
    .toBoc()
    .toString('base64');
}

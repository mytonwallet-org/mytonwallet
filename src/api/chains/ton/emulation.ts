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
import { logDebugError } from '../../../util/logs';
import { toBase64Address } from './util/tonCore';
import { getNftSuperCollectionsByCollectionAddress } from '../../common/addresses';
import { FAKE_TX_ID } from '../../constants';
import { fetchEmulateTrace } from './toncenter/emulation';
import { calculateActivityDetails, getActivityRealFee } from './activities';
import { parseActions } from './toncenter';
import { parseTrace } from './traces';

export async function emulateTransaction(
  network: ApiNetwork,
  wallet: TonWallet,
  transaction: Cell,
  isInitialized?: boolean,
) {
  const boc = buildExternalBoc(wallet, transaction, isInitialized);
  const emulation = await fetchEmulateTrace(network, boc);
  const walletAddress = toBase64Address(wallet.address, false, network);
  const nftSuperCollectionsByCollectionAddress = await getNftSuperCollectionsByCollectionAddress();
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
    transactions: emulation.transactions,
  });

  const allActivities = parseActions(
    network,
    walletAddress,
    emulation.actions,
    emulation.address_book,
    emulation.metadata,
    nftSuperCollectionsByCollectionAddress,
  );

  const walletActivities: ApiActivity[] = [];
  let totalRealFee = 0n;
  let totalExcess = 0n;

  for (let activity of allActivities) {
    if (
      activity.shouldHide || (
        activity.kind === 'transaction'
        && activity.fromAddress !== walletAddress
        && activity.toAddress !== walletAddress
      )) {
      continue;
    }

    if (activity.shouldLoadDetails) {
      const result = calculateActivityDetails(activity, parsedTrace, true);
      if (result) {
        activity = result.activity;
        totalExcess += result.excess;
      } else {
        logDebugError('Unparsable trace for emulated activity', activity.id);
      }
    }

    walletActivities.push(activity);
    totalRealFee += getActivityRealFee(activity);
  }

  if (totalExcess) {
    addExcessActivity(walletAddress, walletActivities, totalExcess);
  }

  return {
    networkFee: parsedTrace.totalNetworkFee,
    received: parsedTrace.totalReceived,
    byTransactionIndex: parsedTrace.byTransactionIndex,
    activities: walletActivities,
    realFee: totalRealFee,
  };
}

function addExcessActivity(walletAddress: string, activities: ApiActivity[], excess: bigint) {
  const index = activities.findIndex((activity) => {
    return activity.kind === 'transaction' && activity.type === 'excess';
  });

  if (index !== -1) {
    const excessActivity = activities.splice(index, 1)[0] as ApiTransactionActivity;
    activities.push({
      ...excessActivity,
      amount: excessActivity.amount + excess,
    });
  } else {
    activities.push({
      id: FAKE_TX_ID,
      timestamp: activities[activities.length - 1].timestamp,
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

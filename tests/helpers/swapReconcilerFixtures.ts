/* eslint-disable @typescript-eslint/no-require-imports */
import type { AddressBook, AnyAction, MetadataMap, SocketFinality } from '../../src/api/chains/ton/toncenter/types';
import type { ApiActivity, ApiSwapActivity, ApiSwapHistoryItem } from '../../src/api/types';

import { parseActionsToActivities } from '../../src/api/chains/ton/toncenter/actions';
import { convertSwapItemToTrusted, swapItemToActivity } from '../../src/api/common/swap';

type ActionsPage = {
  actions: AnyAction[];
  address_book: AddressBook;
  metadata?: MetadataMap;
};

type ActionsSocketMessage = ActionsPage & {
  type: 'actions';
  finality: SocketFinality;
  trace_external_hash_norm: string;
  actions: (AnyAction & { accounts?: string[] })[];
};

type BackendHistoryCall = {
  url: string;
  request: Record<string, unknown> | null;
  response: ApiSwapHistoryItem[] | ApiSwapHistoryItem;
};

export const meta = require('../fixtures/swapReconciler/meta.json') as {
  wallet: string;
  rawWallet: string;
  case1ExternalMsgHashNorm: string;
  case2ExternalMsgHashNorm: string;
  case1SwapId: string;
  case2SwapId: string;
};

/** The BIP39 test wallet of the Near Intents recording (TON address derived through m/44'/607'/0'). */
export const wallet2 = {
  wallet: 'UQA6pbkpoEyE-jBbK9uz-APkGAUO-yHhDXyavP0TM8JXVB2X',
  rawWallet: '0:3AA5B929A04C84FA305B2BDBB3F803E418050EFB21E10D7C9ABCFD1333C25754',
};

/** The 12-word BIP39 test wallet of the Changelly recording. */
export const wallet3 = {
  wallet: 'UQDblBmVhYA7El2pBcViUpRJvbtf4IoygDdSIMFrvQPoHlwo',
  rawWallet: '0:DB94199585803B125DA905C562529449BDBB5FE08A3280375220C16BBD03E81E',
};

export const fixtures = {
  initialActions: require('../fixtures/swapReconciler/initial-actions.json') as ActionsPage,
  initialBackendHistory: require('../fixtures/swapReconciler/initial-backend-history.json') as BackendHistoryCall[],
  case1WsActions: require('../fixtures/swapReconciler/case1-ws-actions.json') as ActionsSocketMessage[],
  case1Backend: require('../fixtures/swapReconciler/case1-backend.json') as {
    buildTransaction: { id: string };
    history: BackendHistoryCall[];
  },
  case2WsActions: require('../fixtures/swapReconciler/case2-ws-actions.json') as ActionsSocketMessage[],
  case2Backend: require('../fixtures/swapReconciler/case2-backend.json') as {
    buildTransaction: { id: string };
    history: BackendHistoryCall[];
  },
  reload1DeltaActions: require('../fixtures/swapReconciler/reload1-delta-actions.json') as {
    url: string;
    response: ActionsPage;
  },
  reload1BackendHistory: require('../fixtures/swapReconciler/reload1-backend-history.json') as BackendHistoryCall[],
  reload1CachedState: require('../fixtures/swapReconciler/reload1-cached-state.json') as { top: ApiActivity[] },
  // GRAM -> SOL through Near Intents from the second wallet: deposit trace on TON, payout on Solana
  nearIntentsWsActions: require('../fixtures/swapReconciler/swap-2545651-ws-actions.json') as ActionsSocketMessage[],
  nearIntentsBackend: require('../fixtures/swapReconciler/swap-2545651-backend.json') as {
    buildTransaction: { swap: ApiSwapHistoryItem };
    history: BackendHistoryCall[];
    swapRowVersions: ApiSwapHistoryItem[];
  },
  // SOL -> GRAM through Near Intents from the second wallet: deposit on Solana, payout trace on TON
  nearIntentsPayoutWsActions: require(
    '../fixtures/swapReconciler/swap-2545664-ws-actions.json',
  ) as ActionsSocketMessage[],
  nearIntentsPayoutBackend: require('../fixtures/swapReconciler/swap-2545664-backend.json') as {
    buildTransaction: { swap: ApiSwapHistoryItem };
    history: BackendHistoryCall[];
    swapRowVersions: ApiSwapHistoryItem[];
  },
  /** `/traces?msg_hash=…&include_actions=true` for the Omniston trace of case 2, as the details loader requests it */
  case2Trace: require('../fixtures/swapReconciler/case2-trace.json') as {
    traces: [{ actions: AnyAction[]; trace: unknown; transactions: Record<string, unknown> }];
    address_book: AddressBook;
    metadata: MetadataMap;
  },
  // HMSTR -> BOLT through Omniston from the third wallet: STON.fi HMSTR -> TON, then DeDust TON -> BOLT, where the
  // TON of the first hop goes to the router and never reaches the wallet
  omnistonTwoHopWsActions: require('../fixtures/swapReconciler/swap-2551567-ws-actions.json') as ActionsSocketMessage[],
  omnistonTwoHopBackend: require('../fixtures/swapReconciler/swap-2551567-backend.json') as { row: ApiSwapHistoryItem },
  /** `/traces?msg_hash=…&include_actions=true` for the Omniston two-hop trace, as the details loader requests it */
  omnistonTwoHopTrace: require('../fixtures/swapReconciler/swap-2551567-trace.json') as {
    traces: [{ actions: AnyAction[]; trace: unknown; transactions: Record<string, unknown> }];
    address_book: AddressBook;
    metadata: MetadataMap;
  },
  /** A DeDust-router HMSTR -> TON swap of the third wallet split over STON.fi and DeDust: both legs pay TON to the wallet */
  dedustJettonToTonTrace: require('../fixtures/swapReconciler/swap-2504807-trace.json') as {
    traces: [{ actions: AnyAction[]; trace: unknown; transactions: Record<string, unknown> }];
    address_book: AddressBook;
    metadata: MetadataMap;
  },
  // GRAM -> HYPE through Changelly from the third wallet: deposit trace on TON, payout on Hyperliquid
  changellyWsActions: require('../fixtures/swapReconciler/swap-2545759-ws-actions.json') as ActionsSocketMessage[],
  changellyBackend: require('../fixtures/swapReconciler/swap-2545759-backend.json') as {
    buildTransaction: { swap: ApiSwapHistoryItem };
    history: BackendHistoryCall[];
    swapRowVersions: ApiSwapHistoryItem[];
  },
};

/** Parses a recorded Toncenter `/actions` or `/pendingActions` page the way the polling does. */
export function activitiesFromActionsPage(page: ActionsPage, isPending = false): ApiActivity[] {
  return parseActionsToActivities(page.actions, {
    network: 'mainnet',
    walletAddress: meta.wallet,
    addressBook: page.address_book,
    metadata: page.metadata ?? {},
    nftSuperCollectionsByCollectionAddress: {},
    isPending,
  });
}

/** Parses a recorded Toncenter streaming `actions` message the way the socket does for the test wallet. */
export function activitiesFromSocketMessage(
  message: ActionsSocketMessage,
  owner: { wallet: string; rawWallet: string } = meta,
): ApiActivity[] {
  const actions = message.actions.filter((action) => action.accounts?.includes(owner.rawWallet));

  return parseActionsToActivities(actions, {
    network: 'mainnet',
    walletAddress: owner.wallet,
    addressBook: message.address_book,
    metadata: message.metadata ?? {},
    nftSuperCollectionsByCollectionAddress: {},
    isPending: message.finality === 'pending',
    finality: message.finality,
  });
}

/** Converts recorded backend history rows into swap activities the way `swapGetHistory` + `swapItemToActivity` do. */
export function activitiesFromBackendRows(rows: ApiSwapHistoryItem[]): ApiSwapActivity[] {
  return rows.map((row) => swapItemToActivity(convertSwapItemToTrusted(row)));
}

export function backendRowsOf(calls: BackendHistoryCall[]): ApiSwapHistoryItem[] {
  const byId = new Map<string, ApiSwapHistoryItem>();
  for (const call of calls) {
    const rows = Array.isArray(call.response) ? call.response : [call.response];
    for (const row of rows) byId.set(row.id, row);
  }
  return [...byId.values()];
}

export function socketMessage(messages: ActionsSocketMessage[], finality: SocketFinality) {
  const message = messages.find((item) => item.finality === finality);
  if (!message) throw new Error(`No recorded ${finality} socket message`);
  return message;
}

export const visible = (activities: readonly ApiActivity[]) => activities.filter(({ shouldHide }) => !shouldHide);

/** The row `swapSubmit` creates at submit time: the backend row under a local id with the submitted message hash. */
export function localSwapRowOf(row: ApiSwapHistoryItem): ApiSwapActivity {
  const [backendRow] = activitiesFromBackendRows([row]);
  const localActivityId = `${row.id}::local`;
  return {
    ...backendRow,
    id: localActivityId,
    externalMsgHashNorm: row.hashes[0],
    extra: {
      reconciliation: {
        operationId: `swap:${row.id}`,
        sourceActionIds: [localActivityId],
        hiddenSourceActionIds: [],
        reason: 'local-intent',
      },
    },
  };
}

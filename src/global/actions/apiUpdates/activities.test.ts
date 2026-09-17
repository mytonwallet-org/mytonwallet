import './activities';

import type { UtxoTransaction } from '../../../api/chains/utxo/types';
import type { ApiBackendActivitiesUpdate } from '../../../api/common/backendSocket';
import type { ApiActivity, ApiSwapActivity, ApiTransactionActivity, OnApiUpdate } from '../../../api/types';
import type { GlobalState } from '../../types';

import { callApi } from '../../../api';
import { setupUtxoBackendActivityTracking } from '../../../api/chains/utxo/polling';
import { getUtxoBackendSocket } from '../../../api/common/backendSocket';
import { getActions, getGlobal, setGlobal } from '../../index';
import { INITIAL_STATE } from '../../initialState';

jest.mock('../../../api', () => ({
  callApi: jest.fn(),
}));

jest.mock('../../../api/common/backendSocket', () => ({
  getUtxoBackendSocket: jest.fn(),
}));

jest.mock('../../../util/notificationSound', () => ({
  playIncomingTransactionSound: jest.fn(),
}));

const ACCOUNT_ID = 'account-1';

const BTC_ADDRESS = 'bc1qvmw9dmensxtuxu5vw7mxtxqurad2u99pdj9wwa';
const BTC_SENDER_ADDRESS = '1BoatSLRHtKNngkdXEeobR76b53LETtpyT';

function makeUtxoRawTransaction(txId: string): UtxoTransaction {
  return {
    txid: txId,
    confirmations: 1,
    blockTime: 1_700_000_000,
    fees: '100',
    vin: [{ addresses: [BTC_SENDER_ADDRESS], value: '1000' }],
    vout: [{ addresses: [BTC_ADDRESS], value: '900', n: 0 }],
  };
}

function mockBackendWatcher() {
  let callback: ((update: ApiBackendActivitiesUpdate) => void) | undefined;
  const watchWallets = jest.fn((_wallets, options) => {
    callback = options.onNewActivities;
    return { destroy: jest.fn() };
  });

  (getUtxoBackendSocket as jest.Mock).mockReturnValue({ watchWallets });

  return {
    emit(update: ApiBackendActivitiesUpdate) {
      callback?.(update);
    },
  };
}

function makePendingCexSwap(overrides: Partial<ApiSwapActivity> = {}): ApiSwapActivity {
  return {
    kind: 'swap',
    id: 'backend-swap-id::backend-swap',
    timestamp: 1_700_000_000_000,
    from: 'trx',
    fromAmount: '10',
    fromAddress: 'trx-source',
    to: 'toncoin',
    toAmount: '5',
    networkFee: '0.1',
    swapFee: '0',
    status: 'pendingTrusted',
    hashes: [],
    cex: { payinAddress: 'trx-payin', payoutAddress: 'ton-payout', status: 'waiting', transactionId: 'cex-tx-id' },
    ...overrides,
  } as ApiSwapActivity;
}

function makeRawReceive(overrides: Partial<ApiTransactionActivity> = {}): ApiTransactionActivity {
  return {
    kind: 'transaction',
    id: 'ton-payout-hash',
    timestamp: 1_700_000_001_000,
    amount: 5n,
    fromAddress: 'sender',
    toAddress: 'ton-payout',
    normalizedAddress: 'sender',
    fee: 0n,
    slug: 'toncoin',
    isIncoming: true,
    status: 'completed',
    ...overrides,
  };
}

function buildGlobal(activities: ApiActivity[]): GlobalState {
  return {
    ...INITIAL_STATE,
    currentAccountId: ACCOUNT_ID,
    accounts: {
      byId: {
        [ACCOUNT_ID]: { type: 'mnemonic', byChain: { ton: { address: 'EQ-account' } } },
      },
    },
    byAccountId: {
      [ACCOUNT_ID]: {
        activities: {
          byId: Object.fromEntries(activities.map((activity) => [activity.id, activity])),
          idsMain: activities.map(({ id }) => id),
          localActivityIds: activities.filter(({ id }) => id.endsWith(':local')).map(({ id }) => id),
        },
      },
    },
  } as GlobalState;
}

function getAccountActivities() {
  return getGlobal().byAccountId[ACCOUNT_ID].activities!;
}

describe('apiUpdate activity reconciliation bridge', () => {
  beforeEach(() => {
    jest.useRealTimers();
    jest.clearAllMocks();
    setGlobal(buildGlobal([makePendingCexSwap()]));
  });

  it('applies UTXO confirmation metadata through generic newActivities', async () => {
    const bitcoinActivity = makeRawReceive({
      id: 'btc-tx-id',
      slug: 'bitcoin',
      status: 'pending',
      confirmations: 1,
      maxConfirmations: 2,
      etaSeconds: 600,
    });
    setGlobal(buildGlobal([]));
    (callApi as jest.Mock).mockResolvedValue(undefined);

    await (getActions().apiUpdate({
      type: 'newActivities',
      accountId: ACCOUNT_ID,
      activities: [bitcoinActivity],
      chain: 'bitcoin',
    }) as unknown as Promise<void>);

    expect(callApi).toHaveBeenCalledWith(
      'reconcileActivityUpdate',
      ACCOUNT_ID,
      [],
      [bitcoinActivity],
      undefined,
      expect.any(Object),
    );
    expect(getAccountActivities().byId[bitcoinActivity.id]).toEqual(expect.objectContaining({
      confirmations: 1,
      maxConfirmations: 2,
      etaSeconds: 600,
      status: 'pending',
    }));
    expect(getAccountActivities().pendingActivityIds?.bitcoin).toEqual([bitcoinActivity.id]);
  });

  it.each([
    { etaSeconds: undefined, expectedEtaSeconds: 600 },
    { etaSeconds: 300, expectedEtaSeconds: 300 },
    { etaSeconds: 0, expectedEtaSeconds: 0 },
  ])('merges UTXO ETA when a partial newActivities update provides $etaSeconds', async ({
    etaSeconds,
    expectedEtaSeconds,
  }) => {
    const bitcoinActivity = makeRawReceive({
      id: 'btc-tx-id',
      slug: 'bitcoin',
      status: 'pending',
      confirmations: 0,
      maxConfirmations: 2,
      etaSeconds: 600,
    });
    const updatedActivity = {
      ...bitcoinActivity,
      confirmations: 1,
      etaSeconds,
    };
    const global = buildGlobal([bitcoinActivity]);
    global.byAccountId[ACCOUNT_ID].activities!.pendingActivityIds = { bitcoin: [bitcoinActivity.id] };
    setGlobal(global);
    (callApi as jest.Mock).mockResolvedValue(undefined);

    await (getActions().apiUpdate({
      type: 'newActivities',
      accountId: ACCOUNT_ID,
      activities: [updatedActivity],
      chain: 'bitcoin',
    }) as unknown as Promise<void>);

    expect(getAccountActivities().byId[bitcoinActivity.id]).toEqual(expect.objectContaining({
      confirmations: 1,
      maxConfirmations: 2,
      status: 'pending',
      etaSeconds: expectedEtaSeconds,
    }));
  });

  it('tracks pending UTXO activities from generic newActivities when chain is present', async () => {
    const bitcoinActivity = makeRawReceive({
      id: 'btc-new-pending-tx-id',
      slug: 'bitcoin',
      status: 'pending',
      confirmations: 1,
      maxConfirmations: 2,
    });
    setGlobal(buildGlobal([]));
    (callApi as jest.Mock).mockResolvedValue({
      confirmedActivities: [bitcoinActivity],
      pendingActivities: [],
      patch: { accountId: ACCOUNT_ID, upsert: [bitcoinActivity], removeIds: [] },
    });

    await (getActions().apiUpdate({
      type: 'newActivities',
      accountId: ACCOUNT_ID,
      activities: [bitcoinActivity],
      pendingActivities: [],
      chain: 'bitcoin',
    }) as unknown as Promise<void>);

    expect(getAccountActivities().byId[bitcoinActivity.id]).toEqual(expect.objectContaining({
      confirmations: 1,
      maxConfirmations: 2,
      status: 'pending',
    }));
    expect(getAccountActivities().pendingActivityIds?.bitcoin).toEqual([bitcoinActivity.id]);
  });

  it('preserves existing pending UTXO activities when partial updates omit pendingActivities', async () => {
    const pendingActivity = makeRawReceive({
      id: 'btc-pending-a',
      slug: 'bitcoin',
      status: 'pending',
      confirmations: 1,
      maxConfirmations: 2,
    });
    const newActivity = makeRawReceive({
      id: 'btc-new-b',
      slug: 'bitcoin',
      status: 'completed',
      confirmations: 2,
      maxConfirmations: 2,
      timestamp: pendingActivity.timestamp + 1,
    });
    const global = buildGlobal([pendingActivity]);
    global.byAccountId[ACCOUNT_ID].activities!.pendingActivityIds = { bitcoin: [pendingActivity.id] };
    setGlobal(global);
    (callApi as jest.Mock).mockResolvedValue(undefined);

    await (getActions().apiUpdate({
      type: 'newActivities',
      accountId: ACCOUNT_ID,
      activities: [newActivity],
      chain: 'bitcoin',
    }) as unknown as Promise<void>);

    const activities = getAccountActivities();
    expect(activities.byId[pendingActivity.id]).toEqual(expect.objectContaining({
      confirmations: 1,
      maxConfirmations: 2,
      status: 'pending',
    }));
    expect(activities.byId[newActivity.id]).toEqual(expect.objectContaining({
      confirmations: 2,
      maxConfirmations: 2,
      status: 'completed',
    }));
    expect(activities.pendingActivityIds?.bitcoin).toEqual([pendingActivity.id]);
    expect(activities.idsMain).toEqual(expect.arrayContaining([pendingActivity.id, newActivity.id]));
  });

  it('reconciles a UTXO socket row with an existing local pendingTrusted row', async () => {
    const accountId = '0-mainnet';
    const txId = 'btc-network-tx-id';
    const watcher = mockBackendWatcher();
    const dispatchedUpdates: Promise<void>[] = [];
    const onUpdate: OnApiUpdate = (update) => {
      dispatchedUpdates.push(getActions().apiUpdate(update) as unknown as Promise<void>);
    };
    const localActivity = makeRawReceive({
      id: `${txId}::local`,
      slug: 'bitcoin',
      status: 'pendingTrusted',
      confirmations: 0,
      maxConfirmations: 2,
    });
    const parsedActivity = makeRawReceive({
      id: txId,
      slug: 'bitcoin',
      status: 'pending',
      confirmations: 1,
      maxConfirmations: 2,
      etaSeconds: 600,
      timestamp: localActivity.timestamp + 1,
    });
    const trustedParsedActivity = {
      ...parsedActivity,
      status: 'pendingTrusted' as const,
    };
    setGlobal({
      ...buildGlobal([localActivity]),
      currentAccountId: accountId,
      accounts: {
        byId: {
          [accountId]: {
            type: 'mnemonic',
            byChain: { bitcoin: { address: BTC_ADDRESS } },
          },
        },
      },
      byAccountId: {
        [accountId]: buildGlobal([localActivity]).byAccountId[ACCOUNT_ID],
      },
    } as GlobalState);
    (callApi as jest.Mock).mockImplementation((method: string) => {
      if (method === 'reconcileActivityUpdate') {
        return Promise.resolve({
          confirmedActivities: [trustedParsedActivity],
          patch: {
            accountId,
            upsert: [trustedParsedActivity],
            removeIds: [localActivity.id],
            replacedIds: { [localActivity.id]: parsedActivity.id },
          },
        });
      }
      return Promise.resolve(undefined);
    });

    setupUtxoBackendActivityTracking('bitcoin', accountId, BTC_ADDRESS, jest.fn(), onUpdate);
    watcher.emit({
      address: BTC_ADDRESS,
      utxoActivityUpdate: {
        type: 'utxoActivityUpdate',
        chain: 'bitcoin',
        address: BTC_ADDRESS,
        txId,
        confirmations: 1,
        maxConfirmations: 2,
        etaSeconds: 600,
        status: 'pending',
        blockHeight: 966489,
        blockHash: 'block-1',
        rawTransaction: makeUtxoRawTransaction(txId),
      },
    });
    await Promise.all(dispatchedUpdates);

    const activities = getGlobal().byAccountId[accountId].activities!;
    expect(callApi).toHaveBeenCalledTimes(1);
    expect(callApi).toHaveBeenCalledWith(
      'reconcileActivityUpdate',
      accountId,
      [localActivity],
      [expect.objectContaining({
        id: txId,
        confirmations: 1,
        maxConfirmations: 2,
        etaSeconds: 600,
        status: 'pending',
      })],
      undefined,
      expect.any(Object),
    );
    expect(activities.byId[localActivity.id]).toBeUndefined();
    expect(activities.byId[txId]).toEqual(expect.objectContaining({
      id: txId,
      confirmations: 1,
      maxConfirmations: 2,
      etaSeconds: 600,
      status: 'pendingTrusted',
    }));
    expect(activities.idsMain).toEqual([txId]);
    expect(activities.localActivityIds).toEqual([]);
    expect(activities.pendingActivityIds?.bitcoin).toEqual([txId]);
  });

  it('hides incoming raw receive in the same committed state when forced refresh returns matching hash', async () => {
    const rawReceive = makeRawReceive();
    const completedSwap = makePendingCexSwap({
      status: 'completed',
      hashes: [rawReceive.id],
      timestamp: rawReceive.timestamp + 1,
    });
    (callApi as jest.Mock).mockResolvedValue({
      confirmedActivities: [completedSwap, { ...rawReceive, shouldHide: true }],
      pendingActivities: [],
      patch: {
        accountId: ACCOUNT_ID,
        upsert: [completedSwap, { ...rawReceive, shouldHide: true }],
        removeIds: [],
      },
    });

    const actionResult = getActions().apiUpdate({
      type: 'newActivities',
      accountId: ACCOUNT_ID,
      activities: [rawReceive],
      pendingActivities: [],
      chain: 'ton',
    }) as unknown as Promise<void>;
    await actionResult;

    const activities = getAccountActivities();
    expect(callApi).toHaveBeenCalledWith(
      'reconcileActivityUpdate',
      ACCOUNT_ID,
      [],
      [rawReceive],
      [],
      expect.objectContaining({
        contextActivities: expect.arrayContaining([expect.objectContaining({ id: rawReceive.id })]),
      }),
    );
    expect(activities.byId[rawReceive.id]?.shouldHide).toBe(true);
    expect(activities.byId[completedSwap.id]).toEqual(expect.objectContaining({ status: 'completed' }));
    expect(activities.idsMain).toContain(completedSwap.id);
  });

  it('does not commit raw receive before forced refresh resolves', async () => {
    let resolveRefresh!: (value: unknown) => void;
    (callApi as jest.Mock).mockReturnValue(new Promise((resolve) => {
      resolveRefresh = resolve;
    }));
    const rawReceive = makeRawReceive();

    const actionPromise = getActions().apiUpdate({
      type: 'newActivities',
      accountId: ACCOUNT_ID,
      activities: [rawReceive],
      pendingActivities: [],
      chain: 'ton',
    }) as unknown as Promise<void>;

    expect(getAccountActivities().byId[rawReceive.id]).toBeUndefined();

    resolveRefresh({
      confirmedActivities: [rawReceive],
      pendingActivities: [],
      patch: { accountId: ACCOUNT_ID, upsert: [rawReceive], removeIds: [] },
    });
    await actionPromise;
    await Promise.resolve();

    expect(getAccountActivities().byId[rawReceive.id]).toEqual(expect.objectContaining({ id: rawReceive.id }));
    expect(getAccountActivities().byId[rawReceive.id]?.shouldHide).toBeUndefined();
  });

  it('serializes SDK reconciliation per account and uses the latest committed context', async () => {
    let resolveFirst!: (value: unknown) => void;
    const firstActivity = makeRawReceive({ id: 'first-activity' });
    const secondActivity = makeRawReceive({ id: 'second-activity', timestamp: firstActivity.timestamp + 1 });
    (callApi as jest.Mock)
      .mockImplementationOnce(() => new Promise((resolve) => {
        resolveFirst = resolve;
      }))
      .mockResolvedValueOnce({
        confirmedActivities: [secondActivity],
        pendingActivities: [],
        patch: { accountId: ACCOUNT_ID, upsert: [secondActivity], removeIds: [] },
      });

    const firstAction = getActions().apiUpdate({
      type: 'newActivities',
      accountId: ACCOUNT_ID,
      activities: [firstActivity],
      pendingActivities: [],
      chain: 'ton',
    }) as unknown as Promise<void>;
    const secondAction = getActions().apiUpdate({
      type: 'newActivities',
      accountId: ACCOUNT_ID,
      activities: [secondActivity],
      pendingActivities: [],
      chain: 'ton',
    }) as unknown as Promise<void>;

    await Promise.resolve();
    expect(callApi).toHaveBeenCalledTimes(1);

    resolveFirst({
      confirmedActivities: [firstActivity],
      pendingActivities: [],
      patch: { accountId: ACCOUNT_ID, upsert: [firstActivity], removeIds: [] },
    });
    await Promise.all([firstAction, secondAction]);

    expect(callApi).toHaveBeenCalledTimes(2);
    expect((callApi as jest.Mock).mock.calls[1][5]).toEqual(expect.objectContaining({
      contextActivities: expect.arrayContaining([expect.objectContaining({ id: firstActivity.id })]),
    }));
    expect(getAccountActivities().byId[firstActivity.id]).toBeDefined();
    expect(getAccountActivities().byId[secondActivity.id]).toBeDefined();
  });

  it('commits raw receive visibly when shared SDK reconciliation returns fail-closed raw output', async () => {
    const rawReceive = makeRawReceive();
    (callApi as jest.Mock).mockResolvedValue({
      confirmedActivities: [rawReceive],
      pendingActivities: [],
      patch: { accountId: ACCOUNT_ID, upsert: [rawReceive], removeIds: [] },
    });

    await (getActions().apiUpdate({
      type: 'newActivities',
      accountId: ACCOUNT_ID,
      activities: [rawReceive],
      pendingActivities: [],
      chain: 'ton',
    }) as unknown as Promise<void>);

    expect(getAccountActivities().byId[rawReceive.id]).toEqual(expect.objectContaining({ id: rawReceive.id }));
    expect(getAccountActivities().byId[rawReceive.id]?.shouldHide).toBeUndefined();
  });

  it('does not infer local replacements when SDK reconciliation is unavailable', async () => {
    const localActivity = makeRawReceive({
      id: 'local-hash::local',
      status: 'pendingTrusted',
      externalMsgHashNorm: 'shared-hash',
    });
    const confirmedActivity = makeRawReceive({
      id: 'confirmed-hash',
      externalMsgHashNorm: 'shared-hash',
    });
    setGlobal(buildGlobal([localActivity]));
    (callApi as jest.Mock).mockResolvedValue(undefined);

    await (getActions().apiUpdate({
      type: 'newActivities',
      accountId: ACCOUNT_ID,
      activities: [confirmedActivity],
      pendingActivities: [],
      chain: 'ton',
    }) as unknown as Promise<void>);

    expect(getAccountActivities().byId[localActivity.id]?.id).toBe(localActivity.id);
    expect(getAccountActivities().byId[localActivity.id]?.shouldHide).toBeUndefined();
    expect(getAccountActivities().byId[confirmedActivity.id]?.id).toBe(confirmedActivity.id);
    expect(getAccountActivities().byId[confirmedActivity.id]?.shouldHide).toBeUndefined();
  });

  it('keeps a new local activity visible when SDK reconciliation is unavailable', async () => {
    const chainActivity = makeRawReceive({ id: 'chain-id', externalMsgHashNorm: 'shared-hash' });
    const localActivity = makeRawReceive({
      id: 'local-id::local',
      status: 'pendingTrusted',
      externalMsgHashNorm: 'shared-hash',
    });
    setGlobal(buildGlobal([chainActivity]));
    (callApi as jest.Mock).mockResolvedValue(undefined);

    await (getActions().apiUpdate({
      type: 'newLocalActivities',
      accountId: ACCOUNT_ID,
      activities: [localActivity],
    }) as unknown as Promise<void>);

    expect(callApi).toHaveBeenCalledWith(
      'reconcileActivityUpdate',
      ACCOUNT_ID,
      [localActivity],
      [chainActivity],
      undefined,
    );
    expect(getAccountActivities().byId[localActivity.id]?.id).toBe(localActivity.id);
    expect(getAccountActivities().byId[localActivity.id]?.shouldHide).toBeUndefined();
  });

  it('removes a replaced local activity exactly as requested by the SDK patch', async () => {
    const chainActivity = makeRawReceive({
      id: 'chain-id',
      status: 'pending',
      externalMsgHashNorm: 'shared-hash',
    });
    const trustedChainActivity = { ...chainActivity, status: 'pendingTrusted' as const };
    const localActivity = makeRawReceive({
      id: 'local-id::local',
      status: 'pendingTrusted',
      externalMsgHashNorm: 'shared-hash',
    });
    setGlobal(buildGlobal([chainActivity]));
    (callApi as jest.Mock).mockResolvedValue({
      confirmedActivities: [trustedChainActivity],
      patch: {
        accountId: ACCOUNT_ID,
        upsert: [trustedChainActivity],
        removeIds: [localActivity.id],
        replacedIds: { [localActivity.id]: chainActivity.id },
      },
    });

    await (getActions().apiUpdate({
      type: 'newLocalActivities',
      accountId: ACCOUNT_ID,
      activities: [localActivity],
    }) as unknown as Promise<void>);

    expect(getAccountActivities().byId[localActivity.id]).toBeUndefined();
    expect(getAccountActivities().byId[chainActivity.id]).toEqual(expect.objectContaining({
      id: chainActivity.id,
      status: 'pendingTrusted',
    }));
  });

  it('stores a hidden local activity only when the SDK patch explicitly upserts it as hidden', async () => {
    const localActivity = makeRawReceive({
      id: 'local-id::local',
      status: 'pendingTrusted',
    });
    const hiddenLocalActivity = { ...localActivity, shouldHide: true };
    (callApi as jest.Mock).mockResolvedValue({
      confirmedActivities: [hiddenLocalActivity],
      patch: {
        accountId: ACCOUNT_ID,
        upsert: [hiddenLocalActivity],
        removeIds: [],
        replacedIds: {},
      },
    });

    await (getActions().apiUpdate({
      type: 'newLocalActivities',
      accountId: ACCOUNT_ID,
      activities: [localActivity],
    }) as unknown as Promise<void>);

    expect(getAccountActivities().byId[localActivity.id]).toEqual(expect.objectContaining({
      id: localActivity.id,
      shouldHide: true,
    }));
  });

  it('commits the SDK patch after generic indexing without merging stale reconciliation metadata', async () => {
    const existing = makeRawReceive({
      id: 'same-id',
      extra: {
        reconciliation: {
          operationId: 'operation-1',
          sourceActionIds: ['same-id', 'old-source'],
          hiddenSourceActionIds: ['old-source'],
          reason: 'cex-swap',
        },
      },
    });
    const authoritative = {
      ...existing,
      extra: {
        reconciliation: {
          operationId: 'operation-1',
          sourceActionIds: ['same-id', 'new-source'],
          hiddenSourceActionIds: ['new-source'],
          reason: 'cex-swap' as const,
        },
      },
    };
    setGlobal(buildGlobal([existing]));
    (callApi as jest.Mock).mockResolvedValue({
      confirmedActivities: [authoritative],
      pendingActivities: [],
      patch: { accountId: ACCOUNT_ID, upsert: [authoritative], removeIds: [], replacedIds: {} },
    });

    await (getActions().apiUpdate({
      type: 'newActivities',
      accountId: ACCOUNT_ID,
      activities: [authoritative],
      pendingActivities: [],
      chain: 'ton',
    }) as unknown as Promise<void>);

    expect(getAccountActivities().byId[authoritative.id]).toBe(authoritative);
  });
});

describe('NFT trade visibility', () => {
  // For `nftTrade` the `isIncoming` flag shows the TONCOIN direction, so a purchase looks like an outgoing transfer
  function makeNftTrade(isBuying: boolean): ApiTransactionActivity {
    return makeRawReceive({
      id: 'nft-trade-hash',
      type: 'nftTrade',
      isIncoming: !isBuying,
      nft: {
        chain: 'ton',
        interface: 'default',
        index: 0,
        address: 'EQAglL_g6q2AhMK_BT9jN1F-8jBlv2pOI30vRkPluU9kcXgV',
        thumbnail: '',
        image: '',
        isOnSale: false,
        isUnverified: true,
        metadata: {},
      },
    });
  }

  beforeEach(() => {
    jest.clearAllMocks();
    (callApi as jest.Mock).mockResolvedValue(undefined);
    setGlobal(buildGlobal([]));
  });

  it('whitelists a bought NFT so an unverified collection does not hide it', async () => {
    const trade = makeNftTrade(true);

    await (getActions().apiUpdate({
      type: 'newActivities',
      accountId: ACCOUNT_ID,
      activities: [trade],
      pendingActivities: [],
      chain: 'ton',
    }) as unknown as Promise<void>);

    const accountState = getGlobal().byAccountId[ACCOUNT_ID];
    expect(accountState.nfts?.byAddress?.[trade.nft!.address]).toBeDefined();
    expect(accountState.whitelistedNftAddresses).toEqual([trade.nft!.address]);
  });

  it('does not whitelist a sold NFT', async () => {
    const trade = makeNftTrade(false);

    await (getActions().apiUpdate({
      type: 'newActivities',
      accountId: ACCOUNT_ID,
      activities: [trade],
      pendingActivities: [],
      chain: 'ton',
    }) as unknown as Promise<void>);

    const accountState = getGlobal().byAccountId[ACCOUNT_ID];
    expect(accountState.nfts?.byAddress?.[trade.nft!.address]).toBeUndefined();
    expect(accountState.whitelistedNftAddresses).toBeUndefined();
  });
});

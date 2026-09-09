import type { ApiActivity, ApiSwapActivity, ApiTransactionActivity } from '../../types';

import {
  activitiesFromActionsPage,
  activitiesFromBackendRows,
  activitiesFromSocketMessage,
  backendRowsOf,
  fixtures,
  localSwapRowOf,
  meta,
  socketMessage,
  visible,
  wallet2,
  wallet3,
} from '../../../../tests/helpers/swapReconcilerFixtures';
import { projectSwapActivities, reconcileActivityUpdate } from './swapReconciler';

const NOW = 1_788_462_500_000;

const ids = (activities: readonly ApiActivity[]) => activities.map(({ id }) => id);
const idsWithStatus = (activities: readonly ApiActivity[]) => activities.map(({ id, status }) => [id, status]);
const hiddenIds = (activities: readonly ApiActivity[]) => ids(activities.filter(({ shouldHide }) => shouldHide));
const findOutgoingTransfer = (activities: readonly ApiActivity[]) => activities.find((activity) => {
  return activity.kind === 'transaction' && !activity.isIncoming && Boolean(activity.externalMsgHashNorm);
})!;

describe('projectSwapActivities', () => {
  it('shows one completed backend row for a finalized Omniston swap and hides its trace actions', () => {
    const chainRows = activitiesFromSocketMessage(socketMessage(fixtures.case2WsActions, 'finalized'));
    const [backendRow] = activitiesFromBackendRows(backendRowsOf(fixtures.case2Backend.history));
    expect(backendRow.status).toBe('pendingTrusted'); // the backend still says `pending`

    const projected = projectSwapActivities(chainRows, [backendRow], {
      fromTime: chainRows[0].timestamp,
      toTime: NOW,
    });

    const visibleRows = visible(projected);
    expect(visibleRows).toHaveLength(1);
    const [swap] = visibleRows as ApiSwapActivity[];
    expect(swap.id).toBe(`${meta.case2SwapId}::backend-swap`);
    expect(swap.status).toBe('completed');
    expect(swap.fromAmount).toBe('50.000000000000000000');
    expect(swap.toAmount).toBe('5739.70168589');
    expect(swap.extra?.mtwAggregator).toEqual({
      traceId: 'llavy3Q/XBVWY/2TFi6RXeh7N1c1bwaHMm0T43ny0O8=',
      swapIds: [chainRows[0].id],
      from: 'ton-eqd0vdsane',
      to: 'ton-eqaj8uwd7e',
    });
    expect(swap.externalMsgHashNorm).toBe(chainRows[0].externalMsgHashNorm); // the details loader reads the trace by it

    expect(hiddenIds(projected).sort()).toEqual(ids(chainRows).sort());
    for (const activity of projected) {
      expect(activity.extra?.reconciliation).toEqual({
        operationId: `swap:${meta.case2SwapId}`,
        sourceActionIds: [swap.id, ...ids(chainRows)],
        hiddenSourceActionIds: ids(chainRows),
        reason: 'ton-aggregated-swap',
      });
    }
  });

  it('shows one completed backend row for a finalized DeDust router swap whose fee transfer is already hidden', () => {
    const chainRows = activitiesFromSocketMessage(socketMessage(fixtures.case1WsActions, 'finalized'));
    const [backendRow] = activitiesFromBackendRows(backendRowsOf(fixtures.case1Backend.history));

    const projected = projectSwapActivities(chainRows, [backendRow], {
      fromTime: chainRows[0].timestamp,
      toTime: NOW,
    });

    const [swap] = visible(projected) as ApiSwapActivity[];
    expect(visible(projected)).toHaveLength(1);
    expect(swap.id).toBe(`${meta.case1SwapId}::backend-swap`);
    expect(swap.status).toBe('completed');
    expect(swap.fromAmount).toBe('0.050000000000000000');
    expect(swap.toAmount).toBe('0.067386'); // what the trace delivered, not the 0.067272 quote
    expect(hiddenIds(projected).sort()).toEqual(ids(chainRows).sort());
  });

  it('does not summarize a swap predicted for a dapp transaction under its local row', () => {
    // A local swap row without the built-in swap's intent marker (a TonConnect prediction) owns nothing
    const chainRows = activitiesFromSocketMessage(socketMessage(fixtures.case2WsActions, 'finalized'));
    const [leg] = chainRows;
    const dappLocalRow = {
      ...leg, id: `${leg.externalMsgHashNorm}:0:local`, status: 'pending' as const, extra: undefined,
    };

    const result = reconcileActivityUpdate([dappLocalRow], chainRows, []);

    expect(ids(visible(result.confirmedActivities))).toEqual([leg.id]);
    expect(result.replacedIds).toEqual({ [dappLocalRow.id]: leg.id });
    expect(result.upsert.every((activity) => !activity.extra?.reconciliation)).toBe(true);
  });

  it('drops the summary row and shows the raw actions when part of the route failed', () => {
    // The recorded Omniston trace with its fee transfer bounced: one leg succeeded, the trace is not a clean route
    const [leg, feeTransfer] = activitiesFromSocketMessage(socketMessage(fixtures.case2WsActions, 'finalized'));
    const bouncedFee = { ...feeTransfer, type: 'bounced' as const, status: 'failed' as const };
    const [backendRow] = activitiesFromBackendRows(backendRowsOf(fixtures.case2Backend.history));

    const projected = projectSwapActivities([leg, bouncedFee], [backendRow], { fromTime: 0, toTime: NOW });

    // The fee transfer is hidden by the parser as our fee; the leg stays raw and the summary leaves the feed
    expect(ids(visible(projected))).toEqual([leg.id]);
    expect(projected.find(({ id }) => id === backendRow.id)?.shouldHide).toBe(true);
    expect(projected.find(({ id }) => id === leg.id)?.extra?.reconciliation).toBeUndefined();
    expect(projected.find(({ id }) => id === bouncedFee.id)?.extra?.reconciliation).toBeUndefined();
  });

  it('keeps a swap row that only has a failed status from the backend visible', () => {
    const [backendRow] = activitiesFromBackendRows(backendRowsOf(fixtures.case2Backend.history));
    const expiredRow = { ...backendRow, status: 'expired' as const };

    const projected = projectSwapActivities([], [expiredRow], { fromTime: 0, toTime: NOW });

    expect(idsWithStatus(visible(projected))).toEqual([[expiredRow.id, 'expired']]);
  });

  it('shows a fresh history page unchanged when the backend has no rows for it', () => {
    const chainRows = activitiesFromActionsPage(fixtures.initialActions);

    const projected = projectSwapActivities(chainRows, [], { fromTime: chainRows.at(-1)!.timestamp, toTime: NOW });

    expect(ids(visible(projected))).toEqual(ids(visible(chainRows)));
    expect(projected.every((activity) => !activity.extra?.reconciliation)).toBe(true);
  });

  it('emits an unmatched backend row only inside the requested window', () => {
    const [backendRow] = activitiesFromBackendRows(backendRowsOf(fixtures.case2Backend.history));
    const { timestamp } = backendRow;

    expect(projectSwapActivities([], [backendRow], { fromTime: timestamp - 1, toTime: NOW })).toHaveLength(1);
    expect(projectSwapActivities([], [backendRow], { fromTime: timestamp + 1, toTime: NOW })).toHaveLength(0);
  });

  it('hides the deposit transfer of a CEX swap and keeps the provider status', () => {
    const chainRows = activitiesFromActionsPage(fixtures.initialActions);
    const deposit = findOutgoingTransfer(chainRows);
    const [case2Row] = backendRowsOf(fixtures.case2Backend.history);
    const [cexRow] = activitiesFromBackendRows([{
      ...case2Row,
      id: '777',
      timestamp: deposit.timestamp - 1000,
      hashes: [deposit.externalMsgHashNorm!],
      cex: { payinAddress: 'payin', payoutAddress: 'payout', status: 'waiting', transactionId: 'cex-1' },
    }]);

    const projected = projectSwapActivities(chainRows, [cexRow], {
      fromTime: chainRows.at(-1)!.timestamp,
      toTime: NOW,
    });

    const swap = projected.find(({ id }) => id === '777::backend-swap')!;
    expect(swap.status).toBe('pendingTrusted');
    expect(swap.extra?.reconciliation?.reason).toBe('cex-swap');
    expect(swap.extra?.mtwAggregator).toBeUndefined();
    expect(projected.find(({ id }) => id === deposit.id)?.shouldHide).toBe(true);
  });
});

describe('reconcileActivityUpdate', () => {
  const [case2Row] = backendRowsOf(fixtures.case2Backend.history);

  it('keeps the local swap row as the only visible row while its trace is pending', () => {
    const localRow = localSwapRowOf(case2Row);
    const pendingRows = activitiesFromSocketMessage(socketMessage(fixtures.case2WsActions, 'pending'));
    expect(pendingRows.map(({ status }) => status)).toEqual(['pending', 'pending']);

    const result = reconcileActivityUpdate([localRow], [], pendingRows);

    expect(result.replacedIds).toEqual({});
    expect(result.removeIds).toEqual([]);
    expect(idsWithStatus(visible(result.upsert))).toEqual([[localRow.id, 'pendingTrusted']]);
    expect(result.pendingActivities?.map(({ id, shouldHide }) => [id, shouldHide]))
      .toEqual(pendingRows.map(({ id }) => [id, true]));
    expect(result.confirmedActivities).toEqual([]);
  });

  it('replaces the local swap row with the backend row once the trace is finalized and enriched', () => {
    const localRow = localSwapRowOf(case2Row);
    const chainRows = activitiesFromSocketMessage(socketMessage(fixtures.case2WsActions, 'finalized'));
    const [backendRow] = activitiesFromBackendRows([case2Row]);
    const enriched = projectSwapActivities(chainRows, [backendRow], {
      fromTime: chainRows[0].timestamp,
      toTime: NOW,
    });

    const result = reconcileActivityUpdate([localRow], enriched, []);

    expect(result.replacedIds).toEqual({ [localRow.id]: backendRow.id });
    expect(result.removeIds).toEqual([localRow.id]);
    expect(idsWithStatus(visible(result.confirmedActivities))).toEqual([[backendRow.id, 'completed']]);
    expect(ids(visible(result.upsert))).toEqual([backendRow.id]);
    expect(result.pendingActivities).toEqual([]);
  });

  it('keeps the submitted hash of the local row when the backend row arrives without it', () => {
    // The wallet knows the normalized hash before its PATCH reaches the backend; a history slice fetched by time
    // window in that gap returns the row with `hashes: []`, and the finalized legs come raw with it.
    const localRow = localSwapRowOf(case2Row);
    const chainRows = activitiesFromSocketMessage(socketMessage(fixtures.case2WsActions, 'finalized'));
    const [hashlessRow] = activitiesFromBackendRows([{ ...case2Row, hashes: [] }]);
    const enriched = projectSwapActivities(chainRows, [hashlessRow], {
      fromTime: hashlessRow.timestamp,
      toTime: NOW,
    });
    expect(idsWithStatus(visible(enriched)))
      .toEqual([[chainRows[0].id, 'completed'], [hashlessRow.id, 'pendingTrusted']]);

    const result = reconcileActivityUpdate([localRow], enriched, []);

    expect(result.replacedIds).toEqual({ [localRow.id]: hashlessRow.id });
    expect(idsWithStatus(visible(result.upsert))).toEqual([[hashlessRow.id, 'completed']]);
    expect(hiddenIds(result.upsert).sort()).toEqual(ids(chainRows).sort());
  });

  it('updates a cached pendingTrusted backend row in place when the history delta arrives after a reload', () => {
    const cachedId = `${meta.case2SwapId}::backend-swap`;
    const cached = fixtures.reload1CachedState.top.find(({ id }) => id === cachedId)!;
    expect(cached.status).toBe('pendingTrusted');
    const deltaRows = activitiesFromActionsPage(fixtures.reload1DeltaActions.response);
    const [backendRow] = activitiesFromBackendRows(backendRowsOf(fixtures.reload1BackendHistory));
    expect(backendRow.status).toBe('completed');
    const enriched = projectSwapActivities(deltaRows, [backendRow], {
      fromTime: deltaRows.at(-1)!.timestamp,
      toTime: NOW,
    });

    const result = reconcileActivityUpdate([], enriched, undefined);

    expect(result.replacedIds).toEqual({});
    expect(idsWithStatus(visible(result.confirmedActivities))).toEqual([[cachedId, 'completed']]);
  });

  it('retires the local rows of a multi-action trace once the chain has finalized it', () => {
    // A dapp transaction is emulated into one local row per message under the trace's external message hash; the
    // finalized trace brings two actions under that hash, so no row pairs one to one and all of them are retired.
    const chainRows = activitiesFromSocketMessage(socketMessage(fixtures.case2WsActions, 'finalized'));
    const { externalMsgHashNorm } = chainRows[0];
    const localRows = [0, 1, 2].map((index) => ({
      ...chainRows[1],
      id: `${externalMsgHashNorm}:${index}:local`,
      status: 'pending' as const,
    }));

    const result = reconcileActivityUpdate(localRows, chainRows, []);

    // One prediction keeps a replacement (an open modal follows it to the chain row), the others are retired
    expect(Object.values(result.replacedIds)).toEqual([chainRows[1].id]);
    expect(result.removeIds.sort()).toEqual(ids(localRows).sort());
  });

  it('does not retire a local transfer without a message hash when a hashless chain row finalizes', () => {
    // Rows of other chains carry no external message hash; an absent hash must never equal another absent hash
    const chainRows = activitiesFromActionsPage(fixtures.initialActions);
    const hashless = { ...findOutgoingTransfer(chainRows), id: '0xevm-finalized', externalMsgHashNorm: undefined };
    const localRow = { ...hashless, id: '0xevm-local::local', status: 'pendingTrusted' as const };

    const result = reconcileActivityUpdate([localRow], [hashless], []);

    expect(result.removeIds).toEqual([]);
    expect(result.replacedIds).toEqual({});
  });

  it('keeps the local rows while the chain rows of the trace are still pending', () => {
    const pendingRows = activitiesFromSocketMessage(socketMessage(fixtures.case2WsActions, 'pending'));
    const { externalMsgHashNorm } = pendingRows[0];
    const localRows = [0, 1].map((index) => ({
      ...pendingRows[1],
      id: `${externalMsgHashNorm}:${index}:local`,
      status: 'pending' as const,
    }));

    const result = reconcileActivityUpdate(localRows, [], pendingRows);

    // Only the prediction the pending fee transfer replaces leaves; nothing is retired before finalization
    expect(result.removeIds).toEqual(Object.keys(result.replacedIds));
    expect(result.removeIds).toHaveLength(1);
  });

  it('replaces a local transfer with the chain transaction that carries its message hash', () => {
    const chainRows = activitiesFromActionsPage(fixtures.initialActions);
    const sent = findOutgoingTransfer(chainRows);
    const localRow = { ...sent, id: 'boc-hash::local', status: 'pendingTrusted' as const };

    const result = reconcileActivityUpdate([localRow], [sent], []);

    expect(result.replacedIds).toEqual({ [localRow.id]: sent.id });
    expect(result.removeIds).toEqual([localRow.id]);
    expect(result.confirmedActivities).toEqual([sent]);
  });
});

describe('CEX swap (Near Intents, GRAM -> SOL)', () => {
  const { swapRowVersions, nearIntentsBackend } = { ...fixtures.nearIntentsBackend, nearIntentsBackend: undefined };
  const pendingVersion = swapRowVersions.find(({ status }) => status === 'pending')!;
  const completedVersion = swapRowVersions.find(({ status }) => status === 'completed')!;
  const depositAt = (finality: 'pending' | 'finalized') => {
    return activitiesFromSocketMessage(socketMessage(fixtures.nearIntentsWsActions, finality), wallet2)[0];
  };
  const deposit = () => depositAt('pending');
  const finalizedDeposit = () => depositAt('finalized');
  const rowWithSubmittedHash = () => {
    return activitiesFromBackendRows([{ ...pendingVersion, hashes: [deposit().externalMsgHashNorm!] }])[0];
  };

  it('hides the deposit already shown as pending once the swap row carries the submitted hash', () => {
    expect(nearIntentsBackend).toBeUndefined();
    const pendingDeposit = deposit();
    expect(pendingDeposit.status).toBe('pending');

    const result = reconcileActivityUpdate([pendingDeposit], [rowWithSubmittedHash()], []);

    expect(idsWithStatus(visible(result.upsert))).toEqual([[`2545651::backend-swap`, 'pendingTrusted']]);
    const hiddenDeposit = result.upsert.find(({ id }) => id === pendingDeposit.id)!;
    expect(hiddenDeposit.shouldHide).toBe(true);
    expect(hiddenDeposit.extra?.reconciliation?.reason).toBe('cex-swap');
    expect(result.replacedIds).toEqual({});
  });

  it('hides an incoming pending deposit under a swap row the platform already holds', () => {
    const pendingDeposit = deposit();

    const result = reconcileActivityUpdate([], [], [pendingDeposit], [rowWithSubmittedHash()]);

    expect(result.pendingActivities?.map(({ shouldHide }) => shouldHide)).toEqual([true]);
    expect(ids(result.upsert)).toContain('2545651::backend-swap');
  });

  it('leaves a row hidden under a swap it does not know untouched', () => {
    const [foreignRow] = activitiesFromBackendRows(backendRowsOf(fixtures.case2Backend.history));
    const foreignChainRows = activitiesFromSocketMessage(socketMessage(fixtures.case2WsActions, 'finalized'));
    const hiddenLeg = projectSwapActivities(foreignChainRows, [foreignRow], { fromTime: 0, toTime: NOW })
      .find(({ shouldHide }) => shouldHide)!;

    const result = reconcileActivityUpdate([hiddenLeg], [rowWithSubmittedHash()], []);

    expect(ids(result.upsert)).not.toContain(hiddenLeg.id);
  });

  it('hides the deposit and the payout under the completed row by trace id and signature', () => {
    const [completedRow] = activitiesFromBackendRows([completedVersion]);
    const payoutSignature = completedVersion.transactionIds.incoming!.hash;
    const payout = {
      kind: 'transaction',
      id: payoutSignature,
      timestamp: completedRow.timestamp + 60_000,
      slug: 'sol',
      amount: 12841297n,
      isIncoming: true,
      fromAddress: 'DuSs7rCr7oTLHjM29QQ8NwDViaahTU58qqxaJVyAkgbn',
      toAddress: wallet2.wallet,
      normalizedAddress: 'DuSs7rCr7oTLHjM29QQ8NwDViaahTU58qqxaJVyAkgbn',
      fee: 0n,
      status: 'completed',
    } as ApiTransactionActivity;

    const projected = projectSwapActivities([payout, finalizedDeposit()], [completedRow], { fromTime: 0, toTime: NOW });

    expect(idsWithStatus(visible(projected))).toEqual([['2545651::backend-swap', 'completed']]);
    expect(hiddenIds(projected).sort()).toEqual([finalizedDeposit().id, payoutSignature].sort());
    expect(visible(projected)[0].extra?.mtwAggregator).toBeUndefined();
  });
});

describe('CEX swap (Near Intents, SOL -> GRAM)', () => {
  const versions = fixtures.nearIntentsPayoutBackend.swapRowVersions;
  const exchangingVersion = versions.find(({ cex }) => cex?.status === 'exchanging')!;
  const completedVersion = versions.find(({ status }) => status === 'completed')!;
  const payout = () => {
    return activitiesFromSocketMessage(socketMessage(fixtures.nearIntentsPayoutWsActions, 'finalized'), wallet2)[0];
  };

  it('keeps the payout visible while the provider has not reported it', () => {
    const [exchangingRow] = activitiesFromBackendRows([exchangingVersion]);
    expect(exchangingRow.hashes).not.toContain(parseTraceId(payout().id));

    const result = reconcileActivityUpdate([], [payout()], [], [exchangingRow]);

    expect(idsWithStatus(visible(result.confirmedActivities))).toEqual([[payout().id, 'completed']]);
    expect(ids(result.upsert)).not.toContain(exchangingRow.id);
  });

  it('hides the payout under the completed row once the provider reports its trace', () => {
    const [completedRow] = activitiesFromBackendRows([completedVersion]);
    expect(completedRow.hashes).toContain(parseTraceId(payout().id));

    const projected = projectSwapActivities([payout()], [completedRow], { fromTime: 0, toTime: NOW });

    expect(idsWithStatus(visible(projected))).toEqual([['2545664::backend-swap', 'completed']]);
    expect(hiddenIds(projected)).toEqual([payout().id]);
    expect(projected.find(({ id }) => id === payout().id)?.extra?.reconciliation?.reason).toBe('cex-swap');
  });
});

describe('CEX swap (Changelly, GRAM -> HYPE)', () => {
  const versions = fixtures.changellyBackend.swapRowVersions;
  const firstVersion = versions[0];
  const sendingVersion = versions.find(({ cex, transactionIds }) => {
    return cex?.status === 'sending' && !transactionIds.incoming;
  })!;
  const completedVersion = versions.find(({ status }) => status === 'completed')!;
  const depositAt = (finality: 'pending' | 'finalized') => {
    return activitiesFromSocketMessage(socketMessage(fixtures.changellyWsActions, finality), wallet3)[0];
  };
  const payout = () => ({
    kind: 'transaction',
    id: completedVersion.transactionIds.incoming!.hash,
    timestamp: completedVersion.timestamp + 90_000,
    slug: 'hyperliquid',
    amount: 332327440000000000n,
    isIncoming: true,
    fromAddress: '0x0000000000000000000000000000000000000001',
    toAddress: completedVersion.cex!.payoutAddress,
    normalizedAddress: '0x0000000000000000000000000000000000000001',
    fee: 0n,
    status: 'completed',
  }) as ApiTransactionActivity;

  it('hides the pending deposit under the row the backend echoes with the submitted hash', () => {
    const [row] = activitiesFromBackendRows([firstVersion]);
    expect(row.hashes).toEqual([depositAt('pending').externalMsgHashNorm]);

    const result = reconcileActivityUpdate([], [], [depositAt('pending')], [row]);

    expect(result.pendingActivities?.map(({ shouldHide }) => shouldHide)).toEqual([true]);
    expect(idsWithStatus(visible(result.upsert))).toEqual([['2545759::backend-swap', 'pendingTrusted']]);
  });

  it('keeps the payout visible while the provider is still sending it', () => {
    const [row] = activitiesFromBackendRows([sendingVersion]);

    const result = reconcileActivityUpdate([], [payout()], [], [row]);

    expect(idsWithStatus(visible(result.confirmedActivities))).toEqual([[payout().id, 'completed']]);
  });

  it('hides the deposit and the payout under the completed row by trace id and transaction hash', () => {
    const [row] = activitiesFromBackendRows([completedVersion]);

    const projected = projectSwapActivities([payout(), depositAt('finalized')], [row], { fromTime: 0, toTime: NOW });

    expect(idsWithStatus(visible(projected))).toEqual([['2545759::backend-swap', 'completed']]);
    expect(hiddenIds(projected).sort()).toEqual([depositAt('finalized').id, payout().id].sort());
  });
});

function parseTraceId(activityId: string) {
  return activityId.split(':')[0];
}

import type { ApiSwapActivity, ApiTransactionActivity } from '../../types';
import type { TraceDetail, Transaction } from './toncenter/types';

import { TONCOIN } from '../../../config';
import { fromDecimal, toDecimal } from '../../../util/decimals';
import {
  activitiesFromBackendRows,
  activitiesFromSocketMessage,
  backendRowsOf,
  fixtures,
  meta,
  socketMessage,
  wallet3,
} from '../../../../tests/helpers/swapReconcilerFixtures';
import { projectSwapActivities } from '../../common/activities/swapReconciler';
import { parseActionsToActivities } from './toncenter/actions';
import { fillActivityDetails } from './activities';
import { parseTrace } from './traces';

// The wallet's TON balance reported by the socket before and after the trace: 287603430 - 274368592 nanoton.
// The real fee the loader reports cannot exceed what the wallet actually spent on the trace.
const TON_SPENT_ON_CASE_2 = 0.013234838;

describe('fillActivityDetails', () => {
  const [trace] = fixtures.case2Trace.traces;
  const parsedTrace = parseTrace({
    network: 'mainnet',
    walletAddress: meta.wallet,
    actions: trace.actions,
    traceDetail: trace.trace as TraceDetail,
    addressBook: fixtures.case2Trace.address_book,
    metadata: fixtures.case2Trace.metadata,
    transactions: trace.transactions as Record<string, Transaction>,
    nftSuperCollectionsByCollectionAddress: {},
  });

  it('fills the real fees of a swap summary built from the backend row', () => {
    const chainRows = activitiesFromSocketMessage(socketMessage(fixtures.case2WsActions, 'finalized'));
    const [backendRow] = activitiesFromBackendRows(backendRowsOf(fixtures.case2Backend.history));
    const summary = projectSwapActivities(chainRows, [backendRow], { fromTime: 0, toTime: Infinity })
      .find(({ id }) => id === backendRow.id) as ApiSwapActivity;
    expect(summary.shouldLoadDetails).toBe(true);

    const detailed = fillActivityDetails(summary, parsedTrace) as ApiSwapActivity;
    const [leg, feeTransfer] = chainRows;
    const detailedLeg = fillActivityDetails(leg, parsedTrace) as ApiSwapActivity;
    const detailedFee = fillActivityDetails(feeTransfer, parsedTrace) as ApiTransactionActivity;

    // The wallet sent two messages (the swap and the fee transfer), each with its own output of the trace: the
    // summary pays for both, a raw leg only for its own
    expect(parsedTrace.traceOutputs).toHaveLength(2);
    expect(detailed.networkFee).not.toBe(backendRow.networkFee);
    expect(Number(detailed.networkFee)).toBeGreaterThan(Number(detailedLeg.networkFee));
    expect(fromDecimal(detailed.networkFee, TONCOIN.decimals))
      .toBe(fromDecimal(detailedLeg.networkFee, TONCOIN.decimals) + detailedFee.fee);
    expect(Number(detailed.networkFee)).toBeLessThanOrEqual(TON_SPENT_ON_CASE_2);
    expect(detailed.ourFee).toBe('0.4375'); // the 437500000-unit fee transfer of the trace
    expect(detailed.shouldLoadDetails).toBeUndefined();
  });

  it('prices a summary projected from a token history, which lacks the fee transfer, over the whole trace', () => {
    // The HMSTR history holds the swap leg but not the BOLT fee transfer; the summary built from that page knows
    // fewer actions, yet the trade cost the wallet both messages
    const [leg] = activitiesFromSocketMessage(socketMessage(fixtures.case2WsActions, 'finalized'));
    const [backendRow] = activitiesFromBackendRows(backendRowsOf(fixtures.case2Backend.history));
    const tokenHistorySummary = projectSwapActivities([leg], [backendRow], { fromTime: 0, toTime: Infinity })
      .find(({ id }) => id === backendRow.id) as ApiSwapActivity;
    expect(tokenHistorySummary.extra?.reconciliation?.sourceActionIds).toEqual([backendRow.id, leg.id]);
    const fullSummary = projectSwapActivities(
      activitiesFromSocketMessage(socketMessage(fixtures.case2WsActions, 'finalized')),
      [backendRow],
      { fromTime: 0, toTime: Infinity },
    ).find(({ id }) => id === backendRow.id) as ApiSwapActivity;

    const fromTokenHistory = fillActivityDetails(tokenHistorySummary, parsedTrace) as ApiSwapActivity;
    const fromMainHistory = fillActivityDetails(fullSummary, parsedTrace) as ApiSwapActivity;

    const detailedLeg = fillActivityDetails(leg, parsedTrace) as ApiSwapActivity;
    expect(fromTokenHistory.networkFee).toBe(fromMainHistory.networkFee);
    expect(Number(fromTokenHistory.networkFee)).toBeGreaterThan(Number(detailedLeg.networkFee));
  });

  it('marks a chain row of another trace as having no details in this trace', () => {
    const [deposit] = activitiesFromSocketMessage(socketMessage(fixtures.case1WsActions, 'finalized'));

    const detailed = fillActivityDetails(deposit, parsedTrace);

    expect(detailed.shouldLoadDetails).toBeUndefined();
    expect(detailed).toEqual({ ...deposit, shouldLoadDetails: undefined });
  });
});

describe('fillActivityDetails for a route through native TON', () => {
  // The wallet's TON balance reported by the socket before and after the trace: 1790299000 - 1772720000 nanoton
  const TON_SPENT = 0.017579;
  const [trace] = fixtures.omnistonTwoHopTrace.traces;
  const parsedTrace = parseTrace({
    network: 'mainnet',
    walletAddress: wallet3.wallet,
    actions: trace.actions,
    traceDetail: trace.trace as TraceDetail,
    addressBook: fixtures.omnistonTwoHopTrace.address_book,
    metadata: fixtures.omnistonTwoHopTrace.metadata,
    transactions: trace.transactions as Record<string, Transaction>,
    nftSuperCollectionsByCollectionAddress: {},
  });
  const chainRows = activitiesFromSocketMessage(socketMessage(fixtures.omnistonTwoHopWsActions, 'finalized'), wallet3);
  const [backendRow] = activitiesFromBackendRows([fixtures.omnistonTwoHopBackend.row]);
  const summary = projectSwapActivities(chainRows, [backendRow], { fromTime: 0, toTime: Infinity })
    .find(({ id }) => id === backendRow.id) as ApiSwapActivity;

  it('prices the summary by what the wallet spent, not by the TON that passed through the router', () => {
    // The first leg names the DeDust hop the router executed, which the parser attributes to nobody
    expect(summary.extra?.mtwAggregator?.swapIds).toHaveLength(2);

    const detailed = fillActivityDetails(summary, parsedTrace) as ApiSwapActivity;

    expect(detailed.shouldLoadDetails).toBeUndefined();
    expect(Number(detailed.networkFee)).toBeLessThanOrEqual(TON_SPENT);
    expect(Number(detailed.networkFee)).toBeGreaterThan(TON_SPENT - 0.001);
    expect(detailed.ourFee).toBe('43.75'); // the 43750000000-unit HMSTR fee transfer of the trace
  });

  it('prices the wallet leg below the TON attached to its message', () => {
    const walletLeg = chainRows.find((row) => row.kind === 'swap' && row.to === TONCOIN.slug)!;

    const detailed = fillActivityDetails(walletLeg, parsedTrace) as ApiSwapActivity;
    const detailedSummary = fillActivityDetails(summary, parsedTrace) as ApiSwapActivity;

    // 0.46 TON was attached to the STON.fi message and 0.446 came back as excess; the 0.6045 TON the hop produced
    // went on to DeDust, not to the wallet, so it is neither income nor a cost of this leg. What remains is the
    // consumed gas plus the fee of the wallet's own transaction
    expect(Number(detailed.networkFee)).toBeGreaterThan(0.46 - 0.4462);
    expect(Number(detailed.networkFee)).toBeLessThan(0.46 - 0.446 + 0.001);
    expect(Number(detailed.networkFee)).toBeLessThan(Number(detailedSummary.networkFee));
  });
});

describe('fillActivityDetails for a swap paying TON to the wallet', () => {
  const [trace] = fixtures.dedustJettonToTonTrace.traces;
  const parseOptions = {
    network: 'mainnet' as const,
    walletAddress: wallet3.wallet,
    addressBook: fixtures.dedustJettonToTonTrace.address_book,
    metadata: fixtures.dedustJettonToTonTrace.metadata,
    nftSuperCollectionsByCollectionAddress: {},
  };
  const parsedTrace = parseTrace({
    ...parseOptions,
    actions: trace.actions,
    traceDetail: trace.trace as TraceDetail,
    transactions: trace.transactions as Record<string, Transaction>,
  });
  const legs = parseActionsToActivities(trace.actions, parseOptions)
    .filter((row): row is ApiSwapActivity => row.kind === 'swap');

  it('keeps the TON both legs pay out as income of the wallet, not as a cost', () => {
    // The wallet attached 0.65 TON to its messages and got 0.6355 of it back next to the 9.8634 TON the trade paid
    // out; the trade cost it the difference plus its own transaction fees
    expect(legs.map(({ to }) => to)).toEqual([TONCOIN.slug, TONCOIN.slug]);
    const realFee = parsedTrace.traceOutputs.reduce((total, output) => total + output.realFee, 0n);

    expect(Number(toDecimal(realFee, TONCOIN.decimals))).toBeGreaterThan(0.015);
    expect(Number(toDecimal(realFee, TONCOIN.decimals))).toBeLessThan(0.017);
    for (const leg of legs) {
      const detailed = fillActivityDetails(leg, parsedTrace) as ApiSwapActivity;
      expect(Number(detailed.networkFee)).toBeGreaterThan(0);
      expect(Number(detailed.networkFee)).toBeLessThan(0.017);
    }
  });
});

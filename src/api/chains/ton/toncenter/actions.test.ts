import {
  activitiesFromSocketMessage,
  fixtures,
  socketMessage,
} from '../../../../../tests/helpers/swapReconcilerFixtures';

describe('parseActionsToActivities', () => {
  it('marks the jetton fee transfer of a swap as our swap fee by the content of its forward payload', () => {
    const activities = activitiesFromSocketMessage(socketMessage(fixtures.case2WsActions, 'finalized'));
    const feeTransfer = activities.find((activity) => activity.kind === 'transaction' && !activity.isIncoming)!;

    expect(feeTransfer.extra?.isOurSwapFee).toBe(true);
    expect(feeTransfer.shouldHide).toBe(true);
  });
});

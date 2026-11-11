import { planHistoryReveal } from './historyReveal';

jest.mock('../../../util/windowEnvironment', () => ({ REM: 16 }));

// A list 400 px wide from its side at 0, whose column runs from 0 down to 800, above the field
const LIST = {
  top: 0, bottom: 800, left: 0, width: 400, isRtl: false,
};

describe('planHistoryReveal', () => {
  it('lets the messages take the placeholders from the bottom up, whoever\'s side they stand on', () => {
    // The Agent's placeholder at the bottom and the user's over it, and two answers in a row
    const placeholders = [
      { left: 8, top: 560, width: 340, height: 220 },
      { left: 220, top: 500, width: 172, height: 50 },
    ];
    const plan = planHistoryReveal(placeholders, [
      { frame: { left: 8, top: 700, width: 300, height: 80 }, isOutgoing: false },
      { frame: { left: 8, top: 600, width: 260, height: 90 }, isOutgoing: false },
    ], LIST);

    expect(plan.sources).toEqual([
      { frame: placeholders[0], placeholderIndex: 0 },
      { frame: placeholders[1], placeholderIndex: 1 },
    ]);
    expect(plan.leavingPlaceholders).toEqual([]);
  });

  it('grows the messages beyond the placeholders out of ones made up on their sides, over the column\'s top', () => {
    const placeholder = { left: 8, top: 560, width: 340, height: 220 };
    const plan = planHistoryReveal([placeholder], [
      { frame: { left: 8, top: 700, width: 300, height: 80 }, isOutgoing: false },
      // Two questions in a row, the first wider than 86% of the list
      { frame: { left: 250, top: 640, width: 140, height: 40 }, isOutgoing: true },
      { frame: { left: 10, top: 590, width: 380, height: 40 }, isOutgoing: true },
      { frame: { left: 8, top: 500, width: 200, height: 80 }, isOutgoing: false },
    ], LIST);

    expect(plan.sources.map(({ frame }) => frame)).toEqual([
      placeholder,
      // 184 px tall, out of sight over the column's top at 0, 16 px from the user's side
      { left: 400 - 16 - 140, top: -184, width: 140, height: 184 },
      // 10 px over the source under it
      { left: 400 - 16 - 344, top: -184 - 10 - 184, width: 344, height: 184 },
      // 16 px from the Agent's side
      { left: 16, top: -378 - 10 - 184, width: 200, height: 184 },
    ]);
    expect(plan.sources.slice(1).every(({ placeholderIndex }) => placeholderIndex === undefined)).toBe(true);
  });

  it('makes up a question\'s placeholder on the left and an answer\'s on the right in a right-to-left layout', () => {
    const plan = planHistoryReveal([], [
      { frame: { left: 250, top: 640, width: 140, height: 40 }, isOutgoing: true },
      { frame: { left: 8, top: 500, width: 200, height: 80 }, isOutgoing: false },
    ], { ...LIST, isRtl: true });

    expect(plan.sources.map(({ frame }) => frame.left)).toEqual([16, 400 - 16 - 200]);
  });

  it('moves the placeholders no message takes up above the column, each above the last and none of them down', () => {
    const placeholders = [
      { left: 8, top: 560, width: 340, height: 220 },
      { left: 220, top: 500, width: 172, height: 50 },
      { left: 8, top: 200, width: 300, height: 290 },
    ];
    const plan = planHistoryReveal(placeholders, [
      { frame: { left: 8, top: 700, width: 300, height: 80 }, isOutgoing: false },
    ], { ...LIST, top: 100 });

    // Over the column's top at 100, 10 px apart: the user's pill rises from 500 to 40, and the one over it from 200
    // to above that
    expect(plan.leavingPlaceholders).toEqual([
      { placeholderIndex: 1, shift: (100 - 10 - 50) - 500 },
      { placeholderIndex: 2, shift: (40 - 10 - 290) - 200 },
    ]);
  });

  it('leaves a placeholder that stands above the column where it is rather than moving it down', () => {
    const plan = planHistoryReveal([
      { left: 8, top: 560, width: 340, height: 220 },
      { left: 220, top: -300, width: 172, height: 50 },
    ], [{ frame: { left: 8, top: 700, width: 300, height: 80 }, isOutgoing: false }], LIST);

    expect(plan.leavingPlaceholders).toEqual([{ placeholderIndex: 1, shift: 0 }]);
  });
});

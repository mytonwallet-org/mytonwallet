import segmentGraphemes from '../segmentGraphemes';

import {
  buildRevealTarget,
  getAvailableTargetCount,
  getCommonGraphemePrefixLength,
  getInputRate,
  TextRevealController,
} from './TextRevealController';

describe('TextRevealController', () => {
  it.each([60, 120])('reveals text at %i Hz with a three-grapheme frame cap', (refreshRate) => {
    const target = buildRevealTarget('smooth grapheme streaming '.repeat(20));
    const controller = new TextRevealController(0, target);
    const snapshots: number[] = [];

    controller.observeUpdate(target, 0);
    for (let frame = 1; frame <= refreshRate * 2; frame++) {
      snapshots.push(controller.tick(frame / refreshRate).revealedGraphemeCount);
    }

    const firstRevealIndex = snapshots.findIndex((count) => count > 0);
    expect(snapshots[firstRevealIndex]).toBeGreaterThanOrEqual(8);
    expect(snapshots[firstRevealIndex]).toBeLessThanOrEqual(12);
    expect(Math.max(...getSteadyDeltas(snapshots))).toBeLessThanOrEqual(3);
  });

  it('buffers a short first chunk for up to 300 milliseconds', () => {
    const target = buildRevealTarget('Short');
    const controller = new TextRevealController(0, target);

    controller.observeUpdate(target, 0);

    expect(controller.tick(0.299)).toEqual({
      revealedGraphemeCount: 0,
      phase: 'buffering',
    });
    expect(controller.tick(0.3)).toEqual({
      revealedGraphemeCount: 5,
      phase: 'streaming',
    });
  });

  it('keeps the original buffer deadline across growing chunks', () => {
    const firstTarget = buildRevealTarget('One');
    const secondTarget = buildRevealTarget('One two');
    const controller = new TextRevealController(0, firstTarget);

    controller.observeUpdate(firstTarget, 0);
    controller.tick(0.2);
    controller.observeUpdate(secondTarget, 0.25);

    expect(controller.tick(0.299).phase).toBe('buffering');
    expect(controller.tick(0.3)).toEqual({
      revealedGraphemeCount: secondTarget.graphemeCount,
      phase: 'streaming',
    });
  });

  it('reveals at most twelve graphemes in the initial seed', () => {
    const target = buildRevealTarget('abcdefghijklmnop');
    const controller = new TextRevealController(0, target);

    controller.observeUpdate(target, 0);

    expect(controller.tick(1 / 60)).toEqual({
      revealedGraphemeCount: 12,
      phase: 'streaming',
    });
  });

  it('holds three trailing graphemes until the source stalls', () => {
    const initialTarget = buildRevealTarget('Initial seed');
    const nextTarget = buildRevealTarget('Initial seed more');
    const controller = new TextRevealController(0, initialTarget);

    controller.observeUpdate(initialTarget, 0);
    expect(controller.tick(1 / 60).revealedGraphemeCount).toBe(
      initialTarget.preferredInitialRevealCount,
    );

    controller.observeUpdate(nextTarget, 0.02);
    for (let frame = 1; frame <= 5; frame++) {
      controller.tick(0.02 + frame / 120);
    }

    expect(controller.getSnapshot().revealedGraphemeCount).toBeLessThanOrEqual(
      nextTarget.graphemeCount - 3,
    );
    for (let frame = 6; frame <= 120; frame++) {
      controller.tick(0.02 + frame / 120);
    }

    expect(controller.getSnapshot().revealedGraphemeCount).toBeGreaterThan(nextTarget.graphemeCount - 3);
  });

  it('uses the exact input-rate hold and eight-update ramp', () => {
    expect(getInputRate(1)).toBe(160);
    expect(getInputRate(2)).toBe(160);
    expect(getInputRate(3)).toBe(170);
    expect(getInputRate(9)).toBe(230);
    expect(getInputRate(10)).toBe(240);
    expect(getInputRate(20)).toBe(240);
  });

  it('releases the three-grapheme tail at the 80 millisecond boundary', () => {
    expect(getAvailableTargetCount(20, 8, 1, 1.079)).toBe(17);
    expect(getAvailableTargetCount(20, 8, 1, 1.08)).toBe(20);
  });

  it('seeds a response finalized during buffering before bounded drain', () => {
    const target = buildRevealTarget('Complete before the first visual frame');
    const controller = new TextRevealController(0, target);

    controller.observeUpdate(target, 0);
    controller.finalize(target, 0.001);

    const snapshot = controller.tick(1 / 60);

    expect(snapshot.revealedGraphemeCount).toBeGreaterThanOrEqual(8);
    expect(snapshot.revealedGraphemeCount).toBeLessThanOrEqual(12);
    expect(snapshot.phase).toBe('draining');
  });

  it('does not replay the initial buffer after a seeded correction', () => {
    const initialTarget = buildRevealTarget('That’s a complete seed');
    const correctedTarget = buildRevealTarget('Different response');
    const controller = new TextRevealController(0, initialTarget);

    controller.observeUpdate(initialTarget, 0);
    controller.tick(1 / 60);
    controller.reconcileUpdate(correctedTarget, 0, 0.02);

    expect(controller.getSnapshot()).toEqual({
      revealedGraphemeCount: 0,
      phase: 'streaming',
    });
  });

  it('rewinds corrections and shrink to the common grapheme prefix', () => {
    const initialTarget = buildRevealTarget('Hello world');
    const correctedTarget = buildRevealTarget('Hello wallet');
    const controller = new TextRevealController(initialTarget.graphemeCount, initialTarget);

    controller.observeUpdate(initialTarget, 0);
    controller.reconcileUpdate(correctedTarget, 6, 0.1);

    expect(controller.getSnapshot()).toEqual({
      revealedGraphemeCount: 6,
      phase: 'streaming',
    });
  });

  it('caps a long frame before advancing the reveal', () => {
    const target = buildRevealTarget('word '.repeat(20));
    const delayedController = new TextRevealController(0, target);
    const regularController = new TextRevealController(0, target);

    delayedController.observeUpdate(target, 0);
    regularController.observeUpdate(target, 0);
    delayedController.tick(0);
    regularController.tick(0);

    expect(delayedController.tick(2)).toEqual(regularController.tick(0.05));
  });

  it('drains a completed response without a final jump', () => {
    const target = buildRevealTarget('buffered response '.repeat(30));
    const controller = new TextRevealController(0, target);
    const snapshots: number[] = [];

    controller.observeUpdate(target, 0);
    controller.finalize(target, 0);
    for (let frame = 1; frame <= 1000 && controller.getSnapshot().phase !== 'complete'; frame++) {
      snapshots.push(controller.tick(frame / 60).revealedGraphemeCount);
    }

    expect(controller.getSnapshot().phase).toBe('complete');
    expect(Math.max(...getSteadyDeltas(snapshots))).toBeLessThanOrEqual(3);
    expect(snapshots.at(-1)).toBe(target.graphemeCount);
  });
});

describe('Agent text segmentation', () => {
  it('keeps emoji, combining marks, ZWJ sequences, CJK and RTL text intact', () => {
    const graphemes = segmentGraphemes('A\u0301👨‍👩‍👧‍👦你ش');

    expect(graphemes).toEqual(['A\u0301', '👨‍👩‍👧‍👦', '你', 'ش']);
  });

  it('builds a grapheme-count target', () => {
    expect(buildRevealTarget('A\u0301👨‍👩‍👧‍👦你')).toEqual({
      graphemeCount: 3,
    });
  });

  it('prefers a stable seed boundary between eight and twelve graphemes', () => {
    expect(buildRevealTarget('That’s a great question').preferredInitialRevealCount).toBe(8);
    expect(buildRevealTarget('unfinished').preferredInitialRevealCount).toBeUndefined();
    expect(buildRevealTarget('abcdefghijklmnop').preferredInitialRevealCount).toBe(12);
  });

  it('finds a common prefix after a grapheme-level correction', () => {
    const first = segmentGraphemes('Hello 👨‍👩‍👧‍👦');
    const second = segmentGraphemes('Hello 👨‍👩‍👦');

    expect(getCommonGraphemePrefixLength(first, second)).toBe(6);
  });
});

function getSteadyDeltas(snapshots: number[]) {
  const firstRevealIndex = snapshots.findIndex((count) => count > 0);

  return snapshots.slice(firstRevealIndex + 1).map(
    (count, index) => count - snapshots[firstRevealIndex + index],
  );
}

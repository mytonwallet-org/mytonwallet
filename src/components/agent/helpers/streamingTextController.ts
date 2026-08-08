import {
  getCommonGraphemePrefixLength,
  TextRevealController,
  type TextRevealTarget,
} from '../../../util/agent/TextRevealController';

export function createTextRevealController(
  target: TextRevealTarget,
  isStreaming: boolean,
  now: number,
  shouldRevealFromStart = false,
) {
  const controller = new TextRevealController(
    shouldRevealFromStart ? 0 : target.graphemeCount,
    target,
  );

  if (isStreaming) {
    controller.observeUpdate(target, now);
  } else {
    controller.finalize(target, now);
  }

  return controller;
}

export function updateTextRevealController(
  controller: TextRevealController,
  previousGraphemes: string[],
  graphemes: string[],
  target: TextRevealTarget,
  now: number,
) {
  const commonPrefixLength = getCommonGraphemePrefixLength(previousGraphemes, graphemes);
  if (commonPrefixLength === previousGraphemes.length && commonPrefixLength === graphemes.length) {
    return;
  }

  if (commonPrefixLength === previousGraphemes.length) {
    controller.observeUpdate(target, now);
    return;
  }

  controller.reconcileUpdate(target, commonPrefixLength, now);
}

export function getNowInSeconds() {
  return performance.now() / 1000;
}

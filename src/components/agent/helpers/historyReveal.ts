import type { MotionRect } from './agentMotion';

import { REM } from '../../../util/windowEnvironment';

// The gap between placeholders, as in `AgentMessagesSkeleton`
const ROW_GAP = 0.625 * REM;
// A message without a placeholder left grows out of one made up in its sender's place, as on iOS and Android: as wide
// as the message but no wider than this share of the list, this tall, and this far from the list's side
const MADE_UP_PLACEHOLDER_WIDTH_SHARE = 0.86;
const MADE_UP_PLACEHOLDER_HEIGHT = 11.5 * REM;
const MADE_UP_PLACEHOLDER_INSET = REM;

/** A message on screen, its bubble and whether the user sent it */
interface HistoryRevealTarget {
  frame: MotionRect;
  isOutgoing: boolean;
}

/** The list's column between the header and the field, and its sides short of its scrollbar */
interface HistoryRevealList {
  top: number;
  bottom: number;
  left: number;
  width: number;
  isRtl: boolean;
}

interface HistoryRevealPlan {
  /** Where each message grows from: the placeholder it takes, by its index, or one made up for it */
  sources: { frame: MotionRect; placeholderIndex?: number }[];
  /** The placeholders no message takes, by their index, each with how far it moves up as it fades */
  leavingPlaceholders: { placeholderIndex: number; shift: number }[];
}

/**
 * Plans the history's reveal out of the placeholders as iOS's `AgentSkeletonReveal` and Android's
 * `planAgentSkeletonReveal` do. The messages on screen take the placeholders from the bottom up, whoever's they are, so
 * consecutive answers never swap places to reach a placeholder of their own sender, and the column keeps its order as
 * it moves. A message left without a placeholder grows out of one made up in its sender's place above the last source,
 * out of sight over the column's top, so that the reveal starts from the placeholders as they show. The placeholders
 * left without a message move up above the column, each above the last, and never down.
 *
 * `placeholders` and `targets` come from the bottom up.
 */
export function planHistoryReveal(
  placeholders: MotionRect[],
  targets: HistoryRevealTarget[],
  list: HistoryRevealList,
): HistoryRevealPlan {
  let sourceTop = list.bottom;
  let columnTop = list.top;
  const sources = targets.map(({ frame, isOutgoing }, index) => {
    const placeholder = placeholders[index];
    const source = placeholder
      ? { frame: placeholder, placeholderIndex: index }
      : { frame: getMadeUpPlaceholder(frame, isOutgoing, Math.min(sourceTop, list.top), list) };
    sourceTop = source.frame.top - ROW_GAP;
    columnTop = Math.min(columnTop, frame.top);
    return source;
  });
  const leavingPlaceholders = placeholders.slice(targets.length).map((frame, index) => {
    const top = Math.min(columnTop - ROW_GAP - frame.height, frame.top);
    columnTop = top;
    return { placeholderIndex: targets.length + index, shift: top - frame.top };
  });

  return { sources, leavingPlaceholders };
}

function getMadeUpPlaceholder(target: MotionRect, isOutgoing: boolean, bottom: number, list: HistoryRevealList) {
  const width = Math.min(target.width, list.width * MADE_UP_PLACEHOLDER_WIDTH_SHARE);
  const isOnRight = isOutgoing !== list.isRtl;
  const left = isOnRight
    ? list.left + list.width - MADE_UP_PLACEHOLDER_INSET - width
    : list.left + MADE_UP_PLACEHOLDER_INSET;

  return {
    left,
    top: bottom - MADE_UP_PLACEHOLDER_HEIGHT,
    width,
    height: MADE_UP_PLACEHOLDER_HEIGHT,
  };
}

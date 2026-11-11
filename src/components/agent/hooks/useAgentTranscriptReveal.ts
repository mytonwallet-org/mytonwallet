import { useEffect, useRef, useState } from '../../../lib/teact/teact';
import { getGlobal } from '../../../global';

import { ANIMATION_LEVEL_MIN } from '../../../config';
import segmentGraphemes from '../../../util/segmentGraphemes';

import useLastCallback from '../../../hooks/useLastCallback';
import { useMediaQuery } from '../../../hooks/useMediaQuery';

/**
 * A transcript comes into the draft character by character, spaces among them, as iOS brings it in: this far apart,
 * closer for a long transcript, whose last character starts within `TRANSCRIPT_REVEAL_MAX_MS`
 */
export const TRANSCRIPT_REVEAL_CHARACTER_MS = 6;
export const TRANSCRIPT_REVEAL_MAX_MS = 800;
/** A character sharpens within 150 ms of coming and then turns to the text's colour over 500 ms */
export const TRANSCRIPT_CHARACTER_SETTLE_MS = 650;
/** Where motion is reduced, the transcript fades in whole over this long */
export const TRANSCRIPT_FADE_MS = 300;

export interface AgentTranscriptReveal {
  /** Where the transcript begins in the draft */
  start: number;
  /** The transcript fades in whole instead of character by character */
  isReduced: boolean;
}

// A layout switch finishes these before either layout saves its draft
const runningReveals = new Set<NoneToVoidFunction>();

interface RevealState {
  base: string;
  characters: string[];
  count: number;
  startedAt: number;
  step: number;
  frame?: number;
}

/**
 * Puts a transcript after the draft a character at a time, at most `TRANSCRIPT_REVEAL_MAX_MS` in all, so that the
 * field grows with it. Each frame adds the characters due by then. `reveal` tells the input which part of the draft is
 * the transcript while its characters settle.
 */
export default function useAgentTranscriptReveal({ inputValue, onInput }: {
  inputValue: string;
  onInput: (value: string) => void;
}) {
  const isReducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)');
  const [reveal, setReveal] = useState<AgentTranscriptReveal>();
  const stateRef = useRef<RevealState>();
  const settleTimerRef = useRef<number>();

  const showCharacters = useLastCallback((state: RevealState, count: number) => {
    state.count = count;
    onInput(state.base + state.characters.slice(0, count).join(''));
  });

  const clearTimers = useLastCallback(() => {
    const frame = stateRef.current?.frame;
    if (frame !== undefined) cancelAnimationFrame(frame);
    window.clearTimeout(settleTimerRef.current);
  });

  const settle = useLastCallback(() => {
    clearTimers();
    runningReveals.delete(finish);
    stateRef.current = undefined;
    setReveal(undefined);
  });

  // The rest of the transcript comes at once, as when the user types or sends while it is being written
  const finish = useLastCallback(() => {
    const state = stateRef.current;
    if (!state) return false;

    const isWriting = state.count < state.characters.length;
    if (isWriting) showCharacters(state, state.characters.length);
    settle();
    return isWriting;
  });

  const revealTranscript = useLastCallback((text: string) => {
    finish();
    const characters = segmentGraphemes(text.trim());
    if (!characters.length) return;

    const draft = inputValue.trim();
    const isReduced = Boolean(isReducedMotion) || getGlobal().settings.animationLevel === ANIMATION_LEVEL_MIN;
    const state: RevealState = {
      base: draft ? `${draft} ` : '',
      characters,
      count: 0,
      startedAt: performance.now(),
      step: characters.length > 1
        ? Math.min(TRANSCRIPT_REVEAL_CHARACTER_MS, TRANSCRIPT_REVEAL_MAX_MS / (characters.length - 1))
        : TRANSCRIPT_REVEAL_CHARACTER_MS,
    };
    stateRef.current = state;
    runningReveals.add(finish);
    setReveal({ start: state.base.length, isReduced });

    if (isReduced) {
      showCharacters(state, characters.length);
      settleTimerRef.current = window.setTimeout(settle, TRANSCRIPT_FADE_MS);
      return;
    }

    const showDue = () => {
      const due = Math.min(characters.length, 1 + Math.floor((performance.now() - state.startedAt) / state.step));
      if (due > state.count) showCharacters(state, due);
      if (state.count < characters.length) {
        state.frame = requestAnimationFrame(showDue);
        return;
      }
      state.frame = undefined;
      settleTimerRef.current = window.setTimeout(settle, TRANSCRIPT_CHARACTER_SETTLE_MS);
    };
    showDue();
  });

  useEffect(() => () => {
    finish();
  }, [finish]);

  return { reveal, revealTranscript, finishReveal: finish };
}

/** Writes at once the rest of every transcript still coming into a draft */
export function finishTranscriptReveals() {
  runningReveals.forEach((finish) => finish());
}

import segmentGraphemes from '../segmentGraphemes';

const VELOCITY_TAU_SECONDS = 0.08;
const GAP_EWMA_ALPHA = 0.4;
const INITIAL_GAP_SECONDS = 0.5;
const STALL_FLOOR_SECONDS = 0.1;
const TRAILING_STALL_SECONDS = 0.08;
const MINIMUM_FINALIZE_TIME_SECONDS = 0.18;
const MAXIMUM_FINALIZE_TIME_SECONDS = 0.5;
const FRAME_DELTA_CAP_SECONDS = 0.05;
const MAX_INPUT_RATE = 240;
const INITIAL_INPUT_RATE = 160;
const INPUT_RATE_HOLD_CHUNKS = 1;
const INPUT_RATE_RAMP_CHUNKS = 8;
const VELOCITY_CEILING = 240;
const FINALIZE_VELOCITY_CEILING = 720;
const MAXIMUM_CATCH_UP_SECONDS = 0.5;
const GRAPHEME_STEP_CAP = 3;
const INITIAL_REVEAL_DESIRED_COUNT = 8;
const INITIAL_REVEAL_MAXIMUM_WAIT_SECONDS = 0.3;
const TRAILING_HOLD_COUNT = 3;

export const MAXIMUM_INITIAL_REVEAL_GRAPHEMES = 12;

const WORD_SEGMENTER = typeof Intl !== 'undefined' && typeof Intl.Segmenter === 'function'
  ? new Intl.Segmenter(undefined, { granularity: 'word' })
  : undefined;

export type TextRevealPhase = 'buffering' | 'streaming' | 'draining' | 'complete';

export interface TextRevealTarget {
  graphemeCount: number;
  preferredInitialRevealCount?: number;
}

interface TextRevealSnapshot {
  revealedGraphemeCount: number;
  phase: TextRevealPhase;
}

interface TextSegment {
  endCount: number;
  isWordLike: boolean;
}

export class TextRevealController {
  private velocity = 0;

  private revealCredit = 0;

  private averageInterArrival = INITIAL_GAP_SECONDS;

  private lastSampleTime?: number;

  private lastSampleLength?: number;

  private predictedNextArrivalTime?: number;

  private chunkCount = 0;

  private lastFrameTime?: number;

  private finalizationStartTime?: number;

  private finalizationStartCount?: number;

  private finalizationDuration = MINIMUM_FINALIZE_TIME_SECONDS;

  private bufferingStartTime?: number;

  private isFinalizationPending = false;

  private revealedCount: number;

  private target: TextRevealTarget;

  private phase: TextRevealPhase;

  private hasCommittedInitialSeed: boolean;

  constructor(
    initialRevealedCount: number,
    initialTarget: TextRevealTarget,
  ) {
    this.target = normalizeTarget(initialTarget);
    this.revealedCount = Math.min(
      this.target.graphemeCount,
      Math.max(Math.floor(initialRevealedCount), 0),
    );
    this.hasCommittedInitialSeed = this.revealedCount > 0;
    this.phase = this.hasCommittedInitialSeed ? 'streaming' : 'buffering';
  }

  get shouldTick() {
    return this.phase === 'draining'
      || (this.phase !== 'complete' && this.revealedCount < this.target.graphemeCount);
  }

  getSnapshot(): TextRevealSnapshot {
    return {
      revealedGraphemeCount: this.revealedCount,
      phase: this.phase,
    };
  }

  observeUpdate(target: TextRevealTarget, now: number) {
    const normalizedTarget = normalizeTarget(target);
    const targetLength = normalizedTarget.graphemeCount;

    if (this.lastSampleLength === undefined) {
      this.lastSampleTime = now;
      this.lastSampleLength = targetLength;
      this.predictedNextArrivalTime = now + this.averageInterArrival;
      this.chunkCount += 1;
    } else if (targetLength > this.lastSampleLength) {
      if (this.lastSampleTime !== undefined) {
        const interArrival = Math.max(now - this.lastSampleTime, 0.001);
        this.averageInterArrival = GAP_EWMA_ALPHA * interArrival
          + (1 - GAP_EWMA_ALPHA) * this.averageInterArrival;
      }

      this.lastSampleTime = now;
      this.lastSampleLength = targetLength;
      this.predictedNextArrivalTime = now + this.averageInterArrival;
      this.chunkCount += 1;
    } else if (targetLength < this.lastSampleLength) {
      this.lastSampleLength = targetLength;
    }

    if (this.phase !== 'buffering') {
      this.phase = 'streaming';
    }
    if (targetLength > 0 && this.bufferingStartTime === undefined) {
      this.bufferingStartTime = now;
    }
    this.isFinalizationPending = false;
    this.finalizationStartTime = undefined;
    this.finalizationStartCount = undefined;
    this.target = normalizedTarget;
    this.revealedCount = Math.min(this.revealedCount, targetLength);
  }

  reconcileUpdate(target: TextRevealTarget, commonPrefixLength: number, now: number) {
    const normalizedTarget = normalizeTarget(target);
    const normalizedPrefixLength = Math.min(
      Math.max(0, Math.floor(commonPrefixLength)),
      normalizedTarget.graphemeCount,
    );

    this.target = normalizedTarget;
    this.revealedCount = Math.min(this.revealedCount, normalizedPrefixLength);
    this.velocity = 0;
    this.revealCredit = 0;
    this.lastSampleTime = now;
    this.lastSampleLength = normalizedTarget.graphemeCount;
    this.predictedNextArrivalTime = now + this.averageInterArrival;
    this.lastFrameTime = now;
    const previousBufferingStartTime = this.bufferingStartTime;

    this.phase = this.hasCommittedInitialSeed ? 'streaming' : 'buffering';
    this.bufferingStartTime = this.phase === 'buffering' && normalizedTarget.graphemeCount > 0
      ? previousBufferingStartTime ?? now
      : undefined;
    this.isFinalizationPending = false;
    this.finalizationStartTime = undefined;
    this.finalizationStartCount = undefined;
  }

  finalize(target: TextRevealTarget, now: number) {
    this.target = normalizeTarget(target);
    this.revealedCount = Math.min(this.revealedCount, this.target.graphemeCount);

    if (this.revealedCount >= this.target.graphemeCount) {
      this.revealedCount = this.target.graphemeCount;
      this.phase = 'complete';
      return;
    }

    if (this.phase === 'buffering') {
      this.isFinalizationPending = true;
      this.bufferingStartTime ??= now;
      return;
    }

    this.startFinalization(now);
  }

  private startFinalization(now: number) {
    this.isFinalizationPending = false;

    const backlog = this.target.graphemeCount - this.revealedCount;

    this.phase = 'draining';
    this.finalizationStartTime = now;
    this.finalizationStartCount = this.revealedCount;
    this.finalizationDuration = clamp(
      backlog / FINALIZE_VELOCITY_CEILING,
      MINIMUM_FINALIZE_TIME_SECONDS,
      MAXIMUM_FINALIZE_TIME_SECONDS,
    );
  }

  tick(now: number): TextRevealSnapshot {
    if (this.phase === 'complete') {
      return this.getSnapshot();
    }

    if (this.phase === 'draining') {
      this.advanceFinalization(now);
      return this.getSnapshot();
    }

    if (this.phase === 'buffering') {
      this.advanceInitialBuffer(now);
      return this.getSnapshot();
    }

    const availableTargetCount = getAvailableTargetCount(
      this.target.graphemeCount,
      this.revealedCount,
      this.lastSampleTime,
      now,
    );
    const frameDelta = Math.max(
      0,
      Math.min(now - (this.lastFrameTime ?? now), FRAME_DELTA_CAP_SECONDS),
    );
    const lag = Math.max(0, availableTargetCount - this.revealedCount);
    const inputRate = getInputRate(this.chunkCount);
    const targetVelocity = Math.min(
      Math.max(this.getTargetVelocity(inputRate, lag, now), lag / MAXIMUM_CATCH_UP_SECONDS),
      VELOCITY_CEILING,
    );
    const smoothing = Math.min(1, frameDelta / VELOCITY_TAU_SECONDS);

    this.velocity += (targetVelocity - this.velocity) * smoothing;
    this.revealCredit += this.velocity * frameDelta;

    const creditedCount = Math.floor(this.revealCredit);
    if (creditedCount > 0) {
      const nextCount = this.advanceToMaximumCount(
        Math.min(
          availableTargetCount,
          this.revealedCount + Math.min(GRAPHEME_STEP_CAP, creditedCount),
        ),
      );
      const revealedDelta = nextCount - this.revealedCount;

      this.revealedCount = nextCount;
      this.revealCredit = Math.max(0, this.revealCredit - revealedDelta);
    }

    this.lastFrameTime = now;

    return this.getSnapshot();
  }

  private advanceFinalization(now: number) {
    const startTime = this.finalizationStartTime ?? now;
    const startCount = this.finalizationStartCount ?? this.revealedCount;
    const elapsedTime = Math.max(0, now - startTime);

    const progress = elapsedTime / this.finalizationDuration;
    const projectedCount = Math.floor(
      startCount + (this.target.graphemeCount - startCount) * progress,
    );
    const cappedCount = Math.min(
      this.target.graphemeCount,
      Math.max(projectedCount, this.revealedCount + 1),
      this.revealedCount + GRAPHEME_STEP_CAP,
    );

    this.revealedCount = this.advanceToMaximumCount(cappedCount);
    if (this.revealedCount >= this.target.graphemeCount) {
      this.phase = 'complete';
    }
    this.lastFrameTime = now;
  }

  private advanceInitialBuffer(now: number) {
    const preferredCount = this.target.preferredInitialRevealCount;
    const hasWaitElapsed = this.bufferingStartTime !== undefined
      && now - this.bufferingStartTime >= INITIAL_REVEAL_MAXIMUM_WAIT_SECONDS;

    if (!this.isFinalizationPending && preferredCount === undefined && !hasWaitElapsed) {
      return;
    }

    const maximumCount = preferredCount
      ?? Math.min(this.target.graphemeCount, MAXIMUM_INITIAL_REVEAL_GRAPHEMES);
    this.revealedCount = this.advanceToMaximumCount(maximumCount);
    this.hasCommittedInitialSeed = this.revealedCount > 0;
    this.lastFrameTime = now;

    if (!this.hasCommittedInitialSeed) {
      return;
    }

    if (this.isFinalizationPending) {
      if (this.revealedCount >= this.target.graphemeCount) {
        this.phase = 'complete';
        this.isFinalizationPending = false;
      } else {
        this.startFinalization(now);
      }
      return;
    }

    this.phase = 'streaming';
  }

  private advanceToMaximumCount(maximumCount: number) {
    return Math.min(this.target.graphemeCount, Math.max(this.revealedCount, maximumCount));
  }

  private getTargetVelocity(inputRate: number, lag: number, now: number) {
    if (this.chunkCount < 2 || this.predictedNextArrivalTime === undefined) {
      return lag > 0 ? inputRate : 0;
    }

    const timeToNextArrival = Math.max(STALL_FLOOR_SECONDS, this.predictedNextArrivalTime - now);
    const catchUpFactor = this.chunkCount <= INPUT_RATE_HOLD_CHUNKS + 1 ? 0.15 : 0.3;

    return Math.max(inputRate * catchUpFactor, lag / timeToNextArrival);
  }
}

/** @internal */
export function getInputRate(chunkCount: number) {
  const chunksAfterHold = Math.max(0, chunkCount - 1 - INPUT_RATE_HOLD_CHUNKS);
  const ramp = Math.min(1, chunksAfterHold / INPUT_RATE_RAMP_CHUNKS);

  return INITIAL_INPUT_RATE + (MAX_INPUT_RATE - INITIAL_INPUT_RATE) * ramp;
}

/** @internal */
export function getAvailableTargetCount(
  targetCount: number,
  revealedCount: number,
  lastSampleTime: number | undefined,
  now: number,
) {
  if (lastSampleTime !== undefined && now - lastSampleTime < TRAILING_STALL_SECONDS) {
    return Math.max(revealedCount, targetCount - TRAILING_HOLD_COUNT);
  }

  return targetCount;
}

export function buildRevealTarget(
  text: string,
  graphemes = segmentGraphemes(text),
): TextRevealTarget {
  if (!graphemes.length) {
    return {
      graphemeCount: 0,
    };
  }

  const preferredInitialRevealCount = getPreferredSoftInitialRevealCount(text, graphemes);

  return {
    graphemeCount: graphemes.length,
    ...(preferredInitialRevealCount !== undefined && { preferredInitialRevealCount }),
  };
}

export function getCommonGraphemePrefixLength(first: string[], second: string[]) {
  const maximumLength = Math.min(first.length, second.length);
  let index = 0;

  while (index < maximumLength && first[index] === second[index]) {
    index += 1;
  }

  return index;
}

function buildWordSegments(text: string, graphemes: string[]): TextSegment[] {
  const graphemeEndOffsets: number[] = [];
  let graphemeIndex = 0;
  let offset = 0;

  graphemes.forEach((grapheme) => {
    offset += grapheme.length;
    graphemeEndOffsets.push(offset);
  });

  return Array.from(WORD_SEGMENTER!.segment(text), ({ index, segment, isWordLike }) => {
    const segmentEndOffset = index + segment.length;
    while (
      graphemeIndex < graphemeEndOffsets.length - 1
      && graphemeEndOffsets[graphemeIndex] < segmentEndOffset
    ) {
      graphemeIndex += 1;
    }

    return {
      endCount: graphemeIndex + 1,
      isWordLike: Boolean(isWordLike),
    };
  });
}

function getPreferredSoftInitialRevealCount(text: string, graphemes: string[]) {
  if (graphemes.length < INITIAL_REVEAL_DESIRED_COUNT) {
    return undefined;
  }

  if (!WORD_SEGMENTER) {
    return INITIAL_REVEAL_DESIRED_COUNT;
  }

  const segments = buildWordSegments(text, graphemes);
  for (const [index, segment] of segments.entries()) {
    if (segment.endCount < INITIAL_REVEAL_DESIRED_COUNT) continue;
    if (segment.endCount > MAXIMUM_INITIAL_REVEAL_GRAPHEMES) {
      return MAXIMUM_INITIAL_REVEAL_GRAPHEMES;
    }

    const isUnfinishedFinalWord = index === segments.length - 1 && segment.isWordLike;
    if (!isUnfinishedFinalWord) {
      return segment.endCount;
    }
  }

  return graphemes.length >= MAXIMUM_INITIAL_REVEAL_GRAPHEMES
    ? MAXIMUM_INITIAL_REVEAL_GRAPHEMES
    : undefined;
}

function normalizeTarget(target: TextRevealTarget): TextRevealTarget {
  const graphemeCount = Math.max(0, Math.floor(target.graphemeCount));
  const preferredInitialRevealCount = target.preferredInitialRevealCount === undefined
    ? undefined
    : Math.min(
      graphemeCount,
      MAXIMUM_INITIAL_REVEAL_GRAPHEMES,
      Math.max(0, Math.floor(target.preferredInitialRevealCount)),
    );

  return {
    graphemeCount,
    preferredInitialRevealCount: preferredInitialRevealCount || undefined,
  };
}

function clamp(value: number, minimum: number, maximum: number) {
  return Math.min(Math.max(value, minimum), maximum);
}

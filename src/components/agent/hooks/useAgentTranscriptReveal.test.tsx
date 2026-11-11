import React from '../../../lib/teact/teact';
import TeactDOM from '../../../lib/teact/teact-dom';

import { pause, waitFor } from '../../../util/schedulers';
import useAgentTranscriptReveal, { TRANSCRIPT_REVEAL_MAX_MS } from './useAgentTranscriptReveal';

let mockIsReducedMotion = false;
jest.mock('../../../hooks/useMediaQuery', () => ({ useMediaQuery: () => mockIsReducedMotion }));
jest.mock('../../../global', () => ({
  ...jest.requireActual('../../../global'),
  getGlobal: () => ({ settings: { animationLevel: 2 } }),
}));

let result: ReturnType<typeof useAgentTranscriptReveal>;

function Harness({ onInput }: { onInput: (value: string) => void }) {
  result = useAgentTranscriptReveal({ inputValue: 'Draft ', onInput });
  return undefined;
}

describe('useAgentTranscriptReveal', () => {
  let root: HTMLDivElement;
  let onInput: jest.Mock;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    onInput = jest.fn();
    TeactDOM.render(<Harness onInput={onInput} />, root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    mockIsReducedMotion = false;
    jest.restoreAllMocks();
  });

  it('writes a transcript after the draft a character at a time', async () => {
    result.revealTranscript(' Hi,  you ');
    expect(onInput.mock.calls).toEqual([['Draft H']]);

    expect(await waitFor(() => onInput.mock.lastCall?.[0] === 'Draft Hi,  you', 10, 30)).toBe(true);
    const values = onInput.mock.calls.map(([value]: [string]) => value);
    // Each frame adds what is due, never taking a character back
    values.slice(1).forEach((value, index) => {
      expect(value.startsWith(values[index].trimEnd())).toBe(true);
      expect(value.length).toBeGreaterThan(values[index].length);
    });
    const callCount = onInput.mock.calls.length;
    await pause(100);
    expect(onInput).toHaveBeenCalledTimes(callCount);
  });

  it('brings the characters of a long transcript closer together, to take no longer than a reveal may', async () => {
    const text = Array.from({ length: 80 }, (_, index) => `word${index}`).join(' ');
    const startedAt = performance.now();
    result.revealTranscript(text);

    expect(await waitFor(() => onInput.mock.lastCall?.[0] === `Draft ${text}`, 20, 60)).toBe(true);
    expect(performance.now() - startedAt).toBeLessThan(TRANSCRIPT_REVEAL_MAX_MS + 150);
    // It came in over several frames rather than at once
    expect(onInput.mock.calls.length).toBeGreaterThan(5);
  });

  it('writes the rest at once when the user types or sends while the characters come in', async () => {
    result.revealTranscript('one two three');

    expect(result.finishReveal()).toBe(true);
    expect(onInput).toHaveBeenLastCalledWith('Draft one two three');
    await pause(100);
    expect(onInput).toHaveBeenCalledTimes(2);
    // Once every character is in, typing and sending go on as usual
    expect(result.finishReveal()).toBe(false);
  });

  it('puts the whole transcript in at once where motion is reduced', () => {
    mockIsReducedMotion = true;
    TeactDOM.render(<Harness onInput={onInput} />, root);

    result.revealTranscript('one two three');
    expect(onInput.mock.calls).toEqual([['Draft one two three']]);
    expect(result.finishReveal()).toBe(false);
  });
});

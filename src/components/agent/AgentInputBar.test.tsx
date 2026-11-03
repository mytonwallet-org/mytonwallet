import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type { AgentInputBarDictation } from './AgentInputBar';

import { pause } from '../../util/schedulers';

import AgentInputBar from './AgentInputBar';

jest.mock('../ui/Input', () => ({ __esModule: true, default: () => undefined }));
jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => (key: string, values?: number | string) => {
    if (key === '$agent_time_hours') return `${String(values)} h`;
    if (key === '$agent_time_minutes') return `${String(values)} min`;
    if (key === '$agent_time_seconds') return `${String(values)} sec`;
    if (key === '$agent_dictation_time_left') return `${key}: ${String(values)}`;
    return key;
  },
}));

describe('AgentInputBar dictation', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    jest.restoreAllMocks();
  });

  function renderBar(dictation: AgentInputBarDictation, inputValue = '') {
    TeactDOM.render(
      <AgentInputBar
        inputValue={inputValue}
        dictation={dictation}
        onInput={jest.fn()}
        onKeyDown={jest.fn()}
        onSend={jest.fn()}
      />,
      root,
    );
    return pause(20);
  }

  function getButton(label: string) {
    return root.querySelector<HTMLButtonElement>(`button[aria-label="${label}"]`)!;
  }

  it('offers the microphone in place of sending while the draft is empty', async () => {
    const dictation = buildDictation({ phase: 'idle' });
    await renderBar(dictation);

    expect(getButton('$agent_dictation_start').classList.contains('not-open')).toBe(false);
    expect(getButton('Send').classList.contains('not-open')).toBe(true);
    getButton('$agent_dictation_start').click();
    expect(dictation.start).toHaveBeenCalled();

    await renderBar(dictation, 'Hi');
    expect(getButton('$agent_dictation_start').classList.contains('not-open')).toBe(true);
    expect(getButton('Send').classList.contains('not-open')).toBe(false);
  });

  it('shows the recording with a countdown near the limit, finishes it and cancels it on Escape', async () => {
    const dictation = buildDictation({ phase: 'recording', elapsedMs: 53_400, level: 1 });
    await renderBar(dictation);

    expect(root.textContent).toContain('0:53');
    expect(root.textContent).toContain('$agent_dictation_time_left');
    expect(getButton('Send').classList.contains('not-open')).toBe(true);

    const finish = getButton('$agent_dictation_finish');
    finish.click();
    expect(dictation.finish).toHaveBeenCalled();
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    expect(dictation.cancel).toHaveBeenCalled();
  });

  it('disables hidden dictation controls and hides them from screen readers', async () => {
    const dictation = buildDictation({ phase: 'idle' });
    await renderBar(dictation, 'Hi');

    const microphone = getButton('$agent_dictation_start');
    expect(microphone.disabled).toBe(true);
    expect(microphone.getAttribute('aria-hidden')).toBe('true');
    microphone.click();
    expect(dictation.start).not.toHaveBeenCalled();

    const action = getButton('$agent_dictation_finish');
    expect(action.disabled).toBe(true);
    expect(action.getAttribute('aria-hidden')).toBe('true');
    action.click();
    expect(dictation.cancelRecognition).not.toHaveBeenCalled();

    await renderBar({ ...dictation, phase: 'recording' }, 'Hi');
    expect(getButton('Send').disabled).toBe(true);
    expect(getButton('Send').getAttribute('aria-hidden')).toBe('true');
    expect(getButton('$agent_dictation_finish').disabled).toBe(false);
  });

  it('announces a constant warning only during the final ten seconds', async () => {
    const dictation = buildDictation({ phase: 'recording', elapsedMs: 49_000 });
    await renderBar(dictation);

    const status = root.querySelector('[role="status"]')!;
    expect(status.classList.contains('visually-hidden')).toBe(true);
    expect(status.textContent).toBe('');

    await renderBar({ ...dictation, elapsedMs: 50_000 });
    expect(status.textContent).toBe('$agent_dictation_time_left: 10');

    await renderBar({ ...dictation, elapsedMs: 59_000 });
    expect(status.textContent).toBe('$agent_dictation_time_left: 10');
  });

  it('records while the microphone is held; a slide cancels it or makes it hands-free', async () => {
    const dictation = buildDictation({ phase: 'idle' });
    await renderBar(dictation);
    const microphone = getButton('$agent_dictation_start');
    function dispatchPointer(
      type: string, clientX: number, clientY: number, target: EventTarget = window, pointerId = 1,
    ) {
      const event = new MouseEvent(type, {
        bubbles: true, cancelable: true, clientX, clientY, button: 0,
      });
      target.dispatchEvent(Object.assign(event, { pointerId, isPrimary: pointerId === 1 }));
    }

    // A tap records hands-free
    dispatchPointer('pointerdown', 300, 300, microphone);
    dispatchPointer('pointerup', 300, 300);
    expect(dictation.start).toHaveBeenCalledTimes(1);

    // Holding records, and letting go finishes
    dispatchPointer('pointerdown', 300, 300, microphone);
    await pause(260);
    expect(dictation.start).toHaveBeenCalledTimes(2);
    // Another finger that slides and lifts leaves the recording going
    dispatchPointer('pointermove', 140, 300, window, 2);
    dispatchPointer('pointerup', 140, 300, window, 2);
    expect(dictation.cancel).not.toHaveBeenCalled();
    expect(dictation.finish).not.toHaveBeenCalled();
    dispatchPointer('pointerup', 300, 300);
    expect(dictation.finish).toHaveBeenCalledTimes(1);

    // Sliding toward the start cancels at once
    dispatchPointer('pointerdown', 300, 300, microphone);
    await pause(260);
    dispatchPointer('pointermove', 140, 300);
    expect(dictation.cancel).toHaveBeenCalledTimes(1);
    dispatchPointer('pointerup', 140, 300);
    expect(dictation.finish).toHaveBeenCalledTimes(1);

    // Letting go after a slide up records hands-free instead of finishing
    dispatchPointer('pointerdown', 300, 300, microphone);
    await pause(260);
    dispatchPointer('pointermove', 300, 220);
    dispatchPointer('pointerup', 300, 220);
    expect(dictation.finish).toHaveBeenCalledTimes(1);
    expect(dictation.cancel).toHaveBeenCalledTimes(1);
  });

  it('ignores a second finish click until recognition has been in progress for 400 ms', async () => {
    const getNow = jest.spyOn(Date, 'now').mockReturnValue(1000);
    const dictation = buildDictation({ phase: 'recording' });
    await renderBar(dictation);

    getButton('$agent_dictation_finish').click();
    expect(dictation.finish).toHaveBeenCalledTimes(1);

    await renderBar({ ...dictation, phase: 'recognizing' });
    expect(root.querySelector('[role="status"]')!.textContent).toBe('$agent_dictation_recognizing');
    getButton('Cancel').click();
    expect(dictation.cancelRecognition).not.toHaveBeenCalled();

    getNow.mockReturnValue(1400);
    getButton('Cancel').click();
    expect(dictation.cancelRecognition).toHaveBeenCalledTimes(1);
  });
});

function buildDictation(state: Partial<AgentInputBarDictation>): AgentInputBarDictation {
  return {
    phase: 'idle',
    elapsedMs: 0,
    level: 0,
    transcriptCount: 0,
    failureCount: 0,
    start: jest.fn(),
    finish: jest.fn(),
    cancel: jest.fn(),
    cancelRecognition: jest.fn(),
    ...state,
  };
}

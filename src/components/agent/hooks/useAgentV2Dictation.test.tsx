import React from '../../../lib/teact/teact';
import TeactDOM from '../../../lib/teact/teact-dom';

import type { DictationRecorder, DictationRecording } from '../helpers/dictationRecorder';
import type { AgentDictation } from './useAgentV2Dictation';

import { getTranslation } from '../../../util/langProvider';
import { pause } from '../../../util/schedulers';
import { callApi } from '../../../api';
import { DICTATION_MAX_DURATION_MS, startDictationRecorder } from '../helpers/dictationRecorder';
import useAgentV2Dictation, { getIsAgentDictationSupported } from './useAgentV2Dictation';

jest.mock('../../../api', () => ({ callApi: jest.fn() }));
const mockShowToast = jest.fn();
jest.mock('../../../global', () => ({
  ...jest.requireActual('../../../global'),
  getActions: () => ({ showToast: mockShowToast }),
}));
jest.mock('../../../util/windowEnvironment', () => ({
  get IS_ELECTRON() {
    return Boolean(globalThis.window.electron);
  },
}));
let mockMinDurationMs = 0;

jest.mock('../helpers/dictationRecorder', () => ({
  DICTATION_MAX_DURATION_MS: 150,
  get DICTATION_MIN_DURATION_MS() {
    return mockMinDurationMs;
  },
  getDictationRecorderFormat: () => ({ mimeType: 'audio/webm;codecs=opus', format: 'webm' }),
  startDictationRecorder: jest.fn(),
}));

// Teact renders state changes on the next frame
const FRAME_MS = 30;
const RECORDING: DictationRecording = { audio: 'GkXfow==', format: 'webm', hasSpeech: true };

const callApiMock = jest.mocked(callApi);
const startRecorderMock = jest.mocked(startDictationRecorder);

let dictation: AgentDictation;

function Harness({ isActive, onTranscript }: { isActive: boolean; onTranscript: (text: string) => void }) {
  dictation = useAgentV2Dictation({ isActive, langCode: 'ru', onTranscript });
  return undefined;
}

describe('useAgentV2Dictation', () => {
  let root: HTMLDivElement;
  let onTranscript: jest.Mock;
  let recorder: { stop: jest.Mock; cancel: jest.Mock; pause: jest.Mock; resume: jest.Mock };
  let getUserMedia: jest.Mock;

  beforeEach(() => {
    root = document.createElement('div');
    document.body.appendChild(root);
    onTranscript = jest.fn();
    recorder = {
      stop: jest.fn(() => Promise.resolve(RECORDING)), cancel: jest.fn(), pause: jest.fn(), resume: jest.fn(),
    };
    getUserMedia = jest.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: { getUserMedia },
    });
    startRecorderMock.mockReset();
    startRecorderMock.mockImplementation(async () => {
      await navigator.mediaDevices.getUserMedia({ audio: true });
      return recorder as DictationRecorder;
    });
    callApiMock.mockReset();
    mockShowToast.mockReset();
    TeactDOM.render(<Harness isActive onTranscript={onTranscript} />, root);
  });

  afterEach(() => {
    TeactDOM.render(undefined, root);
    root.remove();
    window.electron = undefined;
    mockMinDurationMs = 0;
  });

  it('keeps a recording too short for a phrase on the device and says so', async () => {
    mockMinDurationMs = 10_000;

    dictation.start();
    await pause(FRAME_MS);
    dictation.finish();
    await pause(FRAME_MS);

    expect(recorder.cancel).toHaveBeenCalled();
    expect(recorder.stop).not.toHaveBeenCalled();
    expect(callApiMock).not.toHaveBeenCalled();
    expect(dictation.failure).toEqual({ kind: 'tooShort' });
    expect(dictation.notice).toBeUndefined();
    expect(dictation.failureCount).toBe(1);
    expect(dictation.phase).toBe('idle');
  });

  it('hides dictation in an Electron shell without microphone access support', () => {
    window.electron = {};

    expect(getIsAgentDictationSupported()).toBe(false);
  });

  it('reports denied Electron microphone access without opening the microphone', async () => {
    const requestMicrophoneAccess = jest.fn().mockResolvedValue(false);
    window.electron = { requestMicrophoneAccess };

    dictation.start();
    await pause(FRAME_MS);

    expect(requestMicrophoneAccess).toHaveBeenCalledTimes(1);
    expect(startRecorderMock).not.toHaveBeenCalled();
    expect(getUserMedia).not.toHaveBeenCalled();
    expect(dictation.notice).toEqual({ kind: 'microphoneDenied' });
    expect(dictation.phase).toBe('idle');
  });

  it('starts recording after the Electron shell grants microphone access', async () => {
    let grantMicrophoneAccess!: (value: boolean) => void;
    const requestMicrophoneAccess = jest.fn(() => new Promise<boolean>((resolve) => {
      grantMicrophoneAccess = resolve;
    }));
    window.electron = { requestMicrophoneAccess };
    expect(getIsAgentDictationSupported()).toBe(true);

    dictation.start();
    expect(requestMicrophoneAccess).toHaveBeenCalledTimes(1);
    expect(getUserMedia).not.toHaveBeenCalled();
    grantMicrophoneAccess(true);
    await pause(FRAME_MS);

    expect(startRecorderMock).toHaveBeenCalledTimes(1);
    expect(getUserMedia).toHaveBeenCalledTimes(1);
    expect(dictation.phase).toBe('recording');
    expect(dictation.notice).toBeUndefined();
  });

  it('records, transcribes in the app language and hands the text to the composer', async () => {
    callApiMock.mockResolvedValue({ ok: true, value: { protocolVersion: 3, outcome: 'transcribed', text: 'Hi' } });

    dictation.start();
    await pause(FRAME_MS);
    expect(dictation.phase).toBe('recording');
    dictation.finish();
    await pause(FRAME_MS);

    expect(callApiMock).toHaveBeenCalledWith('transcribeAgentV2Audio', {
      audio: 'GkXfow==', format: 'webm', lang: 'ru',
    });
    expect(onTranscript).toHaveBeenCalledWith('Hi');
    expect(dictation.phase).toBe('idle');
    expect(dictation.transcriptCount).toBe(1);
    expect(dictation.notice).toBeUndefined();
  });

  it('does not send a recording in which no voice was heard', async () => {
    recorder.stop.mockResolvedValue({ ...RECORDING, hasSpeech: false });

    dictation.start();
    await pause(FRAME_MS);
    dictation.finish();
    await pause(FRAME_MS);

    expect(callApiMock).not.toHaveBeenCalled();
    expect(dictation.failure).toEqual({ kind: 'noSpeech' });
    expect(dictation.failureCount).toBe(1);
    expect(dictation.notice).toBeUndefined();
  });

  it('reports a failed transcription as a failure of the microphone, without a notice to retry', async () => {
    callApiMock
      .mockResolvedValueOnce({ ok: false, error: { code: 'transcription_unavailable', retryable: true } })
      .mockResolvedValueOnce({ ok: false, error: { code: 'rate_limited', retryable: true, retryAfterMs: 60_000 } });

    dictation.start();
    await pause(FRAME_MS);
    dictation.finish();
    await pause(FRAME_MS);
    expect(dictation.failure).toEqual({ kind: 'error', code: 'transcription_unavailable' });
    expect(dictation.failureCount).toBe(1);
    expect(dictation.notice).toBeUndefined();
    expect(dictation).not.toHaveProperty('retry');

    dictation.start();
    await pause(FRAME_MS);
    dictation.finish();
    await pause(FRAME_MS);
    expect(dictation.failure).toEqual({ kind: 'error', code: 'rate_limited' });
    expect(dictation.failureCount).toBe(2);
    expect(onTranscript).not.toHaveBeenCalled();
  });

  it('never records a phrase let go of while the browser is still opening the microphone', async () => {
    let openMicrophone!: NoneToVoidFunction;
    startRecorderMock.mockImplementation(() => new Promise((resolve) => {
      openMicrophone = () => resolve(recorder as DictationRecorder);
    }));

    dictation.start();
    dictation.finish();
    openMicrophone();
    await pause(FRAME_MS);

    expect(recorder.cancel).toHaveBeenCalled();
    expect(recorder.stop).not.toHaveBeenCalled();
    expect(dictation.phase).toBe('idle');
  });

  it('drops a transcript that arrives after the user cancelled it', async () => {
    let resolveTranscription!: (value: unknown) => void;
    const transcription = new Promise<unknown>((resolve) => {
      resolveTranscription = resolve;
    });
    callApiMock.mockReturnValue(transcription as ReturnType<typeof callApi>);

    dictation.start();
    await pause(FRAME_MS);
    dictation.finish();
    await pause(FRAME_MS);
    expect(dictation.phase).toBe('recognizing');

    dictation.cancelRecognition();
    resolveTranscription({ ok: true, value: { protocolVersion: 3, outcome: 'transcribed', text: 'Late' } });
    await pause(FRAME_MS);

    expect(onTranscript).not.toHaveBeenCalled();
    expect(dictation.phase).toBe('idle');
  });

  it('cancels recording and drops a late transcript when the agent screen becomes inactive', async () => {
    dictation.start();
    await pause(FRAME_MS);
    expect(dictation.phase).toBe('recording');

    TeactDOM.render(<Harness isActive={false} onTranscript={onTranscript} />, root);
    await pause(FRAME_MS * 2);
    expect(recorder.cancel).toHaveBeenCalledTimes(1);
    expect(dictation.phase).toBe('idle');

    dictation.start();
    await pause(DICTATION_MAX_DURATION_MS);
    expect(startRecorderMock).toHaveBeenCalledTimes(1);
    expect(recorder.stop).not.toHaveBeenCalled();
    expect(callApiMock).not.toHaveBeenCalled();

    let resolveTranscription!: (value: unknown) => void;
    callApiMock.mockReturnValue(new Promise<unknown>((resolve) => {
      resolveTranscription = resolve;
    }) as ReturnType<typeof callApi>);

    TeactDOM.render(<Harness isActive onTranscript={onTranscript} />, root);
    dictation.start();
    await pause(FRAME_MS);
    dictation.finish();
    await pause(FRAME_MS);
    expect(dictation.phase).toBe('recognizing');

    TeactDOM.render(<Harness isActive={false} onTranscript={onTranscript} />, root);
    await pause(FRAME_MS * 2);
    expect(dictation.phase).toBe('idle');
    resolveTranscription({ ok: true, value: { protocolVersion: 3, outcome: 'transcribed', text: 'Late' } });
    await pause(FRAME_MS);

    expect(onTranscript).not.toHaveBeenCalled();
    expect(dictation.transcriptCount).toBe(0);
  });

  it('cancels recording when the page is hidden', async () => {
    dictation.start();
    await pause(FRAME_MS * 2);
    expect(dictation.phase).toBe('recording');

    Object.defineProperty(document, 'hidden', { configurable: true, get: () => true });
    try {
      document.dispatchEvent(new Event('visibilitychange'));
      await pause(FRAME_MS);
    } finally {
      // Back to the `Document` prototype's own getter
      delete (document as { hidden?: boolean }).hidden;
    }

    expect(recorder.cancel).toHaveBeenCalledTimes(1);
    expect(dictation.phase).toBe('idle');
    expect(callApiMock).not.toHaveBeenCalled();
  });

  it('does not transcribe a recording cancelled while it is stopping', async () => {
    let resolveStop!: (value: DictationRecording) => void;
    recorder.stop.mockReturnValue(new Promise<DictationRecording>((resolve) => {
      resolveStop = resolve;
    }));

    dictation.start();
    await pause(FRAME_MS);
    dictation.finish();
    expect(recorder.stop).toHaveBeenCalled();
    dictation.cancel();
    resolveStop(RECORDING);
    await pause(FRAME_MS);

    expect(callApiMock).not.toHaveBeenCalled();
    expect(onTranscript).not.toHaveBeenCalled();
    expect(dictation.phase).toBe('idle');
    expect(dictation.notice).toBeUndefined();
  });

  it('closes a microphone that opens after the user cancelled the start', async () => {
    let openMicrophone!: (value: DictationRecorder) => void;
    startRecorderMock.mockReturnValue(new Promise((resolve) => {
      openMicrophone = resolve;
    }));

    dictation.start();
    await pause(FRAME_MS);
    dictation.cancel();
    openMicrophone(recorder as DictationRecorder);
    await pause(FRAME_MS);

    expect(recorder.cancel).toHaveBeenCalled();
    expect(dictation.phase).toBe('idle');
  });

  it('says so when the microphone is refused', async () => {
    startRecorderMock.mockRejectedValue(new DOMException('denied', 'NotAllowedError'));

    dictation.start();
    await pause(FRAME_MS);

    expect(dictation.notice).toEqual({ kind: 'microphoneDenied' });
    expect(dictation.failure).toEqual({ kind: 'microphoneDenied' });
    expect(mockShowToast).toHaveBeenCalledTimes(1);
    expect(mockShowToast).toHaveBeenCalledWith({ message: getTranslation('$agent_dictation_microphone_denied') });
    expect(dictation.phase).toBe('idle');
  });

  it('reports a missing microphone as an internal error, without a notice', async () => {
    startRecorderMock.mockRejectedValue(new DOMException('No microphone', 'NotFoundError'));

    dictation.start();
    await pause(FRAME_MS);

    expect(dictation.failure).toEqual({ kind: 'error', code: 'internal_error' });
    expect(dictation.notice).toBeUndefined();
    expect(mockShowToast).not.toHaveBeenCalled();
    expect(dictation.phase).toBe('idle');
  });

  it('pauses and resumes the same recording, and transcribes all of it', async () => {
    callApiMock.mockResolvedValue({ ok: true, value: { protocolVersion: 3, outcome: 'transcribed', text: 'Hi' } });

    dictation.start();
    await pause(FRAME_MS);
    dictation.pause();
    await pause(FRAME_MS);
    expect(recorder.pause).toHaveBeenCalledTimes(1);
    expect(dictation).toMatchObject({ phase: 'recording', isPaused: true, level: 0 });
    // The limit waits for the recording to go on
    await pause(DICTATION_MAX_DURATION_MS * 2);
    expect(recorder.stop).not.toHaveBeenCalled();

    dictation.resume();
    await pause(FRAME_MS);
    expect(recorder.resume).toHaveBeenCalledTimes(1);
    expect(dictation).toMatchObject({ phase: 'recording', isPaused: false });
    expect(startRecorderMock).toHaveBeenCalledTimes(1);

    dictation.pause();
    dictation.finish();
    await pause(FRAME_MS);
    expect(recorder.stop).toHaveBeenCalledTimes(1);
    expect(onTranscript).toHaveBeenCalledWith('Hi');
    expect(dictation).toMatchObject({ phase: 'idle', isPaused: false });
  });

  it('counts only the time recorded, without its pauses, toward the shortest phrase', async () => {
    mockMinDurationMs = 100;

    dictation.start();
    await pause(FRAME_MS);
    dictation.pause();
    await pause(mockMinDurationMs * 2);
    dictation.finish();
    await pause(FRAME_MS);

    expect(recorder.cancel).toHaveBeenCalled();
    expect(recorder.stop).not.toHaveBeenCalled();
    expect(dictation.failure).toEqual({ kind: 'tooShort' });
  });

  it('stops at the length limit and transcribes what was recorded', async () => {
    callApiMock.mockResolvedValue({ ok: true, value: { protocolVersion: 3, outcome: 'transcribed', text: 'Hi' } });

    dictation.start();
    await pause(300);

    expect(recorder.stop).toHaveBeenCalled();
    expect(onTranscript).toHaveBeenCalledWith('Hi');
    expect(dictation.notice).toBeUndefined();
  });
});

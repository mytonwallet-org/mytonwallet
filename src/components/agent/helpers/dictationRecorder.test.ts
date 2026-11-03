import { pause } from '../../../util/schedulers';
import { getDictationRecorderFormat, startDictationRecorder } from './dictationRecorder';

let supportedTypes: string[] = [];
let inputSample = 0;
let audioContextState: AudioContextState = 'running';
const track = { stop: jest.fn() };
const recorderStart = jest.fn();
const recorderStop = jest.fn();
const audioContextResume = jest.fn(() => Promise.resolve());
const audioContextClose = jest.fn(() => Promise.resolve());

class FakeMediaRecorder {
  static isTypeSupported(type: string) {
    return supportedTypes.includes(type);
  }

  state: RecordingState = 'inactive';

  mimeType: string;

  ondataavailable?: (e: { data: Blob }) => void;

  onstop?: () => void;

  onerror?: () => void;

  constructor(_stream: MediaStream, options: MediaRecorderOptions) {
    this.mimeType = options.mimeType!;
  }

  start() {
    recorderStart();
    this.state = 'recording';
  }

  stop() {
    recorderStop();
    this.state = 'inactive';
    this.ondataavailable?.({ data: new Blob(['abc']) });
    this.onstop?.();
  }
}

class FakeAudioContext extends EventTarget {
  state = audioContextState;

  createAnalyser() {
    return {
      fftSize: 0,
      getFloatTimeDomainData: (samples: Float32Array) => samples.fill(inputSample),
    };
  }

  createMediaStreamSource() {
    return { connect: jest.fn() };
  }

  resume = audioContextResume;

  close = audioContextClose;
}

describe('dictationRecorder', () => {
  beforeEach(() => {
    supportedTypes = ['audio/mp4', 'audio/ogg;codecs=opus'];
    inputSample = 0;
    audioContextState = 'running';
    track.stop.mockClear();
    recorderStart.mockReset();
    recorderStop.mockReset();
    audioContextResume.mockReset().mockResolvedValue(undefined);
    audioContextClose.mockClear();
    Object.assign(window, { MediaRecorder: FakeMediaRecorder, AudioContext: FakeAudioContext });
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: { getUserMedia: jest.fn(() => Promise.resolve({ getTracks: () => [track] })) },
    });
  });

  it('picks the first container the browser records, and none without a recorder', () => {
    expect(getDictationRecorderFormat()).toEqual({ mimeType: 'audio/mp4', format: 'm4a' });

    supportedTypes.push('audio/webm;codecs=opus');
    expect(getDictationRecorderFormat()).toEqual({ mimeType: 'audio/webm;codecs=opus', format: 'webm' });

    Object.assign(window, { MediaRecorder: undefined });
    expect(getDictationRecorderFormat()).toBeUndefined();
  });

  it('returns the recording as base64 and releases the microphone', async () => {
    inputSample = 0.1;
    const onLevel = jest.fn();
    const recorder = await startDictationRecorder(onLevel);
    await pause(100);

    await expect(recorder.stop()).resolves.toEqual({ audio: 'YWJj', format: 'm4a', hasSpeech: true });
    expect(onLevel).toHaveBeenCalledWith(expect.closeTo(0.4, 5));
    expect(track.stop).toHaveBeenCalled();
    expect(audioContextClose).toHaveBeenCalled();
  });

  it('tells a quiet room from speech', async () => {
    inputSample = 0.005;
    const recorder = await startDictationRecorder(jest.fn());
    await pause(100);

    await expect(recorder.stop()).resolves.toMatchObject({ hasSpeech: false });
  });

  it('releases the microphone and meter when the recorder fails to start', async () => {
    const error = new Error('Recording could not start');
    recorderStart.mockImplementationOnce(() => {
      throw error;
    });

    await expect(startDictationRecorder(jest.fn())).rejects.toBe(error);
    expect(track.stop).toHaveBeenCalledTimes(1);
    expect(audioContextClose).toHaveBeenCalledTimes(1);
  });

  it('sends the recording when the audio context stays suspended', async () => {
    audioContextState = 'suspended';
    audioContextResume.mockRejectedValueOnce(new Error('Audio context could not resume'));
    const recorder = await startDictationRecorder(jest.fn());
    await pause(100);

    await expect(recorder.stop()).resolves.toMatchObject({ hasSpeech: true });
  });

  it('releases the microphone and meter when the recorder fails to stop', async () => {
    const error = new Error('Recording could not stop');
    recorderStop.mockImplementationOnce(() => {
      throw error;
    });
    const recorder = await startDictationRecorder(jest.fn());

    await expect(recorder.stop()).rejects.toBe(error);
    expect(track.stop).toHaveBeenCalledTimes(1);
    expect(audioContextClose).toHaveBeenCalledTimes(1);
  });
});

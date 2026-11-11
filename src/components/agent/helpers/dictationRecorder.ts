import type { AgentV2Transcription } from '../../../api/agentV2/types';

export type DictationFormat = AgentV2Transcription['format'];

export interface DictationRecording {
  /** The recording's bytes, base64-encoded */
  audio: string;
  format: DictationFormat;
  /** Whether the input rose above the level of a quiet room at any point */
  hasSpeech: boolean;
}

export interface DictationRecorder {
  stop: () => Promise<DictationRecording>;
  cancel: NoneToVoidFunction;
  /** Holds the recording, which `resume` continues; the level reads 0 meanwhile */
  pause: NoneToVoidFunction;
  resume: NoneToVoidFunction;
}

/** The longest dictation the agent accepts */
export const DICTATION_MAX_DURATION_MS = 60_000;
/** A shorter recording is a tap rather than a phrase, and does not leave the device, as on mobile */
export const DICTATION_MIN_DURATION_MS = 700;

// The first container this browser records goes; the agent reads all three
const RECORDER_FORMATS: readonly { mimeType: string; format: DictationFormat }[] = [
  { mimeType: 'audio/webm;codecs=opus', format: 'webm' },
  { mimeType: 'audio/mp4', format: 'm4a' },
  { mimeType: 'audio/ogg;codecs=opus', format: 'ogg_opus' },
];
// Speech needs far less than a recorder's default: a minute at this rate is a quarter of the agent's 1 MiB limit
const AUDIO_BITS_PER_SECOND = 32_000;
const LEVEL_SAMPLE_INTERVAL_MS = 80;
const ANALYSER_FFT_SIZE = 1024;
// Above this RMS a frame is speech rather than room noise. A recording that never reaches it is not sent:
// on silence the transcription model writes down an invented word.
const SPEECH_RMS_THRESHOLD = 0.02;
// The RMS that fills the level meter
const FULL_SCALE_RMS = 0.25;

export function getDictationRecorderFormat() {
  if (typeof MediaRecorder === 'undefined' || !navigator.mediaDevices?.getUserMedia) return undefined;
  return RECORDER_FORMATS.find(({ mimeType }) => MediaRecorder.isTypeSupported(mimeType));
}

/** Starts recording from the microphone; `onLevel` receives the input level between 0 and 1 while it runs */
export async function startDictationRecorder(onLevel: (level: number) => void): Promise<DictationRecorder> {
  const recorderFormat = getDictationRecorderFormat();
  if (!recorderFormat) throw new Error('Dictation is not supported in this browser');

  const stream = await navigator.mediaDevices.getUserMedia({
    audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true },
  });
  const chunks: Blob[] = [];
  let isCancelled = false;
  let recorder: MediaRecorder;
  let meter: ReturnType<typeof startLevelMeter> | undefined;
  try {
    recorder = new MediaRecorder(stream, {
      mimeType: recorderFormat.mimeType,
      audioBitsPerSecond: AUDIO_BITS_PER_SECOND,
    });
    recorder.ondataavailable = (e) => {
      if (e.data.size) chunks.push(e.data);
    };
    meter = startLevelMeter(stream, onLevel);
    recorder.start();
  } catch (err) {
    release();
    throw err;
  }

  function release() {
    meter?.stop();
    stream.getTracks().forEach((track) => track.stop());
  }

  return {
    stop: () => new Promise((resolve, reject) => {
      recorder.onstop = () => {
        if (isCancelled) return;
        release();
        blobToBase64(new Blob(chunks, { type: recorder.mimeType }))
          .then((audio) => resolve({ audio, format: recorderFormat.format, hasSpeech: meter.hasSpeech() }))
          .catch(reject);
      };
      recorder.onerror = () => {
        if (isCancelled) return;
        release();
        reject(new Error('Recording failed'));
      };
      try {
        recorder.stop();
      } catch (err) {
        release();
        reject(err);
      }
    }),
    cancel: () => {
      isCancelled = true;
      if (recorder.state !== 'inactive') recorder.stop();
      release();
    },
    pause: () => {
      if (recorder.state === 'recording') recorder.pause();
      meter?.setIsPaused(true);
      onLevel(0);
    },
    resume: () => {
      if (recorder.state === 'paused') recorder.resume();
      meter?.setIsPaused(false);
    },
  };
}

function startLevelMeter(stream: MediaStream, onLevel: (level: number) => void) {
  let audioContext: AudioContext | undefined;
  let hasRun = false;
  try {
    audioContext = new AudioContext();
    hasRun = audioContext.state === 'running';
    audioContext.addEventListener('statechange', handleStateChange);
    const analyser = audioContext.createAnalyser();
    analyser.fftSize = ANALYSER_FFT_SIZE;
    audioContext.createMediaStreamSource(stream).connect(analyser);
    // A context created after an await may start suspended
    void audioContext.resume().catch(() => undefined);

    const samples = new Float32Array(analyser.fftSize);
    let hasSpeech = false;
    // A paused recording does not hear what is said meanwhile
    let isPaused = false;
    const timer = window.setInterval(() => {
      if (isPaused) return;
      analyser.getFloatTimeDomainData(samples);
      let sum = 0;
      for (const sample of samples) sum += sample * sample;
      const rms = Math.sqrt(sum / samples.length);
      if (rms >= SPEECH_RMS_THRESHOLD) hasSpeech = true;
      onLevel(Math.min(1, rms / FULL_SCALE_RMS));
    }, LEVEL_SAMPLE_INTERVAL_MS);

    return {
      stop: () => {
        window.clearInterval(timer);
        handleStateChange();
        audioContext!.removeEventListener('statechange', handleStateChange);
        void audioContext!.close().catch(() => undefined);
      },
      hasSpeech: () => hasSpeech || !hasRun,
      setIsPaused: (value: boolean) => {
        isPaused = value;
      },
    };
  } catch {
    audioContext?.removeEventListener('statechange', handleStateChange);
    void audioContext?.close().catch(() => undefined);
    // Without a meter nothing tells silence from speech, so the recording is sent as it is
    return { stop: () => undefined, hasSpeech: () => true, setIsPaused: () => undefined };
  }

  function handleStateChange() {
    if (audioContext!.state === 'running') hasRun = true;
  }
}

function blobToBase64(blob: Blob) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const dataUrl = typeof reader.result === 'string' ? reader.result : '';
      resolve(dataUrl.slice(dataUrl.indexOf(',') + 1));
    };
    reader.onerror = () => reject(reader.error ?? new Error('Recording could not be read'));
    reader.readAsDataURL(blob);
  });
}

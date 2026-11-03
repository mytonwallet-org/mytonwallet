import { useEffect, useRef, useState } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { AgentV2ErrorCode } from '../../../api/agentV2/protocol/types';
import type { DictationRecorder, DictationRecording } from '../helpers/dictationRecorder';

import { IS_AIR_APP, IS_EXTENSION, IS_TELEGRAM_APP } from '../../../config';
import { getTranslation } from '../../../util/langProvider';
import { IS_ELECTRON } from '../../../util/windowEnvironment';
import { callApi } from '../../../api';
import {
  DICTATION_MAX_DURATION_MS,
  DICTATION_MIN_DURATION_MS,
  getDictationRecorderFormat,
  startDictationRecorder,
} from '../helpers/dictationRecorder';

import useLastCallback from '../../../hooks/useLastCallback';

export type AgentDictationPhase = 'idle' | 'recording' | 'recognizing';

/** Why a dictation ended without text; the microphone turns red and a screen reader hears it, as on mobile */
export type AgentDictationFailure =
  | { kind: 'noSpeech' }
  | { kind: 'tooShort' }
  | { kind: 'microphoneDenied' }
  | { kind: 'error'; code: AgentV2ErrorCode };

/** Shown under the composer only when the browser refuses the microphone, which nothing else would explain */
export type AgentDictationNotice = { kind: 'microphoneDenied' };

export interface AgentDictation {
  phase: AgentDictationPhase;
  elapsedMs: number;
  /** The latest input level, 0…1 */
  level: number;
  notice?: AgentDictationNotice;
  /** The latest dictation that ended without a transcript */
  failure?: AgentDictationFailure;
  /** Grows with every transcript put into the composer */
  transcriptCount: number;
  /** Grows with every dictation that ends without a transcript */
  failureCount: number;
  start: NoneToVoidFunction;
  finish: NoneToVoidFunction;
  cancel: NoneToVoidFunction;
  cancelRecognition: NoneToVoidFunction;
  dismissNotice: NoneToVoidFunction;
}

// The extension popup cannot show the microphone prompt
const IS_DICTATION_PLATFORM = !IS_EXTENSION && !IS_AIR_APP && !IS_TELEGRAM_APP;

export function getIsAgentDictationSupported() {
  return IS_DICTATION_PLATFORM
    && (!IS_ELECTRON || Boolean(window.electron?.requestMicrophoneAccess))
    && Boolean(getDictationRecorderFormat());
}

/**
 * Records one phrase and turns it into text through the agent. The text goes to `onTranscript` for the user to
 * read before sending; nothing is sent as a message.
 */
export default function useAgentV2Dictation({ isActive, langCode, onTranscript }: {
  isActive: boolean;
  langCode?: string;
  onTranscript: (text: string) => void;
}): AgentDictation {
  const [phase, setPhase] = useState<AgentDictationPhase>('idle');
  const [elapsedMs, setElapsedMs] = useState(0);
  const [level, setLevel] = useState(0);
  const [notice, setNotice] = useState<AgentDictationNotice>();
  const [failure, setFailure] = useState<AgentDictationFailure>();
  const [transcriptCount, setTranscriptCount] = useState(0);
  const [failureCount, setFailureCount] = useState(0);
  const recorderRef = useRef<DictationRecorder>();
  const recordingStartedAtRef = useRef(0);
  // The browser is asking for the microphone or opening it
  const isStartingRef = useRef(false);
  const limitTimerRef = useRef<number>();
  // A cancelled start or recognition can still resolve; only the latest one may change the state
  const attemptRef = useRef(0);

  const fail = useLastCallback((reason: AgentDictationFailure) => {
    setFailure(reason);
    setFailureCount((count) => count + 1);
    if (reason.kind === 'microphoneDenied') {
      setNotice(reason);
      getActions().showToast({ message: getTranslation('$agent_dictation_microphone_denied') });
    }
  });

  useEffect(() => () => {
    attemptRef.current += 1;
    window.clearTimeout(limitTimerRef.current);
    recorderRef.current?.cancel();
  }, []);

  const transcribe = useLastCallback(async (recording: DictationRecording) => {
    const attempt = ++attemptRef.current;
    setPhase('recognizing');
    const result = await callApi('transcribeAgentV2Audio', {
      audio: recording.audio,
      format: recording.format,
      ...(langCode && { lang: langCode }),
    });
    if (attempt !== attemptRef.current) return;

    setPhase('idle');
    if (!result) {
      fail({ kind: 'error', code: 'network_error' });
      return;
    }
    if (!result.ok) {
      fail({ kind: 'error', code: result.error.code });
      return;
    }

    if (result.value.outcome === 'no_speech') {
      fail({ kind: 'noSpeech' });
      return;
    }
    // The draft changes first, so whatever reacts to the count already sees the text in it
    onTranscript(result.value.text);
    setTranscriptCount((count) => count + 1);
  });

  const stopRecording = useLastCallback(async () => {
    const recorder = recorderRef.current;
    if (!recorder) return;
    const attempt = attemptRef.current;
    recorderRef.current = undefined;
    window.clearTimeout(limitTimerRef.current);

    if (Date.now() - recordingStartedAtRef.current < DICTATION_MIN_DURATION_MS) {
      recorder.cancel();
      setPhase('idle');
      fail({ kind: 'tooShort' });
      return;
    }

    let recording: DictationRecording;
    try {
      recording = await recorder.stop();
    } catch {
      if (attempt !== attemptRef.current) return;
      setPhase('idle');
      fail({ kind: 'error', code: 'audio_unreadable' });
      return;
    }
    if (attempt !== attemptRef.current) return;
    if (!recording.hasSpeech || !recording.audio) {
      setPhase('idle');
      fail({ kind: 'noSpeech' });
      return;
    }

    void transcribe(recording);
  });

  const start = useLastCallback(async () => {
    if (!isActive || phase !== 'idle') return;
    const attempt = ++attemptRef.current;
    setNotice(undefined);
    setLevel(0);
    setElapsedMs(0);
    setPhase('recording');
    isStartingRef.current = true;

    let startedAt = Date.now();
    let recorder: DictationRecorder;
    try {
      if (IS_ELECTRON) {
        const hasMicrophoneAccess = await window.electron?.requestMicrophoneAccess?.();
        if (attempt !== attemptRef.current) return;
        if (!hasMicrophoneAccess) throw new DOMException('Microphone access denied', 'NotAllowedError');
      }
      recorder = await startDictationRecorder((inputLevel) => {
        setLevel(inputLevel);
        setElapsedMs(Date.now() - startedAt);
      });
      // The clock starts once the microphone is open, not while the browser asks for it
      startedAt = Date.now();
      recordingStartedAtRef.current = startedAt;
    } catch (err) {
      if (attempt !== attemptRef.current) return;
      isStartingRef.current = false;
      setPhase('idle');
      const isMicrophoneDenied = err instanceof Error
        && (err.name === 'NotAllowedError' || err.name === 'SecurityError');
      fail(isMicrophoneDenied
        ? { kind: 'microphoneDenied' }
        : { kind: 'error', code: 'internal_error' });
      return;
    }
    // Cancelled while the browser was asking for the microphone
    if (attempt !== attemptRef.current) {
      recorder.cancel();
      return;
    }

    isStartingRef.current = false;
    recorderRef.current = recorder;
    // At the limit the recording finishes by itself
    limitTimerRef.current = window.setTimeout(() => void stopRecording(), DICTATION_MAX_DURATION_MS);
  });

  const cancel = useLastCallback(() => {
    attemptRef.current += 1;
    isStartingRef.current = false;
    window.clearTimeout(limitTimerRef.current);
    recorderRef.current?.cancel();
    recorderRef.current = undefined;
    setPhase('idle');
    setLevel(0);
  });

  // A recording let go of while the browser is still opening the microphone never starts
  const finish = useLastCallback(() => {
    if (isStartingRef.current) {
      cancel();
      return;
    }
    void stopRecording();
  });

  const cancelRecognition = useLastCallback(() => {
    attemptRef.current += 1;
    setPhase('idle');
  });

  useEffect(() => {
    if (isActive) return;
    if (phase === 'recording') cancel();
    else if (phase === 'recognizing') cancelRecognition();
  }, [cancel, cancelRecognition, isActive, phase]);

  // A hidden page, as behind another tab or app, does not keep the microphone open where the user cannot see it
  useEffect(() => {
    if (phase !== 'recording') return undefined;

    function handleVisibilityChange() {
      if (document.hidden) cancel();
    }

    document.addEventListener('visibilitychange', handleVisibilityChange);
    // The page may have been hidden before the listener came, while the recording was starting
    handleVisibilityChange();
    return () => document.removeEventListener('visibilitychange', handleVisibilityChange);
  }, [cancel, phase]);

  const dismissNotice = useLastCallback(() => {
    setNotice(undefined);
  });

  return {
    phase,
    elapsedMs,
    level,
    notice,
    failure,
    transcriptCount,
    failureCount,
    start,
    finish,
    cancel,
    cancelRecognition,
    dismissNotice,
  };
}

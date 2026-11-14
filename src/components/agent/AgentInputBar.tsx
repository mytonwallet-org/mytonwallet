import type { TeactNode } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useLayoutEffect, useRef, useState,
} from '../../lib/teact/teact';
import { setExtraStyles } from '../../lib/teact/teact-dom';

import type { AgentDictationCircleMode } from './AgentDictationCircle';
import type { AgentTranscriptReveal } from './hooks/useAgentTranscriptReveal';
import type { AgentDictation } from './hooks/useAgentV2Dictation';

import { requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import buildClassName from '../../util/buildClassName';
import captureEscKeyListener from '../../util/captureEscKeyListener';
import segmentGraphemes from '../../util/segmentGraphemes';
import { SWIPE_DISABLED_CLASS_NAME } from '../../util/swipeController';
import { IS_TOUCH_ENV } from '../../util/windowEnvironment';
import { DICTATION_MAX_DURATION_MS } from './helpers/dictationRecorder';

import useCurrentOrPrev from '../../hooks/useCurrentOrPrev';
import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useShowTransition from '../../hooks/useShowTransition';
import useThrottledCallback from '../../hooks/useThrottledCallback';
import useToggleClass from '../../hooks/useToggleClass';

import Input from '../ui/Input';
import Portal from '../ui/Portal';
import AgentDictationCircle, { DESIGN_PIXEL } from './AgentDictationCircle';
import AgentFieldGlow from './AgentFieldGlow';
import AgentIcon from './AgentIcon';

import styles from './AgentInputBar.module.scss';

export type AgentInputBarDictation = Pick<AgentDictation,
  'phase' | 'isPaused' | 'elapsedMs' | 'level' | 'transcriptCount' | 'failureCount' | 'start' | 'finish' | 'cancel'
  | 'pause' | 'resume' | 'cancelRecognition'>;

/** How the user records: holding the microphone, or hands-free after a tap or a slide up */
type DictationHold = 'none' | 'holding' | 'locked';

interface MicrophonePress {
  /** The finger or button that pressed; other pointers on the screen do not move or end the press */
  pointerId: number;
  startX: number;
  startY: number;
  lastX: number;
  lastY: number;
  lastAt: number;
  velocityX: number;
  velocityY: number;
  isHolding: boolean;
  timer: number;
  /** The window listeners this press added, which it removes when it ends */
  listeners: {
    move: (e: PointerEvent) => void;
    end: (e: PointerEvent) => void;
    cancel: (e: PointerEvent) => void;
    blur: NoneToVoidFunction;
  };
}

// The countdown appears this long before a dictation reaches its limit
const DICTATION_ENDING_MS = 10_000;
const DICTATION_HIGHLIGHT_MS = 1500;
const DICTATION_ACTION_DELAY_MS = 400;
// Telegram's voice recording gestures, as on mobile
const HOLD_DELAY_MS = 220;
const CANCEL_DISTANCE = 150 * DESIGN_PIXEL;
const CANCEL_RELEASE_DISTANCE = 100 * DESIGN_PIXEL;
const LOCK_DISTANCE = 110 * DESIGN_PIXEL;
const LOCK_RELEASE_DISTANCE = 60 * DESIGN_PIXEL;
const RELEASE_VELOCITY = 400 * DESIGN_PIXEL;
// The share of the finger's speed so far kept at each move
const VELOCITY_SMOOTHING = 0.4;
const HINT_FADE_DISTANCE = 110 * DESIGN_PIXEL;
const FAILURE_DURATION_MS = 750;
const CIRCLE_CLOSE_DURATION_MS = 180;
const SLIDE_HINT_CLOSE_DURATION_MS = 250;
const NO_DRAG = { x: 0, y: 0 };

interface OwnProps {
  inputRef?: React.RefObject<HTMLTextAreaElement | undefined>;
  inputValue: string;
  /** What the empty input asks for; "Ask anything" by default */
  placeholder?: string;
  /** Blocks sending only; the draft stays editable while an answer is running */
  isDisabled?: boolean;
  /** Dims the input while a limit keeps the Agent from answering */
  isDimmed?: boolean;
  /** Voice input in place of the send button while the draft is empty; absent where it is not supported */
  dictation?: AgentInputBarDictation;
  /** Pressing the microphone starts nothing and goes to `onHeldDictation`, as while the Agent asks for consent */
  isDictationHeld?: boolean;
  onHeldDictation?: NoneToVoidFunction;
  dictationNotice?: TeactNode;
  /** Read out to a screen reader, unseen */
  dictationAnnouncement?: TeactNode;
  /** The transcript the draft ends with, while its words come in */
  transcriptReveal?: AgentTranscriptReveal;
  /** An answer is being produced, which `onStop` stops: the microphone turns into Stop in place of send */
  canStop?: boolean;
  onInput: (value: string) => void;
  onKeyDown: (e: React.KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
  onSend: NoneToVoidFunction;
  /** Present where an answer can be stopped from the field */
  onStop?: NoneToVoidFunction;
  onFocus?: NoneToVoidFunction;
  onHeightChange?: (height: number) => void;
}

function AgentInputBar({
  inputRef: externalInputRef, inputValue, placeholder, isDisabled, isDimmed, canStop = false,
  dictation, isDictationHeld, onHeldDictation, dictationNotice, dictationAnnouncement, transcriptReveal,
  onInput, onKeyDown, onSend, onStop, onFocus, onHeightChange,
}: OwnProps) {
  const lang = useLang();
  const { isPortrait } = useDeviceScreen();
  const [isHighlighted, setIsHighlighted] = useState(false);
  const [hold, setHold] = useState<DictationHold>('none');
  // The finger moves many times a frame, so its travel is kept out of the state that renders the bar
  const dragRef = useRef(NO_DRAG);
  const [circleAnchor, setCircleAnchor] = useState<{ x: number; y: number }>();
  const [circleFailure, setCircleFailure] = useState<{ isFailureOnly: boolean }>();
  const dictationActionRef = useRef<HTMLButtonElement>();
  const dictationCancelRef = useRef<HTMLButtonElement>();
  const dictationTimerRef = useRef<HTMLSpanElement>();
  const pressRef = useRef<MicrophonePress>();
  const recognitionStartedAtRef = useRef(0);
  const dictationPhase = dictation?.phase ?? 'idle';
  const isDictating = dictationPhase !== 'idle';
  const isRecording = dictationPhase === 'recording';
  // A recording the user does not hold, as one started from the keyboard, runs hands-free
  const isHolding = isRecording && hold === 'holding';
  const transcriptCount = dictation?.transcriptCount ?? 0;
  const failureCount = dictation?.failureCount ?? 0;
  const ownInputRef = useRef<HTMLTextAreaElement>();
  const wrapperRef = useRef<HTMLDivElement>();
  const inputRef = externalInputRef || ownInputRef;
  const savedScrollRef = useRef({ top: 0, isCaretAtEnd: true });

  // Save scroll state and caret position before re-render triggers Input's resize
  const handleInput = useLastCallback((value: string) => {
    const el = inputRef.current;
    if (el) {
      savedScrollRef.current = {
        top: el.scrollTop,
        isCaretAtEnd: el.selectionEnd === el.value.length,
      };
    }
    onInput(value);
  });

  // After Input's resize resets `scrollTop` to 0, restore scroll position
  useEffect(() => {
    const el = inputRef.current;
    if (!el || el.scrollHeight <= el.clientHeight) return;

    const { top, isCaretAtEnd } = savedScrollRef.current;
    if (isCaretAtEnd) {
      el.scrollTop = el.scrollHeight;
    } else {
      el.scrollTop = Math.min(top, el.scrollHeight - el.clientHeight);
    }
  }, [inputRef, inputValue]);

  useLayoutEffect(() => {
    const element = wrapperRef.current;
    if (!element || !onHeightChange) return undefined;

    const notifyHeightChange = () => {
      requestMeasure(() => {
        if (element.isConnected) {
          onHeightChange(element.offsetHeight);
        }
      });
    };
    const observer = new ResizeObserver(notifyHeightChange);
    observer.observe(element);
    notifyHeightChange();

    return () => observer.disconnect();
  }, [onHeightChange]);

  // While an answer is being produced, Stop stands in the microphone's place; a draft has its send button, which queues
  // the question behind the answer. A recording that is under way keeps its controls until it ends.
  const isStopShown = Boolean(onStop) && canStop && !isDictating;
  // The send button waits in the field, dimmed, on a phone; elsewhere, and where the microphone or Stop stands for it
  // while the draft is empty, it comes with the draft
  const isSendButtonOpen = !isDictating && (Boolean(inputValue) || (!isStopShown && !dictation && isPortrait));
  const canSend = Boolean(inputValue) && !isDisabled;

  const isCircleOpen = Boolean(dictation) && (isRecording || Boolean(circleFailure));
  const { shouldRender: shouldRenderCircle } = useShowTransition({
    isOpen: isCircleOpen,
    withShouldRender: true,
    closeDuration: CIRCLE_CLOSE_DURATION_MS,
    className: false,
  });
  const circleMode: AgentDictationCircleMode = circleFailure ? 'failed' : isHolding ? 'holding' : 'locked';
  const renderedCircleMode = useCurrentOrPrev(isCircleOpen ? circleMode : undefined, true) ?? circleMode;
  // A recording that ends shrinks its circle away first, and the microphone comes back after it. A failure shows
  // over the microphone, which stays.
  const isCircleLeaving = shouldRenderCircle && !isCircleOpen && renderedCircleMode !== 'failed';
  // The finish button stays hidden under the circle of a held recording until the circle has gone, and after the
  // recording locks until the circle is back over it
  const [isCircleOverAction, setIsCircleOverAction] = useState(true);
  const lastHold = useCurrentOrPrev(isRecording ? hold : undefined, true);
  const isDictationActionUnderCircle = isRecording
    ? isHolding || !isCircleOverAction
    : lastHold === 'holding';

  // The microphone turns into Stop in its own place, and back once the answer ends. The button keeps Stop's face while
  // a draft closes it, so the draft trades Stop for its send button and back directly, without the microphone.
  const isMicrophoneSlotFree = !inputValue && !isDictating && !isCircleLeaving;
  const isStopButtonOpen = isStopShown && isMicrophoneSlotFree;
  const isMicrophoneButtonOpen = Boolean(dictation) && !isStopShown && isMicrophoneSlotFree;
  const isMicrophoneSlotOpen = isMicrophoneButtonOpen || isStopButtonOpen;
  // While the agent recognizes the phrase, the microphone's place goes to the field, as on mobile
  const isDictationActionOpen = isRecording;
  // The field glows while it recognizes, and until the transcript has come in, as on iOS; never while the user records
  const isGlowing = dictationPhase === 'recognizing' || Boolean(transcriptReveal);
  const { ref: sendButtonRef } = useShowTransition<HTMLButtonElement>({
    isOpen: isSendButtonOpen,
    noMountTransition: true,
    className: false,
  });
  const { ref: microphoneButtonRef } = useShowTransition<HTMLButtonElement>({
    isOpen: isMicrophoneSlotOpen,
    noMountTransition: true,
    className: false,
  });
  const { ref: dictationActionTransitionRef } = useShowTransition<HTMLButtonElement>({
    isOpen: isDictationActionOpen,
    ref: dictationActionRef,
    noMountTransition: true,
    className: false,
  });

  // A hands-free recording gives the focus to its finish button, so Enter finishes it and Escape cancels it;
  // recognition gives it to its Cancel
  useEffect(() => {
    if (isRecording && !isHolding) dictationActionRef.current?.focus();
    else if (dictationPhase === 'recognizing') dictationCancelRef.current?.focus();
  }, [dictationPhase, isHolding, isRecording]);

  useLayoutEffect(() => {
    if (dictationPhase === 'recognizing') recognitionStartedAtRef.current = Date.now();
    if (!isRecording) {
      setHold('none');
      updateDrag(NO_DRAG);
      setIsCircleOverAction(true);
    }
  }, [dictationPhase, isRecording]);

  // The circle comes up over the microphone's place. The finish button stays in it while the microphone slides in
  // and out, and its scale keeps its middle where it is.
  const measureCircleAnchor = useLastCallback(() => {
    requestMeasure(() => {
      const button = dictationActionRef.current;
      if (!button?.offsetWidth) return;
      const rect = button.getBoundingClientRect();
      setCircleAnchor({ x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 });
    });
  });

  // A recording started from outside the bar, as once the user allows the Agent, runs hands-free
  useEffect(() => {
    if (!isRecording || hold !== 'none') return;
    measureCircleAnchor();
    setHold('locked');
  }, [hold, isRecording, measureCircleAnchor]);

  const isCircleShownRef = useRef(false);
  isCircleShownRef.current = shouldRenderCircle;
  // The scroll-to-latest button gives way to the circle, as on mobile
  useToggleClass({ className: 'is-agent-dictation-circle-shown', isActive: shouldRenderCircle });

  // The hint rises and shrinks away as the recording goes hands-free, while Cancel comes up in its place.
  // The hint's opacity follows the finger frame by frame, so it has no opacity transition of its own.
  const { ref: slideHintRef, shouldRender: shouldRenderSlideHint } = useShowTransition<HTMLSpanElement>({
    isOpen: isHolding,
    withShouldRender: true,
    noMountTransition: true,
    closeDuration: SLIDE_HINT_CLOSE_DURATION_MS,
    className: false,
  });

  // The hint follows the finger toward cancelling and fades on the way, written straight to its style once a frame.
  // It is gone by the time it reaches the timer, as on mobile, however little room the field leaves it. The room is
  // measured as the finger slides, as the field may still be widening into the microphone's place.
  const updateSlideHint = useThrottledCallback(() => {
    const hint = slideHintRef.current;
    if (!hint) return;

    const { x } = dragRef.current;
    const timer = dictationTimerRef.current;
    let fadeDistance = HINT_FADE_DISTANCE;
    if (x && timer) {
      const room = lang.isRtl
        ? timer.offsetLeft - (hint.offsetLeft + hint.offsetWidth)
        : hint.offsetLeft - (timer.offsetLeft + timer.offsetWidth);
      fadeDistance = Math.max(1, Math.min(HINT_FADE_DISTANCE, room));
    }

    requestMutation(() => {
      setExtraStyles(hint, x
        ? { transform: `translateX(${x}px)`, opacity: String(Math.max(0, 1 - Math.abs(x) / fadeDistance)) }
        : { transform: '', opacity: '' });
    });
  }, [lang.isRtl, slideHintRef], requestMeasure);

  const updateDrag = useLastCallback((nextDrag: { x: number; y: number }) => {
    dragRef.current = nextDrag;
    updateSlideHint();
  });

  const getCircleDrag = useLastCallback(() => (isHolding ? dragRef.current : NO_DRAG));

  // A dictation that ends without text turns the circle red for a moment, popping it out of the microphone when it
  // was not up
  useEffect(() => {
    if (!failureCount) return undefined;
    measureCircleAnchor();
    setCircleFailure({ isFailureOnly: !isCircleShownRef.current });
    const timer = window.setTimeout(() => setCircleFailure(undefined), FAILURE_DURATION_MS);
    return () => window.clearTimeout(timer);
  }, [failureCount, measureCircleAnchor]);

  // The transcript's words are drawn over the field's own text, which they match letter for letter, so each can
  // come in blurred and in the accent and settle
  const revealRef = useRef<HTMLDivElement>();
  const revealTextRef = useRef<HTMLDivElement>();
  useLayoutEffect(() => {
    if (!transcriptReveal) return;
    requestMeasure(() => {
      const input = inputRef.current;
      const reveal = revealRef.current;
      const text = revealTextRef.current;
      const pill = reveal?.parentElement;
      if (!input || !reveal || !text || !pill) return;

      const style = getComputedStyle(input);
      const inputRect = input.getBoundingClientRect();
      const pillRect = pill.getBoundingClientRect();
      const scrollTop = input.scrollTop;
      requestMutation(() => {
        setExtraStyles(reveal, {
          top: `${inputRect.top - pillRect.top + input.clientTop}px`,
          left: `${inputRect.left - pillRect.left + input.clientLeft}px`,
          width: `${input.clientWidth}px`,
          height: `${input.clientHeight}px`,
          paddingTop: style.paddingTop,
          paddingRight: style.paddingRight,
          paddingBottom: style.paddingBottom,
          paddingLeft: style.paddingLeft,
          fontFamily: style.fontFamily,
          fontSize: style.fontSize,
          fontWeight: style.fontWeight,
          lineHeight: style.lineHeight,
          letterSpacing: style.letterSpacing,
          visibility: 'visible',
        });
        setExtraStyles(text, { transform: scrollTop ? `translateY(${-scrollTop}px)` : '' });
      });
    });
  }, [inputRef, inputValue, transcriptReveal]);

  // The transcript reaches the draft before the count changes, so the caret can move to its end here
  useEffect(() => {
    if (!transcriptCount) return undefined;
    const element = inputRef.current;
    if (element) {
      element.focus();
      element.setSelectionRange(element.value.length, element.value.length);
    }
    setIsHighlighted(true);
    const timer = window.setTimeout(() => setIsHighlighted(false), DICTATION_HIGHLIGHT_MS);
    return () => window.clearTimeout(timer);
  }, [inputRef, transcriptCount]);

  const handleDictationAction = useLastCallback(() => {
    if (dictationPhase === 'recognizing'
      && Date.now() - recognitionStartedAtRef.current < DICTATION_ACTION_DELAY_MS) return;

    if (isRecording) dictation!.finish();
    else dictation!.cancelRecognition();
  });

  const handleDictationCancel = useLastCallback(() => {
    if (dictationPhase === 'recognizing') {
      handleDictationAction();
      return;
    }
    dictation!.cancel();
    // A touch screen keeps its keyboard down: the user cancelled the recording rather than started typing
    if (!IS_TOUCH_ENV) inputRef.current?.focus();
  });

  const handleDictationEscape = useLastCallback(() => {
    if (isRecording) handleDictationCancel();
    else dictation!.cancelRecognition();
  });

  useEffect(() => (isDictating ? captureEscKeyListener(handleDictationEscape) : undefined), [isDictating]);

  const startHandsFree = useLastCallback(() => {
    if (!dictation || !isMicrophoneButtonOpen) return;
    if (isDictationHeld) {
      onHeldDictation?.();
      return;
    }
    measureCircleAnchor();
    setHold('locked');
    dictation.start();
  });

  // Stop takes any click. On the microphone, a keyboard press starts a hands-free recording; a pointer goes through
  // the press below.
  const handleMicrophoneClick = useLastCallback((e: React.MouseEvent<HTMLButtonElement>) => {
    if (isStopButtonOpen) {
      onStop();
      return;
    }
    if (e.detail === 0) startHandsFree();
  });

  const endPress = useLastCallback(() => {
    const press = pressRef.current;
    if (!press) return;
    pressRef.current = undefined;
    window.clearTimeout(press.timer);
    window.removeEventListener('pointermove', press.listeners.move);
    window.removeEventListener('pointerup', press.listeners.end);
    window.removeEventListener('pointercancel', press.listeners.cancel);
    window.removeEventListener('blur', press.listeners.blur);
  });

  useEffect(() => endPress, [endPress]);

  const lockRecording = useLastCallback(() => {
    endPress();
    setHold('locked');
    updateDrag(NO_DRAG);
    dictationActionRef.current?.focus();
  });

  const cancelRecording = useLastCallback(() => {
    endPress();
    dictation!.cancel();
  });

  const finishRecording = useLastCallback(() => {
    endPress();
    dictation!.finish();
  });

  // Holding the microphone records: sliding toward the start cancels, sliding up records hands-free, letting go
  // finishes. A tap records hands-free.
  const handleMicrophonePointerDown = useLastCallback((e: React.PointerEvent<HTMLButtonElement>) => {
    if (!dictation || !isMicrophoneButtonOpen || e.button !== 0 || !e.isPrimary || pressRef.current) return;
    e.preventDefault();
    if (isDictationHeld) {
      onHeldDictation?.();
      return;
    }

    const press: MicrophonePress = {
      pointerId: e.pointerId,
      startX: e.clientX,
      startY: e.clientY,
      lastX: e.clientX,
      lastY: e.clientY,
      lastAt: Date.now(),
      velocityX: 0,
      velocityY: 0,
      isHolding: false,
      timer: window.setTimeout(() => {
        press.isHolding = true;
        measureCircleAnchor();
        setHold('holding');
        updateDrag(NO_DRAG);
        dictation.start();
      }, HOLD_DELAY_MS),
      listeners: {
        move: handlePressMove, end: handlePressEnd, cancel: handlePressCancel, blur: abortPress,
      },
    };
    pressRef.current = press;
    window.addEventListener('pointermove', press.listeners.move);
    window.addEventListener('pointerup', press.listeners.end);
    window.addEventListener('pointercancel', press.listeners.cancel);
    window.addEventListener('blur', press.listeners.blur);
  });

  function getPressTravel(press: MicrophonePress, x: number, y: number) {
    const cancelSign = lang.isRtl ? 1 : -1;
    return {
      cancelSign,
      towardCancel: Math.max(0, (x - press.startX) * cancelSign),
      towardLock: Math.max(0, press.startY - y),
    };
  }

  function handlePressMove(e: PointerEvent) {
    const press = pressRef.current;
    if (press?.pointerId !== e.pointerId) return;

    const now = Date.now();
    const seconds = Math.max(1, now - press.lastAt) / 1000;
    press.velocityX = VELOCITY_SMOOTHING * press.velocityX
      + (1 - VELOCITY_SMOOTHING) * ((e.clientX - press.lastX) / seconds);
    press.velocityY = VELOCITY_SMOOTHING * press.velocityY
      + (1 - VELOCITY_SMOOTHING) * ((e.clientY - press.lastY) / seconds);
    press.lastX = e.clientX;
    press.lastY = e.clientY;
    press.lastAt = now;
    if (!press.isHolding) return;

    const { cancelSign, towardCancel, towardLock } = getPressTravel(press, e.clientX, e.clientY);
    if (towardCancel >= CANCEL_DISTANCE) {
      cancelRecording();
      return;
    }
    if (towardLock >= LOCK_DISTANCE) {
      lockRecording();
      return;
    }
    updateDrag({ x: towardCancel * cancelSign, y: -towardLock });
  }

  // Only the main direction counts when the finger lets go
  function handlePressEnd(e: PointerEvent) {
    const press = pressRef.current;
    if (press?.pointerId !== e.pointerId) return;
    if (!press.isHolding) {
      endPress();
      startHandsFree();
      return;
    }

    const { cancelSign, towardCancel, towardLock } = getPressTravel(press, e.clientX, e.clientY);
    if (towardCancel >= towardLock) {
      if (press.velocityX * cancelSign > RELEASE_VELOCITY || towardCancel > CANCEL_RELEASE_DISTANCE) {
        cancelRecording();
      } else {
        finishRecording();
      }
      return;
    }
    if (-press.velocityY > RELEASE_VELOCITY || towardLock > LOCK_RELEASE_DISTANCE) lockRecording();
    else finishRecording();
  }

  function handlePressCancel(e: PointerEvent) {
    if (pressRef.current?.pointerId === e.pointerId) abortPress();
  }

  // A window that loses the focus, as to a system prompt, may never get the release, so the press ends at once
  function abortPress() {
    if (pressRef.current?.isHolding) cancelRecording();
    else endPress();
  }

  const handleMicrophoneContextMenu = useLastCallback((e: React.MouseEvent) => {
    e.preventDefault();
  });

  function renderDictation() {
    if (!dictation || !isDictating) return undefined;
    if (dictationPhase === 'recognizing') {
      return (
        <div className={buildClassName(styles.dictation, styles.dictationRecognizing)}>
          <span className={styles.dictationRecognizingText} role="status">
            {lang('$agent_dictation_recognizing')}
          </span>
          {renderDictationCancel(true)}
        </div>
      );
    }

    const remainingMs = Math.max(0, DICTATION_MAX_DURATION_MS - dictation.elapsedMs);
    const isEnding = remainingMs <= DICTATION_ENDING_MS;
    return (
      <div className={styles.dictation}>
        <span className="visually-hidden" role="status">
          {isEnding ? lang('$agent_dictation_time_left', DICTATION_ENDING_MS / 1000) : ''}
        </span>
        <span
          className={buildClassName(styles.recordingDot, dictation.isPaused && styles.recordingDotPaused)}
          aria-hidden
        />
        <span
          ref={dictationTimerRef}
          className={buildClassName(styles.dictationTimer, isEnding && styles.dictationEnding)}
        >
          {formatDictationTime(dictation.elapsedMs)}
        </span>
        <span className={styles.dictationHintSlot}>
          {isEnding ? (
            <span className={buildClassName(styles.dictationHint, styles.dictationEnding)}>
              {lang('$agent_dictation_time_left', Math.ceil(remainingMs / 1000))}
            </span>
          ) : (
            <>
              {shouldRenderSlideHint && (
                <span ref={slideHintRef} className={styles.dictationSlideHint} aria-hidden>
                  {lang.isRtl ? '\u2066\u203A\u2069 ' : '\u2039 '}
                  {lang('$agent_dictation_slide_to_cancel')}
                </span>
              )}
              {!isHolding && renderDictationCancel(false)}
            </>
          )}
        </span>
        {isEnding && !isHolding && renderDictationCancel(true)}
      </div>
    );
  }

  // The draft before the transcript stays as it is. Each of the transcript's characters comes in as it reaches the
  // draft, or the whole transcript fades in where motion is reduced.
  function renderTranscriptReveal({ start, isReduced }: AgentTranscriptReveal) {
    const transcript = inputValue.slice(start);

    return (
      <div ref={revealRef} className={styles.transcriptReveal} aria-hidden>
        <div ref={revealTextRef}>
          {inputValue.slice(0, start)}
          {isReduced ? (
            <span className={styles.transcriptFade}>{transcript}</span>
          ) : segmentGraphemes(transcript).map((character, index) => (
            <span key={index} className={styles.transcriptCharacter}>{character}</span>
          ))}
        </div>
      </div>
    );
  }

  // Cancel stands in the middle of the free space, or at the end beside a countdown or the recognition
  function renderDictationCancel(isAtEnd: boolean) {
    const cancelText = lang('Cancel');

    return (
      <button
        ref={dictationCancelRef}
        type="button"
        className={buildClassName(styles.dictationCancel, isAtEnd && styles.dictationCancelAtEnd)}
        aria-label={cancelText}
        onClick={handleDictationCancel}
      >
        {cancelText}
      </button>
    );
  }

  return (
    <div ref={wrapperRef} className={styles.wrapper}>
      {dictationNotice !== undefined && (
        <div className={styles.statusSlot}>
          {dictationNotice}
        </div>
      )}
      {dictationAnnouncement}
      <div className={buildClassName(styles.inputRow, isDimmed && styles.inputRowDimmed)} data-agent-composer>
        <div
          className={buildClassName(
            styles.pill,
            isDictating && styles.pillDictating,
            isHighlighted && styles.pillHighlighted,
          )}
        >
          <AgentFieldGlow isActive={isGlowing} />
          <Input
            ref={inputRef}
            isMultiline
            value={inputValue}
            placeholder={placeholder ?? lang('Ask anything')}
            className={buildClassName(
              styles.input,
              isSendButtonOpen && styles.inputWithSend,
              transcriptReveal && styles.inputRevealing,
            )}
            wrapperClassName={styles.inputInnerWrapper}
            onInput={handleInput}
            onKeyDown={onKeyDown}
            onFocus={onFocus}
          />
          {transcriptReveal && renderTranscriptReveal(transcriptReveal)}
          {renderDictation()}
          <button
            ref={sendButtonRef}
            type="submit"
            className={buildClassName(styles.pillSendButton, canSend && styles.pillSendButtonActive)}
            aria-label={lang('Send')}
            aria-hidden={!isSendButtonOpen}
            disabled={!canSend || !isSendButtonOpen}
            onClick={onSend}
          >
            <AgentIcon name="send" className={styles.sendIcon} />
          </button>
        </div>
        {(dictation || onStop) && (
          <button
            ref={microphoneButtonRef}
            type="button"
            // A finger that holds the microphone records rather than swipes the chat away
            className={buildClassName(
              styles.sendButton,
              styles.microphoneButton,
              isStopShown && styles.stopButton,
              SWIPE_DISABLED_CLASS_NAME,
            )}
            aria-label={lang(isStopShown || !dictation ? '$agent_stop_answer' : '$agent_dictation_start')}
            title={isStopShown ? lang('$agent_stop_answer') : undefined}
            aria-hidden={!isMicrophoneSlotOpen}
            // The button that is still pressed stays enabled, since some browsers do not deliver the pointer events of
            // a disabled button and the press would never end
            disabled={!isMicrophoneSlotOpen && !pressRef.current}
            onPointerDown={handleMicrophonePointerDown}
            onContextMenu={handleMicrophoneContextMenu}
            onClick={handleMicrophoneClick}
          >
            {dictation && <AgentIcon name="microphone" className={styles.microphoneIcon} />}
            <span className={styles.stopIcon} aria-hidden />
          </button>
        )}
        {dictation && (
          <button
            ref={dictationActionTransitionRef}
            type="button"
            // Under the circle while the finger holds the recording, as the microphone's own circle on mobile
            className={buildClassName(styles.sendButton, isDictationActionUnderCircle && styles.dictationActionHidden)}
            aria-label={lang('$agent_dictation_finish')}
            aria-hidden={!isDictationActionOpen}
            disabled={!isDictationActionOpen}
            onClick={handleDictationAction}
          >
            <i className="icon-check" aria-hidden />
          </button>
        )}
      </div>
      {shouldRenderCircle && circleAnchor && (
        <Portal>
          <AgentDictationCircle
            anchor={circleAnchor}
            mode={renderedCircleMode}
            isFailureOnly={circleFailure?.isFailureOnly}
            isClosing={!isCircleOpen}
            level={dictation!.level}
            getDrag={getCircleDrag}
            onFinish={handleDictationAction}
            isPaused={dictation!.isPaused}
            onPause={dictation!.pause}
            onResume={dictation!.resume}
            onCoverChange={setIsCircleOverAction}
          />
        </Portal>
      )}
    </div>
  );
}

// Minutes, seconds and hundredths, as Telegram's recording timer: "0:07,42"
function formatDictationTime(elapsedMs: number) {
  const hundredths = Math.floor(elapsedMs / 10);
  const seconds = Math.floor(hundredths / 100);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')},`
    + `${String(hundredths % 100).padStart(2, '0')}`;
}

export default memo(AgentInputBar);

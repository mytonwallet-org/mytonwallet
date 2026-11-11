import type { TeactNode } from '../../lib/teact/teact';
import React, {
  memo, useEffect, useLayoutEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { addExtraClass, removeExtraClass, setExtraStyles } from '../../lib/teact/teact-dom';
import { getGlobal } from '../../global';

import type { AgentHint, AgentMessage, AnimationLevel } from '../../global/types';
import type { FollowupSource } from '../agentV2/agentFollowupMorph';
import type { AgentHintsFrame } from './AgentHints';
import type { AgentMessagesSkeletonLayout } from './AgentMessagesSkeleton';
import type { MotionRect } from './helpers/agentMotion';
import type { SentTextPicture } from './helpers/sentQuestionFlight';
import type { SnapEffectKind } from './helpers/snapEffect';
import type { TextRevealPresentation, TextRevealPresentations } from './hooks/textRevealPresentation';
import { LoadMoreDirection } from '../../global/types';

import { requestForcedReflow, requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import animateScroll, {
  cancelScrollAnimation,
  easeInOutTransition,
  isAnimatingScroll,
  restartScrollAnimation,
  trackWheelInertia,
} from '../../util/animateScroll';
import { animate } from '../../util/animation';
import buildClassName from '../../util/buildClassName';
import { processDeeplink } from '../../util/deeplink';
import { SELF_PROTOCOL } from '../../util/deeplink/constants';
import { stopEvent } from '../../util/domEvents';
import { animateShift } from '../../util/layoutChangeAnimation';
import { openUrl } from '../../util/openUrl';
import { IS_TOUCH_ENV } from '../../util/windowEnvironment';
import { getSecretPhraseWordList, hasSecretPhrase } from '../../api/agentV2/secretPhrase';
import {
  captureFollowupSource,
  FOLLOWUP_MORPH_DURATION,
  measureFollowupMorph,
  rippleFollowupsAway,
} from '../agentV2/agentFollowupMorph';
import { getTelegramProgress, interpolateRect } from './helpers/agentMotion';
import buildMessageIds, { DATE_ITEM_ID_PREFIX, UNREAD_ITEM_ID_PREFIX } from './helpers/buildMessageIds';
import buildMessageTurnIds from './helpers/buildMessageTurnIds';
import { getReturnKeyAction, insertLineBreak } from './helpers/composerReturnKey';
import { planHistoryReveal } from './helpers/historyReveal';
import {
  createSentTextPicture,
  measureSentQuestionFlight,
  removeSentTextPicture,
  SENT_QUESTION_FLIGHT_DURATION,
} from './helpers/sentQuestionFlight';
import {
  createSnapGhost, getSnapEffectKind, getSnapEffectLayer, getSnapGapCloseDelay,
} from './helpers/snapEffect';

import useDerivedState from '../../hooks/useDerivedState';
import useFlag from '../../hooks/useFlag';
import useHistoryBack from '../../hooks/useHistoryBack';
import { useHotkeys } from '../../hooks/useHotkeys';
import useInfiniteScroll from '../../hooks/useInfiniteScroll';
import useLastCallback from '../../hooks/useLastCallback';
import usePrevious2 from '../../hooks/usePrevious2';
import useScrolledState from '../../hooks/useScrolledState';
import useSignal from '../../hooks/useSignal';
import { useStateRef } from '../../hooks/useStateRef';
import useAgentLayoutSwitch from './hooks/useAgentLayoutSwitch';
import useScrollResetOnResize from './hooks/useScrollResetOnResize';
import useScrollToBottomOnReveal from './hooks/useScrollToBottomOnReveal';
import useShouldAnimateText from './hooks/useShouldAnimateText';

import { AgentFailureCaption } from '../agentV2/AgentStatusNotice';
import InfiniteScroll from '../ui/InfiniteScroll';
import { getIsAnyModalOpen } from '../ui/Modal';
import Spinner from '../ui/Spinner';
import AgentDateLine from './AgentDateLine';
import AgentEdgeGlow from './AgentEdgeGlow';
import AgentHeader from './AgentHeader';
import AgentHints from './AgentHints';
import AgentInputBar from './AgentInputBar';
import AgentLoadFailure from './AgentLoadFailure';
import AgentMessagesSkeleton, { PLACEHOLDER_MORPH_DURATION } from './AgentMessagesSkeleton';
import AgentUnreadDivider from './AgentUnreadDivider';
import { MESSAGE_LIST_ITEM_SELECTOR } from './MessageBubble';
import ReportAgentProblemModal from './ReportAgentProblemModal';
import ScrollToBottomButton from './ScrollToBottomButton';

import styles from './Agent.module.scss';
import bubbleStyles from './MessageBubble.module.scss';

const PRELOAD_BACKWARD_SLICE = 30;
const CONTINUOUS_HISTORY_MAX_VIEWPORT_SIZE = 60;
const SCROLL_FLICKER_THRESHOLD = 10;
// The scroll-to-latest button shows once the latest message ends this far below the visible bottom, as on mobile
const SCROLL_BOTTOM_THRESHOLD = 60;
const LIVE_TAIL_REQUEST_TIMEOUT = 1000;
// A day's line stuck at the top fades away once the news feed has rested this long, as in Telegram Web A
const STUCK_DATE_LINE_HIDE_DELAY = 1000;
// Subpixel layout can leave a stuck line a fraction of a pixel off its sticky inset
const STUCK_DATE_LINE_TOLERANCE = 1;
const QUESTION_FLY_UP_DURATION = 300;
// Android's sent question grows into place on a spring that settles in about 0.3 s
const QUESTION_IN_PLACE_DURATION = 300;
const QUESTION_IN_PLACE_SCALE = 0.8;
// A question that has appeared where it lands stays there this long before the list takes it up, as iOS's
// `sentUserMessagePinDelay` and Android's `INCOMING_MESSAGE_DELAY_MS`
const QUESTION_IN_PLACE_SCROLL_DELAY = 250;
const DISSOLVE_GAP_CLOSE_DURATION = 400;
// The field grows with its text until it comes this short of the header, as on iOS and Android, as in Telegram
const INPUT_HEADER_CLEARANCE = 120;
// It can always grow as tall as this, as on iOS and Android
const INPUT_MIN_MAX_HEIGHT = 132;
const HISTORY_MORPH_EASING = 'cubic-bezier(0.38, 0.7, 0.125, 1)';
// iOS's `AgentSkeletonReveal` changes the fill and fades the contents with the system's ease-in-out
const HISTORY_FADE_EASING = 'ease-in-out';
const HISTORY_FADE_DURATION = 220;
// Content inside a bubble starts to fade in this long after its bubble starts to grow
const HISTORY_BUBBLE_CONTENT_FADE_DELAY = 140;
// The frames the grown stand-ins hold their bubbles' rectangles for before the bubbles take over
const HISTORY_HANDOVER_FRAMES = 3;
const MESSAGE_ELEMENT_SELECTOR = '[data-agent-v2-message-id]';
const SKELETON_SELECTOR = '[data-agent-skeleton]';
const PLACEHOLDER_SELECTOR = '[data-agent-skeleton-role]';
const MESSAGE_ROLE_SELECTOR = '[data-agent-v2-message-role]';
const FOLLOWUP_BUTTON_SELECTOR = '[data-agent-followup-id]';
const FOLLOWUP_ROW_SELECTOR = '[data-agent-followup-row]';
const QUESTION_TEXT_SELECTOR = '[data-agent-question-text]';
const HINTS_SELECTOR = '[data-agent-hints]';
const HEADER_SELECTOR = '[data-agent-header]';
const NO_COMPOSER: Partial<AgentConversationComposer> = {};
// The lines that come before a message: its date and the "New" line
const MARKER_SELECTOR = `.${styles.dateLine}, .${styles.unreadDivider}`;

export interface AgentConversationMessageContext {
  shouldAnimateTextStreaming: boolean;
  textRevealPresentation?: TextRevealPresentation;
  isJustAdded: boolean;
  onEditMessage: (id: number, text: string) => void;
  onReportMessage?: (id: number) => void;
  onTextRevealProgress: NoneToVoidFunction;
  /**
   * A question sent from a follow-up under an answer shows in place first, where the follow-up with `followupId`
   * turns into it, and then goes up with the list
   */
  onRequestLiveTail: (followupId?: string) => void;
}

export interface AgentConversationComposerProps {
  inputRef: React.RefObject<HTMLTextAreaElement | undefined>;
  inputValue: string;
  isDisabled: boolean;
  /** The stop button stands in place of send and the microphone while an answer is being produced */
  canStop?: boolean;
  onStop?: NoneToVoidFunction;
  onInput: (value: string) => void;
  onKeyDown: (event: React.KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
  onSend: NoneToVoidFunction;
  onHeightChange?: (height: number) => void;
  /**
   * Before consent, sending and dictating ask for it first, and go on once the user allows the Agent. A send from the
   * field gets the field's focus back if the user closes the sheet.
   */
  onRequestConsent?: (action: NoneToVoidFunction, field?: HTMLElement) => void;
}

export interface AgentConversationComposerHeightContext {
  messagesElement: HTMLDivElement;
  getIsAtBottom: () => boolean;
  onTextRevealProgress: NoneToVoidFunction;
}

/** A load of the chat's history, or of the news, that failed */
interface AgentConversationLoadFailure {
  text: string;
  isRetrying?: boolean;
  onRetry: NoneToVoidFunction;
}

export interface AgentConversation {
  messages: AgentMessage[];
  hints?: AgentHint[];
  isInitialLoadComplete: boolean;
  /**
   * The chat opens with the question it was started with, which stands under the header with its answer below it, as
   * after a send. It is read as the chat mounts.
   */
  hasOpeningQuestion?: boolean;
  /** Shows the outlines of bubbles until the history loads, for a chat that has a history to load */
  hasHistoryPlaceholder?: boolean;
  /** The placeholder shows the outlines of news cards in place of a chat's bubbles */
  isNewsPlaceholder?: boolean;
  /** What the chat holds as far as its list row tells, which the placeholder's rows follow */
  historyPlaceholderLayout?: AgentMessagesSkeletonLayout;
  /**
   * A date line comes before the first message of each day rather than after a pause. It names the day alone, and stays
   * at the top over the day's messages as they scroll under it.
   */
  hasDailyDateLines?: boolean;
  /**
   * The first message the user has not seen. A "New" line comes before it, and the list opens at it, under the header
   * with the lines before it, rather than at its end.
   */
  unreadMessageId?: number;
  /**
   * The failure shows centered with Retry in place of a list that has nothing to show, and as the failure line with
   * Retry at the end of the messages already shown
   */
  loadFailure?: AgentConversationLoadFailure;
  /** Shows centered, without Retry, in place of a list that loaded without messages and without a failure */
  emptyText?: string;
  /** An answer is being produced, including the time before its first text arrives */
  isRunActive?: boolean;
  textRevealPresentations: TextRevealPresentations;
  /**
   * Messages that the next `messages` no longer has. The list shows them once more, turns them to dust where they
   * stand, as Telegram does with deleted messages, and calls `onDissolveStart` for the next `messages`. The space they
   * leave closes as they go.
   */
  dissolvingMessageIds?: readonly number[];
  /**
   * The list footer turns to dust in the same way, as a failure under a question that Retry takes away. Its root
   * carries `data-agent-list-footer`, and `onDissolveStart` hands over the next footer.
   */
  isFooterDissolving?: boolean;
  onDissolveStart?: NoneToVoidFunction;
  renderMessage: (message: AgentMessage, context: AgentConversationMessageContext) => TeactNode;
}

export interface AgentConversationComposer {
  isDisabled: boolean;
  shouldHide?: boolean;
  canStop?: boolean;
  onStop?: NoneToVoidFunction;
  onSendMessage: (text: string, editingMessageId?: number) => void;
  onSendHint: (hint: AgentHint) => void;
  onHeightChange?: (height: number, context: AgentConversationComposerHeightContext) => void;
  /** Present until the user allows the Agent; the composer is drawn again as it comes and goes */
  onRequestConsent?: AgentConversationComposerProps['onRequestConsent'];
  render?: (props: AgentConversationComposerProps) => TeactNode;
}

export interface AgentConversationHistory {
  hasOlderMessages: boolean;
  isLoading: boolean;
  /** Older messages come in as they load, with no spinner under the header while they do, as the news feed's posts */
  noLoadingIndicator?: boolean;
  mode: 'continuous' | 'windowed';
  loadOlderMessages: () => void | Promise<void>;
  /**
   * Older messages load as the list scrolls up with at most this many rows, date lines and the "New" line among them,
   * wholly above the part of it under the header, as Android counts them, rather than within a distance of its top
   */
  thresholdRowCount?: number;
}

export interface AgentConversationSlots {
  body?: TeactNode;
  messageListFooter?: TeactNode;
  beforeComposer?: TeactNode;
  bottomStickDependency?: unknown;
}

export type AgentProblemReportOutcome = 'sent' | 'rateLimited' | 'failed';

/** What the header shows for a chat among several; a single chat keeps the plain "Agent" header */
export interface AgentConversationHeader {
  title?: string;
  icon?: string;
  /** A line under the name, which tells that support has the chat */
  subtitle?: string;
  /** Shows the threads button, which calls `onBack` */
  hasBackButton?: boolean;
  /** Shows the chat menu, whose items are Report a Problem and Delete Chat once they are offered */
  hasMenu?: boolean;
}

export interface AgentConversationActions {
  onBack: NoneToVoidFunction;
  /** Offers Delete Chat in the chat menu */
  onDelete?: NoneToVoidFunction;
  /** Reports the conversation, or the message when `messageId` is given. Without it nothing offers a report. */
  onReportProblem?: (messageId: number | undefined, comment: string) => Promise<AgentProblemReportOutcome>;
  onScroll?: (event: React.UIEvent<HTMLDivElement>) => void;
  onMessageVisible?: (id: number) => void;
  /** Shows the bell at the header's end, as the news feed does, which opens the daily digest's settings */
  onOpenDigestSettings?: NoneToVoidFunction;
}

/**
 * What the chat keeps for its next mount, as when the app switches layouts. Message positions are counted from the end
 * because a mount numbers chat messages afresh. The news feed also keeps each message's stable news id.
 */
export interface AgentConversationSession {
  draft: string;
  /** The question being edited, with its text, which tells it is still the same question */
  editedMessage?: { indexFromEnd: number; text: string };
  isInputFocused?: boolean;
  /** The last question is pinned under the header with its answer below it, as after a send */
  isQuestionPinned?: boolean;
  /**
   * The message at the top of the list and where it starts below the list's top; without it the list is at its end.
   * `messageId` is stored only for the news feed, whose news ids stay the same across mounts.
   */
  scrollAnchor?: { messageId?: number; indexFromEnd: number; offset: number };
  /**
   * The list had been placed, so it opens where it was, at `scrollAnchor` or at its end, rather than at the message it
   * is given or its first unread one
   */
  isPlaced?: boolean;
}

export interface AgentConversationSessionStore {
  /** What the chat kept when it was on screen last */
  initial?: AgentConversationSession;
  save: (session: AgentConversationSession) => void;
  /** The news feed keeps its place off screen and saves the anchor's stable news id for its next mount */
  shouldKeepPlaceOffScreen?: boolean;
}

export interface AgentConversationShellProps {
  isActive: boolean;
  animationLevel: AnimationLevel;
  conversation: AgentConversation;
  /**
   * Without it the chat has no input field, as in the news feed. The messages then keep the same gap at the bottom
   * that they keep above a field.
   */
  composer?: AgentConversationComposer;
  history?: AgentConversationHistory;
  slots?: AgentConversationSlots;
  header?: AgentConversationHeader;
  actions: AgentConversationActions;
  session?: AgentConversationSessionStore;
  /**
   * A send puts the new message at the end of the list, as in a messenger, rather than pinning it under the header
   * with space reserved for its answer, and the list follows new messages while it is at its end
   */
  noLiveTail?: boolean;
}

/**
 * A send pins the new question to the top of the list and reserves the rest of the screen for the answer.
 * The request is fulfilled once the list receives an outgoing message other than `lastOutgoingMessage`.
 * Until then, the previous live tail keeps its reserved space.
 */
interface LiveTailRequest {
  lastOutgoingMessage?: AgentMessage;
  previousMessageId?: number;
  /** Where a question sent from the follow-ups appears in the list's content: where those follow-ups begin */
  inPlaceTop?: number;
}

/** What a question being sent came from, for its bubble to come out of: the field's text, or the follow-up tapped */
type SentQuestionSource = {
  kind: 'field';
  picture: SentTextPicture;
  /** The list was at its end, where the question can show in place */
  isSentAtBottom: boolean;
  /** How far the question moves up as the follow-ups under the last answer give their space back */
  followupsSpace: number;
} | {
  kind: 'followup';
  followup: FollowupSource;
};

/** The space dissolving messages leave at the end of the list, until it closes */
interface DissolveGap {
  kind: SnapEffectKind;
  /** The space closes as the messages go, or at once where motion is reduced */
  isAnimated: boolean;
  /** The space the messages took, which the gap holds until it is measured */
  initialHeight: number;
  /** The element over the dissolving messages, or the turn they start, which the space hangs from */
  anchor: HTMLElement;
  /** The space hangs from the anchor's top, rather than from its bottom */
  isAnchorTop: boolean;
  /** How far under the anchor's edge the dissolving messages ended */
  reserve: number;
}

function AgentConversationShell({
  isActive,
  animationLevel,
  conversation,
  composer,
  history,
  slots,
  header,
  actions,
  session,
  noLiveTail = false,
}: AgentConversationShellProps) {
  const {
    messages, hints, isInitialLoadComplete, hasOpeningQuestion = false, hasHistoryPlaceholder = false,
    isNewsPlaceholder = false, historyPlaceholderLayout, hasDailyDateLines = false, unreadMessageId, loadFailure,
    emptyText, isRunActive = false, textRevealPresentations, dissolvingMessageIds, isFooterDissolving = false,
    onDissolveStart, renderMessage,
  } = conversation;
  const hasComposer = Boolean(composer);
  const {
    isDisabled: isInputDisabled = false,
    shouldHide: shouldHideComposer = false,
    canStop = false,
    onStop,
    onSendMessage,
    onSendHint,
    onHeightChange: onComposerHeightChange,
    onRequestConsent,
    render: renderComposer,
  } = composer ?? NO_COMPOSER;
  const {
    onBack, onReportProblem, onScroll: onExternalScroll, onMessageVisible, onDelete, onOpenDigestSettings,
  } = actions;
  const hasOlderMessages = history?.hasOlderMessages ?? false;
  const isLoadingOlderMessages = history?.isLoading ?? false;
  const shouldShowHistorySpinner = isLoadingOlderMessages && !history?.noLoadingIndicator;
  const loadOlderMessages = history?.loadOlderMessages;
  const historyThresholdRowCount = history?.thresholdRowCount;
  const shouldUseContinuousHistory = history?.mode === 'continuous';
  const conversationSlot = slots?.body;
  const isEmptyAfterLoad = Boolean(loadFailure || emptyText) && !messages.length;
  const hasMessageList = conversationSlot === undefined && !isEmptyAfterLoad;
  const messageListFooter = slots?.messageListFooter;
  const beforeComposerSlot = slots?.beforeComposer;
  const bottomStickDependency = slots?.bottomStickDependency;
  // The session is read once: what the chat kept applies as it comes on screen again
  const initialSessionRef = useRef(session?.initial);
  // Kept until the history shows whether the edited question is still there
  const pendingEditRef = useRef(session?.initial?.editedMessage);
  const [getInputValue, setInputValue] = useSignal(initialSessionRef.current?.draft ?? '');
  const inputValue = useDerivedState(getInputValue);
  const [isScrolledUp, setIsScrolledUp] = useState(false);
  const [reportTarget, setReportTarget] = useState<{ messageId?: number } | undefined>();
  const [isReadyToShow, markReadyToShow] = useFlag();
  // The loading bubbles lie under the messages until they have faded, and the bubbles growing out of them until they
  // have grown, and the list leaves its background to them
  const [isPlaceholderGone, markPlaceholderGone] = useFlag();
  const [getEditingMessageId, setEditingMessageId] = useSignal<number | undefined>();
  const editingMessageId = useDerivedState(getEditingMessageId);
  // A question pinned when the chat was on screen last is the live tail again once the history brings it, and so is
  // the question a new chat opens with, as on iOS. Both apply only as the chat mounts.
  const isQuestionPinnedOnOpen = Boolean(initialSessionRef.current?.isQuestionPinned) || hasOpeningQuestion;
  const [liveTailRequest, setLiveTailRequest] = useState<LiveTailRequest | undefined>(
    () => (isQuestionPinnedOnOpen ? {} : undefined),
  );
  const [focusedLiveTailRequest, setFocusedLiveTailRequest] = useState(liveTailRequest);
  const [frozenSpacerHeight, setFrozenSpacerHeight] = useState<number | undefined>();
  const [dissolveGap, setDissolveGap] = useState<DissolveGap | undefined>();
  // A question showing where it lands holds the list still until the list takes it up, as a scroll does
  const [isQuestionInPlace, setIsQuestionInPlace] = useState(false);
  // While removed messages turn to dust or fade, the run's activity under the question waits for them to go
  const [areMessagesDissolving, setAreMessagesDissolving] = useState(false);
  const [areDateLinesSticky, markDateLinesSticky] = useFlag();
  const messagesRef = useRef<HTMLDivElement>();
  // What a sent question flies through on its way into the list, over the field
  const motionLayerRef = useRef<HTMLDivElement>();
  // What the history's bubbles grow through out of the placeholders, under the list
  const historyRevealLayerRef = useRef<HTMLDivElement>();
  // The history's bubbles have grown and taken over from what they grew through
  const historyRevealEndRef = useRef<Promise<void>>();
  const sentSourceRef = useRef<SentQuestionSource>();
  // Ends the way of a question being sent into its bubble where it stands: a suggestion turning into it, or its flight
  // out of the field
  const finishQuestionMotionRef = useRef<NoneToVoidFunction>();
  // A question sent as in a messenger, which comes out of the field once the list has a question after this one
  const [messengerSend, setMessengerSend] = useState<{ lastOutgoingMessage?: AgentMessage }>();
  // Where the hints of an empty chat stood as its first question went, where they fade as it comes
  const [leavingHintsFrame, setLeavingHintsFrame] = useState<AgentHintsFrame>();
  const dissolveGapRef = useRef<HTMLDivElement>();
  const spacerRef = useRef<HTMLDivElement>();
  const liveTailRef = useRef<HTMLDivElement>();
  const inputRef = useRef<HTMLTextAreaElement>();
  const rootRef = useRef<HTMLDivElement>();
  // A chat that opens again where it was left starts away from its end, so nothing holds the list there
  const isAtBottomRef = useRef(!initialSessionRef.current?.scrollAnchor);
  // Where the list last scrolled itself to its end
  const ownEndScrollTopRef = useRef<number>();
  // The scroll button asked for the latest messages while they were out of the rendered window
  const shouldAnimateToEndRef = useRef(false);
  // While the answer grows under a pinned question, the list must not follow it down
  const isFollowSuppressedRef = useRef(isQuestionPinnedOnOpen);
  const shouldRevealLiveTailAnswerRef = useRef(false);
  const liveTailTimeoutRef = useRef<number>();
  // The list takes a question shown in place up once it has appeared
  const inPlaceScrollTimeoutRef = useRef<number>();
  const lastAutoLoadLengthRef = useRef<number>();
  const stuckDateLinesTimeoutRef = useRef<number>();

  useHistoryBack({ isActive, onBack });
  const { getIsSnappingToBottom, cancelSnapToBottom } = useScrollResetOnResize(messagesRef, isAtBottomRef);

  // While nothing on the page has focus, Tab starts at the input. Once something is focused, Tab follows
  // the usual order. A modal or the lock screen covers the agent, so their Tab must not reach the input.
  const handleTab = useLastCallback((e: KeyboardEvent) => {
    const input = inputRef.current;
    if (e.target !== document.body || !input || getIsAnyModalOpen() || getGlobal().isAppLockActive) return;

    e.preventDefault();
    focusAtEnd(input);
  });

  useHotkeys(useMemo(() => (isActive ? { Tab: handleTab } : undefined), [handleTab, isActive]));

  useEffect(() => {
    return () => {
      window.clearTimeout(liveTailTimeoutRef.current);
      window.clearTimeout(inPlaceScrollTimeoutRef.current);
      finishQuestionMotionRef.current?.();
      window.clearTimeout(stuckDateLinesTimeoutRef.current);
    };
  }, []);

  const shouldAnimate = useShouldAnimateText(animationLevel);
  const scrollDuration = shouldAnimate ? undefined : 0;
  const { isScrolled, handleScroll: handleMessagesScroll, update: updateScrolledState } = useScrolledState();

  const allIds = useMemo(
    () => buildMessageIds(messages, { unreadMessageId, hasDailyDateLines }),
    [hasDailyDateLines, messages, unreadMessageId],
  );
  const messagesById = useMemo(() => {
    const nextMessagesById: Record<number, AgentMessage> = {};

    for (const message of messages) {
      nextMessagesById[message.id] = message;
    }

    return nextMessagesById;
  }, [messages]);
  const turnIdByItemId = useMemo(
    () => buildMessageTurnIds(allIds, messagesById, hasDailyDateLines),
    [allIds, hasDailyDateLines, messagesById],
  );
  const lastOutgoingMessage = useMemo(() => getLastOutgoingMessage(messages), [messages]);
  const isLiveTailRequestFulfilled = Boolean(
    liveTailRequest && lastOutgoingMessage && lastOutgoingMessage !== liveTailRequest.lastOutgoingMessage,
  );
  const liveTailMessageId = isLiveTailRequestFulfilled ? lastOutgoingMessage!.id : liveTailRequest?.previousMessageId;
  const liveTailTurnId = liveTailMessageId !== undefined ? turnIdByItemId[liveTailMessageId] : undefined;
  // A request stays pending until the list scrolls to the question it was made for
  const isLiveTailPending = liveTailRequest !== undefined && liveTailRequest !== focusedLiveTailRequest;
  const isLiveTailPendingRef = useStateRef(isLiveTailPending);
  const lastMessage = messages[messages.length - 1];
  const isAnswerSettled = !isRunActive && !isLiveTailPending
    && (!lastMessage || textRevealPresentations[lastMessage.id]?.status !== 'active');
  const areHintsVisible = isInitialLoadComplete && messages.length === 0;
  // The Agent thinks until the text of its answer comes
  const isThinking = isRunActive && (!lastMessage || lastMessage.isOutgoing || !lastMessage.text);

  // Messages that were already there when the list became visible are not new
  const shownIds = isReadyToShow ? allIds : undefined;
  const prevShownIds = usePrevious2(shownIds);
  const justAddedIds = useMemo(
    () => (shownIds && prevShownIds ? getAppendedIds(shownIds, prevShownIds) : undefined),
    [prevShownIds, shownIds],
  );

  const releaseFrozenSpacer = useLastCallback(() => {
    setFrozenSpacerHeight(undefined);
  });

  const cancelInPlaceScroll = useLastCallback(() => {
    window.clearTimeout(inPlaceScrollTimeoutRef.current);
    inPlaceScrollTimeoutRef.current = undefined;
    setIsQuestionInPlace(false);
  });

  const resetLiveTail = useLastCallback(() => {
    window.clearTimeout(liveTailTimeoutRef.current);
    cancelInPlaceScroll();
    setLiveTailRequest(undefined);
    setFocusedLiveTailRequest(undefined);
    releaseFrozenSpacer();
    isFollowSuppressedRef.current = false;
    shouldRevealLiveTailAnswerRef.current = false;
    if (isAnimatingScroll(messagesRef.current)) cancelScrollAnimation();
  });

  const replaceSentSource = useLastCallback((source?: SentQuestionSource) => {
    if (sentSourceRef.current) discardSentSource(sentSourceRef.current);
    sentSourceRef.current = source;
  });

  // The tapped suggestion, a follow-up under an answer or a hint of an empty chat, as it stands, which turns into its
  // question once the list shows it, while the others ripple away from it. It reads the layout, as a send does.
  const captureTappedSuggestion = useLastCallback((button?: HTMLElement): SentQuestionSource | undefined => {
    const layer = motionLayerRef.current;
    if (!shouldAnimate || !button || !layer) return undefined;

    rippleFollowupsAway(button, layer);
    const followup = captureFollowupSource(button);
    return followup && { kind: 'followup', followup };
  });

  // A question sent as in a messenger comes out of what it was sent from too, once the list shows it at its end. One
  // that never reaches the list lets its picture go.
  const waitForMessengerQuestion = useLastCallback(() => {
    setMessengerSend({ lastOutgoingMessage });
    window.clearTimeout(liveTailTimeoutRef.current);
    liveTailTimeoutRef.current = window.setTimeout(() => {
      setMessengerSend(undefined);
      replaceSentSource(undefined);
    }, LIVE_TAIL_REQUEST_TIMEOUT);
  });

  const requestLiveTail = useLastCallback((followupId?: string) => {
    if (noLiveTail) {
      // The reserve of a question pinned before goes too, so that it leaves no empty space above the new message
      const liveTail = liveTailRef.current;
      if (liveTail) {
        requestMutation(() => {
          liveTail.style.removeProperty('min-height');
        });
      }
      resetLiveTail();
      isAtBottomRef.current = true;
      if (sentSourceRef.current) waitForMessengerQuestion();
      return;
    }

    const request: LiveTailRequest = {
      lastOutgoingMessage,
      previousMessageId: liveTailMessageId,
      inPlaceTop: followupId !== undefined ? getFollowupsTop(messagesRef.current) : undefined,
    };
    if (followupId !== undefined) {
      replaceSentSource(captureTappedSuggestion(findFollowupButton(messagesRef.current, followupId)));
    }
    isAtBottomRef.current = true;
    setLiveTailRequest(request);
    // A retried answer reuses its turn, so a reserve trimmed by scrolling must be restored for it
    requestMutation(() => {
      liveTailRef.current?.style.removeProperty('min-height');
    });
    // Short histories are pushed to the bottom by the spacer. Keeping its height until the list scrolls to the new
    // question makes the old messages scroll away instead of jumping to the top when the question is added. An empty
    // chat has nothing to scroll away: its first question stands at the top at once, as on iOS, and its hints leave
    // where they stand, out of the list's way, so nothing jumps and the run's activity under the question comes up
    // clear of them.
    if (areHintsVisible) {
      setLeavingHintsFrame(measureHintsFrame(messagesRef.current));
    } else {
      setFrozenSpacerHeight(spacerRef.current?.offsetHeight || undefined);
    }

    // A send that never reaches the list, such as a run that fails to start, would otherwise leave the list
    // waiting for its question: no scroll to the bottom on new content and no scroll restore on history loads.
    window.clearTimeout(liveTailTimeoutRef.current);
    liveTailTimeoutRef.current = window.setTimeout(() => {
      setFocusedLiveTailRequest(request);
      releaseFrozenSpacer();
      replaceSentSource(undefined);
    }, LIVE_TAIL_REQUEST_TIMEOUT);
  });

  useEffect(() => {
    if (!isInitialLoadComplete || messages.length > 0) return;

    resetLiveTail();
    setLeavingHintsFrame(undefined);
    setDissolveGap(undefined);
    setAreMessagesDissolving(false);
    setIsScrolledUp(false);
    isAtBottomRef.current = true;
    requestMeasure(() => updateScrolledState(messagesRef.current));
  }, [isInitialLoadComplete, messages.length, resetLiveTail, updateScrolledState]);

  // A question pinned when the chat was on screen last is not pinned again
  useLayoutEffect(() => {
    if (noLiveTail && !isReadyToShow) resetLiveTail();
  }, [isReadyToShow, noLiveTail, resetLiveTail]);

  const [viewportIds, getMore, resetScroll] = useInfiniteScroll({
    loadMoreForwards: hasOlderMessages && !isLoadingOlderMessages ? loadOlderMessages : undefined,
    listIds: allIds.length > 0 ? allIds : undefined,
    isActive,
    startFromEnd: true,
    shouldKeepViewportAtEnd: isAtBottomRef.current,
    shouldPreserveViewport: shouldUseContinuousHistory,
    maxPreservedViewportSize: shouldUseContinuousHistory ? CONTINUOUS_HISTORY_MAX_VIEWPORT_SIZE : undefined,
  });
  const lastAllId = allIds[allIds.length - 1];
  const previousLastAllIdRef = useRef(lastAllId);
  const lastViewportId = viewportIds?.[viewportIds.length - 1];
  const isViewportAtEnd = !lastAllId || lastAllId === lastViewportId;

  const updateScrollPosition = useLastCallback((element: HTMLDivElement) => {
    const distanceToBottom = element.scrollHeight - element.scrollTop - element.clientHeight;
    // The event of the list's own scroll to its end can come after an answer has grown further, which does not take
    // the list away from its end
    const isOwnEndScroll = ownEndScrollTopRef.current !== undefined
      && Math.abs(element.scrollTop - ownEndScrollTopRef.current) < 1;
    isAtBottomRef.current = isOwnEndScroll || distanceToBottom < SCROLL_FLICKER_THRESHOLD;
    setIsScrolledUp(!isOwnEndScroll && distanceToBottom > SCROLL_BOTTOM_THRESHOLD);
  });

  // A chat that comes on screen again opens where it was left. Otherwise it opens at its first unread message, and at
  // its end without one.
  const getOpeningMessageId = useLastCallback(() => {
    const { scrollAnchor, isPlaced } = initialSessionRef.current ?? {};
    if (scrollAnchor || isPlaced || isFollowSuppressedRef.current) return undefined;

    return unreadMessageId !== undefined && messagesById[unreadMessageId] ? unreadMessageId : undefined;
  });

  const scrollToInitialPosition = useLastCallback((element: HTMLDivElement) => {
    const liveTail = isFollowSuppressedRef.current ? liveTailRef.current : undefined;
    if (liveTail) {
      element.scrollTo({ top: getPinnedLiveTailScrollTop(element, liveTail), behavior: 'instant' });
      // An answer without text yet comes into view once, as after a send
      shouldRevealLiveTailAnswerRef.current = !lastMessage || lastMessage.isOutgoing || !lastMessage.text;
      updateScrollPosition(element);
      return;
    }

    isFollowSuppressedRef.current = false;
    const scrollAnchor = initialSessionRef.current?.scrollAnchor;
    const anchorScrollTop = scrollAnchor && getScrollAnchorTop(element, scrollAnchor, messages);
    const openingMessageId = getOpeningMessageId();
    const openingScrollTop = openingMessageId !== undefined
      ? getOpeningScrollTop(element, openingMessageId)
      : undefined;
    element.scrollTo({ top: anchorScrollTop ?? openingScrollTop ?? element.scrollHeight, behavior: 'instant' });
    if (!scrollAnchor && openingScrollTop === undefined) return;

    ownEndScrollTopRef.current = undefined;
    updateScrollPosition(element);
  });

  const scrollToBottom = useLastCallback(() => {
    requestMeasure(() => {
      const element = messagesRef.current;
      if (!element) return;

      element.scrollTo({ top: element.scrollHeight, behavior: 'instant' });
      ownEndScrollTopRef.current = element.scrollTop;
    });
  });

  const animateToBottom = useLastCallback(() => {
    requestMeasure(() => {
      const element = messagesRef.current;
      if (!element) return;

      // The scroll button can be pressed while the list still moves from the user's swipe
      requestMutation(animateScroll(element, getBottomScrollTop, {
        forceDuration: scrollDuration,
        shouldWaitForMomentum: true,
        onEnd: releaseFrozenSpacer,
      }));
    });
  });

  // A list about to open at a message is placed there rather than at its end
  const getIsOpeningAtMessage = useLastCallback(() => !isReadyToShow && getOpeningMessageId() !== undefined);

  // The latest messages coming into the rendered window take the list to its end while it is held there or the scroll
  // button asked for them. Scrolled down to them, the list stays where the user is.
  useLayoutEffect(() => {
    if (!isActive || !isViewportAtEnd || getIsOpeningAtMessage()) return;
    if (!isAtBottomRef.current && !shouldAnimateToEndRef.current) return;

    if (shouldAnimateToEndRef.current) {
      shouldAnimateToEndRef.current = false;
      animateToBottom();
    } else {
      scrollToBottom();
    }
  }, [animateToBottom, isActive, isViewportAtEnd, scrollToBottom]);

  useLayoutEffect(() => {
    if (!hasMessageList || !isActive || !isInitialLoadComplete || isReadyToShow) return;

    // A list that opens at a message is not held at its end. The rendered messages make way for that message when it
    // lies beyond them.
    const scrollAnchor = initialSessionRef.current?.scrollAnchor;
    const openingMessageId = scrollAnchor
      ? getScrollAnchorMessage(scrollAnchor, messages)?.id
      : getOpeningMessageId();
    if (openingMessageId !== undefined) {
      isAtBottomRef.current = false;
      if (viewportIds && !viewportIds.includes(String(openingMessageId))) {
        getMore?.({ direction: LoadMoreDirection.Backwards, offsetId: String(openingMessageId) });
        return;
      }
    }

    requestForcedReflow(() => {
      const element = messagesRef.current;
      if (element) scrollToInitialPosition(element);

      // The messages that land on screen come in out of the placeholder, as Telegram's history does
      const revealLayer = historyRevealLayerRef.current;
      const historyReveal = element && revealLayer && hasHistoryPlaceholder && shouldAnimate
        ? measureHistoryReveal(element, revealLayer)
        : undefined;

      return () => {
        // The messages come on screen in the frame the placeholders give way to them
        if (element) removeExtraClass(element, styles.hidden);
        if (historyReveal) historyRevealEndRef.current = startHistoryReveal(historyReveal, revealLayer!);
        markReadyToShow();
      };
    });
  }, [
    getMore, getOpeningMessageId, hasHistoryPlaceholder, hasMessageList, isActive, isInitialLoadComplete, isReadyToShow,
    markReadyToShow, messages, scrollToInitialPosition, shouldAnimate, viewportIds,
  ]);

  useEffect(() => {
    if (!isActive || isViewportAtEnd || !isAtBottomRef.current) return;
    getMore?.({ direction: LoadMoreDirection.Backwards });
  }, [getMore, isActive, isViewportAtEnd, lastAllId, lastViewportId]);

  useEffect(() => {
    if (!isActive || !isInitialLoadComplete || !hasOlderMessages || isLoadingOlderMessages) return;

    requestMeasure(() => {
      const element = messagesRef.current;
      if (element && element.scrollHeight <= element.clientHeight && lastAutoLoadLengthRef.current !== allIds.length) {
        lastAutoLoadLengthRef.current = allIds.length;
        getMore?.({ direction: LoadMoreDirection.Forwards });
      }
    });
  }, [allIds.length, getMore, hasOlderMessages, isActive, isInitialLoadComplete, isLoadingOlderMessages]);

  // The list takes its background back once the bubbles growing under it have taken over too
  const handlePlaceholderClosed = useLastCallback(() => {
    void (historyRevealEndRef.current ?? Promise.resolve()).then(() => markPlaceholderGone());
  });

  const handleRevealFrame = useLastCallback(() => {
    const element = messagesRef.current;
    if (!element) return;

    if (!isFollowSuppressedRef.current) {
      // The answer grows while the list scrolls, so the running animation aims at the new bottom
      if (isAnimatingScroll(element)) {
        restartScrollAnimation();
      } else {
        scrollToBottom();
      }
      return;
    }

    // A question shown in place goes up only when its own time comes, however soon its answer starts
    if (inPlaceScrollTimeoutRef.current !== undefined) return;

    // The answer grows into the reserved space without moving the scroll's target. A row that collapses above the
    // question, as the follow-ups of the previous answer, moves the target with it.
    if (isAnimatingScroll(element)) {
      restartScrollAnimation();
      return;
    }

    requestMeasure(() => {
      // A question taller than the screen pushes the start of its answer below the fold, so the list reveals
      // the first lines once. After that, the answer grows downward without moving the list.
      const isAnswerVisible = lastMessage && !lastMessage.isOutgoing && Boolean(lastMessage.text);
      if (shouldRevealLiveTailAnswerRef.current && isAnswerVisible) {
        shouldRevealLiveTailAnswerRef.current = false;
        const mutate = animateScroll(element, getLiveTailScrollTop, {
          forceDuration: scrollDuration,
          onEnd: releaseFrozenSpacer,
        });
        requestMutation(mutate);
        return;
      }

      updateScrollPosition(element);
    });
  });

  const handleTextRevealProgress = useScrollToBottomOnReveal(
    () => isAtBottomRef.current || isFollowSuppressedRef.current,
    handleRevealFrame,
  );

  const handleScrollToBottomClick = useLastCallback(() => {
    isAtBottomRef.current = true;
    isFollowSuppressedRef.current = false;
    setIsScrolledUp(false);

    if (isViewportAtEnd) {
      animateToBottom();
      return;
    }

    // The latest messages take the place of the rendered ones, and the list scrolls to them once they render
    shouldAnimateToEndRef.current = true;
    resetScroll?.();
  });

  // The list takes up the question that has appeared where it landed, and releases the hold on its position once its
  // own scroll holds it, so that no position kept from before the question restores in between
  const scrollToLiveTail = useLastCallback(() => {
    const element = messagesRef.current;
    // A scroll of the user's own while the question appeared keeps the list where the user took it
    if (!element || !isFollowSuppressedRef.current) {
      setIsQuestionInPlace(false);
      return;
    }

    // The answer's first lines that came while the question appeared come into view with it
    if (lastMessage && !lastMessage.isOutgoing && lastMessage.text) shouldRevealLiveTailAnswerRef.current = false;

    requestMeasure(() => {
      const mutateScroll = animateScroll(element, getLiveTailScrollTop, {
        maxDistance: element.clientHeight,
        forceDuration: scrollDuration,
        transition: easeInOutTransition,
        onEnd: releaseFrozenSpacer,
      });
      requestMutation(() => {
        mutateScroll();
        setIsQuestionInPlace(false);
      });
    });
  });

  // Starts the way of the question being sent into its bubble, ending the one before where it stands
  const startQuestionMotion = useLastCallback((startMotion: () => NoneToVoidFunction) => {
    finishQuestionMotionRef.current?.();
    finishQuestionMotionRef.current = startMotion();
  });

  const focusLiveTail = useLastCallback(() => {
    window.clearTimeout(liveTailTimeoutRef.current);
    cancelInPlaceScroll();
    setFocusedLiveTailRequest(liveTailRequest);
    isAtBottomRef.current = true;
    isFollowSuppressedRef.current = !noLiveTail;
    shouldRevealLiveTailAnswerRef.current = !noLiveTail;

    requestForcedReflow(() => {
      const element = messagesRef.current;
      const layer = motionLayerRef.current;
      const source = sentSourceRef.current;
      sentSourceRef.current = undefined;
      if (!element || !layer) {
        if (source) discardSentSource(source);
        return undefined;
      }

      const isQuestionJustSent = shouldAnimate && liveTailMessageId !== undefined
        && Boolean(justAddedIds?.has(String(liveTailMessageId)));
      const question = isQuestionJustSent ? findQuestion(element, liveTailMessageId) : undefined;
      const getBubble = () => findQuestion(element, liveTailMessageId!)?.bubble;
      // A tapped suggestion turns into its question wherever the list shows it, as on iOS, and a question sent from the
      // field comes out of it there, as Telegram's send does
      const morph = question && source?.kind === 'followup'
        ? measureFollowupMorph(source.followup, question.bubble, question.text, getBubble, layer)
        : undefined;
      const flight = question && source?.kind === 'field' ? measureSentQuestionFlight(
        source.picture, question.bubble, question.text, getBubble, layer, () => getComposerTop(layer),
      ) : undefined;
      if (source && !flight) discardSentSource(source);
      const startMotion = morph ?? flight;

      // A question that shows where it lands appears there first, and the list takes it up once it has appeared, as on
      // iOS and Android: one sent from the field that shows on screen right under the list's end, and one sent from the
      // follow-ups that fits where they were
      const isFieldQuestionInPlace = Boolean(flight && source?.kind === 'field' && source.isSentAtBottom
        && getIsQuestionShownInPlace(element, question!.message, question!.bubble, source.followupsSpace));
      const isFollowupInPlace = Boolean(question && liveTailRequest?.inPlaceTop !== undefined
        && getIsQuestionInPlace(element, question.bubble, liveTailRequest.inPlaceTop));
      if (isFieldQuestionInPlace || isFollowupInPlace) {
        const appearanceDuration = flight ? SENT_QUESTION_FLIGHT_DURATION
          : morph ? FOLLOWUP_MORPH_DURATION : QUESTION_IN_PLACE_DURATION;
        return () => {
          if (startMotion) {
            startQuestionMotion(startMotion);
          } else {
            animateQuestionInPlace(question!.bubble);
          }
          setIsQuestionInPlace(true);
          inPlaceScrollTimeoutRef.current = window.setTimeout(() => {
            inPlaceScrollTimeoutRef.current = undefined;
            scrollToLiveTail();
          }, appearanceDuration + QUESTION_IN_PLACE_SCROLL_DELAY);
        };
      }

      // A question just sent with nothing to come out of that the list has no room to scroll to rises from the input
      // into its place, as on iOS
      const flyUp = isQuestionJustSent && !startMotion ? measureQuestionFlyUp(element, liveTailMessageId) : undefined;
      // Normally the new question is at most one screen away. A longer path means the list was scrolled up,
      // so it jumps closer first instead of animating through the whole history. The question comes up from
      // under the input at rest and settles at rest, as on iOS, its flight or morph following it.
      const mutateScroll = animateScroll(element, getLiveTailScrollTop, {
        maxDistance: element.clientHeight,
        forceDuration: scrollDuration,
        transition: easeInOutTransition,
        onEnd: releaseFrozenSpacer,
      });

      return () => {
        mutateScroll();
        flyUp?.();
        if (startMotion) {
          startQuestionMotion(startMotion);
        } else if (question && !flyUp) {
          // A question with nothing to come out of, as one of more than ten lines, fades in and grows into its bubble
          // as the list brings it up, as Android's row opens and as iOS's question does. One that rises from the input
          // fades in with its rise alone.
          animateQuestionInPlace(question.bubble);
        }
      };
    });
  });

  // The question sent as in a messenger comes out of what it was sent from wherever the list puts it, at its end
  const messengerQuestionId = messengerSend && lastOutgoingMessage
    && lastOutgoingMessage !== messengerSend.lastOutgoingMessage ? lastOutgoingMessage.id : undefined;
  useLayoutEffect(() => {
    if (messengerQuestionId === undefined) return;

    setMessengerSend(undefined);
    window.clearTimeout(liveTailTimeoutRef.current);
    const isQuestionJustSent = shouldAnimate && Boolean(justAddedIds?.has(String(messengerQuestionId)));

    requestForcedReflow(() => {
      const element = messagesRef.current;
      const layer = motionLayerRef.current;
      const source = sentSourceRef.current;
      sentSourceRef.current = undefined;
      const question = element && isQuestionJustSent ? findQuestion(element, messengerQuestionId) : undefined;
      const getBubble = () => findQuestion(element!, messengerQuestionId)?.bubble;
      let startMotion: (() => NoneToVoidFunction) | undefined;
      if (question && layer && source?.kind === 'field') {
        startMotion = measureSentQuestionFlight(
          source.picture, question.bubble, question.text, getBubble, layer, () => getComposerTop(layer),
        );
      } else if (question && layer && source?.kind === 'followup') {
        startMotion = measureFollowupMorph(source.followup, question.bubble, question.text, getBubble, layer);
      }
      if (source && !startMotion) discardSentSource(source);

      return startMotion && (() => startQuestionMotion(startMotion));
    });
  }, [justAddedIds, messengerQuestionId, shouldAnimate, startQuestionMotion]);

  const wasNoLiveTailRef = useRef(noLiveTail);
  // The last item as `noLiveTail` turned on over a pinned question
  const followResumeIdRef = useRef<string>();
  const previousNewsFollowupsRef = useRef<{ id: number; count: number }>();
  useLayoutEffect(() => {
    const isLastItemChanged = lastAllId !== previousLastAllIdRef.current;
    previousLastAllIdRef.current = lastAllId;
    const isNoLiveTailTurningOn = noLiveTail && !wasNoLiveTailRef.current;
    wasNoLiveTailRef.current = noLiveTail;
    const previousNewsFollowups = previousNewsFollowupsRef.current;
    const newsFollowups = lastMessage?.isNewsPost
      ? { id: lastMessage.id, count: lastMessage.followups?.length ?? 0 }
      : undefined;
    const areNewsFollowupsArriving = newsFollowups && newsFollowups.count > 0
      && previousNewsFollowups?.id === newsFollowups.id && previousNewsFollowups.count === 0;
    previousNewsFollowupsRef.current = newsFollowups;

    if (isLiveTailPending && isLiveTailRequestFulfilled) {
      focusLiveTail();
      return;
    }

    // A question pinned as `noLiveTail` turns on keeps its place and its reserve, and the messages that come along with
    // the switch stay under it, while the list follows the messages after them
    if (isNoLiveTailTurningOn && isFollowSuppressedRef.current) {
      followResumeIdRef.current = lastAllId;
      shouldRevealLiveTailAnswerRef.current = false;
      requestMeasure(() => {
        if (messagesRef.current) updateScrollPosition(messagesRef.current);
      });
    } else if (followResumeIdRef.current !== undefined && lastAllId !== followResumeIdRef.current) {
      followResumeIdRef.current = undefined;
      if (noLiveTail) isFollowSuppressedRef.current = false;
    }

    // The list scrolls to the sent question once it arrives, so it must not jump to the bottom before that
    if (isLiveTailPending || isFollowSuppressedRef.current || !isAtBottomRef.current) return;

    if (areNewsFollowupsArriving && shouldAnimate) {
      animateToBottom();
      return;
    }

    // A new last item, as a regenerated answer, makes the list restore its scroll anchor in this frame, which would
    // undo the scroll, so the end is kept from the next frame
    const keepEnd = isLastItemChanged ? requestMeasure : requestForcedReflow;
    keepEnd(() => {
      const element = messagesRef.current;
      if (!element) return;

      if (isAnimatingScroll(element)) {
        restartScrollAnimation();
        return;
      }

      element.scrollTo({ top: element.scrollHeight, behavior: 'instant' });
      ownEndScrollTopRef.current = element.scrollTop;
      isAtBottomRef.current = true;
    });
  }, [
    animateToBottom,
    bottomStickDependency,
    focusLiveTail,
    isLiveTailPending,
    loadFailure,
    isLiveTailRequestFulfilled,
    lastAllId,
    lastMessage,
    messages,
    noLiveTail,
    shouldAnimate,
    textRevealPresentations,
    updateScrollPosition,
  ]);

  // Messages turn to dust where they stand: ghosts of those on screen take their place over the list, and the space
  // they leave is held by a gap at the end of the list once the next messages come
  const startDissolve = useLastCallback((messageIds?: readonly number[]) => {
    const kind = getSnapEffectKind(shouldAnimate);

    requestForcedReflow(() => {
      const container = messagesRef.current;
      const elements = container && isReadyToShow
        ? (messageIds ? findDissolvingElements(container, messageIds) : findDissolvingFooter(container))
        : undefined;
      if (!container || !elements) return onDissolveStart;

      const containerRect = container.getBoundingClientRect();
      const ghosts = elements
        .filter((element) => getIsInView(element, containerRect))
        .map((element) => createSnapGhost(element, kind));
      const first = elements[0];
      const previous = first.previousElementSibling as HTMLElement | null;
      const anchor = previous ?? first.parentElement!;
      const anchorEdge = previous ? previous.getBoundingClientRect().bottom : anchor.getBoundingClientRect().top;
      const start = previous ? anchorEdge : first.getBoundingClientRect().top;
      const end = elements[elements.length - 1].getBoundingClientRect().bottom;

      return () => {
        const layer = getSnapEffectLayer();
        ghosts.forEach((ghost) => layer.appendChild(ghost));
        elements.forEach((element) => addExtraClass(element, styles.dissolved));
        dissolveGenerationRef.current += 1;
        setAreMessagesDissolving(true);
        setDissolveGap({
          kind,
          isAnimated: shouldAnimate,
          initialHeight: Math.max(0, end - start),
          anchor,
          isAnchorTop: !previous,
          reserve: end - anchorEdge,
        });
        onDissolveStart?.();
      };
    });
  });

  useLayoutEffect(() => {
    if (dissolvingMessageIds?.length) {
      startDissolve(dissolvingMessageIds);
    } else if (isFooterDissolving) {
      startDissolve();
    }
  }, [dissolvingMessageIds, isFooterDissolving, startDissolve]);

  const releaseDissolveGap = useLastCallback(() => {
    setDissolveGap(undefined);
  });

  const isAnswerSettledRef = useStateRef(isAnswerSettled);
  // A dissolve that starts while another is closing takes its place
  const dissolveGenerationRef = useRef(0);

  // The gap ends where the dissolved messages ended, so nothing moves when they go. It is measured on every frame from
  // the element over them, so that whatever comes in between, as the run's activity or the next answer, takes its space
  // instead of moving the list, whether the list keeps its top or its end in place, as Android keeps the space under a
  // question answered again. Once the messages have gone and the answer has settled, what is left of it closes, or goes
  // at once where motion is reduced.
  useLayoutEffect(() => {
    if (!dissolveGap) return undefined;

    const {
      kind, isAnimated, anchor, isAnchorTop, reserve,
    } = dissolveGap;
    const startedAt = Date.now();
    const dissolveDuration = getSnapGapCloseDelay(kind);
    const generation = dissolveGenerationRef.current;
    let isCancelled = false;
    let isClosed = false;
    let releaseTimer: number | undefined;

    function finishDissolving() {
      if (dissolveGenerationRef.current === generation) setAreMessagesDissolving(false);
    }

    const dissolveTimeout = window.setTimeout(finishDissolving, dissolveDuration);

    function fitGap() {
      requestForcedReflow(() => {
        const container = messagesRef.current;
        // A new last turn holds the gap in an element of its own
        const gap = dissolveGapRef.current;
        if (isCancelled) return undefined;
        if (!container || !gap || !anchor.isConnected) {
          isClosed = true;
          return releaseDissolveGap;
        }

        if (Date.now() - startedAt >= dissolveDuration && isAnswerSettledRef.current) {
          isClosed = true;
          if (!isAnimated) return releaseDissolveGap;

          return () => {
            if (isCancelled) return;

            closeDissolveGap(container, gap);
            releaseTimer = window.setTimeout(releaseDissolveGap, DISSOLVE_GAP_CLOSE_DURATION);
          };
        }

        const anchorRect = anchor.getBoundingClientRect();
        const contentHeight = gap.getBoundingClientRect().top - (isAnchorTop ? anchorRect.top : anchorRect.bottom);
        const height = Math.max(0, reserve - contentHeight);

        return () => {
          gap.style.height = `${height}px`;
        };
      });
    }

    fitGap();
    animate(() => {
      if (isCancelled || isClosed) return false;

      fitGap();
      return true;
    }, requestMeasure);

    return () => {
      isCancelled = true;
      window.clearTimeout(dissolveTimeout);
      window.clearTimeout(releaseTimer);
      finishDissolving();
    };
  }, [dissolveGap, isAnswerSettledRef, releaseDissolveGap]);

  // The live tail reserves a screen of space under the question for the answer to grow into. Once the answer
  // is finished, scrolling up trims whatever stays empty so the user cannot scroll back down into a blank area.
  // Only the part below the current viewport is trimmed, so the visible content never moves.
  const trimLiveTailReserve = useLastCallback((element: HTMLDivElement) => {
    const liveTail = liveTailRef.current;
    if (!liveTail) return;

    const slack = element.scrollHeight - element.scrollTop - element.clientHeight;
    if (slack <= 0) return;

    const contentHeight = getTurnContentHeight(liveTail);
    const minHeight = Math.max(contentHeight, liveTail.offsetHeight - slack);
    requestMutation(() => {
      liveTail.style.minHeight = `${minHeight}px`;
    });
  });

  // The days' lines stick to the top once the list scrolls after it came on screen, as Telegram Web A's dates do, which
  // keeps the one stuck at the top from showing as the list opens. They all show while the list scrolls, and the stuck
  // one fades away once it rests.
  const updateStickyDateLines = useLastCallback((element: HTMLDivElement) => {
    if (!isReadyToShow) return;

    markDateLinesSticky();
    if (!element.classList.contains(styles.messagesScrolling)) {
      requestMutation(() => addExtraClass(element, styles.messagesScrolling));
    }
    window.clearTimeout(stuckDateLinesTimeoutRef.current);
    stuckDateLinesTimeoutRef.current = window.setTimeout(() => {
      requestMeasure(() => {
        const stuckCapsules = findStuckDateLines(element)
          .map((line) => line.querySelector<HTMLElement>(`.${styles.dateSeparatorDayHeader}`)!);

        requestMutation(() => {
          element.querySelectorAll<HTMLElement>(`.${styles.dateSeparatorStuck}`).forEach((capsule) => {
            removeExtraClass(capsule, styles.dateSeparatorStuck);
          });
          stuckCapsules.forEach((capsule) => addExtraClass(capsule, styles.dateSeparatorStuck));
          removeExtraClass(element, styles.messagesScrolling);
        });
      });
    }, STUCK_DATE_LINE_HIDE_DELAY);
  });

  // Older messages load only once the list has been placed
  const getIsNearTopByRows = useLastCallback((element: HTMLDivElement) => (
    isReadyToShow && getIsWithinRowsOfTop(element, historyThresholdRowCount!)
  ));

  const handleScroll = useLastCallback((event: React.UIEvent<HTMLDivElement>) => {
    const element = event.target as HTMLDivElement;
    // Intermediate positions of an animated scroll must not reset `isAtBottomRef` or flash the scroll button
    if (!isAnimatingScroll(element) && !getIsSnappingToBottom(element)) {
      updateScrollPosition(element);
      if (isAnswerSettled) trimLiveTailReserve(element);
    }
    if (hasDailyDateLines) updateStickyDateLines(element);
    handleMessagesScroll(event);
    onExternalScroll?.(event);
  });

  useEffect(() => {
    const element = messagesRef.current;
    if (!element) return undefined;

    function handleUserScroll() {
      ownEndScrollTopRef.current = undefined;
      isFollowSuppressedRef.current = false;
      cancelSnapToBottom();
      if (isAnimatingScroll(element)) cancelScrollAnimation();
    }

    // The inertia of a swipe made before the scroll button was pressed does not stop the scroll to the latest messages
    function handleWheel(e: WheelEvent) {
      if (trackWheelInertia(element!, e)) return;

      handleUserScroll();
    }

    function handleTouchStart() {
      if (isAnimatingScroll(element)) cancelScrollAnimation();
    }

    function handlePointerDown(e: PointerEvent) {
      // A press on the list element itself rather than on its content lands on the scrollbar
      if (e.target === element) handleUserScroll();
    }

    element.addEventListener('wheel', handleWheel, { passive: true });
    element.addEventListener('touchstart', handleTouchStart, { passive: true });
    element.addEventListener('touchmove', handleUserScroll, { passive: true });
    element.addEventListener('pointerdown', handlePointerDown);

    return () => {
      if (isAnimatingScroll(element)) cancelScrollAnimation();
      element.removeEventListener('wheel', handleWheel);
      element.removeEventListener('touchstart', handleTouchStart);
      element.removeEventListener('touchmove', handleUserScroll);
      element.removeEventListener('pointerdown', handlePointerDown);
    };
  }, [cancelSnapToBottom, hasMessageList]);

  // The field's text as it shows, which the question's bubble comes out of once the list shows it. It reads the
  // layout, as a send does. A question with secret words shows in its bubble without them, so it doesn't come out of
  // the field.
  const captureFieldSource = useLastCallback((): SentQuestionSource | undefined => {
    const input = inputRef.current;
    const layer = motionLayerRef.current;
    if (!shouldAnimate || !input || !layer || hasSecretPhrase(input.value, getSecretPhraseWordList())) return undefined;

    const picture = createSentTextPicture(input, layer);
    return picture && {
      kind: 'field',
      picture,
      isSentAtBottom: isAtBottomRef.current,
      followupsSpace: getFollowupsSpace(messagesRef.current),
    };
  });

  const handleSend = useLastCallback(() => {
    const text = getInputValue().trim();
    // The draft stays editable while an answer is running, so Enter must not send it
    if (!text || isInputDisabled) return;

    const messageId = getEditingMessageId();
    // An edited question keeps its bubble, so only a new one comes out of the field
    replaceSentSource(messageId === undefined ? captureFieldSource() : undefined);
    setInputValue('');
    setEditingMessageId(undefined);
    pendingEditRef.current = undefined;
    requestLiveTail();
    onSendMessage!(text, messageId);
  });

  const handleKeyDown = useLastCallback((event: React.KeyboardEvent) => {
    const action = getReturnKeyAction(event);
    if (action !== 'send' && action !== 'lineBreak') return;

    stopEvent(event);
    if (action === 'lineBreak') {
      if (inputRef.current) insertLineBreak(inputRef.current);
      return;
    }
    handleSend();
  });

  const handleInput = useLastCallback((value: string) => {
    setInputValue(value);
    if (!value) {
      setEditingMessageId(undefined);
      pendingEditRef.current = undefined;
    }
  });

  const handleEditMessage = useLastCallback((id: number, text: string) => {
    setInputValue(text);
    setEditingMessageId(id);
    pendingEditRef.current = undefined;

    requestAnimationFrame(() => {
      if (inputRef.current) focusAtEnd(inputRef.current);
    });
  });

  const getEditedMessage = useLastCallback((): AgentConversationSession['editedMessage'] => {
    const messageId = getEditingMessageId();
    if (messageId === undefined) return pendingEditRef.current;

    const index = messages.findIndex(({ id }) => id === messageId);
    return index === -1 ? undefined : { indexFromEnd: messages.length - 1 - index, text: messages[index].text };
  });

  // The focus and the scroll position as the app switched layouts or the list went off screen, which later saves of the
  // draft carry along
  const switchedLayoutRef = useRef<
    Pick<AgentConversationSession, 'isInputFocused' | 'isQuestionPinned' | 'scrollAnchor' | 'isPlaced'>
  >();
  const buildSession = useLastCallback((): AgentConversationSession => ({
    draft: getInputValue(),
    editedMessage: getInputValue() ? getEditedMessage() : undefined,
    ...switchedLayoutRef.current,
  }));

  const saveSession = session?.save;
  useEffect(() => {
    saveSession?.(buildSession());
  }, [buildSession, editingMessageId, inputValue, saveSession]);

  // The question being edited before the chat mounted again stays in edit, unless the history has changed it
  useEffect(() => {
    const editedMessage = pendingEditRef.current;
    if (!editedMessage || !isInitialLoadComplete) return;

    pendingEditRef.current = undefined;
    const message = messages[messages.length - 1 - editedMessage.indexFromEnd];
    if (message?.isOutgoing && message.text === editedMessage.text) setEditingMessageId(message.id);
  }, [isInitialLoadComplete, messages, setEditingMessageId]);

  const shouldRestoreFocusRef = useRef(initialSessionRef.current?.isInputFocused);
  useEffect(() => {
    const input = inputRef.current;
    if (!shouldRestoreFocusRef.current || !isActive || isInputDisabled || !input) return;

    shouldRestoreFocusRef.current = false;
    requestMeasure(() => focusAtEnd(input));
  }, [isActive, isInputDisabled]);

  // On a desktop a chat opens with its field focused, as in Telegram, while a touch screen keeps its keyboard down
  // until the field is tapped. A modal or the lock screen over the Agent keeps the focus.
  const shouldFocusOnOpenRef = useRef(!IS_TOUCH_ENV && !shouldRestoreFocusRef.current);
  useEffect(() => {
    const input = inputRef.current;
    if (!shouldFocusOnOpenRef.current || !isActive || !input) return;

    shouldFocusOnOpenRef.current = false;
    requestMeasure(() => {
      if (getIsAnyModalOpen() || getGlobal().isAppLockActive) return;
      focusAtEnd(input);
    });
  }, [isActive, shouldHideComposer]);

  const shouldKeepPlaceOffScreen = session?.shouldKeepPlaceOffScreen;
  const keepPlace = useLastCallback(() => {
    const element = messagesRef.current;
    const isQuestionPinned = isFollowSuppressedRef.current && !isLiveTailPending && liveTailMessageId !== undefined;
    // A chat still loading its history keeps the place it mounted with
    const {
      isQuestionPinned: isQuestionInitiallyPinned, scrollAnchor: initialScrollAnchor, isPlaced: isInitiallyPlaced,
    } = initialSessionRef.current ?? {};
    switchedLayoutRef.current = {
      isInputFocused: Boolean(inputRef.current) && document.activeElement === inputRef.current,
      isQuestionPinned: isReadyToShow ? isQuestionPinned || undefined : isQuestionInitiallyPinned,
      scrollAnchor: !isReadyToShow ? initialScrollAnchor : element && !isQuestionPinned && !isAtBottomRef.current
        ? findScrollAnchor(element, messages, shouldKeepPlaceOffScreen)
        : undefined,
      isPlaced: isReadyToShow || isInitiallyPlaced,
    };
    saveSession?.(buildSession());
  });

  useAgentLayoutSwitch(keepPlace, Boolean(saveSession) && isActive);

  useEffect(() => {
    if (!isActive && shouldKeepPlaceOffScreen) requestMeasure(keepPlace);
  }, [isActive, keepPlace, shouldKeepPlaceOffScreen]);

  const handleHintClick = useLastCallback((hint: AgentHint, button: HTMLElement) => {
    if (document.activeElement) (document.activeElement as HTMLElement).blur();

    // Sending measures the list, which is not allowed in a mutation phase. The hint turns into the chat's first
    // question as a follow-up turns into its question.
    requestMeasure(() => {
      replaceSentSource(captureTappedSuggestion(button));
      requestLiveTail();
      onSendHint!(hint);
    });
  });

  const openConversationReport = useLastCallback(() => {
    setReportTarget({});
  });

  const openMessageReport = useLastCallback((messageId: number) => {
    setReportTarget({ messageId });
  });

  const closeReport = useLastCallback(() => {
    setReportTarget(undefined);
  });

  const handleSubmitReport = useLastCallback((comment: string) => {
    return onReportProblem!(reportTarget?.messageId, comment);
  });

  const handleMessageLinkClick = useLastCallback((event: React.MouseEvent<HTMLDivElement>) => {
    const target = event.target as HTMLElement;
    const href = target.closest('a')?.getAttribute('href');
    if (href?.startsWith(SELF_PROTOCOL)) {
      stopEvent(event);
      void processDeeplink(href);
      return;
    }
    if (!href?.startsWith('https://')) return;
    stopEvent(event);
    void openUrl(href);
  });

  useEffect(() => {
    if (!isActive || !onExternalScroll || !messagesRef.current) return;
    const element = messagesRef.current;
    const syntheticEvent = {
      target: element,
      currentTarget: element,
    } as unknown as React.UIEvent<HTMLDivElement>;
    onExternalScroll(syntheticEvent);
  }, [isActive, onExternalScroll]);

  useEffect(() => {
    const element = messagesRef.current;
    if (!isActive || !isReadyToShow || !hasMessageList || !onMessageVisible || !element) return undefined;

    let observer: IntersectionObserver | undefined;
    let isCancelled = false;
    requestMeasure(() => {
      if (isCancelled) return;
      const headerElement = element.parentElement!.querySelector<HTMLElement>(HEADER_SELECTOR)!;
      const topInset = Math.max(0, headerElement.getBoundingClientRect().bottom - element.getBoundingClientRect().top);
      observer = new IntersectionObserver((entries) => {
        if (isCancelled) return;
        entries.forEach((entry) => {
          if (!entry.isIntersecting || !entry.intersectionRect.height) return;
          onMessageVisible(Number((entry.target as HTMLElement).dataset.agentV2MessageId));
        });
      }, { root: element, rootMargin: `-${topInset}px 0px 0px 0px` });
      element.querySelectorAll(MESSAGE_ELEMENT_SELECTOR).forEach((message) => observer!.observe(message));
    });
    return () => {
      isCancelled = true;
      observer?.disconnect();
    };
  }, [hasMessageList, isActive, isReadyToShow, onMessageVisible, viewportIds]);

  // The field grows with its text up to `INPUT_HEADER_CLEARANCE` short of the header, wherever the chat's size puts it
  useEffect(() => {
    const root = rootRef.current;
    const header = root?.querySelector<HTMLElement>(HEADER_SELECTOR);
    if (!root || !header || !hasComposer) return undefined;

    const updateInputMaxHeight = () => {
      requestMeasure(() => {
        const input = inputRef.current;
        if (!input?.isConnected) return;

        const room = input.getBoundingClientRect().bottom - header.getBoundingClientRect().bottom
          - INPUT_HEADER_CLEARANCE;
        const maxHeight = `${Math.max(INPUT_MIN_MAX_HEIGHT, Math.floor(room))}px`;
        requestMutation(() => {
          root.style.setProperty('--agent-input-max-height', maxHeight);
        });
      });
    };
    const observer = new ResizeObserver(updateInputMaxHeight);
    observer.observe(root);
    observer.observe(header);
    return () => observer.disconnect();
  }, [hasComposer, hasMessageList]);

  const handleComposerHeightChange = useLastCallback((height: number) => {
    const messagesElement = messagesRef.current;
    if (!messagesElement || !onComposerHeightChange) return;
    onComposerHeightChange(height, {
      messagesElement,
      // A sent question holds the list until the list has placed it, and one shown where it landed until the list takes
      // it up, so the field shrinking back after the send does not take the list to its end ahead of that, to come back
      // down when it does. On a slow device the field can shrink before the list has placed the question.
      getIsAtBottom: () => isAtBottomRef.current && !isLiveTailPendingRef.current
        && inPlaceScrollTimeoutRef.current === undefined,
      onTextRevealProgress: handleTextRevealProgress,
    });
  });

  const composerProps: AgentConversationComposerProps = {
    inputRef,
    inputValue,
    isDisabled: isInputDisabled,
    canStop,
    onStop,
    onInput: handleInput,
    onKeyDown: handleKeyDown,
    onSend: handleSend,
    onHeightChange: onComposerHeightChange ? handleComposerHeightChange : undefined,
    onRequestConsent,
  };

  function renderItem(id: string) {
    if (id.startsWith(UNREAD_ITEM_ID_PREFIX)) return <AgentUnreadDivider key={id} />;

    if (id.startsWith(DATE_ITEM_ID_PREFIX)) {
      const dateMessage = messagesById[Number(id.slice(DATE_ITEM_ID_PREFIX.length))];
      if (!dateMessage) return undefined;

      return <AgentDateLine key={id} timestamp={dateMessage.timestamp} isDayHeader={hasDailyDateLines} />;
    }

    const message = messagesById[Number(id)];
    if (!message) return undefined;

    return renderMessage(message, {
      shouldAnimateTextStreaming: shouldAnimate,
      textRevealPresentation: textRevealPresentations[message.id],
      // A sent question is carried into its place by the scroll, or comes out of what it was sent from, without a fade
      isJustAdded: Boolean(justAddedIds?.has(id)) && !(isLiveTailPending && message.id === liveTailMessageId)
        && message.id !== messengerQuestionId,
      onEditMessage: handleEditMessage,
      onReportMessage: onReportProblem ? openMessageReport : undefined,
      onTextRevealProgress: handleTextRevealProgress,
      onRequestLiveTail: requestLiveTail,
    });
  }

  // Each question with its answers renders as one turn element. Messages never move between these elements,
  // so switching the live tail to another turn does not remount any message.
  function renderTurns(ids: string[]) {
    const turns: TeactNode[] = [];
    let turnStartIndex = 0;

    ids.forEach((id, index) => {
      const turnId = turnIdByItemId[id];
      const nextId = ids[index + 1];
      if (nextId !== undefined && turnIdByItemId[nextId] === turnId) return;

      const isLastTurn = nextId === undefined;
      const isLiveTail = turnId === liveTailTurnId;
      turns.push(
        <div
          key={turnId}
          ref={isLiveTail ? liveTailRef : undefined}
          className={buildClassName(styles.turn, isLiveTail && styles.liveTail)}
          teactFastList
        >
          {ids.slice(turnStartIndex, index + 1).map(renderItem)}
          {isLastTurn && isViewportAtEnd && messageListFooter}
          {isLastTurn && isViewportAtEnd && renderFailureLine()}
          {isLastTurn && dissolveGap && (
            <div
              key="dissolve-gap"
              ref={dissolveGapRef}
              className={styles.dissolveGap}
              style={`height: ${dissolveGap.initialHeight}px`}
              aria-hidden
            />
          )}
        </div>,
      );
      turnStartIndex = index + 1;
    });

    return turns;
  }

  function renderFailureLine() {
    if (!loadFailure) return undefined;

    return (
      <div key="load-failure" className={styles.loadFailureLine}>
        <AgentFailureCaption
          text={loadFailure.text}
          isRetryDisabled={loadFailure.isRetrying}
          onRetry={loadFailure.onRetry}
        />
      </div>
    );
  }

  function renderEmptyList() {
    if (loadFailure) return <AgentLoadFailure {...loadFailure} />;

    return <div className={styles.emptyText}>{emptyText}</div>;
  }

  if (!hasMessageList) {
    // A chat with nothing to show after its load keeps its menu, so it can still be deleted
    const isEmpty = conversationSlot === undefined;

    return (
      <div className={styles.root}>
        <AgentHeader
          isMenuVisible={isEmpty && header?.hasMenu}
          title={header?.title}
          icon={header?.icon}
          onBack={header?.hasBackButton ? onBack : undefined}
          onDelete={isEmpty ? onDelete : undefined}
          onOpenDigestSettings={onOpenDigestSettings}
        />
        {isEmpty ? renderEmptyList() : conversationSlot}
      </div>
    );
  }

  return (
    <div ref={rootRef} className={styles.root} data-agent-conversation>
      <AgentHeader
        isScrolled={isScrolled}
        isMenuVisible={header?.hasMenu}
        title={header?.title}
        icon={header?.icon}
        subtitle={header?.subtitle}
        onBack={header?.hasBackButton ? onBack : undefined}
        // The conversation can be reported from the start, its history loading or its thread still being created
        onReportProblem={onReportProblem ? openConversationReport : undefined}
        onDelete={onDelete}
        onOpenDigestSettings={onOpenDigestSettings}
      />

      {hasHistoryPlaceholder && (
        <AgentMessagesSkeleton
          isOpen={!isReadyToShow}
          isNewsFeed={isNewsPlaceholder}
          layout={historyPlaceholderLayout}
          onClosed={handlePlaceholderClosed}
        />
      )}
      {hasHistoryPlaceholder && !isPlaceholderGone && (
        <div ref={historyRevealLayerRef} className={styles.historyRevealLayer} aria-hidden />
      )}

      <InfiniteScroll
        ref={messagesRef}
        className={buildClassName(
          styles.messages,
          hasHistoryPlaceholder && !isPlaceholderGone && styles.messagesOverPlaceholder,
          !isReadyToShow && styles.hidden,
          areMessagesDissolving && styles.messagesDissolving,
          !hasComposer && styles.messagesWithoutComposer,
          areDateLinesSticky && styles.messagesStickyDates,
          'custom-scroll',
        )}
        items={viewportIds}
        itemSelector={MESSAGE_LIST_ITEM_SELECTOR}
        loadMoreStrategy={shouldUseContinuousHistory ? 'scrollDirection' : 'anchorMovement'}
        preloadBackwards={PRELOAD_BACKWARD_SLICE}
        getIsNearTop={historyThresholdRowCount !== undefined ? getIsNearTopByRows : undefined}
        noScrollRestore={isLiveTailPending || isQuestionInPlace || isAnimatingScroll(messagesRef.current)}
        onLoadMore={getMore}
        onScroll={handleScroll}
        onClick={handleMessageLinkClick}
      >
        <div
          key="spacer"
          ref={spacerRef}
          className={styles.spacer}
          style={frozenSpacerHeight ? `min-height: ${frozenSpacerHeight}px` : undefined}
        />
        {viewportIds && renderTurns(viewportIds)}
        {(!viewportIds?.length || !isViewportAtEnd) && messageListFooter}
        {(!viewportIds?.length || !isViewportAtEnd) && renderFailureLine()}
        <AgentHints
          key="hints"
          isOpen={areHintsVisible}
          hints={hints}
          leavingFrame={leavingHintsFrame}
          onHintClick={handleHintClick}
        />
      </InfiniteScroll>

      {/* Over the messages, so that those on screen stay where they are while older ones load */}
      {shouldShowHistorySpinner && <Spinner className={styles.historySpinner} />}

      {hasComposer && !shouldHideComposer && beforeComposerSlot}
      {hasComposer && !shouldHideComposer && (
        renderComposer ? renderComposer(composerProps) : <AgentInputBar {...composerProps} />
      )}
      {!hasComposer && <div className={styles.bottomFade} aria-hidden />}

      <div ref={motionLayerRef} className={styles.motionLayer} aria-hidden />

      <AgentEdgeGlow isActive={isActive && isThinking} animationLevel={animationLevel} />

      <ScrollToBottomButton
        className={hasComposer ? styles.scrollToBottom : styles.scrollToBottomWithoutComposer}
        isVisible={isScrolledUp}
        onClick={handleScrollToBottomClick}
      />

      <ReportAgentProblemModal
        isOpen={Boolean(reportTarget && onReportProblem)}
        onClose={closeReport}
        onSubmit={handleSubmitReport}
      />
    </div>
  );
}

export default memo(AgentConversationShell);

function getLastOutgoingMessage(messages: AgentMessage[]) {
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].isOutgoing) return messages[i];
  }

  return undefined;
}

// Only items after the previous last item are new. Items prepended by history loading are not.
function getAppendedIds(ids: string[], prevIds: string[]) {
  if (!prevIds.length) return new Set(ids);

  const prevLastIndex = ids.lastIndexOf(prevIds[prevIds.length - 1]);
  return prevLastIndex === -1 ? undefined : new Set(ids.slice(prevLastIndex + 1));
}

// The live tail is about as tall as the list, so scrolling to its end puts the pinned question near the top
function getLiveTailScrollTop(container: HTMLElement) {
  const liveTail = container.querySelector<HTMLElement>(`.${styles.liveTail}`);
  if (!liveTail) return getBottomScrollTop(container);

  const liveTailBottom = liveTail.getBoundingClientRect().bottom
    - container.getBoundingClientRect().top
    + container.scrollTop;

  const paddingBottom = parseFloat(getComputedStyle(container).paddingBottom) || 0;

  return liveTailBottom + paddingBottom - container.clientHeight;
}

/** Returns where the last answer's follow-ups begin in the list's content */
function getFollowupsTop(container?: HTMLElement) {
  const rows = container?.querySelectorAll<HTMLElement>(FOLLOWUP_ROW_SELECTOR);
  const row = rows?.[rows.length - 1];
  if (!container || !row) return undefined;

  return row.getBoundingClientRect().top - container.getBoundingClientRect().top + container.scrollTop;
}

/** Whether a sent question fits on the screen in the place of the follow-ups it was sent from, at `contentTop` */
function getIsQuestionInPlace(container: HTMLElement, bubble: HTMLElement, contentTop: number) {
  if (!bubble.animate) return false;

  const { top: visibleTop, bottom: visibleBottom } = getVisibleBounds(container);
  const top = container.getBoundingClientRect().top + contentTop - container.scrollTop;
  return top >= visibleTop && top + bubble.offsetHeight <= visibleBottom;
}

/**
 * A sent question appears in the place of the follow-ups it was sent from, as Android's message cell grows in: its
 * bubble scales up from 0.8 as it fades in, while the follow-ups give their space back
 */
function animateQuestionInPlace(bubble: HTMLElement) {
  if (!bubble.animate) return;

  bubble.animate([
    { transform: `scale(${QUESTION_IN_PLACE_SCALE})`, opacity: 0 },
    { transform: 'none', opacity: 1 },
  ], { duration: QUESTION_IN_PLACE_DURATION, easing: 'ease-out' });
}

function discardSentSource(source: SentQuestionSource) {
  if (source.kind === 'field') removeSentTextPicture(source.picture);
}

function findFollowupButton(container: HTMLElement | undefined, followupId: string) {
  const buttons = Array.from(container?.querySelectorAll<HTMLElement>(FOLLOWUP_BUTTON_SELECTOR) ?? []);
  return buttons.reverse().find((button) => button.dataset.agentFollowupId === followupId);
}

/** The question's message, its bubble and its text, once the list shows them */
function findQuestion(container: HTMLElement, messageId: number) {
  const message = container.querySelector<HTMLElement>(`[data-agent-v2-message-id="${messageId}"]`);
  const text = message?.querySelector<HTMLElement>(QUESTION_TEXT_SELECTOR);
  const bubble = text?.parentElement;
  return message && text && bubble ? { message, bubble, text } : undefined;
}

/**
 * Whether a sent question shows whole on screen where it lands, `shift` higher than now, right under the turn before
 * it on screen too, as iOS tells whether its question shows in place
 */
function getIsQuestionShownInPlace(container: HTMLElement, message: HTMLElement, bubble: HTMLElement, shift: number) {
  const previous = message.parentElement?.previousElementSibling;
  if (!previous?.querySelector(MESSAGE_ELEMENT_SELECTOR)) return false;

  const { top: visibleTop, bottom: visibleBottom } = getVisibleBounds(container);
  const previousRect = previous.getBoundingClientRect();
  const rect = bubble.getBoundingClientRect();
  return previousRect.bottom - shift > visibleTop && previousRect.top < visibleBottom
    && rect.top - shift >= visibleTop && rect.bottom - shift <= visibleBottom + 0.5;
}

/** Where the hints of an empty chat stand in the list's content */
function measureHintsFrame(container?: HTMLElement): AgentHintsFrame | undefined {
  const hints = container?.querySelector<HTMLElement>(HINTS_SELECTOR);
  return hints ? { top: hints.offsetTop, left: hints.offsetLeft, width: hints.offsetWidth } : undefined;
}

/** Where the field's row starts, under which a flight out of the field passes once it is past it */
function getComposerTop(layer: HTMLElement) {
  return layer.parentElement?.querySelector('[data-agent-composer]')?.getBoundingClientRect().top;
}

/** The space the follow-ups under the last answer give back as they go */
function getFollowupsSpace(container?: HTMLElement) {
  const rows = container?.querySelectorAll<HTMLElement>(FOLLOWUP_ROW_SELECTOR);
  const row = rows?.[rows.length - 1];
  if (!row) return 0;

  return row.offsetHeight + (parseFloat(getComputedStyle(row).marginTop) || 0);
}

/** The part of the list's box that shows its content, between the header and the field */
function getVisibleBounds(container: HTMLElement) {
  const style = getComputedStyle(container);
  const rect = container.getBoundingClientRect();
  return {
    top: rect.top + (parseFloat(style.paddingTop) || 0),
    bottom: rect.bottom - (parseFloat(style.paddingBottom) || 0),
  };
}

/**
 * Returns the rise of a sent question from the input's edge into its place when the list stays where it is, as when
 * the first question of a chat is already at the top
 */
function measureQuestionFlyUp(container: HTMLElement, messageId: number) {
  const question = container.querySelector<HTMLElement>(`[data-agent-v2-message-id="${messageId}"]`);
  if (!question?.animate) return undefined;

  const maxScrollTop = Math.max(0, container.scrollHeight - container.clientHeight);
  const target = Math.min(Math.max(getLiveTailScrollTop(container), 0), maxScrollTop);
  if (Math.abs(target - container.scrollTop) >= 1) return undefined;

  const paddingBottom = parseFloat(getComputedStyle(container).paddingBottom) || 0;
  const visibleBottom = container.getBoundingClientRect().bottom - paddingBottom;
  const offset = visibleBottom - question.getBoundingClientRect().top;
  if (offset <= 1) return undefined;

  return () => {
    question.animate([
      { transform: `translateY(${offset}px)`, opacity: 0 },
      { transform: 'none', opacity: 1 },
    ], { duration: QUESTION_FLY_UP_DURATION, easing: 'ease-out' });
  };
}

/**
 * Where a send pins the question of the live tail, with the reserve under it reaching the bottom of the list. An
 * answer taller than the reserve keeps the question at the top of the list's content.
 */
function getPinnedLiveTailScrollTop(container: HTMLElement, liveTail: HTMLElement) {
  const containerStyle = getComputedStyle(container);
  const liveTailTop = liveTail.getBoundingClientRect().top - container.getBoundingClientRect().top
    + container.scrollTop;
  if (getTurnContentHeight(liveTail) < liveTail.offsetHeight) {
    const paddingBottom = parseFloat(containerStyle.paddingBottom) || 0;
    return liveTailTop + liveTail.offsetHeight + paddingBottom - container.clientHeight;
  }

  const paddingTop = parseFloat(containerStyle.paddingTop) || 0;
  const liveTailPaddingTop = parseFloat(getComputedStyle(liveTail).paddingTop) || 0;
  return liveTailTop + liveTailPaddingTop - paddingTop;
}

function getBottomScrollTop(container: HTMLElement) {
  return container.scrollHeight - container.clientHeight;
}

// The dissolving messages end the list. The first of them comes with the date line and the "New" line before it.
function findDissolvingElements(container: HTMLElement, messageIds: readonly number[]) {
  const message = container.querySelector<HTMLElement>(`[data-agent-v2-message-id="${messageIds[0]}"]`);
  if (!message) return undefined;

  const first = findLeadingLine(message);

  const elements: HTMLElement[] = [];
  for (let element: Element | null = first; element; element = element.nextElementSibling) {
    elements.push(element as HTMLElement);
  }
  for (let turn = first.parentElement?.nextElementSibling; turn?.classList.contains(styles.turn);
    turn = turn.nextElementSibling) {
    elements.push(...Array.from(turn.children) as HTMLElement[]);
  }

  return elements;
}

// The gap goes at once. Whatever moved because of it, such as the turns above when the list is scrolled to its end,
// starts where it stood and slides into its new place.
function closeDissolveGap(container: HTMLElement, gap: HTMLElement) {
  const turn = gap.parentElement!;
  let turnTopBefore = 0;

  requestMeasure(() => {
    turnTopBefore = turn.getBoundingClientRect().top;
  });

  requestMutation(() => {
    gap.style.height = '0';
  });

  requestForcedReflow(() => {
    const shift = turnTopBefore - turn.getBoundingClientRect().top;
    if (!shift) return undefined;

    const containerRect = container.getBoundingClientRect();
    const shiftedElements = (Array.from(container.children) as HTMLElement[]).filter((element) => {
      const { top, bottom } = element.getBoundingClientRect();
      return Math.max(bottom, bottom + shift) > containerRect.top && Math.min(top, top + shift) < containerRect.bottom;
    });

    return () => {
      shiftedElements.forEach((element) => {
        animateShift(element, 0, shift, DISSOLVE_GAP_CLOSE_DURATION);
      });
    };
  });
}

function findDissolvingFooter(container: HTMLElement) {
  const footer = container.querySelector<HTMLElement>('[data-agent-list-footer]');
  return footer ? [footer] : undefined;
}

function getIsInView(element: HTMLElement, containerRect: DOMRect) {
  const { top, bottom } = element.getBoundingClientRect();
  return bottom > containerRect.top && top < containerRect.bottom;
}

// The turn's own height includes its reserve, so the content height comes from where its last child ends
function getTurnContentHeight(turn: HTMLElement) {
  const lastChild = turn.lastElementChild;
  if (!lastChild) return 0;

  return lastChild.getBoundingClientRect().bottom - turn.getBoundingClientRect().top;
}

interface HistoryReveal {
  /**
   * The bubbles on screen, each growing out of the rectangle of its placeholder or of one made up for it, in the
   * layer's coordinates. A stand-in with the bubble's corners, fill and tail grows in its place under it, so that the
   * corners and the tail keep their size whatever the rectangle, while the bubble shows only its contents.
   */
  morphs: {
    bubble: HTMLElement;
    source: MotionRect;
    sourceColor: string;
    targetColor: string;
    /** The corners it starts with, the placeholder's, and those it ends with, the bubble's */
    sourceRadii: string[];
    radii: string[];
    tail: HistoryRevealTail;
    /** The placeholder's tail, where it hangs on the other side from the bubble's, which gives way to it */
    sourceTail?: HistoryRevealTail;
    placeholder?: HTMLElement;
  }[];
  /** The placeholders that fade out, moving up by `shift` to above the messages */
  leavingPlaceholders: { element: HTMLElement; shift: number }[];
  /**
   * The date lines, the "New" line, and the parts of each message inside and outside its bubble. Each fades in to the
   * `opacity` it has in the stylesheet.
   */
  fades: { element: HTMLElement; opacity: string; delay: number; duration: number }[];
  /** The CSS entrances of the follow-up buttons, which are held back until the history has come in */
  followupAnimations: Animation[];
}

/** A bubble's tail as it stands at its bottom corner, which a stand-in takes as it is */
type HistoryRevealTail = Pick<
  CSSStyleDeclaration, 'width' | 'height' | 'left' | 'right' | 'bottom' | 'opacity' | 'transform' | 'transformOrigin'
> & { maskImage: string };

/** The history comes in out of the placeholders, as `planHistoryReveal` plans from where they and the messages stand */
function measureHistoryReveal(container: HTMLElement, layer: HTMLElement): HistoryReveal | undefined {
  const skeleton = container.parentElement?.querySelector<HTMLElement>(SKELETON_SELECTOR);
  if (!skeleton) return undefined;

  const containerRect = container.getBoundingClientRect();
  const containerStyle = getComputedStyle(container);
  const { top, bottom } = containerRect;
  const placeholders = Array.from(skeleton.querySelectorAll<HTMLElement>(PLACEHOLDER_SELECTOR))
    .map((element) => ({ element, frame: element.getBoundingClientRect() }))
    .sort((a, b) => b.frame.top - a.frame.top);
  const followupAnimations = Array.from(container.querySelectorAll(FOLLOWUP_BUTTON_SELECTOR))
    .flatMap((button) => button.getAnimations());
  const items = Array.from(container.querySelectorAll<HTMLElement>(`${MESSAGE_LIST_ITEM_SELECTOR}, ${MARKER_SELECTOR}`))
    .reverse()
    .filter((element) => {
      const rect = element.getBoundingClientRect();
      return rect.bottom > top && rect.top < bottom;
    });
  const messages = items.flatMap((element) => {
    if (element.matches(MARKER_SELECTOR)) return [];

    const bubble = element.querySelector<HTMLElement>(`.${bubbleStyles.bubble}`) ?? element;
    const target = bubble.getBoundingClientRect();
    return target.width && target.height ? [{ element, bubble, target }] : [];
  });
  const plan = planHistoryReveal(
    placeholders.map(({ frame }) => frame),
    messages.map(({ element, target }) => ({ frame: target, isOutgoing: getRevealRole(element) === 'user' })),
    {
      top,
      bottom: bottom - (parseFloat(containerStyle.paddingBottom) || 0),
      left: containerRect.left + container.clientLeft,
      width: container.clientWidth,
      isRtl: containerStyle.direction === 'rtl',
    },
  );
  // A placeholder made up for a message takes the fill of the ones shown
  const placeholderColor = placeholders.length ? getComputedStyle(placeholders[0].element).backgroundColor : undefined;

  const reveal: HistoryReveal = {
    morphs: [], leavingPlaceholders: [], fades: [], followupAnimations,
  };
  items.forEach((element) => {
    if (element.matches(MARKER_SELECTOR)) {
      reveal.fades.push({
        element,
        opacity: getComputedStyle(element).opacity,
        delay: PLACEHOLDER_MORPH_DURATION,
        duration: HISTORY_FADE_DURATION,
      });
    }
  });
  const layerRect = layer.getBoundingClientRect();
  messages.forEach(({ element, bubble }, index) => {
    const { frame, placeholderIndex } = plan.sources[index];
    const placeholder = placeholderIndex !== undefined ? placeholders[placeholderIndex].element : undefined;
    const bubbleStyle = getComputedStyle(bubble);
    const tail = captureHistoryRevealTail(getComputedStyle(bubble, '::after'));
    const radii = getBorderRadii(bubbleStyle);
    const placeholderTail = placeholder && captureHistoryRevealTail(getComputedStyle(placeholder, '::after'));
    reveal.morphs.push({
      bubble,
      source: getLayerRect(frame, layerRect),
      sourceColor: placeholder
        ? getComputedStyle(placeholder).backgroundColor
        : placeholderColor ?? bubbleStyle.backgroundColor,
      targetColor: bubbleStyle.backgroundColor,
      sourceRadii: placeholder ? getBorderRadii(getComputedStyle(placeholder)) : radii,
      radii,
      tail,
      sourceTail: placeholderTail && (placeholderTail.left !== tail.left || placeholderTail.right !== tail.right)
        ? placeholderTail
        : undefined,
      placeholder,
    });
    measureHistoryFades(element, bubble, reveal);
  });
  plan.leavingPlaceholders.forEach(({ placeholderIndex, shift }) => {
    const { element, frame } = placeholders[placeholderIndex];
    if (frame.width && frame.height) reveal.leavingPlaceholders.push({ element, shift });
  });

  return reveal;
}

function getBorderRadii(style: CSSStyleDeclaration) {
  return [
    style.borderTopLeftRadius, style.borderTopRightRadius, style.borderBottomRightRadius, style.borderBottomLeftRadius,
  ];
}

function captureHistoryRevealTail(style: CSSStyleDeclaration): HistoryRevealTail {
  return {
    width: style.width,
    height: style.height,
    left: style.left,
    right: style.right,
    bottom: style.bottom,
    opacity: style.opacity,
    transform: style.transform,
    transformOrigin: style.transformOrigin,
    maskImage: style.getPropertyValue('mask-image') || style.getPropertyValue('-webkit-mask-image'),
  };
}

// The side a message stands on: the user's, or the Agent's and an operator's
function getRevealRole(element: HTMLElement) {
  const roleElement = element.matches(MESSAGE_ROLE_SELECTOR)
    ? element
    : element.querySelector<HTMLElement>(MESSAGE_ROLE_SELECTOR);
  return roleElement?.dataset.agentV2MessageRole === 'user' ? 'user' : 'assistant';
}

/**
 * Content inside a bubble fades in while the bubble is still growing. The rest of the message fades in after the
 * bubble reaches its final shape, except the follow-up buttons, whose own entrance waits until then.
 */
function measureHistoryFades(view: HTMLElement, bubble: HTMLElement, reveal: HistoryReveal) {
  Array.from(view.children).forEach((child) => {
    if (child.matches(FOLLOWUP_BUTTON_SELECTOR)) return;

    if (child === bubble || child.contains(bubble) || child.querySelector(FOLLOWUP_BUTTON_SELECTOR)) {
      measureHistoryFades(child as HTMLElement, bubble, reveal);
    } else {
      reveal.fades.push({
        element: child as HTMLElement,
        opacity: getComputedStyle(child).opacity,
        delay: bubble.contains(child) ? HISTORY_BUBBLE_CONTENT_FADE_DELAY : PLACEHOLDER_MORPH_DURATION,
        duration: HISTORY_FADE_DURATION,
      });
    }
  });
}

/** Starts the reveal, whose bubbles take over from their stand-ins once they have grown, which the result tells */
function startHistoryReveal({
  morphs, leavingPlaceholders, fades, followupAnimations,
}: HistoryReveal, layer: HTMLElement) {
  const animations: Animation[] = [];
  const growths = morphs.map(({
    bubble, source, sourceColor, targetColor, sourceRadii, radii, tail, sourceTail, placeholder,
  }, index) => {
    if (placeholder) setExtraStyles(placeholder, { opacity: '0', transition: 'none' });

    // The stand-in starts as the placeholder it takes shows. Its box moves and resizes from the placeholder's rectangle
    // to the bubble's, its corners and its tail at their own size, and its fill, which the tail takes, turns from the
    // placeholder's to the bubble's.
    const standIn = document.createElement('div');
    standIn.className = styles.historyRevealBubble;
    standIn.dataset.agentHistoryStandIn = String(index);
    bubble.dataset.agentHistoryRevealIndex = String(index);
    placeHistoryRevealBox(standIn, bubble, source, source);
    const standInTail = createHistoryRevealTail(tail);
    standIn.appendChild(standInTail);
    if (sourceTail) {
      const placeholderTail = createHistoryRevealTail(sourceTail);
      standIn.appendChild(placeholderTail);
      animations.push(
        placeholderTail.animate([{ opacity: sourceTail.opacity }, { opacity: 0 }], {
          duration: PLACEHOLDER_MORPH_DURATION, easing: HISTORY_FADE_EASING, fill: 'both',
        }),
        standInTail.animate([{ opacity: 0 }, { opacity: tail.opacity }], {
          duration: PLACEHOLDER_MORPH_DURATION, easing: HISTORY_FADE_EASING, fill: 'both',
        }),
      );
    }
    layer.appendChild(standIn);
    // The reveal's animations hold their first frame before they start too: on a slow device a resumed animation can
    // stand a frame before its start, which would otherwise leave the stand-ins bare and show the bubbles' fill.
    // The corners keep the reveal's time, which the box keeps too.
    const clock = standIn.animate([{ borderRadius: sourceRadii.join(' ') }, { borderRadius: radii.join(' ') }], {
      duration: PLACEHOLDER_MORPH_DURATION, easing: HISTORY_MORPH_EASING, fill: 'both',
    });
    // The bubble shows only its contents, which fade in over the stand-in, and its tail takes its fill
    const bubbleFill = bubble.animate([{ backgroundColor: 'transparent' }, { backgroundColor: 'transparent' }], {
      duration: PLACEHOLDER_MORPH_DURATION, fill: 'both',
    });
    const fill = standIn.animate([{ backgroundColor: sourceColor }, { backgroundColor: targetColor }], {
      duration: PLACEHOLDER_MORPH_DURATION, easing: HISTORY_FADE_EASING, fill: 'both',
    });
    animations.push(clock, bubbleFill, fill);

    return {
      bubble, standIn, source, clock, bubbleFill,
    };
  });

  leavingPlaceholders.forEach(({ element, shift }) => {
    // The placeholder's own fade on closing would cut this one short
    setExtraStyles(element, { transition: 'none' });
    animations.push(element.animate([
      { transform: 'none', opacity: 1 },
      { transform: `translateY(${shift}px)`, opacity: 0 },
    ], {
      duration: PLACEHOLDER_MORPH_DURATION,
      easing: shift ? HISTORY_MORPH_EASING : HISTORY_FADE_EASING,
      fill: 'both',
    }));
  });

  fades.forEach(({
    element, opacity, delay, duration,
  }) => {
    animations.push(element.animate([{ opacity: 0 }, { opacity }], {
      duration, delay, easing: HISTORY_FADE_EASING, fill: 'backwards',
    }));
  });

  followupAnimations.forEach((animation) => {
    animation.currentTime = -PLACEHOLDER_MORPH_DURATION;
    animations.push(animation);
  });

  // The frame that brings the history on screen can take long to draw. Everything stands as the placeholders did until
  // it has been drawn, so the reveal plays from its start on screen rather than from where its time has gone meanwhile.
  animations.forEach((animation) => animation.pause());
  requestMeasure(() => {
    requestMeasure(() => {
      animations.forEach((animation) => animation.play());
    });
  });

  // Each box goes from its placeholder to where its bubble stands in that frame, which the list can still move as it
  // settles, so it lands on its bubble. Once grown, the boxes hold their bubbles' rectangles for a few frames, and the
  // bubbles take over where they stand.
  return new Promise<void>((resolve) => {
    let grownFrameCount = 0;
    animate(() => {
      const layerRect = layer.getBoundingClientRect();
      const frames = growths.map(({ bubble, source, clock }) => {
        const target = getLayerRect(bubble.getBoundingClientRect(), layerRect);
        const time = typeof clock.currentTime === 'number' ? clock.currentTime : 0;
        const progress = getTelegramProgress(time / PLACEHOLDER_MORPH_DURATION);
        return { target, frame: interpolateRect(source, target, progress) };
      });
      if (growths.every(({ clock }) => clock.playState === 'finished')) grownFrameCount += 1;
      const isHandedOver = grownFrameCount > HISTORY_HANDOVER_FRAMES || !layer.isConnected;

      requestMutation(() => {
        growths.forEach(({ bubble, standIn, bubbleFill }, index) => {
          if (!isHandedOver) {
            placeHistoryRevealBox(standIn, bubble, frames[index].frame, frames[index].target);
            return;
          }

          bubbleFill.cancel();
          setExtraStyles(bubble, { clipPath: '' });
          delete bubble.dataset.agentHistoryRevealIndex;
          standIn.remove();
        });
        if (isHandedOver) resolve();
      });

      return !isHandedOver;
    }, requestMeasure);
  });
}

// The stand-in's box at `frame`, and the bubble standing at `target` shows only what of its contents lies in that box
function placeHistoryRevealBox(standIn: HTMLElement, bubble: HTMLElement, frame: MotionRect, target: MotionRect) {
  standIn.style.transform = `translate(${frame.left}px, ${frame.top}px)`;
  standIn.style.width = `${frame.width}px`;
  standIn.style.height = `${frame.height}px`;
  const top = frame.top - target.top;
  const left = frame.left - target.left;
  const right = target.left + target.width - frame.left - frame.width;
  const bottom = target.top + target.height - frame.top - frame.height;
  setExtraStyles(bubble, { clipPath: `inset(${top}px ${right}px ${bottom}px ${left}px)` });
}

function getLayerRect(rect: MotionRect, layerRect: DOMRect): MotionRect {
  return {
    left: rect.left - layerRect.left, top: rect.top - layerRect.top, width: rect.width, height: rect.height,
  };
}

// A tail of a stand-in, at its own size at the box's bottom corner, in the box's fill
function createHistoryRevealTail(tail: HistoryRevealTail) {
  const element = document.createElement('div');
  element.className = styles.historyRevealTail;
  Object.assign(element.style, {
    width: tail.width,
    height: tail.height,
    left: tail.left,
    right: tail.right,
    bottom: tail.bottom,
    opacity: tail.opacity,
    transform: tail.transform,
    transformOrigin: tail.transformOrigin,
  });
  element.style.setProperty('mask-image', tail.maskImage);
  element.style.setProperty('-webkit-mask-image', tail.maskImage);
  return element;
}

// Focus never scrolls the screens the field lies in, which may still be sliding in
function focusAtEnd(input: HTMLTextAreaElement) {
  input.focus({ preventScroll: true });
  input.setSelectionRange(input.value.length, input.value.length);
}

/**
 * The scroll position that opens the list at a message: the date line and the "New" line before it come first under
 * the header, where the list's first item stands
 */
function getOpeningScrollTop(container: HTMLElement, messageId: number) {
  const message = container.querySelector<HTMLElement>(`[data-agent-v2-message-id="${messageId}"]`);
  if (!message) return undefined;

  const target = findLeadingLine(message);
  const paddingTop = parseFloat(getComputedStyle(container).paddingTop) || 0;
  const marginTop = parseFloat(getComputedStyle(target).marginTop) || 0;
  return target.getBoundingClientRect().top - container.getBoundingClientRect().top + container.scrollTop
    - paddingTop - marginTop;
}

/** The days' lines stuck at the top of the list, or pushed past it by the end of their day, as in Telegram Web A */
function findStuckDateLines(container: HTMLElement) {
  const containerTop = container.getBoundingClientRect().top;
  // A sticky line's inset counts from the list's content edge, under its top padding
  const contentTop = containerTop + container.clientTop + (parseFloat(getComputedStyle(container).paddingTop) || 0);
  return Array.from(container.querySelectorAll<HTMLElement>(`.${styles.dateLineDayHeader}`)).filter((line) => {
    const { top, bottom } = line.getBoundingClientRect();
    const stuckTop = contentTop + (parseFloat(getComputedStyle(line).top) || 0);
    return bottom >= containerTop && top <= stuckTop + STUCK_DATE_LINE_TOLERANCE;
  });
}

/**
 * Whether at most `rowCount` rows lie wholly above the part of the list under the header, as Android's
 * `findFirstVisibleItemPosition` tells. A day's line stuck under the header counts where it stands in the list, right
 * above the row after it.
 */
function getIsWithinRowsOfTop(container: HTMLElement, rowCount: number) {
  const rows = container.querySelectorAll<HTMLElement>(`${MESSAGE_LIST_ITEM_SELECTOR}, ${MARKER_SELECTOR}`);
  const row = rows[rowCount];
  if (!row) return true;

  const nextRow = rows[rowCount + 1];
  const { bottom } = row.getBoundingClientRect();
  const rowBottom = nextRow ? Math.min(bottom, nextRow.getBoundingClientRect().top) : bottom;
  const header = container.parentElement!.querySelector<HTMLElement>(HEADER_SELECTOR)!;
  return rowBottom > header.getBoundingClientRect().bottom;
}

/** The topmost of the lines that come right before a message and belong to it, or the message without them */
function findLeadingLine(message: HTMLElement) {
  let first = message;
  let previous = first.previousElementSibling;
  while (previous instanceof HTMLElement && previous.matches(MARKER_SELECTOR)) {
    first = previous;
    previous = first.previousElementSibling;
  }

  return first;
}

/** The first message that reaches below the top of the list */
function findScrollAnchor(
  container: HTMLElement, messages: AgentMessage[], shouldKeepMessageId = false,
): AgentConversationSession['scrollAnchor'] {
  const { top } = container.getBoundingClientRect();
  for (const element of Array.from(container.querySelectorAll<HTMLElement>(MESSAGE_ELEMENT_SELECTOR))) {
    const rect = element.getBoundingClientRect();
    if (rect.bottom <= top) continue;

    const index = messages.findIndex(({ id }) => String(id) === element.dataset.agentV2MessageId);
    return index === -1 ? undefined : {
      ...(shouldKeepMessageId && { messageId: messages[index].id }),
      indexFromEnd: messages.length - 1 - index, offset: rect.top - top,
    };
  }

  return undefined;
}

/** The scroll position that puts the anchor's message where it was, once the list shows it */
function getScrollAnchorTop(
  container: HTMLElement, anchor: NonNullable<AgentConversationSession['scrollAnchor']>, messages: AgentMessage[],
) {
  const message = getScrollAnchorMessage(anchor, messages);
  const element = message && container.querySelector<HTMLElement>(`[data-agent-v2-message-id="${message.id}"]`);
  if (!element) return undefined;

  return element.getBoundingClientRect().top - container.getBoundingClientRect().top + container.scrollTop
    - anchor.offset;
}

function getScrollAnchorMessage(
  anchor: NonNullable<AgentConversationSession['scrollAnchor']>, messages: AgentMessage[],
) {
  const message = anchor.messageId !== undefined ? messages.find(({ id }) => id === anchor.messageId) : undefined;
  return message ?? messages[messages.length - 1 - anchor.indexFromEnd];
}

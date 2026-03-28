import React, {
  memo, useEffect, useLayoutEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { removeExtraClass, toggleExtraClass } from '../../lib/teact/teact-dom';
import { getActions, withGlobal } from '../../global';

import type { AgentHint, AgentMessage, AnimationLevel } from '../../global/types';
import { LoadMoreDirection } from '../../global/types';

import { ANIMATION_LEVEL_MIN } from '../../config';
import { requestForcedReflow, requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import { fetchAgentHints } from '../../util/agent/agentApi';
import buildClassName from '../../util/buildClassName';
import { formatHumanDay } from '../../util/dateFormat';
import { stopEvent } from '../../util/domEvents';
import { openUrl } from '../../util/openUrl';
import buildMessageIds, { DATE_ITEM_ID_PREFIX } from './helpers/buildMessageIds';

import { useDeviceScreen } from '../../hooks/useDeviceScreen';
import useFlag from '../../hooks/useFlag';
import useHistoryBack from '../../hooks/useHistoryBack';
import useInfiniteScroll from '../../hooks/useInfiniteScroll';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';
import useShowTransition from '../../hooks/useShowTransition';
import useAgentMessages from './hooks/useAgentMessages';
import useScrollResetOnResize from './hooks/useScrollResetOnResize';

import InfiniteScroll from '../ui/InfiniteScroll';
import AgentHeader from './AgentHeader';
import AgentHints from './AgentHints';
import AgentInputBar from './AgentInputBar';
import ClearAgentChatModal from './ClearAgentChatModal';
import MessageBubble, { MESSAGE_LIST_ITEM_SELECTOR } from './MessageBubble';
import ScrollToBottomButton from './ScrollToBottomButton';

import styles from './Agent.module.scss';

interface OwnProps {
  isActive: boolean;
  onScroll?: (e: React.UIEvent<HTMLDivElement>) => void;
}

interface StateProps {
  animationLevel: AnimationLevel;
  agentHints?: AgentHint[];
  agentMessageCount?: number;
}

const PRELOAD_BACKWARD_SLICE = 30;
const SCROLL_FLICKER_THRESHOLD = 10;
const SCROLL_BOTTOM_THRESHOLD = 100;
const CLOSE_HINTS_DURATION = 250;

function Agent({
  isActive, animationLevel, agentHints, agentMessageCount, onScroll: onExternalScroll,
}: OwnProps & StateProps) {
  const { setAgentHints, switchToWallet } = getActions();

  const lang = useLang();
  const { isPortrait } = useDeviceScreen();
  const [inputValue, setInputValue] = useState('');
  const [isScrolledUp, setIsScrolledUp] = useState(false);
  const [areHintsOpen, setAreHintsOpen] = useState(false);
  const [isConfirmClearOpen, openClearConfirm, closeClearConfirm] = useFlag();
  const [editingMessageId, setEditingMessageId] = useState<number | undefined>();

  const messagesRef = useRef<HTMLDivElement>();
  const inputRef = useRef<HTMLTextAreaElement>();
  const isAtBottomRef = useRef(true);
  // Number of remaining layout passes where we force scroll-to-bottom (set to 2 on send to cover both outgoing + reply renders)
  const stickToBottomLayoutPassesRef = useRef(0);
  // Hint prompt to send after hints close animation (see `onCloseAnimationEnd` from `useShowTransition`)
  const pendingHintPromptRef = useRef<string | undefined>();
  // Smooth only the first post-hint snap to avoid a large instant jump for long prompts
  const shouldSmoothNextStickToBottomRef = useRef(false);

  useHistoryBack({ isActive, onBack: switchToWallet });

  useScrollResetOnResize(messagesRef, isAtBottomRef);

  useLayoutEffect(() => {
    toggleExtraClass(document.documentElement, 'is-agent-active', isActive);

    return () => {
      removeExtraClass(document.documentElement, 'is-agent-active');
    };
  }, [isActive]);

  const {
    messages, isInitialLoadComplete,
    sendMessage, clearChat,
  } = useAgentMessages({ lang, agentMessageCount });

  const sendHintPrompt = useLastCallback((prompt: string, withAnimations?: true) => {
    isAtBottomRef.current = true;
    stickToBottomLayoutPassesRef.current = 2;
    shouldSmoothNextStickToBottomRef.current = !!withAnimations;
    sendMessage(prompt);
  });

  const flushPendingHintPrompt = useLastCallback(() => {
    const prompt = pendingHintPromptRef.current;
    pendingHintPromptRef.current = undefined;
    if (!prompt) return;
    sendHintPrompt(prompt, true);
  });

  const { isScrolled, handleScroll: handleMessagesScroll, update: updateScrolledState } = useScrolledState();

  useShowTransition<HTMLDivElement>({
    ref: messagesRef,
    isOpen: areHintsOpen && Boolean(agentHints?.length),
    className: false,
    prefix: 'hints-',
    closeDuration: CLOSE_HINTS_DURATION,
    onCloseAnimationEnd: flushPendingHintPrompt,
  });

  // Open hints and reset scroll state when chat is empty on initial load or external clear
  useEffect(() => {
    if (isInitialLoadComplete && messages.length === 0) {
      setAreHintsOpen(true);
      setIsScrolledUp(false);
      isAtBottomRef.current = true;

      requestMeasure(() => {
        updateScrolledState(messagesRef.current);
      });
    }
  }, [isInitialLoadComplete, messages.length, updateScrolledState]);

  // Preserve referential stability of allIds — `buildMessageIds` always returns a new array,
  // but IDs only change when messages are added/removed, not when text is updated during streaming
  const allIdsRef = useRef<string[]>([]);
  const allIds = useMemo(() => {
    const ids = buildMessageIds(messages);
    const prev = allIdsRef.current;

    if (prev.length === ids.length && prev.every((id, i) => id === ids[i])) {
      return prev;
    }
    allIdsRef.current = ids;
    return ids;
  }, [messages]);

  const messagesByIdRef = useRef<Record<number, AgentMessage>>({});
  const messagesById = useMemo(() => {
    const prevById = messagesByIdRef.current;
    let changed = false;
    const byId: Record<number, AgentMessage> = {};

    for (const msg of messages) {
      byId[msg.id] = msg;
      if (prevById[msg.id] !== msg) {
        changed = true;
      }
    }

    if (!changed && Object.keys(prevById).length === messages.length) {
      return prevById;
    }

    messagesByIdRef.current = byId;
    return byId;
  }, [messages]);

  const [viewportIds, getMore, resetScroll] = useInfiniteScroll({
    listIds: allIds.length > 0 ? allIds : undefined,
    isActive,
    startFromEnd: true,
    shouldKeepViewportAtEnd: isAtBottomRef.current || stickToBottomLayoutPassesRef.current > 0,
  });

  // Ensure viewport always includes the latest messages
  const lastAllId = allIds[allIds.length - 1];
  const lastViewportId = viewportIds?.[viewportIds.length - 1];
  const isViewportAtEnd = !lastAllId || lastAllId === lastViewportId;

  useLayoutEffect(() => {
    if (isActive && isViewportAtEnd) {
      scrollToBottom();
    }
  }, [isActive, isViewportAtEnd]);

  useEffect(() => {
    if (!isActive || isViewportAtEnd || !isAtBottomRef.current) return;

    getMore?.({ direction: LoadMoreDirection.Backwards });
  }, [getMore, isActive, isViewportAtEnd, lastAllId, lastViewportId]);

  const scrollToBottom = useLastCallback((isSmooth?: boolean) => {
    requestMeasure(() => {
      const el = messagesRef.current;
      if (!el) return;

      const behavior = isSmooth && animationLevel !== ANIMATION_LEVEL_MIN ? 'smooth' : 'instant';
      el.scrollTo({ top: el.scrollHeight, behavior });
    });
  });

  const handleScrollToBottomClick = useLastCallback(() => {
    isAtBottomRef.current = true;
    setIsScrolledUp(false);

    if (!isViewportAtEnd) {
      resetScroll?.();
      scrollToBottom();
    } else {
      scrollToBottom(true);
    }
  });

  // `InfiniteScroll` restores `scrollTop` via `requestForcedReflow` *after* all `useLayoutEffects`, so a sync
  // scroll here would be overwritten. Enqueue stick-to-bottom in the same reflow queue, after its `resetScroll`.
  // Streaming may batch outgoing + first stream chunk in one commit (one layout pass); Teact fast list can still
  // grow `scrollHeight` on the next fasterdom frames — extra `requestMutation` snaps cover that gap.
  useLayoutEffect(() => {
    const useFollowUpSnaps = stickToBottomLayoutPassesRef.current > 0;
    if (useFollowUpSnaps) {
      stickToBottomLayoutPassesRef.current -= 1;
    }
    const shouldStickToBottom = useFollowUpSnaps || isAtBottomRef.current;
    if (!shouldStickToBottom) return;

    requestForcedReflow(() => {
      const el = messagesRef.current;
      const scrollHeight = el?.scrollHeight;

      return () => {
        if (!el || scrollHeight === undefined) return;

        if (shouldSmoothNextStickToBottomRef.current && animationLevel !== ANIMATION_LEVEL_MIN) {
          shouldSmoothNextStickToBottomRef.current = false;
          requestMeasure(() => scrollToBottom(true));
        } else {
          el.scrollTop = scrollHeight;

          if (useFollowUpSnaps) {
            requestMeasure(scrollToBottom);
          }
        }
        isAtBottomRef.current = true;
      };
    });
  }, [animationLevel, messages, scrollToBottom]);

  useEffect(() => {
    void fetchAgentHints(lang.code).then((hints) => {
      if (hints) {
        setAgentHints({ hints });
      }
    });
  }, [lang.code]);

  const handleScroll = useLastCallback((e: React.UIEvent<HTMLDivElement>) => {
    const el = e.target as HTMLDivElement;
    isAtBottomRef.current = el.scrollHeight - el.scrollTop - el.clientHeight < SCROLL_FLICKER_THRESHOLD;
    setIsScrolledUp(el.scrollHeight - el.scrollTop - el.clientHeight > SCROLL_BOTTOM_THRESHOLD);
    handleMessagesScroll(e);
    onExternalScroll?.(e);
  });

  const handleSend = useLastCallback(() => {
    const text = inputValue.trim();
    if (!text) return;

    const messageId = editingMessageId;
    setInputValue('');
    setEditingMessageId(undefined);
    isAtBottomRef.current = true;
    stickToBottomLayoutPassesRef.current = 2;
    shouldSmoothNextStickToBottomRef.current = true;
    setAreHintsOpen(false);

    sendMessage(text, messageId);
  });

  const handleKeyDown = useLastCallback((e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      stopEvent(e);
      handleSend();
    }
  });

  const handleInput = useLastCallback((value: string) => {
    setInputValue(value);
    if (!value) {
      setEditingMessageId(undefined);
    }
  });

  const handleClearInput = useLastCallback(() => {
    handleInput('');
  });

  const handleEditMessage = useLastCallback((id: number, text: string) => {
    setInputValue(text);
    setEditingMessageId(id);

    requestAnimationFrame(() => {
      const el = inputRef.current;
      if (el) {
        el.focus();
        el.setSelectionRange(text.length, text.length);
      }
    });
  });

  const handleHintsToggle = useLastCallback(() => {
    setAreHintsOpen((prev) => {
      const next = !prev;
      if (next) {
        pendingHintPromptRef.current = undefined;
        scrollToBottom();
      }

      return next;
    });
  });

  const handleHintClick = useLastCallback((prompt: string) => {
    // Hide mobile keyboard before closing hints panel to avoid conflicting animations
    if (document.activeElement) {
      (document.activeElement as HTMLElement).blur();
    }
    setAreHintsOpen(false);

    if (animationLevel === ANIMATION_LEVEL_MIN) {
      pendingHintPromptRef.current = undefined;
      // `noCloseTransition` path does not call `onCloseAnimationEnd`; defer send to next mutation pass after close
      requestMutation(() => sendHintPrompt(prompt));
      return;
    }

    pendingHintPromptRef.current = prompt;
  });

  const handleConfirmClear = useLastCallback(() => {
    closeClearConfirm();
    setIsScrolledUp(false);
    clearChat();
  });

  const handleMessageLinkClick = useLastCallback((e: React.MouseEvent<HTMLDivElement>) => {
    const target = e.target as HTMLElement;
    const anchor = target.closest('a');
    if (!anchor) return;

    const href = anchor.getAttribute('href');
    if (!href) return;
    if (href.startsWith('https://')) {
      stopEvent(e);
      void openUrl(href);
    }
  });

  // Notify parent about scroll state when becoming active
  useEffect(() => {
    if (!isActive || !onExternalScroll || !messagesRef.current) return;

    const el = messagesRef.current;
    const syntheticEvent = { target: el, currentTarget: el } as unknown as React.UIEvent<HTMLDivElement>;
    onExternalScroll(syntheticEvent);
  }, [isActive, onExternalScroll]);

  function renderItem(id: string) {
    if (id.startsWith(DATE_ITEM_ID_PREFIX)) {
      const timestamp = Number(id.slice(DATE_ITEM_ID_PREFIX.length));

      return (
        <div key={id} className={styles.dateSeparator}>
          {formatHumanDay(lang, timestamp)}
        </div>
      );
    }

    const msg = messagesById[Number(id)];
    if (!msg) return undefined;

    return (
      <MessageBubble
        key={msg.id}
        message={msg}
        onEdit={handleEditMessage}
      />
    );
  }

  return (
    <div className={styles.root}>
      {isPortrait && (
        <AgentHeader isScrolled={isScrolled} isMenuVisible={messages.length > 0} onClearChat={openClearConfirm} />
      )}

      <InfiniteScroll
        ref={messagesRef}
        className={buildClassName(
          styles.messages,
          !isInitialLoadComplete && styles.hidden,
          'custom-scroll',
        )}
        items={viewportIds}
        itemSelector={MESSAGE_LIST_ITEM_SELECTOR}
        preloadBackwards={PRELOAD_BACKWARD_SLICE}
        noScrollRestore={stickToBottomLayoutPassesRef.current > 0}
        onLoadMore={getMore}
        onScroll={handleScroll}
        onClick={handleMessageLinkClick}
      >
        <div key="spacer" className={styles.spacer} />
        {viewportIds?.map(renderItem)}
        <AgentHints
          key="hints"
          isOpen={areHintsOpen}
          hints={agentHints}
          onHintClick={handleHintClick}
        />
      </InfiniteScroll>

      <AgentInputBar
        inputRef={inputRef}
        inputValue={inputValue}
        hints={agentHints}
        isScrolledUp={isScrolledUp}
        onInput={handleInput}
        onKeyDown={handleKeyDown}
        onSend={handleSend}
        onClearInput={handleClearInput}
        onHintsToggle={handleHintsToggle}
      />

      <ScrollToBottomButton
        isVisible={isScrolledUp}
        onClick={handleScrollToBottomClick}
      />

      <ClearAgentChatModal
        isOpen={isConfirmClearOpen}
        onClose={closeClearConfirm}
        onConfirm={handleConfirmClear}
      />
    </div>
  );
}

export default memo(withGlobal<OwnProps>((global): StateProps => {
  return {
    animationLevel: global.settings.animationLevel,
    agentHints: global.agentHints,
    agentMessageCount: global.agentMeta?.messageCount,
  };
})(Agent));

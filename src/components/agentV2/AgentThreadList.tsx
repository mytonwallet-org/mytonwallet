import React, {
  memo, useEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';

import type {
  AgentNewsFeedItemV2,
  AgentThreadListItemV2,
  AgentThreadSummaryV2,
} from '../../api/agentV2/protocol/types';
import type { AgentHint } from '../../global/types';

import { IS_EXTENSION } from '../../config';
import { requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import { getAgentV2LocalState } from '../../util/agent/agentV2LocalState';
import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { getIsInputMethodKey, stopEvent } from '../../util/domEvents';
import { SWIPE_DISABLED_CLASS_NAME } from '../../util/swipeController';
import { buildAgentThreadListSections } from './agentThreadListSections';
import { getIsAgentThreadUnread, subscribeToAgentThreadReadState } from './agentThreadReadState';
import useAgentSuggestions from './useAgentSuggestions';
import useAgentThreadListMotion from './useAgentThreadListMotion';
import { closeAgentThreadSwipe } from './useAgentThreadSwipe';

import useForceUpdate from '../../hooks/useForceUpdate';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';
import useAgentLayoutSwitch from '../agent/hooks/useAgentLayoutSwitch';
import useAgentV2Dictation, { getIsAgentDictationSupported } from '../agent/hooks/useAgentV2Dictation';

import AgentHeader from '../agent/AgentHeader';
import AgentHints from '../agent/AgentHints';
import AgentInputBar from '../agent/AgentInputBar';
import AgentNewsRow from './AgentNewsRow';
import { AgentDictationAnnouncement, AgentDictationNotice } from './AgentStatusNotice';
import AgentThreadListItem from './AgentThreadListItem';
import AgentThreadListSkeleton from './AgentThreadListSkeleton';

import styles from './AgentThreadList.module.scss';

interface OwnProps {
  /** The list is the screen on top; under an open chat it is hidden */
  isActive: boolean;
  items?: AgentThreadListItemV2[];
  /** The user changed the chats, as by a pin or a deletion, and the rows play the change out */
  isUserChange?: boolean;
  hasMore: boolean;
  /** What the Agent is doing in each chat that answers, as a localization key */
  activityLangKeys: Record<string, string>;
  latestNewsItem?: AgentNewsFeedItemV2;
  newsUnreadCount: number;
  onSelect: (threadId: string) => void;
  onOpenNews: NoneToVoidFunction;
  /**
   * A question typed under the list starts a new chat. One sent while composing a chat opens that chat in place of the
   * list, as on mobile.
   */
  onStartChat: (text: string, isInPlace: boolean) => void;
  onLoadMore: NoneToVoidFunction;
  onRename: (thread: AgentThreadSummaryV2) => void;
  onTogglePin: (thread: AgentThreadSummaryV2) => void;
  onDelete: (thread: AgentThreadSummaryV2) => void;
}

// How close to the end of the list the next page starts loading
const LOAD_MORE_THRESHOLD_PX = 200;
// A list left while composing a chat shows its chats again once it is out of sight
const COMPOSE_RESET_DELAY = 350;
const IS_DICTATION_SUPPORTED = getIsAgentDictationSupported();

function AgentThreadList({
  isActive,
  items,
  isUserChange,
  hasMore,
  activityLangKeys,
  latestNewsItem,
  newsUnreadCount,
  onSelect,
  onOpenNews,
  onStartChat,
  onLoadMore,
  onRename,
  onTogglePin,
  onDelete,
}: OwnProps) {
  const localState = useRef(getAgentV2LocalState()).current;
  const lang = useLang();
  const [switchedLayout] = useState(takeSwitchedLayout);
  const [draft, setDraft] = useState(localState.draftOnMount);
  // The list's field takes dictation as a chat's does; the transcript fills the draft, which then starts a new chat
  const handleTranscript = useLastCallback((text: string) => {
    setDraft((current) => (current.trim() ? `${current.trimEnd()} ${text}` : text));
  });
  const dictation = useAgentV2Dictation({ isActive, langCode: lang.code, onTranscript: handleTranscript });
  const {
    notice: dictationNotice, failure: dictationFailure, failureCount: dictationFailureCount,
    dismissNotice: dismissDictationNotice,
  } = dictation;

  // Typing makes a dictation notice about an earlier phrase stale
  const handleDraftInput = useLastCallback((value: string) => {
    if (dictationNotice) dismissDictationNotice();
    setDraft(value);
  });
  // Focusing the field turns the list into a new chat with its suggestions, as on mobile
  const [isComposing, setIsComposing] = useState(Boolean(switchedLayout?.isComposing));
  const isListEmpty = items?.length === 0;
  const shouldShowSuggestions = isComposing || isListEmpty;
  const suggestions = useAgentSuggestions(lang, isActive, shouldShowSuggestions);
  const rootRef = useRef<HTMLElement>();
  const inputRef = useRef<HTMLTextAreaElement>();

  const bodyRef = useRef<HTMLDivElement>();
  const { isScrolled, handleScroll: handleScrolledState } = useScrolledState();
  useAgentThreadListMotion(bodyRef, items, isUserChange);
  const forceUpdate = useForceUpdate();

  useEffect(() => {
    localState.draftOnMount = draft;
  }, [draft, localState]);

  useAgentLayoutSwitch(() => {
    // The effect that keeps the draft may not have run yet
    localState.draftOnMount = draft;
    localState.switchedLayoutOnMount = {
      isComposing,
      isInputFocused: Boolean(inputRef.current) && document.activeElement === inputRef.current,
      scrollTop: bodyRef.current?.scrollTop ?? 0,
    };
  }, isActive);

  // The field takes the focus it had in the other layout
  const shouldRestoreFocusRef = useRef(switchedLayout?.isInputFocused);
  useEffect(() => {
    const input = inputRef.current;
    if (!shouldRestoreFocusRef.current || !isActive || !input) return;

    shouldRestoreFocusRef.current = false;
    requestMeasure(() => input.focus());
  }, [isActive]);

  // The unread dots are read as the rows render
  useEffect(() => subscribeToAgentThreadReadState(forceUpdate), [forceUpdate]);

  const sections = useMemo(() => (items ? buildAgentThreadListSections(items, lang) : undefined), [items, lang]);

  // The rows come back to where the other layout showed them, once they have loaded again
  const restoredScrollTopRef = useRef(switchedLayout?.scrollTop);
  const hasRows = Boolean(sections);
  useEffect(() => {
    const body = bodyRef.current;
    const scrollTop = restoredScrollTopRef.current;
    if (!hasRows || !body || !scrollTop) return;

    restoredScrollTopRef.current = undefined;
    requestMutation(() => {
      body.scrollTop = scrollTop;
    });
  }, [hasRows]);

  const handleScroll = useLastCallback((e: React.UIEvent<HTMLDivElement>) => {
    handleScrolledState(e);
    closeAgentThreadSwipe();
    const { scrollTop, scrollHeight, clientHeight } = e.currentTarget;
    if (hasMore && scrollHeight - scrollTop - clientHeight < LOAD_MORE_THRESHOLD_PX) onLoadMore();
  });

  const endComposing = useLastCallback(() => {
    setIsComposing(false);
    inputRef.current?.blur();
  });

  const startChat = useLastCallback((text: string) => {
    const isInPlace = isComposing;
    // The field gives up the focus before the chat comes, which would hand it back as it closes
    inputRef.current?.blur();
    onStartChat(text, isInPlace);
  });

  const handleSend = useLastCallback(() => {
    const text = draft.trim();
    if (!text) return;
    setDraft('');
    startChat(text);
  });

  const handleDraftFocus = useLastCallback(() => {
    if (!isActive) return;
    closeAgentThreadSwipe();
    setIsComposing(true);
  });

  const handleSuggestionClick = useLastCallback((hint: AgentHint) => {
    startChat(hint.prompt);
  });

  // A tap beside the suggestions ends composing; the suggestions and the Agent mark keep it
  const handleComposeClick = useLastCallback((e: React.MouseEvent<HTMLDivElement>) => {
    if ((e.target as HTMLElement).closest('button, svg')) return;
    endComposing();
  });

  const handleInputHeightChange = useLastCallback((height: number) => {
    requestMutation(() => {
      rootRef.current?.style.setProperty('--agent-input-bar-height', `${height}px`);
    });
  });

  // Escape ends composing; in the extension it would close the popup otherwise
  useEffect(() => (isComposing && isActive ? captureKeyboardListeners({
    onEsc: { handler: endComposing, shouldPreventDefault: IS_EXTENSION },
  }) : undefined), [endComposing, isActive, isComposing]);

  useEffect(() => {
    if (isActive || !isComposing) return undefined;

    const timer = window.setTimeout(() => setIsComposing(false), COMPOSE_RESET_DELAY);
    return () => window.clearTimeout(timer);
  }, [isActive, isComposing]);

  const handleDraftKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    if (e.key !== 'Enter' || e.shiftKey || getIsInputMethodKey(e)) return;
    stopEvent(e);
    handleSend();
  });

  function renderBody() {
    const newsRow = (
      <AgentNewsRow
        key="news"
        latestItem={latestNewsItem}
        unreadCount={newsUnreadCount}
        onClick={onOpenNews}
      />
    );

    if (!sections) return undefined;

    return [
      newsRow,
      <div key="rows">
        {sections.map((section) => (
          <div key={section.key} className={styles.section}>
            <div className={styles.sectionTitle} data-agent-row-key={`section-${section.key}`}>{section.title}</div>
            {section.items.map((item) => (
              <AgentThreadListItem
                key={item.thread.id}
                item={item}
                isUnread={getIsAgentThreadUnread(item.thread)}
                activityLangKey={activityLangKeys[item.thread.id]}
                onSelect={onSelect}
                onRename={onRename}
                onTogglePin={onTogglePin}
                onDelete={onDelete}
              />
            ))}
          </div>
        ))}
      </div>,
    ];
  }

  return (
    // The swipe back of the chats' stack does not start here: the list is the bottom screen, and its rows swipe
    <section
      ref={rootRef}
      className={buildClassName(styles.root, SWIPE_DISABLED_CLASS_NAME)}
      aria-label={lang('Chats')}
      inert={!isActive}
    >
      <AgentHeader
        isScrolled={isScrolled && !isComposing}
        title={isComposing ? lang('New Chat') : lang('Agent')}
        onBack={isComposing ? endComposing : undefined}
      />
      <div
        ref={bodyRef}
        className={buildClassName(styles.body, (isComposing || !sections) && styles.bodyComposing, 'custom-scroll')}
        inert={isComposing || !sections}
        onScroll={handleScroll}
      >
        {renderBody()}
      </div>
      <AgentThreadListSkeleton isOpen={!sections && !isComposing} />
      <div
        className={buildClassName(
          styles.compose,
          shouldShowSuggestions && styles.composeActive,
          isListEmpty && !isComposing && styles.composeEmpty,
        )}
        onClick={isComposing ? handleComposeClick : undefined}
      >
        <div className={styles.composeSpacer} />
        <AgentHints isOpen={shouldShowSuggestions} hints={suggestions} onHintClick={handleSuggestionClick} />
      </div>
      <AgentInputBar
        inputRef={inputRef}
        inputValue={draft}
        dictation={IS_DICTATION_SUPPORTED ? dictation : undefined}
        dictationNotice={dictationNotice ? <AgentDictationNotice notice={dictationNotice} /> : undefined}
        dictationAnnouncement={dictationFailure
          ? <AgentDictationAnnouncement key={dictationFailureCount} failure={dictationFailure} />
          : undefined}
        onInput={handleDraftInput}
        onKeyDown={handleDraftKeyDown}
        onSend={handleSend}
        onFocus={handleDraftFocus}
        onHeightChange={handleInputHeightChange}
      />
    </section>
  );
}

export default memo(AgentThreadList);

function takeSwitchedLayout() {
  const localState = getAgentV2LocalState();
  const switchedLayout = localState.switchedLayoutOnMount;
  localState.switchedLayoutOnMount = undefined;
  return switchedLayout;
}

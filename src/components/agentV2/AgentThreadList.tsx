import React, {
  memo, useEffect, useLayoutEffect, useMemo, useRef, useState,
} from '../../lib/teact/teact';
import { getGlobal } from '../../global';

import type {
  AgentNewsFeedDigestV2,
  AgentNewsFeedItemV2,
  AgentThreadListItemV2,
  AgentThreadSummaryV2,
} from '../../api/agentV2/protocol/types';
import type { AgentHint } from '../../global/types';
import type { AgentV2StarterHintEntryPoint } from '../agent/hooks/agentV2RunController';

import { IS_EXTENSION } from '../../config';
import { requestForcedReflow, requestMeasure, requestMutation } from '../../lib/fasterdom/fasterdom';
import { getAgentV2LocalState } from '../../util/agent/agentV2LocalState';
import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { stopEvent } from '../../util/domEvents';
import { SWIPE_DISABLED_CLASS_NAME } from '../../util/swipeController';
import { IS_TOUCH_ENV } from '../../util/windowEnvironment';
import { getSecretPhraseWordList, hasSecretPhrase } from '../../api/agentV2/secretPhrase';
import { getReturnKeyAction, insertLineBreak } from '../agent/helpers/composerReturnKey';
import focusAtEnd from '../agent/helpers/focusAtEnd';
import getCanAnimate from '../agent/helpers/getCanAnimate';
import { createSnapGhost, getSnapEffectKind, getSnapEffectLayer } from '../agent/helpers/snapEffect';
import { startOpeningSuggestionMorph, startOpeningTextFlight } from './agentOpeningQuestion';
import { buildAgentThreadListSections } from './agentThreadListSections';
import { getIsAgentThreadUnread, subscribeToAgentThreadReadState } from './agentThreadReadState';
import useAgentSuggestions from './useAgentSuggestions';
import useAgentThreadListMotion from './useAgentThreadListMotion';
import { closeAgentThreadSwipe } from './useAgentThreadSwipe';

import useDerivedState from '../../hooks/useDerivedState';
import useForceUpdate from '../../hooks/useForceUpdate';
import { useHotkeys } from '../../hooks/useHotkeys';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useScrolledState from '../../hooks/useScrolledState';
import useSignal from '../../hooks/useSignal';
import { buildAgentV2StarterHintEntryPoint } from '../agent/hooks/agentV2RunController';
import useAgentLayoutSwitch from '../agent/hooks/useAgentLayoutSwitch';

import AgentHeader from '../agent/AgentHeader';
import AgentHints from '../agent/AgentHints';
import AgentLoadFailure from '../agent/AgentLoadFailure';
import { getIsAnyModalOpen } from '../ui/Modal';
import AgentNewsRow from './AgentNewsRow';
import { AgentFailureCaption } from './AgentStatusNotice';
import AgentThreadListItem from './AgentThreadListItem';
import AgentThreadListSkeleton from './AgentThreadListSkeleton';
import AgentV2Composer from './AgentV2Composer';

import styles from './AgentThreadList.module.scss';

interface OwnProps {
  /** The list is the screen on top; under an open chat it is hidden */
  isActive: boolean;
  /** The Agent is on screen, whichever of its screens is on top */
  isAgentActive: boolean;
  items?: AgentThreadListItemV2[];
  /** The user changed the chats, as by a pin or a deletion, and the rows play the change out */
  isUserChange?: boolean;
  /** Chats the user is deleting: their rows turn to dust at once and keep their place until the chats leave */
  dissolvingThreadIds?: ReadonlySet<string>;
  hasMore: boolean;
  /** The first page failed to load: empty lists show the failure in place; cached rows keep it below */
  hasLoadFailed?: boolean;
  /** The next page failed to load: the list ends with its failure line */
  hasPageLoadFailed?: boolean;
  isRetrying?: boolean;
  /** What the Agent is doing in each chat that answers, as a localization key */
  activityLangKeys: Record<string, string>;
  latestNewsItem?: AgentNewsFeedItemV2;
  /** In the Digests view, the latest digest, which the News row shows */
  latestNewsDigest?: AgentNewsFeedDigestV2;
  newsUnreadCount: number;
  /** The user has not allowed the Agent yet, so a question or a recording asks for consent first */
  isDictationHeld?: boolean;
  onSelect: (threadId: string) => void;
  onOpenNews: NoneToVoidFunction;
  /**
   * A question typed under the list starts a new chat. One sent while composing a chat opens that chat in place of the
   * list, as on mobile. A tapped suggestion comes with its `hintEntryPoint`.
   */
  onStartChat: (text: string, isInPlace: boolean, hintEntryPoint?: AgentV2StarterHintEntryPoint) => void;
  /**
   * Carries out what the user did that sends something to the Agent once they allow it: at once if they have, or
   * after the consent sheet's Allow. Closing the sheet drops it, and gives the `field` a question was sent from its
   * focus back.
   */
  onRequestConsent: (action: NoneToVoidFunction, field?: HTMLElement) => void;
  /** Contact Support, the suggestions' last item, which is disabled unless `canRequestSupport` */
  onRequestSupport?: NoneToVoidFunction;
  canRequestSupport?: boolean;
  onLoadMore: NoneToVoidFunction;
  /** Loads the chats again after they failed to load, or the page that failed */
  onRetry: NoneToVoidFunction;
  onRename: (thread: AgentThreadSummaryV2) => void;
  onTogglePin: (thread: AgentThreadSummaryV2) => void;
  onDelete: (thread: AgentThreadSummaryV2) => void;
}

// How close to the end of the list the next page starts loading
const LOAD_MORE_THRESHOLD_PX = 200;
// A list left while composing a chat shows its chats again once it is out of sight
const COMPOSE_RESET_DELAY = 350;
const NO_THREAD_IDS: ReadonlySet<string> = new Set();
const ROW_KEY_ATTRIBUTE = 'data-agent-row-key';
const SECTION_KEY_PREFIX = 'section-';

function AgentThreadList({
  isActive,
  isAgentActive,
  items,
  isUserChange,
  dissolvingThreadIds = NO_THREAD_IDS,
  hasMore,
  hasLoadFailed,
  hasPageLoadFailed,
  isRetrying,
  activityLangKeys,
  latestNewsItem,
  latestNewsDigest,
  newsUnreadCount,
  isDictationHeld,
  onSelect,
  onOpenNews,
  onStartChat,
  onRequestConsent,
  onRequestSupport,
  canRequestSupport = false,
  onLoadMore,
  onRetry,
  onRename,
  onTogglePin,
  onDelete,
}: OwnProps) {
  const localState = useRef(getAgentV2LocalState()).current;
  const lang = useLang();
  const [switchedLayout] = useState(takeSwitchedLayout);
  const [getDraft, setDraft] = useSignal(localState.draftOnMount);
  const draft = useDerivedState(getDraft);
  // A click into the field or typing in it turns the list into a new chat with its suggestions, as on mobile. Focus
  // alone keeps the chats, as the field takes it when the Agent opens.
  const [isComposing, setIsComposing] = useState(Boolean(switchedLayout?.isComposing));
  // Chats that failed to load show the failure in place of the suggestions, which would say there are none
  const isLoadFailureShown = Boolean(hasLoadFailed) && !items?.length;
  const isListEmpty = items?.length === 0 && !isLoadFailureShown;
  const shouldShowSuggestions = isComposing || isListEmpty;
  const suggestions = useAgentSuggestions(lang, isActive && shouldShowSuggestions);
  const rootRef = useRef<HTMLElement>();
  const inputRef = useRef<HTMLTextAreaElement>();

  const bodyRef = useRef<HTMLDivElement>();
  const { isScrolled, handleScroll: handleScrolledState } = useScrolledState();
  useAgentThreadListMotion(bodyRef, items, isUserChange);

  // A deleted chat's row turns to dust as soon as the user confirms, as Telegram's deleted messages do, or fades out
  // where dust isn't drawn, and its place closes once the chat leaves the list. The title of a section it leaves empty
  // goes with it. A deletion that fails shows the row again.
  const [dissolvedThreadIds, setDissolvedThreadIds] = useState<ReadonlySet<string>>(NO_THREAD_IDS);
  const previousDissolvingIdsRef = useRef(dissolvingThreadIds);
  useLayoutEffect(() => {
    const previousIds = previousDissolvingIdsRef.current;
    previousDissolvingIdsRef.current = dissolvingThreadIds;
    const addedIds = [...dissolvingThreadIds].filter((id) => !previousIds.has(id));
    const endedIds = [...previousIds].filter((id) => !dissolvingThreadIds.has(id));
    if (endedIds.length) {
      setDissolvedThreadIds((current) => new Set([...current].filter((id) => !endedIds.includes(id))));
    }
    if (!addedIds.length || !isActive) return;

    const kind = getSnapEffectKind(getCanAnimate());
    requestForcedReflow(() => {
      const body = bodyRef.current;
      if (!body) return undefined;

      const bodyRect = body.getBoundingClientRect();
      const rows = addedIds
        .map((id) => body.querySelector<HTMLElement>(`[${ROW_KEY_ATTRIBUTE}="${CSS.escape(id)}"]`))
        .filter((element): element is HTMLElement => Boolean(element));
      const ghosts = [...rows, ...findLeavingSectionTitles(rows, dissolvingThreadIds)]
        .filter((element) => {
          const rect = element.getBoundingClientRect();
          return rect.bottom > bodyRect.top && rect.top < bodyRect.bottom;
        })
        .map((element) => {
          const ghost = createSnapGhost(element, kind);
          // The copy is no row of the list, which finds its rows by this key
          ghost.querySelectorAll(`[${ROW_KEY_ATTRIBUTE}]`).forEach((copy) => copy.removeAttribute(ROW_KEY_ATTRIBUTE));
          return ghost;
        });

      return () => {
        const layer = getSnapEffectLayer();
        ghosts.forEach((ghost) => layer.appendChild(ghost));
        setDissolvedThreadIds((current) => new Set([...current, ...addedIds]));
      };
    });
  }, [dissolvingThreadIds, isActive]);
  const forceUpdate = useForceUpdate();

  // A save that comes after the app switched layouts keeps the draft typed since this render
  useEffect(() => {
    localState.draftOnMount = getDraft();
  }, [draft, getDraft, localState]);

  useAgentLayoutSwitch(() => {
    // A layout handoff can precede the render for the last input event
    localState.draftOnMount = getDraft();
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

  // On a desktop the Agent opens with the field focused, as a chat does, while a touch screen keeps its keyboard down.
  // Coming back from a chat leaves the focus on its row, and a modal or the lock screen over the Agent keeps it.
  const shouldFocusOnOpenRef = useRef(!IS_TOUCH_ENV && !shouldRestoreFocusRef.current);
  useEffect(() => {
    if (!isAgentActive) {
      shouldFocusOnOpenRef.current = !IS_TOUCH_ENV;
      return;
    }

    const input = inputRef.current;
    if (!shouldFocusOnOpenRef.current || !input) return;

    shouldFocusOnOpenRef.current = false;
    if (!isActive) return;

    requestMeasure(() => {
      if (getIsAnyModalOpen() || getGlobal().isAppLockActive) return;
      focusAtEnd(input);
    });
  }, [isActive, isAgentActive]);

  // While nothing on the page has focus, Tab starts at the field, as in a chat
  const handleTab = useLastCallback((e: KeyboardEvent) => {
    const input = inputRef.current;
    if (e.target !== document.body || !input || getIsAnyModalOpen() || getGlobal().isAppLockActive) return;

    e.preventDefault();
    focusAtEnd(input);
  });

  const hotkeysRef = useRef({ Tab: handleTab });
  useHotkeys(isActive ? hotkeysRef.current : undefined);

  // The unread dots are read as the rows render
  useEffect(() => subscribeToAgentThreadReadState(forceUpdate), [forceUpdate]);

  const sections = useMemo(() => (items ? buildAgentThreadListSections(items, lang) : undefined), [items, lang]);
  const hasBody = Boolean(sections) || isLoadFailureShown;

  // The rows come back to where the other layout showed them, once they have loaded again
  const restoredScrollTopRef = useRef(switchedLayout?.scrollTop);
  const hasRows = Boolean(sections);
  useEffect(() => {
    const body = bodyRef.current;
    const scrollTop = restoredScrollTopRef.current;
    if (!hasRows || !body || !scrollTop) return;

    restoredScrollTopRef.current = undefined;
    // The list scrolls smoothly (`.custom-scroll`), which would scroll the rows in from the top rather than restore them.
    // `scrollTo` lays the page out, so it runs here, in the measure phase.
    body.scrollTo({ top: scrollTop, behavior: 'instant' });
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

  const startChat = useLastCallback((text: string, hintEntryPoint?: AgentV2StarterHintEntryPoint) => {
    const isInPlace = isComposing;
    // The field gives up the focus before the chat comes, which would hand it back as it closes
    inputRef.current?.blur();
    onStartChat(text, isInPlace, hintEntryPoint);
  });

  const handleSend = useLastCallback(() => {
    const text = getDraft().trim();
    if (!text) return;
    // The question flies out of the field into the new chat's first bubble, as a question sent in a chat does. One with
    // secret words shows there without them, so it doesn't fly.
    if (inputRef.current && !hasSecretPhrase(text, getSecretPhraseWordList())) {
      startOpeningTextFlight(inputRef.current, text);
    }
    setDraft('');
    startChat(text);
  });

  const handleDraftFocus = useLastCallback(() => {
    if (!isActive) return;
    closeAgentThreadSwipe();
  });

  // A focused field gets the click too, and the field's own `input` events are the user's typing, not a transcript
  useEffect(() => {
    const input = inputRef.current;
    if (!input || !isActive || isComposing) return undefined;

    const startComposing = () => setIsComposing(true);
    input.addEventListener('click', startComposing);
    input.addEventListener('input', startComposing);
    return () => {
      input.removeEventListener('click', startComposing);
      input.removeEventListener('input', startComposing);
    };
  }, [isActive, isComposing]);

  const handleSuggestionClick = useLastCallback((hint: AgentHint, button: HTMLElement) => {
    const hintEntryPoint = suggestions && buildAgentV2StarterHintEntryPoint(suggestions.starterHints, hint.id);
    onRequestConsent(() => {
      startOpeningSuggestionMorph(button, hint.title);
      startChat(hint.title, hintEntryPoint);
    });
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
    const action = getReturnKeyAction(e);
    if (action !== 'send' && action !== 'lineBreak') return;

    stopEvent(e);
    if (action === 'lineBreak') {
      if (inputRef.current) insertLineBreak(inputRef.current);
      return;
    }
    handleSend();
  });

  function renderBody() {
    const newsRow = (
      <AgentNewsRow
        key="news"
        latestItem={latestNewsItem}
        latestDigest={latestNewsDigest}
        unreadCount={newsUnreadCount}
        onClick={onOpenNews}
      />
    );

    if (!hasBody) return undefined;

    return [
      newsRow,
      sections ? (
        <div key="rows">
          {sections.map((section) => (
            <div key={section.key} className={styles.section}>
              <div
                className={buildClassName(
                  styles.sectionTitle,
                  // A section whose every chat is deleted goes with them
                  section.items.every((item) => dissolvedThreadIds.has(item.thread.id)) && styles.dissolved,
                )}
                data-agent-row-key={`${SECTION_KEY_PREFIX}${section.key}`}
              >
                {section.title}
              </div>
              {section.items.map((item) => (
                <AgentThreadListItem
                  key={item.thread.id}
                  item={item}
                  support={item.thread.support}
                  isUnread={getIsAgentThreadUnread(item.thread)}
                  activityLangKey={activityLangKeys[item.thread.id]}
                  isDissolved={dissolvedThreadIds.has(item.thread.id)}
                  onSelect={onSelect}
                  onRename={onRename}
                  onTogglePin={onTogglePin}
                  onDelete={onDelete}
                />
              ))}
            </div>
          ))}
        </div>
      ) : undefined,
      // A chat's failure line, as the news feed ends with one when it fails to refresh
      (hasLoadFailed || hasPageLoadFailed) && items?.length ? (
        <div key="page-failure" className={styles.pageFailure}>
          <AgentFailureCaption text={lang('$agent_chats_unavailable')} onRetry={onRetry} />
        </div>
      ) : undefined,
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
        className={buildClassName(styles.body, (isComposing || !hasBody) && styles.bodyComposing, 'custom-scroll')}
        inert={isComposing || !hasBody}
        onScroll={handleScroll}
      >
        {renderBody()}
      </div>
      <AgentThreadListSkeleton isOpen={!hasBody && !isComposing} />
      {isLoadFailureShown && !isComposing && (
        <div className={styles.loadFailure}>
          <AgentLoadFailure text={lang('$agent_chats_unavailable')} isRetrying={isRetrying} onRetry={onRetry} />
        </div>
      )}
      <div
        className={buildClassName(
          styles.compose,
          shouldShowSuggestions && styles.composeActive,
          isListEmpty && !isComposing && styles.composeEmpty,
        )}
        onClick={isComposing ? handleComposeClick : undefined}
      >
        <div className={styles.composeSpacer} />
        <AgentHints
          isOpen={shouldShowSuggestions}
          hints={suggestions?.hints}
          isSupportDisabled={!canRequestSupport}
          onHintClick={handleSuggestionClick}
          onSupportClick={onRequestSupport}
        />
      </div>
      <AgentV2Composer
        inputRef={inputRef}
        inputValue={draft}
        isActive={isActive}
        isDisabled={false}
        onRequestConsent={isDictationHeld ? onRequestConsent : undefined}
        onInput={setDraft}
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

// The titles of the sections that have no chat left once the dissolving ones go
function findLeavingSectionTitles(rows: HTMLElement[], dissolvingThreadIds: ReadonlySet<string>) {
  const sections = new Set(rows.map((row) => row.parentElement));
  return [...sections]
    .filter((section): section is HTMLElement => Boolean(section))
    .filter((section) => Array.from(section.querySelectorAll(`[${ROW_KEY_ATTRIBUTE}]`)).every((element) => {
      const key = element.getAttribute(ROW_KEY_ATTRIBUTE)!;
      return key.startsWith(SECTION_KEY_PREFIX) || dissolvingThreadIds.has(key);
    }))
    .map((section) => section.querySelector<HTMLElement>(`[${ROW_KEY_ATTRIBUTE}^="${SECTION_KEY_PREFIX}"]`))
    .filter((title): title is HTMLElement => Boolean(title));
}

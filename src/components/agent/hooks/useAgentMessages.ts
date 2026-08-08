import { useEffect, useRef, useState } from '../../../lib/teact/teact';
import { getActions, getGlobal } from '../../../global';

import type { AgentMessage } from '../../../global/types';
import type { LangFn } from '../../../hooks/useLang';

import {
  selectCurrentAccountId, selectCurrentAccountState, selectCurrentAccountTokens, selectOrderedAccounts,
} from '../../../global/selectors';
import { buildRequestContext, createAgentStream } from '../../../util/agent/agentApi';
import { clearAgentChat, loadAgentMessages, saveAgentMessages } from '../../../util/agent/agentStorage';
import { logDebugError } from '../../../util/logs';

import useLastCallback from '../../../hooks/useLastCallback';
import useSyncEffect from '../../../hooks/useSyncEffect';

interface UseAgentMessagesProps {
  lang: LangFn;
  agentMessageCount?: number;
}

export interface TextRevealPresentation {
  key: string;
  status: 'active' | 'settled' | 'error';
  shouldRevealFromStart: boolean;
}

export type TextRevealPresentations = Record<number, TextRevealPresentation>;

export interface UseAgentMessagesResult {
  messages: AgentMessage[];
  isInitialLoadComplete: boolean;
  textRevealPresentations: TextRevealPresentations;
  sendMessage: (text: string, editMessageId?: number) => void;
  consumeTextRevealSession: (messageId: number, key: string) => void;
  settleTextRevealSession: (messageId: number, key: string) => void;
  clearChat: NoneToVoidFunction;
}

// Delay before starting the API stream, so app can render the outgoing message and typing indicator first
const STREAM_RENDER_DELAY_MS = 300;

export default function useAgentMessages({ lang, agentMessageCount }: UseAgentMessagesProps): UseAgentMessagesResult {
  const { setAgentMeta } = getActions();

  const [messages, setMessages] = useState<AgentMessage[]>([]);
  const [isSending, setIsSending] = useState(false);
  const [isInitialLoadComplete, setIsInitialLoadComplete] = useState(false);
  const [textRevealPresentations, setTextRevealPresentations] = useState<TextRevealPresentations>({});

  const nextIdRef = useRef(1);
  const textRevealSequenceRef = useRef(0);
  const abortRef = useRef<NoneToVoidFunction>();
  const pendingTextRef = useRef<{ id: number; text: string }>();
  /** rAF id for batching stream text updates, chunks arrive dozens of times per second, but we render once per frame */
  const textBatchRafRef = useRef<number>();
  /** Tracks previous `agentMessageCount` to detect external chat clears (e.g. from landscape Content menu) */
  const prevMessageCountRef = useRef(agentMessageCount);
  /** Incremented on each reset/clear: stale stream callbacks compare against this to discard outdated updates */
  const generationRef = useRef(0);

  function resetInternalState() {
    abortRef.current?.();
    abortRef.current = undefined;
    if (textBatchRafRef.current) {
      cancelAnimationFrame(textBatchRafRef.current);
      textBatchRafRef.current = undefined;
    }
    pendingTextRef.current = undefined;
    generationRef.current++;
    setMessages([]);
    setTextRevealPresentations({});
    nextIdRef.current = 1;
    setIsSending(false);
  }

  // Load messages from IDB on mount; cleanup on unmount
  useEffect(() => {
    void loadAgentMessages().then((saved) => {
      if (saved.length) {
        const lastMessage = saved[saved.length - 1];
        setMessages(saved);
        nextIdRef.current = lastMessage.id + 1;
        setAgentMeta({
          messageCount: saved.length,
          lastTimestamp: lastMessage.timestamp,
        });
      }

      setIsInitialLoadComplete(true);
    });

    return () => {
      abortRef.current?.();
      if (textBatchRafRef.current) {
        cancelAnimationFrame(textBatchRafRef.current);
      }
    };
  }, []);

  // React to external clear (e.g. from Content landscape menu)
  useSyncEffect(() => {
    const wasCleared = prevMessageCountRef.current !== undefined
      && prevMessageCountRef.current > 0
      && agentMessageCount === 0;
    prevMessageCountRef.current = agentMessageCount;

    if (wasCleared && messages.length > 0) {
      resetInternalState();
      setIsInitialLoadComplete(true);
    }
  }, [agentMessageCount, messages.length]);

  const persistMessages = useLastCallback((msgs: AgentMessage[]) => {
    void saveAgentMessages(msgs);
    setAgentMeta({
      messageCount: msgs.length,
      lastTimestamp: msgs.at(-1)?.timestamp,
    });
  });

  const sendMessage = useLastCallback((text: string, editMessageId?: number) => {
    if (isSending) return;

    let outId: number;
    let inId: number;
    let originalText: string | undefined;
    const now = Date.now();

    if (editMessageId) {
      outId = editMessageId;
      inId = editMessageId + 1;
      nextIdRef.current = inId + 1;
      originalText = messages.find(({ id }) => id === editMessageId)?.text;

      setMessages((prev) => {
        const editIdx = prev.findIndex(({ id }) => id === editMessageId);
        if (editIdx === -1) return prev;

        return [
          ...prev.slice(0, editIdx),
          { id: outId, text, isOutgoing: true, timestamp: now },
          {
            id: inId,
            text: '',
            isOutgoing: false,
            timestamp: now,
            isTyping: true,
            isStreaming: true,
          },
        ];
      });
    } else {
      outId = nextIdRef.current++;
      inId = nextIdRef.current++;

      setMessages((prev) => [
        ...prev,
        { id: outId, text, isOutgoing: true, timestamp: now },
        {
          id: inId,
          text: '',
          isOutgoing: false,
          timestamp: now,
          isTyping: true,
          isStreaming: true,
        },
      ]);
    }
    textRevealSequenceRef.current += 1;
    const textRevealPresentation: TextRevealPresentation = {
      key: `${generationRef.current}:${inId}:${textRevealSequenceRef.current}`,
      status: 'active',
      shouldRevealFromStart: true,
    };
    setTextRevealPresentations((current) => {
      const next = editMessageId
        ? filterTextRevealPresentations(current, editMessageId)
        : { ...current };

      next[inId] = textRevealPresentation;
      return next;
    });
    setIsSending(true);

    const global = getGlobal();
    const accountId = selectCurrentAccountId(global);
    const orderedAccounts = selectOrderedAccounts(global);
    const accountState = selectCurrentAccountState(global);
    const tokens = selectCurrentAccountTokens(global);
    const context = buildRequestContext(
      orderedAccounts,
      accountId!,
      accountState?.savedAddresses,
      tokens,
      global.settings.theme,
      originalText ? { originalText } : undefined,
    );
    const currentGeneration = generationRef.current;

    let streamAbort: NoneToVoidFunction | undefined;
    let streamStartTimeout: number | undefined = window.setTimeout(() => {
      streamStartTimeout = undefined;

      function flushPendingRaf() {
        if (textBatchRafRef.current) {
          cancelAnimationFrame(textBatchRafRef.current);
          textBatchRafRef.current = undefined;
        }
        const pending = pendingTextRef.current;
        pendingTextRef.current = undefined;
        return pending;
      }

      function finalize(msgs: AgentMessage[]) {
        persistMessages(msgs);
        setIsSending(false);
        abortRef.current = undefined;
      }

      function updateMessageText(msgId: number, newText: string) {
        setMessages((prev) => {
          const idx = prev.findIndex((msg) => msg.id === msgId);
          if (idx === -1) return prev;
          const updated = prev.slice();
          updated[idx] = {
            ...updated[idx], text: newText, isTyping: undefined, isStreaming: true,
          };
          return updated;
        });
      }

      const { abort } = createAgentStream(text, context, {
        onFirstChunk(currentText) {
          updateMessageText(inId, currentText);
        },

        onNextChunk(accumulated) {
          pendingTextRef.current = { id: inId, text: accumulated };
          if (!textBatchRafRef.current) {
            textBatchRafRef.current = requestAnimationFrame(() => {
              textBatchRafRef.current = undefined;
              const pending = pendingTextRef.current;
              if (pending) {
                updateMessageText(pending.id, pending.text);
                pendingTextRef.current = undefined;
              }
            });
          }
        },

        onComplete(accumulated) {
          if (currentGeneration !== generationRef.current) return;

          flushPendingRaf();
          let finalMessages!: AgentMessage[];
          setMessages((prev) => {
            finalMessages = prev
              .filter((msg) => !msg.isTyping)
              .map((msg) => (msg.id === inId ? finalizeStreamingMessage(msg, accumulated) : msg));
            return finalMessages;
          });
          finalize(finalMessages);
        },

        onError(error) {
          if (currentGeneration !== generationRef.current) return;

          flushPendingRaf();
          setTextRevealPresentations((current) => updateTextRevealPresentation(
            current,
            inId,
            textRevealPresentation.key,
            {
              status: 'error',
              shouldRevealFromStart: false,
            },
          ));
          let finalMessages!: AgentMessage[];
          setMessages((prev) => {
            finalMessages = prev
              .filter((msg) => !msg.isTyping || msg.id === inId)
              .map((msg) => (msg.id === inId
                ? finalizeStreamingMessage(msg, lang(error))
                : msg));
            return finalMessages;
          });
          finalize(finalMessages);

          logDebugError('[useAgentMessages] Agent Streaming: ', { error });
        },
      });

      streamAbort = abort;
    }, STREAM_RENDER_DELAY_MS);

    abortRef.current = () => {
      if (streamStartTimeout !== undefined) {
        clearTimeout(streamStartTimeout);
        streamStartTimeout = undefined;
      }
      streamAbort?.();
    };
  });

  const consumeTextRevealSession = useLastCallback((messageId: number, key: string) => {
    setTextRevealPresentations((current) => updateTextRevealPresentation(
      current,
      messageId,
      key,
      { shouldRevealFromStart: false },
    ));
  });

  const settleTextRevealSession = useLastCallback((messageId: number, key: string) => {
    setTextRevealPresentations((current) => updateTextRevealPresentation(
      current,
      messageId,
      key,
      {
        status: 'settled',
        shouldRevealFromStart: false,
      },
    ));
  });

  const clearChat = useLastCallback(() => {
    resetInternalState();
    void clearAgentChat();
    setAgentMeta({ messageCount: 0, lastTimestamp: undefined });
  });

  return {
    messages,
    isInitialLoadComplete,
    textRevealPresentations,
    sendMessage,
    consumeTextRevealSession,
    settleTextRevealSession,
    clearChat,
  };
}

function finalizeStreamingMessage(message: AgentMessage, text: string) {
  const finalizedMessage = { ...message, text };

  delete finalizedMessage.isTyping;
  delete finalizedMessage.isStreaming;

  return finalizedMessage;
}

function filterTextRevealPresentations(
  presentations: TextRevealPresentations,
  maximumMessageId: number,
) {
  return Object.fromEntries(
    Object.entries(presentations).filter(([messageId]) => Number(messageId) < maximumMessageId),
  ) as TextRevealPresentations;
}

function updateTextRevealPresentation(
  presentations: TextRevealPresentations,
  messageId: number,
  key: string,
  update: Partial<TextRevealPresentation>,
) {
  const presentation = presentations[messageId];
  if (!presentation || presentation.key !== key) return presentations;

  return {
    ...presentations,
    [messageId]: {
      ...presentation,
      ...update,
    },
  };
}

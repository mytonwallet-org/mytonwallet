import { useEffect, useMemo, useRef, useState } from '../../../lib/teact/teact';
import { getActions, getGlobal } from '../../../global';

import type {
  AgentActionProposal,
  AgentHintsResponseV2,
  AgentPersistedActionV2,
  AgentPublicFollowUpV2,
  AgentPublicInputContinuationV1,
  AgentUserQuotaV2,
} from '../../../api/agentV2/protocol/types';
import type {
  AgentV2ActionPresentation,
  AgentV2ComposerStatus,
  AgentV2HostContextSnapshot,
  AgentV2IncompatibleHistoryMessage,
  AgentV2ResolvedAction,
  AgentV2WalletConversationControl,
} from '../../../api/agentV2/types';
import type { AgentHint } from '../../../global/types';
import type { AgentRunActivityType } from '../AgentRunActivity';
import type { AgentV2HydrationController } from './agentV2HydrationController';
import type { AgentV2RunController } from './agentV2RunController';
import type { AgentV2SendAction, AgentV2StreamController } from './agentV2StreamController';
import type { TextRevealPresentations } from './textRevealPresentation';
import type {
  UseAgentMessagesProps,
  UseAgentMessagesResult,
} from './useAgentMessages';

import { getAppliedAgentV2CustomWriterInstruction } from '../../../util/agent/agentWriterPrompt';
import {
  cancelAgentV2ActiveRunReplays,
  subscribeToAgentV2Updates,
} from '../../../util/agentV2Updates';
import { getIsSupportedChain } from '../../../util/chain';
import { processDeeplink } from '../../../util/deeplink';
import { SELF_PROTOCOL } from '../../../util/deeplink/constants';
import { logDebugError } from '../../../util/logs';
import { openUrl } from '../../../util/openUrl';
import { callApi } from '../../../api';
import { buildAgentV2SendAuthorityKey } from '../../../api/agentV2/sendActionAuthority';
import {
  isAgentV2ComposerBlocked,
  selectAgentV2ComposerStatus,
} from '../../agentV2/agentComposerStatus';
import {
  getAgentV2ErrorText,
  getAgentV2HintCopy,
} from '../../agentV2/agentV2Copy';
import { buildAgentV2HostContext } from '../../agentV2/buildHostContext';
import { buildAgentV2HydrationError } from '../../agentV2/hydrationError';
import { createAgentV2HydrationController } from './agentV2HydrationController';
import {
  type AgentV2MessagesStateAction,
  INITIAL_AGENT_V2_MESSAGES_STATE,
  reduceAgentV2MessagesState,
  selectAgentV2Activity,
  selectIsAgentV2InputDisabled,
} from './agentV2MessagesState';
import { createAgentV2RunController } from './agentV2RunController';
import { createAgentV2StreamController } from './agentV2StreamController';

import useLastCallback from '../../../hooks/useLastCallback';

interface AgentV2Controllers {
  hydration: AgentV2HydrationController;
  run: AgentV2RunController;
  stream: AgentV2StreamController;
}

export interface UseAgentV2MessagesResult extends UseAgentMessagesResult {
  activity?: AgentRunActivityType;
  hasOlderMessages: boolean;
  isLoadingOlderMessages: boolean;
  loadOlderMessages: () => Promise<void>;
  isConsentAccepted?: boolean;
  composerStatus?: AgentV2ComposerStatus;
  userQuota?: AgentUserQuotaV2;
  sendMessage: (
    text: string,
    editMessageId?: number,
    inputContinuation?: {
      messageId: number;
      continuation: AgentPublicInputContinuationV1;
    },
  ) => void;
  sendHint: (hint: AgentHint) => void;
  sendFollowup: (messageId: number, followup: AgentPublicFollowUpV2) => void;
  sendWalletControl: (messageId: number, control: AgentV2WalletConversationControl) => void;
  acceptConsent: NoneToVoidFunction;
  retryMessage: (messageId: number) => void;
  retryAdmission: NoneToVoidFunction;
  refreshExpiredComposerStatus: NoneToVoidFunction;
  activateAction: (
    messageId: number,
    action: AgentActionProposal | AgentPersistedActionV2,
  ) => void;
}

const ERROR_MESSAGE_ID = -1;

export default function useAgentV2Messages({
  isActive,
  lang,
}: UseAgentMessagesProps): UseAgentV2MessagesResult {
  const {
    openReceiveModal,
    openTransactionInfo,
    setAgentMeta,
    setSwapAmountIn,
    showTokenActivity,
    setSwapAmountOut,
    startSwap,
    startTransfer,
    switchToAgent,
    switchToWallet,
    toggleTokenVisibility,
  } = getActions();
  const langCode = lang.code ?? 'en';
  const [state, setState] = useState(INITIAL_AGENT_V2_MESSAGES_STATE);
  const [textRevealPresentations, setTextRevealPresentations] = useState<TextRevealPresentations>({});
  const stateRef = useRef(state);
  const langRef = useRef(lang);
  const wasActiveRef = useRef(isActive);
  const controllersRef = useRef<AgentV2Controllers>();
  const dispatch = useLastCallback((action: AgentV2MessagesStateAction) => {
    setState((current) => reduceAgentV2MessagesState(current, action));
  });
  stateRef.current = state;
  langRef.current = lang;

  if (!controllersRef.current) {
    const stream = createAgentV2StreamController({
      cancelFrame: (frameId) => window.cancelAnimationFrame(frameId),
      dispatch,
      getActionPresentation: (messageId, actionId) => callApi(
        'getAgentV2ActionPresentation',
        messageId,
        actionId,
      ),
      getState: () => stateRef.current,
      now: Date.now,
      requestFrame: (callback) => window.requestAnimationFrame(callback),
      setTextRevealPresentations,
    });
    const hydration = createAgentV2HydrationController({
      buildHistoryError: (error) => buildAgentV2HydrationError(error, langRef.current),
      dispatch,
      getDefaultThread: () => callApi('getAgentV2DefaultThread'),
      getHints: (currentLangCode) => callApi('getAgentV2Hints', currentLangCode),
      getLangCode: () => langRef.current.code ?? 'en',
      getMessages: (threadId, cursor) => cursor
        ? callApi('getAgentV2Messages', threadId, cursor)
        : callApi('getAgentV2Messages', threadId),
      getState: () => stateRef.current,
      getUnavailableError: () => langRef.current('Agent is unavailable.'),
      isConsentAccepted: () => stateRef.current.isConsentAccepted === true,
      loadAvailability: () => callApi('getAgentV2Availability'),
      loadUserQuota: () => callApi('getAgentV2UserQuota'),
      mapHints: (response, currentLangCode) => mapHints(response, currentLangCode, langRef.current),
      now: Date.now,
      releaseStaleThreadClearOperation: (thread, shouldMatchRevision) => {
        run.releaseStaleThreadClearOperation(thread, shouldMatchRevision);
      },
      reportIncompatibleMessages: reportIncompatibleHistoryMessages,
      stream,
    });
    const run = createAgentV2RunController({
      buildConnectionError: () => langRef.current('Agent connection was interrupted.'),
      clearThread: (threadId, expectedRevision) => callApi(
        'clearAgentV2Thread',
        threadId,
        expectedRevision,
      ),
      dispatch,
      getErrorText: (code) => getAgentV2ErrorText(code, langRef.current),
      getState: () => stateRef.current,
      hydrate: hydration.hydrate,
      now: Date.now,
      retryRun: (clientRunId) => callApi('retryAgentV2Run', clientRunId),
      resetHistory: hydration.resetHistory,
      startRun: async (command) => {
        const customWriterInstruction = getAppliedAgentV2CustomWriterInstruction();
        const hostContext = buildAgentV2HostContext(getGlobal());
        const synchronized = await synchronizeHostContext(hostContext);
        if (synchronized === undefined) return undefined;
        return callApi('startAgentV2Run', {
          ...command,
          ...(customWriterInstruction ? { customWriterInstruction } : {}),
        });
      },
      stream,
    });
    controllersRef.current = { hydration, run, stream };
  }
  const controllers = controllersRef.current;

  const messageCount = state.messages.length;
  const lastMessageTimestamp = state.messages.at(-1)?.timestamp;
  const composerStatus = selectAgentV2ComposerStatus(
    state.availability,
    state.userQuota,
    state.quotaRetry,
    state.userRateLimit,
  );
  const isComposerBlocked = isAgentV2ComposerBlocked(composerStatus);
  const messages = useMemo(() => {
    if (state.admissionFailure && state.admissionFailure.retryMessageId === undefined) {
      return [
        ...state.messages,
        {
          id: ERROR_MESSAGE_ID,
          text: '',
          isOutgoing: false,
          timestamp: state.admissionFailure.timestamp,
          error: state.admissionFailure.error,
          isRetryAvailable: Boolean(state.admissionFailure.clientRunId),
        },
      ];
    }
    if (!state.error) return state.messages;
    return [
      ...state.messages,
      {
        id: ERROR_MESSAGE_ID,
        text: state.error.cause ? '' : state.error.text,
        isOutgoing: false,
        timestamp: state.error.timestamp,
        ...(state.error.cause ? { error: state.error.cause } : {}),
      },
    ];
  }, [state.admissionFailure, state.error, state.messages]);

  useEffect(() => {
    const unsubscribe = subscribeToAgentV2Updates((update) => {
      controllers.stream.handleUpdate(update);
      controllers.hydration.handleUpdate(update);
      controllers.run.handleUpdate(update);
    });

    return () => {
      unsubscribe();
      controllers.hydration.dispose();
      controllers.run.dispose();
      controllers.stream.dispose();
    };
  }, [controllers]);

  useEffect(() => {
    if (!isActive || state.isConsentAccepted !== undefined) return;

    dispatch({ kind: 'consentLoadingStarted' });
    void callApi('getAgentV2Consent').then((isAccepted) => {
      const isConsentAccepted = Boolean(isAccepted);
      dispatch({ kind: 'consentResolved', isAccepted: isConsentAccepted });
      if (isConsentAccepted) void controllers.hydration.hydrate();
    });
  }, [controllers, dispatch, isActive, state.isConsentAccepted]);

  useEffect(() => {
    const wasActive = wasActiveRef.current;
    wasActiveRef.current = isActive;
    if (!isActive || wasActive || state.isConsentAccepted !== true || !state.error) return;
    void controllers.hydration.hydrate();
  }, [controllers, isActive, state.error, state.isConsentAccepted]);

  useEffect(() => {
    if (
      !isActive
      || state.isConsentAccepted !== true
      || !state.thread
      || state.hintsLangCode === langCode
    ) return;
    void controllers.hydration.refreshHints();
  }, [controllers, isActive, langCode, state.hintsLangCode, state.isConsentAccepted, state.thread]);

  useEffect(() => {
    setAgentMeta({ messageCount, lastTimestamp: lastMessageTimestamp });
  }, [lastMessageTimestamp, messageCount, setAgentMeta]);

  const acceptConsent = useLastCallback(() => {
    void callApi('acceptAgentV2Consent').then((isConsentAccepted) => {
      if (isConsentAccepted !== true) return;
      dispatch({ kind: 'consentAccepted' });
      void controllers.hydration.hydrate();
    });
  });

  const activateAction = useLastCallback((
    messageId: number,
    action: AgentActionProposal | AgentPersistedActionV2,
  ) => {
    const sourceId = controllers.stream.getSourceId(messageId);
    if (!sourceId) return;
    if (action.kind === 'send') {
      void activateSendAction(messageId, sourceId, action);
      return;
    }
    const authorityKey = buildAgentV2ActionAuthorityKey(buildAgentV2HostContext(getGlobal()));
    const generation = controllers.stream.getActionPresentationGeneration();
    void callApi('resolveAgentV2Action', sourceId, action.id).then((resolved) => {
      if (!resolved || generation !== controllers.stream.getActionPresentationGeneration()) return;
      const currentAuthorityKey = buildAgentV2ActionAuthorityKey(buildAgentV2HostContext(getGlobal()));
      if (currentAuthorityKey !== authorityKey) return;
      if (resolved.kind === 'inactive') {
        controllers.stream.setActionPresentation(sourceId, action.id, resolved, generation);
        return;
      }
      dispatchResolvedAction(resolved);
    });
  });

  const refreshExpiredComposerStatus = useLastCallback(() => {
    dispatch({ kind: 'composerStatusExpired' });
  });

  const retryMessage = useLastCallback((messageId: number) => {
    const retryMessageId = stateRef.current.admissionFailure?.retryMessageId;
    if (messageId === ERROR_MESSAGE_ID || messageId === retryMessageId) {
      controllers.run.retryAdmission();
      return;
    }
    controllers.run.retryMessage(messageId);
  });

  return {
    messages,
    hints: state.hints,
    activity: selectAgentV2Activity(state),
    isInitialLoadComplete: state.isConsentAccepted === true && !state.isLoading,
    isInputDisabled: selectIsAgentV2InputDisabled(state, isComposerBlocked),
    textRevealPresentations,
    hasOlderMessages: Boolean(state.nextCursor),
    isLoadingOlderMessages: state.isLoadingOlderMessages,
    loadOlderMessages: controllers.hydration.loadOlderMessages,
    isConsentAccepted: state.isConsentAccepted,
    composerStatus,
    userQuota: state.userQuota,
    sendMessage: controllers.run.sendMessage,
    sendHint: controllers.run.sendHint,
    sendFollowup: controllers.run.sendFollowup,
    sendWalletControl: controllers.run.sendWalletControl,
    clearChat: controllers.run.clearChat,
    acceptConsent,
    retryMessage,
    retryAdmission: controllers.run.retryAdmission,
    refreshExpiredComposerStatus,
    activateAction,
    consumeTextRevealSession: controllers.stream.consumeTextRevealSession,
    settleTextRevealSession: controllers.stream.settleTextRevealSession,
  };

  async function activateSendAction(messageId: number, sourceId: string, action: AgentV2SendAction) {
    const lifecycleGeneration = controllers.stream.getActionLifecycleGeneration();
    let presentationGeneration = controllers.stream.getActionPresentationGeneration();
    const presentation = stateRef.current.messages
      .find((message) => message.id === messageId)
      ?.actionPresentations?.[action.id];
    if (!isActiveSendPresentation(presentation)) {
      controllers.stream.setActionPresentation(sourceId, action.id, { kind: 'inactive' });
      return;
    }

    const initialHostContext = buildAgentV2HostContext(getGlobal());
    const initialAuthorityKey = buildAgentV2SendAuthorityKey(initialHostContext);
    if (!initialAuthorityKey) {
      controllers.stream.setActionPresentation(sourceId, action.id, { kind: 'inactive' });
      return;
    }

    try {
      const hasAuthorityChanged = await synchronizeHostContext(initialHostContext);
      const synchronizedAuthorityKey = buildAgentV2SendAuthorityKey(buildAgentV2HostContext(getGlobal()));
      const synchronizedGeneration = controllers.stream.getActionPresentationGeneration();
      if (lifecycleGeneration !== controllers.stream.getActionLifecycleGeneration()) return;
      if (
        hasAuthorityChanged === undefined
        || synchronizedAuthorityKey !== initialAuthorityKey
      ) {
        controllers.stream.setActionPresentation(sourceId, action.id, { kind: 'inactive' }, synchronizedGeneration);
        return;
      }
      presentationGeneration = synchronizedGeneration;

      const resolved = await callApi('resolveAgentV2Action', sourceId, action.id);
      if (lifecycleGeneration !== controllers.stream.getActionLifecycleGeneration()) return;
      const currentHostContext = buildAgentV2HostContext(getGlobal());
      const hasCurrentAuthorityChanged = await synchronizeHostContext(currentHostContext);
      const currentAuthorityKey = buildAgentV2SendAuthorityKey(buildAgentV2HostContext(getGlobal()));
      const currentGeneration = controllers.stream.getActionPresentationGeneration();
      if (lifecycleGeneration !== controllers.stream.getActionLifecycleGeneration()) return;
      if (
        hasCurrentAuthorityChanged === undefined
        || currentAuthorityKey !== initialAuthorityKey
      ) {
        controllers.stream.setActionPresentation(sourceId, action.id, { kind: 'inactive' }, currentGeneration);
        return;
      }
      presentationGeneration = currentGeneration;
      const currentMessage = stateRef.current.messages.find((message) => message.id === messageId);
      if (
        !currentMessage?.actions?.some(({ id }) => id === action.id)
        || (resolved?.kind !== 'reviewSend' && resolved?.kind !== 'sendForm')
      ) {
        controllers.stream.setActionPresentation(sourceId, action.id, { kind: 'inactive' }, presentationGeneration);
        return;
      }

      if (resolved.kind === 'reviewSend') {
        startTransfer({
          tokenSlug: resolved.review.tokenSlug,
          amount: BigInt(resolved.review.amountAtomic),
          toAddress: resolved.review.toAddress,
          ...(resolved.review.comment ? { comment: resolved.review.comment } : {}),
          shouldRequireFreshAuth: true,
        });
      } else {
        dispatchResolvedAction(resolved);
      }
    } catch {
      controllers.stream.setActionPresentation(sourceId, action.id, { kind: 'inactive' }, presentationGeneration);
    }
  }

  function dispatchResolvedAction(resolved: AgentV2ResolvedAction) {
    switch (resolved.kind) {
      case 'openReceive':
        if (getIsSupportedChain(resolved.chain)) openReceiveModal({ chain: resolved.chain });
        return;
      case 'openStaking': {
        switchToWallet();
        void processDeeplink(buildStakingDeeplink(resolved));
        return;
      }
      case 'openSwap':
        switchToWallet();
        if (resolved.amountSide === 'source') {
          startSwap({
            tokenInSlug: resolved.tokenInSlug,
            tokenOutSlug: resolved.tokenOutSlug,
            amountIn: resolved.amount,
          });
          setSwapAmountIn({ amount: resolved.amount });
        } else {
          startSwap({ tokenInSlug: resolved.tokenInSlug, tokenOutSlug: resolved.tokenOutSlug });
          setSwapAmountOut({ amount: resolved.amount });
        }
        return;
      case 'sendForm':
        startTransfer({
          tokenSlug: resolved.tokenSlug,
          amount: undefined,
          toAddress: resolved.toAddress,
          comment: undefined,
          shouldRequireFreshAuth: true,
        });
        return;
      case 'reviewSend':
        return;
      case 'hideSpamAssets':
        resolved.slugs.forEach((slug) => toggleTokenVisibility({ slug, shouldShow: false }));
        return;
      case 'openUrl':
        if (isSafeHttpsUrl(resolved.url)) void openUrl(resolved.url, { isExternal: true });
        return;
      case 'openToken':
        if (getIsSupportedChain(resolved.chain)) {
          showTokenActivity({ slug: resolved.slug });
          switchToWallet();
        }
        return;
      case 'openTransaction':
        if (getIsSupportedChain(resolved.chain) && resolved.transactionRef.trim()) {
          openTransactionInfo({ txHash: resolved.transactionRef, chain: resolved.chain });
        }
        return;
      case 'openAgent':
        switchToAgent();
        return;
      case 'inactive':
        return;
      default:
        assertUnreachable(resolved);
    }
  }
}

function buildAgentV2ActionAuthorityKey(host: AgentV2HostContextSnapshot) {
  const activeAccount = host.accounts.find(({ accountId }) => accountId === host.activeAccountId);
  const activeNetwork = host.activeNetwork;
  return JSON.stringify({
    accountId: host.activeAccountId,
    accountType: activeAccount?.accountType,
    state: activeAccount?.state,
    isViewOnly: activeAccount?.isViewOnly,
    network: activeNetwork,
    isTestnet: host.isTestnet,
    address: activeNetwork ? activeAccount?.addresses[activeNetwork] : undefined,
    chains: activeAccount ? [...activeAccount.chains].sort() : undefined,
  });
}

function buildStakingDeeplink({
  productId,
  tokenSlug,
  amount,
}: Extract<AgentV2ResolvedAction, { kind: 'openStaking' }> | Omit<
  Extract<AgentV2ResolvedAction, { kind: 'openStaking' }>, 'kind'
>) {
  const searchParams = new URLSearchParams({ product: productId, asset: tokenSlug });
  if (amount) searchParams.set('amount', amount.kind === 'all' ? 'all' : amount.value);
  return `${SELF_PROTOCOL}stake?${searchParams}`;
}

function isActiveSendPresentation(
  presentation?: AgentV2ActionPresentation,
): presentation is Extract<AgentV2ActionPresentation, { kind: 'send' }> {
  return presentation?.kind === 'send'
    && (!presentation.expiresAt || Date.parse(presentation.expiresAt) > Date.now());
}

function reportIncompatibleHistoryMessages(
  threadId: string,
  messages: AgentV2IncompatibleHistoryMessage[],
) {
  messages.forEach((message) => {
    logDebugError(`Agent V2 ignored incompatible history message: ${JSON.stringify({
      threadId,
      ...message,
    })}`);
  });
}

async function synchronizeHostContext(hostContext: AgentV2HostContextSnapshot) {
  const result = await callApi('updateAgentV2HostContext', hostContext);
  if (!result?.ok) return undefined;
  if (result.value.authorityChanged) cancelAgentV2ActiveRunReplays();
  return result.value.authorityChanged;
}

function isSafeHttpsUrl(value: string) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password;
  } catch {
    return false;
  }
}

function mapHints(
  response: AgentHintsResponseV2,
  langCode: AgentHint['langCode'],
  lang: UseAgentMessagesProps['lang'],
): AgentHint[] {
  return response.items.map((hint) => {
    const copy = getAgentV2HintCopy(hint.id, lang);
    return {
      id: hint.id,
      langCode,
      title: copy.title,
      subtitle: copy.prompt,
      prompt: copy.prompt,
    };
  });
}

function assertUnreachable(value: never): never {
  throw new Error(`Unsupported Agent V2 value: ${String(value)}`);
}

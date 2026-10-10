import { useEffect, useMemo, useRef, useState } from '../../../lib/teact/teact';
import { getActions, getGlobal } from '../../../global';

import type {
  AgentHintsResponseV2,
  AgentPersistedActionV2,
  AgentPublicFollowUpV2,
  AgentUserQuotaV2,
  AgentV2LiveAction,
} from '../../../api/agentV2/protocol/types';
import type {
  AgentV2ActionPresentation,
  AgentV2ComposerStatus,
  AgentV2HostContextSnapshot,
  AgentV2IncompatibleHistoryMessage,
  AgentV2ResolvedAction,
} from '../../../api/agentV2/types';
import type { AgentHint, AgentMessage } from '../../../global/types';
import type { LangFn } from '../../../hooks/useLang';
import type { AgentProblemReportOutcome } from '../AgentConversationShell';
import type { AgentRunActivityType } from '../AgentRunActivity';
import type { AgentV2HydrationController } from './agentV2HydrationController';
import type { AgentV2RunController } from './agentV2RunController';
import type { AgentV2SendAction, AgentV2StreamController } from './agentV2StreamController';
import type { TextRevealPresentations } from './textRevealPresentation';

import { buildAgentV2HostContext } from '../../../global/agentV2/buildHostContext';
import { buildAgentBuiltinDapps } from '../../../global/agentV2/builtinDapps';
import { selectCurrentAccountState } from '../../../global/selectors';
import { isAgentLinkUrl } from '../../../util/agent/agentLinkUrl';
import {
  cancelAgentV2ActiveRunReplays,
  subscribeToAgentV2RuntimeReady,
  subscribeToAgentV2Updates,
} from '../../../util/agentV2Updates';
import { getIsSupportedChain } from '../../../util/chain';
import {
  isSelfDeeplink, parseDeeplinkTransferParams, processDeeplink,
} from '../../../util/deeplink';
import { SELF_PROTOCOL } from '../../../util/deeplink/constants';
import { logDebugError } from '../../../util/logs';
import { openUrl } from '../../../util/openUrl';
import { callApi } from '../../../api';
import { getAgentV2ActionAvailability } from '../../../api/agentV2/actionAvailability';
import { getSecretPhraseWordList, removeSecretPhrases } from '../../../api/agentV2/secretPhrase';
import {
  isAgentV2ComposerBlocked,
  selectAgentV2ComposerStatus,
} from '../../agentV2/agentComposerStatus';
import {
  getAgentV2ErrorText,
  getAgentV2HintCopy,
} from '../../agentV2/agentV2Copy';
import { buildAgentV2HydrationError } from '../../agentV2/hydrationError';
import { findSiteByUrl, openSite } from '../../explore/helpers/utils';
import { buildAgentV2SendAuthorityKey } from '../helpers/sendActionAuthority';
import { createAgentV2HydrationController } from './agentV2HydrationController';
import {
  type AgentV2MessagesStateAction,
  INITIAL_AGENT_V2_MESSAGES_STATE,
  reduceAgentV2MessagesState,
  selectAgentV2Activity,
  selectIsAgentV2InputDisabled,
  selectIsAgentV2RunActive,
} from './agentV2MessagesState';
import { createAgentV2RunController } from './agentV2RunController';
import { createAgentV2StreamController } from './agentV2StreamController';

import useLastCallback from '../../../hooks/useLastCallback';

interface AgentV2Controllers {
  hydration: AgentV2HydrationController;
  run: AgentV2RunController;
  stream: AgentV2StreamController;
}

interface UseAgentV2MessagesProps {
  isActive?: boolean;
  lang: LangFn;
}

export interface UseAgentV2MessagesResult {
  messages: AgentMessage[];
  hints?: AgentHint[];
  isInitialLoadComplete: boolean;
  isInputDisabled: boolean;
  isRunActive: boolean;
  textRevealPresentations: TextRevealPresentations;
  clearChat: NoneToVoidFunction;
  /** Present while the server takes problem reports */
  reportProblem?: (messageId: number | undefined, comment: string) => Promise<AgentProblemReportOutcome>;
  consumeTextRevealSession: (messageId: number, key: string) => void;
  settleTextRevealSession: (messageId: number, key: string) => void;
  activity?: AgentRunActivityType;
  hasOlderMessages: boolean;
  isLoadingOlderMessages: boolean;
  loadOlderMessages: () => Promise<void>;
  isConsentAccepted?: boolean;
  composerStatus?: AgentV2ComposerStatus;
  userQuota?: AgentUserQuotaV2;
  sendMessage: (text: string, editMessageId?: number) => void;
  sendHint: (hint: AgentHint) => void;
  sendFollowup: (messageId: number, followup: AgentPublicFollowUpV2) => void;
  acceptConsent: NoneToVoidFunction;
  retryMessage: (messageId: number) => void;
  retryAdmission: NoneToVoidFunction;
  refreshExpiredComposerStatus: NoneToVoidFunction;
  activateAction: (
    messageId: number,
    action: AgentV2LiveAction | AgentPersistedActionV2,
  ) => void;
}

const ERROR_MESSAGE_ID = -1;

export default function useAgentV2Messages({
  isActive,
  lang,
}: UseAgentV2MessagesProps): UseAgentV2MessagesResult {
  const {
    openReceiveModal,
    setSwapAmountOut,
    showError,
    startSwap,
    startTransfer,
  } = getActions();
  const langCode = lang.code ?? 'en';
  const [state, setState] = useState(INITIAL_AGENT_V2_MESSAGES_STATE);
  const [textRevealPresentations, setTextRevealPresentations] = useState<TextRevealPresentations>({});
  const [isProblemReportAvailable, setIsProblemReportAvailable] = useState(false);
  const stateRef = useRef(state);
  const langRef = useRef(lang);
  const wasActiveRef = useRef(isActive);
  const controllersRef = useRef<AgentV2Controllers>();
  const dispatch = useLastCallback((action: AgentV2MessagesStateAction) => {
    stateRef.current = reduceAgentV2MessagesState(stateRef.current, action);
    setState(stateRef.current);
  });
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
        const hostContext = buildAgentV2HostContext(getGlobal());
        const synchronized = await synchronizeHostContext(hostContext);
        if (synchronized === undefined) return undefined;
        return callApi('startAgentV2Run', command);
      },
      stream,
      hideSecretPhrases: (text) => removeSecretPhrases(
        text, getSecretPhraseWordList(), langRef.current('$agent_secret_words_removed'),
      ),
    });
    controllersRef.current = { hydration, run, stream };
  }
  const controllers = controllersRef.current;

  useEffect(() => {
    function updateChatActivity() {
      void callApi('setAgentV2ChatActive', Boolean(isActive && state.isConsentAccepted)).catch(() => undefined);
    }

    const unsubscribe = subscribeToAgentV2RuntimeReady(updateChatActivity);
    updateChatActivity();
    return () => {
      unsubscribe();
      void callApi('setAgentV2ChatActive', false).catch(() => undefined);
    };
  }, [isActive, state.isConsentAccepted]);

  const composerStatus = selectAgentV2ComposerStatus(
    state.availability,
    state.userQuota,
    state.quotaRetry,
    state.userRateLimit,
  );
  const isComposerBlocked = isAgentV2ComposerBlocked(composerStatus);
  const messages = useMemo(() => {
    const lastAdmittedUserMessageIndex = state.messages.reduce((lastIndex, { id, isOutgoing }, index) => (
      isOutgoing && state.sourceIdByMessageId[id] ? index : lastIndex
    ), -1);
    const visibleMessages = state.messages.map((message, index) => (
      message.error && index < lastAdmittedUserMessageIndex
        ? { ...message, error: undefined, isRetryAvailable: undefined }
        : message
    ));
    if (state.admissionFailure && state.admissionFailure.retryMessageId === undefined) {
      return [
        ...visibleMessages,
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
    if (!state.error) return visibleMessages;
    return [
      ...visibleMessages,
      {
        id: ERROR_MESSAGE_ID,
        text: state.error.cause ? '' : state.error.text,
        isOutgoing: false,
        timestamp: state.error.timestamp,
        ...(state.error.cause ? { error: state.error.cause } : {}),
      },
    ];
  }, [state.admissionFailure, state.error, state.messages, state.sourceIdByMessageId]);

  useEffect(() => {
    const unsubscribe = subscribeToAgentV2Updates((update) => {
      if (controllers.run.isCancelledRunUpdate(update)) return;
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

  const threadId = state.thread?.id;
  useEffect(() => {
    if (!isActive || !threadId) return undefined;

    let isCurrent = true;
    void callApi('getAgentV2ProblemReportAvailability').then((isAvailable) => {
      if (isCurrent) setIsProblemReportAvailable(Boolean(isAvailable));
    });
    return () => {
      isCurrent = false;
    };
  }, [isActive, threadId]);

  const acceptConsent = useLastCallback(() => {
    void callApi('acceptAgentV2Consent').then((isConsentAccepted) => {
      if (isConsentAccepted !== true) return;
      dispatch({ kind: 'consentAccepted' });
      void controllers.hydration.hydrate();
    });
  });

  const activateAction = useLastCallback((
    messageId: number,
    action: AgentV2LiveAction | AgentPersistedActionV2,
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

  const reportProblem = useLastCallback(async (
    messageId: number | undefined,
    comment: string,
  ): Promise<AgentProblemReportOutcome> => {
    const { thread } = stateRef.current;
    if (!thread) return 'failed';
    // The connection error bubble has no stored message and reports the conversation. An answer that lost its stored
    // message since the form opened is not reported as the conversation in its place.
    const sourceId = messageId === undefined || messageId === ERROR_MESSAGE_ID
      ? undefined
      : controllers.stream.getSourceId(messageId);
    if (messageId !== undefined && messageId !== ERROR_MESSAGE_ID && !sourceId) return 'failed';
    const result = await callApi('reportAgentV2Problem', thread.id, {
      ...(sourceId ? { messageId: sourceId } : {}),
      ...(comment ? { comment } : {}),
    });
    if (result?.ok) return 'sent';
    // A server that has switched reports off refuses them, and asking again takes the report items away
    void callApi('getAgentV2ProblemReportAvailability').then((isAvailable) => {
      setIsProblemReportAvailable(Boolean(isAvailable));
    });
    return result?.error.code === 'rate_limited' ? 'rateLimited' : 'failed';
  });

  const refreshExpiredComposerStatus = useLastCallback(() => {
    dispatch({ kind: 'composerStatusExpired' });
  });

  const retryMessage = useLastCallback((messageId: number) => {
    const admissionFailure = stateRef.current.admissionFailure;
    if (messageId === ERROR_MESSAGE_ID
      || (messageId === admissionFailure?.retryMessageId && admissionFailure.clientRunId)) {
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
    isRunActive: selectIsAgentV2RunActive(state),
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
    clearChat: controllers.run.clearChat,
    reportProblem: isProblemReportAvailable ? reportProblem : undefined,
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
        || resolved?.kind !== 'sendForm'
      ) {
        controllers.stream.setActionPresentation(sourceId, action.id, { kind: 'inactive' }, presentationGeneration);
        return;
      }

      dispatchResolvedAction(resolved);
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
        void processDeeplink(buildStakingDeeplink(resolved));
        return;
      }
      case 'openSwap':
        if (isSelfDeeplink(resolved.url)) {
          const global = getGlobal();
          if (!getAgentV2ActionAvailability(buildAgentV2HostContext(global)).canPrepareSwap) return;
          const tokensBySlug = global.swapTokenInfo?.bySlug;
          if ((resolved.tokenInSlug && !tokensBySlug?.[resolved.tokenInSlug])
            || (resolved.tokenOutSlug && !tokensBySlug?.[resolved.tokenOutSlug])) {
            showError({ error: '$unknown_swap_token' });
            return;
          }
          startSwap({
            tokenInSlug: resolved.tokenInSlug,
            tokenOutSlug: resolved.tokenOutSlug,
            amountIn: resolved.amountSide === 'source' ? resolved.amount : undefined,
          });
          if (resolved.amountSide === 'destination' && resolved.amount) {
            setSwapAmountOut({ amount: resolved.amount });
          }
        } else if (isSafeHttpsUrl(resolved.url)) {
          void openUrl(resolved.url);
        }
        return;
      case 'sendForm': {
        if (resolved.url === 'mtw://send') {
          startTransfer({ shouldRequireFreshAuth: true });
          return;
        }
        const url = new URL(resolved.url);
        if (url.protocol !== 'mtw:' || url.hostname !== 'send') return;
        const global = getGlobal();
        const params = parseDeeplinkTransferParams(resolved.url, global);
        if (!params) return;
        const { error, ...transferParams } = params;
        // The runtime already matched the asset; the parser sees no held tokens until balances load
        const requestedTokenSlug = error === '$dont_have_required_token' && !selectCurrentAccountState(global)?.balances
          ? url.searchParams.get('token') ?? undefined
          : undefined;
        if (error && !requestedTokenSlug) {
          showError({ error });
          return;
        }
        const tokenSlug = requestedTokenSlug || transferParams.tokenSlug;
        // As the Max button does before the fee is known: the form takes the fee off once it has it
        const maxAmount = resolved.isMaxAmount && tokenSlug
          ? selectCurrentAccountState(global)?.balances?.bySlug[tokenSlug]
          : undefined;
        startTransfer({
          ...transferParams,
          tokenSlug,
          ...(maxAmount ? { amount: maxAmount } : {}),
          shouldRequireFreshAuth: true,
        });
        return;
      }
      case 'openDapp': {
        const global = getGlobal();
        // A stored button to a screen of the app, such as Multisend, opens it as an answer link does
        if ((resolved.url.startsWith(SELF_PROTOCOL) && isAgentLinkUrl(resolved.url))
          || buildAgentBuiltinDapps(global).some(({ url }) => url === resolved.url)) {
          void processDeeplink(resolved.url);
          return;
        }
        const site = findSiteByUrl(global.exploreData?.sites, resolved.url);
        if (!site || (global.restrictions.isLimitedRegion && site.canBeRestricted)) return;
        openSite(site.url, site.isExternal, site.name);
        return;
      }
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
  if (result.value.authorityChanged && !result.value.preservesActiveRuns) cancelAgentV2ActiveRunReplays();
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
  lang: UseAgentV2MessagesProps['lang'],
): AgentHint[] {
  return response.items.map((hint) => {
    const copy = getAgentV2HintCopy(hint.id, lang);
    return {
      id: hint.id,
      langCode,
      title: copy.title,
      subtitle: copy.subtitle,
      prompt: copy.prompt,
    };
  });
}

function assertUnreachable(value: never): never {
  throw new Error(`Unsupported Agent V2 value: ${String(value)}`);
}

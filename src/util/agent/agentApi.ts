import type { Account, AgentHint, SavedAddress, Theme, UserToken } from '../../global/types';

import { AGENT_API_URL } from '../../config';
import { logDebugError } from '../logs';
import { DEFAULT_LANG_CODE } from '../windowEnvironment';
import agentStore from './agentStore';

const MAX_CONTEXT_USER_ADDRESSES = 5;
const MAX_CONTEXT_SAVED_ADDRESSES = 10;

export enum AgentError {
  ResponseFailed = 'AgentErrorResponseFailed',
  ConnectionFailed = 'AgentErrorConnectionFailed',
}

interface StreamCallbacks {
  onFirstChunk: (text: string) => void;
  onNextChunk: (accumulated: string) => void;
  onComplete: (accumulated: string) => void;
  onError: (error: AgentError) => void;
}

const AGENT_FETCH_HEADERS = { 'Content-Type': 'application/json' } as const;
const CONVERSATION_ID_STORAGE_KEY = 'agentConversationId';

let conversationId: string | undefined;

function getAgentStreamFetch(): typeof fetch {
  // Capacitor stores the unpatched browser fetch here before replacing `window.fetch`
  // with a native bridge that buffers POST responses and breaks streaming.
  return window.CapacitorWebFetch ?? window.fetch;
}

async function generateConversationId(): Promise<string> {
  const id = crypto.randomUUID();
  await agentStore.setItem(CONVERSATION_ID_STORAGE_KEY, id);
  conversationId = id;
  return id;
}

async function getConversationId(): Promise<string> {
  if (conversationId) return conversationId;

  const stored = await agentStore.getItem<string>(CONVERSATION_ID_STORAGE_KEY);
  if (stored) {
    conversationId = stored;
    return stored;
  }

  return generateConversationId();
}

export async function resetConversationId(): Promise<string> {
  return generateConversationId();
}

export async function fetchAgentHints(langCode: string = DEFAULT_LANG_CODE): Promise<AgentHint[] | undefined> {
  try {
    const res = await fetch(`${AGENT_API_URL}/hints?${new URLSearchParams({ langCode })}`);

    if (!res.ok) {
      logDebugError(`Agent hints fetch failed: ${res.status} ${res.statusText}`);
      return undefined;
    }

    const data = await res.json();
    return data?.items;
  } catch (err: unknown) {
    logDebugError('Agent hints fetch error', err);
    return undefined;
  }
}

export function createAgentStream(
  text: string,
  context: ReturnType<typeof buildRequestContext>,
  callbacks: StreamCallbacks,
): { abort: () => void } {
  const abortController = new AbortController();
  const fetchAgentStream = getAgentStreamFetch();

  void (async () => {
    try {
      const response = await fetchAgentStream(`${AGENT_API_URL}/message`, {
        method: 'POST',
        headers: AGENT_FETCH_HEADERS,
        signal: abortController.signal,
        body: JSON.stringify({
          clientId: await getConversationId(),
          text,
          context,
        }),
      });

      if (!response.ok || !response.body) {
        callbacks.onError(AgentError.ResponseFailed);
        return;
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let accumulated = '';
      let isFirstChunk = true;

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        accumulated += decoder.decode(value, { stream: true });

        if (isFirstChunk) {
          isFirstChunk = false;
          callbacks.onFirstChunk(accumulated);
        } else {
          callbacks.onNextChunk(accumulated);
        }
      }

      if (!accumulated) {
        callbacks.onError(AgentError.ResponseFailed);
        return;
      }

      callbacks.onComplete(accumulated);
    } catch (err) {
      if (abortController.signal.aborted) return;
      logDebugError('[createAgentStream] Connection Failed', err);
      callbacks.onError(AgentError.ConnectionFailed);
    }
  })();

  return {
    abort() {
      abortController.abort();
    },
  };
}

export function buildRequestContext(
  accounts: Array<[string, Account]>,
  currentAccountId: string,
  savedAddresses?: SavedAddress[],
  tokens?: UserToken[],
  theme?: Theme,
  edit?: { originalText: string },
) {
  const topAccounts = accounts.slice(0, MAX_CONTEXT_USER_ADDRESSES);
  const isCurrentInTop = topAccounts.some(([id]) => id === currentAccountId);

  if (!isCurrentInTop) {
    const currentAccount = accounts.find(([id]) => id === currentAccountId)!;
    topAccounts.push(currentAccount);
  }

  return {
    userAddresses: topAccounts.map(([id, account]) => ({
      name: account.title ?? '',
      addresses: Object.entries(account.byChain)
        .flatMap(([chain, wallet]) => (wallet?.address ? [`${chain}:${wallet.address}`] : [])),
      accountType: account.type,
      ...(id === currentAccountId && { isActive: true }),
    })),
    savedAddresses: savedAddresses?.slice(0, MAX_CONTEXT_SAVED_ADDRESSES).map(({ name, address, chain }) => ({
      name,
      addresses: [`${chain}:${address}`],
    })),
    walletTokens: tokens?.map(({ slug, symbol, name, decimals, priceUsd }) => (
      [slug, symbol, name, String(decimals), String(priceUsd)]
    )),
    balances: tokens?.filter(({ amount }) => amount > 0n)
      .map(({ slug, amount }) => `${slug}:${String(amount)}`),
    theme,
    ...(edit && { isEdit: true, originalText: edit.originalText }),
  };
}

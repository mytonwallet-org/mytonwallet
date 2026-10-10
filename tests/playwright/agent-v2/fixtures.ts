import type {
  APIRequestContext,
  BrowserContext,
  Locator,
  Page,
} from '@playwright/test';
import { expect, test as base } from '@playwright/test';

const PRIMARY_ACCOUNT_ID = '0-mainnet';
const SECONDARY_ACCOUNT_ID = '1-mainnet';
const PRIMARY_ADDRESS = 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ';
const SECONDARY_ADDRESS = 'UQBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBF9';

interface AgentV2MockState {
  scenario: string;
  requests: Array<{ method: string; path: string; body?: unknown }>;
  runBodies: Record<string, any>[];
  cancelBodies: Array<{ runId: string; body: unknown }>;
  clearBodies: Record<string, any>[];
  runCount: number;
  quotaRequestCount: number;
  revision: number;
  messages: Record<string, any>[];
  olderMessages: Record<string, any>[];
  pendingResponseCount: number;
}

interface AgentV2Fixture {
  reset: (scenario?: string) => Promise<AgentV2MockState>;
  seedWallet: (withSecondaryAccount?: boolean) => Promise<void>;
  open: () => Promise<void>;
  openPage: (page: Page) => Promise<void>;
  acceptConsent: () => Promise<void>;
  send: (text: string) => Promise<void>;
  sendFromPage: (page: Page, text: string) => Promise<void>;
  getState: () => Promise<AgentV2MockState>;
  completeRun: () => Promise<void>;
  blockedExternalRequests: string[];
}

export const test = base.extend<{ agentV2: AgentV2Fixture }>({
  agentV2: async ({ context, page, request }, use) => {
    const blockedExternalRequests: string[] = [];
    await blockExternalRequests(context, blockedExternalRequests);

    await use({
      reset: (scenario = 'conversation') => resetMock(request, scenario),
      seedWallet: (withSecondaryAccount = false) => seedViewWallet(page, withSecondaryAccount),
      open: () => openAgent(page),
      openPage: (targetPage) => openAgent(targetPage),
      acceptConsent: () => acceptConsent(page),
      send: (text) => sendMessage(page, text),
      sendFromPage: (targetPage, text) => sendMessage(targetPage, text),
      getState: () => getMockState(request),
      completeRun: async () => {
        const response = await request.post('/__agent-v2-control/complete-run');
        expect(response.ok()).toBe(true);
      },
      blockedExternalRequests,
    });

    await context.unrouteAll({ behavior: 'ignoreErrors' });
  },
});

export { expect };

export function getAgentV2Conversation(page: Page): Locator {
  return page.locator('.custom-scroll:visible').filter({
    has: page.locator('[data-agent-v2-message-role], [role="status"]'),
  }).last();
}

async function resetMock(request: APIRequestContext, scenario: string) {
  const response = await request.post('/__agent-v2-control/reset', { data: { scenario } });
  expect(response.ok()).toBe(true);
  return response.json() as Promise<AgentV2MockState>;
}

async function getMockState(request: APIRequestContext) {
  const response = await request.get('/__agent-v2-control/state');
  expect(response.ok()).toBe(true);
  return response.json() as Promise<AgentV2MockState>;
}

async function blockExternalRequests(context: BrowserContext, blockedRequests: string[]) {
  await context.route('**/*', async (route) => {
    const url = new URL(route.request().url());
    if (isLoopback(url) || !['http:', 'https:'].includes(url.protocol)) {
      await route.continue();
      return;
    }

    blockedRequests.push(`${url.protocol}//${url.host}${url.pathname}`);
    await route.abort('blockedbyclient');
  });
}

async function seedViewWallet(page: Page, withSecondaryAccount: boolean) {
  await page.goto('/__agent-v2-seed', { waitUntil: 'domcontentloaded' });
  await page.evaluate(async ({
    primaryAccountId,
    primaryAddress,
    secondaryAccountId,
    secondaryAddress,
    shouldAddSecondaryAccount,
  }) => {
    const localAccounts = {
      [primaryAccountId]: {
        title: 'Synthetic View Wallet',
        type: 'view',
        byChain: { ton: { address: primaryAddress } },
      },
      ...(shouldAddSecondaryAccount ? {
        [secondaryAccountId]: {
          title: 'Secondary View Wallet',
          type: 'view',
          byChain: { ton: { address: secondaryAddress } },
        },
      } : {}),
    };
    const accountIds = Object.keys(localAccounts);

    localStorage.clear();
    sessionStorage.clear();
    localStorage.setItem('mytonwallet-global-state', JSON.stringify({
      stateVersion: 59,
      appState: 1,
      currentAccountId: primaryAccountId,
      accounts: { byId: localAccounts },
      byAccountId: Object.fromEntries(accountIds.map((id) => [id, { isAppReady: true }])),
      settings: { langCode: 'en', orderedAccountIds: accountIds },
    }));

    await new Promise<void>((resolve, reject) => {
      const resetRequest = indexedDB.deleteDatabase('keyval-store');
      resetRequest.onsuccess = () => resolve();
      resetRequest.onerror = () => reject(resetRequest.error);
      resetRequest.onblocked = () => reject(new Error('IndexedDB reset was blocked'));
    });

    const database = await new Promise<IDBDatabase>((resolve, reject) => {
      const openRequest = indexedDB.open('keyval-store', 1);
      openRequest.onupgradeneeded = () => openRequest.result.createObjectStore('keyval');
      openRequest.onsuccess = () => resolve(openRequest.result);
      openRequest.onerror = () => reject(openRequest.error);
    });

    await new Promise<void>((resolve, reject) => {
      const transaction = database.transaction('keyval', 'readwrite');
      const store = transaction.objectStore('keyval');
      store.put(22, 'stateVersion');
      store.put(primaryAccountId, 'currentAccountId');
      store.put(Object.fromEntries(accountIds.map((id) => [id, {
        type: 'view',
        byChain: {
          ton: {
            address: id === primaryAccountId ? primaryAddress : secondaryAddress,
            index: 0,
            version: 'W5',
            isInitialized: true,
          },
        },
      }])), 'accounts');
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
      transaction.onabort = () => reject(transaction.error);
    });
    database.close();
  }, {
    primaryAccountId: PRIMARY_ACCOUNT_ID,
    primaryAddress: PRIMARY_ADDRESS,
    secondaryAccountId: SECONDARY_ACCOUNT_ID,
    secondaryAddress: SECONDARY_ADDRESS,
    shouldAddSecondaryAccount: withSecondaryAccount,
  });
}

async function openAgent(page: Page) {
  await page.goto('/?r=agent-v2-e2e', { waitUntil: 'domcontentloaded' });
  const agentTab = page.getByRole('button', { name: 'Agent', exact: true }).last();
  await agentTab.waitFor({ state: 'visible', timeout: 30_000 });
  await agentTab.click();
}

async function acceptConsent(page: Page) {
  await page.getByRole('heading', { name: 'Data shared with Agent' }).waitFor();
  await page.getByRole('button', { name: 'Allow Agent', exact: true }).click();
  await page.getByRole('textbox', { name: 'Ask anything' }).waitFor();
}

async function sendMessage(page: Page, text: string) {
  await page.getByRole('textbox', { name: 'Ask anything' }).fill(text);
  await page.getByRole('button', { name: 'Send', exact: true }).click();
}

function isLoopback(url: URL) {
  return ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname);
}

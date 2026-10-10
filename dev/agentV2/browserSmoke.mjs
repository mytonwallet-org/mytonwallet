import { chromium } from 'playwright';

const classicUrl = process.env.AGENT_V2_CLASSIC_URL ?? 'http://127.0.0.1:4321';
const replicaA = process.env.AGENT_V2_LOCAL_BASE_URL_A ?? 'http://127.0.0.1:3001';
const replicaB = process.env.AGENT_V2_LOCAL_BASE_URL_B ?? 'http://127.0.0.1:3002';
const accountId = '0-mainnet';
const viewAddress = 'UQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJKZ';
const message = `Browser smoke ${Date.now()}`;
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ locale: 'en-US', viewport: { width: 390, height: 844 } });
const page = await context.newPage();
const externalRequests = [];
const threadRequests = [];
const consoleErrors = [];
const pageErrors = [];

page.on('console', (entry) => {
  if (entry.type() === 'error') consoleErrors.push(entry.text());
});
page.on('pageerror', (error) => pageErrors.push(String(error)));

try {
  await context.route('**/*', async (route) => {
    const request = route.request();
    const url = new URL(request.url());

    if (!isLoopback(url)) {
      externalRequests.push(redactUrl(url));
      await route.abort('blockedbyclient');
      return;
    }

    if (url.origin === new URL(replicaA).origin && url.pathname.startsWith('/api/v2/threads')) {
      const target = new URL(url.pathname + url.search, replicaB);
      threadRequests.push(`${request.method()} ${target.pathname}${target.search}`);
      const response = await route.fetch({ url: target.href });
      await route.fulfill({ response });
      return;
    }

    if (url.origin === new URL(replicaA).origin
      && url.pathname === '/api/v2/runs'
      && request.method() === 'POST') {
      await new Promise((resolve) => setTimeout(resolve, 800));
    }

    await route.continue();
  });

  await context.route(`${classicUrl}/__agent-v2-seed`, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'text/html',
      body: '<!doctype html><html><body>Agent V2 browser seed</body></html>',
    });
  });
  await context.route('**/v2/dapp/catalog?*', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        categories: [],
        sites: [{
          url: 'https://fragment.com/',
          name: 'Fragment',
          icon: 'https://static.example/fragment.png',
          manifestUrl: '',
          description: 'Telegram collectibles',
          canBeRestricted: false,
          isExternal: true,
        }],
      }),
    });
  });

  await page.goto(`${classicUrl}/__agent-v2-seed`, { waitUntil: 'domcontentloaded' });
  await seedViewWallet(page);
  await page.goto(`${classicUrl}/?r=browser-smoke`, { waitUntil: 'domcontentloaded' });

  const agentTab = page.getByRole('button', { name: 'Agent', exact: true }).last();
  await agentTab.waitFor({ state: 'visible', timeout: 30_000 });
  await agentTab.click();

  await page.getByRole('heading', { name: 'Data shared with Agent' }).waitFor({ timeout: 15_000 });
  await page.getByRole('button', { name: 'Allow Agent', exact: true }).click();
  const input = page.getByRole('textbox', { name: 'Ask anything' });
  await input.waitFor({ timeout: 15_000 });
  await input.fill(message);
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  await page.getByText(message, { exact: true }).waitFor({ timeout: 15_000 });
  await page.locator('[data-agent-v2-message-role="user"]:not([data-agent-v2-message-id^="local-"])')
    .filter({ hasText: message })
    .waitFor({ timeout: 20_000 });
  await page.locator('[data-agent-v2-message-role="assistant"][data-agent-v2-message-status="complete"]')
    .last()
    .waitFor({
      state: 'attached',
      timeout: 20_000,
    });

  await input.fill('Show me how to receive tokens');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  const receiveAction = page.locator('button[data-agent-action-kind="receive"]');
  await receiveAction.waitFor({ timeout: 20_000 });
  assert(await receiveAction.isEnabled(), 'Receive action is not available to the view wallet');

  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.getByRole('button', { name: 'Agent', exact: true }).last().click();
  await page.getByText(message, { exact: true }).waitFor({ timeout: 20_000 });

  await page.getByRole('button', { name: 'Open Menu', exact: true }).click();
  await page.getByText('Clear Chat', { exact: true }).last().click();
  const confirmClear = page.locator('#agent-clear-chat-confirm:visible');
  await confirmClear.waitFor();
  await confirmClear.click();
  await page.getByText(message, { exact: true }).waitFor({ state: 'detached' });

  assert(threadRequests.some((request) => request === 'GET /api/v2/threads/default'),
    'Default-thread hydration was not routed through replica B');
  assert(threadRequests.some((request) => request.includes('/messages?')),
    'Message history was not routed through replica B');
  assert(threadRequests.some((request) => request.endsWith('/clear')),
    'Default-thread clear was not routed through replica B');
  assert(threadRequests.every((request) => !/^(GET|POST) \/api\/v2\/threads(?:\?|$)/u.test(request)),
    'Classic requested the removed thread list or create endpoint');
  assert(threadRequests.every((request) => !/^(PATCH|DELETE) \/api\/v2\/threads\//u.test(request)),
    'Classic requested removed thread metadata or delete endpoints');

  process.stdout.write(`${JSON.stringify({
    ok: true,
    classicUrl,
    replicaA,
    replicaB,
    threadRequests: threadRequests.length,
    blockedExternalRequests: [...new Set(externalRequests)].length,
    checked: [
      'consent',
      'direct-chat',
      'receive-action',
      'reload-hydration',
      'clear',
      'default-only-thread-api',
    ],
  }, undefined, 2)}\n`);
} catch (error) {
  const screenshotPath = `${process.env.TMPDIR ?? '/tmp'}/agent-v2-browser-smoke-failure.png`;
  await page.screenshot({ path: screenshotPath, fullPage: true }).catch(() => undefined);
  const messageStates = await page.locator('[data-agent-v2-message-id]').evaluateAll((messages) => {
    return messages.map((item) => ({
      id: item.getAttribute('data-agent-v2-message-id'),
      role: item.getAttribute('data-agent-v2-message-role'),
      status: item.getAttribute('data-agent-v2-message-status'),
    }));
  }).catch(() => []);
  process.stderr.write(`Agent V2 browser smoke failed at ${page.url()}; screenshot=${screenshotPath}; `
    + `messages=${JSON.stringify(messageStates)}; consoleErrors=${JSON.stringify(consoleErrors)}; `
    + `pageErrors=${JSON.stringify(pageErrors)}; ${String(error)}\n`);
  throw error;
} finally {
  await context.unrouteAll({ behavior: 'ignoreErrors' }).catch(() => undefined);
  await context.close().catch(() => undefined);
  await browser.close().catch(() => undefined);
}

async function seedViewWallet(page) {
  await page.evaluate(async ({ id, address }) => {
    localStorage.clear();
    localStorage.setItem('mytonwallet-global-state', JSON.stringify({
      stateVersion: 59,
      appState: 1,
      currentAccountId: id,
      accounts: {
        byId: {
          [id]: {
            title: 'Synthetic View Wallet',
            type: 'view',
            byChain: { ton: { address } },
          },
        },
      },
      byAccountId: { [id]: { isAppReady: true } },
      settings: { langCode: 'en' },
    }));

    await new Promise((resolve, reject) => {
      const request = indexedDB.deleteDatabase('keyval-store');
      request.onsuccess = () => resolve(undefined);
      request.onerror = () => reject(request.error);
      request.onblocked = () => reject(new Error('IndexedDB reset was blocked'));
    });

    const database = await new Promise((resolve, reject) => {
      const request = indexedDB.open('keyval-store', 1);
      request.onupgradeneeded = () => request.result.createObjectStore('keyval');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });

    await new Promise((resolve, reject) => {
      const transaction = database.transaction('keyval', 'readwrite');
      const store = transaction.objectStore('keyval');
      store.put(22, 'stateVersion');
      store.put(id, 'currentAccountId');
      store.put({
        [id]: {
          type: 'view',
          byChain: {
            ton: {
              address,
              index: 0,
              version: 'W5',
              isInitialized: true,
            },
          },
        },
      }, 'accounts');
      transaction.oncomplete = () => resolve(undefined);
      transaction.onerror = () => reject(transaction.error);
      transaction.onabort = () => reject(transaction.error);
    });
    database.close();
  }, { id: accountId, address: viewAddress });
}

function isLoopback(url) {
  return ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname);
}

function redactUrl(url) {
  return `${url.protocol}//${url.host}${url.pathname}`;
}

function assert(value, message) {
  if (!value) throw new Error(message);
}

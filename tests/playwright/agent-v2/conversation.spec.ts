import { expect, getAgentV2Conversation, test } from './fixtures';

test.describe('Agent V2 deterministic conversation', () => {
  test('uses V2 despite a saved V1 selection and a legacy V1 link', async ({ agentV2, page }) => {
    await agentV2.reset();
    await agentV2.seedWallet();
    await page.addInitScript(() => {
      localStorage.setItem('agentProtocolVersion', 'v1');
      const url = new URL(window.location.href);
      url.searchParams.set('agent', 'v1');
      window.history.replaceState(undefined, '', url);
    });
    await agentV2.open();
    await agentV2.acceptConsent();

    const prompt = 'Explain this wallet using the default agent';
    await agentV2.send(prompt);
    await expect(page.getByText(`Deterministic response: ${prompt}`, { exact: true })).toBeVisible();
    const state = await agentV2.getState();
    expect(state.runBodies).toHaveLength(1);
    expect(state.requests.some(({ path }) => path.startsWith('/api/v2/threads/'))).toBe(true);
  });

  test('preserves the wallet session within one tab and isolates it across tabs', async ({
    agentV2,
    context,
    page,
  }) => {
    await agentV2.reset();
    await agentV2.seedWallet();
    await agentV2.open();

    await expect(page.getByRole('heading', { name: 'Data shared with Agent' })).toBeVisible();
    await agentV2.acceptConsent();

    const prompt = 'Explain this deterministic wallet';
    await agentV2.send(prompt);
    await expect(page.getByText(prompt, { exact: true })).toBeVisible();
    const assistantMessage = page.locator('[data-agent-v2-message-role="assistant"]').last();
    await expect(assistantMessage).toHaveAttribute('data-agent-v2-message-status', 'streaming');
    await expect(assistantMessage
      .filter({ hasText: `Deterministic response: ${prompt}` }))
      .toHaveAttribute('data-agent-v2-message-status', 'complete');
    const initialState = await agentV2.getState();
    const initialSessionId = initialState.runBodies[0].walletContext.sessionId;

    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.getByRole('button', { name: 'Agent', exact: true }).last().click();
    await expect(page.getByText(prompt, { exact: true })).toBeVisible();
    await expect(page.getByText(`Deterministic response: ${prompt}`, { exact: true })).toBeVisible();

    const reloadPrompt = 'Confirm the reloaded wallet session';
    await agentV2.send(reloadPrompt);
    await expect(page.getByText(`Deterministic response: ${reloadPrompt}`, { exact: true })).toBeVisible();
    const reloadedState = await agentV2.getState();
    expect(reloadedState.runBodies[1].walletContext.sessionId).toBe(initialSessionId);

    const secondPage = await context.newPage();
    await agentV2.openPage(secondPage);
    const secondTabPrompt = 'Confirm the isolated wallet session';
    await agentV2.sendFromPage(secondPage, secondTabPrompt);
    await expect(secondPage.getByText(`Deterministic response: ${secondTabPrompt}`, { exact: true })).toBeVisible();
    const secondTabState = await agentV2.getState();
    expect(secondTabState.runBodies[2].walletContext.sessionId).not.toBe(initialSessionId);

    await secondPage.getByRole('button', { name: 'Open Menu', exact: true }).click();
    await secondPage.getByText('Clear Chat', { exact: true }).last().click();
    await secondPage.locator('#agent-clear-chat-confirm:visible').click();
    await expect(secondPage.getByText(prompt, { exact: true })).toBeHidden();

    const state = await agentV2.getState();
    expect(state.clearBodies).toHaveLength(1);
    expect(state.messages).toEqual([]);
    expect(state.requests.map(({ method, path }) => `${method} ${path}`)).toEqual(expect.arrayContaining([
      'GET /api/v2/threads/default',
      expect.stringMatching(/^POST \/api\/v2\/threads\/[^/]+\/clear$/u),
    ]));
    const messageHistoryRequest = state.requests.find(({ method, path }) => (
      method === 'GET' && /^\/api\/v2\/threads\/[^/]+\/messages\?/u.test(path)
    ));
    expect(messageHistoryRequest).toBeDefined();
    const messageHistoryUrl = new URL(messageHistoryRequest!.path, 'http://localhost');
    expect(messageHistoryUrl.pathname).toMatch(/^\/api\/v2\/threads\/[^/]+\/messages$/u);
    expect(Object.fromEntries(messageHistoryUrl.searchParams))
      .toEqual({ limit: '100' });
    await secondPage.close();
  });

  test('loads an older page when the conversation reaches its backward boundary', async ({ agentV2, page }) => {
    await agentV2.reset('pagination');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.acceptConsent();

    await expect(page.getByText('Latest seeded answer', { exact: true })).toBeVisible();
    const conversation = getAgentV2Conversation(page);
    await conversation.evaluate((element) => {
      element.scrollTop = 0;
      element.dispatchEvent(new Event('scroll'));
    });
    await expect(page.getByText('Oldest seeded question', { exact: true })).toBeAttached();

    const state = await agentV2.getState();
    expect(state.requests.some(({ path }) => path.includes('cursor=older'))).toBe(true);
  });
});

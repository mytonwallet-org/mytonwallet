import type { Page } from '@playwright/test';

import { expect, getAgentV2Conversation, test } from './fixtures';

test.describe('Agent V2 deterministic conversation', () => {
  test('crossfades the whole chat list from placeholders, including News', async ({ agentV2, page }) => {
    await agentV2.reset('news-post');
    await agentV2.seedWallet();
    let releaseList: () => void;
    const listMayFinish = new Promise<void>((resolve) => {
      releaseList = resolve;
    });
    await page.route(/\/api\/v2\/threads(?:\?|$)/u, async (route) => {
      if (route.request().method() === 'GET') await listMayFinish;
      await route.continue();
    });
    await agentV2.open();
    const list = page.getByRole('region', { name: 'Chats', exact: true });
    const skeleton = list.getByRole('status', { name: 'Loading...', exact: true });
    await expect(skeleton).toBeVisible();
    await expect(list.getByRole('button', { name: /^News,/u })).toHaveCount(0);
    const fading = list.evaluate(async (element) => {
      let hasCrossfade = false;
      for (let frame = 0; frame < 50; frame++) {
        const placeholder = element.querySelector('[role="status"]');
        const body = element.querySelector('.custom-scroll');
        if (placeholder && body) {
          const from = Number(getComputedStyle(placeholder).opacity);
          const to = Number(getComputedStyle(body).opacity);
          hasCrossfade ||= from > 0 && from < 1 && to > 0 && to < 1;
        }
        await new Promise(requestAnimationFrame);
      }
      return hasCrossfade;
    });
    releaseList!();
    await expect(list.getByRole('button', { name: /^News,/u })).toBeVisible();
    expect(await fading).toBe(true);
    await expect(skeleton).toHaveCount(0);
  });

  test('morphs news follow-up placeholders into buttons without shifting the chat', async ({ agentV2, page }) => {
    await page.setViewportSize({ width: 390, height: 500 });
    await agentV2.reset('news-post');
    await agentV2.seedWallet();
    await page.route('**/api/v2/news-feed?*', async (route) => {
      const response = await route.fetch();
      const feed = await response.json();
      feed.items[0].discussion = { threadId: '44444444-4444-4444-8444-444444444444' };
      await route.fulfill({ response, json: feed });
    });
    let releaseHistory: () => void;
    const historyMayFinish = new Promise<void>((resolve) => {
      releaseHistory = resolve;
    });
    await page.route('**/api/v2/threads/*/messages?*', async (route) => {
      const response = await route.fetch();
      const history = await response.json();
      history.messages[0].followups = Array.from({ length: 3 }, (_, index) => ({
        id: `adadadad-adad-4dad-8dad-adadadadada${index}`,
        kind: 'suggested_prompt',
        text: `Explain this update ${index}`,
      }));
      await historyMayFinish;
      await route.fulfill({ json: history });
    });
    await agentV2.open();
    await agentV2.waitForList();
    await page.getByRole('button', { name: /^News,/u }).click();
    await page.getByRole('button', { name: 'Discuss, Deterministic MyPulse headline', exact: true }).click();
    await expect(page.locator('[data-agent-news-post-event-id="5"]')).toBeVisible();
    await expect(page.locator('[data-agent-followup-placeholder]')).toHaveCount(3);
    // Let the card finish its own flight before measuring the later follow-up scroll
    await page.waitForTimeout(600);
    const conversation = getAgentV2Conversation(page);
    const offsets = conversation.evaluate(async (element) => {
      const samples: number[] = [];
      let hasAnimatedButton = false;
      for (let frame = 0; frame < 70; frame++) {
        samples.push(element.scrollTop);
        hasAnimatedButton ||= Array.from(element.querySelectorAll('[data-agent-followup-id]'))
          .some((button) => button.getAnimations().some((animation) => animation.playState === 'running'));
        await new Promise(requestAnimationFrame);
      }
      return { samples, hasAnimatedButton };
    });
    releaseHistory!();
    await expect(page.getByRole('button', { name: 'Explain this update 2', exact: true })).toBeVisible();
    const { samples, hasAnimatedButton } = await offsets;
    expect(Math.max(...samples) - Math.min(...samples)).toBeLessThan(2);
    expect(hasAnimatedButton).toBe(true);
    await expect(page.locator('[data-agent-followup-placeholder]')).toHaveCount(0);
  });

  test('opens MyPulse as one post without a run and appends the first question', async ({ agentV2, page }) => {
    await agentV2.reset('news-post');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.waitForList();
    await page.getByRole('button', { name: /^News,/u }).click();

    let releaseCreation: () => void;
    const creationMayFinish = new Promise<void>((resolve) => {
      releaseCreation = resolve;
    });
    let creationCount = 0;
    await page.route('**/api/v2/threads', async (route) => {
      if (route.request().method() === 'POST') {
        creationCount += 1;
        await creationMayFinish;
      }
      await route.continue();
    });
    await page.getByRole('button', { name: 'Discuss, Deterministic MyPulse headline', exact: true }).click();

    const post = page.locator('[data-agent-news-post-event-id="5"]');
    await expect(post).toBeVisible();
    await expect(post).toContainText(`The full MyPulse news body. ${'Market context. '.repeat(20)}`.trim());
    await expect(getAgentV2Conversation(page).getByRole('status')).toHaveCount(0);
    expect((await agentV2.getState()).runBodies).toHaveLength(0);
    // A discussion the user hasn't written in has nothing to delete, and its menu, without items, no button
    const menuButton = page.getByRole('button', { name: 'Open Menu', exact: true });
    await expect(menuButton).toHaveCount(0);
    const previewElement = await post.elementHandle();
    const composer = page.getByRole('textbox', { name: 'Ask anything', exact: true });
    await expect(composer).toBeEnabled();
    await page.evaluate(() => new Promise<void>((resolve) => {
      requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
    }));
    expect(creationCount).toBe(0);
    await expect(post).toHaveCount(1);
    expect((await agentV2.getState()).runBodies).toHaveLength(0);

    const prompt = 'What does this news mean?';
    await composer.fill(prompt);
    const messagesLoaded = page.waitForResponse((response) => (
      response.request().method() === 'GET' && /\/api\/v2\/threads\/[^/]+\/messages\?/u.test(response.url())
    ));
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expect(getAgentV2Conversation(page).getByText(prompt, { exact: true })).toBeVisible();
    await expect.poll(() => creationCount).toBe(1);
    releaseCreation!();
    await messagesLoaded;
    await expect(page.getByText(`Deterministic response: ${prompt}`, { exact: true })).toBeVisible();
    await expect(post).toHaveCount(1);
    expect(await post.evaluate((element, preview) => element === preview, previewElement)).toBe(true);
    await menuButton.click();
    await expect(page.getByText('Delete Chat', { exact: true }).last()).toBeVisible();
    await page.keyboard.press('Escape');

    const state = await agentV2.getState();
    expect(state.messages.filter(({ newsPost }) => newsPost)).toHaveLength(1);
    expect(state.runBodies).toHaveLength(1);
    expect(state.runBodies[0]).toMatchObject({
      input: { kind: 'append', message: { text: prompt } },
    });
    expect(state.runBodies[0]).not.toHaveProperty('entryPoint');
  });

  test('waits for existing MyPulse discussion history before showing its post', async ({ agentV2, page }) => {
    await agentV2.reset('news-post');
    await agentV2.seedWallet();
    const threadId = '88888888-8888-4888-8888-888888888888';
    const createdAt = '2026-08-11T09:00:00.000Z';
    const news = {
      eventId: 5,
      headline: 'Deterministic MyPulse headline',
      body: 'Saved news body',
      publishedAt: createdAt,
    };
    const thread = {
      id: threadId, revision: 1, createdAt, updatedAt: createdAt, lastActivityAt: createdAt,
      messageCount: 3, title: 'Existing MyPulse discussion', news,
    };
    await page.route('**/api/v2/news-feed?*', async (route) => {
      const response = await route.fetch();
      const feed = await response.json();
      feed.items[0].discussion = { threadId };
      await route.fulfill({ response, json: feed });
    });
    await page.route('**/api/v2/threads?*', (route) => route.fulfill({
      json: { protocolVersion: 3, threads: [{ thread }] },
    }));
    let releaseHistory!: () => void;
    const historyMayFinish = new Promise<void>((resolve) => {
      releaseHistory = resolve;
    });
    await page.route(`**/api/v2/threads/${threadId}/messages?*`, async (route) => {
      await historyMayFinish;
      await route.fulfill({ json: {
        protocolVersion: 3,
        thread,
        messages: [
          { role: 'assistant', text: '**Deterministic MyPulse headline**\n\nSaved news body', newsPost: true },
          { role: 'user', text: 'Earlier question' },
          { role: 'assistant', text: 'Earlier answer' },
        ].map(({ text, ...message }, index) => ({
          ...message,
          id: `00000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
          threadId, createdAt, status: 'complete', content: { kind: 'markdown', text },
        })),
      } });
    });
    await agentV2.open();
    await agentV2.waitForList();
    await expect(page.getByRole('button', { name: /Existing MyPulse discussion/u })).toBeVisible();
    await page.getByRole('button', { name: /^News,/u }).click();
    const historyRequested = page.waitForRequest((request) => request.url().includes(`/threads/${threadId}/messages?`));
    await page.getByRole('button', { name: 'Continue discussing Deterministic MyPulse headline', exact: true }).click();
    await historyRequested;

    const post = page.locator('[data-agent-news-post-event-id="5"]');
    await expect(post).toHaveCount(0);
    await expect(page.getByText('Earlier answer', { exact: true })).toHaveCount(0);
    await expect(page.locator('[data-agent-skeleton-role="user"]').first()).toBeVisible();
    // The post grows out of a placeholder through a stand-in of its bubble
    const hasMorph = page.evaluate(async () => {
      for (let frame = 0; frame < 70; frame++) {
        const postBubble = document.querySelector<HTMLElement>(
          '[data-agent-news-post-event-id="5"] [class*="__bubble__"]',
        );
        const index = postBubble?.dataset.agentHistoryRevealIndex;
        if (index !== undefined && document.querySelector(`[data-agent-history-stand-in="${index}"]`)) return true;
        await new Promise(requestAnimationFrame);
      }
      return false;
    });
    releaseHistory();
    await expect(page.getByText('Earlier answer', { exact: true })).toBeVisible();
    await expect(post).toBeVisible();
    await expect(post).toHaveCount(1);
    expect(await hasMorph).toBe(true);
    expect((await agentV2.getState()).runBodies).toHaveLength(0);
  });

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
    await agentV2.waitForList();

    const prompt = 'Explain this wallet using the default agent';
    await agentV2.send(prompt);
    await expect(page.getByText(`Deterministic response: ${prompt}`, { exact: true })).toBeVisible();
    const state = await agentV2.getState();
    expect(state.runBodies).toHaveLength(1);
    expect(state.requests.some(({ path }) => path.startsWith('/api/v2/threads'))).toBe(true);
  });

  test('preserves the wallet session within one tab and isolates it across tabs', async ({
    agentV2,
    context,
    page,
  }) => {
    await agentV2.reset();
    await agentV2.seedWallet();
    await agentV2.open();

    await agentV2.waitForList();

    const prompt = 'Explain this deterministic wallet';
    // The answer streams for about half a second, partly while the chat fades in over the list, so every status it
    // takes is recorded from the moment the question is sent
    await recordAnswerStatuses(page);
    await agentV2.send(prompt);
    await expect.poll(() => getAnswerStatuses(page)).toContain('streaming');
    const assistantMessage = page.locator('[data-agent-v2-message-role="assistant"]').last();
    await expect(getAgentV2Conversation(page).getByText(prompt, { exact: true })).toBeVisible();
    await expect(assistantMessage
      .filter({ hasText: `Deterministic response: ${prompt}` }))
      .toHaveAttribute('data-agent-v2-message-status', 'complete');
    const initialState = await agentV2.getState();
    const initialSessionId = initialState.runBodies[0].walletContext.sessionId;

    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.getByRole('button', { name: 'Agent', exact: true }).last().click();
    await agentV2.openThread();
    await expect(getAgentV2Conversation(page).getByText(prompt, { exact: true })).toBeVisible();
    await expect(page.getByText(`Deterministic response: ${prompt}`, { exact: true })).toBeVisible();

    const reloadPrompt = 'Confirm the reloaded wallet session';
    await agentV2.send(reloadPrompt);
    await expect(page.getByText(`Deterministic response: ${reloadPrompt}`, { exact: true })).toBeVisible();
    const reloadedState = await agentV2.getState();
    expect(reloadedState.runBodies[1].walletContext.sessionId).toBe(initialSessionId);

    const secondPage = await context.newPage();
    await agentV2.openPage(secondPage);
    await agentV2.openThreadFromPage(secondPage);
    const secondTabPrompt = 'Confirm the isolated wallet session';
    await agentV2.sendFromPage(secondPage, secondTabPrompt);
    await expect(secondPage.getByText(`Deterministic response: ${secondTabPrompt}`, { exact: true })).toBeVisible();
    const secondTabState = await agentV2.getState();
    expect(secondTabState.runBodies[2].walletContext.sessionId).not.toBe(initialSessionId);

    await secondPage.getByRole('button', { name: 'Open Menu', exact: true }).click();
    await secondPage.getByText('Delete Chat', { exact: true }).last().click();
    await secondPage.getByRole('dialog').getByRole('button', { name: 'Delete', exact: true }).click();
    // The deleted chat closes to the chat list, which no longer has it
    await expect(secondPage.getByRole('button', { name: 'Back', exact: true })).toHaveCount(0);
    await expect(secondPage.locator('[data-agent-v2-thread-id]')).toHaveCount(0);

    const state = await agentV2.getState();
    expect(state.deleteBodies).toHaveLength(1);
    expect(state.deleteBodies[0].clientOperationId).toEqual(expect.any(String));
    expect(state.messages).toEqual([]);
    expect(state.requests.map(({ method, path }) => `${method} ${path}`)).toEqual(expect.arrayContaining([
      'POST /api/v2/threads',
      expect.stringMatching(/^POST \/api\/v2\/threads\/[^/]+\/delete$/u),
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

  test('opens a chat seen just before with its messages at once, without the placeholder', async ({
    agentV2, page,
  }) => {
    await agentV2.reset();
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.waitForList();
    await agentV2.send('Remember this chat');
    const answer = getAgentV2Conversation(page)
      .getByText('Deterministic response: Remember this chat', { exact: true });
    await expect(answer).toBeVisible({ timeout: 15000 });
    await expect(page.getByRole('status')).toHaveCount(0);

    await page.getByRole('button', { name: 'Back', exact: true }).click();
    await expect(page.getByRole('region', { name: 'Chats', exact: true })).toBeVisible();
    // The chat has left the page, and kept its history as it went
    await expect(page.locator('[data-agent-v2-message-role]')).toHaveCount(0);
    // Whether the history placeholder shows at any point while the chat opens again
    await page.evaluate(() => {
      const observer = new MutationObserver(() => {
        if (document.querySelector('[data-agent-skeleton]')) document.body.dataset.hasSeenSkeleton = 'true';
      });
      observer.observe(document.body, { childList: true, subtree: true });
    });
    await agentV2.openThread();

    await expect(answer).toBeVisible();
    expect(await page.evaluate(() => document.body.dataset.hasSeenSkeleton)).toBeUndefined();
  });

  test('loads an older page when the conversation reaches its backward boundary', async ({ agentV2, page }) => {
    await agentV2.reset('pagination');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.waitForList();
    await agentV2.openThread();

    await expect(page.getByText('Latest seeded answer', { exact: true })).toBeVisible();
    const conversation = getAgentV2Conversation(page);
    await conversation.evaluate((element) => {
      element.scrollTop = 0;
      element.dispatchEvent(new Event('scroll'));
    });
    await expect(getAgentV2Conversation(page).getByText('Oldest seeded question', { exact: true })).toBeAttached();

    const state = await agentV2.getState();
    expect(state.requests.some(({ path }) => path.includes('cursor=older'))).toBe(true);
  });
});

type WindowWithAnswerStatuses = Window & { agentV2AnswerStatuses?: string[] };

function recordAnswerStatuses(page: Page) {
  return page.evaluate(() => {
    const statuses: string[] = [];
    (window as WindowWithAnswerStatuses).agentV2AnswerStatuses = statuses;
    new MutationObserver(() => {
      document.querySelectorAll('[data-agent-v2-message-role="assistant"]').forEach((element) => {
        const status = element.getAttribute('data-agent-v2-message-status');
        if (status && !statuses.includes(status)) statuses.push(status);
      });
    }).observe(document.body, {
      subtree: true, childList: true, attributes: true, attributeFilter: ['data-agent-v2-message-status'],
    });
  });
}

function getAnswerStatuses(page: Page) {
  return page.evaluate(() => (window as WindowWithAnswerStatuses).agentV2AnswerStatuses ?? []);
}

import type { Page } from '@playwright/test';

import type { AgentV2Fixture } from './fixtures';

import { expect, test } from './fixtures';

// The sheet's slide in and the app's modal transition, with a margin
const SHEET_SETTLE_MS = 700;

test.describe('Agent V2 consent sheet', () => {
  test('asks at the first question, keeps the draft when closed and sends it once on Allow', async ({
    agentV2,
    page,
  }) => {
    await agentV2.reset();
    await agentV2.seedWallet(false, false);
    await agentV2.open();

    // The list shows without asking: its field, and no sheet or request to the Agent
    const field = page.getByRole('textbox', { name: 'Ask anything' });
    const allow = page.getByRole('button', { name: 'Allow the agent', exact: true });
    await expect(field).toBeVisible();
    await expect(allow).toBeHidden();
    const initialState = await agentV2.getState();
    expect(initialState.requests.some(({ path }) => path.startsWith('/api/v2/threads'))).toBe(false);

    await field.fill('Explain consent');
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expect(allow).toBeVisible();

    // Closing it sends nothing and keeps the question in the field, which gets its focus back
    await page.keyboard.press('Escape');
    await expect(allow).toBeHidden();
    await expect(field).toHaveValue('Explain consent');
    await expect(field).toBeFocused();
    expect((await agentV2.getState()).runBodies).toHaveLength(0);

    // The next send asks again; Allow sends the question once
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expect(allow).toBeVisible();
    await allow.click();
    await expect(allow).toBeHidden();
    await expect(page.getByRole('button', { name: 'Back', exact: true })).toBeVisible();
    await expect.poll(async () => (await agentV2.getState()).runBodies.length).toBe(1);
    expect((await agentV2.getState()).runBodies[0]).toMatchObject({
      input: { kind: 'append', message: { text: 'Explain consent' } },
    });
  });

  test('keeps the consent: after a reload, a question goes without the sheet', async ({ agentV2, page }) => {
    await agentV2.reset();
    await agentV2.seedWallet(false, false);
    await agentV2.open();
    const allow = page.getByRole('button', { name: 'Allow the agent', exact: true });
    await page.getByRole('textbox', { name: 'Ask anything' }).fill('First question');
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await allow.click();
    await expect.poll(async () => (await agentV2.getState()).runBodies.length).toBe(1);

    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.getByRole('button', { name: 'Agent', exact: true }).last().click();
    await agentV2.waitForList();
    await agentV2.send('Second question');
    await expect(allow).toBeHidden();
    await expect.poll(async () => (await agentV2.getState()).runBodies.length).toBe(2);
  });

  test('reads News and opens a discussion before consent, which asks before it sends, then sends once', async ({
    agentV2,
    page,
  }) => {
    await agentV2.reset('news-post');
    await agentV2.seedWallet(false, false);
    await agentV2.open();
    await agentV2.waitForList();
    await page.getByRole('button', { name: /^News,/u }).click();
    await page.getByRole('button', { name: 'Discuss, Deterministic MyPulse headline', exact: true }).click();

    // The discussion opens with the feed's post and the composer, and creates its thread for the first question
    const post = page.locator('[data-agent-news-post-event-id="5"]');
    const allow = page.getByRole('button', { name: 'Allow the agent', exact: true });
    await expect(post).toBeVisible();
    await expect(allow).toBeHidden();
    const isThreadCreated = ({ method, path }: { method: string; path: string }) => (
      method === 'POST' && path === '/api/v2/threads'
    );
    const prompt = 'What does this news mean?';
    const composer = page.getByRole('textbox', { name: 'Ask anything', exact: true });
    await composer.fill(prompt);
    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await expect(allow).toBeVisible();
    // The sheet takes keys a few frames after it shows, as the app's modals and menus do
    await page.evaluate(() => new Promise<void>((resolve) => {
      requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
    }));
    await page.keyboard.press('Escape');
    await expect(allow).toBeHidden();
    await expect(composer).toHaveValue(prompt);
    await expect(composer).toBeFocused();
    expect((await agentV2.getState()).runBodies).toHaveLength(0);
    expect((await agentV2.getState()).requests.filter(isThreadCreated)).toHaveLength(0);

    await page.getByRole('button', { name: 'Send', exact: true }).click();
    await allow.click();
    await expect(page.getByText(`Deterministic response: ${prompt}`, { exact: true })).toBeVisible();
    await expect(post).toHaveCount(1);
    const { requests, runBodies } = await agentV2.getState();
    expect(requests.filter(isThreadCreated)).toHaveLength(1);
    expect(requests.find(isThreadCreated)?.body)
      .toEqual({ protocolVersion: 3, news: { eventId: 5, locale: expect.any(String) } });
    expect(runBodies).toHaveLength(1);
    expect(runBodies[0]).toMatchObject({ input: { kind: 'append', message: { text: prompt } } });
  });

  // The sheet is as tall as its content where the screen has room for it, with nothing left to scroll. On a screen too
  // short for it, its text scrolls above Allow, which stays in view.
  for (const { name, width, height, canFit } of [
    { name: 'a desktop', width: 1280, height: 800, canFit: true },
    { name: 'a phone', width: 390, height: 844, canFit: true },
    { name: 'a short desktop', width: 1280, height: 420, canFit: false },
    { name: 'a short phone', width: 390, height: 480, canFit: false },
  ]) {
    test(`fits ${name} screen ${canFit ? 'without a scroll' : 'with its text scrolling above Allow'}`, async ({
      agentV2,
      page,
    }) => {
      await page.setViewportSize({ width, height });
      const allow = await openConsentSheet(agentV2, page);

      const layout = await page.locator('[class*="__consentScroll__"]').evaluate((scroll) => {
        const content = scroll.parentElement!;
        const dialog = content.parentElement!.getBoundingClientRect();
        return {
          textOverflow: scroll.scrollHeight - scroll.clientHeight,
          contentOverflow: content.scrollHeight - content.clientHeight,
          dialogTop: dialog.top,
          dialogBottom: dialog.bottom,
        };
      });
      const allowBox = (await allow.boundingBox())!;
      expect(layout.contentOverflow).toBe(0);
      expect(layout.dialogTop).toBeGreaterThanOrEqual(0);
      expect(layout.dialogBottom).toBeLessThanOrEqual(height);
      expect(allowBox.y + allowBox.height).toBeLessThanOrEqual(height);
      if (canFit) {
        expect(layout.textOverflow).toBe(0);
      } else {
        expect(layout.textOverflow).toBeGreaterThan(0);
      }
    });
  }

  test('grows the top beside its title over the header while it is held, without moving the title', async ({
    agentV2,
    page,
  }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    const allow = await openConsentSheet(agentV2, page);
    const top = page.locator('[class*="__consentTitleIcon__"]');
    const title = page.locator('[class*="__consentTitle__"]');
    await expect(top).toBeVisible();
    test.skip(await top.evaluate((element) => !element.querySelector('canvas')), 'The 3D top needs WebGL2');

    const titleBox = await title.boundingBox();
    const topBox = (await top.boundingBox())!;
    await page.mouse.move(topBox.x + topBox.width / 2, topBox.y + topBox.height / 2);
    await page.mouse.down();

    // Held, the top draws on a canvas over the window, above the sheet, and the title keeps its place
    const lifted = page.locator('body > canvas[aria-hidden="true"]');
    await expect(lifted).toHaveCount(1);
    await page.waitForTimeout(SHEET_SETTLE_MS);
    const sheetLayer = await page.getByRole('dialog').filter({ has: allow })
      .evaluate((element) => Number(getComputedStyle(element).zIndex));
    expect(await lifted.evaluate((canvas) => Number(getComputedStyle(canvas).zIndex))).toBeGreaterThan(sheetLayer);
    const liftedBox = (await lifted.boundingBox())!;
    expect(liftedBox.width).toBeGreaterThan(topBox.width * 3);
    expect(liftedBox.height).toBeGreaterThan(topBox.height * 3);
    expect(await title.boundingBox()).toEqual(titleBox);

    // Let go, it settles back into its place in the header, and the sheet stays open
    await page.mouse.up();
    await expect(lifted).toHaveCount(0, { timeout: 5000 });
    expect(await title.boundingBox()).toEqual(titleBox);
    await expect(allow).toBeVisible();
  });
});

async function openConsentSheet(agentV2: AgentV2Fixture, page: Page) {
  await agentV2.reset();
  await agentV2.seedWallet(false, false);
  await agentV2.open();
  await page.getByRole('textbox', { name: 'Ask anything' }).fill('Explain consent');
  await page.getByRole('button', { name: 'Send', exact: true }).click();
  const allow = page.getByRole('button', { name: 'Allow the agent', exact: true });
  await expect(allow).toBeVisible();
  await page.waitForTimeout(SHEET_SETTLE_MS);
  return allow;
}

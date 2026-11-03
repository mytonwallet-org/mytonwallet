import type { Page } from '@playwright/test';

import { expect, getAgentV2Conversation, test } from './fixtures';

const PHONE = { width: 402, height: 874 };
const DESKTOP = { width: 1280, height: 720 };

// The landscape layout holds the Agent beside the wallet
const LANDSCAPE_LAYOUT_SELECTOR = '[class*="landscapeContainer"]';

// Portrait and landscape mount the Agent separately: the incoming layout's field is the only one once it has mounted
async function resizeAcrossBreakpoint(page: Page, size: typeof PHONE) {
  await page.setViewportSize(size);
  const fields = page.getByRole('textbox', { name: 'Ask anything' });
  await expect(page.locator(LANDSCAPE_LAYOUT_SELECTOR).getByRole('textbox', { name: 'Ask anything' }))
    .toHaveCount(size === DESKTOP ? 1 : 0);
  await expect(fields).toHaveCount(1);
}

test.describe('Agent V2 across the phone breakpoint', () => {
  test('keeps the question typed under the chat list', async ({ agentV2, page }) => {
    await agentV2.reset('pagination');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.acceptConsent();

    const field = page.getByRole('textbox', { name: 'Ask anything' });
    await field.fill('A question in progress');
    await expect(field).toHaveValue('A question in progress');
    await expect(page.getByRole('heading', { name: 'New Chat' })).toBeVisible();

    await resizeAcrossBreakpoint(page, PHONE);
    await expect(field).toHaveValue('A question in progress');
    await expect(field).toBeFocused();
    await expect(page.getByRole('heading', { name: 'New Chat' })).toBeVisible();

    await resizeAcrossBreakpoint(page, DESKTOP);
    await expect(field).toHaveValue('A question in progress');
    await expect(field).toBeFocused();
  });

  test('keeps the open chat with its draft', async ({ agentV2, page }) => {
    await agentV2.reset('pagination');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.acceptConsent();
    await agentV2.openThread();

    const field = page.getByRole('textbox', { name: 'Ask anything' });
    await expect(page.getByText('Latest seeded answer', { exact: true })).toBeVisible();
    await field.fill('A follow-up in progress');
    await expect(field).toHaveValue('A follow-up in progress');

    await resizeAcrossBreakpoint(page, PHONE);
    await expect(getAgentV2Conversation(page).getByText('Latest seeded answer', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Back', exact: true })).toBeVisible();
    await expect(field).toHaveValue('A follow-up in progress');
    await expect(field).toBeFocused();

    await resizeAcrossBreakpoint(page, DESKTOP);
    await expect(getAgentV2Conversation(page).getByText('Latest seeded answer', { exact: true })).toBeVisible();
    await expect(field).toHaveValue('A follow-up in progress');

    // The draft belongs to that chat; the list's own field stays empty
    await page.getByRole('button', { name: 'Back', exact: true }).click();
    await expect(page.getByRole('region', { name: 'Chats' })).toBeVisible();
    await expect(field).toHaveCount(1);
    await expect(field).toHaveValue('');
  });

  test('keeps the sent question pinned under the header while its answer comes', async ({ agentV2, page }) => {
    await agentV2.reset('run-activity');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.acceptConsent();

    await agentV2.send('Research the latest TON update');
    await expect(page.getByText('Deterministic response: Research the latest TON update', { exact: true }))
      .toBeVisible({ timeout: 15000 });
    await expect(page.getByRole('status')).toHaveCount(0);

    // A question asked in the chat is pinned under the header, and the answer comes in the room under it
    await agentV2.send('What changed since then?');
    await page.getByRole('status').locator('[data-agent-activity-step]').first().waitFor();
    await expectQuestionPinned(page);

    await resizeAcrossBreakpoint(page, PHONE);
    await expectQuestionPinned(page);
    await expect(page.getByText('Deterministic response: What changed since then?', { exact: true }))
      .toBeVisible({ timeout: 15000 });
    await expectQuestionPinned(page);

    await resizeAcrossBreakpoint(page, DESKTOP);
    await expectQuestionPinned(page);
  });
});

// The question stands at the top of the chat, with the room under it kept for the answer, rather than over the field
async function expectQuestionPinned(page: Page) {
  const question = getAgentV2Conversation(page).locator('[data-agent-v2-message-role="user"]').last();
  await expect(question).toBeVisible();
  await expect.poll(async () => (await question.boundingBox())?.y ?? Infinity)
    .toBeLessThan(page.viewportSize()!.height / 3);
}

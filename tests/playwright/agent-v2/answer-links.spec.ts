import type { Page } from '@playwright/test';

import { expect, test } from './fixtures';

test.describe('Agent V2 answer links', () => {
  test('shows an answer link over its label from the first revealed character and from history', async ({
    agentV2,
    page,
  }) => {
    await agentV2.reset('answer-links');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.acceptConsent();

    await agentV2.send('Where are the TON docs?');
    const answer = getAnswer(page);
    const partialLink = answer.getByRole('link', { name: 'TON', exact: true });
    await expect(partialLink).toHaveAttribute('href', 'https://docs.ton.org/develop');
    await expect(answer).toHaveAttribute('data-agent-v2-message-status', 'streaming');

    await agentV2.completeRun();
    await expectDocsLink(page);

    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.getByRole('button', { name: 'Agent', exact: true }).last().click();
    await expectDocsLink(page);
  });

  test('keeps valid links and leaves the labels of malformed ones as text, live and from history', async ({
    agentV2,
    page,
  }) => {
    // The app's error handler logs a failed update handler instead of throwing it
    const agentErrors: string[] = [];
    page.on('pageerror', (error) => agentErrors.push(error.message));
    page.on('console', (message) => {
      if (message.type() === 'error' && message.text().includes('Agent V2')) agentErrors.push(message.text());
    });
    await agentV2.reset('answer-link-events');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.acceptConsent();

    await agentV2.send('Where can I read about TON?');
    await expectSiteLinkOnly(page);
    await expect(page.getByText('Response interrupted', { exact: true })).toHaveCount(0);
    await expect(page.getByRole('textbox', { name: 'Ask anything' })).toBeEnabled();

    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.getByRole('button', { name: 'Agent', exact: true }).last().click();
    await expectSiteLinkOnly(page);
    expect(agentErrors).toEqual([]);
  });
});

function getAnswer(page: Page) {
  return page.locator('[data-agent-v2-message-role="assistant"]').last();
}

async function expectDocsLink(page: Page) {
  const answer = getAnswer(page);
  await expect(answer.getByText('Read the TON docs before you build.', { exact: true })).toBeVisible();
  await expect(answer).toHaveAttribute('data-agent-v2-message-status', 'complete');
  const link = answer.getByRole('link');
  await expect(link).toHaveCount(1);
  await expect(link).toHaveText('TON docs');
  await expect(link).toHaveAttribute('href', 'https://docs.ton.org/develop');
  await expect(link).toHaveAttribute('target', '_blank');
  await expect(link).toHaveAttribute('rel', 'noopener noreferrer');
}

async function expectSiteLinkOnly(page: Page) {
  const answer = getAnswer(page);
  await expect(answer.getByText('Open TON site, docs and blog.', { exact: true })).toBeVisible();
  await expect(answer).toHaveAttribute('data-agent-v2-message-status', 'complete');
  const link = answer.getByRole('link');
  await expect(link).toHaveCount(1);
  await expect(link).toHaveText('TON site');
  await expect(link).toHaveAttribute('href', 'https://ton.org/');
}

import { expect, test } from './fixtures';

test.use({ launchOptions: { args: ['--enable-unsafe-swiftshader'] } });

for (const width of [390, 1280]) {
  test(`shows suggestions, focuses the field on return to the Agent and keeps News accessible at ${width}px`, async ({
    agentV2, page, context,
  }) => {
    await page.setViewportSize({ width, height: 844 });
    await agentV2.reset();
    await agentV2.seedWallet();
    // One hint of each group, so that the pick shows them all
    await context.route('**/api/v2/hints/pool*', (route) => route.fulfill({
      json: {
        protocolVersion: 3,
        catalogVersion: 'agent-starter-hints-v2',
        items: [{ id: 'agent.capabilities', group: 'learn' }, { id: 'receive.tokens', group: 'wallet' }],
      },
    }));
    await agentV2.open();
    await agentV2.waitForList();
    await expect(page.getByRole('button', { name: 'Back', exact: true })).toBeHidden();
    const walletTab = page.getByRole('button', { name: 'Wallet', exact: true }).last();
    await expect(walletTab).toBeVisible();
    await walletTab.click();
    await expect(page.getByRole('region', { name: 'Chats', exact: true })).toBeHidden();
    const agentTab = page.getByRole('button', { name: 'Agent', exact: true }).last();
    await expect(agentTab).toBeVisible();
    await agentTab.click();
    await agentV2.waitForList();
    const hint = page.getByRole('button', { name: 'What can you do?', exact: true });
    await expect(hint).toBeVisible();
    // A desktop gives the field the focus as the list comes back on screen
    await expect(page.getByRole('textbox', { name: 'Ask anything' })).toBeFocused();
    await expect(page.getByText('Ask a question to start a new chat.', { exact: true })).toHaveCount(0);
    await expect(page.getByRole('button', { name: /^News,/u })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Receive tokens', exact: true })).toBeVisible();
    await page.screenshot({ path: test.info().outputPath('empty-list.png'), animations: 'disabled' });
    await page.getByRole('button', { name: /^News,/u }).click();
    await expect(page.getByRole('button', { name: 'Back', exact: true })).toBeVisible();
  });
}

import { expect, getAgentV2Conversation, test } from './fixtures';

test.describe('Agent V2 support request', () => {
  test('calls support from the chat header once the user confirms', async ({ agentV2, page }) => {
    await agentV2.reset();
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.send('What is TON?');
    await expect(getAgentV2Conversation(page).getByText('Deterministic response: What is TON?', { exact: true }))
      .toBeVisible({ timeout: 15000 });
    const { runCount } = await agentV2.getState();

    const contactSupport = page.getByRole('button', { name: 'Contact support', exact: true });
    await expect(contactSupport).toBeEnabled();
    await contactSupport.click();
    const sheet = page.getByRole('dialog');
    await expect(sheet.getByText('Call an operator?', { exact: true })).toBeVisible();
    await sheet.getByRole('button', { name: 'Cancel', exact: true }).click();
    await expect(sheet).toBeHidden();
    expect((await agentV2.getState()).runCount).toBe(runCount);

    await contactSupport.click();
    await sheet.getByRole('button', { name: 'Call', exact: true }).click();
    await expect.poll(async () => (await agentV2.getState()).runBodies.slice(runCount))
      .toEqual([expect.objectContaining({ entryPoint: { kind: 'supportRequest', source: 'header' } })]);
  });
});

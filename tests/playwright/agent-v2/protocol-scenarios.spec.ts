import { expect, getAgentV2Conversation, test } from './fixtures';

test.describe('Agent V2 deterministic protocol scenarios', () => {
  test('shows one active server progress line until the answer starts', async ({ agentV2, page }) => {
    await page.setViewportSize({ width: 1160, height: 447 });
    await agentV2.reset('run-activity');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.acceptConsent();

    await agentV2.send('Research the latest TON update');
    await expect(page.getByRole('status')).toHaveText('Searching the web…');
    await expect(page.getByRole('status')).toHaveText('Reviewing sources…');
    await expect(page.getByRole('status')).toHaveText('Checking market data…');
    await expect(page.getByRole('status')).toHaveCount(1);
    const activityLayout = await page.getByRole('status').evaluate((status) => {
      const composer = document.querySelector('textarea')!;
      const statusRect = status.getBoundingClientRect();
      const composerRect = composer.getBoundingClientRect();

      return {
        statusHeight: statusRect.height,
        statusBottom: statusRect.bottom,
        composerTop: composerRect.top,
      };
    });
    expect(activityLayout.statusHeight).toBeLessThanOrEqual(40);
    expect(activityLayout.statusBottom).toBeLessThanOrEqual(activityLayout.composerTop);
    // The list scrolls to the pinned question with an animation
    await expect.poll(() => page.getByRole('status').evaluate((status) => {
      const conversation = status.closest('.custom-scroll')!;
      return conversation.scrollHeight - conversation.scrollTop - conversation.clientHeight;
    })).toBeLessThanOrEqual(1);
    await expect(page.getByText('Relevant sources found', { exact: true })).toHaveCount(0);
    await expect(page.getByText('Sources reviewed', { exact: true })).toHaveCount(0);
    await expect(page.getByText('Calculations complete', { exact: true })).toHaveCount(0);
    await expect(page.getByText('Research the latest TON update', { exact: true })).toBeVisible();
    await expect(page.getByText(
      'Deterministic response: Research the latest TON update', { exact: true },
    )).toBeVisible();
    await expect(page.getByRole('status')).toHaveCount(0);
  });

  test('keeps conversation position stable as the composer changes height', async ({ agentV2, page }) => {
    await page.setViewportSize({ width: 390, height: 447 });
    await agentV2.reset();
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.acceptConsent();

    const input = page.getByRole('textbox', { name: 'Ask anything' });
    for (let index = 1; index <= 4; index++) {
      const prompt = `Layout message ${index}`;
      await agentV2.send(prompt);
      await expect(page.locator('[data-agent-v2-message-role="assistant"]').filter({
        hasText: `Deterministic response: ${prompt}`,
      }))
        .toHaveAttribute('data-agent-v2-message-status', 'complete');
      await expect(input).toBeEnabled();
    }

    const conversation = getAgentV2Conversation(page);
    const enterMultilineText = async () => {
      const lines = Array.from({ length: 7 }, (_, index) => `Line ${index + 1}`);
      let text = '';
      await input.click();
      for (const line of lines) {
        if (text) {
          await input.press('Shift+Enter');
          text += '\n';
          await expect(input).toHaveValue(text);
        }
        await page.keyboard.insertText(line);
        text += line;
        await expect(input).toHaveValue(text);
      }
    };
    const readLayout = () => conversation.evaluate((element) => {
      const composerInput = document.querySelector<HTMLTextAreaElement>('textarea[placeholder="Ask anything"]');
      if (!composerInput) throw new Error('Agent composer was not found');

      let composerWrapper: HTMLElement | null = composerInput.parentElement;
      while (composerWrapper && getComputedStyle(composerWrapper).position !== 'absolute') {
        composerWrapper = composerWrapper.parentElement;
      }

      const messages = Array.from(element.querySelectorAll<HTMLElement>('[data-agent-v2-message-role]'));
      const lastMessage = messages.at(-1);
      if (!composerWrapper || !lastMessage) throw new Error('Agent conversation layout was not found');

      const wrapperRect = composerWrapper.getBoundingClientRect();
      return {
        inputHeight: composerInput.getBoundingClientRect().height,
        wrapperHeight: wrapperRect.height,
        paddingBottom: Number.parseFloat(getComputedStyle(element).paddingBottom),
        gap: wrapperRect.top - lastMessage.getBoundingClientRect().bottom,
        scrollTop: element.scrollTop,
        distanceToBottom: element.scrollHeight - element.scrollTop - element.clientHeight,
      };
    });

    await conversation.evaluate((element) => {
      element.scrollTo({ top: element.scrollHeight, behavior: 'instant' });
      element.dispatchEvent(new Event('scroll'));
    });
    await expect.poll(async () => (await readLayout()).distanceToBottom).toBeLessThanOrEqual(1);

    const singleLine = await readLayout();
    await enterMultilineText();
    await expect.poll(async () => {
      const layout = await readLayout();
      return layout.inputHeight > singleLine.inputHeight
        && layout.wrapperHeight > singleLine.wrapperHeight
        && layout.paddingBottom > singleLine.paddingBottom
        && layout.gap >= -1
        && layout.distanceToBottom <= 1;
    }).toBe(true);
    const multiline = await readLayout();

    expect(multiline.wrapperHeight).toBeGreaterThan(singleLine.wrapperHeight);
    expect(multiline.paddingBottom).toBeGreaterThan(singleLine.paddingBottom);
    expect(multiline.gap).toBeGreaterThanOrEqual(-1);
    expect(multiline.distanceToBottom).toBeLessThanOrEqual(1);

    const quotaButton = page.getByRole('button', { name: /^Agent quota:/u });
    await quotaButton.click();
    await expect(page.getByText(/Daily quota resets in/u)).toBeVisible();
    await expect.poll(async () => {
      const layout = await readLayout();
      return layout.wrapperHeight > multiline.wrapperHeight
        && layout.paddingBottom > multiline.paddingBottom
        && layout.gap >= -1
        && layout.distanceToBottom <= 1;
    }).toBe(true);
    const withQuota = await readLayout();

    expect(withQuota.paddingBottom).toBeGreaterThan(multiline.paddingBottom);
    expect(withQuota.gap).toBeGreaterThanOrEqual(-1);
    expect(withQuota.distanceToBottom).toBeLessThanOrEqual(1);

    await input.fill('');
    await expect(input).toHaveValue('');
    await quotaButton.click();
    await expect(page.getByText(/Daily quota resets in/u)).toHaveCount(0);
    await expect.poll(readLayout).toMatchObject({
      inputHeight: singleLine.inputHeight,
      wrapperHeight: singleLine.wrapperHeight,
      paddingBottom: singleLine.paddingBottom,
    });
    await input.click();
    const scrolledUpTop = await conversation.evaluate((element) => {
      const nextScrollTop = (element.scrollHeight - element.clientHeight) / 2;
      element.scrollTo({ top: nextScrollTop, behavior: 'instant' });
      element.dispatchEvent(new Event('scroll'));
      return element.scrollTop;
    });
    expect(scrolledUpTop).toBeGreaterThan(0);

    const collapsed = await readLayout();
    await enterMultilineText();
    await expect.poll(async () => {
      const layout = await readLayout();
      return layout.inputHeight > collapsed.inputHeight
        && layout.paddingBottom > collapsed.paddingBottom;
    }).toBe(true);
    const afterScrolledUpResize = await readLayout();
    expect(afterScrolledUpResize.scrollTop).toBeCloseTo(scrolledUpTop, 0);
  });

  test('retries an admitted quota failure exactly, then starts an independent send', async ({ agentV2, page }) => {
    await agentV2.reset('quota-retry');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.acceptConsent();

    await agentV2.send('First quota request');
    await expect(page.getByText('Not enough Agent quota', { exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Retry request', exact: true }).click();
    await expect(page.getByText('Quota request completed: First quota request', { exact: true })).toBeVisible();

    await agentV2.send('Second independent request');
    await expect(page.getByText('Quota request completed: Second independent request', { exact: true })).toBeVisible();

    const { runBodies } = await agentV2.getState();
    expect(runBodies).toHaveLength(3);
    expect(runBodies[1]).toEqual(runBodies[0]);
    expect(runBodies[2].clientRunId).not.toBe(runBodies[0].clientRunId);
    expect(runBodies[2].input.message.text).toBe('Second independent request');
  });

  test('shows a rejected admission as one assistant message and retries its exact request', async ({
    agentV2,
    page,
  }) => {
    await page.setViewportSize({ width: 390, height: 447 });
    await agentV2.reset('admission-retry');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.acceptConsent();

    await agentV2.send('Retry after provider recovery');
    await expect(page.getByText('Couldn’t get a response', { exact: true })).toBeVisible();
    await expect(page.getByText('You can try again, but the response may not load.', { exact: true }))
      .toBeVisible();
    await expect(page.locator('[data-agent-v2-message-role="assistant"]')).toHaveCount(1);
    await expect(page.getByRole('status').filter({ hasText: 'Couldn’t get a response' })).toHaveCount(0);
    await expect(page.getByText('Retry after provider recovery', { exact: true })).toHaveCount(1);

    const layout = await getAgentV2Conversation(page).evaluate((messages) => {
      const input = document.querySelector<HTMLTextAreaElement>('textarea[placeholder="Ask anything"]');
      const failure = messages.querySelector<HTMLElement>('[data-agent-v2-message-role="assistant"]');
      if (!input || !failure) throw new Error('Agent admission failure layout was not found');
      let composerWrapper: HTMLElement | null = input.parentElement;
      while (composerWrapper && getComputedStyle(composerWrapper).position !== 'absolute') {
        composerWrapper = composerWrapper.parentElement;
      }
      if (!composerWrapper) throw new Error('Agent composer wrapper was not found');
      return composerWrapper.getBoundingClientRect().top - failure.getBoundingClientRect().bottom;
    });
    expect(layout).toBeGreaterThanOrEqual(-1);

    await page.getByRole('button', { name: 'Retry request', exact: true }).click();
    await expect(page.getByText(
      'Recovered response: Retry after provider recovery',
      { exact: true },
    )).toBeVisible();

    const { runBodies } = await agentV2.getState();
    expect(runBodies).toHaveLength(4);
    expect(runBodies.slice(1)).toEqual([runBodies[0], runBodies[0], runBodies[0]]);
  });

  test('does not commit an action or trailing events after a terminal stream error', async ({ agentV2, page }) => {
    await agentV2.reset('terminal-action-error');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.acceptConsent();

    await agentV2.send('Trigger terminal error');
    await expect(page.getByText('This response will fail.', { exact: true })).toBeVisible();
    await expect(page.getByText('Response interrupted', { exact: true })).toBeVisible();
    await expect(page.getByText('Agent could not complete the request. Please try again.', { exact: true }))
      .toBeVisible();
    await expect(page.getByRole('button', { name: 'Retry request', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Open receive', exact: true })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Open app', exact: true })).toHaveCount(0);

    await page.getByRole('button', { name: 'Retry request', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Retry request', exact: true })).toBeEnabled();
    await expect(page.getByText('Response interrupted', { exact: true })).toHaveCount(1);
    await expect(page.locator('[data-agent-v2-message-role="assistant"]')).toHaveCount(1);
    await expect(page.getByRole('status').filter({ hasText: 'Couldn’t get a response' })).toHaveCount(0);

    await agentV2.open();
    await expect(page.getByText('This response will fail.', { exact: true })).toBeVisible();
    await expect(page.getByText('Response interrupted', { exact: true })).toBeVisible();
    await expect(page.getByText('Agent could not complete the request. Please try again.', { exact: true }))
      .toBeVisible();
    await expect(page.getByRole('button', { name: 'Retry request', exact: true })).toBeVisible();

    await page.getByRole('button', { name: 'Open Menu', exact: true }).click();
    await page.getByText('Clear Chat', { exact: true }).last().click();
    await page.locator('#agent-clear-chat-confirm:visible').click();
    await expect.poll(async () => (await agentV2.getState()).clearBodies.length).toBe(1);
    const state = await agentV2.getState();
    expect(state.clearBodies[0].expectedThreadRevision).toBe(1);
  });

  test('keeps a failed response and current capacity status distinct across reload', async ({ agentV2, page }) => {
    await page.setViewportSize({ width: 390, height: 447 });
    await agentV2.reset('capacity-error');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.acceptConsent();

    await agentV2.send('Trigger capacity failure');
    await expect(page.getByText('A partial response was started.', { exact: true })).toBeVisible();
    await expect(page.getByText('Response interrupted', { exact: true })).toBeVisible();
    await expect(page.getByText('Agent is temporarily unavailable', { exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Retry request', exact: true })).toBeVisible();
    const input = page.getByRole('textbox', { name: 'Ask anything' });
    const sendButton = page.getByRole('button', { name: 'Send', exact: true });
    const draft = 'Next question';
    const assertDraftCannotSend = async () => {
      await expect(input).toBeEditable();
      await input.fill(draft);
      await expect(sendButton).toBeDisabled();
      await input.press('Enter');
      await expect(input).toHaveValue(draft);
      expect((await agentV2.getState()).runBodies).toHaveLength(1);
    };
    await assertDraftCannotSend();

    const readLayout = () => getAgentV2Conversation(page).evaluate((messages) => {
      const input = document.querySelector<HTMLTextAreaElement>('textarea[placeholder="Ask anything"]');
      const lastMessage = Array.from(
        messages.querySelectorAll<HTMLElement>('[data-agent-v2-message-role="assistant"]'),
      ).at(-1);
      if (!input || !lastMessage) throw new Error('Agent failure layout was not found');
      let composerWrapper: HTMLElement | null = input.parentElement;
      while (composerWrapper && getComputedStyle(composerWrapper).position !== 'absolute') {
        composerWrapper = composerWrapper.parentElement;
      }
      if (!composerWrapper) throw new Error('Agent composer wrapper was not found');
      return {
        gap: composerWrapper.getBoundingClientRect().top - lastMessage.getBoundingClientRect().bottom,
        distanceToBottom: messages.scrollHeight - messages.scrollTop - messages.clientHeight,
      };
    });
    await expect.poll(async () => (await readLayout()).gap).toBeGreaterThanOrEqual(-1);
    await expect.poll(async () => (await readLayout()).distanceToBottom).toBeLessThanOrEqual(1);

    await agentV2.open();
    await expect(page.getByText('A partial response was started.', { exact: true })).toBeVisible();
    await expect(page.getByText('Response interrupted', { exact: true })).toBeVisible();
    await expect(page.getByText('Agent is temporarily unavailable', { exact: true })).toBeVisible();
    await assertDraftCannotSend();
  });

  test('keeps the response active while switching wallets and drafting the next question', async ({
    agentV2,
    page,
  }) => {
    await agentV2.reset('wallet-switch');
    await agentV2.seedWallet(true);
    await agentV2.open();
    await agentV2.acceptConsent();

    const walletOptions = page.getByRole('dialog').getByRole('button', { name: 'Switch Account', exact: true });
    const partialText = 'Partial response before switching wallets.';
    const assistantMessage = page.locator('[data-agent-v2-message-role="assistant"]:visible');
    const input = page.locator('textarea[placeholder="Ask anything"]:visible');
    const sendButton = page.getByRole('button', { name: 'Send', exact: true });
    await agentV2.send('Start a response on the first account');
    await expect(assistantMessage).toContainText(partialText);
    await page.locator('button[aria-label="Switch Account"]:visible').click();
    await walletOptions.nth(1).click();

    await expect(walletOptions).toHaveCount(0);
    await expect(page.locator('button[aria-label="Switch Account"]:visible')
      .filter({ hasText: 'Secondary View Wallet' })).toBeVisible();
    await expect(assistantMessage).toContainText(partialText);
    await expect(input).toBeEditable();

    await page.locator('button[aria-label="Switch Account"]:visible').click();
    await expect(walletOptions.first()).toBeVisible();
    await expect(walletOptions.first()).toBeEnabled();
    await walletOptions.first().click();
    await expect(walletOptions).toHaveCount(0);
    await expect(page.locator('button[aria-label="Switch Account"]:visible')
      .filter({ hasText: 'Synthetic View Wallet' })).toBeVisible();
    const draft = 'Next question after switching back';
    await input.fill(draft);
    await expect(sendButton).toBeDisabled();
    await input.press('Enter');
    await expect(input).toHaveValue(draft);
    const activeState = await agentV2.getState();
    expect(activeState.runBodies).toHaveLength(1);
    expect(activeState.cancelBodies).toHaveLength(0);

    await agentV2.completeRun();
    await expect(assistantMessage).toContainText(`${partialText} The response continued after switching wallets.`);
    await expect(assistantMessage).toHaveAttribute('data-agent-v2-message-status', 'complete');
    await expect(input).toHaveValue(draft);
    await expect(sendButton).toBeEnabled();

    await sendButton.click();
    await expect.poll(async () => (await agentV2.getState()).runBodies.length).toBe(2);
    await expect(input).toHaveValue('');
    const state = await agentV2.getState();
    expect(state.runBodies[1].input.message.text).toBe(draft);
    expect(state.cancelBodies).toHaveLength(0);
    await expect(assistantMessage).toHaveCount(2);
    await agentV2.completeRun();
    await expect(assistantMessage.last()).toHaveAttribute('data-agent-v2-message-status', 'complete');
  });

  test('dispatches a receive action and opens a screen from an answer link', async ({ agentV2, page }) => {
    await agentV2.reset('receive-navigation');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.acceptConsent();

    await agentV2.send('Show wallet actions');
    await page.getByRole('button', { name: 'Open receive', exact: true }).click();
    await expect(page.getByRole('dialog').getByText(/^(Fund|Add)$/u)).toBeVisible();
    await page.getByRole('dialog').getByRole('button', { name: 'Close', exact: true }).click();

    // The seeded wallet is view-only, which opens settings as the settings button did
    await expect(page.getByText('Theme', { exact: true })).toHaveCount(0);
    await page.getByRole('link', { name: 'Appearance', exact: true }).click();
    await expect(page.getByText('Theme', { exact: true })).toBeVisible();
  });
});

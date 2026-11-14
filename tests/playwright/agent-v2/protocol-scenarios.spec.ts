import type { Locator, Page } from '@playwright/test';

import { expect, getAgentV2Conversation, test } from './fixtures';

// The draft's send button and Stop trade places in 200 ms, after the frame that renders the change
const STOP_SETTLE_MS = 600;
// The recording goes on this long after the next answer comes, past the rows' move as the next question goes
const GLIDE_RECORDING_SETTLE_MS = 1200;
// The rows move on Telegram's list curve over 800 ms, as on iOS. The curve starts at its steepest, 1 / 0.23 times as
// fast as an even pace, so a row covers at most that share of its way in a millisecond.
const GLIDE_MAX_SHARE_PER_MS = 1 / (0.23 * 800);
// A sample may read the list as the frame before drew it, so a step between samples may span one frame more
const FRAME_MS = 17;
const GLIDE_TOLERANCE_PX = 4;
// The question that still waits moves down by the height of the activity that comes in over it
const GLIDE_MIN_TRAVEL_PX = 24;
// A nudge up that takes the list farther from its end than the scroll button's 60 px, with the last row still in sight
const NUDGE_SCROLL_UP_PX = 100;
// A scroll up into the history, as far as it goes
const HISTORY_SCROLL_UP_PX = 5000;
// The last row ends this far below the visible bottom of the list once the scroll button shows, as on mobile
const SCROLL_BUTTON_OVERHANG_PX = 60;
const BUBBLE_SELECTOR = '[class*="__bubble__"]';
const MESSAGE_MENU_SELECTOR = '.menu-bubble[class*="MessageBubble"][class*="__menu__"]';

test.describe('Agent V2 deterministic protocol scenarios', () => {
  test('shows one active server progress line until the answer starts', async ({ agentV2, page }) => {
    await page.setViewportSize({ width: 1160, height: 447 });
    await agentV2.reset('run-activity');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.waitForList();

    await agentV2.send('Research the latest TON update');
    // A step comes every 650 ms and blurs away as the next one comes in, so each step is awaited as it comes in
    // rather than polled for
    const activityStep = page.getByRole('status').locator('[data-agent-activity-step]');
    for (const step of ['Searching the web…', 'Reviewing sources…', 'Checking market data…']) {
      await activityStep.filter({ hasText: step }).waitFor();
    }
    await expect(page.getByRole('status')).toHaveCount(1);
    const activityLayout = await page.getByRole('status').evaluate((status) => {
      // The chat's own field; the chat list under it has another
      const composer = status.closest('.custom-scroll')!.parentElement!.querySelector('textarea')!;
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
    await expect(getAgentV2Conversation(page).getByText('Research the latest TON update', { exact: true }))
      .toBeVisible();
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
    await agentV2.waitForList();

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
      const composerInput = element.parentElement!.querySelector<HTMLTextAreaElement>(
        'textarea[placeholder="Ask anything"]',
      );
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

    await input.fill('');
    await expect(input).toHaveValue('');
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
    await agentV2.waitForList();

    await agentV2.send('First quota request');
    // The quota the denial carries has reset already, so the question offers Retry as a failed request does
    await expect(getAgentV2Conversation(page).getByText(/^Daily agent limit reached\. Resets at .+\.$/)).toBeVisible();
    await expect(page.getByRole('status').filter({ hasText: 'Daily agent limit reached' })).toHaveCount(0);
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
    await agentV2.waitForList();

    await agentV2.send('Retry after provider recovery');
    await expect(page.getByText('You can try again, but the response may not load.', { exact: true }))
      .toBeVisible();
    await expect(page.locator('[data-agent-v2-message-role="assistant"]')).toHaveCount(1);
    await expect(page.getByRole('status').filter({ hasText: 'You can try again, but the response may not load.' }))
      .toHaveCount(0);
    await expect(getAgentV2Conversation(page).getByText('Retry after provider recovery', { exact: true }))
      .toHaveCount(1);

    const layout = await getAgentV2Conversation(page).evaluate((messages) => {
      const input = messages.parentElement!.querySelector<HTMLTextAreaElement>('textarea[placeholder="Ask anything"]');
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
    await agentV2.waitForList();

    await agentV2.send('Trigger terminal error');
    await expect(page.getByText('This response will fail.', { exact: true })).toBeVisible();
    await expect(page.getByText('Agent could not complete the request. Please try again.', { exact: true }))
      .toBeVisible();
    await expect(page.getByRole('button', { name: 'Retry request', exact: true })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Open receive', exact: true })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Open app', exact: true })).toHaveCount(0);

    await page.getByRole('button', { name: 'Retry request', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Retry request', exact: true })).toBeEnabled();
    await expect(page.getByText('Agent could not complete the request. Please try again.', { exact: true }))
      .toHaveCount(1);
    await expect(page.locator('[data-agent-v2-message-role="assistant"]')).toHaveCount(1);
    await expect(page.getByRole('status').filter({ hasText: 'Agent could not complete the request.' }))
      .toHaveCount(0);

    await agentV2.open();
    await agentV2.openThread();
    await expect(page.getByText('This response will fail.', { exact: true })).toBeVisible();
    await expect(page.getByText('Agent could not complete the request. Please try again.', { exact: true }))
      .toHaveCount(1);
    await expect(page.getByRole('button', { name: 'Retry request', exact: true })).toBeVisible();

    await page.getByRole('button', { name: 'Open Menu', exact: true }).click();
    await page.getByText('Delete Chat', { exact: true }).last().click();
    await page.getByRole('dialog').getByRole('button', { name: 'Delete', exact: true }).click();
    await expect.poll(async () => (await agentV2.getState()).deleteBodies.length).toBe(1);
    await expect(page.getByRole('button', { name: 'Back', exact: true })).toHaveCount(0);
  });

  test('keeps a failed response and current capacity status distinct across reload', async ({ agentV2, page }) => {
    await page.setViewportSize({ width: 390, height: 447 });
    await agentV2.reset('capacity-error');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.waitForList();

    await agentV2.send('Trigger capacity failure');
    await expect(page.getByText('A partial response was started.', { exact: true })).toBeVisible();
    // The capacity status ends the chat in place of the answer's own caption, without Retry while the limit holds
    await expect(page.getByText(
      'The request cannot be completed because an agent limit was reached.', { exact: true },
    )).toHaveCount(0);
    await expect(getAgentV2Conversation(page).getByText('Agent is temporarily unavailable', { exact: true }))
      .toBeVisible();
    await expect(page.getByRole('button', { name: 'Retry request', exact: true })).toHaveCount(0);
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
      const input = messages.parentElement!.querySelector<HTMLTextAreaElement>('textarea[placeholder="Ask anything"]');
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
    await agentV2.openThread();
    await expect(page.getByText('A partial response was started.', { exact: true })).toBeVisible();
    // The capacity status ends the chat in place of the answer's own caption, without Retry while the limit holds
    await expect(page.getByText(
      'The request cannot be completed because an agent limit was reached.', { exact: true },
    )).toHaveCount(0);
    await expect(getAgentV2Conversation(page).getByText('Agent is temporarily unavailable', { exact: true }))
      .toBeVisible();
    await expect(page.getByRole('button', { name: 'Retry request', exact: true })).toHaveCount(0);
    await assertDraftCannotSend();
  });

  test('tells an interrupted request once, live and after the chat opens again', async ({ agentV2, page }) => {
    await agentV2.reset('run-interrupted');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.waitForList();

    await agentV2.send('Interrupt this request');
    const failure = page.getByText('Connection to the agent was interrupted.', { exact: true });
    const retry = page.getByRole('button', { name: 'Retry request', exact: true });
    // The history read after the interruption holds the failed run, which offers Retry; the connection's own
    // failure does not show beside it
    await expect(retry).toBeVisible();
    await expect(failure).toHaveCount(1);
    await expect(page.locator('[data-agent-v2-message-status="error"]')).toHaveCount(1);

    await agentV2.open();
    await agentV2.openThread();
    await expect(retry).toBeVisible();
    await expect(failure).toHaveCount(1);
    await expect(page.locator('[data-agent-v2-message-status="error"]')).toHaveCount(1);
  });

  test('stops an answer being written, keeping what it wrote, and the chat goes on', async ({ agentV2, page }) => {
    await agentV2.reset('stop');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.waitForList();

    const partialText = 'The answer written before the stop.';
    const assistantMessage = page.locator('[data-agent-v2-message-role="assistant"]:visible');
    const input = page.locator('textarea[placeholder="Ask anything"]:visible');
    const stop = page.getByRole('button', { name: 'Stop response', exact: true });
    await agentV2.send('Start an answer to stop');
    await expect(assistantMessage).toContainText(partialText);
    await expect(assistantMessage).toHaveAttribute('data-agent-v2-message-status', 'streaming');

    // A draft trades Stop for its send button and back, and the microphone never shows on the way
    const microphoneRecording = recordStopMicrophone(page);
    await input.fill('A draft');
    await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeVisible();
    await expect(stop).toHaveCount(0);
    await input.fill('');
    await expect(stop).toBeVisible();
    expect(await microphoneRecording).toEqual({ hasMicrophone: true, isDraftCleared: true, maxOpacity: 0 });
    await stop.click();

    await expect.poll(async () => (await agentV2.getState()).cancelBodies.length).toBe(1);
    const { runBodies, cancelBodies } = await agentV2.getState();
    expect(runBodies).toHaveLength(1);
    expect(cancelBodies[0].runId).toMatch(/^[0-9a-f-]{36}$/u);
    // The button turns back, and the answer ends as it was written
    await expect(stop).toHaveCount(0);
    await expect(assistantMessage).toHaveAttribute('data-agent-v2-message-status', 'complete');
    await expect(assistantMessage).toContainText(partialText);
    await expect(assistantMessage).not.toContainText('This part is never written.');

    await input.fill('The next question');
    await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();

    // The server keeps the same answer
    await agentV2.open();
    await agentV2.openThread();
    await expect(assistantMessage).toContainText(partialText);
    await expect(assistantMessage).toHaveAttribute('data-agent-v2-message-status', 'complete');
  });

  test('sends a queued question as soon as Stop ends the answer, with Stop staying in place', async ({
    agentV2,
    page,
  }) => {
    await agentV2.reset('stop');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.waitForList();

    const partialText = 'The answer written before the stop.';
    const assistantMessage = page.locator('[data-agent-v2-message-role="assistant"]:visible');
    const userMessage = page.locator('[data-agent-v2-message-role="user"]:visible');
    const input = page.locator('textarea[placeholder="Ask anything"]:visible');
    const stop = page.getByRole('button', { name: 'Stop response', exact: true });
    await agentV2.send('Start an answer to stop');
    await expect(assistantMessage).toContainText(partialText);
    await expect(assistantMessage).toHaveAttribute('data-agent-v2-message-status', 'streaming');

    // The question waits behind the answer, last in the chat. Enter sends the draft once the field has drawn it.
    const queued = 'The question queued behind it';
    await input.fill(queued);
    await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
    await input.press('Enter');
    await expect(input).toHaveValue('');
    await expect(userMessage.last()).toContainText(queued);
    await expect(stop).toBeVisible();
    expect((await agentV2.getState()).runBodies).toHaveLength(1);

    // Stop stays under the finger while the queued question goes, as on Android
    const finishStopRecording = await startStopRecording(page);
    await stop.click();
    expect(await finishStopRecording()).toEqual({ isNextAnswerStreaming: true, isStopKept: true });
    const { runBodies, cancelBodies } = await agentV2.getState();
    expect(runBodies).toHaveLength(2);
    expect(runBodies[1].input.message.text).toBe(queued);
    expect(cancelBodies).toHaveLength(1);
    await expect(assistantMessage).toHaveCount(2);
    await expect(assistantMessage.first()).toHaveAttribute('data-agent-v2-message-status', 'complete');
    await expect(assistantMessage.last()).toHaveAttribute('data-agent-v2-message-status', 'streaming');

    // The answer to the queued question stops in turn, and with nothing queued the button turns back
    await stop.click();
    await expect.poll(async () => (await agentV2.getState()).cancelBodies.length).toBe(2);
    await expect(stop).toHaveCount(0);
    await expect(assistantMessage.last()).toHaveAttribute('data-agent-v2-message-status', 'complete');
  });

  for (const trigger of ['Stop', 'the answer finishing'] as const) {
    test(`glides the question that still waits as the next one goes after ${trigger}, under its activity`, async ({
      agentV2,
      page,
    }) => {
      await agentV2.reset('stop');
      await agentV2.seedWallet();
      await agentV2.open();
      await agentV2.waitForList();

      const assistantMessage = page.locator('[data-agent-v2-message-role="assistant"]:visible');
      const userMessage = page.locator('[data-agent-v2-message-role="user"]:visible');
      const input = page.locator('textarea[placeholder="Ask anything"]:visible');
      const send = page.getByRole('button', { name: 'Send', exact: true });
      const stop = page.getByRole('button', { name: 'Stop response', exact: true });
      await agentV2.send('Open the chat');
      await expect(assistantMessage).toContainText('The answer written before the stop.');
      await agentV2.completeRun();
      await expect(assistantMessage).toHaveAttribute('data-agent-v2-message-status', 'complete');

      // A question sent from the chat is pinned under the header with its answer under it. Enter sends each draft once
      // the field has drawn it.
      await input.fill('Start an answer to stop');
      await expect(send).toBeEnabled();
      await input.press('Enter');
      await expect(assistantMessage).toHaveCount(2);
      await expect(assistantMessage.last()).toContainText('The answer written before the stop.');

      // Two questions wait under the answer, in sight, as on mobile
      const going = 'The question queued behind it';
      const waiting = 'The question queued after it';
      for (const queued of [going, waiting]) {
        await input.fill(queued);
        await expect(send).toBeEnabled();
        await input.press('Enter');
        await expect(userMessage.last()).toContainText(queued);
      }
      await expect(userMessage.last()).toBeInViewport();
      await expect(stop).toBeVisible();

      const finishGlideRecording = await startQueuedQuestionRecording(page, waiting);
      if (trigger === 'Stop') {
        await stop.click();
      } else {
        await agentV2.completeRun();
      }
      const { samples, activityIndex, isActivityBelowWaiting } = await finishGlideRecording();

      // The next question's activity comes in under it, over the question that still waits, which moves down out of
      // its way. Its place in the list's content, which the list's own scroll leaves alone, moves only as fast as the
      // move's curve allows from there.
      expect(activityIndex).toBeGreaterThan(0);
      expect(isActivityBelowWaiting).toBe(false);
      const moveSamples = samples.slice(activityIndex - 1);
      const travel = Math.abs(moveSamples[moveSamples.length - 1].top - moveSamples[0].top);
      expect(travel).toBeGreaterThan(GLIDE_MIN_TRAVEL_PX);
      moveSamples.slice(1).forEach(({ time, top }, index) => {
        const previous = moveSamples[index];
        const maxStep = travel * GLIDE_MAX_SHARE_PER_MS * (time - previous.time + FRAME_MS) + GLIDE_TOLERANCE_PX;
        expect(Math.abs(top - previous.top), `The step ${Math.round(time - moveSamples[0].time)} ms in`)
          .toBeLessThanOrEqual(maxStep);
      });

      // Its answer comes under it, over the question that still waits
      await expect(assistantMessage).toHaveCount(3);
      await expect.poll(() => page.locator('[data-agent-v2-message-role]:visible').evaluateAll((messages) => (
        messages.map((message) => message.getAttribute('data-agent-v2-message-role'))
      ))).toEqual(['user', 'assistant', 'user', 'assistant', 'user', 'assistant', 'user']);
      await expect(userMessage.last()).toContainText(waiting);
    });
  }

  test('pins the next queued question after a nudge up, and leaves a chat scrolled into its history in place', async ({
    agentV2,
    page,
  }) => {
    test.setTimeout(90_000);
    await agentV2.reset('stop');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.waitForList();

    const assistantMessage = page.locator('[data-agent-v2-message-role="assistant"]:visible');
    const userMessage = page.locator('[data-agent-v2-message-role="user"]:visible');
    const input = page.locator('textarea[placeholder="Ask anything"]:visible');
    const send = page.getByRole('button', { name: 'Send', exact: true });
    const scrollToBottom = page.locator('[data-agent-conversation]').last()
      .getByRole('button', { name: 'Scroll To Bottom', exact: true });
    const ask = async (text: string) => {
      await input.fill(text);
      await expect(send).toBeEnabled();
      await input.press('Enter');
    };
    // The chat has more than a screen of answered questions above the one being answered
    await agentV2.send('Open the chat');
    await expect(assistantMessage).toContainText('The answer written before the stop.');
    await agentV2.completeRun();
    await expect(assistantMessage).toHaveAttribute('data-agent-v2-message-status', 'complete');
    const historyQuestions = [
      'Ask a second question', 'Ask a third question', 'Ask a fourth question', 'Ask a fifth question',
    ];
    for (const [index, question] of historyQuestions.entries()) {
      await ask(question);
      await expect(assistantMessage).toHaveCount(index + 2);
      await expect(assistantMessage.last()).toContainText('The answer written before the stop.');
      await agentV2.completeRun();
      await expect(assistantMessage.last()).toHaveAttribute('data-agent-v2-message-status', 'complete');
    }

    // A question is pinned under the header while its answer is written, and three questions wait under it
    await ask('Start an answer to stop');
    await expect(assistantMessage).toHaveCount(historyQuestions.length + 2);
    await expect(assistantMessage.last()).toContainText('The answer written before the stop.');
    const [firstGoing, secondGoing] = ['The first question queued', 'The second question queued'];
    for (const queued of [firstGoing, secondGoing, 'The third question queued']) {
      await ask(queued);
      await expect(userMessage.last()).toContainText(queued);
    }
    const list = getAgentV2Conversation(page);
    await waitForListRest(list);
    await expect(scrollToBottom).toHaveCount(0);

    // A nudge up with the wheel takes the list away from its end, while the last question that waits stays in sight and
    // no scroll button shows
    const box = (await list.boundingBox())!;
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.wheel(0, -NUDGE_SCROLL_UP_PX);
    await waitForListRest(list);
    const nudged = await measureListEnd(list);
    expect(nudged.distanceToEnd).toBeGreaterThan(SCROLL_BUTTON_OVERHANG_PX);
    expect(nudged.lastRowOverhang).toBeLessThanOrEqual(0);
    await expect(scrollToBottom).toHaveCount(0);

    // The answer ends, and the question that goes is brought up as a fresh send is
    await agentV2.completeRun();
    await expect(assistantMessage).toHaveCount(historyQuestions.length + 3);
    await expect.poll(async () => (await measureListEnd(list)).distanceToEnd).toBeLessThanOrEqual(1);
    await expect(userMessage.filter({ hasText: firstGoing })).toBeInViewport();
    await waitForListRest(list);

    // The user scrolls up into the history, which takes the last row out of sight, and the scroll button shows
    await page.mouse.wheel(0, -HISTORY_SCROLL_UP_PX);
    await waitForListRest(list);
    expect((await measureListEnd(list)).lastRowOverhang).toBeGreaterThan(SCROLL_BUTTON_OVERHANG_PX);
    await expect(scrollToBottom).toBeVisible();

    // The answer ends and the next question goes, its answer coming under it, while the list stays where the user took
    // it, the rows on screen hold still and the scroll button stays
    const finishScrollRecording = await startListScrollRecording(list, secondGoing);
    await agentV2.completeRun();
    const { scrollTops, maxRowShift, hasNextAnswer } = await finishScrollRecording();
    expect(hasNextAnswer).toBe(true);
    expect(scrollTops.filter((scrollTop) => Math.abs(scrollTop - scrollTops[0]) > 1)).toEqual([]);
    expect(maxRowShift).toBeLessThanOrEqual(1);
    await expect(assistantMessage.last()).toHaveAttribute('data-agent-v2-message-status', 'streaming');
    await expect(scrollToBottom).toBeVisible();

    // The scroll button takes the user down to the end, where the question that went is in sight
    await scrollToBottom.click();
    await expect.poll(async () => (await measureListEnd(list)).distanceToEnd).toBeLessThanOrEqual(1);
    await expect(userMessage.filter({ hasText: secondGoing })).toBeInViewport();
  });

  test('offers Edit on a stored question once no answer runs and no question waits, and never on a queued one', async ({
    agentV2,
    page,
  }) => {
    await agentV2.reset('stop');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.waitForList();

    const assistantMessage = page.locator('[data-agent-v2-message-role="assistant"]:visible');
    const userMessage = page.locator('[data-agent-v2-message-role="user"]:visible');
    const input = page.locator('textarea[placeholder="Ask anything"]:visible');
    const stop = page.getByRole('button', { name: 'Stop response', exact: true });
    const menu = page.locator(MESSAGE_MENU_SELECTOR);
    const edit = menu.getByText('Edit', { exact: true });
    const openMenu = async (message: Locator) => {
      await message.locator(BUBBLE_SELECTOR).click({ button: 'right' });
      await expect(menu.getByText('Copy', { exact: true })).toBeVisible();
    };
    const closeMenu = async () => {
      await page.keyboard.press('Escape');
      await expect(menu).toHaveCount(0);
    };
    await agentV2.send('Start an answer to stop');
    await expect(assistantMessage).toContainText('The answer written before the stop.');

    // The question waits for its answer, as on mobile
    await openMenu(userMessage.first());
    await expect(edit).toHaveCount(0);
    await closeMenu();

    // A queued question has no stored message to edit. Enter sends the draft once the field has drawn it.
    const queued = 'The question queued behind it';
    await input.fill(queued);
    await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
    await input.press('Enter');
    await expect(userMessage.last()).toContainText(queued);
    await openMenu(userMessage.last());
    await expect(edit).toHaveCount(0);
    await closeMenu();

    // Stop sends the queued question, and a second Stop ends its answer, which leaves the chat free once the stopped
    // answers have been read again
    await stop.click();
    await expect(assistantMessage).toHaveCount(2);
    await expect(assistantMessage.last()).toHaveAttribute('data-agent-v2-message-status', 'streaming');
    await stop.click();
    await expect(stop).toHaveCount(0);
    await expect.poll(async () => {
      await openMenu(userMessage.first());
      const editCount = await edit.count();
      await closeMenu();
      return editCount;
    }).toBe(1);
  });

  test('keeps the response active while switching wallets and drafting the next question', async ({
    agentV2,
    page,
  }) => {
    await agentV2.reset('wallet-switch');
    await agentV2.seedWallet(true);
    await agentV2.open();
    await agentV2.waitForList();

    // A wallet list row is named by its avatar initials and the wallet name; the card's button shows the current wallet
    const firstWalletRow = page.getByRole('button', { name: 'SV Synthetic View Wallet' });
    const secondWalletRow = page.getByRole('button', { name: 'SV Secondary View Wallet' });
    const firstWalletCard = page.getByRole('button', { name: 'Synthetic View Wallet', exact: true });
    const secondWalletCard = page.getByRole('button', { name: 'Secondary View Wallet', exact: true });
    const partialText = 'Partial response before switching wallets.';
    // Outgoing crossfade snapshots are visible but inert; assert against the live conversation.
    const assistantMessage = page.locator('[data-agent-v2-message-role="assistant"]:visible:not([inert] *)');
    const input = page.locator('textarea[placeholder="Ask anything"]:visible:not([inert] *)');
    const sendButton = page.getByRole('button', { name: 'Send', exact: true });
    const stopButton = page.getByRole('button', { name: 'Stop response', exact: true });
    await agentV2.send('Start a response on the first account');
    await expect(assistantMessage).toContainText(partialText);
    await secondWalletRow.click();
    await expect(secondWalletCard).toBeVisible();
    await expect(assistantMessage).toContainText(partialText);
    await expect(input).toBeEditable();

    await firstWalletRow.click();
    await expect(firstWalletCard).toBeVisible();
    // Stop stands in the empty field's microphone place while the response is active, and a draft has Send
    await expect(stopButton).toBeVisible();
    const draft = 'Next question after switching back';
    await input.fill(draft);
    await expect(stopButton).toHaveCount(0);
    await expect(sendButton).toBeEnabled();
    // The question waits behind the answer, shown at once
    await input.press('Enter');
    await expect(input).toHaveValue('');
    await expect(page.locator('[data-agent-v2-message-role="user"]:visible').last()).toContainText(draft);
    const activeState = await agentV2.getState();
    expect(activeState.runBodies).toHaveLength(1);
    expect(activeState.cancelBodies).toHaveLength(0);

    await agentV2.completeRun();
    await expect(assistantMessage.first()).toContainText(
      `${partialText} The response continued after switching wallets.`,
    );
    await expect(assistantMessage.first()).toHaveAttribute('data-agent-v2-message-status', 'complete');
    // Once the answer has ended, the queued question goes, once
    await expect.poll(async () => (await agentV2.getState()).runBodies.length).toBe(2);
    const state = await agentV2.getState();
    expect(state.runBodies[1].input.message.text).toBe(draft);
    expect(state.cancelBodies).toHaveLength(0);
    await expect(assistantMessage).toHaveCount(2);
    await agentV2.completeRun();
    await expect(assistantMessage.last()).toHaveAttribute('data-agent-v2-message-status', 'complete');
  });

  test('fails a question queued for the wallet switched from, whose Retry asks it again behind the answer', async ({
    agentV2,
    page,
  }) => {
    await agentV2.reset('wallet-switch');
    await agentV2.seedWallet(true);
    await agentV2.open();
    await agentV2.waitForList();

    // A wallet list row is named by its avatar initials and the wallet name; the card's button shows the current wallet
    const secondWalletRow = page.getByRole('button', { name: 'SV Secondary View Wallet' });
    const secondWalletCard = page.getByRole('button', { name: 'Secondary View Wallet', exact: true });
    const assistantMessage = page.locator('[data-agent-v2-message-role="assistant"]:visible');
    const userMessage = page.locator('[data-agent-v2-message-role="user"]:visible');
    const input = page.locator('textarea[placeholder="Ask anything"]:visible');
    const retry = page.getByRole('button', { name: 'Retry request', exact: true });
    await agentV2.send('Start a response on the first account');
    await expect(assistantMessage).toContainText('Partial response before switching wallets.');

    const queued = 'A question for the first account';
    await input.fill(queued);
    // Enter sends the draft once the field has drawn it
    await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
    await input.press('Enter');
    await expect(input).toHaveValue('');
    await expect(userMessage.last()).toContainText(queued);

    await secondWalletRow.click();
    await expect(secondWalletCard).toBeVisible();
    // The question stays last with its failure, whose Retry works while the answer runs, as on Android
    await expect(retry).toBeEnabled();
    await expect(userMessage.last()).toContainText(queued);
    expect((await agentV2.getState()).runBodies).toHaveLength(1);

    // Retry queues it again behind the answer, which it follows once the answer has ended
    await retry.click();
    await expect(retry).toHaveCount(0);
    expect((await agentV2.getState()).runBodies).toHaveLength(1);
    await agentV2.completeRun();
    await expect.poll(async () => (await agentV2.getState()).runBodies.length).toBe(2);
    expect((await agentV2.getState()).runBodies[1].input.message.text).toBe(queued);
    await agentV2.completeRun();
    await expect(assistantMessage.last()).toHaveAttribute('data-agent-v2-message-status', 'complete');
  });

  test('dispatches a receive action and opens a screen from an answer link', async ({ agentV2, page }) => {
    await agentV2.reset('receive-navigation');
    await agentV2.seedWallet();
    await agentV2.open();
    await agentV2.waitForList();

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

// The highest opacity the microphone in Stop's button takes in any frame while a draft is written and cleared
function recordStopMicrophone(page: Page) {
  return page.evaluate(async ({ settleMs, timeoutMs }) => {
    const stop = Array.from(document.querySelectorAll('button[aria-label="Stop response"]'))
      .find((button) => button.getAttribute('aria-hidden') !== 'true')!;
    const microphone = stop.querySelector('svg');
    const field = stop.closest('[data-agent-composer]')!.querySelector('textarea')!;
    const startedAt = performance.now();
    let hasDraft = false;
    let clearedAt: number | undefined;
    let maxOpacity = 0;
    while (microphone && performance.now() - startedAt < timeoutMs
      && (clearedAt === undefined || performance.now() - clearedAt < settleMs)) {
      maxOpacity = Math.max(maxOpacity, Number(getComputedStyle(microphone).opacity));
      if (field.value) {
        hasDraft = true;
      } else if (hasDraft) {
        clearedAt ??= performance.now();
      }
      await new Promise(requestAnimationFrame);
    }

    return { hasMicrophone: Boolean(microphone), isDraftCleared: clearedAt !== undefined, maxOpacity };
  }, { settleMs: STOP_SETTLE_MS, timeoutMs: 10_000 });
}

// Watches the button Stop stands in, from before the tap until an answer after the ones shown streams, and a while
// longer, and tells whether the button ever showed anything but Stop on the way. The watch is running once this
// resolves, so a tap after it can't be missed, and the next answer counts however soon it comes, even in the frame the
// stopped one ends.
async function startStopRecording(page: Page) {
  await page.evaluate(({ settleMs, timeoutMs }) => {
    const stop = Array.from(document.querySelectorAll('button[aria-label="Stop response"]'))
      .find((button) => button.getAttribute('aria-hidden') !== 'true')!;
    const getAnswers = () => Array.from(document.querySelectorAll('[data-agent-v2-message-role="assistant"]'))
      .filter((answer) => answer.getClientRects().length > 0);
    const shownAnswerCount = getAnswers().length;
    const recording = (async () => {
      const startedAt = performance.now();
      let nextAnswerAt: number | undefined;
      let isStopKept = true;
      while (performance.now() - startedAt < timeoutMs
        && (nextAnswerAt === undefined || performance.now() - nextAnswerAt < settleMs)) {
        if (stop.getAttribute('aria-label') !== 'Stop response' || stop.getAttribute('aria-hidden') === 'true') {
          isStopKept = false;
        }
        const answers = getAnswers();
        if (answers.length > shownAnswerCount
          && answers[answers.length - 1].getAttribute('data-agent-v2-message-status') === 'streaming') {
          nextAnswerAt ??= performance.now();
        }
        await new Promise(requestAnimationFrame);
      }

      return { isNextAnswerStreaming: nextAnswerAt !== undefined, isStopKept };
    })();
    (window as unknown as { agentStopRecording: typeof recording }).agentStopRecording = recording;
  }, { settleMs: STOP_SETTLE_MS, timeoutMs: 10_000 });

  return () => page.evaluate(() => (
    window as unknown as { agentStopRecording: Promise<{ isNextAnswerStreaming: boolean; isStopKept: boolean }> }
  ).agentStopRecording);
}

interface QuestionSample {
  time: number;
  top: number;
}

interface QueuedQuestionRecording {
  samples: QuestionSample[];
  /** The first sample in which a run's activity was on screen */
  activityIndex: number;
  /** An activity stood after the question that waits */
  isActivityBelowWaiting: boolean;
}

/**
 * Samples, each frame from now until the next answer has run a while, where the question `text`, which waits, stands
 * in the list's content, which the list's own scroll leaves alone, and where the run's activity stands against it
 */
async function startQueuedQuestionRecording(page: Page, text: string) {
  await page.evaluate(({ questionText, settleMs, timeoutMs }) => {
    const question = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-v2-message-role="user"]'))
      .find((element) => element.getClientRects().length > 0 && element.textContent?.includes(questionText))!;
    const list = question.closest<HTMLElement>('.custom-scroll')!;
    const getAnswerCount = () => Array.from(document.querySelectorAll('[data-agent-v2-message-role="assistant"]'))
      .filter((answer) => answer.getClientRects().length > 0)
      .length;
    const shownAnswerCount = getAnswerCount();
    const recording = (async () => {
      const result: QueuedQuestionRecording = { samples: [], activityIndex: -1, isActivityBelowWaiting: false };
      const startedAt = performance.now();
      let nextAnswerAt: number | undefined;
      while (performance.now() - startedAt < timeoutMs
        && (nextAnswerAt === undefined || performance.now() - nextAnswerAt < settleMs)) {
        const time = performance.now();
        result.samples.push({
          time,
          top: question.getBoundingClientRect().top - list.getBoundingClientRect().top + list.scrollTop,
        });
        // The question that waits and the activities, in the order of the document
        const rows = Array.from(list.querySelectorAll(
          '[data-agent-v2-message-role="user"], [data-agent-run-activity]',
        ));
        const questionIndex = rows.indexOf(question);
        rows.forEach((row, index) => {
          if (!row.hasAttribute('data-agent-run-activity')) return;
          if (result.activityIndex === -1) result.activityIndex = result.samples.length - 1;
          if (index > questionIndex) result.isActivityBelowWaiting = true;
        });
        if (getAnswerCount() > shownAnswerCount) nextAnswerAt ??= time;
        await new Promise(requestAnimationFrame);
      }

      return result;
    })();
    (window as unknown as { agentGlideRecording: typeof recording }).agentGlideRecording = recording;
  }, { questionText: text, settleMs: GLIDE_RECORDING_SETTLE_MS, timeoutMs: 10_000 });

  return () => page.evaluate(() => (
    window as unknown as { agentGlideRecording: Promise<QueuedQuestionRecording> }
  ).agentGlideRecording);
}

// How far the list is from its end, and how far its last row ends below the visible bottom of the list
function measureListEnd(list: Locator) {
  return list.evaluate((element) => {
    const rows = element.querySelectorAll(
      '[data-agent-v2-message-id], [data-agent-run-activity], [data-agent-list-footer]',
    );
    const paddingBottom = Number.parseFloat(getComputedStyle(element).paddingBottom) || 0;
    return {
      distanceToEnd: element.scrollHeight - element.scrollTop - element.clientHeight,
      lastRowOverhang: rows[rows.length - 1].getBoundingClientRect().bottom
        - (element.getBoundingClientRect().bottom - paddingBottom),
    };
  });
}

// The list holds still for some frames, its scroll position kept
async function waitForListRest(list: Locator) {
  await expect.poll(() => list.evaluate(async (element) => {
    const shownScrollTop = element.scrollTop;
    for (let frame = 0; frame < 10; frame++) {
      await new Promise(requestAnimationFrame);
      if (element.scrollTop !== shownScrollTop) return false;
    }
    return true;
  }), { timeout: 5000 }).toBe(true);
}

interface ListScrollRecording {
  scrollTops: number[];
  /** The farthest a row on screen above the question that goes moved on screen */
  maxRowShift: number;
  /** The text of the next answer came while the list was recorded */
  hasNextAnswer: boolean;
}

/**
 * Samples, each frame from now until the next answer's text has been in the list a while, the list's scroll position
 * and where the rows on screen above the question `goingText` stand on screen
 */
async function startListScrollRecording(list: Locator, goingText: string) {
  await list.evaluate((element, { answerText, questionText, settleMs, timeoutMs }) => {
    const getAnswerCount = () => Array.from(element.querySelectorAll('[data-agent-v2-message-role="assistant"]'))
      .filter((answer) => answer.textContent?.includes(answerText))
      .length;
    const shownAnswerCount = getAnswerCount();
    const going = Array.from(element.querySelectorAll('[data-agent-v2-message-role="user"]'))
      .find((question) => question.textContent?.includes(questionText))!;
    const listRect = element.getBoundingClientRect();
    const rows = Array.from(element.querySelectorAll('[data-agent-v2-message-id]'));
    const rowsAbove = rows.slice(0, rows.indexOf(going))
      .filter((row) => {
        const { top, bottom } = row.getBoundingClientRect();
        return bottom > listRect.top && top < listRect.bottom;
      })
      .map((row) => ({
        id: row.getAttribute('data-agent-v2-message-id')!,
        top: row.getBoundingClientRect().top - listRect.top,
      }));
    const recording = (async () => {
      const scrollTops: number[] = [];
      let maxRowShift = 0;
      const startedAt = performance.now();
      let nextAnswerAt: number | undefined;
      while (performance.now() - startedAt < timeoutMs
        && (nextAnswerAt === undefined || performance.now() - nextAnswerAt < settleMs)) {
        scrollTops.push(element.scrollTop);
        const listTop = element.getBoundingClientRect().top;
        rowsAbove.forEach(({ id, top }) => {
          const row = element.querySelector(`[data-agent-v2-message-id="${id}"]`);
          if (row) maxRowShift = Math.max(maxRowShift, Math.abs(row.getBoundingClientRect().top - listTop - top));
        });
        if (getAnswerCount() > shownAnswerCount) nextAnswerAt ??= performance.now();
        await new Promise(requestAnimationFrame);
      }

      return { scrollTops, maxRowShift, hasNextAnswer: nextAnswerAt !== undefined };
    })();
    (window as unknown as { agentScrollRecording: typeof recording }).agentScrollRecording = recording;
  }, {
    answerText: 'The answer written before the stop.',
    questionText: goingText,
    settleMs: GLIDE_RECORDING_SETTLE_MS,
    timeoutMs: 10_000,
  });

  return () => list.evaluate(() => (
    window as unknown as { agentScrollRecording: Promise<ListScrollRecording> }
  ).agentScrollRecording);
}

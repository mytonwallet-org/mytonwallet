import type { Page } from '@playwright/test';

import { expect, getAgentV2Conversation, test } from './fixtures';

const VIEWPORTS = [
  { name: 'phone Classic', width: 402, height: 874 },
  { name: 'desktop', width: 1280, height: 900 },
];
const ANSWER_SELECTOR = '[data-agent-v2-message-role="assistant"]';
const QUESTION_SELECTOR = '[data-agent-v2-message-role="user"]';
const BUBBLE_SELECTOR = '[class*="__bubble__"]';
const GAP_SELECTOR = '[class*="__dissolveGap__"]';
const SNAP_LAYER_SELECTOR = '#agent-snap-effect-layer';
// From the press on Regenerate until the next answer has come in place of the one that turned to dust
const RECORDING_MS = 3000;
const LONG_QUESTION_WORDS = 40;
const POSITION_TOLERANCE_PX = 1;

const CASES = [
  // The spacer pushes a short chat to the bottom of the list, so the answer's space holds the chat up
  { name: 'a short chat opened again', questionCount: 1, isReopened: true },
  // The list keeps its end in place
  { name: 'a long chat opened again', questionCount: 6, isReopened: true },
  // The question asked last keeps a screen of space under it
  { name: 'a long chat just asked', questionCount: 6, isReopened: false },
];

for (const viewport of VIEWPORTS) {
  test.describe(`Agent V2 regeneration on ${viewport.name}`, () => {
    test.use({ viewport: { width: viewport.width, height: viewport.height } });

    for (const { name, questionCount, isReopened } of CASES) {
      test(`keeps the messages over a regenerated answer in place in ${name}`, async ({ agentV2, page }, testInfo) => {
        test.slow();
        await agentV2.reset();
        await agentV2.seedWallet();
        await agentV2.open();
        await agentV2.waitForList();
        for (let index = 0; index < questionCount; index++) {
          const question = buildQuestion(index);
          await agentV2.send(question);
          await expect(getAgentV2Conversation(page).getByText(`Deterministic response: ${question}`, { exact: true }))
            .toBeVisible({ timeout: 15000 });
          await expect(page.getByRole('status')).toHaveCount(0);
        }
        if (isReopened) {
          await page.getByRole('button', { name: 'Back', exact: true }).click();
          await expect(page.getByRole('region', { name: 'Chats', exact: true })).toBeVisible();
          await agentV2.openThread();
        }
        await page.locator(ANSWER_SELECTOR).last().locator(BUBBLE_SELECTOR).click({ button: 'right' });
        // The chat has settled, including a smooth scroll from Playwright's retry of the click
        await expect.poll(async () => {
          const frames = await recordRegeneration(page, 200);
          return frames[0].questionTop === frames.at(-1)!.questionTop;
        }).toBe(true);

        const recording = recordRegeneration(page, RECORDING_MS);
        await page.getByText('Regenerate', { exact: true }).click();
        const frames = await recording;
        await testInfo.attach('regeneration.json', {
          body: JSON.stringify(frames, undefined, 2), contentType: 'application/json',
        });
        await expect(getAgentV2Conversation(page).getByText(/^Regenerated response:/u)).toBeVisible();

        // The answer left as dust, or faded where dust isn't drawn, and its space was held
        expect(frames.some(({ ghostCount }) => ghostCount > 0), JSON.stringify(frames)).toBe(true);
        const heldFrames = frames.filter(({ gapHeight }) => gapHeight !== undefined && gapHeight > 0);
        expect(heldFrames.length, JSON.stringify(frames)).toBeGreaterThan(0);
        // Nothing over the answer moved while its space was held: neither as the run's activity came under the
        // question, nor as the next answer came into the space
        const { questionTop } = frames[0];
        for (const frame of heldFrames) {
          expect(Math.abs(frame.questionTop - questionTop), JSON.stringify(frame))
            .toBeLessThanOrEqual(POSITION_TOLERANCE_PX);
        }
      });
    }
  });
}

function buildQuestion(index: number) {
  return `Question ${index + 1}: ${'words '.repeat(LONG_QUESTION_WORDS).trim()}`;
}

// On every frame: where the last question's bubble stands, the space the dissolved answer left, and the ghosts over
// the list
function recordRegeneration(page: Page, duration: number) {
  return page.evaluate(async ({
    recordingDuration, questionSelector, bubbleSelector, gapSelector, layerSelector,
  }) => {
    const frames = [];
    const startedAt = performance.now();
    while (performance.now() - startedAt < recordingDuration) {
      await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
      const host = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-conversation]')).at(-1)!;
      const question = Array.from(host.querySelectorAll<HTMLElement>(questionSelector)).at(-1)!;
      const bubble = question.querySelector<HTMLElement>(bubbleSelector) ?? question;
      const gap = host.querySelector<HTMLElement>(gapSelector);
      frames.push({
        time: Math.round(performance.now() - startedAt),
        questionTop: bubble.getBoundingClientRect().top,
        gapHeight: gap?.offsetHeight,
        ghostCount: document.querySelector(layerSelector)?.childElementCount ?? 0,
      });
    }
    return frames;
  }, {
    recordingDuration: duration,
    questionSelector: QUESTION_SELECTOR,
    bubbleSelector: BUBBLE_SELECTOR,
    gapSelector: GAP_SELECTOR,
    layerSelector: SNAP_LAYER_SELECTOR,
  });
}

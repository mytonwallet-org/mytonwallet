import { expect, test } from './fixtures';
import {
  assertCalmReveal,
  assertGradualMorph,
  assertLanding,
  assertShapeKept,
  assertWholeMorph,
  delayStoredHistory,
  getIsSameRect,
  getMorphSourceRects,
  measurePlaceholders,
  recordHistoryMorph,
  waitForPlaceholdersSettled,
} from './historyRevealChecks';

const VIEWPORTS = [
  { name: 'phone Classic', width: 402, height: 874 },
  { name: 'desktop', width: 1280, height: 900 },
];
// Scrollbars that take room from the list from the app's start, as Safari's do on a Mac. Chromium draws no custom
// scrollbar for an element with scrollbar colours, so the style takes the app's colours off.
const CLASSIC_SCROLLBAR_STYLE = '.custom-scroll { scrollbar-color: auto !important; scrollbar-width: auto !important; }'
  + ' .custom-scroll::-webkit-scrollbar { width: 15px !important; }';
const CLASSIC_SCROLLBAR_WIDTH = 15;
// The placeholders the chat's list row counts, under a history that holds more messages than they and the list do
const SHORT_LINES_PLACEHOLDER_COUNT = 4;

// Playwright hides Chromium's scrollbars, which then take no room
test.use({ launchOptions: { ignoreDefaultArgs: ['--hide-scrollbars'] } });

for (const viewport of VIEWPORTS) {
  test.describe(`Agent V2 history reveal with classic scrollbars on ${viewport.name}`, () => {
    test.use({ viewport: { width: viewport.width, height: viewport.height } });

    test('lands one-line messages on their bubbles in the column the placeholders stood in', async ({
      agentV2, page,
    }, testInfo) => {
      // A constructed style sheet, which the app's content security policy leaves to the page
      await page.addInitScript((style) => {
        const sheet = new CSSStyleSheet();
        sheet.replaceSync(style);
        document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
      }, CLASSIC_SCROLLBAR_STYLE);
      await agentV2.reset();
      await agentV2.seedWallet();
      const releaseHistory = await delayStoredHistory(page, 'shortLines');
      await agentV2.open();
      await agentV2.waitForList();
      await agentV2.openThread();
      const placeholders = page.locator('[data-agent-conversation] [data-agent-skeleton-role]');
      await expect(placeholders).toHaveCount(SHORT_LINES_PLACEHOLDER_COUNT);
      await waitForPlaceholdersSettled(page);
      const shown = await measurePlaceholders(page);

      const recording = recordHistoryMorph(page);
      releaseHistory();
      const frames = await recording;
      await testInfo.attach('classic-scrollbars-morph.json', {
        body: JSON.stringify({ shown, frames }, undefined, 2), contentType: 'application/json',
      });
      // The list scrolls, its scrollbar taking room from its column, which the placeholders kept to as well
      const { list } = frames.at(-1)!;
      expect(list.scrollbarWidth).toBe(CLASSIC_SCROLLBAR_WIDTH);
      expect(list.isScrollable).toBe(true);
      for (const placeholder of shown) {
        expect(placeholder.right, JSON.stringify({ placeholder, list })).toBeLessThanOrEqual(list.contentRight + 1);
      }
      // The messages beyond the placeholders grow out of made-up ones
      const sources = getMorphSourceRects(frames);
      expect(sources.filter(({ rect }) => !shown.some((placeholder) => getIsSameRect(placeholder, rect))).length,
        JSON.stringify(sources)).toBeGreaterThan(0);
      assertCalmReveal(frames, shown);
      assertShapeKept(frames);
      assertGradualMorph(frames, shown);
      assertWholeMorph(frames);
      assertLanding(frames);
    });
  });
}

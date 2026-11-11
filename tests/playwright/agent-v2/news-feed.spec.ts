import type { Page } from '@playwright/test';

import type { AgentV2Fixture } from './fixtures';

import { expect, getAgentV2Conversation, test } from './fixtures';

const VIEWPORTS = [
  { name: 'phone Classic', width: 402, height: 874 },
  { name: 'desktop', width: 1280, height: 900 },
];
const DAY = 24 * 60 * 60 * 1000;
const HOUR = 60 * 60 * 1000;
const LATEST_DAY_START = Date.parse('2026-08-11T06:00:00.000Z');
const DAY_COUNT = 3;
const NEWS_PER_DAY = 3;
const CAPSULE_SELECTOR = '[class*="__dateLineDayHeader__"]';
const CAPSULE_FILL_SELECTOR = '[class*="__dateSeparator__"]';
// The second post of the middle day
const MIDDLE_POST_SELECTOR = '[data-agent-news-event-id="104"]';
// A stuck capsule stands 6 px under the header, as on iOS
const STUCK_CAPSULE_GAP = 6;
// The stuck capsule fades once the feed has rested for a second, over 300 ms; a slow runner gets some slack
const STUCK_CAPSULE_HIDE_TIMEOUT = 3000;
// Covers the discussion sliding away and the feed settling under it
const RETURN_RECORDING_MS = 1000;
const OLDER_CURSOR = 'older';
const OLDER_NEWS_COUNT = 3;
// Older news start loading once at most this many rows lie wholly above the part of the feed under the header
const OLDER_NEWS_THRESHOLD_ROW_COUNT = 5;
// Each row of the feed: a post, a day's line or the "New" line
const ROW_SELECTOR = '[data-agent-v2-message-id], [class*="__dateLine__"], [class*="__unreadDivider__"]';
// How far past the header's bottom the test's scroll leaves a row's bottom
const ROW_CROSSING_DISTANCE = 20;
// Covers a request for older news leaving the SDK after a scroll
const OLDER_NEWS_REQUEST_WAIT_MS = 500;

interface CapsuleSample {
  top: number;
  opacity: number;
}

/** The feed's older page, which waits until the test lets it come */
interface OlderNewsPage {
  requestCount: number;
  arrival: Promise<void>;
  release: NoneToVoidFunction;
}

for (const viewport of VIEWPORTS) {
  test.describe(`Agent V2 news feed on ${viewport.name}`, () => {
    test.use({ viewport: { width: viewport.width, height: viewport.height } });

    test('keeps the day capsule 6 px under the header while the feed scrolls, then fades it once it rests', async ({
      agentV2, page,
    }) => {
      await openFeedOfSeveralDays(agentV2, page);
      const headerBottom = await getHeaderBottom(page);
      const stuckTop = headerBottom + STUCK_CAPSULE_GAP;
      // The middle of a day comes under the header: near the day's end the next day's capsule pushes the stuck one up,
      // and a fixed scroll can land there, depending on how tall the fonts make the posts
      const postTop = await page.locator(MIDDLE_POST_SELECTOR).evaluate((post) => post.getBoundingClientRect().top);
      await getAgentV2Conversation(page).hover();
      await page.mouse.wheel(0, postTop - headerBottom);
      await expect.poll(async () => (await findStuckCapsule(page, stuckTop))?.opacity).toBe(1);

      await expect.poll(async () => (await findStuckCapsule(page, stuckTop))?.opacity, {
        timeout: STUCK_CAPSULE_HIDE_TIMEOUT,
      }).toBe(0);

      await page.mouse.wheel(0, -40);
      await expect.poll(async () => (await findStuckCapsule(page, stuckTop))?.opacity).toBe(1);
    });

    test('stands a day capsule as far from the post above it as from the post below it', async ({ agentV2, page }) => {
      await openFeedOfSeveralDays(agentV2, page);

      // Each capsule is measured in its place in the list, under the previous day's last post brought to the middle
      const gaps = await page.evaluate(({ capsuleSelector, capsuleFillSelector }) => (
        Array.from(document.querySelectorAll<HTMLElement>(capsuleSelector)).flatMap((capsule) => {
          const previousPosts = capsule.parentElement!.previousElementSibling
            ?.querySelectorAll<HTMLElement>('[data-agent-news-event-id]');
          const previousPost = previousPosts?.[previousPosts.length - 1];
          const nextPost = capsule.parentElement!.querySelector<HTMLElement>('[data-agent-news-event-id]');
          if (!previousPost || !nextPost) return [];

          previousPost.scrollIntoView({ block: 'center', behavior: 'instant' });
          const fill = capsule.querySelector<HTMLElement>(capsuleFillSelector)!.getBoundingClientRect();
          return [{
            above: fill.top - previousPost.getBoundingClientRect().bottom,
            below: nextPost.getBoundingClientRect().top - fill.bottom,
          }];
        })
      ), { capsuleSelector: CAPSULE_SELECTOR, capsuleFillSelector: CAPSULE_FILL_SELECTOR });

      expect(gaps).toHaveLength(DAY_COUNT - 1);
      for (const { above, below } of gaps) {
        expect(above).toBeCloseTo(below, 0);
      }
    });

    test('comes back from a discussion to the feed as it was left, with no placeholders', async ({ agentV2, page }) => {
      await openFeedOfSeveralDays(agentV2, page);
      // The post with its Discuss strip in sight
      const discuss = page.getByRole('button', { name: 'Discuss, News 4', exact: true });
      await discuss.scrollIntoViewIfNeeded();
      const cardTop = await waitForStillTop(page, MIDDLE_POST_SELECTOR);

      await discuss.click();
      await expect(page.locator('[data-agent-composer]').last()).toBeVisible();
      await expect(page.locator(MIDDLE_POST_SELECTOR)).toHaveCount(0);

      const recording = recordReturningFeed(page, MIDDLE_POST_SELECTOR);
      await page.getByRole('button', { name: 'Back' }).last().click();
      const frames = await recording;

      const feedFrames = frames.filter(({ top }) => top !== undefined);
      expect(feedFrames.length).toBeGreaterThan(0);
      for (const frame of frames) {
        expect(frame.placeholderCount, JSON.stringify(frame)).toBe(0);
      }
      for (const frame of feedFrames) {
        expect(frame.isCardShown, JSON.stringify(frame)).toBe(true);
        expect(frame.top, JSON.stringify(frame)).toBeCloseTo(cardTop, 0);
      }
    });

    test('starts loading older news as it scrolls up with five rows left above, keeping the posts in place', async ({
      agentV2, page,
    }) => {
      const olderNewsPage = createOlderNewsPage();
      await openFeedOfSeveralDays(agentV2, page, olderNewsPage);
      await getAgentV2Conversation(page).hover();

      // Six rows above: the sixth row's bottom is just above the header
      await scrollRowBottomToHeader(page, OLDER_NEWS_THRESHOLD_ROW_COUNT, -ROW_CROSSING_DISTANCE);
      expect(await countRowsAboveHeader(page)).toBe(OLDER_NEWS_THRESHOLD_ROW_COUNT + 1);
      await page.waitForTimeout(OLDER_NEWS_REQUEST_WAIT_MS);
      expect(olderNewsPage.requestCount).toBe(0);

      // Five rows above: the sixth row comes under the header
      await page.mouse.wheel(0, -2 * ROW_CROSSING_DISTANCE);
      await expect.poll(() => olderNewsPage.requestCount).toBe(1);
      const postTop = await waitForStillTop(page, MIDDLE_POST_SELECTOR);
      expect(await countRowsAboveHeader(page)).toBe(OLDER_NEWS_THRESHOLD_ROW_COUNT);

      // The older news come in above, and the posts on screen stay where they are
      olderNewsPage.release();
      await expect(page.locator('[data-agent-news-event-id]')).toHaveCount(DAY_COUNT * NEWS_PER_DAY + OLDER_NEWS_COUNT);
      expect(await waitForStillTop(page, MIDDLE_POST_SELECTOR)).toBeCloseTo(postTop, 0);
    });
  });
}

async function openFeedOfSeveralDays(agentV2: AgentV2Fixture, page: Page, olderNewsPage?: OlderNewsPage) {
  await agentV2.reset('news-post');
  await agentV2.seedWallet();
  await page.route('**/api/v2/news-feed?*', async (route) => {
    const isOlderPage = new URL(route.request().url()).searchParams.has('cursor');
    if (isOlderPage) {
      olderNewsPage!.requestCount++;
      await olderNewsPage!.arrival;
    }
    const response = await route.fetch();
    const feed = await response.json();
    feed.items = isOlderPage ? buildOlderNews() : buildNewsOfSeveralDays();
    if (olderNewsPage && !isOlderPage) feed.nextCursor = OLDER_CURSOR;
    await route.fulfill({ response, json: feed });
  });
  await agentV2.open();
  await agentV2.waitForList();
  await page.getByRole('button', { name: /^News,/u }).click();
  await expect(page.locator(CAPSULE_SELECTOR)).toHaveCount(DAY_COUNT);
  await expect(page.locator('[data-agent-news-event-id]')).toHaveCount(DAY_COUNT * NEWS_PER_DAY);
  // The posts grow out of the placeholders first
  await expect(page.locator('[data-agent-skeleton]')).toHaveCount(0);
  await page.locator('[data-agent-conversation]').evaluate((conversation) => (
    Promise.allSettled(conversation.getAnimations({ subtree: true }).map((animation) => animation.finished))
  ));
}

// Newest last, each tall enough that a day's posts outgrow the screen
function buildNewsOfSeveralDays() {
  return Array.from({ length: DAY_COUNT * NEWS_PER_DAY }, (_, index) => {
    const day = DAY_COUNT - 1 - Math.floor(index / NEWS_PER_DAY);
    const deliveredAt = LATEST_DAY_START - day * DAY + (index % NEWS_PER_DAY) * HOUR;
    return {
      eventId: 100 + index,
      deliveredAt: new Date(deliveredAt).toISOString(),
      headline: `News ${index}`,
      body: `News ${index} body. ${'Market context. '.repeat(80)}`,
      sources: [{ name: 'Source', url: 'https://example.com/source' }],
    };
  });
}

// A day before the feed's first page, which its older page brings
function buildOlderNews() {
  return Array.from({ length: OLDER_NEWS_COUNT }, (_, index) => ({
    eventId: 90 + index,
    deliveredAt: new Date(LATEST_DAY_START - DAY_COUNT * DAY + index * HOUR).toISOString(),
    headline: `Older news ${index}`,
    body: `Older news ${index} body. ${'Market context. '.repeat(80)}`,
    sources: [{ name: 'Source', url: 'https://example.com/source' }],
  }));
}

function createOlderNewsPage(): OlderNewsPage {
  let release!: NoneToVoidFunction;
  const arrival = new Promise<void>((resolve) => {
    release = resolve;
  });
  return { requestCount: 0, arrival, release };
}

// Puts the bottom of the feed's row at `rowIndex` `distance` px below the header's bottom
async function scrollRowBottomToHeader(page: Page, rowIndex: number, distance: number) {
  const { headerBottom, rowBottoms } = await measureRows(page);
  await page.mouse.wheel(0, rowBottoms[rowIndex] - headerBottom - distance);
  await waitForStillTop(page, MIDDLE_POST_SELECTOR);
}

// The rows that lie wholly above the part of the feed under the header
async function countRowsAboveHeader(page: Page) {
  const { headerBottom, rowBottoms } = await measureRows(page);
  return rowBottoms.filter((bottom) => bottom <= headerBottom).length;
}

// Where the header and each row of the feed end. A day's line stuck under the header ends where it stands in the list,
// right above the row after it.
function measureRows(page: Page) {
  return page.evaluate((rowSelector) => {
    const conversation = document.querySelector('[data-agent-conversation]')!;
    const rows = Array.from(conversation.querySelectorAll<HTMLElement>(rowSelector));
    return {
      headerBottom: conversation.querySelector('[data-agent-header]')!.getBoundingClientRect().bottom,
      rowBottoms: rows.map((row, index) => {
        const { bottom } = row.getBoundingClientRect();
        const nextRow = rows[index + 1];
        return nextRow ? Math.min(bottom, nextRow.getBoundingClientRect().top) : bottom;
      }),
    };
  }, ROW_SELECTOR);
}

async function getHeaderBottom(page: Page) {
  return page.locator('[data-agent-conversation] [data-agent-header]').evaluate((header) => (
    header.getBoundingClientRect().bottom
  ));
}

// The capsule that stands where a stuck one does, if any
function findStuckCapsule(page: Page, stuckTop: number) {
  return page.evaluate(({ capsuleSelector, capsuleFillSelector, top }): CapsuleSample | undefined => {
    const capsule = Array.from(document.querySelectorAll<HTMLElement>(capsuleSelector))
      .find((element) => Math.abs(element.getBoundingClientRect().top - top) <= 1);
    const fill = capsule?.querySelector<HTMLElement>(capsuleFillSelector);
    if (!capsule || !fill) return undefined;

    return {
      top: capsule.getBoundingClientRect().top,
      opacity: Number(getComputedStyle(capsule).opacity) * Number(getComputedStyle(fill).opacity),
    };
  }, { capsuleSelector: CAPSULE_SELECTOR, capsuleFillSelector: CAPSULE_FILL_SELECTOR, top: stuckTop });
}

async function waitForStillTop(page: Page, selector: string) {
  let previousTop: number | undefined;
  await expect.poll(async () => {
    const top = await page.locator(selector).evaluate((element) => element.getBoundingClientRect().top);
    const isStill = top === previousTop;
    previousTop = top;
    return isStill;
  }).toBe(true);
  return previousTop!;
}

// The feed coming back as the discussion slides away: whether placeholders show, and the card's place in each frame
function recordReturningFeed(page: Page, cardSelector: string) {
  return page.evaluate(async ({ selector, duration }) => {
    const frames: { placeholderCount: number; isCardShown: boolean; top?: number }[] = [];
    const startedAt = performance.now();
    while (performance.now() - startedAt < duration) {
      await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
      const card = document.querySelector<HTMLElement>(selector);
      const style = card ? getComputedStyle(card) : undefined;
      frames.push({
        placeholderCount: document.querySelectorAll('[data-agent-skeleton]').length,
        isCardShown: style?.visibility === 'visible' && Number(style.opacity) === 1,
        top: card?.getBoundingClientRect().top,
      });
    }
    return frames;
  }, { selector: cardSelector, duration: RETURN_RECORDING_MS });
}

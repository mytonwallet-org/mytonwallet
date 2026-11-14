import type { Page, Route } from '@playwright/test';
import { writeFile } from 'node:fs/promises';

import { expect, test } from './fixtures';
import {
  assertCalmReveal,
  assertGradualMorph,
  assertLanding,
  assertShapeKept,
  assertWholeMorph,
  BUBBLE_SELECTOR,
  CONSECUTIVE_QUESTIONS_LISTED_COUNT,
  CREATED_AT,
  delayStoredHistory,
  FOLLOWUPS,
  getIsSameRect,
  getMorphSourceRects,
  MADE_UP_PLACEHOLDER_INSET,
  measurePlaceholders,
  recordHistoryMorph,
  SHORT_QUESTION_MESSAGES,
  STORED_MESSAGES,
  waitForPlaceholdersSettled,
} from './historyRevealChecks';

const VIEWPORTS = [
  { name: 'phone Classic', width: 402, height: 874 },
  { name: 'desktop', width: 1280, height: 900 },
];
// The mock server's own thread, which its runs answer in
const SERVER_THREAD_ID = '44444444-4444-4444-8444-444444444444';
const FLIGHT_SELECTOR = '[class*="__flight__"][aria-hidden="true"]';
// The feed's and the thread's cards name the same picture by different addresses
const PICTURE_PATHNAME = '/icon-512x512.png';
const FEED_PICTURE_PATH = `${PICTURE_PATHNAME}?news=feed`;
const THREAD_PICTURE_PATH = `${PICTURE_PATHNAME}?news=thread`;
// Once the feed card shows the picture, a new `img` loads it again for this long, so that, as in Chromium on a Mac, it
// cannot show the picture in its first frame
const PICTURE_RELOAD_DELAY_MS = 200;
// The thread is created by the time the card is halfway into the discussion
const THREAD_CREATION_DELAY_MS = 250;
// The card has landed and the post has shown its picture for this many frames when the recording ends
const LANDED_FRAME_COUNT = 10;
const NEWS_PICTURE_MAX_RECORDING_MS = 5000;
// Follow-ups appear 150 ms apart, which a recording brackets between the frames around each appearance
const FOLLOWUP_STAGGER_MIN_MS = 130;
const FOLLOWUP_STAGGER_MAX_MS = 170;
// Samples this close together read the same frame
const SAME_FRAME_MS = 4;
// A tapped follow-up turns into its question in place over 450 ms, and the list takes it up 250 ms later, as on iOS
const QUESTION_IN_PLACE_MS = 700;
// Where the question settles in place, after the follow-ups have given their space back, against where they began
const QUESTION_IN_PLACE_TOLERANCE_PX = 24;
// A question sent from the field flies into its bubble over Telegram's 250 ms, and the list takes it up 250 ms later
const QUESTION_FLIGHT_MS = 500;
// A suggestion's reveal, which the tail of the bubble it hangs from goes into its corner with
const TAIL_AWAY_MS = 300;
// The tail grows back on a spring that settles in 400 ms, 50 ms after the suggestions go
const TAIL_SPRING_MS = 400;
const TAIL_BACK_MS = 450;
// The longest the tail is recorded growing back, as a busy runner gets its transitions under way later
const TAIL_BACK_MAX_RECORDING_MS = 4000;
// The tail has rested whole for this many frames when such a recording ends
const TAIL_WHOLE_FRAME_COUNT = 3;
// An empty chat's hints fade and slide down this far over this time as its first question comes
const HINTS_LEAVE_MS = 250;
const HINTS_LEAVE_SLIDE_PX = 26;
// The farthest the question a new chat opens with stands below the list's top, under the date line that opens the chat
const OPENING_QUESTION_MAX_OFFSET_PX = 96;
// A flight's last state stands on the bubble as the flight reads it in the same frame
const FLIGHT_LANDING_TOLERANCE_PX = 2;
// A busy runner gets a flight under way and ends it later
const FLIGHT_MAX_RECORDING_MS = 6000;
// The opening flight is recorded until the chat has rested this long after it, which a busy runner reaches later
const OPENING_SETTLE_MS = 500;
// An answer longer than the screen, whose paragraphs take a line each at any width
const LONG_ANSWER = Array.from({ length: 50 }, (_, index) => `Part ${index + 1}.`).join('\n\n');
// The most a streamed letter may move as it settles from the Agent's colours into the text's
const LETTER_TOLERANCE_PX = 0.25;
// Questions asked before, whose answers run over a couple of lines on a phone
const QUEUE_HISTORY_QUESTIONS = [
  'Open the chat with a question long enough to wrap',
  'Ask a second question that wraps onto another line',
  'Ask a third question that wraps onto another line too',
];
const QUEUE_PINNED_QUESTION = 'The question being answered';
const QUEUE_WAITING_QUESTIONS = [
  'The first question that waits',
  'The second question that waits',
  'The third question that waits',
];
// The Agent thinks this long, and the list is recorded this long after an answer has come
const QUEUE_STEP_MS = 1500;
const QUEUE_RECORDING_MAX_MS = 30_000;
// The list rests once it has held still for longer than a question that shows where it lands waits there before the
// list takes it up
const QUEUE_REST_MS = QUESTION_IN_PLACE_MS;
// A queued question that moves the rows on screen does so within this time
const ROW_MOVE_WATCH_MS = 1500;
// A frame is this long at 60 Hz
const FRAME_MS = 1000 / 60;
// Rows hold still to within this, as subpixel layout rounds
const STILL_TOLERANCE_PX = 2;
// The fastest a row moves on screen in a frame: the scroll that pins a question and a glide together stay below it,
// while a jump of the list or of the rows over a screen's part goes past it
const MAX_FRAME_STEP_PX = 56;

test.use({ video: 'on' });

for (const viewport of VIEWPORTS) {
  test.describe(`Agent V2 motion on ${viewport.name}`, () => {
    test.use({ viewport: { width: viewport.width, height: viewport.height } });

    test('crossfades every cold chat-list row, including News', async ({ agentV2, page }, testInfo) => {
      await agentV2.reset('news-post');
      await agentV2.seedWallet();
      let releaseList!: () => void;
      const listMayFinish = new Promise<void>((resolve) => {
        releaseList = resolve;
      });
      await page.route(/\/api\/v2\/threads(?:\?|$)/u, async (route) => {
        if (route.request().method() !== 'GET') {
          await route.continue();
          return;
        }
        await listMayFinish;
        await route.fulfill({ json: {
          protocolVersion: 3,
          threads: STORED_MESSAGES.map((message, index) => ({ thread: {
            id: `00000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
            title: message.text,
            revision: 1,
            createdAt: CREATED_AT,
            updatedAt: CREATED_AT,
            lastActivityAt: CREATED_AT,
            messageCount: 2,
          } })),
        } });
      });
      await agentV2.open();
      const list = page.getByRole('region', { name: 'Chats', exact: true });
      const skeleton = list.getByRole('status', { name: 'Loading...', exact: true });
      await expect(skeleton).toBeVisible();
      const loadingFrames = await recordChatListCrossfade(page, 400);
      expect(loadingFrames.length).toBeGreaterThan(5);
      for (const frame of loadingFrames) {
        expect(frame.newsCount).toBe(0);
        expect(frame.threadCount).toBe(0);
        expect(frame.skeletonRowCount).toBeGreaterThan(5);
        expect(frame.skeletonOpacity).toBeGreaterThan(0.99);
      }
      const recording = recordChatListCrossfade(page, 700);
      releaseList();
      const frames = await recording;
      const framesPath = testInfo.outputPath('chat-list-crossfade-frames.json');
      await writeFile(framesPath, JSON.stringify({ loadingFrames, frames }, undefined, 2));
      await testInfo.attach('chat-list-crossfade-frames.json', { path: framesPath, contentType: 'application/json' });
      const blended = frames.filter(({ skeletonOpacity, contentOpacity, newsOpacity }) => (
        skeletonOpacity > 0.05 && skeletonOpacity < 0.95
        && contentOpacity > 0.05 && contentOpacity < 0.95
        && newsOpacity > 0.05 && newsOpacity < 0.95
      ));
      expect(blended.length).toBeGreaterThanOrEqual(3);
      for (const frame of blended) {
        expect(frame.newsOpacity).toBeCloseTo(frame.contentOpacity, 2);
        expect(frame.firstNewsTop).toBeCloseTo(frame.firstSkeletonTop!, 0);
      }
      await expect(skeleton).toHaveCount(0);
      await expect(list.locator('[data-agent-news-row]')).toBeVisible();
      await expect(list.locator('[data-agent-v2-thread-id]')).toHaveCount(STORED_MESSAGES.length);
      await list.screenshot({ path: testInfo.outputPath('loaded-chat-list.png') });
    });

    for (const isNewsOnly of [false, true]) {
      test(isNewsOnly
        ? 'shapes a news discussion\'s placeholders as its list row tells and grows the post out of the lowest'
        : 'grows consecutive answers out of the placeholders from the bottom up, whoever\'s they were', async ({
        agentV2, page,
      }, testInfo) => {
        await agentV2.reset();
        await agentV2.seedWallet();
        const releaseHistory = await delayStoredHistory(page, isNewsOnly ? 'newsOnly' : 'stored');
        await agentV2.open();
        await agentV2.waitForList();
        await agentV2.openThread();
        // The placeholders follow the chat's list row from the composer up: the four stored messages, taken to
        // alternate from a question, or the question the row counts under the news post's card
        const expectedRoles = isNewsOnly ? ['user', 'assistant'] : ['assistant', 'user', 'assistant', 'user'];
        const placeholders = page.locator('[data-agent-conversation] [data-agent-skeleton-role]');
        await expect(placeholders).toHaveCount(expectedRoles.length);
        await waitForPlaceholdersSettled(page);
        expect(await measureComposerGap(page, '[data-agent-skeleton-role]:first-child')).toBeCloseTo(16, 0);
        const initial = await placeholders.evaluateAll((elements) => elements.slice(0, 4).map((element) => {
          const rect = element.getBoundingClientRect();
          const tail = getComputedStyle(element, '::after');
          const host = element.parentElement!.getBoundingClientRect();
          return {
            role: element.getAttribute('data-agent-skeleton-role'),
            width: rect.width,
            height: rect.height,
            top: rect.top,
            bottom: rect.bottom,
            availableWidth: Math.min(host.width - 16, 402),
            tailWidth: Number.parseFloat(tail.width),
            tailHeight: Number.parseFloat(tail.height),
            tailMask: tail.maskImage,
          };
        }));
        expect(initial.map(({ role }) => role)).toEqual(expectedRoles);
        // The Agent's placeholders are wide and tall, and the user's narrower and shorter than any of them
        const assistantPlaceholders = initial.filter(({ role }) => role === 'assistant');
        const userPlaceholders = initial.filter(({ role }) => role === 'user');
        for (const placeholder of assistantPlaceholders) {
          expect(placeholder.width).toBeGreaterThanOrEqual(placeholder.availableWidth * 0.63);
          expect(placeholder.height).toBeGreaterThanOrEqual(120);
        }
        const narrowestAssistantWidth = Math.min(...assistantPlaceholders.map(({ width }) => width));
        const shortestAssistantHeight = Math.min(...assistantPlaceholders.map(({ height }) => height));
        for (const placeholder of userPlaceholders) {
          expect(placeholder.width).toBeLessThan(narrowestAssistantWidth);
          expect(placeholder.height).toBeLessThan(shortestAssistantHeight);
          expect(placeholder.height).toBeGreaterThanOrEqual(placeholder.tailHeight);
        }
        for (const placeholder of initial) {
          expect(placeholder.tailWidth).toBeGreaterThan(0);
          expect(placeholder.tailHeight).toBeGreaterThan(0);
          expect(placeholder.tailMask).not.toBe('none');
        }
        expect(initial.find(({ role }) => role === 'assistant')!.height).toBeGreaterThanOrEqual(184);

        const shown = await measurePlaceholders(page);
        const recording = recordHistoryMorph(page);
        releaseHistory();
        const frames = await recording;
        const framesPath = testInfo.outputPath('morph-frames.json');
        await writeFile(framesPath, JSON.stringify({ initial, shown, frames }, undefined, 2));
        await testInfo.attach('morph-frames.json', { path: framesPath, contentType: 'application/json' });
        assertFollowupStagger(frames);
        assertCalmReveal(frames, shown);
        assertShapeKept(frames);
        assertGradualMorph(frames, shown);
        assertLanding(frames);
        // The placeholders guessed the chat's rows wrong, yet the messages take them from the bottom up, as on iOS and
        // Android: an answer grows out of a question's pill, and nothing fades in where it stands
        assertWholeMorph(frames);
        await expect(page.locator('[data-agent-conversation] [data-agent-skeleton]')).toHaveCount(0);
        expect(await measureComposerGap(page, '[data-agent-followup-id]')).toBeCloseTo(16, 0);
        await page.screenshot({ path: testInfo.outputPath('settled.png') });
      });
    }

    test('grows two questions in a row and the messages beyond the placeholders out of made-up ones above', async ({
      agentV2, page,
    }, testInfo) => {
      await agentV2.reset();
      await agentV2.seedWallet();
      const releaseHistory = await delayStoredHistory(page, 'consecutiveQuestions');
      await agentV2.open();
      await agentV2.waitForList();
      await agentV2.openThread();
      // The list row counts the answer and the question before it
      const placeholders = page.locator('[data-agent-conversation] [data-agent-skeleton-role]');
      await expect(placeholders).toHaveCount(CONSECUTIVE_QUESTIONS_LISTED_COUNT);
      await waitForPlaceholdersSettled(page);
      const shown = await measurePlaceholders(page);
      expect(shown.map(({ role }) => role)).toEqual(['assistant', 'user']);

      const recording = recordHistoryMorph(page);
      releaseHistory();
      const frames = await recording;
      await testInfo.attach('consecutive-questions-morph.json', {
        body: JSON.stringify({ shown, frames }, undefined, 2), contentType: 'application/json',
      });
      assertCalmReveal(frames, shown);
      assertShapeKept(frames);
      assertGradualMorph(frames, shown);
      assertLanding(frames);
      assertWholeMorph(frames);
      // The two messages over the placeholders grow out of made-up ones, the first question's on the user's side
      const sources = getMorphSourceRects(frames);
      const madeUp = sources.filter(({ rect }) => !shown.some((placeholder) => getIsSameRect(placeholder, rect)));
      expect(madeUp.map(({ id }) => id).sort(), JSON.stringify(sources)).toEqual(['message:0', 'message:1']);
      const list = frames.at(-1)!.list;
      const question = madeUp.find(({ id }) => id === 'message:1')!;
      expect(Math.abs(list.contentRight - MADE_UP_PLACEHOLDER_INSET - question.rect.right), JSON.stringify(question))
        .toBeLessThan(2);
      for (const frame of frames) {
        expect(frame.isMessageOrderPreserved, JSON.stringify(frame)).toBe(true);
      }
    });

    test('grows short questions out of their own placeholders, with no scrollbar and no shift after', async ({
      agentV2, page,
    }, testInfo) => {
      await agentV2.reset();
      await agentV2.seedWallet();
      const releaseHistory = await delayStoredHistory(page, 'shortQuestions');
      await agentV2.open();
      await agentV2.waitForList();
      await agentV2.openThread();
      // The chat alternates from its question, as its placeholders guess
      const placeholders = page.locator('[data-agent-conversation] [data-agent-skeleton-role]');
      await expect(placeholders).toHaveCount(SHORT_QUESTION_MESSAGES.length);
      await waitForPlaceholdersSettled(page);
      const shown = await measurePlaceholders(page);
      expect(shown.map(({ role }) => role)).toEqual(['assistant', 'user', 'assistant', 'user']);

      const recording = recordHistoryMorph(page);
      releaseHistory();
      const frames = await recording;
      const framesPath = testInfo.outputPath('short-questions-morph.json');
      await writeFile(framesPath, JSON.stringify({ shown, frames }, undefined, 2));
      await testInfo.attach('short-questions-morph.json', { path: framesPath, contentType: 'application/json' });
      // Every message grows out of its placeholder, the short questions out of wide ones
      expect(frames.filter(({ morphingCount }) => morphingCount === SHORT_QUESTION_MESSAGES.length).length)
        .toBeGreaterThanOrEqual(5);
      expect(new Set(frames.flatMap(({ morphSources }) => morphSources.map(({ id }) => id))).size)
        .toBe(SHORT_QUESTION_MESSAGES.length);
      assertCalmReveal(frames, shown);
      assertShapeKept(frames);
      assertGradualMorph(frames, shown);
      assertLanding(frames);
      assertFollowupStagger(frames);
      for (const frame of frames) {
        expect(frame.overlaps, JSON.stringify(frame)).toEqual([]);
        expect(frame.isMessageOrderPreserved, JSON.stringify(frame)).toBe(true);
      }
      expect(await measureComposerGap(page, '[data-agent-followup-id]')).toBeCloseTo(16, 0);
    });

    test('shows the placeholder at once, a history that comes at once taking its place', async ({ agentV2, page }) => {
      await agentV2.reset();
      await agentV2.seedWallet();
      const releaseHistory = await delayStoredHistory(page, 'stored');
      releaseHistory();
      await agentV2.open();
      await agentV2.waitForList();
      // Whether the placeholder shows while the chat opens, at full opacity from its first frame
      await page.evaluate(() => {
        const observer = new MutationObserver(() => {
          const skeleton = document.querySelector('[data-agent-conversation] [data-agent-skeleton]');
          if (skeleton && !document.body.dataset.skeletonOpacity) {
            document.body.dataset.skeletonOpacity = getComputedStyle(skeleton).opacity;
          }
        });
        observer.observe(document.body, { childList: true, subtree: true });
      });
      await agentV2.openThread();

      const messages = page.locator('[data-agent-conversation] [data-agent-v2-message-role]');
      await expect(messages).toHaveCount(STORED_MESSAGES.length);
      await expect(messages.last()).toBeVisible();
      expect(await page.evaluate(() => document.body.dataset.skeletonOpacity)).toBe('1');
      await expect(page.locator('[data-agent-conversation] [data-agent-skeleton]')).toHaveCount(0);
    });

    test('grows a news discussion out of placeholders shaped like it, the question staying on its side', async ({
      agentV2, page,
    }, testInfo) => {
      await agentV2.reset();
      await agentV2.seedWallet();
      const releaseHistory = await delayStoredHistory(page, 'newsQuestion');
      await agentV2.open();
      await agentV2.waitForList();
      await agentV2.openThread();
      // From the first frame, the question's pill under the news post's card, as the list row tells
      const placeholders = page.locator('[data-agent-conversation] [data-agent-skeleton-role]');
      await expect(placeholders).toHaveCount(2);
      // The screen has slid in
      await page.waitForTimeout(600);
      const shown = await measurePlaceholders(page);
      expect(shown.map(({ role }) => role)).toEqual(['user', 'assistant']);
      await page.waitForTimeout(300);
      expect(await measurePlaceholders(page)).toEqual(shown);

      await waitForPlaceholdersSettled(page);
      const recording = recordHistoryMorph(page);
      releaseHistory();
      const frames = await recording;
      await testInfo.attach('news-question-morph.json', {
        body: JSON.stringify({ shown, frames }, undefined, 2), contentType: 'application/json',
      });
      assertCalmReveal(frames, shown);
      assertShapeKept(frames);
      assertGradualMorph(frames, shown);
      assertLanding(frames);
      const chat = await page.locator('[data-agent-conversation]').last().evaluate((element) => {
        const { left, right } = element.getBoundingClientRect();
        return { middle: (left + right) / 2 };
      });
      const questionFrames = frames.flatMap(({ surfaces }) => surfaces.filter(({ id }) => id === 'message:1'));
      expect(questionFrames.length).toBeGreaterThan(0);
      // The question grows out of its own pill and never leaves the user's side
      for (const surface of questionFrames) {
        expect((surface.left + surface.right) / 2, JSON.stringify(surface)).toBeGreaterThan(chat.middle);
      }
      const settled = questionFrames.at(-1)!;
      expect(Math.abs(settled.right - shown[0].right)).toBeLessThan(24);
      for (const frame of frames) {
        expect(frame.overlaps, JSON.stringify(frame)).toEqual([]);
        expect(frame.isMessageOrderPreserved, JSON.stringify(frame)).toBe(true);
      }
    });

    test('reveals news placeholders every 150 ms then morphs the ready followups together', async ({
      agentV2, page,
    }, testInfo) => {
      await agentV2.reset('news-post');
      await agentV2.seedWallet();
      await page.route('**/api/v2/news-feed?*', async (route) => {
        const response = await route.fetch();
        const feed = await response.json();
        feed.items[0].discussion = { threadId: SERVER_THREAD_ID };
        await route.fulfill({ response, json: feed });
      });
      let releaseHistory!: () => void;
      const historyMayFinish = new Promise<void>((resolve) => {
        releaseHistory = resolve;
      });
      await page.route('**/api/v2/threads/*/messages?*', async (route) => {
        const response = await route.fetch();
        const history = await response.json();
        history.messages[0].followups = FOLLOWUPS;
        await historyMayFinish;
        await route.fulfill({ json: history });
      });
      await agentV2.open();
      await agentV2.waitForList();
      await page.getByRole('button', { name: /^News,/u }).click();
      const loadingRecording = recordFollowups(page, 3000, '[data-agent-followup-placeholder]');
      await page.getByRole('button', { name: 'Discuss, Deterministic MyPulse headline', exact: true }).click();
      await expect(page.locator('[data-agent-followup-placeholder]')).toHaveCount(3);
      await expect(page.locator(FLIGHT_SELECTOR)).toHaveCount(0);
      const loadingFrames = await loadingRecording;
      assertFollowupStagger(loadingFrames);
      assertFollowupBlurIn(loadingFrames);
      expect(await measureComposerGap(page, '[data-agent-followup-placeholder]')).toBeCloseTo(16, 0);
      const recording = recordFollowups(page);
      releaseHistory();
      const frames = await recording;
      const firstVisible = FOLLOWUPS.map((_, index) => (
        frames.find((frame) => frame.followupOpacities[index] > 0.05)?.time
      ));
      expect(firstVisible.every((time) => time !== undefined), JSON.stringify(frames)).toBe(true);
      expect(Math.max(...firstVisible as number[]) - Math.min(...firstVisible as number[])).toBeLessThan(35);
      expect(frames.at(-1)!.followupOpacities).toEqual([1, 1, 1]);
      expect(await measureComposerGap(page, '[data-agent-followup-id]')).toBeCloseTo(16, 0);
      const positions = frames.map(({ scrollTop }) => scrollTop);
      expect(Math.max(...positions) - Math.min(...positions)).toBeLessThan(2);
      await testInfo.attach('delayed-news-followups.json', {
        body: JSON.stringify({ loadingFrames, frames }, undefined, 2), contentType: 'application/json',
      });
    });

    test('reveals a fresh answer’s followups every 150 ms', async ({ agentV2, page }, testInfo) => {
      await agentV2.reset();
      await agentV2.seedWallet();
      let releaseRun!: () => void;
      const runMayFinish = new Promise<void>((resolve) => {
        releaseRun = resolve;
      });
      let markRunReady!: () => void;
      const runReady = new Promise<void>((resolve) => {
        markRunReady = resolve;
      });
      await page.route('**/api/v2/runs', async (route) => {
        const response = await route.fetch();
        const events = (await response.text()).trim().split('\n').map((line) => JSON.parse(line));
        const end = events.at(-1);
        events.splice(events.length - 1, 0, {
          protocolVersion: 3, type: 'followups', runId: end.runId, messageId: end.messageId,
          sequence: end.sequence, items: FOLLOWUPS,
        });
        end.sequence += 1;
        markRunReady();
        await runMayFinish;
        await route.fulfill({ response, body: `${events.map((event) => JSON.stringify(event)).join('\n')}\n` });
      });
      await agentV2.open();
      await agentV2.waitForList();
      await agentV2.send('A short answer');
      await runReady;
      const recording = recordFollowups(page, 2000);
      releaseRun();
      const frames = await recording;
      assertFollowupStagger(frames);
      assertFollowupBlurIn(frames);
      await testInfo.attach('fresh-answer-followups.json', {
        body: JSON.stringify(frames, undefined, 2), contentType: 'application/json',
      });
    });

    test('colours a streamed answer\'s own letters, none of them moving as they settle', async ({
      agentV2, page,
    }, testInfo) => {
      const question = 'Which letters settle where they stand?';
      const answerText = `Deterministic response: ${question}`;
      await agentV2.reset();
      await agentV2.seedWallet();
      await agentV2.open();
      await agentV2.waitForList();
      await agentV2.send(question);
      // The whole answer has come while its last letters still settle in the Agent's colours
      let colored: StreamedLetters | undefined;
      await expect.poll(async () => {
        colored = await measureStreamedLetters(page, answerText);
        return colored.isComplete && colored.letters.length > 0;
      }, { intervals: [16], timeout: 10_000 }).toBe(true);
      // The colours lie on the answer's own letters, and the copies over them draw nothing but their glow
      for (const color of colored!.copyColors) {
        expect(color, JSON.stringify(colored)).toBe('rgba(0, 0, 0, 0)');
      }
      await expect.poll(async () => (
        (await measureStreamedLetters(page, answerText)).letters.length
      ), { timeout: 2000 }).toBe(0);
      const settled = await measureStreamedLetters(page, answerText, colored!.letters.map(({ offset }) => offset));
      await testInfo.attach('streamed-letters.json', {
        body: JSON.stringify({ colored, settled }, undefined, 2), contentType: 'application/json',
      });
      // Each letter stands where it stood in the Agent's colours once it has settled in the text's
      for (const letter of colored!.letters) {
        const settledLetter = settled.letters.find(({ offset }) => offset === letter.offset);
        expect(settledLetter?.letter, JSON.stringify(letter)).toBe(letter.letter);
        expect(Math.abs(settledLetter!.left - letter.left), JSON.stringify({ letter, settledLetter }))
          .toBeLessThanOrEqual(LETTER_TOLERANCE_PX);
        expect(Math.abs(settledLetter!.right - letter.right), JSON.stringify({ letter, settledLetter }))
          .toBeLessThanOrEqual(LETTER_TOLERANCE_PX);
        expect(Math.abs(settledLetter!.top - letter.top), JSON.stringify({ letter, settledLetter }))
          .toBeLessThanOrEqual(LETTER_TOLERANCE_PX);
      }
    });

    test('shows a tapped follow-up where the follow-ups were before the list takes it up', async ({
      agentV2, page,
    }, testInfo) => {
      await agentV2.reset();
      await agentV2.seedWallet();
      let hasAddedFollowups = false;
      await page.route('**/api/v2/runs', async (route) => {
        if (hasAddedFollowups) {
          await route.continue();
          return;
        }
        hasAddedFollowups = true;
        const response = await route.fetch();
        const events = (await response.text()).trim().split('\n').map((line) => JSON.parse(line));
        const end = events.at(-1);
        events.splice(events.length - 1, 0, {
          protocolVersion: 3, type: 'followups', runId: end.runId, messageId: end.messageId,
          sequence: end.sequence, items: FOLLOWUPS,
        });
        end.sequence += 1;
        await route.fulfill({ response, body: `${events.map((event) => JSON.stringify(event)).join('\n')}\n` });
      });
      await agentV2.open();
      await agentV2.waitForList();
      await agentV2.send('A short answer');
      const buttons = page.locator('[data-agent-followup-id]');
      await expect(buttons).toHaveCount(3);
      // The follow-ups have come in and the list stands still
      await expect.poll(async () => {
        const frames = await recordFollowups(page, 200);
        return frames.every(({ followupOpacities }) => followupOpacities.every((opacity) => opacity === 1))
          && frames[0].scrollTop === frames.at(-1)!.scrollTop;
      }).toBe(true);
      const followupsTop = await buttons.first().evaluate((element) => element.getBoundingClientRect().top);
      const recording = recordQuestionInPlace(page, FOLLOWUPS[0].text);
      await page.getByRole('button', { name: FOLLOWUPS[0].text, exact: true }).click();
      const samples = await recording;
      await testInfo.attach('followup-in-place.json', {
        body: JSON.stringify({ followupsTop, samples }, undefined, 2), contentType: 'application/json',
      });
      const frames = samples.filter((sample, index) => {
        const next = samples[index + 1];
        return !next || next.time - sample.time >= SAME_FRAME_MS;
      });
      const shownIndex = frames.findIndex(({ question }) => question);
      expect(shownIndex, JSON.stringify(frames)).toBeGreaterThanOrEqual(0);
      const shown = frames[shownIndex];
      const scrollIndex = frames.findIndex((frame, index) => (
        index > shownIndex && Math.abs(frame.scrollTop - shown.scrollTop) > 1
      ));
      expect(scrollIndex, JSON.stringify(frames)).toBeGreaterThan(shownIndex);
      // The question's bubble waits under the suggestion turning into it while the list stands still and the
      // follow-ups give their space back, and settles on screen where they were
      const inPlace = frames.slice(shownIndex, scrollIndex);
      const settled = inPlace.at(-1)!;
      expect(inPlace.some(({ question }) => question!.opacity < 0.9), JSON.stringify(frames)).toBe(true);
      expect(settled.question!.top, JSON.stringify(frames)).toBeGreaterThanOrEqual(settled.visibleTop - 1);
      expect(settled.question!.bottom, JSON.stringify(frames)).toBeLessThanOrEqual(settled.visibleBottom + 1);
      expect(Math.abs(settled.question!.top - followupsTop), JSON.stringify(frames))
        .toBeLessThanOrEqual(QUESTION_IN_PLACE_TOLERANCE_PX);
      // A loaded machine draws frames late, which shifts where the appearance is seen by up to the longest frame gap
      const longestFrameGap = Math.max(...frames.slice(1).map(({ time }, index) => time - frames[index].time));
      expect(frames[scrollIndex].time - shown.time, JSON.stringify(frames))
        .toBeGreaterThanOrEqual(QUESTION_IN_PLACE_MS - longestFrameGap);
      // Then the list takes it up
      const last = frames.at(-1)!;
      expect(last.scrollTop - shown.scrollTop, JSON.stringify(frames)).toBeGreaterThan(40);
      expect(last.question!.top, JSON.stringify(frames)).toBeLessThan(settled.question!.top - 40);
    });

    test('flies a question sent from the field into its bubble before the list takes it up', async ({
      agentV2, page,
    }, testInfo) => {
      const firstFieldQuestion = 'And the first part?';
      const question = 'And the next part?';
      await agentV2.reset();
      await agentV2.seedWallet();
      await routeLongFirstAnswer(page);
      await agentV2.open();
      await agentV2.waitForList();
      await agentV2.send('A long answer');
      const answers = page.locator('[data-agent-v2-message-role="assistant"]');
      await expect(answers.last()).toHaveAttribute('data-agent-v2-message-status', 'complete');
      const field = page.getByRole('textbox', { name: 'Ask anything' });
      // The field sends the draft the chat holds, which takes the typed text a render later
      const sendButton = page.getByRole('button', { name: 'Send', exact: true });
      await expect(field).toBeEnabled();
      // The chat that the chat list opened has its question under the header and its first answer running on under the
      // field, so the next question lands under the field and comes up with the list, as on iOS, its text flying out of
      // the field into it as the list brings it up, as Telegram's send does. The one after it lands on screen, under
      // the answer to the question the list took up. A question sent while the answer is still typing out would land
      // on screen under its first lines instead.
      await waitForLastAnswerTyped(page);
      await field.fill(firstFieldQuestion);
      await expect(sendButton).toBeEnabled();
      const pinnedStatesRecording = recordFlightStates(page, firstFieldQuestion);
      const pinnedRecording = recordQuestionFlight(page, firstFieldQuestion);
      await field.press('Enter');
      const [pinnedSamples, pinnedStates] = await Promise.all([pinnedRecording, pinnedStatesRecording]);
      await testInfo.attach('pinned-question-flight.json', {
        body: JSON.stringify({ frames: pinnedSamples, states: pinnedStates }, undefined, 2),
        contentType: 'application/json',
      });
      // The bubble stays out of sight under the flight, which leaves the field and goes up after it as the list moves.
      // The text only ever rises out of the field, waiting in it while the list brings the bubble up from under it.
      for (const sample of pinnedSamples.filter(({ flight }) => flight)) {
        expect(sample.bubble?.opacity ?? 0, JSON.stringify(sample)).toBe(0);
      }
      const { first: pinnedFirst, landing: pinnedLanding } = assertFlightStates(pinnedStates);
      expect(new Set(pinnedStates.map(({ scrollTop }) => scrollTop)).size, JSON.stringify(pinnedStates))
        .toBeGreaterThan(1);
      expect(pinnedLanding.top, JSON.stringify(pinnedStates)).toBeLessThan(pinnedFirst.top - 40);
      const pinnedLanded = pinnedSamples.at(-1)!;
      expect(pinnedLanded.flight, JSON.stringify(pinnedLanded)).toBeUndefined();
      expect(pinnedLanded.bubble?.opacity, JSON.stringify(pinnedLanded)).toBe(1);
      await expect(answers.filter({ hasText: `Deterministic response: ${firstFieldQuestion}` }))
        .toHaveAttribute('data-agent-v2-message-status', 'complete');
      await expect(field).toBeEnabled();
      // The list stands still under the answer, typed out whole
      await expect.poll(async () => {
        const frames = await recordFollowups(page, 200);
        return frames[0].scrollTop === frames.at(-1)!.scrollTop;
      }).toBe(true);
      await waitForLastAnswerTyped(page);
      await field.fill(question);
      await expect(sendButton).toBeEnabled();
      const statesRecording = recordFlightStates(page, question);
      const recording = recordQuestionFlight(page, question);
      await field.press('Enter');
      const [samples, states] = await Promise.all([recording, statesRecording]);
      await testInfo.attach('question-flight.json', {
        body: JSON.stringify({ frames: samples, states }, undefined, 2), contentType: 'application/json',
      });
      const frames = samples.filter((sample, index) => {
        const next = samples[index + 1];
        return !next || next.time - sample.time >= SAME_FRAME_MS;
      });
      const shownIndex = frames.findIndex(({ bubble }) => bubble);
      expect(shownIndex, JSON.stringify(frames)).toBeGreaterThanOrEqual(0);
      const shown = frames[shownIndex];
      // The field empties as the bubble shows, out of sight under the flight
      expect(shown.fieldValue, JSON.stringify(shown)).toBe('');
      expect(shown.bubble!.opacity, JSON.stringify(shown)).toBe(0);
      expect(shown.bubble!.transform, JSON.stringify(shown)).toBe('none');
      expect(shown.picture?.isVisible, JSON.stringify(shown)).toBe(true);
      // The text leaves the field as the bubble's background starts out of the field's box, still to come in. The
      // picture of the text flies up onto the bubble's text as it fades, and the background lands on the bubble, which
      // stands whole by then, with the list still where it was.
      const { first, landing } = assertFlightStates(states);
      expect(first.appearance, JSON.stringify(first)).toBe(0);
      expect(first.top, JSON.stringify(first)).toBeGreaterThan(first.bubble!.top + 20);
      expect(landing.fieldTextTop, JSON.stringify(states)).toBeLessThan(first.fieldTextTop - 20);
      expect(Math.abs(landing.top - landing.bubble!.top), JSON.stringify(states))
        .toBeLessThan(FLIGHT_LANDING_TOLERANCE_PX);
      expect(landing.bubble, JSON.stringify(landing)).toMatchObject({ opacity: 1, transform: 'none' });
      for (const state of states) {
        expect(Math.abs(state.scrollTop! - first.scrollTop!), JSON.stringify(states)).toBeLessThanOrEqual(1);
      }
      const scrollIndex = frames.findIndex((frame, index) => (
        index > shownIndex && Math.abs(frame.scrollTop - shown.scrollTop) > 1
      ));
      expect(scrollIndex, JSON.stringify(frames)).toBeGreaterThan(shownIndex);
      // A loaded machine draws frames late, which shifts where the flight is seen by up to the longest frame gap
      const longestFrameGap = Math.max(...frames.slice(1).map(({ time }, index) => time - frames[index].time));
      expect(frames[scrollIndex].time - shown.time, JSON.stringify(frames))
        .toBeGreaterThanOrEqual(QUESTION_FLIGHT_MS - longestFrameGap);
      // The flight has gone before the list takes the question up
      for (const frame of frames.slice(scrollIndex)) {
        expect(frame.flight, JSON.stringify(frame)).toBeUndefined();
        expect(frame.picture, JSON.stringify(frame)).toBeUndefined();
      }
      const last = frames.at(-1)!;
      expect(last.scrollTop - shown.scrollTop, JSON.stringify(frames)).toBeGreaterThan(40);
    });

    test('takes a question of a few lines up once, as the field shrinks back under it', async ({ agentV2, page }) => {
      const question = ['The first line', 'The second line', 'The third line', 'The fourth line'].join('\n');
      await agentV2.reset();
      await agentV2.seedWallet();
      await agentV2.open();
      await agentV2.waitForList();
      await agentV2.send('A short question');
      await expect(page.locator('[data-agent-v2-message-role="assistant"]').last())
        .toHaveAttribute('data-agent-v2-message-status', 'complete');
      await waitForLastAnswerTyped(page);
      const field = page.getByRole('textbox', { name: 'Ask anything' });
      await field.fill(question);
      await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
      const recording = recordQuestionFlight(page, question);
      await field.press('Enter');
      const tops = (await recording).flatMap(({ bubble }) => (bubble ? [bubble.top] : []));

      // The question shows where it lands and the list then takes it up under the header: it never goes back down, as
      // when the field shrinking back took the list to its end first, and the list's own scroll came back from there
      expect(tops.length, JSON.stringify(tops)).toBeGreaterThan(0);
      tops.forEach((top, index) => {
        if (index) expect(top, JSON.stringify(tops)).toBeLessThanOrEqual(tops[index - 1] + 1);
      });
      expect(tops.at(-1)!, JSON.stringify(tops)).toBeLessThan(tops[0] - 40);
    });

    test('shows a question of more than ten lines without the flight, as Telegram does', async ({ agentV2, page }) => {
      const question = Array.from({ length: 11 }, (_, index) => `Line ${index + 1}`).join('\n');
      await agentV2.reset();
      await agentV2.seedWallet();
      await agentV2.open();
      await agentV2.waitForList();
      await agentV2.send('A short question');
      await expect(page.locator('[data-agent-v2-message-role="assistant"]').last())
        .toHaveAttribute('data-agent-v2-message-status', 'complete');
      await waitForLastAnswerTyped(page);
      const field = page.getByRole('textbox', { name: 'Ask anything' });
      await field.fill(question);
      await expect(page.getByRole('button', { name: 'Send', exact: true })).toBeEnabled();
      // The field grows to show all of them, as it can grow up to near the header, as on iOS and Android
      await expect.poll(() => field.evaluate((input) => input.scrollHeight - input.clientHeight))
        .toBeLessThanOrEqual(1);
      const recording = recordQuestionFlight(page, question);
      await field.press('Enter');
      const samples = await recording;

      // The field's text leaves it at once and nothing flies: the bubble fades in and grows as the list brings it up,
      // as Android's row opens
      expect(samples.some(({ bubble }) => bubble), JSON.stringify(samples)).toBe(true);
      for (const sample of samples) {
        expect(sample.flight, JSON.stringify(sample)).toBeUndefined();
        expect(sample.picture?.isVisible ?? false, JSON.stringify(sample)).toBe(false);
      }
      expect(samples.some(({ bubble }) => bubble && bubble.opacity > 0 && bubble.opacity < 1), JSON.stringify(samples))
        .toBe(true);
      expect(samples.at(-1)!.bubble?.opacity, JSON.stringify(samples.at(-1))).toBe(1);
    });

    test('takes an answer\'s tail into its corner as its followups come and grows it back as they go', async ({
      agentV2, page,
    }, testInfo) => {
      await agentV2.reset();
      await agentV2.seedWallet();
      let hasAddedFollowups = false;
      let releaseRun!: () => void;
      const runMayFinish = new Promise<void>((resolve) => {
        releaseRun = resolve;
      });
      let markRunReady!: () => void;
      const runReady = new Promise<void>((resolve) => {
        markRunReady = resolve;
      });
      await page.route('**/api/v2/runs', async (route) => {
        if (hasAddedFollowups) {
          await route.continue();
          return;
        }
        hasAddedFollowups = true;
        const response = await route.fetch();
        const events = (await response.text()).trim().split('\n').map((line) => JSON.parse(line));
        const end = events.at(-1);
        events.splice(events.length - 1, 0, {
          protocolVersion: 3, type: 'followups', runId: end.runId, messageId: end.messageId,
          sequence: end.sequence, items: FOLLOWUPS,
        });
        end.sequence += 1;
        markRunReady();
        await runMayFinish;
        await route.fulfill({ response, body: `${events.map((event) => JSON.stringify(event)).join('\n')}\n` });
      });
      await agentV2.open();
      await agentV2.waitForList();
      await agentV2.send('A short answer');
      await runReady;
      const awayRecording = recordTail(page, 2500);
      releaseRun();
      const away = (await awayRecording).filter(({ tail }) => tail);
      await testInfo.attach('tail-away.json', {
        body: JSON.stringify(away, undefined, 2), contentType: 'application/json',
      });
      // The tail stays while the answer's text comes, and goes into its corner as the followups come in, over their
      // reveal, its corner rounding meanwhile, rather than at once
      const comingIndex = away.findIndex(({ followupCount }) => followupCount > 0);
      expect(comingIndex, JSON.stringify(away)).toBeGreaterThan(0);
      expect(away[comingIndex - 1].tail!.opacity, JSON.stringify(away)).toBe(1);
      const going = away.slice(comingIndex);
      expect(going.filter(({ tail }) => tail!.opacity > 0.05 && tail!.opacity < 0.95).length, JSON.stringify(going))
        .toBeGreaterThanOrEqual(2);
      const goneIndex = going.findIndex(({ tail }) => tail!.opacity === 0);
      expect(goneIndex, JSON.stringify(going)).toBeGreaterThan(0);
      const longestFrameGap = Math.max(...going.slice(1).map(({ time }, index) => time - going[index].time));
      expect(going[goneIndex].time - going[0].time, JSON.stringify(going))
        .toBeGreaterThanOrEqual(TAIL_AWAY_MS - 2 * longestFrameGap);
      expect(going.some(({ cornerRadius }) => cornerRadius > 0.5 && cornerRadius < going.at(-1)!.cornerRadius - 0.5))
        .toBe(true);
      expect(going.at(-1)!.tail!.transform, JSON.stringify(going)).not.toBe('none');

      // A tapped followup takes the followups away, and the tail grows back out of its corner on its spring
      const answerId = going.at(-1)!.messageId;
      const backRecording = recordTail(page, TAIL_BACK_MAX_RECORDING_MS, answerId, true);
      await page.getByRole('button', { name: FOLLOWUPS[0].text, exact: true }).click();
      const back = (await backRecording).filter(({ tail }) => tail);
      await testInfo.attach('tail-back.json', {
        body: JSON.stringify(back, undefined, 2), contentType: 'application/json',
      });
      // The tail's own transitions, each started once, take the spring's time and end within it after the followups
      // go
      const tailTransitions = new Map(back.flatMap((frame) => frame.tailTransitions).map((transition) => (
        [`${transition.property}@${transition.startTime}`, transition] as const
      )));
      for (const property of ['transform', 'opacity']) {
        const started = Array.from(tailTransitions.values()).filter((transition) => transition.property === property);
        expect(started, JSON.stringify(back)).toHaveLength(1);
        expect(started[0].duration, JSON.stringify(started)).toBe(TAIL_SPRING_MS);
        expect(started[0].delay + started[0].duration, JSON.stringify(started)).toBeLessThanOrEqual(TAIL_BACK_MS);
      }
      // The tail is seen growing on them, in however few frames a busy runner draws meanwhile
      const growing = back.filter((frame) => frame.tailTransitions.some(({ delay, duration, currentTime }) => (
        currentTime > delay && currentTime < delay + duration
      )));
      expect(growing.length, JSON.stringify(back)).toBeGreaterThanOrEqual(1);
      // And the tail is seen whole by then, within a frame drawn late on a loaded machine
      const backIndex = back.findIndex(({ tail }) => tail!.opacity === 1 && tail!.transform === 'none');
      const backFrameGap = Math.max(...back.slice(1).map(({ time }, index) => time - back[index].time));
      expect(back[backIndex].time - growing[0].time, JSON.stringify(back))
        .toBeLessThanOrEqual(TAIL_BACK_MS + backFrameGap);
      expect(back.at(-1)!.tail, JSON.stringify(back)).toEqual({ opacity: 1, transform: 'none' });
      expect(back.at(-1)!.cornerRadius, JSON.stringify(back)).toBe(0);
    });

    test('flies a question typed under the chat list into the first bubble of the chat it opens', async ({
      agentV2, page,
    }, testInfo) => {
      const question = 'What does staking pay?';
      await agentV2.reset();
      await agentV2.seedWallet();
      // The Agent thinks over the question until the recording ends
      let releaseRun!: () => void;
      const runMayFinish = new Promise<void>((resolve) => {
        releaseRun = resolve;
      });
      await page.route('**/api/v2/runs', async (route) => {
        await runMayFinish;
        await route.continue();
      });
      await agentV2.open();
      await agentV2.waitForList();
      await page.getByRole('textbox', { name: 'Ask anything' }).fill(question);
      const statesRecording = recordFlightStates(page, question);
      const recording = recordOpeningFlight(page, question);
      await page.getByRole('button', { name: 'Send', exact: true }).click();
      const [frames, states] = await Promise.all([recording, statesRecording]);
      releaseRun();
      await testInfo.attach('opening-flight.json', {
        body: JSON.stringify({ frames, states }, undefined, 2), contentType: 'application/json',
      });
      // The bubble stays out of sight under the flight, over both screens, whose bubble grows out of the field where
      // the text stood, while the text itself goes up into it, as a question sent in a chat does
      for (const frame of frames.filter(({ flight }) => flight)) {
        expect(frame.bubble?.opacity ?? 0, JSON.stringify(frame)).toBe(0);
      }
      const { first, landing } = assertFlightStates(states);
      const settled = frames.at(-1)!;
      expect(settled.hasLayer, JSON.stringify(settled)).toBe(false);
      expect(settled.bubble?.opacity, JSON.stringify(settled)).toBe(1);
      // The question stands at the top, under the header and the date line that opens the chat, as on iOS, with the
      // Agent's thinking row under it, clear of the field
      expect(settled.bubble!.top - settled.visibleTop!, JSON.stringify(settled)).toBeGreaterThanOrEqual(-1);
      expect(settled.bubble!.top - settled.visibleTop!, JSON.stringify(settled))
        .toBeLessThan(OPENING_QUESTION_MAX_OFFSET_PX);
      expect(settled.activity, JSON.stringify(settled)).toBeDefined();
      expect(settled.activity!.top, JSON.stringify(settled)).toBeGreaterThanOrEqual(settled.bubble!.bottom - 1);
      expect(settled.activity!.bottom, JSON.stringify(settled)).toBeLessThanOrEqual(settled.composerTop! + 1);
      // The flight leaves the field, far under where the question stands, and comes up to it with the text
      expect(first.top, JSON.stringify(first)).toBeGreaterThan(settled.bubble!.top + 100);
      expect(first.isFieldTextVisible, JSON.stringify(first)).toBe(true);
      expect(landing.fieldTextTop, JSON.stringify(states)).toBeLessThan(first.fieldTextTop - 100);
      // The bubble may still move with the screen after the flight ends, so the flight lands on it as it stood then
      expect(landing.bubble, JSON.stringify(landing)).toBeDefined();
      expect(Math.abs(landing.top - landing.bubble!.top), JSON.stringify(states))
        .toBeLessThan(FLIGHT_LANDING_TOLERANCE_PX);
      // The question lands as the chat arrives, not before
      expect(landing.screenOpacity, JSON.stringify(landing)).toBeGreaterThan(0.95);
      expect(first.screenOpacity, JSON.stringify(first)).toBeLessThan(0.95);
    });

    for (const isHintTapped of [false, true]) {
      const name = isHintTapped
        ? 'turns a tapped hint of an empty chat into its first question, the others rippling away, nothing jumping'
        : 'lets an empty chat\'s hints leave where they stand as its first question goes, nothing jumping';
      test(name, async ({ agentV2, page }, testInfo) => {
        await agentV2.reset();
        await agentV2.seedWallet();
        await routeEmptyThread(page);
        await agentV2.open();
        await agentV2.waitForList();
        await agentV2.openThread();
        const hintButtons = page.locator('[data-agent-conversation] [data-agent-hints] button');
        await expect(hintButtons.nth(1)).toBeVisible();
        // The hints have come in and stand still
        await expect.poll(async () => {
          const frames = await recordEmptyChatSend(page, 300);
          return frames.every(({ hints }) => hints?.opacity === 1 && hints.top === frames[0].hints!.top);
        }).toBe(true);
        const recording = recordEmptyChatSend(page, 1500);
        await expect(page.locator('body')).toHaveAttribute('data-agent-recording', 'started');
        if (isHintTapped) {
          await hintButtons.nth(1).click();
        } else {
          const field = page.getByRole('textbox', { name: 'Ask anything' });
          await field.fill('What is staking?');
          await field.press('Enter');
        }
        const frames = await recording;
        await testInfo.attach('empty-chat-send.json', {
          body: JSON.stringify(frames, undefined, 2), contentType: 'application/json',
        });

        const shownIndex = frames.findIndex(({ bubble }) => bubble);
        expect(shownIndex, JSON.stringify(frames)).toBeGreaterThan(0);
        const shown = frames[shownIndex];
        // The question stands at the top at once, and the list does not move
        for (const frame of frames.slice(shownIndex)) {
          expect(Math.abs(frame.bubble!.top - shown.bubble!.top), JSON.stringify(frame)).toBeLessThanOrEqual(1);
          expect(frame.scrollTop, JSON.stringify(frame)).toBe(shown.scrollTop);
        }
        // The hints fade where they stood, only sliding down a little, and go: their box holds still, neither pushed by
        // the question nor taking its place, and only their own slide takes them down, as far as it goes and never back
        const withHints = frames.filter(({ hints }) => hints);
        const standingTop = withHints[0].hints!.top;
        withHints.forEach(({ hints }, index) => {
          expect(Math.abs(hints!.top - hints!.slide - standingTop), JSON.stringify(hints))
            .toBeLessThanOrEqual(STILL_TOLERANCE_PX);
          expect(hints!.slide, JSON.stringify(hints)).toBeLessThanOrEqual(HINTS_LEAVE_SLIDE_PX);
          if (!index) return;
          expect(hints!.slide, JSON.stringify(hints)).toBeGreaterThanOrEqual(withHints[index - 1].hints!.slide);
        });
        // They fade and slide on transitions of their own, which go on between the frames a busy runner draws
        const hintsTransitions = frames.slice(shownIndex).flatMap((frame) => frame.hintsTransitions);
        for (const property of ['opacity', 'transform']) {
          const started = hintsTransitions.filter((transition) => transition.property === property);
          expect(started, JSON.stringify(hintsTransitions)).toHaveLength(1);
          expect(started[0].duration, JSON.stringify(started)).toBe(HINTS_LEAVE_MS);
        }
        expect(frames.at(-1)!.hints, JSON.stringify(frames.at(-1))).toBeUndefined();
        // The run's activity comes up under the question, clear of the hints as they fade
        for (const { hints, activity } of frames) {
          if (!hints || !activity || hints.opacity < 0.05 || activity.opacity < 0.05) continue;
          expect(activity.bottom <= hints.top || activity.top >= hints.bottom, JSON.stringify({ hints, activity }))
            .toBe(true);
        }
        if (isHintTapped) {
          // The tapped hint turns into the question from the frame it shows, and never comes back
          expect(frames.some(({ hasMorph }) => hasMorph), JSON.stringify(frames)).toBe(true);
          for (const { hints } of frames.slice(shownIndex)) {
            if (hints) expect(hints.buttons[1], JSON.stringify(hints)).toEqual({ isVisible: false });
          }
          // The others ripple away at the tap
          const tapIndex = frames.findIndex(({ hints }) => hints?.buttons.some(({ isVisible }) => !isVisible));
          expect(tapIndex, JSON.stringify(frames)).toBeGreaterThan(0);
          expect(tapIndex, JSON.stringify(frames)).toBeLessThanOrEqual(shownIndex);
        } else {
          expect(frames.some(({ hasFlight }) => hasFlight), JSON.stringify(frames)).toBe(true);
        }
      });
    }

    test('draws the thinking glow over the header, as far as its corners', async ({ agentV2, page }) => {
      await agentV2.reset();
      await agentV2.seedWallet();
      let releaseRun!: () => void;
      const runMayFinish = new Promise<void>((resolve) => {
        releaseRun = resolve;
      });
      await page.route('**/api/v2/runs', async (route) => {
        await runMayFinish;
        await route.continue();
      });
      await agentV2.open();
      await agentV2.waitForList();
      await agentV2.send('A short answer');
      const glow = page.locator('[data-agent-conversation] [class*="AgentEdgeGlow"][class*="__root__"]');
      await expect(glow).toBeAttached();
      const layout = await glow.evaluate((element) => {
        const header = element.parentElement!.querySelector<HTMLElement>('[data-agent-header]')!;
        const glowRect = element.getBoundingClientRect();
        const headerRect = header.getBoundingClientRect();
        return {
          isBesideHeader: header.parentElement === element.parentElement,
          glowZIndex: Number(getComputedStyle(element).zIndex),
          headerZIndex: Number(getComputedStyle(header).zIndex),
          pointerEvents: getComputedStyle(element).pointerEvents,
          glow: { top: glowRect.top, left: glowRect.left, right: glowRect.right },
          header: { top: headerRect.top, left: headerRect.left, right: headerRect.right },
        };
      });
      releaseRun();
      // Nothing at the top of the chat lies over the glow: it is drawn above the header, across its whole width
      expect(layout.isBesideHeader).toBe(true);
      expect(layout.glowZIndex).toBeGreaterThan(layout.headerZIndex);
      expect(layout.pointerEvents).toBe('none');
      expect(layout.glow.top).toBeLessThanOrEqual(layout.header.top);
      expect(layout.glow.left).toBeLessThanOrEqual(layout.header.left);
      expect(layout.glow.right).toBeGreaterThanOrEqual(layout.header.right);
    });

    test('shows history followups immediately with reduced motion', async ({ agentV2, page }) => {
      await page.emulateMedia({ reducedMotion: 'reduce' });
      await agentV2.reset();
      await agentV2.seedWallet();
      const releaseHistory = await delayStoredHistory(page, 'newsOnly');
      await agentV2.open();
      await agentV2.waitForList();
      await agentV2.openThread();
      releaseHistory();
      const buttons = page.locator('[data-agent-followup-id]');
      await expect(buttons).toHaveCount(3);
      const frames = await recordFollowups(page, 300);
      expect(frames.every(({ followupOpacities }) => followupOpacities.every((opacity) => opacity === 1))).toBe(true);
      expect(frames.every(({ followupStates }) => followupStates.every(({ blur, rise }) => !blur && !rise))).toBe(true);
      expect(await buttons.evaluateAll((elements) => elements.some((element) => element.getAnimations().length > 0)))
        .toBe(false);
    });

    test('flies over sliding screens while staying below the header and composer', async ({
      agentV2, page,
    }, testInfo) => {
      const errors: string[] = [];
      page.on('pageerror', (error) => errors.push(error.message));
      await agentV2.reset('news-post');
      await agentV2.seedWallet();
      await page.route('**/api/v2/news-feed?*', async (route) => {
        const response = await route.fetch();
        const feed = await response.json();
        feed.items[0].body = 'Full news context for the discussion. '.repeat(75);
        await route.fulfill({ response, json: feed });
      });
      let releaseCreation!: () => void;
      const creationMayFinish = new Promise<void>((resolve) => {
        releaseCreation = resolve;
      });
      await page.route('**/api/v2/threads', async (route) => {
        if (route.request().method() === 'POST') await creationMayFinish;
        await route.continue();
      });
      await agentV2.open();
      await agentV2.waitForList();
      await page.getByRole('button', { name: /^News,/u }).click();
      const discuss = page.getByRole('button', {
        name: 'Discuss, Deterministic MyPulse headline', exact: true,
      });
      await expect(discuss).toBeVisible();
      await discuss.scrollIntoViewIfNeeded();
      const recording = recordNewsFlight(page);
      await discuss.click();
      const frames = await recording;
      releaseCreation();
      const framesPath = testInfo.outputPath('flight-frames.json');
      await writeFile(framesPath, JSON.stringify(frames, undefined, 2));
      await testInfo.attach('flight-frames.json', { path: framesPath, contentType: 'application/json' });
      expect(frames.length).toBeGreaterThanOrEqual(8);
      expect(frames.some(({ hasSlidingAncestor }) => hasSlidingAncestor)).toBe(true);
      expect(frames.some(({ frame, composerTop }) => composerTop !== undefined && frame.bottom > composerTop))
        .toBe(true);
      for (const sample of frames) {
        expect(sample.isBodyChild, JSON.stringify(sample)).toBe(true);
        expect(sample.position, JSON.stringify(sample)).toBe('fixed');
        expect(sample.clipTop, JSON.stringify(sample)).toBeGreaterThanOrEqual(sample.headerBottom - 1);
        if (sample.composerTop !== undefined) {
          expect(sample.clipBottom, JSON.stringify(sample)).toBeLessThanOrEqual(sample.composerTop + 1);
        }
        expect(sample.isAboveScreen, JSON.stringify(sample)).toBe(true);
        // The card keeps its tail and the square corner it grows from as it flies and lands, as the post has them
        expect(sample.hasTail, JSON.stringify(sample)).toBe(true);
        expect(sample.tailCornerRadius, JSON.stringify(sample)).toBe('0px');
      }
      await expect(page.locator(FLIGHT_SELECTOR)).toHaveCount(0);
      await expect(page.locator('[data-agent-news-post-event-id="5"]')).toBeVisible();
      expect(errors).toEqual([]);
      await page.screenshot({ path: testInfo.outputPath('landed.png') });
    });

    test('shows the news picture on every frame as the card flies into its discussion', async ({ agentV2, page }) => {
      await agentV2.reset('news-post');
      await agentV2.seedWallet();
      await page.route('**/api/v2/news-feed?*', async (route) => {
        const response = await route.fetch();
        const feed = await response.json();
        feed.items[0].imageUrl = FEED_PICTURE_PATH;
        await route.fulfill({ response, json: feed });
      });
      // The thread is created while the card flies, and its card names the picture by another address
      await page.route('**/api/v2/threads', async (route) => {
        if (route.request().method() !== 'POST') {
          await route.continue();
          return;
        }
        await new Promise((resolve) => setTimeout(resolve, THREAD_CREATION_DELAY_MS));
        await fulfillWithThreadPicture(route);
      });
      await page.route('**/api/v2/threads/*/messages*', fulfillWithThreadPicture);
      let shouldDelayPicture = false;
      await page.route((url) => url.pathname === PICTURE_PATHNAME, async (route) => {
        if (shouldDelayPicture) await new Promise((resolve) => setTimeout(resolve, PICTURE_RELOAD_DELAY_MS));
        await route.continue();
      });
      await agentV2.open();
      await agentV2.waitForList();
      await page.getByRole('button', { name: /^News,/u }).click();
      const discuss = page.getByRole('button', {
        name: 'Discuss, Deterministic MyPulse headline', exact: true,
      });
      await discuss.scrollIntoViewIfNeeded();
      await expect.poll(() => page.locator('[data-agent-news-event-id="5"] img').evaluate((image: HTMLImageElement) => (
        image.complete && image.naturalWidth > 0
      ))).toBe(true);
      // Chromium drops the pictures it keeps for new `img` elements as its cache is turned off
      const session = await page.context().newCDPSession(page);
      await session.send('Network.setCacheDisabled', { cacheDisabled: true });
      shouldDelayPicture = true;

      const recording = recordNewsPicture(page);
      await discuss.click();
      const frames = await recording;

      expect(frames.some(({ shownBy }) => shownBy === 'flight'), JSON.stringify(frames)).toBe(true);
      expect(frames.at(-1)!.shownBy, JSON.stringify(frames)).toBe('post');
      for (const frame of frames) {
        expect(frame.pictures.length, JSON.stringify(frame)).toBeGreaterThan(0);
        for (const picture of frame.pictures) {
          expect(picture.isShown, JSON.stringify(frame)).toBe(true);
          // The flight's copies draw the picture, and the card and the post show it from the feed's address
          if (frame.shownBy !== 'flight') expect(picture.url, JSON.stringify(frame)).toBe(FEED_PICTURE_PATH);
        }
      }
    });

    test('keeps the questions that wait in place as another is queued, the answer comes and the next one goes', async ({
      agentV2, page,
    }, testInfo) => {
      test.setTimeout(120_000);
      await agentV2.reset();
      await agentV2.seedWallet();
      // Each run waits for the test while the Agent thinks, then streams: the answer's message starts, its text comes
      // in a later chunk, and the run ends soon after, while the answer still appears
      const heldRuns: (() => void)[] = [];
      await page.route('**/api/v2/runs', async (route) => {
        await new Promise<void>((resolve) => {
          heldRuns.push(resolve);
        });
        await route.continue();
      });
      let releasedRunCount = 0;
      const releaseRun = async () => {
        await expect.poll(() => heldRuns.length).toBeGreaterThan(releasedRunCount);
        heldRuns[releasedRunCount]();
        releasedRunCount += 1;
      };
      const input = page.locator('textarea[placeholder="Ask anything"]:visible');
      const send = page.getByRole('button', { name: 'Send', exact: true });
      const stop = page.getByRole('button', { name: 'Stop response', exact: true });
      const userMessage = page.locator('[data-agent-v2-message-role="user"]:visible');
      const activity = page.locator('[data-agent-conversation] [data-agent-run-activity]');
      await agentV2.open();
      await agentV2.waitForList();
      await agentV2.send(QUEUE_HISTORY_QUESTIONS[0]);
      await releaseRun();
      await expect(page.getByText(`Deterministic response: ${QUEUE_HISTORY_QUESTIONS[0]}`, { exact: true }))
        .toBeVisible();
      // The chat has some history above the questions, each pinned as it is sent
      for (const question of QUEUE_HISTORY_QUESTIONS.slice(1)) {
        await expect(stop).toHaveCount(0);
        await input.fill(question);
        await expect(send).toBeEnabled();
        await input.press('Enter');
        await releaseRun();
        await expect(page.getByText(`Deterministic response: ${question}`, { exact: true })).toBeVisible();
      }
      await expect(stop).toHaveCount(0);

      // The question sent next is pinned under the header while the Agent thinks
      await input.fill(QUEUE_PINNED_QUESTION);
      await expect(send).toBeEnabled();
      await input.press('Enter');
      await expect(activity.last()).toBeVisible();
      await waitForQueueListRest(page);

      // The questions wait under the activity, each queued as the others wait. The answer comes, the first of them
      // goes, and its own answer comes in turn.
      await startQueueRecording(page);
      for (const question of QUEUE_WAITING_QUESTIONS) {
        await input.fill(question);
        await expect(send).toBeEnabled();
        await input.press('Enter');
        await expect(userMessage.last()).toContainText(question);
      }
      await page.waitForTimeout(QUEUE_STEP_MS);
      await releaseRun();
      await expect(page.getByText(`Deterministic response: ${QUEUE_PINNED_QUESTION}`, { exact: true }))
        .toBeVisible();
      await page.waitForTimeout(QUEUE_STEP_MS);
      await releaseRun();
      await expect(page.getByText(`Deterministic response: ${QUEUE_WAITING_QUESTIONS[0]}`, { exact: true }))
        .toBeVisible();
      await page.waitForTimeout(QUEUE_STEP_MS);
      const recording = await finishQueueRecording(page);
      const framesPath = testInfo.outputPath('queue-frames.json');
      await writeFile(framesPath, JSON.stringify(recording, undefined, 2));
      await testInfo.attach('queue-frames.json', { path: framesPath, contentType: 'application/json' });

      const failures = findQueueMotionFailures(recording.frames);
      expect(failures.length, failures.slice(0, 40).join('\n')).toBe(0);
    });
  });
}

async function fulfillWithThreadPicture(route: Route) {
  const response = await route.fetch();
  const json = await response.json();
  if (json.thread?.news) json.thread.news.imageUrl = THREAD_PICTURE_PATH;
  await route.fulfill({ response, json });
}

// The first answer of the chat runs on longer than the screen
async function routeLongFirstAnswer(page: Page) {
  let isFirstRun = true;
  await page.route('**/api/v2/runs', async (route) => {
    if (!isFirstRun) {
      await route.continue();
      return;
    }
    isFirstRun = false;
    const response = await route.fetch();
    const events = (await response.text()).trim().split('\n').map((line) => JSON.parse(line));
    events.find(({ type }) => type === 'text_delta').delta = LONG_ANSWER;
    await route.fulfill({ response, body: `${events.map((event) => JSON.stringify(event)).join('\n')}\n` });
  });
}

// The last answer has typed out its whole text, which grows it no more, well after its message has ended
async function waitForLastAnswerTyped(page: Page) {
  await expect.poll(() => page.locator('[data-agent-conversation]').last().evaluate(async (host) => {
    const getAnswerHeight = () => Array.from(
      host.querySelectorAll<HTMLElement>('[data-agent-v2-message-role="assistant"]'),
    ).at(-1)?.offsetHeight;
    const height = getAnswerHeight();
    await new Promise((resolve) => setTimeout(resolve, 300));
    return height !== undefined && height === getAnswerHeight();
  }), { timeout: 10_000 }).toBe(true);
}

// The chat list shows the server's thread, whose history holds no message yet, as a chat cleared elsewhere, so the
// chat opens with the hints of an empty chat and its runs answer in it
async function routeEmptyThread(page: Page) {
  // One hint of each group, so that the pick shows them all
  await page.route('**/api/v2/hints/pool*', (route) => route.fulfill({
    json: {
      protocolVersion: 3,
      catalogVersion: 'agent-starter-hints-v2',
      items: [
        { id: 'agent.capabilities', group: 'learn' },
        { id: 'receive.tokens', group: 'wallet' },
        { id: 'market.today', group: 'market' },
        { id: 'action.swap', group: 'action' },
      ],
    },
  }));
  // The list leaves out a chat it counts no message in
  const thread = {
    id: SERVER_THREAD_ID,
    revision: 1,
    createdAt: CREATED_AT,
    updatedAt: CREATED_AT,
    lastActivityAt: CREATED_AT,
    messageCount: 1,
    title: 'Empty animation test chat',
  };
  await page.route('**/api/v2/threads?*', (route) => route.fulfill({
    json: { protocolVersion: 3, threads: [{ thread }] },
  }));
}

function measureComposerGap(page: Page, selector: string) {
  return page.locator('[data-agent-conversation]').last().evaluate((host, tailSelector) => {
    const composer = host.querySelector('[data-agent-composer]')!;
    const tail = Array.from(host.querySelectorAll(tailSelector)).at(-1)!;
    return composer.getBoundingClientRect().top - tail.getBoundingClientRect().bottom;
  }, selector);
}

function assertFollowupStagger(samples: { time: number; followupOpacities: number[] }[]) {
  // Each frame once, as its last sample read it
  const frames = samples.filter((sample, index) => {
    const next = samples[index + 1];
    return !next || next.time - sample.time >= SAME_FRAME_MS;
  });
  const firstVisible = FOLLOWUPS.map((_, index) => frames.findIndex((frame) => frame.followupOpacities[index] > 0.05));
  expect(firstVisible.every((index) => index >= 0), JSON.stringify(frames)).toBe(true);
  const windows = firstVisible.map((index) => ({
    from: frames[Math.max(0, index - 1)].time,
    to: frames[index].time,
  }));
  // A loaded machine draws frames late, which shifts where each appearance is seen by up to the longest frame gap
  const longestFrameGap = Math.max(...frames.slice(1).map(({ time }, index) => time - frames[index].time));
  for (let index = 1; index < windows.length; index++) {
    const previous = windows[index - 1];
    const current = windows[index];
    expect(current.to, JSON.stringify(windows)).toBeGreaterThan(previous.to);
    // Visibility starts between two captured frames, even when the browser skips a sampling frame
    expect(current.from - previous.to, JSON.stringify(windows))
      .toBeLessThanOrEqual(FOLLOWUP_STAGGER_MAX_MS + longestFrameGap);
    expect(current.to - previous.from, JSON.stringify(windows))
      .toBeGreaterThanOrEqual(FOLLOWUP_STAGGER_MIN_MS - longestFrameGap);
  }
  expect(frames.at(-1)!.followupOpacities).toEqual([1, 1, 1]);
}

// Each comes into focus out of a blur as it fades in and rises into place, as on iOS, and ends sharp and in place
function assertFollowupBlurIn(frames: { followupStates: { opacity: number; blur: number; rise: number }[] }[]) {
  FOLLOWUPS.forEach((_, index) => {
    const fading = frames.filter(({ followupStates }) => (
      followupStates[index] && followupStates[index].opacity > 0.05 && followupStates[index].opacity < 0.95
    ));
    expect(fading.length, JSON.stringify(frames)).toBeGreaterThan(0);
    for (const { followupStates } of fading) {
      expect(followupStates[index].blur, JSON.stringify(followupStates)).toBeGreaterThan(0);
      expect(followupStates[index].rise, JSON.stringify(followupStates)).toBeGreaterThan(0);
    }
  });
  expect(frames.at(-1)!.followupStates.map(({ blur, rise }) => [blur, rise])).toEqual(FOLLOWUPS.map(() => [0, 0]));
}

function recordFollowups(page: Page, duration = 1200, selector = '[data-agent-followup-id]') {
  return page.evaluate(async ({ milliseconds, selector: followupSelector }) => {
    const frames = [];
    const startedAt = performance.now();
    while (performance.now() - startedAt < milliseconds) {
      await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
      const host = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-conversation]')).at(-1);
      const followups = Array.from(host?.querySelectorAll(followupSelector) ?? []);
      const followupOpacities = followups.map((button) => {
        let opacity = 1;
        for (let element: Element | null = button; element; element = element.parentElement) {
          opacity *= Number(getComputedStyle(element).opacity);
        }
        return opacity;
      });
      // Each one's own opacity, and its blur and how far it is below its place, in pixels
      const followupStates = followups.map((button) => {
        const style = getComputedStyle(button);
        return {
          opacity: Number(style.opacity),
          blur: Number(/blur\(([\d.]+)px\)/u.exec(style.filter)?.[1] ?? 0),
          rise: new DOMMatrixReadOnly(style.transform).m42,
        };
      });
      frames.push({
        time: performance.now() - startedAt, followupOpacities, followupStates,
        scrollTop: host?.querySelector<HTMLElement>('.custom-scroll')?.scrollTop ?? 0,
      });
    }
    return frames;
  }, { milliseconds: duration, selector });
}

interface StreamedLetters {
  isComplete: boolean;
  letters: { offset: number; letter: string; left: number; right: number; top: number }[];
  copyColors: string[];
}

/**
 * The last answer's letters that the streamed text's highlights colour, or those at `offsets`, each with its offset in
 * `answerText` and where it stands in the answer's bubble, whether the bubble shows the whole of `answerText`, and the
 * colours of the copies over the text. The bubble holds the streaming text and then the settled one, each in text
 * nodes of their own, so the offsets run over its whole text.
 */
function measureStreamedLetters(page: Page, answerText: string, offsets?: number[]): Promise<StreamedLetters> {
  return page.evaluate(({ text, letterOffsets, bubbleSelector }) => {
    const answer = Array.from(document.querySelectorAll('[data-agent-v2-message-role="assistant"]')).at(-1);
    const bubble = answer?.querySelector(bubbleSelector);
    if (!bubble) return { isComplete: false, letters: [], copyColors: [] };

    const copyColors = Array.from(
      bubble.querySelectorAll('[data-agent-streaming-reveal-edge-text]'),
      (copy) => getComputedStyle(copy).color,
    );
    const nodes: { node: Text; start: number }[] = [];
    const walker = document.createTreeWalker(bubble, NodeFilter.SHOW_TEXT);
    let length = 0;
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      nodes.push({ node: node as Text, start: length });
      length += (node as Text).data.length;
    }
    const textStart = nodes.map(({ node }) => node.data).join('').indexOf(text);
    if (textStart < 0) return { isComplete: false, letters: [], copyColors };

    const coloredOffsets: number[] = [];
    if (!letterOffsets) {
      CSS.highlights.forEach((highlight, name) => {
        if (!name.startsWith('agent-streamed-text')) return;
        highlight.forEach((range) => {
          const entry = nodes.find(({ node }) => node === range.startContainer);
          if (!entry || range.endContainer !== entry.node) return;
          for (let offset = range.startOffset; offset < range.endOffset; offset++) {
            coloredOffsets.push(entry.start + offset - textStart);
          }
        });
      });
    }
    // Where the letters stand in the bubble, wherever the list has taken it meanwhile
    const origin = bubble.getBoundingClientRect();
    const range = document.createRange();
    const letters = (letterOffsets ?? coloredOffsets.sort((first, second) => first - second)).flatMap((offset) => {
      const textOffset = textStart + offset;
      const entry = nodes.filter(({ start }) => start <= textOffset).at(-1);
      if (!entry || textOffset - entry.start >= entry.node.data.length) return [];
      range.setStart(entry.node, textOffset - entry.start);
      range.setEnd(entry.node, textOffset - entry.start + 1);
      const { left, right, top } = range.getBoundingClientRect();
      return [{
        offset,
        letter: entry.node.data[textOffset - entry.start],
        left: left - origin.left,
        right: right - origin.left,
        top: top - origin.top,
      }];
    });

    return { isComplete: true, letters, copyColors };
  }, { text: answerText, letterOffsets: offsets, bubbleSelector: BUBBLE_SELECTOR });
}

function recordQuestionInPlace(page: Page, text: string) {
  return page.evaluate(async ({ bubbleSelector, questionText }) => {
    const frames = [];
    const startedAt = performance.now();
    while (performance.now() - startedAt < 1800) {
      await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
      const host = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-conversation]')).at(-1)!;
      const scroll = host.querySelector<HTMLElement>('.custom-scroll')!;
      const scrollRect = scroll.getBoundingClientRect();
      const scrollStyle = getComputedStyle(scroll);
      const bubble = Array.from(host.querySelectorAll<HTMLElement>('[data-agent-v2-message-role="user"]'))
        .find((message) => message.textContent?.includes(questionText))
        ?.querySelector<HTMLElement>(bubbleSelector);
      const rect = bubble?.getBoundingClientRect();
      frames.push({
        time: performance.now() - startedAt,
        scrollTop: scroll.scrollTop,
        visibleTop: scrollRect.top + Number.parseFloat(scrollStyle.paddingTop),
        visibleBottom: scrollRect.bottom - Number.parseFloat(scrollStyle.paddingBottom),
        question: bubble && rect
          ? { top: rect.top, bottom: rect.bottom, opacity: Number(getComputedStyle(bubble).opacity) }
          : undefined,
      });
    }
    return frames;
  }, { bubbleSelector: BUBBLE_SELECTOR, questionText: text });
}

function recordQuestionFlight(page: Page, text: string) {
  return page.evaluate(async ({ bubbleSelector, questionText }) => {
    const frames = [];
    const startedAt = performance.now();
    while (performance.now() - startedAt < 1800) {
      await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
      const host = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-conversation]')).at(-1)!;
      const scroll = host.querySelector<HTMLElement>('.custom-scroll')!;
      const bubble = Array.from(host.querySelectorAll<HTMLElement>('[data-agent-v2-message-role="user"]'))
        .find((message) => message.textContent?.includes(questionText))
        ?.querySelector<HTMLElement>(bubbleSelector);
      // The field's text, and the bubble's background flying out of the field
      const pictures = host.querySelectorAll<HTMLElement>('[class*="__motionLayer__"] [class*="__picture__"]');
      const picture = Array.from(pictures).find((element) => element.textContent === questionText);
      const flight = host.querySelector<HTMLElement>('[class*="__motionLayer__"] [class*="__flightBubble__"]');
      const bubbleStyle = bubble && getComputedStyle(bubble);
      const pictureStyle = picture && getComputedStyle(picture);
      frames.push({
        time: performance.now() - startedAt,
        scrollTop: scroll.scrollTop,
        fieldValue: host.querySelector('textarea')?.value,
        bubble: bubble && bubbleStyle ? {
          opacity: Number(bubbleStyle.opacity),
          transform: bubbleStyle.transform,
          top: bubble.getBoundingClientRect().top,
        } : undefined,
        flight: flight ? {
          opacity: Number(getComputedStyle(flight).opacity),
          top: flight.getBoundingClientRect().top,
        } : undefined,
        picture: picture && pictureStyle ? {
          isVisible: pictureStyle.visibility === 'visible',
          opacity: Number(pictureStyle.opacity),
          top: picture.getBoundingClientRect().top,
        } : undefined,
      });
    }
    return frames;
  }, { bubbleSelector: BUBBLE_SELECTOR, questionText: text });
}

interface FlightState {
  time: number;
  isFlying: boolean;
  /** The top of the flight's bubble background */
  top: number;
  /** How far the background has come in */
  appearance: number;
  fieldTextTop: number;
  isFieldTextVisible?: boolean;
  bubble?: { opacity: number; transform: string; top: number };
  scrollTop?: number;
  screenOpacity: number;
}

/**
 * Every state the flight of the question with `text` is put in, read as the flight sets it, until it ends. A busy runner
 * draws few of the flight's frames, while the states always have its first and its last.
 */
function recordFlightStates(page: Page, text: string) {
  return page.evaluate(({ questionText, bubbleSelector, maxDuration }) => new Promise<FlightState[]>((resolve) => {
    const states: FlightState[] = [];
    const startedAt = performance.now();
    // How far an element is moved down by the `translate` its style starts with
    const getShiftY = (element: HTMLElement) => Number(
      /^translate\([^,]+,\s*(-?[\d.]+(?:e[-+]?\d+)?)px\)/u.exec(element.style.transform)?.[1] ?? 0,
    );
    // The flight's parts as it starts, and where its layer and the field's text stand with no shift
    let flight: {
      layer: HTMLElement; background: HTMLElement; fieldText: HTMLElement; layerTop: number; fieldTextTop: number;
    } | undefined;

    const observer = new MutationObserver(() => {
      if (!flight) {
        const fieldText = Array.from(document.querySelectorAll<HTMLElement>('[class*="__picture__"]'))
          .find((element) => element.textContent === questionText);
        const background = fieldText?.parentElement?.querySelector<HTMLElement>(':scope > [class*="__flightBubble__"]');
        const layer = fieldText?.parentElement?.parentElement;
        if (!fieldText || !background || !layer) return;

        flight = {
          layer,
          background,
          fieldText,
          layerTop: layer.getBoundingClientRect().top,
          fieldTextTop: fieldText.getBoundingClientRect().top - getShiftY(fieldText),
        };
      }

      const { layer, background, fieldText, fieldTextTop } = flight;
      const isFlying = background.isConnected;
      if (layer.isConnected) flight.layerTop = layer.getBoundingClientRect().top;
      const host = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-conversation]')).at(-1);
      const bubble = Array.from(host?.querySelectorAll<HTMLElement>('[data-agent-v2-message-role="user"]') ?? [])
        .find((message) => message.textContent?.includes(questionText))
        ?.querySelector<HTMLElement>(bubbleSelector);
      const bubbleStyle = bubble && getComputedStyle(bubble);
      let screenOpacity = host ? 1 : 0;
      for (let element = host; element; element = element.parentElement ?? undefined) {
        screenOpacity *= Number(getComputedStyle(element).opacity);
      }
      states.push({
        time: performance.now() - startedAt,
        isFlying,
        top: flight.layerTop + getShiftY(background),
        appearance: Number(background.style.opacity || 1),
        fieldTextTop: fieldTextTop + getShiftY(fieldText),
        isFieldTextVisible: isFlying ? getComputedStyle(fieldText).visibility === 'visible' : undefined,
        bubble: bubble && bubbleStyle ? {
          opacity: Number(bubbleStyle.opacity),
          transform: bubbleStyle.transform,
          top: bubble.getBoundingClientRect().top,
        } : undefined,
        scrollTop: host?.querySelector<HTMLElement>('.custom-scroll')?.scrollTop,
        screenOpacity,
      });
      if (!isFlying) finish();
    });
    const timeout = window.setTimeout(finish, maxDuration);

    function finish() {
      observer.disconnect();
      window.clearTimeout(timeout);
      resolve(states);
    }

    observer.observe(document.body, { attributes: true, attributeFilter: ['style'], childList: true, subtree: true });
  }), { questionText: text, bubbleSelector: BUBBLE_SELECTOR, maxDuration: FLIGHT_MAX_RECORDING_MS });
}

/**
 * The flight has started and ended, with the bubble out of sight under it, and its background and the field's text
 * have only ever risen from where they started. Gives its first state and its last, where it lands.
 */
function assertFlightStates(states: FlightState[]) {
  expect(states.length, 'the flight has started').toBeGreaterThan(0);
  const [first] = states;
  const landing = states.at(-1)!;
  expect(first.isFlying, JSON.stringify(first)).toBe(true);
  expect(landing.isFlying, JSON.stringify(landing)).toBe(false);
  for (const state of states) {
    if (state.isFlying) expect(state.bubble?.opacity ?? 0, JSON.stringify(state)).toBe(0);
    expect(state.top, JSON.stringify(states)).toBeLessThanOrEqual(first.top + 1);
    expect(state.fieldTextTop, JSON.stringify(states)).toBeLessThanOrEqual(first.fieldTextTop + 1);
  }
  return { first, landing };
}

// The tail of an answer, the last one or the one with `messageId`, and the corner it goes into, for `duration`, or,
// `shouldEndWhole`, until the tail has rested whole after its transitions, for `duration` at most
function recordTail(page: Page, duration: number, messageId?: string, shouldEndWhole = false) {
  return page.evaluate(async ({
    milliseconds, id, bubbleSelector, isUntilWhole, wholeFrameCount,
  }) => {
    const frames = [];
    const startedAt = performance.now();
    let hasTransitioned = false;
    let wholeFrames = 0;
    while (performance.now() - startedAt < milliseconds) {
      await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
      const host = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-conversation]')).at(-1);
      const answers = Array.from(host?.querySelectorAll<HTMLElement>('[data-agent-v2-message-role="assistant"]') ?? []);
      const answer = id ? answers.find((element) => element.dataset.agentV2MessageId === id) : answers.at(-1);
      const bubble = answer?.querySelector<HTMLElement>(bubbleSelector);
      const tail = bubble && getComputedStyle(bubble, '::after');
      // The transitions of the tail under way, by when each started on the document's timeline
      const tailTransitions = (bubble?.getAnimations({ subtree: true }) ?? []).flatMap((animation) => {
        const { effect, startTime } = animation;
        if (!(animation instanceof CSSTransition) || !(effect instanceof KeyframeEffect)
          || effect.pseudoElement !== '::after' || typeof startTime !== 'number') return [];
        const { delay, duration } = effect.getTiming();
        return [{
          property: animation.transitionProperty,
          startTime: Number(startTime),
          delay: delay ?? 0,
          duration: Number(duration),
          currentTime: Number(animation.currentTime),
        }];
      });
      const tailState = tail ? { opacity: Number(tail.opacity), transform: tail.transform } : undefined;
      frames.push({
        time: performance.now() - startedAt,
        messageId: answer?.dataset.agentV2MessageId,
        followupCount: answer?.querySelectorAll('[data-agent-followup-id]').length ?? 0,
        tail: tailState,
        tailTransitions,
        cornerRadius: bubble ? Number.parseFloat(getComputedStyle(bubble).borderEndStartRadius) : 0,
      });
      hasTransitioned ||= tailTransitions.length > 0;
      const isWhole = hasTransitioned && !tailTransitions.length && tailState?.opacity === 1
        && tailState.transform === 'none';
      wholeFrames = isWhole ? wholeFrames + 1 : 0;
      if (isUntilWhole && wholeFrames >= wholeFrameCount) break;
    }
    return frames;
  }, {
    milliseconds: duration,
    id: messageId,
    bubbleSelector: BUBBLE_SELECTOR,
    isUntilWhole: shouldEndWhole,
    wholeFrameCount: TAIL_WHOLE_FRAME_COUNT,
  });
}

// The flight over the screens, and the bubble, the thinking row under it and the screen of the chat that opens with the
// question
// The opening flight in each frame the runner draws, until the chat has rested after it
function recordOpeningFlight(page: Page, text: string) {
  return page.evaluate(async ({
    questionText, bubbleSelector, settleDuration, maxDuration,
  }) => {
    const frames = [];
    const startedAt = performance.now();
    const getHost = () => Array.from(document.querySelectorAll<HTMLElement>('[data-agent-conversation]')).at(-1);
    const findBubble = (host?: HTMLElement) => Array.from(
      host?.querySelectorAll<HTMLElement>('[data-agent-v2-message-role="user"]') ?? [],
    ).find((message) => message.textContent?.includes(questionText))?.querySelector<HTMLElement>(bubbleSelector);
    const getScreenOpacity = (host?: HTMLElement) => {
      let opacity = host ? 1 : 0;
      for (let element = host; element; element = element.parentElement ?? undefined) {
        opacity *= Number(getComputedStyle(element).opacity);
      }
      return opacity;
    };
    let hasLayerShown = false;
    let landedAt: number | undefined;
    while (performance.now() - startedAt < maxDuration) {
      await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
      const time = performance.now() - startedAt;
      if (landedAt !== undefined && time - landedAt >= settleDuration) break;

      const layer = document.querySelector<HTMLElement>('[class*="__openingQuestionLayer__"]');
      hasLayerShown ||= Boolean(layer);
      if (hasLayerShown && !layer) landedAt ??= time;
      const flightBubble = layer?.querySelector<HTMLElement>('[class*="__flightBubble__"]');
      const fieldText = layer?.querySelector<HTMLElement>('[class*="__picture__"]');
      const host = getHost();
      const scroll = host?.querySelector<HTMLElement>('.custom-scroll');
      const bubble = findBubble(host);
      const bubbleRect = bubble?.getBoundingClientRect();
      const activityRect = host?.querySelector('[data-agent-run-activity]')?.getBoundingClientRect();
      frames.push({
        time,
        hasLayer: Boolean(layer),
        flight: flightBubble ? { top: flightBubble.getBoundingClientRect().top } : undefined,
        fieldText: fieldText ? {
          top: fieldText.getBoundingClientRect().top,
          isVisible: getComputedStyle(fieldText).visibility === 'visible',
        } : undefined,
        visibleTop: scroll
          ? scroll.getBoundingClientRect().top + Number.parseFloat(getComputedStyle(scroll).paddingTop)
          : undefined,
        bubble: bubble && bubbleRect ? {
          opacity: Number(getComputedStyle(bubble).opacity),
          top: bubbleRect.top,
          bottom: bubbleRect.bottom,
        } : undefined,
        activity: activityRect?.height ? { top: activityRect.top, bottom: activityRect.bottom } : undefined,
        composerTop: host?.querySelector('[data-agent-composer]')?.getBoundingClientRect().top,
        screenOpacity: getScreenOpacity(host),
      });
    }
    return frames;
  }, {
    questionText: text,
    bubbleSelector: BUBBLE_SELECTOR,
    settleDuration: OPENING_SETTLE_MS,
    maxDuration: FLIGHT_MAX_RECORDING_MS,
  });
}

// An empty chat's hints, its first question and the run's activity under it, and what comes out of the field or the
// tapped hint
function recordEmptyChatSend(page: Page, duration: number) {
  return page.evaluate(async ({ milliseconds, bubbleSelector }) => {
    const frames = [];
    const startedAt = performance.now();
    // The transitions the hints start, as each starts, though it may start and end between two frames drawn
    let hintsTransitions: { property: string; duration: number }[] = [];
    function handleTransitionRun({ target, propertyName }: TransitionEvent) {
      if (!(target instanceof HTMLElement) || !target.matches('[data-agent-hints]')) return;
      const transition = target.getAnimations().find((animation) => (
        animation instanceof CSSTransition && animation.transitionProperty === propertyName
      ));
      hintsTransitions.push({ property: propertyName, duration: Number(transition?.effect?.getTiming().duration) });
    }
    document.addEventListener('transitionrun', handleTransitionRun, true);
    while (performance.now() - startedAt < milliseconds) {
      await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
      const host = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-conversation]')).at(-1)!;
      const hints = host.querySelector<HTMLElement>('[data-agent-hints]');
      const hintsRect = hints?.getBoundingClientRect();
      const hintsStyle = hints && getComputedStyle(hints);
      const bubble = host.querySelector<HTMLElement>(`[data-agent-v2-message-role="user"] ${bubbleSelector}`);
      const activity = host.querySelector<HTMLElement>('[data-agent-run-activity]');
      const activityRect = activity?.getBoundingClientRect();
      let activityOpacity = 0;
      if (activity && activityRect?.height) {
        activityOpacity = 1;
        for (let element: HTMLElement | null = activity; element && element !== host; element = element.parentElement) {
          activityOpacity *= Number(getComputedStyle(element).opacity);
        }
      }
      frames.push({
        time: performance.now() - startedAt,
        scrollTop: host.querySelector<HTMLElement>('.custom-scroll')!.scrollTop,
        hints: hints && hintsRect && hintsStyle ? {
          top: hintsRect.top,
          bottom: hintsRect.bottom,
          // How far their own transform takes them down
          slide: hintsStyle.transform === 'none' ? 0 : new DOMMatrixReadOnly(hintsStyle.transform).m42,
          opacity: Number(hintsStyle.opacity),
          buttons: Array.from(hints.querySelectorAll('button'))
            .map((button) => ({ isVisible: getComputedStyle(button).visibility === 'visible' })),
        } : undefined,
        hintsTransitions,
        bubble: bubble ? { top: bubble.getBoundingClientRect().top } : undefined,
        activity: activity && activityRect?.height
          ? { top: activityRect.top, bottom: activityRect.bottom, opacity: activityOpacity }
          : undefined,
        hasFlight: Boolean(host.querySelector('[class*="__motionLayer__"] [class*="__flightBubble__"]')),
        hasMorph: Boolean(host.querySelector('[class*="__motionLayer__"] [class*="__followupMorph__"]')),
      });
      hintsTransitions = [];
      // The recording has the chat as it stands before the test acts on it
      document.body.dataset.agentRecording = 'started';
    }
    document.removeEventListener('transitionrun', handleTransitionRun, true);
    delete document.body.dataset.agentRecording;
    return frames;
  }, { milliseconds: duration, bubbleSelector: BUBBLE_SELECTOR });
}

function recordChatListCrossfade(page: Page, duration: number) {
  return page.evaluate(async (milliseconds) => {
    const frames = [];
    const startedAt = performance.now();
    while (performance.now() - startedAt < milliseconds) {
      await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
      const list = document.querySelector<HTMLElement>('[aria-label="Chats"]')!;
      const skeleton = list.querySelector<HTMLElement>('[role="status"]');
      const content = list.querySelector<HTMLElement>('.custom-scroll')!;
      const news = list.querySelector<HTMLElement>('[data-agent-news-row]');
      const contentOpacity = Number(getComputedStyle(content).opacity);
      let newsOpacity = 0;
      if (news) {
        newsOpacity = 1;
        for (let element: HTMLElement | null = news; element && element !== list; element = element.parentElement) {
          newsOpacity *= Number(getComputedStyle(element).opacity);
        }
      }
      frames.push({
        time: performance.now() - startedAt,
        newsCount: list.querySelectorAll('[data-agent-news-row]').length,
        threadCount: list.querySelectorAll('[data-agent-v2-thread-id]').length,
        skeletonRowCount: skeleton?.children.length ?? 0,
        skeletonOpacity: skeleton ? Number(getComputedStyle(skeleton).opacity) : 0,
        contentOpacity,
        newsOpacity,
        firstSkeletonTop: skeleton?.firstElementChild?.getBoundingClientRect().top,
        firstNewsTop: news?.getBoundingClientRect().top,
      });
    }
    return frames;
  }, duration);
}

function recordNewsFlight(page: Page) {
  return page.evaluate(async (flightSelector) => {
    const frames = [];
    const startedAt = performance.now();
    while (performance.now() - startedAt < 1600) {
      await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
      const root = document.querySelector<HTMLElement>(flightSelector);
      const movingFrame = root?.firstElementChild as HTMLElement | undefined;
      const cardFrame = root?.querySelector<HTMLElement>('[class*="__flightFrame__"]');
      const tail = root?.querySelector<HTMLElement>('[class*="__flightTail__"]');
      if (root && movingFrame && cardFrame) {
        const rect = movingFrame.getBoundingClientRect();
        const style = getComputedStyle(root);
        const rootRect = root.getBoundingClientRect();
        const insets = style.clipPath.match(/^inset\(([^)]+)\)/u)?.[1].split(/\s+/u).map(parseFloat) ?? [0];
        const topInset = insets[0];
        const bottomInset = insets[2] ?? topInset;
        const headers = Array.from(document.querySelectorAll<HTMLElement>(
          '[data-agent-header], [data-agent-header-accessory]',
        ))
          .map((header) => header.getBoundingClientRect())
          .filter((header) => header.right > rect.left && header.left < rect.right);
        const headerBottom = Math.max(0, ...headers.map((header) => header.bottom));
        const post = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-news-post-event-id="5"]'))
          .find((element) => !root.contains(element));
        const conversation = post?.closest<HTMLElement>('[data-agent-conversation]');
        const composer = conversation?.querySelector<HTMLElement>('[data-agent-composer]');
        const composerRect = composer?.getBoundingClientRect();
        const composerTop = composerRect && composerRect.left < Math.min(rect.right, innerWidth)
          && composerRect.right > Math.max(0, rect.left) ? composerRect.top : undefined;
        let hasSlidingAncestor = false;
        for (let ancestor = conversation; ancestor; ancestor = ancestor.parentElement ?? undefined) {
          hasSlidingAncestor ||= getComputedStyle(ancestor).transform !== 'none';
        }
        const clipTop = rootRect.top + topInset;
        const clipBottom = rootRect.bottom - bottomInset;
        const x = Math.max(1, Math.min(innerWidth - 1, rect.left + rect.width / 2));
        const y = (Math.max(rect.top, clipTop) + Math.min(rect.bottom, clipBottom)) / 2;
        const pointerEvents = root.style.pointerEvents;
        root.style.pointerEvents = 'auto';
        const hit = document.elementFromPoint(x, y);
        const isAboveScreen = Boolean(hit && hit !== root && root.contains(hit));
        root.style.pointerEvents = pointerEvents;
        frames.push({
          time: performance.now() - startedAt,
          isBodyChild: root.parentElement === document.body,
          position: style.position,
          clipPath: style.clipPath,
          clipTop,
          clipBottom,
          headerBottom,
          composerTop,
          mountedComposer: composerRect && {
            left: composerRect.left, right: composerRect.right, top: composerRect.top,
          },
          hasSlidingAncestor,
          isAboveScreen,
          tailCornerRadius: getComputedStyle(cardFrame).borderEndStartRadius,
          hasTail: Boolean(tail) && getComputedStyle(tail, '::after').content !== 'none',
          frame: { top: rect.top, bottom: rect.bottom, left: rect.left, width: rect.width },
        });
      }
    }
    return frames;
  }, FLIGHT_SELECTOR);
}

// The news picture in each frame from the tap until the card has landed: the feed card's until the flight takes its
// place, then the flying copies', then the discussion post's
function recordNewsPicture(page: Page) {
  return page.evaluate(async ({ flightSelector, landedFrameCount, maxDuration }) => {
    const frames: {
      time: number;
      shownBy?: 'card' | 'flight' | 'post';
      pictures: { url?: string; isShown: boolean }[];
    }[] = [];
    const startedAt = performance.now();
    let hasFlown = false;
    let landedFrames = 0;
    while (landedFrames < landedFrameCount && performance.now() - startedAt < maxDuration) {
      await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
      const flight = document.querySelector<HTMLElement>(flightSelector);
      const card = document.querySelector<HTMLElement>('[data-agent-news-event-id="5"]');
      const post = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-news-post-event-id="5"]'))
        .find((element) => !flight?.contains(element));
      const owner = flight ?? [post, card].find((element) => (
        element && getComputedStyle(element).visibility === 'visible'
      ));
      const shownBy = !owner ? undefined : owner === flight ? 'flight' : owner === post ? 'post' : 'card';
      hasFlown ||= shownBy === 'flight';
      if (hasFlown && shownBy === 'post') landedFrames++;
      const pictures = owner?.querySelectorAll<HTMLImageElement | HTMLCanvasElement>('img, canvas') ?? [];
      frames.push({
        time: performance.now() - startedAt,
        shownBy,
        pictures: Array.from(pictures, (picture) => {
          const isVisible = getComputedStyle(picture).visibility === 'visible';
          if (picture instanceof HTMLCanvasElement) {
            // The middle of the picture is opaque, and a canvas nothing is drawn on is clear
            const pixel = picture.width && picture.height
              ? picture.getContext('2d')!.getImageData(picture.width / 2, picture.height / 2, 1, 1).data
              : undefined;
            return { isShown: isVisible && Boolean(pixel?.[3]) };
          }

          const url = new URL(picture.src);
          return {
            url: `${url.pathname}${url.search}`,
            isShown: isVisible && picture.complete && picture.naturalWidth > 0,
          };
        }),
      });
    }
    return frames;
  }, {
    flightSelector: FLIGHT_SELECTOR,
    landedFrameCount: LANDED_FRAME_COUNT,
    maxDuration: NEWS_PICTURE_MAX_RECORDING_MS,
  });
}

interface QueueRow {
  /** The message's id, or `activity` */
  key: string;
  /** The row's element, numbered as it was first seen, so that a row put in again counts as another */
  node: number;
  role: 'user' | 'assistant' | 'activity';
  status?: string;
  /** The text of the row's bubble, empty while an answer has none */
  text: string;
  /** Where its bubble, or the row without one, stands against the top of the list's box */
  top: number;
  bottom: number;
  /** With the opacity of every element between it and the list */
  opacity: number;
  translate: string;
}

interface QueueFrame {
  time: number;
  scrollTop: number;
  scrollHeight: number;
  clientHeight: number;
  /** Where the list's padding leaves the messages, against the top of its box */
  visibleTop: number;
  visibleBottom: number;
  spacerHeight?: number;
  liveTailKey?: string;
  reserveBottom?: number;
  rows: QueueRow[];
}

interface QueueScrollWrite {
  time: number;
  from: number;
  to: number;
  /** The calls that set the list's scroll position */
  stack: string[];
}

interface QueueRecording {
  frames: QueueFrame[];
  scrollWrites: QueueScrollWrite[];
}

// The list holds still for `QUEUE_REST_MS`, its rows in place and its scroll position kept
async function waitForQueueListRest(page: Page) {
  await expect.poll(() => page.evaluate(async (restMs) => {
    const host = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-conversation]')).at(-1)!;
    const list = host.querySelector<HTMLElement>('.custom-scroll')!;
    const measure = () => [list.scrollTop, ...Array.from(list.querySelectorAll('[data-agent-v2-message-id]'))
      .map((row) => row.getBoundingClientRect().top)].join();
    const shown = measure();
    const startedAt = performance.now();
    while (performance.now() - startedAt < restMs) {
      await new Promise(requestAnimationFrame);
      if (measure() !== shown) return false;
    }
    return true;
  }, QUEUE_REST_MS), { timeout: 10_000 }).toBe(true);
}

/**
 * Samples, after each frame has been drawn, where every message and activity of the open chat stands on screen and how
 * opaque it is, until `finishQueueRecording`. Every write of the list's scroll position is noted with its callers.
 */
async function startQueueRecording(page: Page) {
  await page.evaluate(({ bubbleSelector, maxMs }) => {
    const host = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-conversation]')).at(-1)!;
    const list = host.querySelector<HTMLElement>('.custom-scroll')!;
    const startedAt = performance.now();
    const nodes = new WeakMap<Element, number>();
    let nodeCount = 0;
    const recording = { isDone: false, frames: [] as QueueFrame[], scrollWrites: [] as QueueScrollWrite[] };

    function recordScrollWrite(element: Element, to: number) {
      if (element !== list) return;
      recording.scrollWrites.push({
        time: performance.now() - startedAt,
        from: list.scrollTop,
        to,
        stack: (new Error().stack ?? '').split('\n').slice(3, 14)
          .map((line) => line.trim().replace(/https?:\/\/[^/]+\//gu, '')),
      });
    }

    const scrollTopDescriptor = Object.getOwnPropertyDescriptor(Element.prototype, 'scrollTop')!;
    Object.defineProperty(Element.prototype, 'scrollTop', {
      configurable: true,
      get(this: Element) {
        return scrollTopDescriptor.get!.call(this);
      },
      set(this: Element, value: number) {
        recordScrollWrite(this, value);
        scrollTopDescriptor.set!.call(this, value);
      },
    });
    const { scrollTo } = Element.prototype;
    Element.prototype.scrollTo = function recordScrollTo(this: Element, ...args: unknown[]) {
      const [options, y] = args;
      const top = typeof options === 'object' ? (options as ScrollToOptions | null)?.top : y;
      recordScrollWrite(this, Number(top));
      Reflect.apply(scrollTo, this, args);
    };

    function getOpacity(element: Element) {
      let opacity = 1;
      for (let current: Element | null = element; current && current !== list; current = current.parentElement) {
        opacity *= Number(getComputedStyle(current).opacity);
      }
      return opacity;
    }

    function getNode(element: Element) {
      if (!nodes.has(element)) {
        nodeCount += 1;
        nodes.set(element, nodeCount);
      }
      return nodes.get(element)!;
    }

    function measureRow(element: HTMLElement, listTop: number): QueueRow {
      const isActivity = element.hasAttribute('data-agent-run-activity');
      const bubble = isActivity ? undefined : element.querySelector<HTMLElement>(bubbleSelector) ?? undefined;
      // An answer with no text yet shows the activity in its place
      const isAnswerPlaceholder = !isActivity && Boolean(element.querySelector('[data-agent-run-activity]'));
      const { top, bottom } = (bubble ?? element).getBoundingClientRect();
      return {
        key: isActivity ? 'activity' : element.getAttribute('data-agent-v2-message-id')!,
        node: getNode(element),
        role: isActivity
          ? 'activity'
          : element.getAttribute('data-agent-v2-message-role') === 'user' ? 'user' : 'assistant',
        status: element.getAttribute('data-agent-v2-message-status') ?? undefined,
        text: isAnswerPlaceholder ? '' : (bubble?.textContent ?? '').trim().slice(0, 80),
        top: top - listTop,
        bottom: bottom - listTop,
        opacity: getOpacity(bubble ?? element),
        translate: getComputedStyle(element).translate,
      };
    }

    function measureFrame(): QueueFrame {
      const listRect = list.getBoundingClientRect();
      const style = getComputedStyle(list);
      const liveTail = list.querySelector('[class*="__liveTail__"]');
      const reserve = list.querySelector('[data-agent-live-tail-reserve]');
      const spacer = list.querySelector<HTMLElement>('[class*="__spacer__"]');
      return {
        time: performance.now() - startedAt,
        scrollTop: list.scrollTop,
        scrollHeight: list.scrollHeight,
        clientHeight: list.clientHeight,
        visibleTop: Number.parseFloat(style.paddingTop),
        visibleBottom: list.clientHeight - Number.parseFloat(style.paddingBottom),
        spacerHeight: spacer?.offsetHeight,
        liveTailKey: liveTail?.querySelector('[data-agent-v2-message-id]')?.getAttribute('data-agent-v2-message-id')
          ?? undefined,
        reserveBottom: reserve ? reserve.getBoundingClientRect().bottom - listRect.top : undefined,
        rows: Array.from(list.querySelectorAll<HTMLElement>('[data-agent-v2-message-id], [data-agent-run-activity]'))
          .filter((element) => element.getClientRects().length > 0)
          .map((element) => measureRow(element, listRect.top)),
      };
    }

    void (async () => {
      while (!recording.isDone && performance.now() - startedAt < maxMs) {
        await new Promise((resolve) => {
          requestAnimationFrame(() => setTimeout(resolve, 0));
        });
        recording.frames.push(measureFrame());
      }
    })();
    (window as unknown as { agentQueueRecording: typeof recording }).agentQueueRecording = recording;
  }, { bubbleSelector: BUBBLE_SELECTOR, maxMs: QUEUE_RECORDING_MAX_MS });
}

function finishQueueRecording(page: Page) {
  return page.evaluate((): QueueRecording => {
    const recording = (window as unknown as {
      agentQueueRecording: QueueRecording & { isDone: boolean };
    }).agentQueueRecording;
    recording.isDone = true;
    return { frames: recording.frames, scrollWrites: recording.scrollWrites };
  });
}

/**
 * Tells how the rows of a queue recording moved otherwise than on mobile, where the questions that wait ride with the
 * list and move under it only as far as the rows above them change, and the pinned question stays in sight
 */
function findQueueMotionFailures(frames: QueueFrame[]) {
  const failures: string[] = [];
  const [pinnedQuestion, firstWaitingQuestion] = [QUEUE_PINNED_QUESTION, QUEUE_WAITING_QUESTIONS[0]];
  const describeFrame = (index: number) => `Frame ${index} (${Math.round(frames[index].time)} ms)`;
  const describeRow = (row: QueueRow) => (row.role === 'activity' ? 'the activity' : `"${row.text.slice(0, 40)}"`);
  const findQuestion = (frame: QueueFrame, text: string) => frame.rows.find((row) => (
    row.role === 'user' && row.text.includes(text)
  ));
  const findAnswer = (frame: QueueFrame, question: string) => {
    const messages = frame.rows.filter(({ role }) => role !== 'activity');
    const index = messages.findIndex((row) => row.role === 'user' && row.text.includes(question));
    return index === -1 || messages[index + 1]?.role !== 'assistant' ? undefined : messages[index + 1];
  };
  const getMessageKeys = (frame: QueueFrame) => frame.rows
    .filter(({ role }) => role !== 'activity')
    .map(({ key }) => key)
    .join();
  const getIsShown = (frame: QueueFrame, text: string) => {
    const question = findQuestion(frame, text);
    return question !== undefined && question.top >= frame.visibleTop - 18
      && question.bottom <= frame.visibleBottom + STILL_TOLERANCE_PX && question.opacity >= 0.95;
  };

  // A row moves on screen in a frame no farther than the scroll that pins a question and a glide take it
  frames.slice(1).forEach((frame, previousIndex) => {
    const previous = frames[previousIndex];
    const duration = frame.time - previous.time;
    const maxStep = MAX_FRAME_STEP_PX * Math.max(1, duration / FRAME_MS);
    frame.rows.forEach((row) => {
      const shown = previous.rows.find(({ node }) => node === row.node);
      if (shown && Math.abs(row.top - shown.top) > maxStep) {
        failures.push(`${describeFrame(previousIndex + 1)}: ${describeRow(row)} moved`
          + ` ${Math.round(row.top - shown.top)} px on screen in ${Math.round(duration)} ms`);
      }
    });
  });

  // A question queued comes in at the end, and nothing on screen moves
  QUEUE_WAITING_QUESTIONS.forEach((question) => {
    const queuedIndex = frames.findIndex((frame) => findQuestion(frame, question));
    if (queuedIndex < 1) {
      failures.push(`"${question}" did not come in while the list was recorded`);
      return;
    }

    const shownFrame = frames[queuedIndex - 1];
    const keys = getMessageKeys(frames[queuedIndex]);
    for (let index = queuedIndex; index < frames.length && getMessageKeys(frames[index]) === keys
      && frames[index].time - frames[queuedIndex].time < ROW_MOVE_WATCH_MS; index++) {
      frames[index].rows.forEach((row) => {
        // A question just queued finishes its own appearance
        const shown = shownFrame.rows.find(({ node, opacity }) => node === row.node && opacity > 0.99);
        if (shown && Math.abs(row.top - shown.top) > STILL_TOLERANCE_PX) {
          failures.push(`${describeFrame(index)}: ${describeRow(row)} moved ${Math.round(row.top - shown.top)} px on`
            + ` screen as "${question}" was queued`);
        }
      });
    }
  });

  // The answer comes under the pinned question, which stays where it is from the frame the answer's message comes in
  // place of the activity until the answer ends
  const startIndex = frames.findIndex((frame) => findAnswer(frame, pinnedQuestion));
  const endIndex = frames.findIndex((frame) => findAnswer(frame, pinnedQuestion)?.status === 'complete');
  if (startIndex < 1 || !frames.some((frame) => findAnswer(frame, pinnedQuestion)?.text)) {
    failures.push('The answer to the pinned question did not come while the list was recorded');
  } else {
    const shown = findQuestion(frames[startIndex - 1], pinnedQuestion)!;
    for (let index = startIndex; index < (endIndex === -1 ? frames.length : endIndex); index++) {
      const question = findQuestion(frames[index], pinnedQuestion);
      if (question && Math.abs(question.top - shown.top) > STILL_TOLERANCE_PX) {
        failures.push(`${describeFrame(index)}: the pinned question moved ${Math.round(question.top - shown.top)} px`
          + ' on screen as its answer came');
      }
    }
  }

  // The questions that wait never come over a message above them, though they may pass over an activity coming in
  frames.forEach((frame, index) => {
    let bottom = -Infinity;
    frame.rows.forEach((row) => {
      if (row.role === 'activity' || !row.text) return;
      if (row.role === 'user' && QUEUE_WAITING_QUESTIONS.some((question) => row.text.includes(question))
        && row.top < bottom - STILL_TOLERANCE_PX) {
        failures.push(`${describeFrame(index)}: ${describeRow(row)} came ${Math.round(bottom - row.top)} px over the`
          + ' message above it');
      }
      bottom = Math.max(bottom, row.bottom);
    });
  });

  // A pinned question is in sight in every frame: the one being answered, or the one that goes after it, which
  // stays in sight from the frame its activity shows under it
  const pinnedQuestions = [pinnedQuestion, ...QUEUE_WAITING_QUESTIONS];
  const goneIndices = pinnedQuestions.map((question) => frames.findIndex((frame) => {
    const index = frame.rows.findIndex((row) => row.role === 'user' && row.text.includes(question));
    return index !== -1 && frame.rows.slice(index + 1).some(({ role }) => role === 'activity');
  }));
  if (goneIndices[1] === -1) failures.push(`"${firstWaitingQuestion}" did not go while the list was recorded`);
  // The rows above a question that goes hold still on screen in the frame it goes, before the list scrolls to it
  goneIndices.forEach((goneIndex, questionIndex) => {
    if (goneIndex < 1 || !questionIndex) return;

    const question = pinnedQuestions[questionIndex];
    const [shownFrame, frame] = [frames[goneIndex - 1], frames[goneIndex]];
    const index = frame.rows.findIndex((row) => row.role === 'user' && row.text.includes(question));
    frame.rows.slice(0, index).forEach((row) => {
      const shown = shownFrame.rows.find(({ node }) => node === row.node);
      if (shown && Math.abs(row.top - shown.top) > STILL_TOLERANCE_PX) {
        failures.push(`${describeFrame(goneIndex)}: ${describeRow(row)} moved ${Math.round(row.top - shown.top)} px`
          + ` on screen as "${question}" went`);
      }
    });
  });
  frames.forEach((frame, index) => {
    const pinnedIndex = goneIndices.reduce((last, goneIndex, questionIndex) => (
      goneIndex !== -1 && goneIndex <= index ? questionIndex : last
    ), 0);
    const isShown = getIsShown(frame, pinnedQuestions[pinnedIndex])
      || (pinnedIndex + 1 < pinnedQuestions.length && getIsShown(frame, pinnedQuestions[pinnedIndex + 1]));
    if (!isShown) failures.push(`${describeFrame(index)}: no pinned question in sight`);
  });

  return failures;
}

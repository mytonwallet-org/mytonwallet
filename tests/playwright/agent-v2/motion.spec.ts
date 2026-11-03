import type { Page } from '@playwright/test';
import { writeFile } from 'node:fs/promises';

import { expect, test } from './fixtures';

const VIEWPORTS = [
  { name: 'phone Classic', width: 402, height: 874 },
  { name: 'desktop', width: 1280, height: 900 },
];
const THREAD_ID = '88888888-8888-4888-8888-888888888888';
const CREATED_AT = '2026-08-11T09:00:00.000Z';
const BUBBLE_SELECTOR = '[class*="__bubble__"]';
const FLIGHT_SELECTOR = '[class*="__flight__"][aria-hidden="true"]';
// The history morph is recorded for at least its own length. Recording then goes on until the follow-ups that stagger
// in after the morph are fully shown, which a slow runner reaches later.
const HISTORY_MORPH_MIN_RECORDING_MS = 1000;
const HISTORY_MORPH_MAX_RECORDING_MS = 3000;
const FOLLOWUPS = Array.from({ length: 3 }, (_, index) => ({
  id: `adadadad-adad-4dad-8dad-adadadadada${index}`,
  kind: 'suggested_prompt',
  text: `Explain this update ${index}`,
}));
const STORED_MESSAGES = [
  { role: 'assistant', text: 'The first stored answer.' },
  { role: 'user', text: 'Please explain the next part of this conversation.' },
  { role: 'assistant', text: 'The first part of the explanation.\n\nThere is another paragraph here.' },
  { role: 'assistant', text: 'The second part of the explanation is a separate message.' },
];

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
      await page.getByRole('button', { name: 'Allow Agent', exact: true }).click();
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
        ? 'uses large tailed dialogue placeholders for a single news post and moves the surplus away'
        : 'morphs consecutive answers as one ordered column without overlapping placeholders', async ({
        agentV2, page,
      }, testInfo) => {
        await agentV2.reset();
        await agentV2.seedWallet();
        const releaseHistory = await delayStoredHistory(page, isNewsOnly);
        await agentV2.open();
        await agentV2.acceptConsent();
        await agentV2.openThread();
        const placeholders = page.locator('[data-agent-conversation] [data-agent-skeleton-role]');
        await expect(placeholders).toHaveCount(8);
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
        expect(initial.map(({ role }) => role)).toEqual(['assistant', 'user', 'assistant', 'user']);
        for (const placeholder of initial) {
          expect(placeholder.width).toBeGreaterThanOrEqual(placeholder.availableWidth * 0.63);
          expect(placeholder.height).toBeGreaterThanOrEqual(120);
          expect(placeholder.tailWidth).toBeGreaterThan(0);
          expect(placeholder.tailHeight).toBeGreaterThan(0);
          expect(placeholder.tailMask).not.toBe('none');
        }
        expect(initial[0].height).toBeGreaterThanOrEqual(184);

        const recording = recordHistoryMorph(page);
        releaseHistory();
        const frames = await recording;
        assertFollowupStagger(frames);
        const framesPath = testInfo.outputPath('morph-frames.json');
        await writeFile(framesPath, JSON.stringify({ initial, frames }, undefined, 2));
        await testInfo.attach('morph-frames.json', { path: framesPath, contentType: 'application/json' });
        const movingFrames = frames.filter(({ isMorphing }) => isMorphing);
        expect(movingFrames.length).toBeGreaterThanOrEqual(5);
        const lastMessageId = `message:${isNewsOnly ? 0 : STORED_MESSAGES.length - 1}`;
        const positions = movingFrames.map(({ surfaces }) => surfaces.find(({ id }) => id === lastMessageId)?.top)
          .filter((top): top is number => top !== undefined);
        expect(new Set(positions.map((top) => Math.round(top * 10))).size).toBeGreaterThanOrEqual(5);
        const settled = frames.at(-1)!.surfaces.find(({ id }) => id === lastMessageId)!;
        for (const frame of movingFrames) {
          const bubble = frame.surfaces.find(({ id }) => id === lastMessageId);
          if (!bubble) continue;
          expect(bubble.bottom, JSON.stringify({ initial: initial[0], settled, frame }))
            .toBeLessThanOrEqual(Math.max(initial[0].bottom, settled.bottom) + 1);
          expect(bubble.top, JSON.stringify({ initial: initial[0], settled, frame }))
            .toBeGreaterThanOrEqual(Math.min(initial[0].top, settled.top) - 1);
        }
        for (const frame of frames) {
          expect(frame.overlaps, JSON.stringify(frame)).toEqual([]);
          expect(frame.isMessageOrderPreserved, JSON.stringify(frame)).toBe(true);
        }
        await expect(page.locator('[data-agent-conversation] [data-agent-skeleton]')).toHaveCount(0);
        expect(await measureComposerGap(page, '[data-agent-followup-id]')).toBeCloseTo(16, 0);
        await page.screenshot({ path: testInfo.outputPath('settled.png') });
      });
    }

    test('reveals news placeholders every 150 ms then morphs the ready followups together', async ({
      agentV2, page,
    }, testInfo) => {
      await agentV2.reset('news-post');
      await agentV2.seedWallet();
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
      await agentV2.acceptConsent();
      await page.getByRole('button', { name: /^News,/u }).click();
      const loadingRecording = recordFollowups(page, 3000, '[data-agent-followup-placeholder]');
      await page.getByRole('button', { name: 'Discuss, Deterministic MyPulse headline', exact: true }).click();
      await expect(page.locator('[data-agent-followup-placeholder]')).toHaveCount(3);
      await expect(page.locator(FLIGHT_SELECTOR)).toHaveCount(0);
      const loadingFrames = await loadingRecording;
      assertFollowupStagger(loadingFrames);
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
      await agentV2.acceptConsent();
      await agentV2.send('A short answer');
      await runReady;
      const recording = recordFollowups(page, 2000);
      releaseRun();
      const frames = await recording;
      assertFollowupStagger(frames);
      await testInfo.attach('fresh-answer-followups.json', {
        body: JSON.stringify(frames, undefined, 2), contentType: 'application/json',
      });
    });

    test('shows history followups immediately with reduced motion', async ({ agentV2, page }) => {
      await page.emulateMedia({ reducedMotion: 'reduce' });
      await agentV2.reset();
      await agentV2.seedWallet();
      const releaseHistory = await delayStoredHistory(page, true);
      await agentV2.open();
      await agentV2.acceptConsent();
      await agentV2.openThread();
      releaseHistory();
      const buttons = page.locator('[data-agent-followup-id]');
      await expect(buttons).toHaveCount(3);
      const frames = await recordFollowups(page, 300);
      expect(frames.every(({ followupOpacities }) => followupOpacities.every((opacity) => opacity === 1))).toBe(true);
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
      await agentV2.acceptConsent();
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
      }
      await expect(page.locator(FLIGHT_SELECTOR)).toHaveCount(0);
      await expect(page.locator('[data-agent-news-post-event-id="5"]')).toBeVisible();
      expect(errors).toEqual([]);
      await page.screenshot({ path: testInfo.outputPath('landed.png') });
    });
  });
}

async function delayStoredHistory(page: Page, isNewsOnly: boolean) {
  const messages = isNewsOnly
    ? [{ role: 'assistant', text: 'A single saved news post.\n\nThis is the full news body.', newsPost: true }]
    : STORED_MESSAGES;
  const thread = {
    id: THREAD_ID,
    revision: 1,
    createdAt: CREATED_AT,
    updatedAt: CREATED_AT,
    lastActivityAt: CREATED_AT,
    messageCount: messages.length,
    title: 'Stored animation test conversation',
    ...(isNewsOnly && {
      news: {
        eventId: 5,
        headline: 'A single saved news post',
        body: 'This is the full news body.',
        publishedAt: CREATED_AT,
      },
    }),
  };
  await page.route('**/api/v2/threads?*', (route) => route.fulfill({
    json: { protocolVersion: 3, threads: [{ thread }] },
  }));
  let releaseHistory!: () => void;
  const historyMayFinish = new Promise<void>((resolve) => {
    releaseHistory = resolve;
  });
  await page.route(`**/api/v2/threads/${THREAD_ID}/messages?*`, async (route) => {
    await historyMayFinish;
    await route.fulfill({ json: {
      protocolVersion: 3,
      thread,
      messages: messages.map(({ text, ...message }, index) => ({
        ...message,
        id: `00000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
        threadId: THREAD_ID,
        createdAt: CREATED_AT,
        status: 'complete',
        content: { kind: 'markdown', text },
        ...(index === messages.length - 1 && { followups: FOLLOWUPS }),
      })),
    } });
  });
  return releaseHistory;
}

function measureComposerGap(page: Page, selector: string) {
  return page.locator('[data-agent-conversation]').last().evaluate((host, tailSelector) => {
    const composer = host.querySelector('[data-agent-composer]')!;
    const tail = Array.from(host.querySelectorAll(tailSelector)).at(-1)!;
    return composer.getBoundingClientRect().top - tail.getBoundingClientRect().bottom;
  }, selector);
}

function recordHistoryMorph(page: Page) {
  return page.evaluate(async ({ bubbleSelector, minDuration, maxDuration }) => {
    const frames = [];
    const startedAt = performance.now();
    let areFollowupsShown = false;
    while (getElapsed() < maxDuration && (getElapsed() < minDuration || !areFollowupsShown)) {
      await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
      const host = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-conversation]')).at(-1)!;
      const scroll = host.querySelector<HTMLElement>('.custom-scroll')!;
      const visibleRect = scroll.getBoundingClientRect();
      const messages = Array.from(host.querySelectorAll<HTMLElement>('[data-agent-v2-message-role]'));
      const bubbles = messages.flatMap((message, index) => {
        const bubble = message.querySelector<HTMLElement>(bubbleSelector);
        return bubble ? [{ element: bubble, id: `message:${index}`, index }] : [];
      });
      const placeholders = Array.from(host.querySelectorAll<HTMLElement>('[data-agent-skeleton-role]'))
        .map((element, index) => ({ element, id: `placeholder:${index}`, index: -1 }));
      const isMorphing = bubbles.some(({ element }) => element.getAnimations().some((animation) => (
        animation.playState === 'running' && animation.effect instanceof KeyframeEffect
        && animation.effect.getKeyframes().some((keyframe) => String(keyframe.transform).includes('scale('))
      )));
      const surfaces = [...bubbles, ...placeholders].flatMap(({ element, id, index }) => {
        let opacity = 1;
        for (let ancestor: HTMLElement | null = element; ancestor; ancestor = ancestor.parentElement) {
          const style = getComputedStyle(ancestor);
          opacity *= Number(style.opacity);
          if (style.visibility === 'hidden' || style.display === 'none') opacity = 0;
        }
        const rect = element.getBoundingClientRect();
        const top = Math.max(rect.top, visibleRect.top);
        const bottom = Math.min(rect.bottom, visibleRect.bottom);
        if (opacity < 0.03 || bottom <= top || rect.width < 1) return [];
        return [{ id, index, top, bottom, left: rect.left, right: rect.right, opacity }];
      });
      const overlaps = surfaces.flatMap((surface, index) => surfaces.slice(index + 1).flatMap((other) => {
        const width = Math.min(surface.right, other.right) - Math.max(surface.left, other.left);
        const height = Math.min(surface.bottom, other.bottom) - Math.max(surface.top, other.top);
        return width > 2 && height > 1 ? [{ first: surface.id, second: other.id, width, height }] : [];
      }));
      const visibleMessages = surfaces.filter(({ index }) => index >= 0);
      const isMessageOrderPreserved = visibleMessages.every((surface, index) => (
        index === 0 || surface.top >= visibleMessages[index - 1].bottom - 1
      ));
      const followupOpacities = Array.from(host.querySelectorAll('[data-agent-followup-id]')).map((button) => {
        let opacity = 1;
        for (let element: Element | null = button; element; element = element.parentElement) {
          opacity *= Number(getComputedStyle(element).opacity);
        }
        return opacity;
      });
      areFollowupsShown = followupOpacities.length > 0 && followupOpacities.every((opacity) => opacity === 1);
      frames.push({
        time: performance.now() - startedAt, isMorphing, surfaces, overlaps, isMessageOrderPreserved, followupOpacities,
      });
    }
    return frames;

    function getElapsed() {
      return performance.now() - startedAt;
    }
  }, {
    bubbleSelector: BUBBLE_SELECTOR,
    minDuration: HISTORY_MORPH_MIN_RECORDING_MS,
    maxDuration: HISTORY_MORPH_MAX_RECORDING_MS,
  });
}

function assertFollowupStagger(frames: { time: number; followupOpacities: number[] }[]) {
  const firstVisible = FOLLOWUPS.map((_, index) => frames.findIndex((frame) => frame.followupOpacities[index] > 0.05));
  expect(firstVisible.every((index) => index >= 0), JSON.stringify(frames)).toBe(true);
  const windows = firstVisible.map((index) => ({
    from: frames[Math.max(0, index - 1)].time,
    to: frames[index].time,
  }));
  for (let index = 1; index < windows.length; index++) {
    const previous = windows[index - 1];
    const current = windows[index];
    expect(current.to, JSON.stringify(windows)).toBeGreaterThan(previous.to);
    // Visibility starts between two captured frames, even when the browser skips a sampling frame
    expect(current.from - previous.to, JSON.stringify(windows)).toBeLessThanOrEqual(170);
    expect(current.to - previous.from, JSON.stringify(windows)).toBeGreaterThanOrEqual(130);
  }
  expect(frames.at(-1)!.followupOpacities).toEqual([1, 1, 1]);
}

function recordFollowups(page: Page, duration = 1200, selector = '[data-agent-followup-id]') {
  return page.evaluate(async ({ milliseconds, selector: followupSelector }) => {
    const frames = [];
    const startedAt = performance.now();
    while (performance.now() - startedAt < milliseconds) {
      await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
      const host = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-conversation]')).at(-1);
      const followupOpacities = Array.from(host?.querySelectorAll(followupSelector) ?? []).map((button) => {
        let opacity = 1;
        for (let element: Element | null = button; element; element = element.parentElement) {
          opacity *= Number(getComputedStyle(element).opacity);
        }
        return opacity;
      });
      frames.push({
        time: performance.now() - startedAt, followupOpacities,
        scrollTop: host?.querySelector<HTMLElement>('.custom-scroll')?.scrollTop ?? 0,
      });
    }
    return frames;
  }, { milliseconds: duration, selector });
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
      if (root && movingFrame) {
        const rect = movingFrame.getBoundingClientRect();
        const style = getComputedStyle(root);
        const rootRect = root.getBoundingClientRect();
        const insets = style.clipPath.match(/^inset\(([^)]+)\)/u)?.[1].split(/\s+/u).map(parseFloat) ?? [0];
        const topInset = insets[0];
        const bottomInset = insets[2] ?? topInset;
        const headers = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-header]'))
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
          frame: { top: rect.top, bottom: rect.bottom, left: rect.left, width: rect.width },
        });
      }
    }
    return frames;
  }, FLIGHT_SELECTOR);
}

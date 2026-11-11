import type { Locator, Page } from '@playwright/test';

import type { AgentV2Fixture } from './fixtures';

import { expect, getAgentV2Conversation, test } from './fixtures';

const THREAD_ID = '77777777-7777-4777-8777-777777777777';
const CREATED_AT = '2026-08-11T09:00:00.000Z';
const ANSWER_SELECTOR = '[data-agent-v2-message-role="assistant"]';
const BUBBLE_SELECTOR = '[class*="__bubble__"]';
const BADGE_SELECTOR = '[data-agent-feedback-badge]';
// The corner's emoji, its picture or its animation, and the cloud's; and the emoji of a reaction replaced
const ICON_SELECTOR = '[class*="__icon__"]';
const REPLACED_ICON_SELECTOR = '[class*="__replacedIcon__"]';
const EFFECT_SELECTOR = '[data-agent-feedback-effect]';
const FLIGHT_SELECTOR = '[data-agent-feedback-flight]';
const CLOUD_SELECTOR = '[data-agent-feedback-cloud]';
// An answer's menu, which its bubble keeps until the menu has faded out, and opens again only after that
const MESSAGE_MENU_SELECTOR = '.menu-bubble[class*="MessageBubble"][class*="__menu__"]';
// The composer of the open chat
const COMPOSER_SELECTOR = '[data-agent-conversation] [data-agent-composer]';
const TOAST_ICON_FRAME_SELECTOR = '[class*="__animatedIconFrame__"]';
// A toast's text runs in 16 px lines, with 16 px of padding all round
const TOAST_LINE_HEIGHT = 16;
const TOAST_PADDING = 16;
// The capsule's height and its gap over the bubble's top
const CLOUD_RISE = 56 + 6;
// The cloud keeps this far from the top of the screen
const CLOUD_TOP_LIMIT = 12;
// The answer's emoji: 22 px, its centre 3 px inside the bubble's trailing edge and its bottom 3 px under the bubble's.
// It draws the emoji 18 px wide in its frame.
const BADGE_SIZE = 22;
const BADGE_INSET = 3;
const BADGE_DROP = 3;
const BADGE_EMOJI_SIZE = 18;
// Messages stand 10 px apart
const MESSAGE_GAP = 10;
// Telegram's flight: 0.2 s with linear timing along a parabola 30 px over its start halfway across, with the burst
// from 0.15 s, and the swap of the emoji at the corner in 0.12 s
const FLIGHT_DURATION = 200;
const FLIGHT_ELEVATION = 30;
const BURST_DELAY = 150;
const SWAP_DURATION = 120;
// The size of the cloud's icons
const CLOUD_ICON_SIZE = 36;
// How near frames come to where they should be, in pixels, in the share of the way, and in opacity
const RECT_TOLERANCE = 1.5;
const PIXEL_TOLERANCE = 0.5;
const PROGRESS_TOLERANCE = 0.02;
const OPACITY_TOLERANCE = 0.05;
// The reaction is recorded until it has rested at the corner for this long after it changed
const RECORDING_SETTLE_MS = 400;
const RECORDING_MAX_MS = 5000;
// The menu opening or closing over the corner is recorded for this long
const MENU_RECORDING_MS = 1000;
// A reaction is held this long, past any long press, and its place shrinks to this while it is pressed
const HOLD_MS = 800;
const PRESS_SCALE = 0.85;
// Telegram's circle behind the current rating, one neutral overlay on the cloud's colour, at rest
const SELECTION_CIRCLE = {
  color: 'rgba(0, 0, 0, 0.08)', size: 44, opacity: '1', transform: 'none',
};
const LONG_ANSWER = Array.from({ length: 40 }, (_, index) => (
  `Part ${index + 1}: the network keeps its fees low as more people use it.`
)).join('\n\n');
const MESSAGES = [
  { role: 'user', text: 'What keeps the fees low?' },
  { role: 'assistant', text: 'Sharding does.' },
  { role: 'user', text: 'Tell me more.' },
  { role: 'assistant', text: LONG_ANSWER, feedback: 'like' },
];

interface Rect {
  left: number;
  top: number;
  width: number;
  height: number;
}

interface Point {
  x: number;
  y: number;
}

interface FlightState extends Rect {
  /** The opacities of the cloud's still of the emoji and of the corner's drawing over it */
  drawings: number[];
}

interface ReactionFrame {
  time: number;
  flight?: FlightState;
  feedback?: string;
  /** The corner shows its own emoji, and the emoji of a reaction it replaced, with how much of it is left */
  isBadgeShown: boolean;
  replacedOpacity?: number;
  /** The burst around the corner, where it plays */
  burst?: Rect;
  hasBurst: boolean;
  /** The corner's emoji plays, or an effect plays over it */
  hasLottie: boolean;
}

interface ReactionRecording {
  /** The flying emoji's first frame, as it is put on the screen, and when */
  start?: FlightState & { time: number };
  frames: ReactionFrame[];
}

test.describe('Agent V2 reactions', () => {
  test.use({ viewport: { width: 402, height: 640 } });

  test('keeps the cloud in reach over a long answer, which keeps its emoji while the menu is open', async ({
    agentV2,
    page,
  }) => {
    const { badge, cloud, conversation } = await openRatedLongAnswer(agentV2, page);

    // The answer's top is out of sight, so the cloud stays at the top of the screen, drawn over the answer
    await placeAnswerTop(conversation, -300);
    await page.mouse.click(120, 320, { button: 'right' });
    await expect(cloud).toBeVisible();
    await expect(page.locator(MESSAGE_MENU_SELECTOR)).toHaveCount(1);
    await expect.poll(() => getTop(cloud)).toBe(CLOUD_TOP_LIMIT);
    await expect.poll(() => getIsOnTop(cloud.getByRole('button', { name: 'Like', exact: true }))).toBe(true);
    // As in Telegram, the answer keeps its emoji while the menu is open
    expect(await getIsBadgeShown(badge)).toBe(true);

    // The menu holds the chat still
    const scrollTop = await getScrollTop(conversation);
    await page.mouse.move(200, 100);
    await page.mouse.wheel(0, -400);
    await page.waitForTimeout(300);
    expect(await getScrollTop(conversation)).toBe(scrollTop);

    // Once the list brings the answer's top down, the cloud rides over it
    const answerTop = await placeAnswerTop(conversation, 160);
    expect(answerTop - CLOUD_RISE).toBeGreaterThan(CLOUD_TOP_LIMIT);
    await expect.poll(() => getTop(cloud)).toBeCloseTo(answerTop - CLOUD_RISE, 0);

    await page.keyboard.press('Escape');
    await expect(cloud).toHaveCount(0);
    expect(await getIsBadgeShown(badge)).toBe(true);
    await waitForMenuClosed(page);

    // A reaction chosen in the cloud at the top of the screen flies to the corner out of sight, which shows the heart
    // until the broken heart lands there
    await placeAnswerTop(conversation, -300);
    await page.mouse.click(120, 320, { button: 'right' });
    await expect.poll(() => getTop(cloud)).toBe(CLOUD_TOP_LIMIT);
    const recording = recordReaction(page, -1);
    await cloud.getByRole('button', { name: 'Dislike', exact: true }).click();
    await expect(badge).toHaveAttribute('data-agent-feedback-badge', 'dislike');
    await expect.poll(() => getIsBadgeShown(badge)).toBe(true);

    const { frames } = await recording;
    const timeline = getTimeline(frames);
    expect(frames.some(({ flight }) => flight), timeline).toBe(true);
    expect(frames.every(({ isBadgeShown, replacedOpacity }) => isBadgeShown || replacedOpacity), timeline).toBe(true);
    expect(frames.at(-1), timeline).toMatchObject({ feedback: 'dislike', isBadgeShown: true });
  });

  test('shows the reaction as an emoji on the bubble\'s corner, taking no room, untouched by the menu', async ({
    agentV2,
    page,
  }) => {
    const { badge, cloud, conversation } = await openRatedLongAnswer(agentV2, page);
    await placeAnswerBottom(conversation);
    const answer = page.locator(ANSWER_SELECTOR).last();
    const bubble = await getRect(answer.locator(BUBBLE_SELECTOR));
    const corner = await getRect(badge);

    // The emoji alone, 22 px, centred 3 px inside the bubble's trailing edge with its bottom 3 px under the bubble's
    expectRect(corner, getCornerRect(bubble), PIXEL_TOLERANCE);
    expect(await badge.evaluate((element) => {
      const { backgroundColor, boxShadow } = getComputedStyle(element);
      return [backgroundColor, boxShadow, element.children.length];
    })).toEqual(['rgba(0, 0, 0, 0)', 'none', 1]);
    // It is drawn over what is under the bubble, and keeps off the answer's text
    expect(await getIsOnTop(badge, BADGE_SIZE / 2 - 2)).toBe(true);
    expect(await getTextOverlap(badge)).toBe(0);
    // It takes no room: the rated answer stands as far from the question over it as the other answer does
    expect(await getGapOver(answer)).toBeCloseTo(MESSAGE_GAP, 0);
    expect(await getGapOver(page.locator(ANSWER_SELECTOR).first())).toBeCloseTo(MESSAGE_GAP, 0);

    // The menu opens and closes over it as over an answer without a reaction, nothing flying and nothing playing,
    // while the corner shows the heart on every frame
    const opening = recordReaction(page, -1, { maxDuration: MENU_RECORDING_MS, noSettle: true });
    await page.mouse.click(120, 300, { button: 'right' });
    const like = cloud.getByRole('button', { name: 'Like', exact: true });
    await expect.poll(() => getSelectionCircle(like)).toEqual(SELECTION_CIRCLE);
    const { frames: openingFrames } = await opening;
    expectUntouched(openingFrames);

    const closing = recordReaction(page, -1, { maxDuration: MENU_RECORDING_MS, noSettle: true });
    await page.keyboard.press('Escape');
    await expect(cloud).toHaveCount(0);
    const { frames: closingFrames } = await closing;
    expectUntouched(closingFrames);
    expectRect(await getRect(badge), corner, PIXEL_TOLERANCE);
  });

  test('flies a chosen reaction to the corner on Telegram\'s parabola, and bursts there as it lands', async ({
    agentV2, page,
  }) => {
    await openRatedLongAnswer(agentV2, page);
    const answer = page.locator(ANSWER_SELECTOR).first();
    const cloud = page.locator(CLOUD_SELECTOR);

    await answer.locator(BUBBLE_SELECTOR).click({ button: 'right' });
    const like = cloud.getByRole('button', { name: 'Like', exact: true });
    const dislike = cloud.getByRole('button', { name: 'Dislike', exact: true });
    await expect.poll(() => getHasDrawn(like)).toBe(true);
    await expect.poll(() => getHasDrawn(dislike)).toBe(true);
    const cloudIcon = await getRect(like.locator(ICON_SELECTOR));

    const recording = recordReaction(page, 0);
    await like.click();
    const { start, frames } = await recording;
    const badge = answer.locator(BADGE_SELECTOR);
    await expect(badge).toHaveAttribute('data-agent-feedback-badge', 'like');
    // The first like explains itself in the app's toast, which plays the heart in its icon's place
    const toast = page.getByText('The agent will respond more like this.', { exact: true });
    await expect(toast).toBeVisible();
    await expect.poll(() => getHasDrawn(toast)).toBe(true);
    // As Telegram's, it shows at the top of the screen, clear of the composer
    const toastRect = await getRect(toast.locator('xpath=..'));
    expect(toastRect.top + toastRect.height).toBeLessThan((await getRect(page.locator(COMPOSER_SELECTOR).last())).top);
    // The heart is centred on the text's first line, and the toast is as tall as a plain one of as many lines
    const toastLayout = await getToastLayout(toast);
    expect(Math.abs(toastLayout.iconCenter - toastLayout.lineCenter)).toBeLessThanOrEqual(1);
    expect(toastRect.height).toBeCloseTo(TOAST_PADDING * 2 + TOAST_LINE_HEIGHT * toastLayout.lineCount, 0);
    const corner = await getRect(badge);
    const timeline = getTimeline(frames);

    // The heart leaves its place in the cloud as the cloud's still, and lands at the corner as the corner's first
    // drawing, at its size
    expectRect(start!, cloudIcon);
    expect(start!.drawings).toEqual([1, 0]);
    const flightFrames = frames.filter(({ flight }) => flight);
    expect(flightFrames.length, timeline).toBeGreaterThan(3);
    expectRect(flightFrames.at(-1)!.flight!, corner, RECT_TOLERANCE);
    expect(flightFrames.at(-1)!.flight!.drawings).toEqual([0, 1]);

    // On every frame it is on Telegram's parabola, as far along as its linear time, which rises 30 px over the start
    // halfway across and falls fast onto the corner. A frame is seen at most a frame late, and the one where it has
    // arrived shows until the next.
    const frameGap = getLongestFrameGap(frames);
    const from = getCenter(start!);
    const to = getCenter(corner);
    flightFrames.forEach(({ time, flight }) => {
      const center = getCenter(flight!);
      const progress = (center.x - from.x) / (to.x - from.x);
      expect(Math.abs(center.y - getParabolaY(from, to, progress)), timeline).toBeLessThan(RECT_TOLERANCE);
      expect(Math.abs(flight!.width - (start!.width + (BADGE_SIZE - start!.width) * progress)))
        .toBeLessThan(RECT_TOLERANCE);
      expect(Math.abs(flight!.drawings[0] - Math.min(1, (1 - progress) * 2))).toBeLessThan(OPACITY_TOLERANCE);
      expect(Math.abs(flight!.drawings[1] - Math.min(1, progress * 2))).toBeLessThan(OPACITY_TOLERANCE);
      const timeProgress = (time - start!.time) / FLIGHT_DURATION;
      expect(progress, timeline).toBeLessThan(timeProgress + PROGRESS_TOLERANCE);
      if (progress < 1 - PROGRESS_TOLERANCE) {
        expect(progress, timeline).toBeGreaterThan(timeProgress - (frameGap + 5) / FLIGHT_DURATION);
      }
    });
    expect(flightFrames.some(({ flight }) => getCenter(flight!).y < from.y - FLIGHT_ELEVATION / 2)).toBe(true);
    // It arrives in 0.2 s, and shows there for a frame
    const flightEnd = flightFrames.at(-1)!.time;
    expect(flightEnd - start!.time, timeline).toBeGreaterThan(FLIGHT_DURATION - frameGap - 5);
    expect(flightEnd - start!.time, timeline).toBeLessThan(FLIGHT_DURATION + frameGap * 2 + 5);

    // The burst starts around the corner 0.15 s in, before the heart lands
    const burstFrames = frames.filter(({ hasBurst }) => hasBurst);
    expect(burstFrames[0].time - start!.time, timeline).toBeGreaterThan(BURST_DELAY - 5);
    expect(burstFrames[0].time, timeline).toBeLessThan(flightEnd + frameGap + 1);
    expectRect(burstFrames.at(-1)!.burst!, getCenteredRect(corner, BADGE_SIZE * 6));

    // The corner shows its emoji in the frame the flying one goes, and never while it flies
    const landing = frames.findIndex(({ flight }, index) => index > 0 && !flight && frames[index - 1].flight);
    expect(landing, timeline).toBeGreaterThan(0);
    expect(frames[landing].isBadgeShown, timeline).toBe(true);
    expect(frames.slice(0, landing).some(({ isBadgeShown }) => isBadgeShown), timeline).toBe(false);
    expect(frames.slice(landing).every(({ isBadgeShown }) => isBadgeShown), timeline).toBe(true);

    // The cloud has closed into its tail, the emoji plays as it lands, and the burst goes when it ends
    await expect(cloud).toHaveCount(0);
    await expect(page.locator(EFFECT_SELECTOR)).toHaveCount(0, { timeout: 5000 });
    await expect.poll(() => getIsBadgeShown(badge)).toBe(true);
    // A one-line answer's emoji keeps off its text too
    expect(await getTextOverlap(badge)).toBe(0);
  });

  test('swaps the emoji as a new reaction lands, and shrinks it away as it is withdrawn, moving nothing', async ({
    agentV2, page,
  }) => {
    const { badge, cloud, conversation } = await openRatedLongAnswer(agentV2, page);
    await placeAnswerBottom(conversation);
    const answerPlace = await getLastAnswerOffset(conversation);

    // A press held on the broken heart chooses it as it ends, as a click does: while it is held, its place shrinks
    // with the emoji, which does not grow
    await page.mouse.click(120, 300, { button: 'right' });
    const dislike = cloud.getByRole('button', { name: 'Dislike', exact: true });
    await expect.poll(() => getHasDrawn(dislike)).toBe(true);
    const recording = recordReaction(page, -1);
    const dislikeBox = (await dislike.boundingBox())!;
    await page.mouse.move(dislikeBox.x + dislikeBox.width / 2, dislikeBox.y + dislikeBox.height / 2);
    await page.mouse.down();
    await page.waitForTimeout(HOLD_MS);
    expect((await dislike.boundingBox())!.width).toBeCloseTo(CLOUD_ICON_SIZE * PRESS_SCALE, 0);
    expect((await getRect(dislike.locator(ICON_SELECTOR))).width).toBeCloseTo(CLOUD_ICON_SIZE * PRESS_SCALE, 0);
    expect(await page.locator(FLIGHT_SELECTOR).count()).toBe(0);
    await expect(badge).toHaveAttribute('data-agent-feedback-badge', 'like');
    await page.mouse.up();

    // The heart shows until the broken heart lands, and then goes in 0.12 s
    const { frames } = await recording;
    const timeline = getTimeline(frames);
    const landing = frames.findIndex(({ flight }, index) => index > 0 && !flight && frames[index - 1].flight);
    expect(landing, timeline).toBeGreaterThan(0);
    expect(frames.slice(0, landing).every(({ isBadgeShown, replacedOpacity, feedback }) => (
      feedback === 'like' ? isBadgeShown : !isBadgeShown && replacedOpacity === 1
    )), timeline).toBe(true);
    expect(frames[landing], timeline).toMatchObject({ feedback: 'dislike', isBadgeShown: true });
    const replacedEnd = frames.findIndex(({ replacedOpacity }, index) => index > landing && !replacedOpacity);
    expect(replacedEnd, timeline).toBeGreaterThan(landing);
    expect(frames[replacedEnd].time - frames[landing].time, timeline)
      .toBeLessThan(SWAP_DURATION + getLongestFrameGap(frames) + 5);
    expect(await getLastAnswerOffset(conversation)).toBeCloseTo(answerPlace, 0);

    // A tap on the current rating shrinks the emoji away, with nothing flying
    await waitForMenuClosed(page);
    await page.mouse.click(120, 300, { button: 'right' });
    await expect.poll(() => getHasDrawn(dislike)).toBe(true);
    const withdrawal = recordReaction(page, -1);
    await dislike.click();
    await expect(badge).toHaveCount(0);
    const { frames: withdrawalFrames } = await withdrawal;
    expect(withdrawalFrames.some(({ flight, hasBurst }) => flight || hasBurst)).toBe(false);
    expect(await getLastAnswerOffset(conversation)).toBeCloseTo(answerPlace, 0);
  });

  test('draws the same neutral circle behind either current rating', async ({ agentV2, page }) => {
    test.slow();
    const { cloud, conversation } = await openRatedLongAnswer(agentV2, page);
    await placeAnswerTop(conversation, 200);
    await page.mouse.click(120, 320, { button: 'right' });
    const like = cloud.getByRole('button', { name: 'Like', exact: true });
    // It scales up and fades in with the heart
    await expect.poll(() => getSelectionCircle(like)).toEqual(SELECTION_CIRCLE);
    await page.keyboard.press('Escape');
    await expect(cloud).toHaveCount(0);
    await waitForMenuClosed(page);

    const answer = page.locator(ANSWER_SELECTOR).first();
    await answer.locator(BUBBLE_SELECTOR).click({ button: 'right' });
    await cloud.getByRole('button', { name: 'Dislike', exact: true }).click();
    await expect(cloud).toHaveCount(0);
    await expect.poll(() => getIsBadgeShown(answer.locator(BADGE_SELECTOR))).toBe(true);
    await waitForMenuClosed(page);
    await answer.locator(BUBBLE_SELECTOR).click({ button: 'right' });
    await expect.poll(() => getSelectionCircle(cloud.getByRole('button', { name: 'Dislike', exact: true })))
      .toEqual(SELECTION_CIRCLE);
  });
});

/**
 * On every frame of a reaction to the answer at `answerIndex` (from the end where negative), from before the press
 * that chooses it until its corner has rested a while with another reaction, or none: the flying emoji, what the
 * corner shows, and the effects
 */
function recordReaction(
  page: Page,
  answerIndex: number,
  { maxDuration = RECORDING_MAX_MS, noSettle = false }: { maxDuration?: number; noSettle?: boolean } = {},
): Promise<ReactionRecording> {
  return page.evaluate(async ({
    index, duration, settleDuration, isSettling, selectors,
  }) => {
    function getFlightState(flight: Element) {
      const { left, top, width, height } = flight.getBoundingClientRect();
      return {
        left,
        top,
        width,
        height,
        drawings: Array.from(flight.querySelectorAll('img')).map((image) => Number(getComputedStyle(image).opacity)),
      };
    }

    const startedAt = performance.now();
    let start: ReactionRecording['start'];
    const observer = new MutationObserver((mutations) => {
      mutations.forEach(({ addedNodes }) => addedNodes.forEach((node) => {
        if (!start && node instanceof Element && node.matches(selectors.flight)) {
          start = { ...getFlightState(node), time: performance.now() - startedAt };
        }
      }));
    });
    observer.observe(document.body, { childList: true });

    const frames: ReactionFrame[] = [];
    let initialFeedback: string | undefined;
    let restingSince: number | undefined;
    while (performance.now() - startedAt < duration
      && (restingSince === undefined || performance.now() - restingSince < settleDuration)) {
      const answer = Array.from(document.querySelectorAll(selectors.answer)).at(index);
      const badge = answer?.querySelector(selectors.badge);
      const flight = document.querySelector(selectors.flight);
      const replaced = badge?.querySelector(selectors.replacedIcon);
      const isBadgeShown = badge
        ? Number(getComputedStyle(badge).opacity) > 0 && Array.from(badge.querySelectorAll(selectors.icon))
          .some((icon) => getComputedStyle(icon).visibility === 'visible')
        : false;
      const effects = Array.from(document.querySelectorAll(selectors.effect));
      const burst = effects.find((effect) => effect.getAttribute('data-agent-feedback-effect')!.endsWith('-burst'));
      const feedback = badge?.getAttribute('data-agent-feedback-badge') ?? undefined;
      if (!frames.length) initialFeedback = feedback;
      const burstRect = burst?.getBoundingClientRect();
      frames.push({
        time: performance.now() - startedAt,
        flight: flight ? getFlightState(flight) : undefined,
        feedback,
        isBadgeShown,
        replacedOpacity: replaced ? Number(getComputedStyle(replaced).opacity) : undefined,
        burst: burstRect && {
          left: burstRect.left, top: burstRect.top, width: burstRect.width, height: burstRect.height,
        },
        hasBurst: Boolean(burst),
        hasLottie: Boolean(badge?.querySelector('canvas')) || effects.length > 0,
      });
      const isResting = isSettling && feedback !== initialFeedback && !flight && !replaced && !effects.length
        && (!badge || isBadgeShown);
      if (isResting) {
        restingSince ??= performance.now();
      } else {
        restingSince = undefined;
      }
      await new Promise(requestAnimationFrame);
    }

    observer.disconnect();
    return { start, frames };
  }, {
    index: answerIndex,
    duration: maxDuration,
    settleDuration: RECORDING_SETTLE_MS,
    isSettling: !noSettle,
    selectors: {
      answer: ANSWER_SELECTOR,
      badge: BADGE_SELECTOR,
      flight: FLIGHT_SELECTOR,
      icon: ICON_SELECTOR,
      replacedIcon: REPLACED_ICON_SELECTOR,
      effect: EFFECT_SELECTOR,
    },
  });
}

// The longest time between two frames recorded, which a frame can be seen late by
function getLongestFrameGap(frames: ReactionFrame[]) {
  return Math.max(...frames.slice(1).map(({ time }, index) => time - frames[index].time));
}

// The corner shows its emoji on every frame, with nothing flying, nothing playing over it and nothing replaced
function expectUntouched(frames: ReactionFrame[]) {
  const timeline = getTimeline(frames);
  expect(frames.length).toBeGreaterThan(10);
  expect(frames.every(({
    isBadgeShown, flight, hasLottie, replacedOpacity,
  }) => isBadgeShown && !flight && !hasLottie && replacedOpacity === undefined), timeline).toBe(true);
}

// What changed on which frame, for a failure to show
function getTimeline(frames: ReactionFrame[]) {
  return frames.map(({
    time, flight, feedback, isBadgeShown, replacedOpacity, hasBurst,
  }) => {
    const state = [
      flight ? `F${Math.round(flight.left)},${Math.round(flight.top)},${Math.round(flight.width)}` : '',
      feedback ? `${feedback}${isBadgeShown ? '+' : '-'}` : '',
      replacedOpacity !== undefined ? `R${replacedOpacity.toFixed(2)}` : '',
      hasBurst ? 'B' : '',
    ].filter(Boolean).join(' ');
    return `${Math.round(time)}:${state}`;
  })
    .filter((change, index, all) => change.split(':')[1] !== all[index - 1]?.split(':')[1])
    .join(' | ');
}

// The answer's menu has faded out after closing, so that a press on the answer opens it again. The cloud goes sooner.
function waitForMenuClosed(page: Page) {
  return expect(page.locator(MESSAGE_MENU_SELECTOR)).toHaveCount(0);
}

async function openRatedLongAnswer(agentV2: AgentV2Fixture, page: Page) {
  await agentV2.reset();
  await agentV2.seedWallet();
  await routeRatedLongAnswer(page);
  await agentV2.open();
  await agentV2.waitForList();
  await agentV2.openThread();

  const badge = page.locator(BADGE_SELECTOR);
  await expect(badge).toHaveAttribute('data-agent-feedback-badge', 'like');
  const conversation = getAgentV2Conversation(page);
  // The chat has taken its first place
  await expect.poll(async () => {
    const previousScrollTop = await getScrollTop(conversation);
    await page.waitForTimeout(200);
    return await getScrollTop(conversation) === previousScrollTop;
  }).toBe(true);

  return { badge, cloud: page.locator(CLOUD_SELECTOR), conversation };
}

async function routeRatedLongAnswer(page: Page) {
  const thread = {
    id: THREAD_ID,
    revision: 1,
    createdAt: CREATED_AT,
    updatedAt: CREATED_AT,
    lastActivityAt: CREATED_AT,
    messageCount: MESSAGES.length,
    title: 'A long rated answer',
  };
  await page.route('**/api/v2/threads?*', (route) => route.fulfill({
    json: { protocolVersion: 3, threads: [{ thread }] },
  }));
  await page.route(`**/api/v2/threads/${THREAD_ID}/messages?*`, (route) => route.fulfill({
    json: {
      protocolVersion: 3,
      thread,
      messages: MESSAGES.map(({ text, ...message }, index) => ({
        ...message,
        id: `00000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
        threadId: THREAD_ID,
        createdAt: CREATED_AT,
        status: 'complete',
        content: { kind: 'markdown', text },
      })),
    },
  }));
  await page.route(`**/api/v2/threads/${THREAD_ID}/messages/*/feedback`, (route) => {
    // The server answers a withdrawal without a rating
    const { feedback } = route.request().postDataJSON() as { feedback?: string };
    return route.fulfill({ json: { protocolVersion: 3, ...(feedback ? { feedback } : undefined) } });
  });
}

// Scrolls the chat at once, past its smooth scrolling, so that the long answer's top is at `top` of the window, as near
// as the chat goes
function placeAnswerTop(conversation: Locator, top: number) {
  return conversation.evaluate((element, { answerSelector, bubbleSelector, targetTop }) => {
    const bubble = Array.from(element.querySelectorAll(answerSelector)).at(-1)!.querySelector(bubbleSelector)!;
    element.style.scrollBehavior = 'auto';
    element.scrollTop += bubble.getBoundingClientRect().top - targetTop;
    element.style.scrollBehavior = '';
    return bubble.getBoundingClientRect().top;
  }, { answerSelector: ANSWER_SELECTOR, bubbleSelector: BUBBLE_SELECTOR, targetTop: top });
}

// Scrolls the chat at once to its end, where the long answer's bottom and its corner are on the screen
function placeAnswerBottom(conversation: Locator) {
  return conversation.evaluate((element) => {
    element.style.scrollBehavior = 'auto';
    element.scrollTop = element.scrollHeight;
    element.style.scrollBehavior = '';
  });
}

function getScrollTop(locator: Locator) {
  return locator.evaluate((element) => element.scrollTop);
}

function getTop(locator: Locator) {
  return locator.evaluate((element) => element.getBoundingClientRect().top);
}

// Where the long answer's bubble stands in the chat's content, whichever way the chat is scrolled
function getLastAnswerOffset(conversation: Locator) {
  return conversation.evaluate((element, { answerSelector, bubbleSelector }) => {
    const bubble = Array.from(element.querySelectorAll(answerSelector)).at(-1)!.querySelector(bubbleSelector)!;
    return bubble.getBoundingClientRect().top - element.getBoundingClientRect().top + element.scrollTop;
  }, { answerSelector: ANSWER_SELECTOR, bubbleSelector: BUBBLE_SELECTOR });
}

// The room between the answer's bubble and the message over it
function getGapOver(answer: Locator) {
  return answer.evaluate((element, bubbleSelector) => {
    const message = element.closest('[data-agent-v2-message-id]')!;
    const previous = message.previousElementSibling!.querySelector(bubbleSelector)!;
    return element.querySelector(bubbleSelector)!.getBoundingClientRect().top - previous.getBoundingClientRect().bottom;
  }, BUBBLE_SELECTOR);
}

// How much of the corner's emoji, as drawn in its frame, lies over the lines of its answer's text
function getTextOverlap(badge: Locator) {
  return badge.evaluate((element, { bubbleSelector, emojiSize }) => {
    const frame = element.getBoundingClientRect();
    const inset = (frame.width - emojiSize) / 2;
    const emoji = {
      left: frame.left + inset, right: frame.right - inset, top: frame.top + inset, bottom: frame.bottom - inset,
    };
    const text = element.closest('[data-agent-v2-message-id]')!.querySelector('[data-agent-static-text]')
      ?? element.closest(bubbleSelector)!;
    const walker = document.createTreeWalker(text, NodeFilter.SHOW_TEXT);
    const lines: DOMRect[] = [];
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const range = document.createRange();
      range.selectNodeContents(node);
      lines.push(...Array.from(range.getClientRects()));
    }
    return lines.reduce((overlap, line) => {
      const width = Math.min(line.right, emoji.right) - Math.max(line.left, emoji.left);
      const height = Math.min(line.bottom, emoji.bottom) - Math.max(line.top, emoji.top);
      return overlap + (width > 0 && height > 0 ? width * height : 0);
    }, 0);
  }, { bubbleSelector: BUBBLE_SELECTOR, emojiSize: BADGE_EMOJI_SIZE });
}

// Where a toast's animated icon and the first line of its text are centred, and how many lines the text takes
function getToastLayout(content: Locator) {
  return content.evaluate((element, iconFrameSelector) => {
    // The message, past the empty text nodes that stand for the toast's absent parts
    const text = Array.from(element.childNodes)
      .find((node) => node.nodeType === Node.TEXT_NODE && node.textContent!.trim())!;
    const range = document.createRange();
    range.selectNodeContents(text);
    const lines = Array.from(range.getClientRects());
    const icon = element.querySelector(iconFrameSelector)!.getBoundingClientRect();
    return {
      iconCenter: icon.top + icon.height / 2,
      lineCenter: lines[0].top + lines[0].height / 2,
      lineCount: new Set(lines.map(({ top }) => Math.round(top))).size,
    };
  }, TOAST_ICON_FRAME_SELECTOR);
}

function getRect(locator: Locator) {
  return locator.evaluate((element) => {
    const { left, top, width, height } = element.getBoundingClientRect();
    return { left, top, width, height };
  });
}

function getCenteredRect(rect: Rect, size: number): Rect {
  return {
    left: rect.left + (rect.width - size) / 2, top: rect.top + (rect.height - size) / 2, width: size, height: size,
  };
}

function getCornerRect(bubble: Rect): Rect {
  return {
    left: bubble.left + bubble.width - BADGE_INSET - BADGE_SIZE / 2,
    top: bubble.top + bubble.height + BADGE_DROP - BADGE_SIZE,
    width: BADGE_SIZE,
    height: BADGE_SIZE,
  };
}

function getCenter({ left, top, width, height }: Rect): Point {
  return { x: left + width / 2, y: top + height / 2 };
}

// Telegram's parabola through the start, the point halfway across 30 px over it, and the end, at `progress` across
function getParabolaY(from: Point, to: Point, progress: number) {
  const middleY = from.y - FLIGHT_ELEVATION;
  return from.y * (1 - progress) * (1 - 2 * progress)
    + middleY * 4 * progress * (1 - progress)
    + to.y * progress * (2 * progress - 1);
}

// The answer shows its reaction: its emoji, a picture or an animation, is visible
function getIsBadgeShown(badge: Locator) {
  return badge.evaluate((element, iconSelector) => {
    const icons = Array.from(element.querySelectorAll(iconSelector));
    return Number(getComputedStyle(element).opacity) > 0
      && icons.some((icon) => getComputedStyle(icon).visibility === 'visible');
  }, ICON_SELECTOR);
}

function getSelectionCircle(button: Locator) {
  return button.evaluate((element) => {
    const {
      backgroundColor, width, opacity, transform,
    } = getComputedStyle(element, '::before');
    return {
      color: backgroundColor, size: parseFloat(width), opacity, transform,
    };
  });
}

// A canvas of Telegram's animation in the element has drawn a frame
function getHasDrawn(locator: Locator) {
  return locator.evaluate((element) => Array.from(element.querySelectorAll('canvas')).some((canvas) => {
    const { data } = canvas.getContext('2d')!.getImageData(0, 0, canvas.width, canvas.height);
    return data.some((value, index) => index % 4 === 3 && value > 0);
  }));
}

// The element is the one drawn at its centre, or this far under it
function getIsOnTop(locator: Locator, offsetY = 0) {
  return locator.evaluate((element, offset) => {
    const rect = element.getBoundingClientRect();
    return element.contains(document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2 + offset));
  }, offsetY);
}

function expectRect(actual: Rect, expected: Rect, tolerance = RECT_TOLERANCE) {
  expect(Math.abs(actual.left - expected.left)).toBeLessThan(tolerance);
  expect(Math.abs(actual.top - expected.top)).toBeLessThan(tolerance);
  expect(Math.abs(actual.width - expected.width)).toBeLessThan(tolerance);
  expect(Math.abs(actual.height - expected.height)).toBeLessThan(tolerance);
}

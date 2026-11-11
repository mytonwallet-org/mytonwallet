import type { Page } from '@playwright/test';

import { expect } from './fixtures';

const THREAD_ID = '88888888-8888-4888-8888-888888888888';
export const CREATED_AT = '2026-08-11T09:00:00.000Z';
export const BUBBLE_SELECTOR = '[class*="__bubble__"]';
// The history morph is recorded for at least its own length. Recording then goes on until the follow-ups that stagger
// in after the morph are fully shown, which a slow runner reaches later.
const HISTORY_MORPH_MIN_RECORDING_MS = 1000;
const HISTORY_MORPH_MAX_RECORDING_MS = 3000;
export const FOLLOWUPS = Array.from({ length: 3 }, (_, index) => ({
  id: `adadadad-adad-4dad-8dad-adadadadada${index}`,
  kind: 'suggested_prompt',
  text: `Explain this update ${index}`,
}));
export const STORED_MESSAGES = [
  { role: 'assistant', text: 'The first stored answer.' },
  { role: 'user', text: 'Please explain the next part of this conversation.' },
  { role: 'assistant', text: 'The first part of the explanation.\n\nThere is another paragraph here.' },
  { role: 'assistant', text: 'The second part of the explanation is a separate message.' },
];
// Questions far narrower than the placeholders they grow out of
export const SHORT_QUESTION_MESSAGES = [
  { role: 'user', text: 'ok' },
  { role: 'assistant', text: 'The first stored answer, which runs over a couple of lines as answers do.' },
  { role: 'user', text: 'test' },
  { role: 'assistant', text: 'The latest stored answer.' },
];
// Two questions in a row, of which the chat's list row counts the last two messages only
const CONSECUTIVE_QUESTION_MESSAGES = [
  { role: 'assistant', text: 'The first stored answer.' },
  { role: 'user', text: 'A first question.' },
  { role: 'user', text: 'And a second one, sent right after it.' },
  { role: 'assistant', text: 'The answer to both of them.' },
];
export const CONSECUTIVE_QUESTIONS_LISTED_COUNT = 2;
// One-line answers and questions of a letter or two, more than the chat's list row counts and than the list holds
const SHORT_LINE_MESSAGES = Array.from({ length: 10 }, (_, index) => [
  { role: 'user', text: ['дд', 'пп', 'a', 'ok'][index % 4] },
  { role: 'assistant', text: ['Да, конечно.', 'Понятно.', 'A short answer.', 'Another short one.'][index % 4] },
]).flat();
const SHORT_LINES_LISTED_COUNT = 4;
// A placeholder made up for a message beyond the placeholders shown: as tall as this and as far from its sender's side,
// and no wider than this share of the list
const MADE_UP_PLACEHOLDER_HEIGHT = 184;
export const MADE_UP_PLACEHOLDER_INSET = 16;
const MADE_UP_PLACEHOLDER_WIDTH_SHARE = 0.86;
// The most of its way a bubble growing out of a placeholder moves from one frame to the next
const MAX_MORPH_STEP_SHARE = 0.35;
const NOMINAL_FRAME_MS = 1000 / 60;
// A stand-in's tail and its bubble's may differ by a layout unit or so, never by a visible amount
const TAIL_SIZE_TOLERANCE_PX = 0.05;

export async function delayStoredHistory(
  page: Page,
  scenario: 'stored' | 'shortQuestions' | 'consecutiveQuestions' | 'shortLines' | 'newsOnly' | 'newsQuestion',
) {
  const isNews = scenario === 'newsOnly' || scenario === 'newsQuestion';
  const newsPost = {
    role: 'assistant', text: 'A single saved news post.\n\nThis is the full news body.', newsPost: true,
  };
  const newsQuestion = { role: 'user', text: 'What does this news mean for me?' };
  const messages = scenario === 'stored' ? STORED_MESSAGES
    : scenario === 'shortQuestions' ? SHORT_QUESTION_MESSAGES
      : scenario === 'consecutiveQuestions' ? CONSECUTIVE_QUESTION_MESSAGES
        : scenario === 'shortLines' ? SHORT_LINE_MESSAGES
          : [newsPost, ...(scenario === 'newsQuestion' ? [newsQuestion] : [])];
  const thread = {
    id: THREAD_ID,
    revision: 1,
    createdAt: CREATED_AT,
    updatedAt: CREATED_AT,
    lastActivityAt: CREATED_AT,
    messageCount: messages.length,
    title: 'Stored animation test conversation',
    ...(isNews && {
      news: {
        eventId: 5,
        headline: 'A single saved news post',
        body: 'This is the full news body.',
        publishedAt: CREATED_AT,
      },
    }),
  };
  // The list leaves out a discussion the user hasn't written in, so the listed row counts a question that this history
  // page, holding the post alone, leaves out
  const listedMessageCount = scenario === 'newsOnly' ? messages.length + 1
    : scenario === 'consecutiveQuestions' ? CONSECUTIVE_QUESTIONS_LISTED_COUNT
      : scenario === 'shortLines' ? SHORT_LINES_LISTED_COUNT : messages.length;
  const listedThread = { ...thread, messageCount: listedMessageCount };
  await page.route('**/api/v2/threads?*', (route) => route.fulfill({
    json: { protocolVersion: 3, threads: [{ thread: listedThread }] },
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
        ...(index === messages.length - 1 && message.role === 'assistant' && { followups: FOLLOWUPS }),
      })),
    } });
  });
  return releaseHistory;
}

// The placeholders' outlines as they stand, from the composer up
export function measurePlaceholders(page: Page) {
  return page.locator('[data-agent-conversation] [data-agent-skeleton-role]').evaluateAll((elements) => (
    elements.map((element) => {
      const {
        left, right, top, bottom,
      } = element.getBoundingClientRect();
      return {
        role: element.getAttribute('data-agent-skeleton-role'), left, right, top, bottom,
      };
    })
  ));
}

// The placeholders as they stand once the screen has slid in: still over three frames
export async function waitForPlaceholdersSettled(page: Page) {
  await page.evaluate(async () => {
    let previous = '';
    let stillFrames = 0;
    for (let frame = 0; frame < 300 && stillFrames < 3; frame++) {
      await new Promise(requestAnimationFrame);
      const placeholders = document.querySelectorAll('[data-agent-conversation] [data-agent-skeleton-role]');
      const rects = JSON.stringify(Array.from(placeholders, (element) => {
        const {
          left, right, top, bottom,
        } = element.getBoundingClientRect();
        return [left, right, top, bottom];
      }));
      stillFrames = rects === previous ? stillFrames + 1 : 0;
      previous = rects;
    }
  });
}

/**
 * Checks what every way of revealing the history keeps to: something is on screen in each frame, no placeholder moves
 * down, each bubble grows out of a placeholder, whoever's it was, or out of one made up in its sender's place above
 * them, the list never gains a horizontal scrollbar, and the messages keep their places in the list throughout and on
 * screen once nothing grows.
 */
export function assertCalmReveal(
  frames: Awaited<ReturnType<typeof recordHistoryMorph>>,
  placeholders: Awaited<ReturnType<typeof measurePlaceholders>>,
) {
  const end = frames.at(-1)!;
  for (const frame of frames) {
    const details = JSON.stringify(frame);
    expect(frame.surfaces.length, details).toBeGreaterThan(0);
    expect(frame.placeholderCount, details).toBeLessThanOrEqual(placeholders.length);
    expect(frame.isHorizontallyScrollable, details).toBe(false);
    expect(frame.clientHeight, details).toBe(frames[0].clientHeight);
    for (const surface of frame.surfaces.filter(({ index }) => index < 0)) {
      const shown = placeholders[Number(surface.id.split(':')[1])];
      expect(surface.top, details).toBeLessThanOrEqual(Math.max(shown.top, frame.list.top) + 1);
    }
    for (const { id, top } of frame.layoutTops) {
      const settled = end.layoutTops.find((layout) => layout.id === id)!;
      expect(Math.abs(top - settled.top), details).toBeLessThan(1);
    }
  }

  const morphingIndexes = frames.flatMap(({ morphingCount }, index) => (morphingCount > 0 ? [index] : []));
  for (const frame of frames.slice((morphingIndexes.at(-1) ?? -1) + 1)) {
    for (const surface of frame.surfaces.filter(({ index }) => index >= 0)) {
      const settled = end.surfaces.find(({ id }) => id === surface.id)!;
      expect(Math.abs(surface.top - settled.top), JSON.stringify(frame)).toBeLessThan(1);
    }
  }

  const placeholdersTop = Math.min(...placeholders.map(({ top }) => top));
  for (const { role, rect } of getMorphSourceRects(frames)) {
    const details = JSON.stringify({ role, rect, placeholders, list: end.list });
    if (placeholders.some((placeholder) => getIsSameRect(placeholder, rect))) continue;

    // Made up in its sender's place over all the placeholders, out of sight over the list's top
    expect(Math.abs(rect.bottom - rect.top - MADE_UP_PLACEHOLDER_HEIGHT), details).toBeLessThan(2);
    expect(rect.right - rect.left, details)
      .toBeLessThanOrEqual((end.list.contentRight - end.list.left) * MADE_UP_PLACEHOLDER_WIDTH_SHARE + 1);
    expect(rect.bottom, details).toBeLessThanOrEqual(Math.min(placeholdersTop, end.list.top) + 1);
    const inset = role === 'user' ? end.list.contentRight - rect.right : rect.left - end.list.left;
    expect(Math.abs(inset - MADE_UP_PLACEHOLDER_INSET), details).toBeLessThan(2);
  }
}

// Every message on screen grows out of a placeholder or a made-up one, without fading in where it stands
export function assertWholeMorph(frames: Awaited<ReturnType<typeof recordHistoryMorph>>) {
  const morphedIds = new Set(frames.flatMap(({ morphSources }) => morphSources.map(({ id }) => id)));
  const onScreenIds = frames.at(-1)!.surfaces.filter(({ index }) => index >= 0).map(({ id }) => id);
  expect(onScreenIds.length).toBeGreaterThan(0);
  expect(onScreenIds.filter((id) => !morphedIds.has(id)), JSON.stringify(frames)).toEqual([]);
  for (const frame of frames) {
    for (const surface of frame.surfaces.filter(({ index }) => index >= 0)) {
      expect(surface.opacity, JSON.stringify(frame)).toBeGreaterThan(0.95);
    }
  }
}

// Whether two rectangles stand in the same place, to within the 2 px their layouts round to
export function getIsSameRect(
  first: { left: number; right: number; top: number; bottom: number },
  second: { left: number; right: number; top: number; bottom: number },
) {
  return Math.abs(first.left - second.left) < 2 && Math.abs(first.right - second.right) < 2
    && Math.abs(first.top - second.top) < 2 && Math.abs(first.bottom - second.bottom) < 2;
}

// The rectangle each bubble grows out of, from its first recorded growth, with its sender
export function getMorphSourceRects(frames: Awaited<ReturnType<typeof recordHistoryMorph>>) {
  const sources = new Map<string, (typeof frames)[number]['morphSources'][number]>();
  frames.forEach(({ morphSources }) => morphSources.forEach((source) => {
    if (!sources.has(source.id)) sources.set(source.id, source);
  }));

  return Array.from(sources.values(), ({ id, role, current }) => ({ id, role, rect: current }));
}

/**
 * The reveal starts on screen from the placeholders as they showed: each stand-in shows first over the placeholder it
 * takes, or out of sight over the list, and then moves no more than `MAX_MORPH_STEP_SHARE` of its way in a frame's time,
 * rather than jumping on after a long first frame
 */
export function assertGradualMorph(
  frames: Awaited<ReturnType<typeof recordHistoryMorph>>,
  placeholders: Awaited<ReturnType<typeof measurePlaceholders>>,
) {
  const edges = ['left', 'top', 'right', 'bottom'] as const;
  const getDistance = (first: Record<typeof edges[number], number>, second: Record<typeof edges[number], number>) => (
    Math.max(...edges.map((edge) => Math.abs(first[edge] - second[edge])))
  );
  const samplesById = new Map<string, { time: number; morph: (typeof frames)[number]['morphSources'][number] }[]>();
  frames.forEach(({ time, morphSources }) => morphSources.forEach((morph) => {
    samplesById.set(morph.id, [...(samplesById.get(morph.id) ?? []), { time, morph }]);
  }));
  expect(samplesById.size).toBeGreaterThan(0);
  for (const samples of samplesById.values()) {
    const details = JSON.stringify(samples);
    const [{ morph: first }] = samples;
    const placeholder = placeholders.find((shown) => getIsSameRect(shown, first.current));
    if (!placeholder) {
      expect(first.current.bottom, details).toBeLessThanOrEqual(frames[0].list.top + 1);
    }
    const travel = getDistance(first.current, samples.at(-1)!.morph.bubbleRect);
    samples.slice(1).forEach(({ time, morph }, index) => {
      // The first frame holds the stand-in however long it takes to draw. After it the stand-in follows the clock, so a
      // frame drawn late carries it as much further.
      const frameCount = index === 0 ? 1 : Math.max(1, (time - samples[index].time) / NOMINAL_FRAME_MS);
      expect(getDistance(morph.current, samples[index].morph.current), details)
        .toBeLessThanOrEqual(Math.min(travel, travel * MAX_MORPH_STEP_SHARE * frameCount) + 1);
    });
  }
}

/**
 * The stand-ins land on their bubbles where those stand, whatever moves the list meanwhile: each stays inside the
 * list's content, a bubble's contents show only inside its stand-in, each stands on its bubble over its last frames,
 * and the bubble takes over where its stand-in stood
 */
export function assertLanding(frames: Awaited<ReturnType<typeof recordHistoryMorph>>) {
  const edges = ['left', 'top', 'right', 'bottom'] as const;
  const ids = new Set(frames.flatMap(({ morphSources }) => morphSources.map(({ id }) => id)));
  expect(ids.size).toBeGreaterThan(0);
  for (const id of ids) {
    const indexes = frames.flatMap(({ morphSources }, index) => (
      morphSources.some((morph) => morph.id === id) ? [index] : []
    ));
    const samples = indexes.map((index) => frames[index].morphSources.find((morph) => morph.id === id)!);
    const details = JSON.stringify(samples);
    samples.forEach((sample, index) => {
      const { list } = frames[indexes[index]];
      expect(sample.current.left, details).toBeGreaterThanOrEqual(list.left - 1);
      expect(sample.current.right, details).toBeLessThanOrEqual(list.contentRight + 1);
      if (sample.contentOpacity <= 0.1) return;
      expect(sample.contentRect.left, details).toBeGreaterThanOrEqual(sample.current.left - 1);
      expect(sample.contentRect.top, details).toBeGreaterThanOrEqual(sample.current.top - 1);
      expect(sample.contentRect.right, details).toBeLessThanOrEqual(sample.current.right + 1);
      expect(sample.contentRect.bottom, details).toBeLessThanOrEqual(sample.current.bottom + 1);
    });
    // The stand-ins hold their bubbles' rectangles for three frames, of which a loaded runner can record two
    for (const sample of samples.slice(-2)) {
      for (const edge of edges) {
        expect(Math.abs(sample.current[edge] - sample.bubbleRect[edge]), details).toBeLessThanOrEqual(1);
      }
    }
    const handover = frames[indexes.at(-1)! + 1];
    const settled = handover?.bubbleRects.find((rect) => rect.id === id);
    expect(settled, details).toBeDefined();
    for (const edge of edges) {
      expect(Math.abs(settled![edge] - samples.at(-1)!.current[edge]), JSON.stringify({ settled, details }))
        .toBeLessThanOrEqual(1);
    }
  }
}

/**
 * Each bubble keeps its shape as it grows: its stand-in only moves, its corners keep their size in screen pixels, on
 * their way from the placeholder's to the bubble's where those differ, its tail keeps its size and takes its fill on
 * every frame, and the bubble itself is not scaled
 */
export function assertShapeKept(frames: Awaited<ReturnType<typeof recordHistoryMorph>>) {
  const shapesById = new Map<string, (typeof frames)[number]['morphSources'][number]['shape'][]>();
  frames.forEach(({ morphSources }) => morphSources.forEach(({ id, shape }) => {
    shapesById.set(id, [...(shapesById.get(id) ?? []), shape]);
  }));
  expect(shapesById.size).toBeGreaterThan(0);
  for (const shapes of shapesById.values()) {
    const [first] = shapes;
    for (const shape of shapes) {
      const details = JSON.stringify(shape);
      shape.radii.forEach((radius, index) => {
        const bounds = [Number.parseFloat(first.radii[index]), Number.parseFloat(shape.bubbleRadii[index])];
        expect(Number.parseFloat(radius), details).toBeGreaterThanOrEqual(Math.min(...bounds) - 0.5);
        expect(Number.parseFloat(radius), details).toBeLessThanOrEqual(Math.max(...bounds) + 0.5);
      });
      const [scaleX, skewY, skewX, scaleY] = shape.transform.match(/^matrix\(([^)]+)\)$/u)![1].split(',').map(Number);
      expect([scaleX, skewY, skewX, scaleY], details).toEqual([1, 0, 0, 1]);
      expect(shape.bubbleTransform, details).toBe('none');
      // Within the browser's layout unit, a 64th of a pixel, as the tail's height is a fraction of a rem
      expect(Math.abs(parseFloat(shape.tail.width) - parseFloat(shape.bubbleTail.width)), details)
        .toBeLessThanOrEqual(TAIL_SIZE_TOLERANCE_PX);
      expect(Math.abs(parseFloat(shape.tail.height) - parseFloat(shape.bubbleTail.height)), details)
        .toBeLessThanOrEqual(TAIL_SIZE_TOLERANCE_PX);
      expect(shape.tail.color, details).toBe(shape.color);
    }
  }
}

export function recordHistoryMorph(page: Page) {
  return page.evaluate(async ({ bubbleSelector, minDuration, maxDuration }) => {
    const frames = [];
    const startedAt = performance.now();
    let areFollowupsShown = false;
    while (getElapsed() < maxDuration && (getElapsed() < minDuration || !areFollowupsShown)) {
      await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
      const host = Array.from(document.querySelectorAll<HTMLElement>('[data-agent-conversation]')).at(-1)!;
      const scroll = host.querySelector<HTMLElement>('.custom-scroll')!;
      const scrollStyle = getComputedStyle(scroll);
      const visibleRect = scroll.getBoundingClientRect();
      const messages = Array.from(host.querySelectorAll<HTMLElement>('[data-agent-v2-message-role]'));
      const bubbles = messages.flatMap((message, index) => {
        const bubble = message.querySelector<HTMLElement>(bubbleSelector);
        const role = message.dataset.agentV2MessageRole === 'user' ? 'user' : 'assistant';
        return bubble ? [{
          element: bubble, id: `message:${index}`, index, role,
        }] : [];
      });
      const placeholders = Array.from(host.querySelectorAll<HTMLElement>('[data-agent-skeleton-role]'))
        .map((element, index) => ({ element, id: `placeholder:${index}`, index: -1 }));
      // The stand-ins the bubbles grow through, each where it stands against its bubble, what of the bubble's contents
      // shows and how much, and its shape against the bubble's own
      const standIns = Array.from(host.querySelectorAll<HTMLElement>('[data-agent-history-stand-in]'));
      const morphs = standIns.flatMap((standIn) => {
        const bubbleElement = host.querySelector<HTMLElement>(
          `[data-agent-history-reveal-index="${standIn.dataset.agentHistoryStandIn}"]`,
        );
        const bubble = bubbles.find(({ element }) => element === bubbleElement);
        if (!bubble) return [];

        const standInStyle = getComputedStyle(standIn);
        const bubbleStyle = getComputedStyle(bubble.element);
        const tailStyle = getComputedStyle(standIn.firstElementChild!);
        const bubbleTailStyle = getComputedStyle(bubble.element, '::after');
        const getRadii = (style: CSSStyleDeclaration) => [
          style.borderTopLeftRadius,
          style.borderTopRightRadius,
          style.borderBottomRightRadius,
          style.borderBottomLeftRadius,
        ];
        const getEdges = (rect: DOMRect) => ({
          left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom,
        });
        const bubbleRect = getEdges(bubble.element.getBoundingClientRect());
        // The part of the bubble its contents show in
        const insets = bubbleStyle.clipPath.match(/^inset\(([^)]+)\)$/u)?.[1].split(' ').map(Number.parseFloat);
        const [clipTop, clipRight = clipTop, clipBottom = clipTop, clipLeft = clipRight] = insets ?? [0];
        return [{
          id: bubble.id,
          role: bubble.role,
          current: getEdges(standIn.getBoundingClientRect()),
          bubbleRect,
          contentRect: {
            left: bubbleRect.left + clipLeft,
            top: bubbleRect.top + clipTop,
            right: bubbleRect.right - clipRight,
            bottom: bubbleRect.bottom - clipBottom,
          },
          contentOpacity: Math.max(0, ...Array.from(bubble.element.children, (child) => (
            Number(getComputedStyle(child).opacity)
          ))),
          shape: {
            radii: getRadii(standInStyle),
            bubbleRadii: getRadii(bubbleStyle),
            transform: standInStyle.transform,
            bubbleTransform: bubbleStyle.transform,
            color: standInStyle.backgroundColor,
            tail: { width: tailStyle.width, height: tailStyle.height, color: tailStyle.backgroundColor },
            bubbleTail: { width: bubbleTailStyle.width, height: bubbleTailStyle.height },
          },
        }];
      });
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
        time: performance.now() - startedAt,
        morphingCount: new Set(morphs.map(({ id }) => id)).size,
        morphSources: morphs,
        placeholderCount: surfaces.filter(({ index }) => index < 0).length,
        isHorizontallyScrollable: ['auto', 'scroll'].includes(scrollStyle.overflowX)
          && scroll.scrollWidth > scroll.clientWidth,
        clientHeight: scroll.clientHeight,
        list: {
          left: visibleRect.left,
          right: visibleRect.right,
          top: visibleRect.top,
          bottom: visibleRect.bottom,
          // Where the list's content ends, before its scrollbar
          contentRight: visibleRect.left + scroll.clientLeft + scroll.clientWidth,
          scrollbarWidth: scroll.offsetWidth - scroll.clientWidth,
          isScrollable: scroll.scrollHeight > scroll.clientHeight,
        },
        // Where each message stands in the list, apart from how its bubble grows
        layoutTops: scrollStyle.visibility === 'hidden' ? [] : messages.map((message, index) => ({
          id: `message:${index}`, top: message.getBoundingClientRect().top,
        })),
        bubbleRects: bubbles.map(({ element, id }) => {
          const {
            left, right, top, bottom,
          } = element.getBoundingClientRect();
          return {
            id, left, right, top, bottom,
          };
        }),
        surfaces,
        overlaps,
        isMessageOrderPreserved,
        followupOpacities,
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

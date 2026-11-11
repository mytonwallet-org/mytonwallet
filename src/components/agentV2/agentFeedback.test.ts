import {
  getAgentFeedbackBadgeCenter,
  getAgentFeedbackCloudLayout,
  getAgentFeedbackParabolaPoint,
} from './agentFeedback';

// The design's "Incoming Message Menu": a 402 px wide screen with the lifted answer at 16, 219, 327 × 227
const VIEWPORT = { width: 402, height: 874, safeAreaTop: 0 };
const BUBBLE = {
  left: 16, right: 343, top: 219, bottom: 446,
};

describe('getAgentFeedbackCloudLayout', () => {
  it('puts the cloud over the answer as the design does, its tail beside the bubble\'s top trailing corner', () => {
    // The design's "Feedback Pill" is at 282, 157, with its dots' centres at 65, 56 and 74, 70
    expect(getAgentFeedbackCloudLayout(BUBBLE, BUBBLE.bottom, VIEWPORT, false)).toEqual({
      left: 282,
      top: 157,
      largeDotX: 65,
      largeDotY: 56,
      smallDotX: 74,
      smallDotY: 70,
      isBelow: false,
    });
  });

  it('mirrors the cloud over an answer on the right in a right-to-left language', () => {
    const bubble = { ...BUBBLE, left: VIEWPORT.width - BUBBLE.right, right: VIEWPORT.width - BUBBLE.left };

    expect(getAgentFeedbackCloudLayout(bubble, bubble.bottom, VIEWPORT, true)).toEqual({
      left: VIEWPORT.width - 282 - 108,
      top: 157,
      largeDotX: 108 - 65,
      largeDotY: 56,
      smallDotX: 108 - 74,
      smallDotY: 70,
      isBelow: false,
    });
  });

  it('moves the capsule in from the side of the screen, leaving the tail at the bubble\'s corner', () => {
    const bubble = { ...BUBBLE, right: 380 };
    const layout = getAgentFeedbackCloudLayout(bubble, bubble.bottom, VIEWPORT, false);

    expect(layout.left).toBe(VIEWPORT.width - 12 - 108);
    expect(layout.left + layout.largeDotX).toBe(bubble.right + 4);
    expect(layout.left + layout.smallDotX).toBe(bubble.right + 13);

    const rtlBubble = { ...BUBBLE, left: 22 };
    const rtlLayout = getAgentFeedbackCloudLayout(rtlBubble, rtlBubble.bottom, VIEWPORT, true);
    expect(rtlLayout.left).toBe(12);
    expect(rtlLayout.left + rtlLayout.largeDotX).toBe(rtlBubble.left - 4);
  });

  it('puts the tail under the capsule, as in the design, where the bubble\'s corner is near the screen\'s side', () => {
    // A wide answer that ends 12 px from the side, where the 8 px dot beside its corner would cross the side
    const bubble = { ...BUBBLE, right: VIEWPORT.width - 12 };
    expect(getAgentFeedbackCloudLayout(bubble, bubble.bottom, VIEWPORT, false)).toEqual({
      left: VIEWPORT.width - 12 - 108,
      top: 157,
      largeDotX: 65,
      largeDotY: 56,
      smallDotX: 74,
      smallDotY: 70,
      isBelow: false,
    });

    const rtlBubble = { ...BUBBLE, left: 12, right: VIEWPORT.width - 16 };
    expect(getAgentFeedbackCloudLayout(rtlBubble, rtlBubble.bottom, VIEWPORT, true)).toEqual({
      left: 12,
      top: 157,
      largeDotX: 108 - 65,
      largeDotY: 56,
      smallDotX: 108 - 74,
      smallDotY: 70,
      isBelow: false,
    });
  });

  it('keeps the tail at the bubble\'s corner while the 8 px dot is at least 4 px from the side of the screen', () => {
    // The dot's outer edge is 17 px past the bubble's trailing edge
    const bubbleAtLimit = { ...BUBBLE, right: VIEWPORT.width - 21 };
    const atLimit = getAgentFeedbackCloudLayout(bubbleAtLimit, bubbleAtLimit.bottom, VIEWPORT, false);
    expect(atLimit.left + atLimit.smallDotX).toBe(bubbleAtLimit.right + 13);
    const bubblePastLimit = { ...BUBBLE, right: VIEWPORT.width - 20 };
    expect(getAgentFeedbackCloudLayout(bubblePastLimit, bubblePastLimit.bottom, VIEWPORT, false).smallDotX).toBe(74);

    const rtlBubbleAtLimit = { ...BUBBLE, left: 21 };
    const rtlAtLimit = getAgentFeedbackCloudLayout(rtlBubbleAtLimit, rtlBubbleAtLimit.bottom, VIEWPORT, true);
    expect(rtlAtLimit.left + rtlAtLimit.smallDotX).toBe(rtlBubbleAtLimit.left - 13);
    const rtlBubblePastLimit = { ...BUBBLE, left: 20 };
    expect(getAgentFeedbackCloudLayout(rtlBubblePastLimit, rtlBubblePastLimit.bottom, VIEWPORT, true).smallDotX)
      .toBe(108 - 74);
  });

  it('puts the tail under the capsule where its 16 px dot beside the corner would be off the capsule', () => {
    // A bubble whose trailing edge is so near the leading side of the screen that the capsule stops 12 px from it
    const bubble = { ...BUBBLE, left: -300, right: 6 };
    expect(getAgentFeedbackCloudLayout(bubble, bubble.bottom, VIEWPORT, false)).toMatchObject({
      left: 12,
      largeDotX: 65,
      smallDotX: 74,
    });
  });

  it('pins the cloud over a long answer to the top of the screen until the answer\'s top comes down', () => {
    // An answer taller than the screen, with its top at each of these places as the chat scrolls and its bottom out of
    // sight
    [-1200, -62, 0, 73, 74, 75, 300].forEach((messageTop) => {
      const bubble = { ...BUBBLE, right: VIEWPORT.width - 12, top: messageTop, bottom: messageTop + 3000 };

      expect(getAgentFeedbackCloudLayout(bubble, bubble.bottom, VIEWPORT, false)).toEqual({
        left: 282,
        top: Math.max(12, messageTop - 6 - 56),
        // The tail keeps its place under the capsule, over the answer
        largeDotX: 65,
        largeDotY: 56,
        smallDotX: 74,
        smallDotY: 70,
        isBelow: false,
      });
    });

    // The system's bar at the top lowers the place it is pinned to
    const bubble = { ...BUBBLE, top: -500, bottom: 1500 };
    expect(getAgentFeedbackCloudLayout(bubble, bubble.bottom, { ...VIEWPORT, safeAreaTop: 47 }, false).top)
      .toBe(47 + 12);
  });

  it('hangs the cloud under the message, never over the bubble, when there is no room above it', () => {
    const bubble = { ...BUBBLE, top: 40, bottom: 300 };
    // The action buttons hang from the bubble down to 360
    const layout = getAgentFeedbackCloudLayout(bubble, 360, VIEWPORT, false);

    expect(layout).toEqual({
      left: 282,
      top: 366,
      largeDotX: 65,
      largeDotY: 0,
      smallDotX: 74,
      smallDotY: -14,
      isBelow: true,
    });
    // The system's bar at the top takes room from above the bubble too
    expect(getAgentFeedbackCloudLayout(BUBBLE, BUBBLE.bottom, { ...VIEWPORT, safeAreaTop: 160 }, false).isBelow)
      .toBe(true);
  });

  it('keeps the cloud at the top of the screen when there is room neither above nor under the message', () => {
    const bubble = { ...BUBBLE, top: 40, bottom: 850 };

    expect(getAgentFeedbackCloudLayout(bubble, bubble.bottom, VIEWPORT, false)).toMatchObject({
      top: 12,
      isBelow: false,
    });
  });
});

describe('getAgentFeedbackBadgeCenter', () => {
  it('centres the 22 px emoji 3 px inside the bubble\'s trailing edge, its bottom 3 px under the bubble\'s', () => {
    expect(getAgentFeedbackBadgeCenter(BUBBLE, false)).toEqual({ x: 343 - 3, y: 446 + 3 - 11 });
    expect(getAgentFeedbackBadgeCenter(BUBBLE, true)).toEqual({ x: 16 + 3, y: 446 + 3 - 11 });
  });
});

describe('getAgentFeedbackParabolaPoint', () => {
  const FROM = { x: 300, y: 180 };
  const TO = { x: 343, y: 439 };

  it('passes through the start, 30 px over it halfway across, and the end, as Telegram\'s keyframes do', () => {
    expect(getAgentFeedbackParabolaPoint(FROM, TO, 30, 0)).toEqual(FROM);
    expect(getAgentFeedbackParabolaPoint(FROM, TO, 30, 0.5)).toEqual({ x: (300 + 343) / 2, y: 150 });
    expect(getAgentFeedbackParabolaPoint(FROM, TO, 30, 1)).toEqual(TO);
  });

  it('moves linearly across, rising briefly before it falls fast', () => {
    const points = [0.1, 0.2, 0.3, 0.75, 0.9].map((progress) => getAgentFeedbackParabolaPoint(FROM, TO, 30, progress));

    points.forEach(({ x }, index) => {
      expect(x).toBeCloseTo(300 + 43 * [0.1, 0.2, 0.3, 0.75, 0.9][index], 6);
    });
    expect(points[0].y).toBeLessThan(FROM.y);
    // Telegram's parabola through the three points: y = a x² + b x + c
    const [x1, y1, x2, y2, x3, y3] = [FROM.x, FROM.y, (FROM.x + TO.x) / 2, FROM.y - 30, TO.x, TO.y];
    const denominator = (x1 - x2) * (x1 - x3) * (x2 - x3);
    const a = (x3 * (y2 - y1) + x2 * (y1 - y3) + x1 * (y3 - y2)) / denominator;
    const b = (x1 * x1 * (y2 - y3) + x3 * x3 * (y1 - y2) + x2 * x2 * (y3 - y1)) / denominator;
    const c = (x2 * x2 * (x3 * y1 - x1 * y3) + x2 * (x1 * x1 * y3 - x3 * x3 * y1) + x1 * x3 * (x3 - x1) * y2)
      / denominator;
    points.forEach(({ x, y }) => expect(y).toBeCloseTo(a * x * x + b * x + c, 6));
    // The fall over the last tenth is longer than the whole rise
    expect(TO.y - points[4].y).toBeGreaterThan(FROM.y - Math.min(...points.map(({ y }) => y)));
  });

  it('goes straight between ends nearer than 5 px', () => {
    expect(getAgentFeedbackParabolaPoint({ x: 10, y: 10 }, { x: 14, y: 6 }, 30, 0.5)).toEqual({ x: 12, y: 8 });
  });

  it('rises and falls along a vertical path', () => {
    expect(getAgentFeedbackParabolaPoint({ x: 10, y: 100 }, { x: 10, y: 200 }, 30, 0.5)).toEqual({ x: 10, y: 70 });
  });
});

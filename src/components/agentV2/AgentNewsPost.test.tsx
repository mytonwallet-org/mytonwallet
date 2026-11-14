import React from '../../lib/teact/teact';
import TeactDOM from '../../lib/teact/teact-dom';

import type {
  AgentPublicFollowUpV2, AgentThreadDigestCardV2, AgentThreadNewsCardV2,
} from '../../api/agentV2/protocol/types';
import type { AgentMessage } from '../../global/types';

import AgentNewsBubble from './AgentNewsBubble';
import AgentNewsPost from './AgentNewsPost';

jest.mock('../../hooks/useLang', () => ({
  __esModule: true,
  default: () => Object.assign((key: string, value?: Record<string, string>) => (
    value ? `${key} ${Object.values(value).join(' ')}` : key
  ), { code: 'en' }),
}));
jest.mock('./AgentNewsBubble', () => ({
  __esModule: true,
  default: jest.fn(() => undefined),
}));
const mockOpenMediaViewer = jest.fn();
jest.mock('../../global', () => {
  const actual = jest.requireActual<typeof import('../../global')>('../../global');
  return { ...actual, getActions: () => ({ ...actual.getActions(), openMediaViewer: mockOpenMediaViewer }) };
});
// Every style module maps to the same stub, so its one mock names the post's tailless class
jest.mock('../agent/MessageBubble.module.scss', () => ({ tailless: 'tailless' }));

const NEWS: AgentThreadNewsCardV2 = {
  eventId: 7,
  headline: 'News headline',
  publishedAt: '2026-10-21T09:00:00.000Z',
};
const FOLLOWUPS: AgentPublicFollowUpV2[] = [
  { id: 'followup-1', kind: 'suggested_prompt', text: 'What does it mean?' },
  { id: 'followup-2', kind: 'suggested_prompt', text: 'Should I act?' },
];
const DIGEST: AgentThreadDigestCardV2 = {
  id: 'digest-1',
  windowEnd: '2026-10-21T18:00:00.000Z',
  total: 7,
  top: [{ eventId: 7, headline: 'News headline' }, { eventId: 8, headline: 'Other headline' }],
};
const PLACEHOLDER_SELECTOR = '[data-agent-followup-placeholder]';
const FOLLOWUP_SELECTOR = '[data-agent-followup-id]';

let pendingAnimationFrames = new Map<number, FrameRequestCallback>();
let nextAnimationFrameId = 0;

describe('AgentNewsPost', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    jest.useFakeTimers();
    pendingAnimationFrames = new Map();
    jest.spyOn(window, 'requestAnimationFrame').mockImplementation((callback) => {
      const id = ++nextAnimationFrameId;
      pendingAnimationFrames.set(id, callback);
      return id;
    });
    jest.spyOn(window, 'cancelAnimationFrame').mockImplementation((id) => {
      pendingAnimationFrames.delete(id);
    });
    root = document.createElement('div');
    document.body.appendChild(root);
  });

  afterEach(async () => {
    TeactDOM.render(undefined, root);
    await advance(100);
    root.remove();
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('shows suggestions that come within 1 s with their own entrance and no placeholders', async () => {
    renderPost();
    await advance(500);
    expect(root.querySelector(PLACEHOLDER_SELECTOR)).toBeNull();

    renderPost(FOLLOWUPS);
    await advance(100);
    expect(root.querySelectorAll(FOLLOWUP_SELECTOR)).toHaveLength(2);
    await advance(1000);
    expect(root.querySelector(PLACEHOLDER_SELECTOR)).toBeNull();
  });

  it('shows placeholders once the suggestions have taken 1 s, which the suggestions then replace', async () => {
    renderPost();
    await advance(900);
    expect(root.querySelector(PLACEHOLDER_SELECTOR)).toBeNull();

    await advance(200);
    expect(root.querySelectorAll(PLACEHOLDER_SELECTOR)).toHaveLength(3);

    renderPost(FOLLOWUPS);
    await advance(100);
    expect(root.querySelector(PLACEHOLDER_SELECTOR)).toBeNull();
    expect(root.querySelectorAll(FOLLOWUP_SELECTOR)).toHaveLength(2);
  });

  it('shows no placeholders for a chat that failed to load before 1 s', async () => {
    renderPost(undefined, { hasLoadFailed: true });
    await advance(1500);

    expect(root.querySelector(PLACEHOLDER_SELECTOR)).toBeNull();
  });

  it('counts the 1 s from when the post starts waiting for its suggestions', async () => {
    renderPost(undefined, { shouldShowFollowups: false });
    await advance(1500);

    renderPost();
    await advance(900);
    expect(root.querySelector(PLACEHOLDER_SELECTOR)).toBeNull();

    await advance(200);
    expect(root.querySelectorAll(PLACEHOLDER_SELECTOR)).toHaveLength(3);
  });

  it('keeps the post\'s tail until the placeholders or the suggestions hang from it', async () => {
    renderPost();
    await advance(500);
    expect(getBubbleClassName()).toBeUndefined();

    await advance(600);
    expect(getBubbleClassName()).toBe('tailless');

    renderPost(FOLLOWUPS);
    await advance(100);
    expect(getBubbleClassName()).toBe('tailless');
  });

  it('shows a digest\'s post: its name and time, title, the headlines as on the card, its suggestions', async () => {
    const onOpenDigestNews = jest.fn();
    renderPost(FOLLOWUPS, { digest: DIGEST, onOpenDigestNews });
    await advance(100);

    const bubbleProps = jest.mocked(AgentNewsBubble).mock.calls.at(-1)![0];
    // The headlines are copied one per line
    expect(bubbleProps.news).toEqual({ headline: '$agent_digest_title', body: '• News headline\n• Other headline' });
    expect(bubbleProps.timeDateTime).toBe(DIGEST.windowEnd);
    // A digest has no picture
    expect(bubbleProps.pictureId).toBeUndefined();
    const header = document.createElement('div');
    TeactDOM.render(<div>{bubbleProps.header}</div>, header);
    expect(header.textContent).toBe('News');
    TeactDOM.render(undefined, header);
    // In the page, where the app's click handlers listen
    const content = document.body.appendChild(document.createElement('div'));
    TeactDOM.render(<div>{bubbleProps.content}</div>, content);
    const headlines = content.querySelectorAll<HTMLButtonElement>('[data-agent-news-digest-headline]');
    expect(Array.from(headlines, (headline) => headline.textContent)).toEqual(['News headline', 'Other headline']);
    expect(content.textContent).toContain('$agent_digest_more 5');
    headlines[1].click();
    expect(onOpenDigestNews).toHaveBeenCalledWith(8);
    TeactDOM.render(undefined, content);
    content.remove();
    expect(root.querySelector('[data-agent-digest-post-id="digest-1"]')).not.toBeNull();
    expect(root.querySelector('[data-agent-news-post-key="digest-digest-1"]')).not.toBeNull();
    expect(root.querySelectorAll(FOLLOWUP_SELECTOR)).toHaveLength(2);
  });

  it('opens its picture in the viewer, which shares it in the discussion\'s language, apart from the app\'s', () => {
    TeactDOM.render(
      <AgentNewsPost
        news={{ ...NEWS, imageUrl: 'https://pulse.mytonwallet.org/images/7.jpg' }}
        locale="ru"
        message={{ id: 1, text: NEWS.headline, timestamp: 0, isOutgoing: false, isNewsPost: true }}
        isDisabled={false}
        shouldShowFollowups={false}
      />,
      root,
    );

    jest.mocked(AgentNewsBubble).mock.calls.at(-1)![0].onOpenPicture!();
    const { pictures } = mockOpenMediaViewer.mock.calls[0][0];
    expect(pictures.byId['agent-news-post-7'].news).toMatchObject({ eventId: 7, locale: 'ru' });
  });

  function renderPost(
    followups?: AgentPublicFollowUpV2[],
    {
      hasLoadFailed = false, shouldShowFollowups = true, digest, onOpenDigestNews,
    }: {
      hasLoadFailed?: boolean;
      shouldShowFollowups?: boolean;
      digest?: AgentThreadDigestCardV2;
      onOpenDigestNews?: (eventId: number) => void;
    } = {},
  ) {
    const message: AgentMessage = {
      id: 1, text: NEWS.headline, timestamp: 0, isOutgoing: false, isNewsPost: true, followups,
    };
    TeactDOM.render(
      <AgentNewsPost
        {...(digest ? { digest } : { news: NEWS })}
        message={message}
        isDisabled={false}
        shouldShowFollowups={shouldShowFollowups}
        hasLoadFailed={hasLoadFailed}
        onOpenDigestNews={onOpenDigestNews}
      />,
      root,
    );
  }
});

function getBubbleClassName() {
  return jest.mocked(AgentNewsBubble).mock.calls.at(-1)![0].className;
}

// Runs the timers and the animation frames due within `milliseconds`
async function advance(milliseconds: number) {
  for (let elapsed = 0; elapsed < milliseconds; elapsed += 20) {
    await jest.advanceTimersByTimeAsync(20);
    const callbacks = Array.from(pendingAnimationFrames.values());
    pendingAnimationFrames.clear();
    callbacks.forEach((callback) => callback(elapsed));
    await Promise.resolve();
  }
}

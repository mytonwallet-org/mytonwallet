import { getAdjacentMediaId } from '../mediaViewer/helpers/getAdjacentMediaId';
import { buildAgentNewsPictures, getAgentNewsPictureId } from './agentNewsPictures';

const SOURCES = [{ name: 'Source', url: 'https://example.com/news' }];
const NEWS = [
  {
    eventId: 1,
    headline: 'Oldest',
    time: '2026-10-21T09:00:00.000Z',
    imageUrl: 'https://pulse.mytonwallet.org/images/1.jpg',
  },
  { eventId: 2, headline: 'No picture', time: '2026-10-21T10:00:00.000Z' },
  {
    eventId: 3,
    headline: 'Newest',
    body: 'The **news** body',
    sources: SOURCES,
    time: '2026-10-21T11:00:00.000Z',
    imageUrl: 'https://pulse.mytonwallet.org/images/3.jpg',
  },
];

describe('buildAgentNewsPictures', () => {
  it('pages through the feed\'s pictures in its order, past news without one', () => {
    const pictures = buildAgentNewsPictures(NEWS, 'feed', 'ru');

    expect(pictures.ids).toEqual(['agent-news-feed-1', 'agent-news-feed-3']);
    expect(getAdjacentMediaId(pictures.ids, 'agent-news-feed-1', 1)).toBe('agent-news-feed-3');
    expect(getAdjacentMediaId(pictures.ids, 'agent-news-feed-3', 1)).toBeUndefined();
    // The viewer captions the picture with its news, dated as its card dates it, and shares it in the feed's language
    expect(pictures.byId['agent-news-feed-3']).toEqual({
      url: 'https://pulse.mytonwallet.org/images/3.jpg',
      title: 'Newest',
      news: {
        eventId: 3,
        headline: 'Newest',
        body: 'The **news** body',
        sources: SOURCES,
        timestamp: Date.UTC(2026, 9, 21, 11),
        locale: 'ru',
      },
    });
  });

  it('gives a post\'s picture an id of its own, apart from the same news in the feed', () => {
    const pictures = buildAgentNewsPictures([NEWS[0]], 'post');

    expect(pictures.ids).toEqual([getAgentNewsPictureId('post', 1)]);
    expect(getAgentNewsPictureId('post', 1)).not.toBe(getAgentNewsPictureId('feed', 1));
  });

  it('has nothing to show for news without pictures', () => {
    expect(buildAgentNewsPictures([NEWS[1]], 'feed')).toEqual({ ids: [], byId: {} });
  });
});

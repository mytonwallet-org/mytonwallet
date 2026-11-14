import type { AgentNewsFeedLocaleV2, AgentThreadNewsCardV2 } from '../../api/agentV2/protocol/types';
import type { MediaViewerPictures } from '../../global/types';

/**
 * Where a News picture is shown: a feed card, the post a discussion starts with, or a digest's headline on its card in
 * the feed or in its post, apart for each digest
 */
type AgentNewsPictureSurface = 'feed' | 'post' | `${'feedDigest' | 'postDigest'}-${string}`;

interface AgentNewsWithPicture
  extends Pick<AgentThreadNewsCardV2, 'eventId' | 'headline' | 'body' | 'sources' | 'imageUrl'> {
  /** When the news came, as its card or post dates it */
  time: string;
}

/**
 * The surface of a digest's headline pictures. The digest's id, which can hold any character, is encoded, as the id
 * goes into an attribute selector.
 */
export function getAgentDigestPictureSurface(digestId: string, isPost: boolean): AgentNewsPictureSurface {
  return `${isPost ? 'postDigest' : 'feedDigest'}-${encodeURIComponent(digestId)}`;
}

/** The picture's id in the media viewer, which its `img` carries so the viewer opens from it and closes to it */
export function getAgentNewsPictureId(surface: AgentNewsPictureSurface, eventId: number) {
  return `agent-news-${surface}-${eventId}`;
}

/**
 * The pictures of the news, in their order, for the media viewer to page through, each with its news for the
 * viewer's caption and actions; news without a picture are left out. A feed's or a post's picture is shared in
 * `locale`; a digest's headline, as its digest, is not shared.
 */
export function buildAgentNewsPictures(
  items: AgentNewsWithPicture[],
  surface: AgentNewsPictureSurface,
  locale?: AgentNewsFeedLocaleV2,
): MediaViewerPictures {
  const pictures: MediaViewerPictures = { ids: [], byId: {} };
  const canShare = surface === 'feed' || surface === 'post';
  items.forEach(({
    eventId, headline, body, sources, imageUrl, time,
  }) => {
    if (!imageUrl) return;

    const id = getAgentNewsPictureId(surface, eventId);
    pictures.ids.push(id);
    pictures.byId[id] = {
      url: imageUrl,
      title: headline,
      news: {
        headline, body, sources, timestamp: Date.parse(time), ...(canShare && { eventId, locale }),
      },
    };
  });

  return pictures;
}

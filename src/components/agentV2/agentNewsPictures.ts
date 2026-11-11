import type { AgentThreadNewsCardV2 } from '../../api/agentV2/protocol/types';
import type { MediaViewerPictures } from '../../global/types';

/** Where a News picture is shown: a feed card, or the post a discussion starts with */
type AgentNewsPictureSurface = 'feed' | 'post';

interface AgentNewsWithPicture
  extends Pick<AgentThreadNewsCardV2, 'eventId' | 'headline' | 'body' | 'sources' | 'imageUrl'> {
  /** When the news came, as its card or post dates it */
  time: string;
}

/** The picture's id in the media viewer, which its `img` carries so the viewer opens from it and closes to it */
export function getAgentNewsPictureId(surface: AgentNewsPictureSurface, eventId: number) {
  return `agent-news-${surface}-${eventId}`;
}

/**
 * The pictures of the news, in their order, for the media viewer to page through, each with its news for the
 * viewer's caption and actions; news without a picture are left out
 */
export function buildAgentNewsPictures(
  items: AgentNewsWithPicture[],
  surface: AgentNewsPictureSurface,
): MediaViewerPictures {
  const pictures: MediaViewerPictures = { ids: [], byId: {} };
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
        headline, body, sources, timestamp: Date.parse(time),
      },
    };
  });

  return pictures;
}

import React, { memo, useMemo, useState } from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { AgentNewsDigestHeadlineV2 } from '../../api/agentV2/protocol/types';
import { MediaType } from '../../global/types';

import buildClassName from '../../util/buildClassName';
import { toNativeDigits } from '../../util/nativeDigits';
import { buildAgentNewsPictures, getAgentDigestPictureSurface, getAgentNewsPictureId } from './agentNewsPictures';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AgentNewsIcon from './AgentNewsIcon';

import styles from './AgentNews.module.scss';

interface OwnProps {
  /** Tells the pictures of the digest apart from the same news' pictures in another digest */
  digestId: string;
  headlines: AgentNewsDigestHeadlineV2[];
  /** How many news the digest covers beyond its headlines */
  remainder: number;
  /** When the digest came, as its card or post dates it, which the media viewer tells over its pictures */
  time: string;
  /** In a post's text, under its title, which already stands at the text's inset */
  isInText?: boolean;
  /** The list shows digests only, so the news the digest leaves out are not above it */
  isInDigestsView?: boolean;
  onOpen: (eventId: number) => void;
}

/**
 * A digest's top headlines, as its card in the feed and its post at the top of its discussion show them: each a button
 * with a gray arrow where the "Discuss" strip has its own, opening its news item's discussion, then the news the digest
 * leaves out. A headline leads with its news item's picture, which opens the digest's pictures in the media viewer, or,
 * when another headline has one, with the News mark in its place; without any picture, each leads with a bullet by its
 * first line.
 */
function AgentNewsDigestHeadlines({
  digestId, headlines, remainder, time, isInText = false, isInDigestsView = false, onOpen,
}: OwnProps) {
  const lang = useLang();
  const [failedImageUrls, setFailedImageUrls] = useState<Set<string>>();
  // The card in the feed and the post of the same digest stay on the page together while the discussion is over the feed
  const pictureSurface = getAgentDigestPictureSurface(digestId, isInText);
  const hasPictures = headlines.some(({ imageUrl }) => imageUrl);
  const headlineTextClassName = buildClassName(
    styles.digestHeadlineText, hasPictures && styles.digestHeadlineTextBesidePicture,
  );

  // The viewer pages through the digest's pictures that load, each captioned with its headline alone
  const pictures = useMemo(() => (
    hasPictures
      ? buildAgentNewsPictures(headlines.map(({ eventId, headline, imageUrl }) => ({
        eventId,
        headline,
        imageUrl: imageUrl && !failedImageUrls?.has(imageUrl) ? imageUrl : undefined,
        time,
      })), pictureSurface)
      : undefined
  ), [failedImageUrls, hasPictures, headlines, pictureSurface, time]);

  const handlePictureClick = useLastCallback((e: React.MouseEvent<HTMLImageElement>) => {
    openPicture(e.currentTarget);
  });

  // The picture is a button, which Enter and Space press
  const handlePictureKeyDown = useLastCallback((e: React.KeyboardEvent<HTMLImageElement>) => {
    if (e.key !== 'Enter' && e.key !== ' ') return;

    e.preventDefault();
    openPicture(e.currentTarget);
  });

  // A picture that fails leaves the News mark in its place
  const handlePictureError = useLastCallback((imageUrl: string) => {
    setFailedImageUrls((urls) => new Set(urls).add(imageUrl));
  });

  function openPicture(picture: HTMLImageElement) {
    getActions().openMediaViewer({
      mediaType: MediaType.AgentNews,
      mediaId: picture.dataset.mediaViewerPictureId!,
      pictures: pictures!,
    });
  }

  function renderLead(imageUrl?: string) {
    if (!hasPictures) return <span className={styles.digestBullet} aria-hidden />;

    // A picture loads over its square's fill, which shows the News mark, as the post's "News" line has it, for a
    // headline without one
    const hasPicture = Boolean(imageUrl) && !failedImageUrls?.has(imageUrl);
    return (
      <span className={styles.digestThumbnailPlace} aria-hidden>
        {!hasPicture && <AgentNewsIcon className={styles.postIcon} />}
      </span>
    );
  }

  return (
    <>
      <div className={buildClassName(styles.digestHeadlines, isInText && styles.digestHeadlinesInText)} role="list">
        {headlines.map(({ eventId, headline, imageUrl }) => (
          <div key={eventId} className={styles.digestHeadlineItem} role="listitem">
            <button
              type="button"
              className={buildClassName(styles.digestHeadline, hasPictures && styles.digestHeadlineWithPicture)}
              data-agent-news-digest-headline={eventId}
              onClick={() => onOpen(eventId)}
            >
              {renderLead(imageUrl)}
              <span className={headlineTextClassName}>{headline}</span>
              <svg className={styles.digestHeadlineChevron} viewBox="0 0 24 24" aria-hidden>
                <path d="M9.5 6.5L15 12l-5.5 5.5" />
              </svg>
            </button>
            {/* A button of its own over the row's lead, named by its headline as the post's picture is */}
            {imageUrl && !failedImageUrls?.has(imageUrl) && (
              <img
                className={styles.digestThumbnail}
                src={imageUrl}
                alt=""
                role="button"
                aria-label={headline}
                tabIndex={0}
                loading="lazy"
                decoding="async"
                draggable={false}
                data-media-viewer-picture-id={getAgentNewsPictureId(pictureSurface, eventId)}
                onClick={handlePictureClick}
                onKeyDown={handlePictureKeyDown}
                onError={() => handlePictureError(imageUrl)}
              />
            )}
          </div>
        ))}
      </div>
      {remainder > 0 && (
        <div
          className={buildClassName(
            styles.digestRemainder,
            isInText && styles.digestRemainderInText,
            hasPictures && styles.digestRemainderWithPictures,
          )}
        >
          {lang(
            isInDigestsView ? '$agent_digest_more_count' : '$agent_digest_more',
            { count: toNativeDigits(String(remainder)) },
            undefined,
            remainder,
          )}
        </div>
      )}
    </>
  );
}

export default memo(AgentNewsDigestHeadlines);

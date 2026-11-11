import renderMarkdown from '../../../util/renderMarkdown';

// The answers of a few windows of the message list, which holds up to 60 messages at a time
const CACHE_SIZE = 100;

const htmlByKey = new Map<string, string>();

/**
 * Renders the Markdown of an answer that is no longer written. Such an answer renders the same each time it mounts,
 * as when it scrolls back into the windowed message list or its chat opens again, so the latest results are kept.
 */
export default function renderFinishedMarkdown(text: string, areLinksEnabled: boolean, codeCopyLabel: string) {
  const key = `${Number(areLinksEnabled)}${codeCopyLabel}\n${text}`;
  let html = htmlByKey.get(key);

  if (html === undefined) {
    html = renderMarkdown(text, { areLinksEnabled, codeCopyLabel }).html;
    if (htmlByKey.size >= CACHE_SIZE) {
      htmlByKey.delete(htmlByKey.keys().next().value!);
    }
  } else {
    // The map keeps insertion order, so a result used again moves to the end and leaves last
    htmlByKey.delete(key);
  }

  htmlByKey.set(key, html);

  return html;
}

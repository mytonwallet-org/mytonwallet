import type { AgentNewsFeedItemV2, AgentThreadNewsCardV2 } from '../../../api/agentV2/protocol/types';

import { openUrl } from '../../../util/openUrl';

const NEWS_SOURCE_PROTOCOLS = new Set(['https:', 'http:', 'tg:']);
const MARKDOWN_BOLD_PATTERN = /\*\*/g;
const WWW_PREFIX_PATTERN = /^www\./;

type AgentNewsSources = Pick<AgentNewsFeedItemV2, 'sources'> | Pick<AgentThreadNewsCardV2, 'sources'>;

export function getAgentNewsCopyText(item: { headline: string; body?: string } & AgentNewsSources) {
  const url = item.sources?.[0]?.url;
  return [item.headline, item.body && stripAgentNewsMarkdown(item.body), url].filter(Boolean).join('\n\n');
}

/** The first source, when it is a web or Telegram link the app can open */
export function getAgentNewsSourceUrl(item: AgentNewsSources) {
  const url = item.sources?.[0]?.url;
  if (!url) return undefined;

  try {
    const parsed = new URL(url);
    return NEWS_SOURCE_PROTOCOLS.has(parsed.protocol) && parsed.hostname && !parsed.username && !parsed.password
      ? url
      : undefined;
  } catch {
    return undefined;
  }
}

export function openAgentNewsSource(item: AgentNewsSources) {
  const url = getAgentNewsSourceUrl(item);
  return url ? openUrl(url) : undefined;
}

/** The first source's name, its host when it has none, or the name a card stored before it kept links */
export function getAgentNewsSourceName(news: Pick<AgentThreadNewsCardV2, 'sources' | 'source'>) {
  const source = news.sources?.[0];
  if (!source) return news.source;
  if (source.name) return source.name;

  try {
    return new URL(source.url).hostname.replace(WWW_PREFIX_PATTERN, '') || undefined;
  } catch {
    return undefined;
  }
}

/** News bodies mark emphasis with `**`, which the feed shows as bold and plain text drops */
export function stripAgentNewsMarkdown(text: string) {
  return text.replace(MARKDOWN_BOLD_PATTERN, '').trim();
}

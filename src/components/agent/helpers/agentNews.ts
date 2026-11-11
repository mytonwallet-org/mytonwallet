import type { AgentNewsFeedItemV2, AgentThreadNewsCardV2 } from '../../../api/agentV2/protocol/types';

import { openUrl } from '../../../util/openUrl';

const NEWS_SOURCE_PROTOCOLS = new Set(['https:', 'http:', 'tg:']);
const MARKDOWN_BOLD_PATTERN = /\*\*/g;
const WWW_PREFIX_PATTERN = /^www\./;
const MAX_SHOWN_SOURCES = 3;

type AgentNewsSources = Pick<AgentNewsFeedItemV2, 'sources'> | Pick<AgentThreadNewsCardV2, 'sources'>;

export interface AgentNewsSourceEntry {
  name: string;
  /** The source's link, when the app can open it */
  url?: string;
}

export function getAgentNewsCopyText(item: { headline: string; body?: string } & AgentNewsSources) {
  const url = item.sources?.[0]?.url;
  return [item.headline, item.body && stripAgentNewsMarkdown(item.body), url].filter(Boolean).join('\n\n');
}

/** The first source, when it is a web or Telegram link the app can open */
export function getAgentNewsSourceUrl(item: AgentNewsSources) {
  return getOpenableSourceUrl(item.sources?.[0]?.url);
}

export function openAgentNewsSource(item: AgentNewsSources) {
  const url = getAgentNewsSourceUrl(item);
  return url ? openUrl(url) : undefined;
}

/**
 * The sources a news item names at its foot: the first three distinct ones, each by its name or its site without
 * "www.". A card stored before it kept links names its source alone.
 */
export function getAgentNewsSourceEntries(news: Pick<AgentThreadNewsCardV2, 'sources' | 'source'>) {
  const entries: AgentNewsSourceEntry[] = [];
  const shownNames = new Set<string>();

  for (const { name, url } of news.sources ?? []) {
    if (entries.length === MAX_SHOWN_SOURCES) break;

    const shownName = name?.trim() || getSourceHostName(url);
    if (!shownName || shownNames.has(shownName.toLowerCase())) continue;

    shownNames.add(shownName.toLowerCase());
    const openableUrl = getOpenableSourceUrl(url);
    entries.push(openableUrl ? { name: shownName, url: openableUrl } : { name: shownName });
  }

  const legacyName = news.source?.trim();
  if (!entries.length && legacyName) {
    entries.push({ name: legacyName });
  }

  return entries;
}

/** News bodies mark emphasis with `**`, which the feed shows as bold and plain text drops */
export function stripAgentNewsMarkdown(text: string) {
  return text.replace(MARKDOWN_BOLD_PATTERN, '').trim();
}

function getOpenableSourceUrl(url?: string) {
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

function getSourceHostName(url: string) {
  try {
    return new URL(url).hostname.replace(WWW_PREFIX_PATTERN, '') || undefined;
  } catch {
    return undefined;
  }
}

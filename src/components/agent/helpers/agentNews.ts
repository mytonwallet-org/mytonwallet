import type { AgentNewsFeedItemV2, AgentThreadNewsCardV2 } from '../../../api/agentV2/protocol/types';

const NEWS_SOURCE_PROTOCOLS = new Set(['https:', 'http:', 'tg:']);
const MARKDOWN_BOLD_PATTERN = /\*\*/g;
const WWW_PREFIX_PATTERN = /^www\./;

type AgentNewsSources = Pick<AgentNewsFeedItemV2, 'sources'> | Pick<AgentThreadNewsCardV2, 'sources'>;

/** The headline and the plain body text, without a link: a source's link is in the menu's Sources */
export function getAgentNewsCopyText(item: { headline: string; body?: string }) {
  return [item.headline, item.body && stripAgentNewsMarkdown(item.body)].filter(Boolean).join('\n\n');
}

/** The sources the menu's Sources lists: those the app can open, each once, by its name or its site without "www." */
export function getAgentNewsMenuSources(item: AgentNewsSources) {
  const sources: { name: string; url: string }[] = [];
  const names = new Set<string>();

  for (const { name, url } of item.sources ?? []) {
    const openableUrl = getOpenableSourceUrl(url);
    const shownName = name?.trim() || (openableUrl && new URL(openableUrl).hostname.replace(WWW_PREFIX_PATTERN, ''));
    if (!openableUrl || !shownName || names.has(shownName.toLowerCase())) continue;

    names.add(shownName.toLowerCase());
    sources.push({ name: shownName, url: openableUrl });
  }

  return sources;
}

/** News bodies mark emphasis with `**`, which the feed shows as bold and plain text drops */
export function stripAgentNewsMarkdown(text: string) {
  return text.replace(MARKDOWN_BOLD_PATTERN, '').trim();
}

/** The link, when it is a web or Telegram link the app can open */
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

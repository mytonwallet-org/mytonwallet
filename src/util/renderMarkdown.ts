import { isAgentLinkUrl } from './agent/agentLinkUrl';
import {
  ANSWER_LINK_MARKER_PATTERN,
  decodeMarkerUrl,
  MARKDOWN_ESCAPE_PATTERN,
  removeAnswerLinkMarkers,
  STRAY_ANSWER_LINK_MARKER_PATTERN,
} from './agent/answerLinkMarkers';
import { SELF_PROTOCOL } from './deeplink/constants';

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

interface RenderMarkdownOptions {
  areLinksEnabled: boolean;
}

interface RenderedMarkdown {
  html: string;
}

export function renderDeterministicMarkdownTable(text: string): RenderedMarkdown {
  const lines = text.trim().split('\n');
  if (lines.length < 2) throw new Error('Invalid deterministic Markdown table');
  const rows = lines.map(parseDeterministicTableRow);
  const columnCount = rows[0].length;
  if (columnCount === 0
    || rows.some((row) => row.length !== columnCount)
    || rows[1].some((cell) => !/^:?-{3,}:?$/u.test(cell))) {
    throw new Error('Invalid deterministic Markdown table');
  }
  const header = rows[0].map((cell) => `<th scope="col">${escapeHtml(cell)}</th>`).join('');
  const body = rows.slice(2).map((row) => (
    `<tr>${row.map((cell) => `<td>${escapeHtml(cell)}</td>`).join('')}</tr>`
  )).join('');
  return {
    html: `<table><thead><tr>${header}</tr></thead><tbody>${body}</tbody></table>`,
  };
}

function parseDeterministicTableRow(row: string) {
  if (!row.startsWith('|') || !row.endsWith('|')) {
    throw new Error('Invalid deterministic Markdown table');
  }
  const cells: string[] = [];
  let cell = '';
  let escaped = false;
  for (const character of row.slice(1, -1)) {
    if (escaped) {
      cell += character;
      escaped = false;
    } else if (character === '\\') {
      escaped = true;
    } else if (character === '|') {
      cells.push(cell.trim());
      cell = '';
    } else {
      cell += character;
    }
  }
  if (escaped) cell += '\\';
  cells.push(cell.trim());
  return cells;
}

export default function renderMarkdown(
  text: string,
  { areLinksEnabled }: RenderMarkdownOptions,
): RenderedMarkdown {
  const trailingInlineWhitespace = text.match(/[^\S\r\n]+$/u)?.[0] ?? '';
  const codeBlocks: string[] = [];
  const withCodePlaceholders = text.replace(
    /^```([A-Za-z0-9_+-]*)[^\S\r\n]*\n([\s\S]*?)(?:^```\s*$|(?![\s\S]))/gmu,
    (_match, language: string, code: string) => {
      const index = codeBlocks.length;
      const literalCode = removeAnswerLinkMarkers(code.trimEnd());
      codeBlocks.push(`<pre data-language="${escapeHtml(language)}"><code>${escapeHtml(literalCode)}</code></pre>`);
      return `\n%%AGENT_CODE_BLOCK_${index}%%\n`;
    },
  );
  const lines = withCodePlaceholders.replace(/\r\n/gu, '\n').split('\n');
  const html: string[] = [];
  let paragraphLines: string[] = [];

  const flushParagraph = () => {
    if (paragraphLines.length === 0) return;
    html.push(`<p>${renderAgentV2Inline(paragraphLines.join(' '), areLinksEnabled)}</p>`);
    paragraphLines = [];
  };

  for (let index = 0; index < lines.length;) {
    const line = lines[index];
    const trimmed = line.trim();
    if (!trimmed) {
      flushParagraph();
      index += 1;
      continue;
    }

    const codeBlock = /^%%AGENT_CODE_BLOCK_(\d+)%%$/u.exec(trimmed);
    if (codeBlock) {
      flushParagraph();
      html.push(codeBlocks[Number(codeBlock[1])] ?? `<p>${escapeHtml(trimmed)}</p>`);
      index += 1;
      continue;
    }

    const table = parseAgentV2Table(lines, index);
    if (table) {
      flushParagraph();
      html.push(renderAgentV2Table(table, areLinksEnabled));
      index = table.endIndex;
      continue;
    }

    const unordered = /^[-+*]\s+(\S[\s\S]*)$/u.exec(line);
    const ordered = /^(\d+)[.)]\s+(\S[\s\S]*)$/u.exec(line);
    if (unordered || ordered) {
      flushParagraph();
      const tag = unordered ? 'ul' : 'ol';
      const items: string[] = [];
      while (index < lines.length) {
        const candidate = lines[index];
        const match = tag === 'ul'
          ? /^[-+*]\s+(\S[\s\S]*)$/u.exec(candidate)
          : /^(\d+)[.)]\s+(\S[\s\S]*)$/u.exec(candidate);
        if (!match) break;
        const content = tag === 'ul' ? match[1] : match[2];
        items.push(`<li>${renderAgentV2Inline(content, areLinksEnabled)}</li>`);
        index += 1;
      }
      // A list keeps its first number, so an answer that begins "24. …" does not show "1."
      const start = ordered ? Number(ordered[1]) : 1;
      const startAttribute = Number.isSafeInteger(start) && start !== 1 ? ` start="${start}"` : '';
      html.push(`<${tag}${startAttribute}>${items.join('')}</${tag}>`);
      continue;
    }

    paragraphLines.push(trimmed);
    index += 1;
  }
  flushParagraph();

  return { html: html.join('') + escapeHtml(trailingInlineWhitespace) };
}

interface AgentV2Table {
  header: string[];
  rows: string[][];
  endIndex: number;
}

function parseAgentV2Table(lines: string[], startIndex: number): AgentV2Table | undefined {
  const header = parseAgentV2TableRow(lines[startIndex]);
  const separator = parseAgentV2TableRow(lines[startIndex + 1]);
  if (!header || !separator || header.length !== separator.length
    || !separator.every((cell) => /^:?-{3,}:?$/u.test(cell))) {
    return undefined;
  }

  const rows: string[][] = [];
  let index = startIndex + 2;
  while (index < lines.length) {
    const row = parseAgentV2TableRow(lines[index]);
    if (!row || row.length !== header.length) break;
    rows.push(row);
    index += 1;
  }
  if (rows.length === 0) return undefined;

  return { header, rows, endIndex: index };
}

function parseAgentV2TableRow(line: string | undefined): string[] | undefined {
  const row = line?.trim();
  if (!row?.startsWith('|') || !row.endsWith('|')) return undefined;

  const cells: string[] = [];
  let cell = '';
  let escaped = false;
  for (const character of row.slice(1, -1)) {
    if (escaped) {
      cell += character;
      escaped = false;
    } else if (character === '\\') {
      cell += character;
      escaped = true;
    } else if (character === '|') {
      cells.push(cell.trim());
      cell = '';
    } else {
      cell += character;
    }
  }
  if (escaped) cell += '\\';
  cells.push(cell.trim());
  return cells;
}

function renderAgentV2Table(table: AgentV2Table, areLinksEnabled: boolean): string {
  const header = table.header
    .map((cell) => `<th scope="col">${renderAgentV2Inline(cell, areLinksEnabled)}</th>`)
    .join('');
  const body = table.rows.map((row) => (
    `<tr>${row.map((cell) => `<td>${renderAgentV2Inline(cell, areLinksEnabled)}</td>`).join('')}</tr>`
  )).join('');
  return `<table><thead><tr>${header}</tr></thead><tbody>${body}</tbody></table>`;
}

function renderAgentV2Inline(text: string, areLinksEnabled: boolean): string {
  let tokenPrefix = '%%AGENT_INLINE_';
  while (text.includes(tokenPrefix)) tokenPrefix += '_';
  const escapedPattern = new RegExp(`${tokenPrefix}ESCAPED_(\\d+)%%`, 'gu');
  const contentPattern = new RegExp(`${tokenPrefix}CONTENT_(\\d+)%%`, 'gu');
  const escapedCharacters: string[] = [];
  const protectedContent: string[] = [];
  const processed = text
    .replace(MARKDOWN_ESCAPE_PATTERN, (_match, character: string) => {
      escapedCharacters.push(character);
      return `${tokenPrefix}ESCAPED_${escapedCharacters.length - 1}%%`;
    })
    .replace(/`([^`\n]+)`/gu, (_match, code: string) => {
      const literalCode = code.replace(escapedPattern, (_token, index: string) => escapedCharacters[Number(index)]);
      protectedContent.push(`<code>${escapeHtml(removeAnswerLinkMarkers(literalCode))}</code>`);
      return `${tokenPrefix}CONTENT_${protectedContent.length - 1}%%`;
    })
    .replace(
      /(?<!!)\[([^\]\n]+)\]\(((?:https?:\/\/|mtw:\/\/)(?:[^()\s]|\([^()\s]*\))+)\)/gu,
      (match, label: string, destination: string) => {
        const url = destination.replace(escapedPattern, (_token, index: string) => escapedCharacters[Number(index)]);
        if (url.startsWith(SELF_PROTOCOL)) return label;
        if (!areLinksEnabled) return `${label} (${destination})`;
        if (!label.trim() || url.includes(tokenPrefix) || !isAgentLinkUrl(url)) return match;
        protectedContent.push(renderLink(url, label));
        return `${tokenPrefix}CONTENT_${protectedContent.length - 1}%%`;
      },
    )
    // Answer links the server sent apart from the text (`markAnswerLinks`)
    .replace(ANSWER_LINK_MARKER_PATTERN, (_match, encodedUrl: string, label: string) => {
      const url = decodeMarkerUrl(encodedUrl);
      if (!url || !label.trim()) return label;
      protectedContent.push(areLinksEnabled ? renderLink(url, label) : `${formatInline(label)} (${escapeHtml(url)})`);
      return `${tokenPrefix}CONTENT_${protectedContent.length - 1}%%`;
    })
    .replace(STRAY_ANSWER_LINK_MARKER_PATTERN, '');

  return formatInline(processed);

  function renderLink(url: string, label: string) {
    return `<a href="${escapeHtml(url)}" target="_blank" rel="noopener noreferrer">${formatInline(label)}</a>`;
  }

  function formatInline(value: string) {
    return escapeHtml(value)
      .replace(/\*\*(\S(?:[^*\n]|\*(?!\*))*?)\*\*/gu, '<strong>$1</strong>')
      .replace(/(^|[^\w*])\*(\S(?:[^*\n]|\*(?!\*))*?)\*(?!\*)/gu, '$1<em>$2</em>')
      .replace(escapedPattern, (_match, index: string) => escapeHtml(escapedCharacters[Number(index)]))
      .replace(contentPattern, (_match, index: string) => protectedContent[Number(index)]);
  }
}

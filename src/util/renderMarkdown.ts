function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export interface ActionButton {
  label: string;
  url: string;
}

export default function renderMarkdown(text: string): { html: string; buttons: ActionButton[] } {
  const buttons: ActionButton[] = [];

  // Extract mtw:// action links before escaping
  let processed = text.replace(
    /\[([^\]]+)\]\((mtw:\/\/[^)]+)\)/g,
    (_match, label: string, url: string) => {
      buttons.push({ label, url });
      return '';
    },
  );

  // Convert [label](https://...) to placeholder before escaping
  const links: { label: string; url: string }[] = [];
  processed = processed.replace(
    /\[([^\]]+)\]\((https?:\/\/[^)]+)\)/g,
    (_match, label: string, url: string) => {
      links.push({ label, url });
      return `%%LINK_${links.length - 1}%%`;
    },
  );

  // Escape HTML to prevent XSS
  let html = escapeHtml(processed);

  // Code blocks (``` ... ```)
  html = html.replace(/```(\w*)\n([\s\S]*?)```/g, (_match, _lang, code) => {
    return `<pre><code>${code.trimEnd()}</code></pre>`;
  });

  // Inline code
  html = html.replace(/`([^`\n]+)`/g, '<code>$1</code>');

  // Bold
  html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');

  // Italic
  html = html.replace(/\*(.+?)\*/g, '<em>$1</em>');

  // Headings → bold
  html = html.replace(/^#{1,6} (.+)$/gm, '<strong>$1</strong>');

  // Unordered lists — convert items, collapse blank lines between them, then wrap
  html = html.replace(/^- (.+)$/gm, '<ul-li>$1</ul-li>');
  html = html.replace(/((?:<ul-li>.*<\/ul-li>\n?)(?:\n*<ul-li>.*<\/ul-li>\n?)*)/g, (block) => {
    const items = block.match(/<ul-li>.*<\/ul-li>/g)!;
    return `<ul>${items.map((item) => item.replace(/<\/?ul-li>/g, (tag) => tag.replace('ul-li', 'li'))).join('')}</ul>`;
  });

  // Ordered lists
  html = html.replace(/^\d+\. (.+)$/gm, '<ol-li>$1</ol-li>');
  html = html.replace(/((?:<ol-li>.*<\/ol-li>\n?)(?:\n*<ol-li>.*<\/ol-li>\n?)*)/g, (block) => {
    const items = block.match(/<ol-li>.*<\/ol-li>/g)!;
    return `<ol>${items.map((item) => item.replace(/<\/?ol-li>/g, (tag) => tag.replace('ol-li', 'li'))).join('')}</ol>`;
  });

  // Tables
  html = html.replace(
    /((?:^\|.+\|$\n?)+)/gm,
    (tableBlock) => {
      const rows = tableBlock.trim().split('\n');
      const headerRow = rows[0];
      const isSeparator = (row: string) => /^\|[\s:|-]+\|$/.test(row);
      const hasSeparator = rows.length > 1 && isSeparator(rows[1]);
      const dataRows = hasSeparator ? rows.slice(2) : rows.slice(1);

      const parseCells = (row: string) => row.split('|').slice(1, -1).map((c) => c.trim());

      let result = '<table>';
      if (hasSeparator) {
        result += `<thead><tr>${parseCells(headerRow).map((c) => `<th>${c}</th>`).join('')}</tr></thead>`;
      } else {
        dataRows.unshift(headerRow);
      }
      result += '<tbody>';
      for (const row of dataRows) {
        result += `<tr>${parseCells(row).map((c) => `<td>${c}</td>`).join('')}</tr>`;
      }
      result += '</tbody></table>';
      return result;
    },
  );

  // Restore placeholders inside code blocks to original escaped text (not clickable links)
  html = html.replace(/<code>([\s\S]*?)<\/code>/g, (codeBlock) => {
    return codeBlock.replace(/%%LINK_(\d+)%%/g, (_m, index: string) => {
      const link = links[Number(index)];
      return link ? `[${escapeHtml(link.label)}](${escapeHtml(link.url)})` : '';
    });
  });

  // Restore markdown links (after all structural transforms to prevent XSS via list/table injection)
  html = html.replace(/%%LINK_(\d+)%%/g, (_match, index: string) => {
    const link = links[Number(index)];
    return link
      ? `<a href="${escapeHtml(link.url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(link.label)}</a>`
      : '';
  });
  // Safety-net: remove any surviving placeholders
  html = html.replace(/%%LINK_\d+%%/g, '');

  // Auto-link bare URLs (skip those already inside <a> tags)
  html = html.replace(
    /(?:<a\b[^>]*>.*?<\/a>)|(?:href="[^"]*")|(https:\/\/[^\s<]+)/g,
    (match, url?: string) => {
      if (!url) return match;
      return `<a href="${url}" target="_blank" rel="noopener noreferrer">${url}</a>`;
    },
  );

  // Wrap remaining text lines into paragraphs
  html = html
    .split('\n')
    .map((line) => {
      const trimmed = line.trim();
      if (!trimmed) return '';
      if (/^<(pre|ul|ol|table)/.test(trimmed)) return trimmed;
      if (/<\/(pre|ul|ol|table)>$/.test(trimmed)) return trimmed;
      return `<p>${trimmed}</p>`;
    })
    .join('');

  return { html, buttons };
}

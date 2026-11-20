/** Plain text only; callers must use text nodes, never innerHTML or SVG markup. */
export function giftLabel(value: unknown, max = 120): string {
  if (!Number.isInteger(max) || max < 1 || max > 512) throw Error('Invalid label limit');
  if (typeof value !== 'string' || value.length > 4096) return 'Unnamed gift';
  return [...value.normalize('NFC').replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]/g,'')].slice(0,max).join('').trim() || 'Unnamed gift';
}
/** URL filtering only. Rendering must use a wallet image proxy with redirect/MIME/size controls.
 * The experimental trading screens do not load remote NFT images at all. */
export function giftImageUrl(value: unknown, origins: readonly string[]): string | null {
  if (typeof value !== 'string' || value.length > 2048 || !Array.isArray(origins) || origins.length > 16) return null;
  try {
    const u = new URL(value);
    if (u.protocol !== 'https:' || u.username || u.password || u.port || !origins.includes(u.origin)
      || !/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(u.hostname) || /(^|\.)localhost$|\.local$|\.internal$/i.test(u.hostname)
      || u.search || u.hash || /\.svg$/i.test(u.pathname)) return null;
    return u.href;
  } catch { return null; }
}
/** Bound structure before processing untrusted JSON. JSON.parse alone does not limit depth. */
export function boundedJson(text: string): unknown {
  if (typeof text !== 'string' || text.length > 1048576) throw Error('JSON budget exceeded');
  const value: unknown = JSON.parse(text), stack: [unknown,number][] = [[value,0]]; let count = 0;
  while (stack.length) {
    const [item,depth] = stack.pop()!;
    if (++count > 30000 || depth > 24) throw Error('JSON structure budget exceeded');
    if (item && typeof item === 'object') {
      const entries = Object.entries(item);
      if (entries.length > 5000) throw Error('JSON container budget exceeded');
      for (const [key,child] of entries) {
        if (['__proto__','prototype','constructor'].includes(key)) throw Error('Unsafe JSON property');
        stack.push([child,depth+1]);
      }
    }
  }
  rejectDuplicateJsonKeys(text);
  return value;
}

// JSON.parse has already validated the grammar. Scan the original property names
// because the parsed object retains only the final occurrence of each name.
function rejectDuplicateJsonKeys(text: string): void {
  const containers: (Set<string> | null)[] = [];
  for (let index = 0; index < text.length; index++) {
    const char = text[index];
    if (char === '{' || char === '[') {
      if (containers.length >= 25) throw Error('JSON structure budget exceeded');
      containers.push(char === '{' ? new Set() : null);
    } else if (char === '}' || char === ']') containers.pop();
    else if (char === '"') {
      const start = index++;
      while (text[index] !== '"') {
        if (text[index] === '\\') index++;
        index++;
      }
      const keys = containers.at(-1);
      if (!keys) continue;
      let next = index + 1;
      while (/^[ \t\r\n]$/.test(text[next] ?? '')) next++;
      if (text[next] !== ':') continue;
      const key: string = JSON.parse(text.slice(start, index + 1));
      if (keys.has(key)) throw Error('Duplicate JSON property');
      keys.add(key);
    }
  }
}

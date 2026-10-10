import { load } from 'js-yaml';
import fs from 'node:fs';
import path from 'node:path';

const SEMANTIC_KEYS = [
  '$agent_hint_capabilities_title',
  '$agent_hint_portfolio_title',
  'Send',
  'Asset',
  '$agent_error_generic',
  '$agent_notice_content_over_budget',
  '$agent_notice_web_search_no_results',
  'Network',
  'Enter Amount',
  'Recipient',
  'Insufficient Balance',
  '$agent_error_update_required',
  '$agent_error_conversation_updated',
] as const;

describe('Agent V2 semantic locale catalogs', () => {
  const english = readCatalog('en');
  const russian = readCatalog('ru');
  const persian = readCatalog('fa');

  it('defines the complete semantic fallback catalog in English', () => {
    SEMANTIC_KEYS.forEach((key) => expect(english[key]).toEqual(expect.any(String)));
  });

  it.each(['en', 'ru', 'uk', 'de', 'es', 'pl', 'tr', 'ar', 'fa', 'it', 'th', 'zh-Hans', 'zh-Hant'])(
    'keeps a generic request failure distinct from an input label in %s', (locale) => {
      const catalog = readCatalog(locale);
      expect(catalog.$agent_error_generic)
        .not.toBe(catalog.Asset);
    },
  );

  it('ships native Russian semantic copy', () => {
    expect(russian.$agent_hint_capabilities_title).toBe('Что ты умеешь?');
    SEMANTIC_KEYS.forEach((key) => {
      expect(russian[key]).toEqual(expect.any(String));
      if (key.startsWith('$agent_')) expect(russian[key]).not.toBe(english[key]);
    });
  });

  it('ships native Persian semantic copy', () => {
    SEMANTIC_KEYS.forEach((key) => expect(persian[key]).toEqual(expect.any(String)));
  });

  it('does not keep frontend-owned answer or follow-up copy', () => {
    [english, russian, persian].forEach((catalog) => {
      expect(Object.keys(catalog).some((key) => /^\$agent_(followup|semantic|portfolio)_/.test(key))).toBe(false);
    });
  });
});

function readCatalog(locale: string): Record<string, string> {
  const filename = path.join(process.cwd(), 'src', 'i18n', `${locale}.yaml`);
  return load(fs.readFileSync(filename, 'utf8')) as Record<string, string>;
}

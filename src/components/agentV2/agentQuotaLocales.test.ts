import { load } from 'js-yaml';
import fs from 'node:fs';
import path from 'node:path';

const LOCALES = [
  'ar',
  'de',
  'en',
  'es',
  'fa',
  'it',
  'pl',
  'ru',
  'th',
  'tr',
  'uk',
  'zh-Hans',
  'zh-Hant',
] as const;

const QUOTA_KEYS = [
  '$agent_capacity_limit_title',
  '$agent_capacity_limit_known',
  '$agent_capacity_degraded_title',
  '$agent_capacity_limit_unknown',
  '$agent_response_failed_title',
  '$agent_response_interrupted_title',
  '$agent_retry_request',
  '$agent_rate_limit_title',
  '$agent_rate_limit_body',
  '$agent_user_quota_meter',
  '$agent_user_quota_reset',
  '$agent_user_quota_exhausted_title',
  '$agent_user_quota_exhausted_body',
] as const;

describe('Agent quota locale catalogs', () => {
  const catalogs = new Map(LOCALES.map((locale) => [locale, readCatalog(locale)]));
  const english = catalogs.get('en')!;

  it.each(LOCALES)('contains complete quota copy for %s', (locale) => {
    const catalog = catalogs.get(locale)!;
    QUOTA_KEYS.forEach((key) => {
      expect(typeof catalog[key]).toBe('string');
      expect(catalog[key].trim().length).toBeGreaterThan(0);
    });
    if (locale !== 'en') {
      expect(catalog.$agent_capacity_limit_title).not.toBe(english.$agent_capacity_limit_title);
      expect(catalog.$agent_capacity_limit_known).not.toBe(english.$agent_capacity_limit_known);
      expect(catalog.$agent_capacity_degraded_title).not.toBe(english.$agent_capacity_degraded_title);
      expect(catalog.$agent_capacity_limit_unknown).not.toBe(english.$agent_capacity_limit_unknown);
      expect(catalog.$agent_rate_limit_title).not.toBe(english.$agent_rate_limit_title);
      expect(catalog.$agent_user_quota_exhausted_title).not.toBe(english.$agent_user_quota_exhausted_title);
    }
  });

  it.each(LOCALES)('preserves Agent limit placeholders for %s', (locale) => {
    const catalog = catalogs.get(locale)!;
    expect(catalog.$agent_capacity_limit_known).toEqual(expect.stringContaining('%duration%'));
    expect(catalog.$agent_user_quota_meter).toEqual(expect.stringContaining('%remaining%'));
    expect(catalog.$agent_user_quota_meter).toEqual(expect.stringContaining('%limit%'));
    expect(catalog.$agent_user_quota_reset).toEqual(expect.stringContaining('%duration%'));
    expect(catalog.$agent_user_quota_exhausted_body).toEqual(expect.stringContaining('%limit%'));
    expect(catalog.$agent_user_quota_exhausted_body).toEqual(expect.stringContaining('%duration%'));
  });

  it('describes partial quota insufficiency in units', () => {
    expect(english.$agent_user_quota_meter).toContain('units');
    expect(english.$agent_user_quota_exhausted_title).toBe('Not enough Agent quota');
    expect(english.$agent_user_quota_exhausted_body).toContain('enough quota for this request');
    expect(english.$agent_user_quota_exhausted_body).not.toContain('used all');
  });

  it('distinguishes failed responses from current Agent availability', () => {
    expect(english.$agent_response_failed_title).toBe('Couldn’t get a response');
    expect(english.$agent_response_interrupted_title).toBe('Response interrupted');
    expect(english.$agent_retry_request).toBe('Retry request');
    expect(english.$agent_capacity_limit_title).toBe('Agent is temporarily unavailable');
    expect(english.$agent_capacity_limit_known).toBe('New requests will be available in %duration%.');
    expect(english.$agent_capacity_degraded_title).toBe('Agent may be unstable');
    expect(english.$agent_capacity_limit_unknown)
      .toBe('You can try again, but the response may not load.');

    const russian = catalogs.get('ru')!;
    expect(russian.$agent_response_failed_title).toBe('Не удалось получить ответ');
    expect(russian.$agent_response_interrupted_title).toBe('Ответ прерван');
    expect(russian.$agent_retry_request).toBe('Повторить запрос');
    expect(russian.$agent_capacity_limit_title).toBe('Агент временно недоступен');
    expect(russian.$agent_capacity_limit_known)
      .toBe('Новые запросы можно будет отправить через %duration%.');
    expect(russian.$agent_capacity_degraded_title).toBe('Агент может отвечать нестабильно');
    expect(russian.$agent_capacity_limit_unknown)
      .toBe('Можно попробовать ещё раз, но ответ может не загрузиться.');
  });
});

function readCatalog(locale: string): Record<string, string> {
  const filename = path.join(process.cwd(), 'src', 'i18n', `${locale}.yaml`);
  return load(fs.readFileSync(filename, 'utf8')) as Record<string, string>;
}

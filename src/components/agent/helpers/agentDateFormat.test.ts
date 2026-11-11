import type { LangCode } from '../../../global/types';
import type { LangFn } from '../../../util/langProvider';

import { setNativeDigitsLang } from '../../../util/nativeDigits';
import {
  formatAgentDay, formatAgentDayWithTime, formatAgentListTime, formatAgentTime, getAgentDaysAgo,
} from './agentDateFormat';

// Saturday, November 7, 2026, in the local time zone like the chat itself
const NOW = new Date(2026, 10, 7, 15, 0).getTime();
const TODAY_MORNING = new Date(2026, 10, 7, 9, 5).getTime();
const TODAY_EVENING = new Date(2026, 10, 7, 21, 30).getTime();
const LAST_NIGHT = new Date(2026, 10, 6, 23, 57).getTime();
const SIX_DAYS_AGO = new Date(2026, 10, 1, 9, 0).getTime();
const A_WEEK_AGO = new Date(2026, 9, 31, 9, 0).getTime();
const THIS_NOVEMBER_5 = new Date(2026, 10, 5, 9, 0).getTime();
const LAST_NOVEMBER_7 = new Date(2025, 10, 7, 9, 0).getTime();
const TOMORROW_MORNING = new Date(2026, 10, 8, 9, 5).getTime();
const JANUARY_2 = new Date(2027, 0, 2, 15, 0).getTime();
const DECEMBER_30 = new Date(2026, 11, 30, 9, 0).getTime();
// The space between the time and AM or PM, which is narrow in newer versions of the locale data
const AM_PM_SPACE = '[\\s\\u202F]';

describe('agentDateFormat', () => {
  afterEach(() => {
    setNativeDigitsLang(undefined);
  });

  it('writes the time in 24 or 12 hours as the language does', () => {
    expect(formatAgentTime('ru', TODAY_MORNING)).toBe('09:05');
    expect(formatAgentTime('de', TODAY_EVENING)).toBe('21:30');
    expect(formatAgentTime('en', TODAY_MORNING)).toMatch(new RegExp(`^9:05${AM_PM_SPACE}AM$`));
    expect(formatAgentTime('en', TODAY_EVENING)).toMatch(new RegExp(`^9:30${AM_PM_SPACE}PM$`));
  });

  it('writes the time in the app\'s digits', () => {
    setNativeDigitsLang('fa');

    expect(formatAgentTime('fa', TODAY_MORNING)).toBe('۰۹:۰۵');
  });

  it('names a chat\'s day "Today", "Yesterday", by its date, and by its year too in another year', () => {
    expect(formatAgentDay(buildLang('ru'), TODAY_MORNING, NOW)).toBe('Today');
    expect(formatAgentDay(buildLang('ru'), LAST_NIGHT, NOW)).toBe('Yesterday');
    expect(formatAgentDay(buildLang('ru'), THIS_NOVEMBER_5, NOW)).toBe('5 ноября');
    expect(formatAgentDay(buildLang('ru'), LAST_NOVEMBER_7, NOW)).toBe('7 ноября 2025');
    expect(formatAgentDay(buildLang('uk'), LAST_NOVEMBER_7, NOW)).toBe('7 листопада 2025');
    expect(formatAgentDay(buildLang('en'), THIS_NOVEMBER_5, NOW)).toBe('November 5');
    expect(formatAgentDay(buildLang('en'), LAST_NOVEMBER_7, NOW)).toBe('November 7, 2025');
    expect(formatAgentDay(buildLang('zh-Hans'), LAST_NOVEMBER_7, NOW)).toBe('2025年11月7日');
  });

  it('names a day later than now "Today", as a clock running ahead may stamp it', () => {
    expect(formatAgentDay(buildLang('ru'), TOMORROW_MORNING, NOW)).toBe('Today');
  });

  it('shows a chat list row\'s time today, its weekday within the week, its day this year and its date before', () => {
    const ru = buildLang('ru');
    expect(formatAgentListTime(ru, TODAY_MORNING, NOW)).toBe('09:05');
    expect(formatAgentListTime(ru, LAST_NIGHT, NOW)).toBe('пт');
    expect(formatAgentListTime(ru, SIX_DAYS_AGO, NOW)).toBe('вс');
    expect(formatAgentListTime(ru, A_WEEK_AGO, NOW)).toBe('31 окт');
    expect(formatAgentListTime(ru, LAST_NOVEMBER_7, NOW)).toBe('07.11.25');

    const en = buildLang('en');
    expect(formatAgentListTime(en, TODAY_MORNING, NOW)).toMatch(new RegExp(`^9:05${AM_PM_SPACE}AM$`));
    expect(formatAgentListTime(en, LAST_NIGHT, NOW)).toBe('Fri');
    expect(formatAgentListTime(en, A_WEEK_AGO, NOW)).toBe('Oct 31');
    expect(formatAgentListTime(en, LAST_NOVEMBER_7, NOW)).toBe('11/07/25');
  });

  it('turns a chat list row\'s day at midnight', () => {
    const midnight = new Date(2026, 10, 7, 0, 0).getTime();

    expect(formatAgentListTime(buildLang('ru'), midnight, midnight + 1)).toBe('00:00');
    expect(formatAgentListTime(buildLang('ru'), midnight - 1, midnight)).toBe('пт');
    expect(getAgentDaysAgo(midnight - 1, midnight)).toBe(1);
    expect(getAgentDaysAgo(midnight, midnight + 1)).toBe(0);
  });

  it('shows a chat list row\'s weekday within the week across the year boundary', () => {
    expect(formatAgentListTime(buildLang('ru'), DECEMBER_30, JANUARY_2)).toBe('ср');
  });

  it('shows only the time for a future chat list timestamp', () => {
    expect(formatAgentListTime(buildLang('ru'), TOMORROW_MORNING, NOW)).toBe('09:05');
  });

  it('cuts every Russian month to three letters', () => {
    const ru = buildLang('ru');
    expect(formatAgentListTime(ru, new Date(2026, 8, 4, 9, 0).getTime(), NOW)).toBe('4 сен');
    expect(formatAgentListTime(ru, new Date(2026, 1, 4, 9, 0).getTime(), NOW)).toBe('4 фев');
    expect(formatAgentListTime(ru, new Date(2026, 4, 4, 9, 0).getTime(), NOW)).toBe('4 мая');
    expect(formatAgentDayWithTime('ru', new Date(2026, 10, 2, 15, 38).getTime(), NOW)).toBe('2 ноя, 15:38');
  });

  it('keeps the inner dots of a month abbreviated with several', () => {
    expect(formatAgentListTime(buildLang('th'), A_WEEK_AGO, NOW)).toBe('31 ต.ค.');
  });

  it('drops a single trailing dot from an abbreviated month', () => {
    expect(formatAgentListTime(buildLang('de'), A_WEEK_AGO, NOW)).toBe('31. Okt');
    expect(formatAgentDayWithTime('fr', A_WEEK_AGO, NOW)).toBe('31 oct, 09:00');
  });

  it('writes a day with its time, and with its year in another year', () => {
    const july20 = new Date(2026, 6, 20, 15, 38).getTime();
    const lastJuly20 = new Date(2025, 6, 20, 15, 38).getTime();

    expect(formatAgentDayWithTime('ru', july20, NOW)).toBe('20 июл, 15:38');
    expect(formatAgentDayWithTime('ru', lastJuly20, NOW)).toBe('20 июл 2025, 15:38');
    expect(formatAgentDayWithTime('en', july20, NOW)).toMatch(new RegExp(`^Jul 20, 3:38${AM_PM_SPACE}PM$`));
  });
});

function buildLang(code: LangCode) {
  return Object.assign((key: string) => key, { code }) as LangFn;
}

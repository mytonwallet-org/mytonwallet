import type { LangFn } from '../../../util/langProvider';

import { DAY } from '../../../util/dateFormat';
import { toNativeDigits } from '../../../util/nativeDigits';

const WEEK_DAYS = 7;
// A month abbreviated with a single dot at its end, as "июл." and "Okt.", but not "ต.ค."
const MONTH_DOT_PATTERN = /^([^.]+)\.$/;
// Russian abbreviates every month to three letters, as Telegram does: "7 ноя", "4 сен"
const RUSSIAN_SHORT_MONTHS = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
// The abbreviated word after a year, as " г." in "2025 г." and " р." in "2025 р.", but not "年"
const YEAR_WORD_PATTERN = /^\s\p{L}+\./u;
const DAY_OPTIONS: Intl.DateTimeFormatOptions = { month: 'long', day: 'numeric' };
const DAY_WITH_YEAR_OPTIONS: Intl.DateTimeFormatOptions = { year: 'numeric', month: 'long', day: 'numeric' };
const WEEKDAY_OPTIONS: Intl.DateTimeFormatOptions = { weekday: 'short' };
const SHORT_DAY_OPTIONS: Intl.DateTimeFormatOptions = { month: 'short', day: 'numeric' };
const NUMERIC_DAY_OPTIONS: Intl.DateTimeFormatOptions = { year: '2-digit', month: '2-digit', day: '2-digit' };

const formatters = new Map<string, Intl.DateTimeFormat>();

/**
 * The time of day in 24 or 12 hours, as the language writes it: "09:41" in Russian, "9:41 AM" in English. Times on
 * mobile follow the system's setting, which a web page cannot read, so the language stands for it.
 */
export function formatAgentTime(langCode: string, timestamp: number | string) {
  return formatAgentDate(langCode, timestamp, getTimeOptions(langCode));
}

/**
 * The day a chat's date line names: "Today", "Yesterday", "November 7", or "November 7, 2025" for another year,
 * without a weekday
 */
export function formatAgentDay(lang: LangFn, timestamp: number | string, now = Date.now()) {
  const daysAgo = getAgentDaysAgo(timestamp, now);
  // A time later than now, as a server clock running ahead stamps it, is today's, as on mobile
  if (daysAgo <= 0) return lang('Today');
  if (daysAgo === 1) return lang('Yesterday');

  const isThisYear = new Date(timestamp).getFullYear() === new Date(now).getFullYear();
  return formatAgentDate(lang.code ?? 'en', timestamp, isThisYear ? DAY_OPTIONS : DAY_WITH_YEAR_OPTIONS);
}

/**
 * The time of a chat list row: the time today, the short weekday within the last week ("Mon"), the day and the short
 * month this year ("Nov 7") and the numeric date before that ("11/07/25", "07.11.25")
 */
export function formatAgentListTime(lang: LangFn, timestamp: number | string, now = Date.now()) {
  const langCode = lang.code ?? 'en';
  const daysAgo = getAgentDaysAgo(timestamp, now);
  if (daysAgo <= 0) return formatAgentTime(langCode, timestamp);
  if (daysAgo < WEEK_DAYS) return formatAgentDate(langCode, timestamp, WEEKDAY_OPTIONS);

  const isThisYear = new Date(timestamp).getFullYear() === new Date(now).getFullYear();
  return formatAgentDate(langCode, timestamp, isThisYear ? SHORT_DAY_OPTIONS : NUMERIC_DAY_OPTIONS);
}

/** The short day with the time, as "Jul 20, 3:38 PM" or "20 июл, 15:38", and with the year for another year */
export function formatAgentDayWithTime(langCode: string, timestamp: number | string, now = Date.now()) {
  const isThisYear = new Date(timestamp).getFullYear() === new Date(now).getFullYear();
  return formatAgentDate(langCode, timestamp, {
    ...SHORT_DAY_OPTIONS,
    year: isThisYear ? undefined : 'numeric',
    ...getTimeOptions(langCode),
  });
}

/** How many days on the local calendar lie between the day of `timestamp` and today */
export function getAgentDaysAgo(timestamp: number | string, now: number) {
  return getDayOrdinal(now) - getDayOrdinal(new Date(timestamp).getTime());
}

/**
 * Formats as the language does, in the app's digits. An abbreviated month loses its trailing dot ("20 июл", and
 * Russian's three letters stand for "нояб." and "сент.") and a year its abbreviated word ("7 ноября 2025"), as Telegram
 * writes dates.
 */
function formatAgentDate(langCode: string, timestamp: number | string, options: Intl.DateTimeFormatOptions) {
  const date = new Date(timestamp);
  const parts = getFormatter(langCode, options).formatToParts(date);
  const isRussian = langCode.split('-')[0] === 'ru';

  return toNativeDigits(parts.map(({ type, value }, index) => {
    if (type === 'month' && options.month === 'short') {
      return isRussian ? RUSSIAN_SHORT_MONTHS[date.getMonth()] : value.replace(MONTH_DOT_PATTERN, '$1');
    }
    if (type === 'literal' && parts[index - 1]?.type === 'year') return value.replace(YEAR_WORD_PATTERN, '');

    return value;
  }).join(''));
}

// The hour has two digits in 24 hours and one or two in 12, as the language writes it
function getTimeOptions(langCode: string): Intl.DateTimeFormatOptions {
  const { hourCycle } = getFormatter(langCode, { hour: 'numeric' }).resolvedOptions();
  const isTwelveHour = hourCycle === 'h12' || hourCycle === 'h11';
  return {
    hour: isTwelveHour ? 'numeric' : '2-digit',
    minute: '2-digit',
    hourCycle: isTwelveHour ? hourCycle : 'h23',
  };
}

// Latin digits, which `toNativeDigits` turns into the app's own
function getFormatter(langCode: string, options: Intl.DateTimeFormatOptions) {
  const key = `${langCode}:${JSON.stringify(options)}`;
  let formatter = formatters.get(key);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat(langCode, { ...options, numberingSystem: 'latn' });
    formatters.set(key, formatter);
  }

  return formatter;
}

// Counts days on the local calendar, which a daylight saving change cannot shift
function getDayOrdinal(time: number) {
  const date = new Date(time);
  return Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / DAY;
}

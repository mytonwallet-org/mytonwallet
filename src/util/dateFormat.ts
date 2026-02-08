import type { LangCode } from '../global/types';
import type { LangFn } from './langProvider';

import withCache from './withCache';

export const SECOND = 1000;
export const MINUTE = SECOND * 60;
export const HOUR = MINUTE * 60;
export const DAY = HOUR * 24;
export const YEAR = 365 * DAY;

const formatDayToStringWithCache = withCache((
  langCode: LangCode,
  dayStartAt: number,
  noYear?: boolean,
  monthFormat: 'short' | 'long' | 'numeric' | false = 'short',
  noDay?: boolean,
  withTime = false,
) => {
  return new Date(dayStartAt).toLocaleString(
    langCode,
    {
      year: noYear ? undefined : 'numeric',
      month: monthFormat || undefined,
      day: noDay ? undefined : 'numeric',
      hour: withTime ? 'numeric' : undefined,
      minute: withTime ? 'numeric' : undefined,
      hourCycle: 'h23',
    },
  );
});

export function formatRelativeHumanDateTime(
  langCode: LangCode = 'en',
  time: number,
) {
  const total = time - Date.now();
  const minutes = Math.floor((total / 1000 / 60) % 60);
  const hours = Math.floor((total / (1000 * 3600)) % 24);
  const days = Math.floor(total / 1000 / 3600 / 24);

  const rtf = new Intl.RelativeTimeFormat(langCode, {
    localeMatcher: 'best fit',
    numeric: 'always',
    style: 'long',
  });

  const result: string[] = [];

  if (days > 0) {
    const [daysPlural, daysValue] = rtf.formatToParts(days, 'day').reverse();
    result.push(`${daysValue.value}${daysPlural.value}`.replace(' ', '\u00A0'));
  }
  if (hours > 0) {
    const [hoursPlural, hoursValue] = rtf.formatToParts(hours, 'hour').reverse();
    result.push(`${hoursValue.value}${hoursPlural.value}`.replace(' ', '\u00A0'));
  }
  if (minutes > 0) {
    const [minutesPlural, minutesValue] = rtf.formatToParts(minutes, 'minute').reverse();
    result.push(`${minutesValue.value}${minutesPlural.value}`.replace(' ', '\u00A0'));
  }

  return result.join(' ');
}

export function formatHumanDay(lang: LangFn, datetime: string | number) {
  if (isToday(datetime)) {
    return lang('Today');
  }

  if (isYesterday(datetime)) {
    return lang('Yesterday');
  }

  return formatFullDay(lang.code!, datetime);
}

export function formatFullDay(langCode: LangCode, datetime: string | number | Date) {
  const date = new Date(datetime);
  const dayStartAt = getDayStartAt(date);
  const today = getDayStart(new Date());
  const noYear = date.getFullYear() === today.getFullYear();

  return formatDayToStringWithCache(langCode, dayStartAt, noYear, 'long');
}

export function formatShortDay(langCode: LangCode, datetime: string | number | Date, withTime = false, noYear = false) {
  const date = new Date(datetime);
  const dayStartAt = getDayStartAt(date);
  const today = getDayStart(new Date());
  const todayStartAt = getDayStartAt(today);
  const noDate = withTime && dayStartAt === todayStartAt;
  const targetAt = withTime ? getMinuteStart(date).getTime() : dayStartAt;

  noYear ||= date.getFullYear() === today.getFullYear();

  return formatDayToStringWithCache(langCode, targetAt, noYear, !noDate && 'short', noDate, withTime);
}

export function formatTime(datetime: string | number) {
  const date = new Date(datetime);

  return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
}

export function getCountDaysToDate(datetime: string | number | Date) {
  const today = new Date();
  const date = datetime instanceof Date ? datetime
    : new Date(datetime);

  return Math.ceil((date.getTime() - today.getTime()) / DAY);
}

export function getDayStart(datetime: number | Date) {
  const date = new Date(datetime);
  date.setHours(0, 0, 0, 0);
  return date;
}

export function getDayStartAt(datetime: number | Date) {
  return getDayStart(datetime).getTime();
}

export function getMinuteStart(datetime: number | Date) {
  const date = new Date(datetime);
  date.setSeconds(0, 0);
  return date;
}

function isToday(datetime: string | number) {
  return getDayStartAt(new Date()) === getDayStartAt(new Date(datetime));
}

function isYesterday(datetime: string | number) {
  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);

  return getDayStartAt(yesterday) === getDayStartAt(new Date(datetime));
}

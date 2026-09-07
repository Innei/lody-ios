import { currentLocale, t, tp } from '../i18n/index.ts';

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

export function relativeTime(value: string | number, now = Date.now()) {
  const parsed = typeof value === 'number' ? value : Date.parse(value);
  if (Number.isNaN(parsed)) return '';
  const elapsed = now - parsed;
  if (elapsed < MINUTE) return t('time.justNow');
  if (elapsed < HOUR) {
    const count = Math.floor(elapsed / MINUTE);
    return tp('time.minutesAgo', count, { count });
  }

  const date = new Date(parsed);
  const startOfToday = new Date(now);
  startOfToday.setHours(0, 0, 0, 0);
  if (parsed >= startOfToday.getTime()) {
    const count = Math.floor(elapsed / HOUR);
    return tp('time.hoursAgo', count, { count });
  }
  if (parsed >= startOfToday.getTime() - DAY) return t('time.yesterday');

  return date.toLocaleDateString(currentLocale(), {
    month: 'short',
    day: 'numeric',
  });
}

export function activityBucket(value: string | number, now = Date.now()) {
  const parsed = typeof value === 'number' ? value : Date.parse(value);
  const startOfToday = new Date(now);
  startOfToday.setHours(0, 0, 0, 0);
  const today = startOfToday.getTime();
  if (Number.isNaN(parsed) || parsed >= today) return 'today';
  if (parsed >= today - DAY) return 'yesterday';
  if (parsed >= today - 7 * DAY) return 'week';
  if (parsed >= today - 30 * DAY) return 'month';
  return 'older';
}

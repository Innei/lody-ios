const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

export function relativeTime(value: string | number, now = Date.now()) {
  const parsed = typeof value === 'number' ? value : Date.parse(value);
  if (Number.isNaN(parsed)) return '';
  const elapsed = now - parsed;
  if (elapsed < MINUTE) return '刚刚';
  if (elapsed < HOUR) return `${Math.floor(elapsed / MINUTE)} 分钟前`;

  const date = new Date(parsed);
  const startOfToday = new Date(now);
  startOfToday.setHours(0, 0, 0, 0);
  if (parsed >= startOfToday.getTime())
    return `${Math.floor(elapsed / HOUR)} 小时前`;
  if (parsed >= startOfToday.getTime() - DAY) return '昨天';

  return date.toLocaleDateString('zh-CN', { month: 'short', day: 'numeric' });
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

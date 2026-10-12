import type { ScheduleRule, ScheduleTrigger } from '../models/schedules.ts';

const formatters = new Map<string, Intl.DateTimeFormat>();
function formatter(timeZone: string) {
  let value = formatters.get(timeZone);
  if (!value) {
    value = new Intl.DateTimeFormat('en-US', {
      timeZone,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
    formatters.set(timeZone, value);
  }
  return value;
}
const parts = (ms: number, zone: string) =>
  Object.fromEntries(
    formatter(zone)
      .formatToParts(ms)
      .map((part) => [part.type, Number(part.value)]),
  );
export function instantToZonedLocalInput(ms: number, zone: string): string {
  const p = parts(ms, zone),
    pad = (n: number) => String(n).padStart(2, '0');
  return `${p.year}-${pad(p.month)}-${pad(p.day)}T${pad(p.hour)}:${pad(p.minute)}`;
}
// Match the upstream one-off picker: gaps move forward; folds choose the first instant.
export function zonedLocalInputToInstant(
  value: string,
  zone: string,
): number | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(value);
  if (!match) return null;
  const [year, month, day, hour, minute] = match.slice(1).map(Number);
  const utc = Date.UTC(year, month - 1, day, hour, minute);
  const date = new Date(utc);
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day ||
    hour > 23 ||
    minute > 59
  )
    return null;
  const offset = (ms: number) => {
    const p = parts(ms, zone);
    return (
      Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) - ms
    );
  };
  const candidates = [
    ...new Set([
      utc - offset(utc - 86_400_000),
      utc - offset(utc + 86_400_000),
    ]),
  ].sort((a, b) => a - b);
  return (
    candidates.find((ms) => instantToZonedLocalInput(ms, zone) === value) ??
    candidates.at(-1)!
  );
}

const months = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];
const weekdays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
function fieldValues(
  field: string,
  min: number,
  max: number,
  names: string[] = [],
) {
  const number = (token: string) => {
    const named = names.indexOf(token.toUpperCase());
    const value = named >= 0 ? named + min : Number(token);
    if (
      (!/^\d+$/.test(token) && named < 0) ||
      !Number.isInteger(value) ||
      value < min ||
      value > max
    )
      throw new Error('schedule_invalid_time');
    return value;
  };
  const found = new Set<number>();
  for (const entry of field.split(',')) {
    const [range, stepText, extra] = entry.split('/');
    if (extra !== undefined || !range) throw new Error('schedule_invalid_time');
    const step = stepText === undefined ? 1 : Number(stepText);
    if (
      !Number.isInteger(step) ||
      step < 1 ||
      (stepText !== undefined && !/^\d+$/.test(stepText))
    )
      throw new Error('schedule_invalid_time');
    const bounds = range.split('-');
    if (bounds.length > 2) throw new Error('schedule_invalid_time');
    const from = range === '*' ? min : number(bounds[0]);
    let to = from;
    if (range === '*') to = max;
    else if (bounds.length === 2) to = number(bounds[1]);
    else if (stepText !== undefined) to = max;
    if (from > to) throw new Error('schedule_invalid_time');
    for (let value = from; value <= to; value += step) found.add(value);
  }
  return [...found].sort((a, b) => a - b);
}
function cronFields(expression: string) {
  const fields = expression.trim().split(/\s+/);
  if (fields.length !== 5) throw new Error('schedule_invalid_time');
  const [minute, hour, day, month, weekday] = fields;
  return {
    minute: fieldValues(minute, 0, 59),
    hour: fieldValues(hour, 0, 23),
    day: fieldValues(day, 1, 31),
    month: fieldValues(month, 1, 12, months),
    weekday: fieldValues(weekday, 0, 7, weekdays).map((value) => value % 7),
    dayAny: day === '*',
    weekdayAny: weekday === '*',
  };
}
export function validateScheduleTrigger(
  trigger: ScheduleTrigger,
): ScheduleTrigger {
  if (!trigger || typeof trigger !== 'object')
    throw new Error('schedule_invalid_time');
  const instant = (value: string) => {
    if (
      typeof value !== 'string' ||
      value.length > 100 ||
      !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)$/.test(
        value,
      ) ||
      !Number.isFinite(Date.parse(value))
    )
      throw new Error('schedule_invalid_time');
    return new Date(value).toISOString();
  };
  switch (trigger.kind) {
    case 'manual':
      return { kind: 'manual' };
    case 'once':
      return { kind: 'once', at: instant(trigger.at) };
    case 'interval':
      if (!Number.isInteger(trigger.everyMs) || trigger.everyMs < 60_000)
        throw new Error('schedule_invalid_time');
      return {
        kind: 'interval',
        everyMs: trigger.everyMs,
        anchorAt: instant(trigger.anchorAt),
      };
    case 'cron':
      if (
        typeof trigger.expression !== 'string' ||
        trigger.expression.length > 256 ||
        typeof trigger.timeZone !== 'string' ||
        !trigger.timeZone ||
        trigger.timeZone.length > 100
      )
        throw new Error('schedule_invalid_time');
      cronFields(trigger.expression);
      formatter(trigger.timeZone);
      return {
        kind: 'cron',
        expression: trigger.expression.trim(),
        timeZone: trigger.timeZone,
      };
    default:
      throw new Error('schedule_invalid_time');
  }
}
export function ruleToTrigger(
  rule: ScheduleRule,
  now: number,
  timeZone: string,
): ScheduleTrigger {
  switch (rule.kind) {
    case 'manual':
      return { kind: 'manual' };
    case 'once':
      return validateScheduleTrigger({ kind: 'once', at: rule.at });
    case 'minutes':
    case 'hours': {
      if (!Number.isInteger(rule.every) || rule.every < 1)
        throw new Error('schedule_invalid_time');
      const minutes = rule.kind === 'minutes';
      const divides = (minutes ? 60 : 24) % rule.every === 0;
      if (!divides)
        return validateScheduleTrigger({
          kind: 'interval',
          everyMs: rule.every * (minutes ? 60_000 : 3_600_000),
          anchorAt: new Date(now).toISOString(),
        });
      return validateScheduleTrigger({
        kind: 'cron',
        expression: minutes
          ? `*/${rule.every} * * * *`
          : `0 */${rule.every} * * *`,
        timeZone,
      });
    }
    default: {
      if (
        !Number.isInteger(rule.hour) ||
        rule.hour < 0 ||
        rule.hour > 23 ||
        !Number.isInteger(rule.minute) ||
        rule.minute < 0 ||
        rule.minute > 59
      )
        throw new Error('schedule_invalid_time');
      let day = '*',
        weekday = '*';
      if (rule.kind === 'weekdays') weekday = '1-5';
      if (rule.kind === 'weekly') {
        if (
          !rule.weekdays.length ||
          rule.weekdays.some((v) => !Number.isInteger(v) || v < 0 || v > 6)
        )
          throw new Error('schedule_invalid_time');
        weekday = [...new Set(rule.weekdays)].sort((a, b) => a - b).join(',');
      }
      if (rule.kind === 'monthly') {
        if (
          !rule.days.length ||
          rule.days.some((v) => !Number.isInteger(v) || v < 1 || v > 31)
        )
          throw new Error('schedule_invalid_time');
        day = [...new Set(rule.days)].sort((a, b) => a - b).join(',');
      }
      return validateScheduleTrigger({
        kind: 'cron',
        expression: `${rule.minute} ${rule.hour} ${day} * ${weekday}`,
        timeZone: rule.timeZone ?? timeZone,
      });
    }
  }
}
export function triggerToRule(
  trigger: ScheduleTrigger,
  timeZone: string,
): ScheduleRule | null {
  if (trigger.kind === 'manual' || trigger.kind === 'once') return trigger;
  if (trigger.kind === 'interval') {
    if (trigger.everyMs % 3_600_000 === 0)
      return { kind: 'hours', every: trigger.everyMs / 3_600_000 };
    if (trigger.everyMs % 60_000 === 0)
      return { kind: 'minutes', every: trigger.everyMs / 60_000 };
    return null;
  }
  const [minute, hour, day, month, weekday] = trigger.expression.split(/\s+/);
  if (month !== '*') return null;
  if (
    /^\*\/\d+$/.test(minute) &&
    hour === '*' &&
    day === '*' &&
    weekday === '*'
  )
    return { kind: 'minutes', every: Number(minute.slice(2)) };
  if (
    minute === '0' &&
    /^\*\/\d+$/.test(hour) &&
    day === '*' &&
    weekday === '*'
  )
    return { kind: 'hours', every: Number(hour.slice(2)) };
  if (!/^\d{1,2}$/.test(minute) || !/^\d{1,2}$/.test(hour)) return null;
  const time = {
    hour: Number(hour),
    minute: Number(minute),
    timeZone: trigger.timeZone || timeZone,
  };
  if (day === '*') {
    if (weekday === '*') return { kind: 'daily', ...time };
    if (weekday.includes('/')) return null;
    const selected = [
      ...new Set(fieldValues(weekday, 0, 7, weekdays).map((v) => v % 7)),
    ].sort((a, b) => a - b);
    if (selected.join(',') === '1,2,3,4,5')
      return { kind: 'weekdays', ...time };
    if (selected.length === 7) return { kind: 'daily', ...time };
    return { kind: 'weekly', weekdays: selected, ...time };
  }
  if (weekday !== '*' || day.includes('/')) return null;
  return { kind: 'monthly', days: fieldValues(day, 1, 31), ...time };
}
export function nextScheduleSlot(
  trigger: ScheduleTrigger,
  activeFrom: number,
  after: number,
): number | undefined {
  const lower = Math.max(activeFrom, after + 1);
  if (trigger.kind === 'manual') return undefined;
  if (trigger.kind === 'once') {
    const at = Date.parse(trigger.at);
    return at >= lower ? at : undefined;
  }
  if (trigger.kind === 'interval') {
    const anchor = Date.parse(trigger.anchorAt);
    return (
      anchor +
      Math.max(0, Math.ceil((lower - anchor) / trigger.everyMs)) *
        trigger.everyMs
    );
  }
  const fields = cronFields(trigger.expression),
    today = parts(lower, trigger.timeZone);
  const start = Date.UTC(today.year, today.month - 1, today.day);
  // Five-field calendars repeat within eight years; impossible dates have no slot.
  for (let days = 0; days < 366 * 8; days++) {
    const date = new Date(start + days * 86_400_000),
      day = date.getUTCDate(),
      weekday = date.getUTCDay();
    if (!fields.month.includes(date.getUTCMonth() + 1)) continue;
    const dom = fields.day.includes(day),
      dow = fields.weekday.includes(weekday);
    const matches =
      fields.dayAny || fields.weekdayAny ? dom && dow : dom || dow;
    if (!matches) continue;
    const prefix = date.toISOString().slice(0, 10);
    for (const hour of fields.hour)
      for (const minute of fields.minute) {
        const wall = `${prefix}T${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
        const candidate = zonedLocalInputToInstant(wall, trigger.timeZone)!;
        // Cron skips a DST gap and dispatches only the first instant in a fold.
        if (
          candidate >= lower &&
          instantToZonedLocalInput(candidate, trigger.timeZone) === wall
        )
          return candidate;
      }
  }
  return undefined;
}
export function previewSchedule(
  trigger: ScheduleTrigger,
  activeFrom: number,
  now: number,
  count = 3,
): number[] {
  if (!Number.isInteger(count) || count < 0 || count > 100)
    throw new Error('schedule_invalid_time');
  const result: number[] = [];
  let after = now;
  for (let i = 0; i < count; i++) {
    const next = nextScheduleSlot(trigger, activeFrom, after);
    if (next === undefined) break;
    result.push(next);
    after = next;
  }
  return result;
}
